// Package pubsubpush expone el endpoint HTTP que recibe las entregas push de
// una suscripcion de Cloud Pub/Sub y las enruta al handler de la tarea.
//
// Modelo (Entrega 4): a diferencia de asynq, donde el worker BUSCA trabajos en
// Redis, aqui Pub/Sub ENTREGA cada mensaje como una solicitud HTTP. Eso encaja
// con Cloud Run, que escala por solicitudes entrantes: mas mensajes pendientes
// significan mas solicitudes simultaneas y, por tanto, mas instancias (hasta el
// maximo configurado).
//
// Contrato de confirmacion (ack):
//   - 2xx: Pub/Sub marca el mensaje como entregado y no lo reenvia. Se responde
//     2xx SOLO despues de persistir el estado y el resultado del trabajo, o
//     cuando el trabajo no debe reintentarse (payload corrupto, asset
//     inexistente, duplicado ya procesado).
//   - 5xx: Pub/Sub reintenta mas tarde (con backoff). Se responde 5xx ante un
//     fallo transitorio (base caida, interrupcion al retirar el worker).
package pubsubpush

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"google.golang.org/api/idtoken"

	"mooc-platform/internal/tasks"
)

// pushEnvelope es el cuerpo que Pub/Sub envia a un endpoint push.
// Ver https://cloud.google.com/pubsub/docs/push (formato del mensaje).
type pushEnvelope struct {
	Message struct {
		Data       []byte            `json:"data"` // base64 -> []byte automatico
		Attributes map[string]string `json:"attributes"`
		MessageID  string            `json:"messageId"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

// Server valida el push y lo despacha al handler de la tarea.
type Server struct {
	deps      *tasks.Deps
	validator *idtoken.Validator
	audience  string // audiencia OIDC esperada: la URL del propio servicio worker
	email     string // email de la cuenta de servicio de la suscripcion push
}

// New construye el servidor. Si audience esta vacio, NO se valida el token
// OIDC (solo para pruebas locales); en la nube debe ir siempre configurado.
func New(ctx context.Context, deps *tasks.Deps, audience, pushSAEmail string) (*Server, error) {
	s := &Server{deps: deps, audience: audience, email: pushSAEmail}
	if audience != "" {
		v, err := idtoken.NewValidator(ctx)
		if err != nil {
			return nil, err
		}
		s.validator = v
	}
	return s, nil
}

// Handler arma el mux HTTP del worker push: el endpoint de Pub/Sub y las rutas
// operativas (salud y metricas las conecta cmd/worker).
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /pubsub/push", s.handlePush)
	return mux
}

func (s *Server) handlePush(w http.ResponseWriter, r *http.Request) {
	if err := s.authenticate(r); err != nil {
		log.Printf("push: token rechazado: %v", err)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 10<<20)) // 10 MiB tope
	if err != nil {
		http.Error(w, "no se pudo leer el cuerpo", http.StatusBadRequest)
		return
	}
	var env pushEnvelope
	if err := json.Unmarshal(body, &env); err != nil {
		// Un sobre ilegible no mejora reintentando: 400 (no 5xx) para que
		// Pub/Sub no reentregue en bucle.
		http.Error(w, "sobre invalido", http.StatusBadRequest)
		return
	}

	taskType := env.Message.Attributes["task"]
	if taskType == "" {
		http.Error(w, "falta el atributo 'task'", http.StatusBadRequest)
		return
	}

	// El trabajo hereda el contexto de la solicitud: si Cloud Run empieza a
	// apagar la instancia, el contexto se cancela y el handler devuelve una
	// interrupcion (5xx), que Pub/Sub reentrega.
	err = s.deps.Dispatch(r.Context(), taskType, env.Message.Data)
	switch {
	case err == nil:
		// Procesado y persistido: ack.
		w.WriteHeader(http.StatusNoContent)
	case tasks.IsSkipRetry(err):
		// No reintentar (payload corrupto, asset inexistente, duplicado): ack
		// para que Pub/Sub no reentregue. El detalle queda en el log del job.
		log.Printf("push: %s no se reintenta: %v", taskType, err)
		w.WriteHeader(http.StatusNoContent)
	default:
		// Fallo transitorio: 5xx para que Pub/Sub reintente con backoff.
		log.Printf("push: %s fallo, se reintentara: %v", taskType, err)
		http.Error(w, "procesamiento fallido", http.StatusInternalServerError)
	}
}

// authenticate valida el token OIDC del push: debe estar firmado por Google,
// dirigido a la audiencia de este servicio y emitido por la cuenta de servicio
// de la suscripcion. Esto cumple el requisito del enunciado de "autorizar la
// identidad de la suscripcion push" y proteger al worker (ingreso interno +
// invocacion solo de esa identidad).
func (s *Server) authenticate(r *http.Request) error {
	if s.validator == nil {
		return nil // validacion desactivada (solo local)
	}
	authz := r.Header.Get("Authorization")
	raw, ok := strings.CutPrefix(authz, "Bearer ")
	if !ok || raw == "" {
		return errors.New("falta el token Bearer")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	payload, err := s.validator.Validate(ctx, raw, s.audience)
	if err != nil {
		return err
	}
	// Si se fijo el email de la cuenta de servicio, exigir que coincida.
	if s.email != "" {
		if email, _ := payload.Claims["email"].(string); email != s.email {
			return errors.New("el token no viene de la cuenta de servicio autorizada")
		}
	}
	return nil
}
