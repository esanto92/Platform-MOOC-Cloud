#!/usr/bin/env bash
# =====================================================================
# Verificacion de la Entrega 4 (Cloud Run + Cloud Pub/Sub).
#
# Corre las comprobaciones de los cuatro criterios de la rubrica e imprime
# un reporte con OK / FALLA / AVISO por cada una. NO despliega ni modifica
# nada: solo lee el estado de GCP. Debe ejecutarse DESPUES del despliegue
# (build.sh + migrate.sh migrate-e4 + cloudrun.sh worker pubsub api).
#
# Uso (Cloud Shell o PC con gcloud autenticado en el proyecto):
#   export PROJECT=dsc-uniandes-20262
#   ./deploy/gcp/verificar-e4.sh
#
# Variables opcionales (valores por defecto entre parentesis):
#   REGION (us-central1)  PUBSUB_TOPIC (mooc-tasks)  PUBSUB_SUB (mooc-tasks-push)
#   MAX_ESPERADO (3)       ACK_ESPERADO (600)
# =====================================================================
set -uo pipefail

PROJECT="${PROJECT:?exporta PROJECT con el id del proyecto}"
REGION="${REGION:-us-central1}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-mooc-tasks}"
PUBSUB_SUB="${PUBSUB_SUB:-mooc-tasks-push}"
MAX_ESPERADO="${MAX_ESPERADO:-3}"
ACK_ESPERADO="${ACK_ESPERADO:-600}"
SA_PUSH="mooc-pubsub-push@$PROJECT.iam.gserviceaccount.com"
SA_API="mooc-api@$PROJECT.iam.gserviceaccount.com"

gcloud config set project "$PROJECT" >/dev/null 2>&1

# --- utilidades de reporte ---
rojo=$'\033[0;31m'; verde=$'\033[0;32m'; ama=$'\033[0;33m'; cyan=$'\033[1;36m'; fin=$'\033[0m'
OK=0; FALLA=0; AVISO=0
ok()    { printf '  %sOK%s    %s\n'    "$verde" "$fin" "$*"; OK=$((OK+1)); }
falla() { printf '  %sFALLA%s %s\n'    "$rojo"  "$fin" "$*"; FALLA=$((FALLA+1)); }
aviso() { printf '  %sAVISO%s %s\n'    "$ama"   "$fin" "$*"; AVISO=$((AVISO+1)); }
titulo(){ printf '\n%s== %s%s\n' "$cyan" "$*" "$fin"; }

url_de() { gcloud run services describe "$1" --region="$REGION" --format='value(status.url)' 2>/dev/null; }
existe() { "$@" >/dev/null 2>&1; }

# =====================================================================
titulo "1. Cloud Run: tres servicios desplegados (Despliegue e integracion, 30 pts)"
for s in mooc-web mooc-api mooc-worker; do
  if existe gcloud run services describe "$s" --region="$REGION"; then
    estado="$(gcloud run services describe "$s" --region="$REGION" \
      --format="value(status.conditions[0].status)" 2>/dev/null)"
    [ "$estado" = "True" ] && ok "$s desplegado y Ready" || falla "$s existe pero no esta Ready (estado=$estado)"
  else
    falla "$s no existe en Cloud Run"
  fi
done

API_URL="$(url_de mooc-api)"; WEB_URL="$(url_de mooc-web)"; WORKER_URL="$(url_de mooc-worker)"
echo "    web=$WEB_URL"
echo "    api=$API_URL"
echo "    worker=$WORKER_URL"

# =====================================================================
titulo "2. Escalamiento: maximo de $MAX_ESPERADO instancias por servicio (20 pts)"
for s in mooc-web mooc-api mooc-worker; do
  m="$(gcloud run services describe "$s" --region="$REGION" \
    --format="value(spec.template.metadata.annotations['autoscaling.knative.dev/maxScale'])" 2>/dev/null)"
  [ "$m" = "$MAX_ESPERADO" ] && ok "$s maxScale=$m" || falla "$s maxScale=$m (se esperaba $MAX_ESPERADO)"
done

# =====================================================================
titulo "3. API sana y conectada a sus dependencias"
if [ -n "$API_URL" ]; then
  ready="$(curl -s --max-time 20 "$API_URL/readyz" 2>/dev/null)"
  if echo "$ready" | grep -q '"ready":true'; then
    ok "GET /readyz -> ready:true  ($ready)"
  else
    falla "GET /readyz no devolvio ready:true  (respuesta: ${ready:-sin respuesta})"
  fi
else
  falla "no se pudo resolver la URL de mooc-api"
fi

# =====================================================================
titulo "4. Worker protegido por IAM (Configuracion y acceso, 15 pts)"
if [ -n "$WORKER_URL" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$WORKER_URL/pubsub/push" 2>/dev/null)"
  case "$code" in
    401|403) ok "POST /pubsub/push sin token -> $code (rechazado, correcto)" ;;
    000)     aviso "no hubo respuesta del worker (ingreso interno: normal desde fuera de la VPC)" ;;
    *)       falla "POST /pubsub/push sin token -> $code (el worker podria estar expuesto)" ;;
  esac
fi
# El unico invoker debe ser la cuenta de la suscripcion push.
invokers="$(gcloud run services get-iam-policy mooc-worker --region="$REGION" \
  --format="value(bindings.members)" --flatten="bindings[].members" \
  --filter="bindings.role=roles/run.invoker" 2>/dev/null)"
if echo "$invokers" | grep -q "$SA_PUSH"; then
  ok "run.invoker incluye la cuenta de la suscripcion ($SA_PUSH)"
else
  falla "run.invoker NO incluye $SA_PUSH (invokers: ${invokers:-ninguno})"
fi
if echo "$invokers" | grep -q "allUsers"; then
  falla "run.invoker incluye allUsers: el worker es publico"
else
  ok "run.invoker no incluye allUsers"
fi

# =====================================================================
titulo "5. Pub/Sub: topic y suscripcion push (Pub/Sub y workers, 25 pts)"
if existe gcloud pubsub topics describe "$PUBSUB_TOPIC"; then
  ok "topic $PUBSUB_TOPIC existe"
else
  falla "topic $PUBSUB_TOPIC no existe"
fi

if existe gcloud pubsub subscriptions describe "$PUBSUB_SUB"; then
  endpoint="$(gcloud pubsub subscriptions describe "$PUBSUB_SUB" --format='value(pushConfig.pushEndpoint)' 2>/dev/null)"
  oidc_sa="$(gcloud pubsub subscriptions describe "$PUBSUB_SUB" --format='value(pushConfig.oidcToken.serviceAccountEmail)' 2>/dev/null)"
  oidc_aud="$(gcloud pubsub subscriptions describe "$PUBSUB_SUB" --format='value(pushConfig.oidcToken.audience)' 2>/dev/null)"
  ack="$(gcloud pubsub subscriptions describe "$PUBSUB_SUB" --format='value(ackDeadlineSeconds)' 2>/dev/null)"

  [ "$endpoint" = "$WORKER_URL/pubsub/push" ] \
    && ok "endpoint push -> $endpoint" \
    || falla "endpoint push = $endpoint (se esperaba $WORKER_URL/pubsub/push)"

  [ "$oidc_sa" = "$SA_PUSH" ] \
    && ok "token OIDC firmado por $oidc_sa" \
    || falla "OIDC serviceAccount = ${oidc_sa:-vacio} (se esperaba $SA_PUSH)"

  [ -n "$oidc_aud" ] \
    && ok "audiencia OIDC = $oidc_aud" \
    || aviso "audiencia OIDC vacia (si el worker la exige, el push fallara)"

  [ "$ack" = "$ACK_ESPERADO" ] \
    && ok "ackDeadlineSeconds = $ack" \
    || aviso "ackDeadlineSeconds = $ack (se esperaba $ACK_ESPERADO)"
else
  falla "suscripcion $PUBSUB_SUB no existe"
fi

# =====================================================================
titulo "6. Permisos de publicacion de la API (minimo privilegio)"
pubroles="$(gcloud pubsub topics get-iam-policy "$PUBSUB_TOPIC" \
  --format="value(bindings.role)" --flatten="bindings[]" \
  --filter="bindings.members:$SA_API" 2>/dev/null)"
if echo "$pubroles" | grep -q "roles/pubsub.publisher"; then
  ok "mooc-api tiene roles/pubsub.publisher sobre el topic"
else
  falla "mooc-api NO tiene roles/pubsub.publisher sobre $PUBSUB_TOPIC"
fi

# =====================================================================
titulo "7. Mensajes pendientes en la suscripcion (muestra puntual)"
pend="$(gcloud monitoring time-series list \
  --filter='metric.type="pubsub.googleapis.com/subscription/num_undelivered_messages" AND resource.labels.subscription_id="'"$PUBSUB_SUB"'"' \
  --interval-start-time="$(date -u -d '5 min ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
  --format="value(points[0].value.int64Value)" 2>/dev/null | head -1)"
if [ -n "$pend" ]; then
  aviso "mensajes sin entregar ahora: $pend (0 en reposo; sube bajo carga)"
else
  aviso "sin datos de la metrica (normal si no ha habido trafico reciente)"
fi

# =====================================================================
titulo "Resumen"
printf '  %sOK: %d%s   %sAVISO: %d%s   %sFALLA: %d%s\n' "$verde" "$OK" "$fin" "$ama" "$AVISO" "$fin" "$rojo" "$FALLA" "$fin"
echo
echo "Comprobaciones manuales que este script NO cubre (requieren interaccion):"
echo "  - Recorrido profesor->estudiante desde el navegador ($WEB_URL)."
echo "  - Seguir una tarea en los logs: gcloud run services logs read mooc-api|mooc-worker --region=$REGION"
echo "  - Reentrega sin duplicados: subir un video largo y verificar un solo HLS y estado 'ready'."
echo "  - Grafica de instancias bajo carga (Consola: Cloud Run -> mooc-worker -> Metricas)."
echo
[ "$FALLA" -eq 0 ]
