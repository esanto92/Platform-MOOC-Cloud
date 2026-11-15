# Verificacion de escalamiento - Entrega 4 (Cloud Run + Pub/Sub)

## Ventana de la prueba

- **Fecha:** 14 de noviembre de 2026
- **Ventana (UTC):** `2026-11-14T18:45:38Z` a `2026-11-14T19:21:14Z`
  (equivale a ~1:45 p.m. - 2:21 p.m. UTC-5 en las graficas de la consola).
- **Proyecto / region:** `dsc-uniandes-20262` / `us-central1`
- **Script:** [`deploy/gcp/escalamiento-e4.sh`](../../../deploy/gcp/escalamiento-e4.sh)

## Carga aplicada (controlada)

- **Mensajes al topic `mooc-tasks`:** 1350 (9 oleadas de 150, cada 20 s).
- **Peticiones a la API:** ~2700 concurrentes a `mooc-api/readyz` (300 por oleada).
- Las tareas son `media:scan` sobre assets inexistentes: el worker las confirma
  de inmediato (push con p50 = 0.09 s), lo que ejercita el escalado por volumen
  sin procesar contenido real.

## Resultados observados

| Metrica | Pico observado | Limite configurado | Veredicto |
|---|---|---|---|
| Instancias `mooc-worker` | **2** | 3 | OK (escala y no supera el maximo) |
| Instancias `mooc-api` | **2** | 3 | OK (escala y no supera el maximo) |
| Mensajes pendientes (suscripcion) | **1** | - | cola minima: el ack es casi inmediato |
| Latencia del push (p50 / p95 / p99) | 0.09 s / 0.11 s / 0.12 s | - | confirmacion rapida del worker |

**Escalamiento observado:** SI. Ambos servicios pasaron de 1 a 2 instancias
bajo carga y volvieron a reducirse al terminar, siempre por debajo del maximo
configurado de 3.

## Lectura e interpretacion

- **Se cumple el requisito:** el enunciado pide demostrar escalamiento con
  metricas y un maximo de 3 por servicio. Las graficas muestran que `mooc-worker`
  y `mooc-api` escalan automaticamente con la carga (1 -> 2) y nunca superan 3.
- **Por que el pico fue 2 y no 3:** los mensajes pendientes no pasaron de 1
  porque el worker confirma cada tarea en ~0.1 s (son tareas no-op, sin
  transcodificacion). Sin acumulacion de backlog, Cloud Run no necesita crear la
  tercera instancia. El escalado a 3 se observaria con tareas que tardan
  (transcodificacion de video real).
- El enunciado no exige alcanzar el tope de 3, solo demostrar el escalado
  automatico y el limite configurado; ambos quedan evidenciados.

## Configuracion efectiva de los servicios

Formato: minScale, maxScale, concurrencia, timeout(s), recursos. Obtener con
`./deploy/gcp/cloudrun.sh resumen` o:

```
gcloud run services describe <servicio> --region=us-central1 \
  --format="value(spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],
    spec.template.metadata.annotations['autoscaling.knative.dev/maxScale'],
    spec.template.spec.containerConcurrency, spec.template.spec.timeoutSeconds,
    spec.template.spec.containers[0].resources.limits)"
```

| Servicio | minScale | maxScale | Concurrencia | Timeout | Recursos |
|---|---|---|---|---|---|
| `mooc-worker` | 0 | 3 | 1 | 600 s | 2 vCPU / 4 GiB |
| `mooc-api` | 0 | 3 | 80 | 60 s | 1 vCPU / 512 MiB |
| `mooc-web` | 0 | 3 | 80 | 60 s | 1 vCPU / 512 MiB |

> Verificar estos valores con `cloudrun.sh resumen`; la tabla recoge los
> definidos en `deploy/gcp/cloudrun.sh`.

## Evidencias (graficas de la consola)

Capturas tomadas en la ventana de la prueba (adjuntar en esta carpeta):

- `instancias-worker.png` - Cloud Run > mooc-worker > Metricas > *Cantidad de
  instancias de contenedor*: pico de 2 instancias activas.
- `instancias-api.png` - Cloud Run > mooc-api > Metricas: pico de 2 instancias.
- `mensajes-pendientes.png` - Pub/Sub > suscripcion mooc-tasks-push > Metricas >
  *Mensajes pendientes*: pico de 1, con latencia de push p50 = 0.09 s.

Metricas de origen:
- `run.googleapis.com/container/instance_count`
- `pubsub.googleapis.com/subscription/num_undelivered_messages`
