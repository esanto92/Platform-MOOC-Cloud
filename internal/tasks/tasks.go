// Package tasks contiene los handlers que ejecutan los workers.
//
// Un worker es un proceso APARTE de la API. No atiende HTTP: se suscribe a la
// cola, toma trabajos y los ejecuta. Se puede escalar solo (docker compose up
// --scale worker=3) sin tocar la API, porque la cola reparte el trabajo entre
// todos los consumidores.
//
// IDEMPOTENCIA EN DOS CAPAS:
//
//	Capa 1 (Redis/asynq): la opcion TaskID rechaza encolar dos veces la misma
//	   llave mientras el trabajo existe.
//	Capa 2 (Postgres): la tabla processed_jobs registra el trabajo terminado.
//	   Esta capa es la que importa de verdad, porque Redis puede perder
//	   estado y Postgres no. Si la cola reentrega un trabajo ya hecho, el
//	   worker lo detecta aqui y no repite el efecto.
//
// Ademas, cada handler comprueba el ESTADO del dominio antes de actuar (por
// ejemplo, que el asset siga en 'uploaded'). Esa es la defensa mas robusta:
// no depende de ningun registro auxiliar.
package tasks

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/hibiken/asynq"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"mooc-platform/internal/audit"
	"mooc-platform/internal/config"
	"mooc-platform/internal/mailer"
	"mooc-platform/internal/metrics"
	"mooc-platform/internal/queue"
	"mooc-platform/internal/storage"
)

// tracer emite los spans de los trabajos del worker. Cada job es la raiz de su
// propia traza (la entrega de la cola es asincrona: la API ya respondio), y las
// consultas SQL que haga el handler cuelgan de ese span.
var tracer = otel.Tracer("mooc-worker")

type Deps struct {
	Cfg    config.Config
	DB     *sql.DB
	Store  *storage.Storage
	Queue  queue.Publisher
	Mailer *mailer.Mailer
	Audit  *audit.Logger
}

// errSkipRetry marca un error que NO debe reintentarse: el trabajo no va a
// mejorar repitiendolo (payload corrupto, asset inexistente, estado invalido).
// Es agnostico de la cola; el adaptador de asynq lo traduce a asynq.SkipRetry
// y el consumidor de Pub/Sub lo trata como ack (2xx) en vez de reentrega.
var errSkipRetry = errors.New("no reintentar")

// IsSkipRetry indica si un error del Dispatch marca "no reintentar". El
// consumidor de Pub/Sub lo usa para responder 2xx (ack) en vez de 5xx.
func IsSkipRetry(err error) bool { return errors.Is(err, errSkipRetry) }

// Handler es la firma de un handler de tarea desacoplada de la cola: recibe el
// contexto y el payload crudo del mensaje. La misma funcion sirve para asynq
// (local) y para la suscripcion push de Pub/Sub (nube), porque ninguna de las
// dos aparece en la firma.
type Handler func(context.Context, []byte) error

// Dispatch enruta un payload al handler de su tipo. Lo usa el consumidor de
// Pub/Sub: Pub/Sub entrega el tipo en un atributo del mensaje y el cuerpo en
// Data. Devuelve un error si el tipo no tiene handler registrado.
func (d *Deps) Dispatch(ctx context.Context, taskType string, payload []byte) error {
	h, ok := d.handlers()[taskType]
	if !ok {
		return fmt.Errorf("tipo de tarea desconocido: %s", taskType)
	}
	return h(ctx, payload)
}

// handlers mapea cada tipo de tarea a su handler instrumentado. Es la unica
// fuente de verdad del enrutamiento; Register (asynq) y Dispatch (Pub/Sub) la
// comparten para no duplicar la lista.
func (d *Deps) handlers() map[string]Handler {
	return map[string]Handler{
		queue.TaskSendEmail:    d.instrument(queue.TaskSendEmail, d.HandleSendEmail),
		queue.TaskScanAsset:    d.instrument(queue.TaskScanAsset, d.HandleScanAsset),
		queue.TaskTranscodeHLS: d.instrument(queue.TaskTranscodeHLS, d.HandleTranscode),
		queue.TaskIssueBadge:   d.instrument(queue.TaskIssueBadge, d.HandleIssueBadge),
		queue.TaskReapStale:    d.instrument(queue.TaskReapStale, d.HandleReapStale),
	}
}

// Register conecta cada tipo de tarea con su handler en el mux de asynq
// (modo local). El cierre adapta el *asynq.Task al Handler desacoplado:
// extrae el payload crudo, que es lo unico que los handlers usan de la tarea.
func (d *Deps) Register(mux *asynq.ServeMux) {
	for taskType, h := range d.handlers() {
		h := h
		mux.HandleFunc(taskType, func(ctx context.Context, t *asynq.Task) error {
			err := h(ctx, t.Payload())
			// Traduce el sentinel agnostico al de asynq para que no reintente.
			if errors.Is(err, errSkipRetry) {
				return fmt.Errorf("%w: %w", err, asynq.SkipRetry)
			}
			return err
		})
	}
}

// instrument envuelve cada handler para medir duracion y resultado sin
// repetir el mismo codigo en los cinco handlers.
func (d *Deps) instrument(name string, fn Handler) Handler {
	return func(ctx context.Context, payload []byte) error {
		ctx, span := tracer.Start(ctx, "job "+name)
		span.SetAttributes(
			attribute.String("messaging.destination", name),
		)
		if id, ok := asynq.GetTaskID(ctx); ok {
			span.SetAttributes(attribute.String("messaging.message.id", id))
		}

		start := time.Now()
		err := fn(ctx, payload)
		metrics.JobDuration.WithLabelValues(name).Observe(time.Since(start).Seconds())

		status := "success"
		if err != nil {
			status = "retry"
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
		}
		metrics.JobsProcessed.WithLabelValues(name, status).Inc()
		span.SetAttributes(attribute.String("job.status", status))
		span.End()

		if err != nil {
			log.Printf("worker: %s fallo: %v", name, err)
		}
		return err
	}
}

// alreadyProcessed consulta la capa 2 de idempotencia.
func (d *Deps) alreadyProcessed(ctx context.Context, jobKey string) (bool, error) {
	var exists bool
	err := d.DB.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM processed_jobs WHERE job_key = $1)`, jobKey).Scan(&exists)
	return exists, err
}

func (d *Deps) markProcessed(ctx context.Context, jobKey, taskType string, result map[string]any) {
	raw, err := json.Marshal(result)
	if err != nil {
		raw = []byte("{}")
	}
	if _, err := d.DB.ExecContext(ctx, `
		INSERT INTO processed_jobs (job_key, task_type, result)
		VALUES ($1, $2, $3)
		ON CONFLICT (job_key) DO NOTHING`, jobKey, taskType, string(raw)); err != nil {
		log.Printf("worker: no se pudo registrar processed_jobs (%s): %v", jobKey, err)
	}
}

// interrupted distingue "el archivo no sirve" de "nos interrumpieron".
//
// Cuando el autoescalador retira una VM, asynq devuelve a la cola el trabajo
// activo y cancela su contexto, lo que mata a ffmpeg/ffprobe a mitad de
// camino. Ese error NO dice nada del archivo: marcar el asset como fallido
// lo dejaria asi para siempre, aunque otro worker lo procese bien. Si el
// contexto termino, se devuelve error sin tocar el estado y el reintento
// vuelve a empezar desde el original (los derivados se sobrescriben en las
// mismas llaves, asi que no quedan duplicados).
func interrupted(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return fmt.Errorf("trabajo interrumpido, no se marca como fallido: %w", err)
	}
	return nil
}

// skipDuplicate centraliza el mensaje y la metrica de una reentrega.
func (d *Deps) skipDuplicate(taskType, jobKey string) {
	metrics.JobsProcessed.WithLabelValues(taskType, "duplicate").Inc()
	log.Printf("worker: %s ya fue procesado (%s); se ignora la reentrega", taskType, jobKey)
}

// alertAssetFailed deja la ALERTA cuando el procesamiento de un asset queda en
// estado terminal de fallo (archivo corrupto, MIME que no corresponde, ffmpeg
// que no pudo con el archivo). La alerta vive en el dominio, no en un hook de
// la cola: ocurre al marcar el asset como 'failed', asi que es la misma pase
// lo que pase con la mensajeria (asynq en local, Pub/Sub en la nube).
//
// El estado 'failed' con failure_reason en la base es el diagnostico; esta
// linea de auditoria es la senal para operacion. Solo se llega aqui tras
// comprobar interrupted(ctx): una interrupcion al retirar el worker NO deja
// el asset en 'failed' ni dispara esta alerta.
func (d *Deps) alertAssetFailed(ctx context.Context, taskType, assetID, reason string) {
	metrics.JobsProcessed.WithLabelValues(taskType, "failed").Inc()
	log.Printf("ALERTA: %s dejo el asset %s en estado fallido: %s", taskType, assetID, reason)

	// ctx puede venir cancelado (el trabajo fallo por timeout) y la auditoria
	// se perderia. WithoutCancel ignora esa cancelacion pero conserva los
	// valores del contexto, como la traza.
	bgCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	d.Audit.Log(bgCtx, "", audit.ActionAssetFailed, "asset", assetID, "",
		map[string]any{"task": taskType, "reason": reason})
}
