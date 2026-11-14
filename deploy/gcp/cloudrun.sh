#!/usr/bin/env bash
# =====================================================================
# Despliegue en Cloud Run (Entrega 4).
#
#   Navegador --> mooc-web (Cloud Run, Next.js BFF) --HTTPS--> mooc-api (Cloud Run)
#                                                                |  Direct VPC egress
#                                                                v  (subred mooc-run)
#                                    Cloud SQL (IP privada) + Redis en infra-server
#                 Cloud Storage <-- URLs prefirmadas (HMAC), directo desde el navegador
#
# Primera fase: frontend y API en Cloud Run. La API sigue encolando en Redis
# (infra-server) hasta que se migre a Pub/Sub; por eso infra-server sigue
# encendida. El paso worker-temporal es OPCIONAL y solo sirve para probar el
# flujo completo antes de Pub/Sub (ver comentario del paso).
#
# Uso (desde Cloud Shell o un PC con gcloud, en la raiz del repo o donde sea):
#   export PROJECT=dsc-uniandes-20262
#   ./deploy/gcp/build.sh api web worker     # imagenes del commit actual
#   ./deploy/gcp/cloudrun.sh todo            # apis red secretos api web resumen
#
#   Pasos sueltos: apis red secretos api web worker worker-temporal pubsub resumen
#   Se pueden encadenar: ./deploy/gcp/cloudrun.sh api web
#   VERSION=<sha> fija la version de las imagenes (por defecto, el commit actual).
#
# Entrega 4 (Pub/Sub), orden tipico despues de 'todo':
#   ./deploy/gcp/migrate.sh migrate-e4    # columna del lease de transcode
#   ./deploy/gcp/cloudrun.sh worker       # worker push (reemplaza worker-temporal)
#   ./deploy/gcp/cloudrun.sh pubsub       # topic + suscripcion push (usa la URL del worker)
#   ./deploy/gcp/cloudrun.sh api          # redeploy para que la API publique en Pub/Sub
# La API debe redesplegarse con QUEUE_BACKEND=pubsub (ver paso_api).
#
# La configuracion NO secreta se toma de los secretos de la Entrega 3
# (mooc-api-env, mooc-worker-env, mooc-web-env) para no duplicarla. Los
# valores sensibles se publican como secretos INDIVIDUALES (mooc-run-*),
# porque Cloud Run inyecta cada secreto en una variable de entorno. Ningun
# valor sensible queda en el repositorio, en las imagenes ni en la salida.
# =====================================================================
set -euo pipefail

PROJECT="${PROJECT:?exporta PROJECT con el id del proyecto}"
REGION="${REGION:-us-central1}"
NET="mooc-vpc"
# Subred propia para Direct VPC egress: Cloud Run toma de aqui una IP por
# instancia. Separada de las subredes de las VMs de la Entrega 3.
SUBNET_RUN="mooc-run"; RANGE_RUN="10.20.5.0/24"
REGISTRY="$REGION-docker.pkg.dev/$PROJECT/mooc"

SA_API="mooc-api@$PROJECT.iam.gserviceaccount.com"
SA_WORKER="mooc-worker@$PROJECT.iam.gserviceaccount.com"
SA_WEB="mooc-web@$PROJECT.iam.gserviceaccount.com"
# Cuenta de servicio DEDICADA a la suscripcion push: firma el token OIDC con
# el que Pub/Sub invoca al worker. Es la unica identidad autorizada a llamarlo.
SA_PUSH="mooc-pubsub-push@$PROJECT.iam.gserviceaccount.com"

# --- Pub/Sub (Entrega 4) ---
PUBSUB_TOPIC="${PUBSUB_TOPIC:-mooc-tasks}"
PUBSUB_SUB="${PUBSUB_SUB:-mooc-tasks-push}"
# Plazo de confirmacion (ack) de la suscripcion push. El maximo que admite
# Pub/Sub en push es 600 s. Debe ser menor que el lease de transcodificacion
# del worker (TranscodeLease, 20 min en internal/tasks/transcode.go) para que
# una reentrega encuentre el lease vigente y no duplique el trabajo.
PUBSUB_ACK_DEADLINE="${PUBSUB_ACK_DEADLINE:-600}"

# --- Limites y recursos de cada servicio (se documentan en la entrega) ---
# Maximo de 3 instancias por servicio, exigido por el enunciado.
MAX_INSTANCIAS="${MAX_INSTANCIAS:-3}"
# API: Go consume poco; 80 solicitudes simultaneas por instancia es el valor
# por defecto de Cloud Run y cabe en el pool de 20 conexiones a Postgres
# porque la mayoria de solicitudes son cortas. Las cargas de archivos NO
# pasan por la API (van directo al bucket), asi que 60 s de timeout sobra.
API_MIN="${API_MIN:-0}";  API_CPU="${API_CPU:-1}";  API_MEM="${API_MEM:-512Mi}"
API_CONC="${API_CONC:-80}"; API_TIMEOUT="${API_TIMEOUT:-60}"
# Web: el servidor de Next.js (BFF) solo reenvia a la API.
WEB_MIN="${WEB_MIN:-0}";  WEB_CPU="${WEB_CPU:-1}";  WEB_MEM="${WEB_MEM:-512Mi}"
WEB_CONC="${WEB_CONC:-80}"; WEB_TIMEOUT="${WEB_TIMEOUT:-60}"
# Worker temporal: ffmpeg con 2 vCPU como las VMs e2-highcpu-2. En Cloud Run
# el disco local (/tmp) vive en MEMORIA, asi que los archivos temporales de
# la transcodificacion cuentan contra este limite: por eso 4 GiB y no 2.
WORKER_MIN="${WORKER_MIN:-1}"; WORKER_CPU="${WORKER_CPU:-2}"; WORKER_MEM="${WORKER_MEM:-4Gi}"

# Claves de los .env de la Entrega 3 que son secretos: nunca se copian como
# variables de entorno normales; van por Secret Manager (paso secretos).
SECRETOS_EN_ENV=" DATABASE_URL REDIS_PASSWORD S3_SECRET_KEY ADMIN_PASSWORD "

AQUI="$(cd "$(dirname "$0")" && pwd)"
TMPD="$(mktemp -d)"; chmod 700 "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
existe() { "$@" >/dev/null 2>&1; }
version() { echo "${VERSION:-$(git -C "$AQUI" rev-parse --short=7 HEAD)}"; }

gcloud config set project "$PROJECT" >/dev/null

# URL de un servicio de Cloud Run. Es deterministica
# (https://<servicio>-<numero de proyecto>.<region>.run.app), asi que se
# conoce antes del primer despliegue.
NUMERO_PROYECTO=""
url_de() {
  [ -n "$NUMERO_PROYECTO" ] ||
    NUMERO_PROYECTO="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' | tr -d '\r')"
  echo "https://$1-$NUMERO_PROYECTO.$REGION.run.app"
}

imagen_existe() {
  existe gcloud artifacts docker images describe "$REGISTRY/$1:$2" && return 0
  echo "No existe la imagen $1:$2 en Artifact Registry. Ejecuta antes: ./deploy/gcp/build.sh $1" >&2
  echo "(o fija otra version ya construida, p. ej. VERSION=61f22e4)" >&2
  return 1
}

# cargar_env <rol>: baja el .env de la Entrega 3 (mooc-<rol>-env) a una
# carpeta temporal privada que se borra al terminar el script.
cargar_env() {
  local f="$TMPD/$1.env"
  [ -f "$f" ] || gcloud secrets versions access latest --secret="mooc-$1-env" | tr -d '\r' > "$f"
  echo "$f"
}
# valor <archivo_env> <CLAVE>
valor() { sed -n "s/^$2=//p" "$1" | head -n1; }

yaml_linea() { local v="${2//\'/\'\'}"; printf "%s: '%s'\n" "$1" "$v"; }

# env_cloudrun <archivo_env> <salida.yaml> [CLAVE=valor ...]
# Copia la configuracion NO secreta del .env de la Entrega 3 a un archivo
# YAML para --env-vars-file. Los pares extra reemplazan al valor original;
# un par con valor vacio (CLAVE=) elimina la variable.
env_cloudrun() {
  local origen="$1" salida="$2" par linea k v; shift 2
  local -A extra=()
  for par in "$@"; do extra["${par%%=*}"]="${par#*=}"; done
  : > "$salida"
  while IFS= read -r linea || [ -n "$linea" ]; do
    [[ -z "$linea" || "$linea" == \#* || "$linea" != *=* ]] && continue
    k="${linea%%=*}"; v="${linea#*=}"
    case "$SECRETOS_EN_ENV" in *" $k "*) continue ;; esac
    [[ -v "extra[$k]" ]] && continue
    [ -n "$v" ] && yaml_linea "$k" "$v" >> "$salida"
  done < "$origen"
  for k in "${!extra[@]}"; do
    [ -n "${extra[$k]}" ] && yaml_linea "$k" "${extra[$k]}" >> "$salida"
  done
  return 0
}

# publicar_secreto <nombre> <valor> <cuenta de servicio...>
# Crea el secreto o agrega una version SOLO si el valor cambio, y da acceso
# de lectura unicamente a las cuentas indicadas (minimo privilegio).
publicar_secreto() {
  local nombre="$1" val="$2" sa actual; shift 2
  [ -n "$val" ] || { echo "El valor de $nombre salio vacio: revisa los secretos de la Entrega 3." >&2; return 1; }
  if existe gcloud secrets describe "$nombre"; then
    actual="$(gcloud secrets versions access latest --secret="$nombre" 2>/dev/null || true)"
    if [ "$actual" != "$val" ]; then
      printf '%s' "$val" | gcloud secrets versions add "$nombre" --data-file=- >/dev/null
      echo "  $nombre: version nueva"
    else
      echo "  $nombre: sin cambios"
    fi
  else
    printf '%s' "$val" | gcloud secrets create "$nombre" --replication-policy=automatic --data-file=- >/dev/null
    echo "  $nombre: creado"
  fi
  for sa in "$@"; do
    gcloud secrets add-iam-policy-binding "$nombre" --member="serviceAccount:$sa" \
      --role=roles/secretmanager.secretAccessor --condition=None >/dev/null
  done
}

paso_apis() {
  say "Habilitando Cloud Run"
  gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
}

paso_red() {
  say "Subred $SUBNET_RUN ($RANGE_RUN) para Direct VPC egress"
  existe gcloud compute networks subnets describe "$SUBNET_RUN" --region="$REGION" ||
    gcloud compute networks subnets create "$SUBNET_RUN" --network="$NET" \
      --region="$REGION" --range="$RANGE_RUN" --enable-private-ip-google-access
  # No hace falta una regla nueva: los servicios salen con las etiquetas de
  # red mooc-api / mooc-worker, que la regla de la Entrega 3 ya autoriza
  # hacia Redis (6379) y Mailpit (1025) en infra-server.
  if ! existe gcloud compute firewall-rules describe mooc-allow-app-to-infra; then
    echo "AVISO: falta la regla mooc-allow-app-to-infra (provision.sh firewall-elastico)." >&2
    echo "Sin ella la API no llega a Redis y no arranca." >&2
  fi
}

paso_secretos() {
  say "Secretos individuales para Cloud Run (a partir de los de la Entrega 3)"
  local api worker
  api="$(cargar_env api)"; worker="$(cargar_env worker)"
  # API y workers usan el mismo usuario de Postgres y la misma contrasena de
  # Redis; cada rol conserva SU llave HMAC del bucket.
  publicar_secreto mooc-run-database-url   "$(valor "$api" DATABASE_URL)"    "$SA_API" "$SA_WORKER"
  publicar_secreto mooc-run-redis-password "$(valor "$api" REDIS_PASSWORD)"  "$SA_API" "$SA_WORKER"
  publicar_secreto mooc-run-admin-password "$(valor "$api" ADMIN_PASSWORD)"  "$SA_API"
  publicar_secreto mooc-run-s3-secret-api    "$(valor "$api" S3_SECRET_KEY)"    "$SA_API"
  publicar_secreto mooc-run-s3-secret-worker "$(valor "$worker" S3_SECRET_KEY)" "$SA_WORKER"
}

paso_api() {
  local v yaml url
  v="$(version)"; imagen_existe api "$v"
  url="$(url_de mooc-api)"
  say "mooc-api $v -> $url"
  yaml="$TMPD/api.yaml"
  # PUBLIC_BASE_URL: los enlaces que arma la API (verificacion de correo,
  #   insignias) apuntan a ella misma.
  # TRUSTED_PROXIES: se quita. Los rangos eran los del balanceador de la
  #   Entrega 3; en Cloud Run las solicitudes llegan por el frontend de
  #   Google. Pendiente verificar la IP de cliente (deuda tecnica).
  # QUEUE_BACKEND=pubsub: la API publica las tareas en el topic de Pub/Sub en
  # lugar de encolar en Redis. El topic lo crea paso_pubsub; la identidad
  # mooc-api tiene roles/pubsub.publisher solo sobre el. Para la Fase 1
  # (todavia con Redis) se puede sobreescribir con QUEUE_BACKEND=asynq.
  env_cloudrun "$(cargar_env api)" "$yaml" \
    "PUBLIC_BASE_URL=$url" "HTTP_ADDR=:8080" "TRUSTED_PROXIES=" \
    "QUEUE_BACKEND=${QUEUE_BACKEND:-pubsub}" "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
    "DB_MAX_OPEN_CONNS=20" "DB_MAX_IDLE_CONNS=10"
  gcloud run deploy mooc-api --quiet \
    --image="$REGISTRY/api:$v" --region="$REGION" \
    --service-account="$SA_API" --execution-environment=gen2 \
    --port=8080 --cpu="$API_CPU" --memory="$API_MEM" \
    --concurrency="$API_CONC" --timeout="$API_TIMEOUT" --cpu-boost \
    --min-instances="$API_MIN" --max-instances="$MAX_INSTANCIAS" \
    --network="$NET" --subnet="$SUBNET_RUN" --network-tags=mooc-api \
    --vpc-egress=private-ranges-only \
    --env-vars-file="$yaml" \
    --set-secrets="DATABASE_URL=mooc-run-database-url:latest,REDIS_PASSWORD=mooc-run-redis-password:latest,S3_SECRET_KEY=mooc-run-s3-secret-api:latest,ADMIN_PASSWORD=mooc-run-admin-password:latest" \
    --ingress=all --allow-unauthenticated \
    --labels="app=mooc,rol=api,version=$v"
  # --allow-unauthenticated: la API es publica a nivel de Cloud Run porque
  # la autenticacion la hace la propia aplicacion (token Bearer).
}

paso_web() {
  local v yaml api
  v="$(version)"; imagen_existe web "$v"
  api="$(url_de mooc-api)"
  say "mooc-web $v -> $(url_de mooc-web)"
  yaml="$TMPD/web.yaml"
  # El BFF de Next.js llama a la API por su URL publica de Cloud Run. El
  # navegador nunca habla con la API: todo pasa por los Route Handlers del
  # BFF (mismo origen), asi que la API no necesita CORS. El bucket ya acepta
  # PUT/GET desde cualquier origen (deploy/gcp/cors.json).
  env_cloudrun "$(cargar_env web)" "$yaml" "API_BASE_URL=$api/api/v1" "NODE_ENV=production"
  gcloud run deploy mooc-web --quiet \
    --image="$REGISTRY/web:$v" --region="$REGION" \
    --service-account="$SA_WEB" --execution-environment=gen2 \
    --port=3000 --cpu="$WEB_CPU" --memory="$WEB_MEM" \
    --concurrency="$WEB_CONC" --timeout="$WEB_TIMEOUT" --cpu-boost \
    --min-instances="$WEB_MIN" --max-instances="$MAX_INSTANCIAS" \
    --env-vars-file="$yaml" \
    --ingress=all --allow-unauthenticated \
    --labels="app=mooc,rol=web,version=$v"
  # Sin --network: el frontend no habla con nada privado.
}

# OPCIONAL y TEMPORAL. El worker actual (asynq) BUSCA trabajos en Redis por
# su cuenta; Cloud Run, en cambio, esta hecho para servicios que RECIBEN
# solicitudes. Para que funcione mientras llega Pub/Sub:
#   --no-cpu-throttling  CPU asignada siempre (si no, se congela sin solicitudes)
#   --min-instances=1    al menos un consumidor vivo
#   --port=9100          Cloud Run exige un puerto escuchando: el de /healthz
# Cloud Run NO escala esta version por la cola (no recibe solicitudes), y
# con CPU siempre asignada se cobra la instancia todo el tiempo. Se
# reemplazara por el worker con suscripcion push de Pub/Sub.
paso_worker_temporal() {
  local v yaml
  v="$(version)"; imagen_existe worker "$v"
  say "mooc-worker $v (TEMPORAL, consume Redis)"
  yaml="$TMPD/worker.yaml"
  # Cloud Run da 10 s entre SIGTERM y SIGKILL: asynq espera 8 s a los
  # trabajos activos y lo demas vuelve a la cola.
  env_cloudrun "$(cargar_env worker)" "$yaml" \
    "WORKER_SHUTDOWN_TIMEOUT_SECONDS=8" "DB_MAX_OPEN_CONNS=5" "DB_MAX_IDLE_CONNS=2"
  gcloud run deploy mooc-worker --quiet \
    --image="$REGISTRY/worker:$v" --region="$REGION" \
    --service-account="$SA_WORKER" --execution-environment=gen2 \
    --port=9100 --cpu="$WORKER_CPU" --memory="$WORKER_MEM" \
    --no-cpu-throttling --min-instances="$WORKER_MIN" --max-instances="$MAX_INSTANCIAS" \
    --network="$NET" --subnet="$SUBNET_RUN" --network-tags=mooc-worker \
    --vpc-egress=private-ranges-only \
    --env-vars-file="$yaml" \
    --set-secrets="DATABASE_URL=mooc-run-database-url:latest,REDIS_PASSWORD=mooc-run-redis-password:latest,S3_SECRET_KEY=mooc-run-s3-secret-worker:latest" \
    --ingress=internal --no-allow-unauthenticated \
    --labels="app=mooc,rol=worker,version=$v"
}

# Topic, cuenta de servicio de la suscripcion y suscripcion push (Entrega 4).
# Debe ejecutarse DESPUES de desplegar el servicio worker (paso_worker), porque
# la suscripcion necesita la URL del worker como endpoint push y como audiencia
# del token OIDC. Idempotente: no recrea lo que ya existe.
paso_pubsub() {
  say "Pub/Sub: topic $PUBSUB_TOPIC y suscripcion push $PUBSUB_SUB"
  gcloud services enable pubsub.googleapis.com >/dev/null

  # Topic de tareas.
  existe gcloud pubsub topics describe "$PUBSUB_TOPIC" ||
    gcloud pubsub topics create "$PUBSUB_TOPIC"

  # La API publica en el topic (solo publicar, nada mas): minimo privilegio.
  gcloud pubsub topics add-iam-policy-binding "$PUBSUB_TOPIC" \
    --member="serviceAccount:$SA_API" --role=roles/pubsub.publisher --condition=None >/dev/null

  # Cuenta de servicio dedicada a la suscripcion push.
  existe gcloud iam service-accounts describe "$SA_PUSH" ||
    gcloud iam service-accounts create mooc-pubsub-push \
      --display-name="Identidad de la suscripcion push de Pub/Sub"

  # Solo esta identidad puede invocar el worker (ingreso interno + sin invocacion
  # publica). Asi se protege al worker por IAM, como exige el enunciado.
  local worker_url
  worker_url="$(url_de mooc-worker)"
  gcloud run services add-iam-policy-binding mooc-worker --region="$REGION" \
    --member="serviceAccount:$SA_PUSH" --role=roles/run.invoker >/dev/null

  # Pub/Sub necesita poder acuñar tokens OIDC como la cuenta de la suscripcion.
  local pubsub_agent
  pubsub_agent="service-$NUMERO_PROYECTO@gcp-sa-pubsub.iam.gserviceaccount.com"
  [ -n "$NUMERO_PROYECTO" ] ||
    NUMERO_PROYECTO="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' | tr -d '\r')"
  pubsub_agent="service-$NUMERO_PROYECTO@gcp-sa-pubsub.iam.gserviceaccount.com"
  gcloud iam service-accounts add-iam-policy-binding "$SA_PUSH" \
    --member="serviceAccount:$pubsub_agent" \
    --role=roles/iam.serviceAccountTokenCreator --condition=None >/dev/null

  # Suscripcion push: entrega a <worker_url>/pubsub/push con token OIDC cuya
  # audiencia es la URL del worker (lo que el worker valida).
  if existe gcloud pubsub subscriptions describe "$PUBSUB_SUB"; then
    gcloud pubsub subscriptions update "$PUBSUB_SUB" \
      --push-endpoint="$worker_url/pubsub/push" \
      --push-auth-service-account="$SA_PUSH" \
      --push-auth-token-audience="$worker_url" \
      --ack-deadline="$PUBSUB_ACK_DEADLINE"
  else
    gcloud pubsub subscriptions create "$PUBSUB_SUB" --topic="$PUBSUB_TOPIC" \
      --push-endpoint="$worker_url/pubsub/push" \
      --push-auth-service-account="$SA_PUSH" \
      --push-auth-token-audience="$worker_url" \
      --ack-deadline="$PUBSUB_ACK_DEADLINE"
  fi
  echo "  suscripcion -> $worker_url/pubsub/push (ack ${PUBSUB_ACK_DEADLINE}s, token de $SA_PUSH)"
}

# Worker de la Entrega 4: servicio push de Pub/Sub. REEMPLAZA a worker-temporal
# (mismo nombre mooc-worker). A diferencia del temporal, escala por los mensajes
# que entrega Pub/Sub (cada mensaje es una solicitud HTTP) y no tiene CPU
# siempre asignada ni consume Redis como cola.
paso_worker() {
  local v yaml url
  v="$(version)"; imagen_existe worker "$v"
  url="$(url_de mooc-worker)"
  say "mooc-worker $v (push de Pub/Sub) -> $url"
  yaml="$TMPD/worker.yaml"
  # QUEUE_BACKEND=pubsub cambia el worker a modo push. PUBSUB_PUSH_AUDIENCE y
  # PUBSUB_PUSH_SA son lo que el worker exige al validar el token OIDC del push.
  # Concurrencia 1: cada instancia procesa un trabajo a la vez, para que mas
  # mensajes signifiquen mas instancias (hasta el maximo), no mas carga por CPU.
  env_cloudrun "$(cargar_env worker)" "$yaml" \
    "QUEUE_BACKEND=pubsub" "PUBSUB_TOPIC=$PUBSUB_TOPIC" \
    "PUBSUB_PUSH_AUDIENCE=$url" "PUBSUB_PUSH_SA=$SA_PUSH" \
    "HTTP_ADDR=:8080" "WORKER_SHUTDOWN_TIMEOUT_SECONDS=8" \
    "DB_MAX_OPEN_CONNS=5" "DB_MAX_IDLE_CONNS=2"
  gcloud run deploy mooc-worker --quiet \
    --image="$REGISTRY/worker:$v" --region="$REGION" \
    --service-account="$SA_WORKER" --execution-environment=gen2 \
    --port=8080 --cpu="$WORKER_CPU" --memory="$WORKER_MEM" \
    --concurrency=1 --timeout="$PUBSUB_ACK_DEADLINE" \
    --min-instances=0 --max-instances="$MAX_INSTANCIAS" \
    --network="$NET" --subnet="$SUBNET_RUN" --network-tags=mooc-worker \
    --vpc-egress=private-ranges-only \
    --env-vars-file="$yaml" \
    --set-secrets="DATABASE_URL=mooc-run-database-url:latest,REDIS_PASSWORD=mooc-run-redis-password:latest,S3_SECRET_KEY=mooc-run-s3-secret-worker:latest" \
    --ingress=internal --no-allow-unauthenticated \
    --labels="app=mooc,rol=worker,version=$v"
  # --ingress=internal + --no-allow-unauthenticated: el worker no admite
  # invocacion publica. Solo la identidad de la suscripcion (paso_pubsub) puede
  # llamarlo. El timeout = ack-deadline: una solicitud push puede durar lo que
  # dure la tarea mas larga admitida.
}

paso_resumen() {
  say "Servicios de Cloud Run"
  gcloud run services list --region="$REGION" --filter="metadata.labels.app=mooc" \
    --format="table(metadata.name,status.url,metadata.labels.version,status.conditions[0].status)"
  local s
  for s in mooc-web mooc-api mooc-worker; do
    existe gcloud run services describe "$s" --region="$REGION" || continue
    say "Configuracion efectiva de $s"
    gcloud run services describe "$s" --region="$REGION" --format="yaml(
      spec.template.metadata.annotations.'autoscaling.knative.dev/minScale',
      spec.template.metadata.annotations.'autoscaling.knative.dev/maxScale',
      spec.template.spec.containerConcurrency,
      spec.template.spec.timeoutSeconds,
      spec.template.spec.containers[0].resources.limits,
      spec.template.spec.serviceAccountName)"
  done
  echo
  echo "Frontend: $(url_de mooc-web)"
  echo "API:      $(url_de mooc-api)   (prueba: $(url_de mooc-api)/readyz)"
}

[ "$#" -gt 0 ] || { sed -n '2,29p' "$0"; exit 1; }
for paso in "$@"; do
  case "$paso" in
    todo) paso_apis; paso_red; paso_secretos; paso_api; paso_web; paso_resumen ;;
    apis|red|secretos|api|web|worker|worker-temporal|pubsub|resumen) "paso_${paso//-/_}" ;;
    *) echo "Paso desconocido: $paso" >&2; sed -n '2,29p' "$0"; exit 1 ;;
  esac
done
