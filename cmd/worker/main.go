// Comando worker: ejecuta el trabajo pesado (antimalware, HLS, correo,
// insignias). Tiene dos modos, segun QUEUE_BACKEND:
//
//   - asynq (local, Entrega 3): se SUSCRIBE a la cola de Redis y busca
//     trabajos. Se escala con `docker compose up --scale worker=3`; asynq
//     reparte los trabajos entre las instancias.
//   - pubsub (Entrega 4, Cloud Run): expone un servidor HTTP que RECIBE cada
//     mensaje de una suscripcion push de Pub/Sub. Cloud Run escala por esas
//     solicitudes entrantes. No hay scheduler: Pub/Sub ya reentrega los
//     mensajes no confirmados, asi que el reaper periodico de asynq no aplica
//     (ver internal/tasks/reap.go).
//
// En ambos modos los handlers son los mismos (internal/tasks): solo cambia
// como llega el trabajo. Ninguna instancia guarda estado propio: leen de
// Postgres y del almacenamiento.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hibiken/asynq"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"mooc-platform/internal/audit"
	"mooc-platform/internal/config"
	"mooc-platform/internal/database"
	"mooc-platform/internal/mailer"
	"mooc-platform/internal/pubsubpush"
	"mooc-platform/internal/queue"
	"mooc-platform/internal/storage"
	"mooc-platform/internal/tasks"
	"mooc-platform/internal/telemetry"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("[worker] ")

	cfg := config.Load()
	log.Printf("iniciando: %s backend=%s", cfg.Describe(), cfg.QueueBackend)

	// Trazas OpenTelemetry para el worker: cada trabajo abre su propio span y
	// las consultas SQL cuelgan de el. Apagado si no hay endpoint configurado.
	shutdownTracing, err := telemetry.Init(context.Background(), "mooc-worker", cfg.OTelEndpoint, cfg.OTelSampleRatio)
	if err != nil {
		log.Printf("telemetria: %v (se continua sin trazas)", err)
		shutdownTracing = func(context.Context) error { return nil }
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = shutdownTracing(ctx)
	}()

	db, err := database.OpenPostgres(cfg.DatabaseURL, cfg.DBMaxOpenConns, cfg.DBMaxIdleConns)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer db.Close()

	store, err := storage.New(storage.Config{
		Endpoint:       cfg.S3Endpoint,
		PublicEndpoint: cfg.S3PublicEndpoint,
		AccessKey:      cfg.S3AccessKey,
		SecretKey:      cfg.S3SecretKey,
		Bucket:         cfg.S3Bucket,
		Region:         cfg.S3Region,
		UseSSL:         cfg.S3UseSSL,
	})
	if err != nil {
		log.Fatalf("almacenamiento: %v", err)
	}

	// El worker tambien publica trabajos derivados (scan -> transcode,
	// badge -> email), asi que necesita un Publisher del mismo backend.
	q, err := queue.NewPublisher(context.Background(), cfg)
	if err != nil {
		log.Fatalf("cola: %v", err)
	}
	defer q.Close()

	deps := &tasks.Deps{
		Cfg:    cfg,
		DB:     db,
		Store:  store,
		Queue:  q,
		Mailer: mailer.New(cfg.SMTPAddr, cfg.SMTPFrom),
		Audit:  audit.New(db),
	}

	if cfg.QueueBackend == "pubsub" {
		runPubSub(cfg, deps)
		return
	}
	runAsynq(cfg, deps)
}

// runPubSub arranca el servidor HTTP que recibe las entregas push de Pub/Sub.
// Cloud Run enruta el trafico al puerto que escucha aqui.
func runPubSub(cfg config.Config, deps *tasks.Deps) {
	srv, err := pubsubpush.New(context.Background(), deps, cfg.PushAudience, cfg.PushSAEmail)
	if err != nil {
		log.Fatalf("pubsub push: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/pubsub/", srv.Handler())
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	httpSrv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		log.Printf("worker push escuchando en %s (POST /pubsub/push)", cfg.HTTPAddr)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("servidor http: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Println("apagando: se esperan los push en curso...")
	ctx, cancel := context.WithTimeout(context.Background(), cfg.WorkerShutdownTimeout)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
	log.Println("adios")
}

// runAsynq arranca el consumidor de la cola de Redis (modo local / Entrega 3).
func runAsynq(cfg config.Config, deps *tasks.Deps) {
	// Prometheus tambien raspa al worker: sin esto no habria forma de ver
	// cuantos trabajos se procesan ni cuantos caen en la DLQ.
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"ok"}`))
		})
		log.Println("metricas del worker en :9100/metrics")
		if err := http.ListenAndServe(":9100", mux); err != nil {
			log.Printf("servidor de metricas: %v", err)
		}
	}()

	redisOpt := asynq.RedisClientOpt{Addr: cfg.RedisAddr, Password: cfg.RedisPassword}

	srv := asynq.NewServer(redisOpt, asynq.Config{
		Concurrency: cfg.WorkerConcurrency,
		// Pesos de las colas: por cada 6 trabajos criticos se atienden 3
		// normales y 1 de baja prioridad. Asi un correo de verificacion no
		// espera detras de una transcodificacion de dos horas.
		Queues: map[string]int{
			queue.QueueCritical: 6,
			queue.QueueDefault:  3,
			queue.QueueLow:      1,
		},
		// Al retirar la VM, los trabajos activos tienen este tiempo para
		// terminar; despues asynq los devuelve a la cola sin gastar un
		// reintento. Debe ser menor que stop_grace_period del compose.
		ShutdownTimeout: cfg.WorkerShutdownTimeout,
	})

	mux := asynq.NewServeMux()
	deps.Register(mux)

	// Scheduler: encola el mantenimiento periodico. Aunque haya varias
	// replicas del worker, asynq garantiza que la tarea programada se encole
	// una sola vez por periodo. Solo existe en modo asynq.
	scheduler := asynq.NewScheduler(redisOpt, nil)
	if _, err := scheduler.Register("@every 5m",
		asynq.NewTask(queue.TaskReapStale, nil), asynq.Queue(queue.QueueLow)); err != nil {
		log.Fatalf("scheduler: %v", err)
	}
	go func() {
		if err := scheduler.Run(); err != nil {
			log.Printf("scheduler: %v", err)
		}
	}()

	go func() {
		log.Printf("consumiendo la cola (concurrencia=%d)", cfg.WorkerConcurrency)
		if err := srv.Run(mux); err != nil {
			log.Fatalf("asynq: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("apagando: se esperan los trabajos en curso...")
	scheduler.Shutdown()
	srv.Shutdown() // deja terminar lo que ya empezo
	log.Println("adios")
}
