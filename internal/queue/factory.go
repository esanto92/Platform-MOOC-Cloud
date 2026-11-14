package queue

import (
	"context"
	"fmt"

	"mooc-platform/internal/config"
)

// NewPublisher construye el Publisher segun cfg.QueueBackend. La API y el
// worker lo usan por igual: ambos pueden publicar (la API encola el trabajo
// inicial; el worker encola trabajos derivados, p. ej. scan -> transcode y
// badge -> email).
func NewPublisher(ctx context.Context, cfg config.Config) (Publisher, error) {
	switch cfg.QueueBackend {
	case "pubsub":
		return NewPubSubPublisher(ctx, cfg.PubSubProject, cfg.PubSubTopic)
	case "asynq", "":
		return NewClient(cfg.RedisAddr, cfg.RedisPassword), nil
	default:
		return nil, fmt.Errorf("QUEUE_BACKEND desconocido: %q (usa asynq o pubsub)", cfg.QueueBackend)
	}
}
