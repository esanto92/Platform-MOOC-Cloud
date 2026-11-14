// Implementacion de Publisher sobre Cloud Pub/Sub (Entrega 4).
//
// A diferencia de asynq, donde el worker BUSCA trabajos en Redis, Pub/Sub
// ENTREGA cada mensaje como una solicitud HTTP a una suscripcion push. Eso
// encaja con Cloud Run, que escala por solicitudes entrantes.
//
// Formato del mensaje (un solo topic para todas las tareas):
//
//   - Attributes["task"]  = tipo de tarea (queue.TaskScanAsset, etc.). El
//     consumidor lo usa para enrutar al handler (tasks.Dispatch).
//   - Attributes["jobKey"] = llave de idempotencia derivada del EFECTO
//     ("scan:<asset>", "badge:<enrollment>"). Pub/Sub no deduplica por esta
//     llave (no existe el equivalente a asynq.TaskID); la idempotencia la
//     garantiza el worker en Postgres (processed_jobs + estado de dominio).
//   - Data = el payload JSON, el mismo que consume el handler.
package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"cloud.google.com/go/pubsub"
)

// PubSubPublisher publica trabajos en un topic de Cloud Pub/Sub.
type PubSubPublisher struct {
	client *pubsub.Client
	topic  *pubsub.Topic
}

// Verifica en tiempo de compilacion que cumple el contrato.
var _ Publisher = (*PubSubPublisher)(nil)

// NewPubSubPublisher abre el cliente y referencia el topic. No crea el topic:
// lo provisiona el script de despliegue (deploy/gcp/cloudrun.sh pubsub). Las
// credenciales salen del entorno de Cloud Run (Application Default
// Credentials, la cuenta de servicio del servicio mooc-api).
func NewPubSubPublisher(ctx context.Context, projectID, topicID string) (*PubSubPublisher, error) {
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("cliente pubsub: %w", err)
	}
	return &PubSubPublisher{client: client, topic: client.Topic(topicID)}, nil
}

func (p *PubSubPublisher) Close() error {
	p.topic.Stop() // vacia los mensajes en vuelo antes de cerrar
	return p.client.Close()
}

// publish serializa el payload y publica con el tipo y la jobKey en atributos.
// Espera la confirmacion del servidor (Get) para devolver un error real si la
// publicacion falla: la API trata ese error como fallo de encolado, igual que
// con asynq.
func (p *PubSubPublisher) publish(taskType, jobKey string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("serializar payload: %w", err)
	}
	attrs := map[string]string{"task": taskType}
	if jobKey != "" {
		attrs["jobKey"] = jobKey
	}

	// Timeout acotado: publicar no debe colgar la respuesta de la API.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	res := p.topic.Publish(ctx, &pubsub.Message{Data: body, Attributes: attrs})
	if _, err := res.Get(ctx); err != nil {
		return fmt.Errorf("publicar %s: %w", taskType, err)
	}
	return nil
}

// Los atajos reciben los mismos argumentos que los de asynq para que los
// call-sites de la API no cambien. maxRetries se ignora: en Pub/Sub los
// reintentos y el backoff los gobierna la suscripcion, no el publicador.

func (p *PubSubPublisher) EnqueueEmail(to, subject, body string) error {
	return p.publish(TaskSendEmail, "", EmailPayload{To: to, Subject: subject, Body: body})
}

func (p *PubSubPublisher) EnqueueScan(assetID string, _ int) error {
	return p.publish(TaskScanAsset, "scan:"+assetID, AssetPayload{AssetID: assetID})
}

func (p *PubSubPublisher) EnqueueTranscode(assetID string, _ int) error {
	return p.publish(TaskTranscodeHLS, "hls:"+assetID, AssetPayload{AssetID: assetID})
}

func (p *PubSubPublisher) EnqueueBadge(enrollmentID string, _ int) error {
	return p.publish(TaskIssueBadge, "badge:"+enrollmentID, BadgePayload{EnrollmentID: enrollmentID})
}
