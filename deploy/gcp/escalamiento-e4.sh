#!/usr/bin/env bash
# =====================================================================
# Verificacion breve del escalamiento (Entrega 4, Cloud Run + Pub/Sub).
#
# Genera una carga controlada y SOSTENIDA y deja un reporte Markdown con la
# ventana de tiempo, la configuracion efectiva de los servicios y las
# instrucciones para leer las dos metricas que pide el enunciado en Cloud
# Monitoring: numero de instancias por servicio y mensajes pendientes.
#
# Por que no lee las metricas por CLI: 'gcloud monitoring time-series list' no
# existe en el componente estandar de esta instalacion (solo en alpha, no
# disponible aqui). Las metricas se consultan en la consola de Cloud Monitoring
# con la VENTANA que este script imprime y guarda en el reporte. Eso es
# exactamente lo que el enunciado acepta como evidencia ("metricas del numero
# de instancias ... con una carga controlada").
#
# Uso:
#   export PROJECT=dsc-uniandes-20262
#   ./deploy/gcp/escalamiento-e4.sh                        # carga por defecto
#   OLEADAS=8 POR_OLEADA=200 INTERVALO=20 ./deploy/gcp/escalamiento-e4.sh
#
# Variables opcionales (defaults entre parentesis):
#   REGION (us-central1)  PUBSUB_TOPIC (mooc-tasks)  PUBSUB_SUB (mooc-tasks-push)
#   OLEADAS (9)      numero de oleadas de publicacion al topic
#   POR_OLEADA (150) mensajes por oleada
#   INTERVALO (20)   segundos entre oleadas  -> ventana ~= OLEADAS*INTERVALO
#   API_HITS (300)   peticiones concurrentes a la API por oleada (0 = ninguna)
# =====================================================================
set -uo pipefail

PROJECT="${PROJECT:?exporta PROJECT con el id del proyecto}"
REGION="${REGION:-us-central1}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-mooc-tasks}"
PUBSUB_SUB="${PUBSUB_SUB:-mooc-tasks-push}"
OLEADAS="${OLEADAS:-9}"
POR_OLEADA="${POR_OLEADA:-150}"
INTERVALO="${INTERVALO:-20}"
API_HITS="${API_HITS:-300}"

gcloud config set project "$PROJECT" >/dev/null 2>&1

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$RAIZ/docs/entrega4/resultados-escalamiento"
REPORTE="$OUTDIR/escalamiento_$STAMP.md"
mkdir -p "$OUTDIR"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

API_URL="$(gcloud run services describe mooc-api --region="$REGION" --format='value(status.url)' 2>/dev/null)"
NUMPROY="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' 2>/dev/null)"

config_servicio() {  # minScale, maxScale, concurrencia, timeout, recursos
  gcloud run services describe "$1" --region="$REGION" --format="value(
    spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],
    spec.template.metadata.annotations['autoscaling.knative.dev/maxScale'],
    spec.template.spec.containerConcurrency,
    spec.template.spec.timeoutSeconds,
    spec.template.spec.containers[0].resources.limits)" 2>/dev/null
}

say "Entrega 4 - verificacion de escalamiento"
echo "proyecto=$PROJECT region=$REGION"
echo "carga: $OLEADAS oleadas x $POR_OLEADA mensajes (cada ${INTERVALO}s) al topic $PUBSUB_TOPIC"
[ "$API_HITS" -gt 0 ] && [ -n "$API_URL" ] && echo "       + $API_HITS peticiones a la API por oleada"
echo "ventana estimada: ~$(( OLEADAS * INTERVALO ))s"

INICIO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "Generando carga sostenida desde $INICIO"

total=0
for o in $(seq 1 "$OLEADAS"); do
  # Oleada de mensajes al topic (worker). asset inexistente: el handler hace
  # ack rapido, pero el volumen sostenido mantiene mensajes en vuelo y obliga
  # a Cloud Run a crear instancias del worker.
  for i in $(seq 1 "$POR_OLEADA"); do
    gcloud pubsub topics publish "$PUBSUB_TOPIC" \
      --attribute="task=media:scan" \
      --message="{\"asset_id\":\"00000000-0000-0000-0000-$(printf '%012d' $(( o*10000 + i )))\"}" \
      >/dev/null 2>&1 &
    if (( i % 25 == 0 )); then wait; fi
  done
  wait
  total=$(( total + POR_OLEADA ))

  # Oleada de peticiones a la API (solicitudes concurrentes).
  if [ "$API_HITS" -gt 0 ] && [ -n "$API_URL" ]; then
    for _ in $(seq 1 "$API_HITS"); do
      curl -s -o /dev/null --max-time 10 "$API_URL/readyz" &
      if (( $(jobs -r | wc -l) >= 40 )); then wait -n 2>/dev/null || wait; fi
    done
    wait
  fi

  echo "  oleada $o/$OLEADAS enviada (acumulado: $total mensajes)  $(date -u +%H:%M:%S)"
  [ "$o" -lt "$OLEADAS" ] && sleep "$INTERVALO"
done

FIN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "Carga terminada en $FIN  (total: $total mensajes)"

# --- Reporte Markdown --------------------------------------------------------
say "Escribiendo el reporte"
link_run="https://console.cloud.google.com/run/detail/$REGION/mooc-worker/metrics?project=$PROJECT"
link_sub="https://console.cloud.google.com/cloudpubsub/subscription/detail/$PUBSUB_SUB?project=$PROJECT"
{
  echo "# Verificacion de escalamiento - Entrega 4 (Cloud Run + Pub/Sub)"
  echo
  echo "## Ventana de la prueba (UTC)"
  echo
  echo "- **Inicio:** \`$INICIO\`"
  echo "- **Fin:**    \`$FIN\`"
  echo "- Usa esta ventana en Cloud Monitoring / consola para leer las metricas."
  echo
  echo "## Carga aplicada (controlada)"
  echo
  echo "- **Mensajes al topic \`$PUBSUB_TOPIC\`:** $total ($OLEADAS oleadas de $POR_OLEADA, cada ${INTERVALO}s)."
  if [ "$API_HITS" -gt 0 ] && [ -n "$API_URL" ]; then
    echo "- **Peticiones a la API:** $(( API_HITS * OLEADAS )) concurrentes a \`$API_URL/readyz\`."
  fi
  echo
  echo "## Configuracion efectiva de los servicios"
  echo
  echo "Formato: minScale, maxScale, concurrencia, timeout(s), recursos."
  echo
  echo "- **mooc-worker:** \`$(config_servicio mooc-worker)\`"
  echo "- **mooc-api:** \`$(config_servicio mooc-api)\`"
  echo "- **mooc-web:** \`$(config_servicio mooc-web)\`"
  echo
  echo "El maximo configurado es **3 instancias por servicio** (maxScale=3)."
  echo
  echo "## Metricas a leer (en la ventana de arriba)"
  echo
  echo "1. **Numero de instancias por servicio** - Cloud Run -> servicio -> Metricas -> *Container instance count*:"
  echo "   - [mooc-worker (metricas)]($link_run)"
  echo "   - Metrica: \`run.googleapis.com/container/instance_count\`."
  echo "2. **Mensajes pendientes** - Pub/Sub -> suscripcion -> Metricas:"
  echo "   - [mooc-tasks-push (suscripcion)]($link_sub)"
  echo "   - Metrica: \`pubsub.googleapis.com/subscription/num_undelivered_messages\`."
  echo
  echo "## Resultados observados (completar con las graficas)"
  echo
  echo "| Metrica | Pico observado | Limite | Veredicto |"
  echo "|---|---|---|---|"
  echo "| Instancias mooc-worker | _rellenar_ | 3 | _OK si <=3_ |"
  echo "| Instancias mooc-api | _rellenar_ | 3 | _OK si <=3_ |"
  echo "| Mensajes pendientes (pico) | _rellenar_ | - | cola bajo carga |"
  echo
  echo "> Adjuntar las capturas de las graficas de instancias y de mensajes"
  echo "> pendientes en esta carpeta y referenciarlas aqui."
  echo
  echo "## Notas"
  echo
  echo "- La carga del worker es una rafaga sostenida de mensajes al topic:"
  echo "  inflan \`num_undelivered_messages\`, Pub/Sub los entrega por push y"
  echo "  Cloud Run crea instancias del worker, hasta el maximo de 3."
  echo "- Cloud Monitoring agrega por minuto; el pico real puede ser mayor que"
  echo "  un punto aislado. La grafica de la consola es la evidencia principal."
  echo "- Proyecto \`$PROJECT\` (numero $NUMPROY), region \`$REGION\`."
} > "$REPORTE"

say "Listo"
echo "Reporte: $REPORTE"
echo "Ventana UTC: $INICIO  ->  $FIN"
echo
echo "Abre estas graficas y anota los picos en el reporte:"
echo "  instancias worker: $link_run"
echo "  mensajes pend.:    $link_sub"
