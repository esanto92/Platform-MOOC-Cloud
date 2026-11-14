package pubsubpush

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"mooc-platform/internal/queue"
	"mooc-platform/internal/tasks"
)

// nuevoServidor crea un Server con la validacion OIDC desactivada (audience
// vacio): aqui se prueba el mapeo de respuestas, no la autenticacion.
func nuevoServidor(t *testing.T) *Server {
	t.Helper()
	s, err := New(context.Background(), &tasks.Deps{}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// sobre arma el cuerpo que Pub/Sub envia a un endpoint push.
func sobre(taskType string, data []byte) []byte {
	env := map[string]any{
		"message": map[string]any{
			"data":       data, // json.Marshal de []byte -> base64, como Pub/Sub
			"attributes": map[string]string{"task": taskType},
			"messageId":  "1",
		},
		"subscription": "projects/p/subscriptions/s",
	}
	b, _ := json.Marshal(env)
	return b
}

func post(t *testing.T, s *Server, body []byte) int {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/pubsub/push", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, req)
	return rec.Code
}

func TestPushSobreIlegibleDevuelve400(t *testing.T) {
	s := nuevoServidor(t)
	if code := post(t, s, []byte("no es json")); code != http.StatusBadRequest {
		t.Fatalf("code = %d, se esperaba 400", code)
	}
}

func TestPushSinAtributoTaskDevuelve400(t *testing.T) {
	s := nuevoServidor(t)
	body, _ := json.Marshal(map[string]any{
		"message": map[string]any{"data": []byte("{}"), "attributes": map[string]string{}},
	})
	if code := post(t, s, body); code != http.StatusBadRequest {
		t.Fatalf("code = %d, se esperaba 400", code)
	}
}

func TestPushTipoDesconocidoDevuelve500(t *testing.T) {
	// Dispatch de un tipo sin handler devuelve un error normal (no skip-retry):
	// debe pedir reentrega con 5xx.
	s := nuevoServidor(t)
	if code := post(t, s, sobre("tarea:inexistente", []byte("{}"))); code != http.StatusInternalServerError {
		t.Fatalf("code = %d, se esperaba 500", code)
	}
}

func TestPushPayloadCorruptoHaceAck(t *testing.T) {
	// Un payload que no es JSON valido para el handler de correo produce
	// errSkipRetry: no se reintenta, se confirma con 2xx. No toca Mailer ni DB
	// porque falla al deserializar antes.
	s := nuevoServidor(t)
	code := post(t, s, sobre(queue.TaskSendEmail, []byte("payload corrupto")))
	if code != http.StatusNoContent {
		t.Fatalf("code = %d, se esperaba 204 (ack sin reintento)", code)
	}
}
