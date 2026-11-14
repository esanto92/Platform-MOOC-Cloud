#!/usr/bin/env bash
# =====================================================================
# Verificacion breve del escalamiento (Entrega 4, Cloud Run + Pub/Sub).
#
# Genera una carga controlada y mide, durante la ventana, las dos metricas
# que pide el enunciado:
#   - numero de instancias por servicio (mooc-worker, mooc-api)
#   - mensajes pendientes en la suscripcion push
# Deja un REPORTE Markdown con la serie temporal, los picos y el veredicto
# (maximo de 3 instancias por servicio).
#
# NO depende de k6 ni de subir archivos: la carga del worker es una rafaga de
# mensajes al topic (infla los mensajes pendientes -> Pub/Sub escala el worker)
# y la de la API son peticiones concurrentes a /readyz. Corre en Cloud Shell.
#
# Uso:
#   export PROJECT=dsc-uniandes-20262
#   ./deploy/gcp/escalamiento-e4.sh                 # 60 mensajes, 4 min de muestreo
#   MENSAJES=120 DURACION=360 ./deploy/gcp/escalamiento-e4.sh
#
# Variables opcionales (defaults entre parentesis):
#   REGION (us-central1)  PUBSUB_TOPIC (mooc-tasks)  PUBSUB_SUB (mooc-tasks-push)
#   MENSAJES (60)   rafaga de mensajes al topic
#   API_HITS (200)  peticiones concurrentes a la API
#   DURACION (240)  segundos de muestreo de metricas
#   INTERVALO (15)  segundos entre muestras
# =====================================================================
set -uo pipefail

PROJECT="${PROJECT:?exporta PROJECT con el id del proyecto}"
REGION="${REGION:-us-central1}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-mooc-tasks}"
PUBSUB_SUB="${PUBSUB_SUB:-mooc-tasks-push}"
MENSAJES="${MENSAJES:-60}"
API_HITS="${API_HITS:-200}"
DURACION="${DURACION:-240}"
INTERVALO="${INTERVALO:-15}"

gcloud config set project "$PROJECT" >/dev/null 2>&1

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$RAIZ/docs/entrega4/resultados-escalamiento"
REPORTE="$OUTDIR/escalamiento_$STAMP.md"
mkdir -p "$OUTDIR"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

API_URL="$(gcloud run services describe mooc-api --region="$REGION" --format='value(status.url)' 2>/dev/null)"

# --- Lectura de metricas de Cloud Monitoring ---------------------------------
# Devuelve el valor mas reciente de una serie (o "-" si no hay dato).
instancias() {  # instancias <servicio>
  gcloud monitoring time-series list \
    --filter='metric.type="run.googleapis.com/container/instance_count" AND resource.labels.service_name="'"$1"'"' \
    --interval-start-time="$(date -u -d '2 min ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2M +%Y-%m-%dT%H:%M:%SZ)" \
    --format="value(points[0].value.int64Value,points[0].value.doubleValue)" 2>/dev/null \
    | head -1 | awk '{print ($1==""?"-":$1)}'
}
pendientes() {
  gcloud monitoring time-series list \
    --filter='metric.type="pubsub.googleapis.com/subscription/num_undelivered_messages" AND resource.labels.subscription_id="'"$PUBSUB_SUB"'"' \
    --interval-start-time="$(date -u -d '2 min ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2M +%Y-%m-%dT%H:%M:%SZ)" \
    --format="value(points[0].value.int64Value)" 2>/dev/null | head -1 | awk '{print ($1==""?"-":$1)}'
}

# --- Config efectiva de los servicios (para el reporte) ----------------------
config_servicio() {  # config_servicio <servicio>
  gcloud run services describe "$1" --region="$REGION" --format="value(
    spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],
    spec.template.metadata.annotations['autoscaling.knative.dev/maxScale'],
    spec.template.spec.containerConcurrency,
    spec.template.spec.timeoutSeconds,
    spec.template.spec.containers[0].resources.limits)" 2>/dev/null
}

say "Entrega 4 - verificacion de escalamiento"
echo "proyecto=$PROJECT region=$REGION"
echo "carga: $MENSAJES mensajes al topic + $API_HITS peticiones a la API"
echo "muestreo: cada ${INTERVALO}s durante ${DURACION}s"
echo "reporte: $REPORTE"

# --- Generar la carga --------------------------------------------------------
say "Generando carga del worker (rafaga de $MENSAJES mensajes)"
for i in $(seq 1 "$MENSAJES"); do
  gcloud pubsub topics publish "$PUBSUB_TOPIC" \
    --attribute="task=media:scan" \
    --message="{\"asset_id\":\"00000000-0000-0000-0000-00000000$(printf '%04d' "$i")\"}" >/dev/null 2>&1 &
  # Limitar la concurrencia de publicacion para no saturar la sesion.
  if (( i % 20 == 0 )); then wait; fi
done
wait
echo "  $MENSAJES mensajes publicados"

if [ -n "$API_URL" ]; then
  say "Generando carga de la API ($API_HITS peticiones concurrentes a /readyz)"
  for _ in $(seq 1 "$API_HITS"); do
    curl -s -o /dev/null --max-time 10 "$API_URL/readyz" &
    # Mantener ~30 en vuelo para provocar concurrencia sin tumbar Cloud Shell.
    if (( $(jobs -r | wc -l) >= 30 )); then wait -n 2>/dev/null || wait; fi
  done
  wait
  echo "  $API_HITS peticiones enviadas"
fi

# --- Muestreo de metricas ----------------------------------------------------
say "Muestreando metricas durante ${DURACION}s"
INICIO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
declare -a filas
max_w=0; max_a=0; max_p=0
muestras=$(( DURACION / INTERVALO ))
for n in $(seq 1 "$muestras"); do
  t="$(date -u +%H:%M:%S)"
  w="$(instancias mooc-worker)"; a="$(instancias mooc-api)"; p="$(pendientes)"
  printf '  %s  worker=%s  api=%s  pendientes=%s\n' "$t" "$w" "$a" "$p"
  filas+=("| $t | $w | $a | $p |")
  [[ "$w" =~ ^[0-9]+$ ]] && (( w > max_w )) && max_w=$w
  [[ "$a" =~ ^[0-9]+$ ]] && (( a > max_a )) && max_a=$a
  [[ "$p" =~ ^[0-9]+$ ]] && (( p > max_p )) && max_p=$p
  sleep "$INTERVALO"
done
FIN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Veredicto ---------------------------------------------------------------
veredicto_w="OK"; (( max_w > 3 )) && veredicto_w="REVISAR (supero 3)"
veredicto_a="OK"; (( max_a > 3 )) && veredicto_a="REVISAR (supero 3)"
escalo="SI"; (( max_w <= 1 && max_a <= 1 )) && escalo="NO se observo escalado (subir MENSAJES/API_HITS o DURACION)"

# --- Reporte Markdown --------------------------------------------------------
say "Escribiendo el reporte"
{
  echo "# Verificacion de escalamiento - Entrega 4 (Cloud Run + Pub/Sub)"
  echo
  echo "- **Fecha (UTC):** $INICIO a $FIN"
  echo "- **Proyecto / region:** \`$PROJECT\` / \`$REGION\`"
  echo "- **Carga aplicada:** $MENSAJES mensajes al topic \`$PUBSUB_TOPIC\`"
  [ -n "$API_URL" ] && echo "  y $API_HITS peticiones concurrentes a \`$API_URL/readyz\`"
  echo "- **Muestreo:** cada ${INTERVALO}s durante ${DURACION}s"
  echo
  echo "## Resumen"
  echo
  echo "| Metrica | Pico observado | Limite configurado | Veredicto |"
  echo "|---|---|---|---|"
  echo "| Instancias \`mooc-worker\` | $max_w | 3 | $veredicto_w |"
  echo "| Instancias \`mooc-api\` | $max_a | 3 | $veredicto_a |"
  echo "| Mensajes pendientes (suscripcion) | $max_p | - | pico de cola |"
  echo
  echo "**Escalamiento observado:** $escalo"
  echo
  echo "## Configuracion efectiva de los servicios"
  echo
  echo "Formato: minScale, maxScale, concurrencia, timeout(s), recursos."
  echo
  echo "- **mooc-worker:** \`$(config_servicio mooc-worker)\`"
  echo "- **mooc-api:** \`$(config_servicio mooc-api)\`"
  echo "- **mooc-web:** \`$(config_servicio mooc-web)\`"
  echo
  echo "## Serie temporal"
  echo
  echo "| Hora (UTC) | Instancias worker | Instancias api | Mensajes pendientes |"
  echo "|---|---|---|---|"
  for f in "${filas[@]}"; do echo "$f"; done
  echo
  echo "## Notas"
  echo
  echo "- La carga del worker es una rafaga de mensajes al topic: inflan"
  echo "  \`num_undelivered_messages\`, Pub/Sub los entrega por push y Cloud Run"
  echo "  crea instancias del worker (hasta el maximo de 3)."
  echo "- Las instancias y los mensajes pendientes se leen de Cloud Monitoring"
  echo "  (\`run.googleapis.com/container/instance_count\`,"
  echo "  \`pubsub.googleapis.com/subscription/num_undelivered_messages\`)."
  echo "- Cloud Monitoring agrega por minuto: el pico real puede ser mayor que"
  echo "  el ultimo valor muestreado. Complementar con la grafica de la consola"
  echo "  (Cloud Run -> servicio -> Metricas -> Instance count) si se requiere."
} > "$REPORTE"

say "Listo"
echo "Reporte: $REPORTE"
echo "Picos -> worker=$max_w  api=$max_a  pendientes=$max_p"
