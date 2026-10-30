#!/usr/bin/env bash
# =====================================================================
# Escenario 2 - Prueba minima (Entrega 3): corre L1, L2 y L3 seguidos
#
# Repite la prueba minima de la Entrega 2 (resultados/entrega2_minima_*)
# con los mismos niveles, perfiles y patron, ahora contra el balanceador.
# Por cada nivel deja en resultados/entrega3_minima_<fecha>/:
#
#   L<n>_params          cargas/min:espectadores del nivel
#   L<n>_ventana         inicio y fin (UTC) para cruzar con Cloud Monitoring
#   L<n>_consola.log     una linea E2_CARGA por cada carga de profesor
#   L<n>_salida.txt      salida de k6
#   L<n>_resumen.json    resumen de k6 (--summary-export)
#   L<n>_reporte_k6.html reporte HTML de k6
#   L<n>_exit            codigo de salida de k6 (99 = algun umbral fallo)
#   L<n>_instancias.csv  instancias de mooc-api y mooc-worker cada 15 s
#                        (solo si gcloud funciona en esta VM)
#
# y al final reporte.md (generar_reporte.sh) con las mismas tablas que el
# de la Entrega 2.
#
# Uso (desde la raiz del repo, en la VM de pruebas, despues de
# preparar_datos.sh):
#   WORKER_CONCURRENCY=2 ./capacity-planning/escenario2/correr_minima.sh
#
# Variables opcionales:
#   NIVELES_A_CORRER ("L1 L2 L3")   PAUSA_ENTRE_NIVELES_S (60)
#   ZONE (us-central1-a)            INTERVALO_INSTANCIAS_S (15)
# Requiere: k6 (v1.3.0, la de la Entrega 2), jq y curl.
# =====================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
SEED="$DIR/datos/seed.json"
PERFILES="$DIR/media/perfiles.json"
NIVELES_A_CORRER="${NIVELES_A_CORRER:-L1 L2 L3}"
PAUSA_ENTRE_NIVELES_S="${PAUSA_ENTRE_NIVELES_S:-60}"
ZONE="${ZONE:-us-central1-a}"
INTERVALO_INSTANCIAS_S="${INTERVALO_INSTANCIAS_S:-15}"
# Sin valor por defecto a proposito: en la Entrega 2 era 4 en una sola VM y
# en la Entrega 3 es por instancia; el reporte debe decir cual se uso.
WORKER_CONCURRENCY="${WORKER_CONCURRENCY:?Indica WORKER_CONCURRENCY por instancia (la de worker.env de la plantilla)}"
K6_ENTREGA2="v1.3.0"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v k6 >/dev/null || die "k6 no esta instalado (ver README, seccion 2)"
command -v jq >/dev/null || die "falta jq (sudo apt-get install -y jq)"
[ -f "$SEED" ] || die "falta $SEED: corre preparar_datos.sh"
for n in $NIVELES_A_CORRER; do
  jq -e --arg n "$n" '.niveles[$n]' "$DIR/niveles.json" >/dev/null || die "nivel '$n' no existe en niveles.json"
done

API_URL="$(jq -r .api_url "$SEED")"
EDAD_SEED=$(( $(date +%s) - $(date -d "$(jq -r .generado "$SEED")" +%s) ))
[ "$EDAD_SEED" -lt 79200 ] || die "seed.json tiene mas de 22 h: los tokens (24 h) vencerian durante la prueba. Vuelve a correr preparar_datos.sh"

K6_VERSION="$(k6 version | head -1)"
case "$K6_VERSION" in
  *"$K6_ENTREGA2"*) ;;
  *) echo "AVISO: k6 es '$K6_VERSION' y la Entrega 2 uso $K6_ENTREGA2. Declararlo en el informe." ;;
esac

# Los archivos deben ser los mismos que describe perfiles.json (los de la
# Entrega 2); si no, la comparacion no es de la misma carga.
SHA_OK=true
for f in $(jq -r '.perfiles[].archivo' "$PERFILES"); do
  [ -f "$DIR/media/$f" ] || die "falta media/$f: copialo desde la Entrega 2 o corre generar_perfiles.sh"
  esperado=$(jq -r --arg f "$f" '.perfiles[] | select(.archivo==$f) | .sha256' "$PERFILES")
  real=$(sha256sum "$DIR/media/$f" | awk '{print $1}')
  if [ "$esperado" != "$real" ]; then
    echo "AVISO: media/$f no coincide con el SHA-256 de perfiles.json"
    SHA_OK=false
  fi
done

curl -fsS -m 10 "$API_URL/readyz" >/dev/null || die "la API no responde en $API_URL/readyz"

RUN="$DIR/resultados/entrega3_minima_$(date -u +%Y%m%d-%H%M)"
mkdir -p "$RUN"
echo "Resultados de esta corrida: $RUN"

# ---------------------------------------------------------------------
# gcloud es opcional: si esta y tiene permiso de lectura sobre Compute,
# se registran las instancias de cada grupo durante cada nivel.
# ---------------------------------------------------------------------
GCLOUD=false
PLANTILLA_API="?"; PLANTILLA_WORKER="?"
if command -v gcloud >/dev/null &&
   gcloud compute instance-groups managed describe mooc-api --zone="$ZONE" --format='value(name)' >/dev/null 2>&1; then
  GCLOUD=true
  PLANTILLA_API="$(gcloud compute instance-groups managed describe mooc-api --zone="$ZONE" --format='value(instanceTemplate.basename())')"
  PLANTILLA_WORKER="$(gcloud compute instance-groups managed describe mooc-worker --zone="$ZONE" --format='value(instanceTemplate.basename())')"
else
  echo "AVISO: gcloud no puede leer los grupos desde esta VM; no se registran instancias (tomarlas de Cloud Monitoring)."
fi

say "Condiciones (condiciones.json)"
jq -n --arg fecha "$(date -u +%Y-%m-%dT%H:%MZ)" --arg api "$API_URL" --arg k6 "$K6_VERSION" \
  --arg commit "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')" \
  --arg gen "$(hostname), $(nproc) vCPU, $(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)" \
  --arg wc "$WORKER_CONCURRENCY" --arg zona "$ZONE" --argjson sha "$SHA_OK" \
  --arg tpl_api "$PLANTILLA_API" --arg tpl_worker "$PLANTILLA_WORKER" \
  --argjson niveles "$(jq --arg l "$NIVELES_A_CORRER" '.niveles | with_entries(select(.key as $k | ($l | split(" ")) | index($k)))' "$DIR/niveles.json")" \
  --argjson comun "$(jq .comun "$DIR/niveles.json")" \
  --argjson datos "$(jq '{curso_contenido: .curso_contenido.slug, profesores: (.profesores|length), estudiantes: (.estudiantes|length), contenido: [.curso_contenido.assets[] | {perfil, duracion_s, variantes}]}' "$SEED")" \
  '{fecha:$fecha, api_url:$api, k6_version:$k6, git_commit_generador:$commit, generador:$gen,
    worker_concurrency_por_instancia:$wc, zona:$zona, plantilla_api:$tpl_api, plantilla_worker:$tpl_worker,
    media_igual_a_entrega2:$sha, niveles:$niveles, comun:$comun, datos:$datos}' > "$RUN/condiciones.json"
cat "$RUN/condiciones.json"

# Escribe "ts_ms,api_existentes,api_operativas,worker_existentes,worker_operativas".
# Operativa = RUNNING y sin accion en curso (no se esta creando ni borrando).
muestrear_instancias() {
  local salida="$1" g estados
  echo "ts_ms,api_existentes,api_operativas,worker_existentes,worker_operativas" > "$salida"
  while :; do
    local fila="$(date +%s%3N)"
    for g in mooc-api mooc-worker; do
      estados="$(gcloud compute instance-groups managed list-instances "$g" --zone="$ZONE" \
        --format='value(instanceStatus,currentAction)' 2>/dev/null || true)"
      fila+=",$(grep -c . <<<"$estados" || true),$(grep -c -P '^RUNNING\tNONE$' <<<"$estados" || true)"
    done
    echo "$fila" >> "$salida"
    sleep "$INTERVALO_INSTANCIAS_S"
  done
}

MUESTREO_PID=""
parar_muestreo() {
  if [ -n "$MUESTREO_PID" ]; then
    kill "$MUESTREO_PID" 2>/dev/null || true
    wait "$MUESTREO_PID" 2>/dev/null || true
    MUESTREO_PID=""
  fi
}
trap parar_muestreo EXIT

# ---------------------------------------------------------------------
ULTIMO="${NIVELES_A_CORRER##* }"
for N in $NIVELES_A_CORRER; do
  say "Nivel $N ($(jq -r --arg n "$N" '.niveles[$n] | "\(.cargas_por_min) cargas/min, \(.espectadores) espectadores"' "$DIR/niveles.json"))"
  jq -r --arg n "$N" '.niveles[$n] | "\(.cargas_por_min):\(.espectadores)"' "$DIR/niveles.json" > "$RUN/${N}_params"

  if $GCLOUD; then
    muestrear_instancias "$RUN/${N}_instancias.csv" &
    MUESTREO_PID=$!
  fi

  INICIO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Panel en vivo de k6: http://localhost:5665 (tunel SSH, ver README)"
  set +e
  (
    cd "$DIR/k6"
    K6_NO_USAGE_REPORT=true K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT="$RUN/${N}_reporte_k6.html" \
    NIVEL="$N" API_URL="$API_URL" \
      k6 run \
        --console-output="$RUN/${N}_consola.log" --log-format=json \
        --summary-export="$RUN/${N}_resumen.json" \
        escenario2.js 2>&1 | tee "$RUN/${N}_salida.txt"
    exit "${PIPESTATUS[0]}"
  )
  echo $? > "$RUN/${N}_exit"
  set -e
  printf '%s %s\n' "$INICIO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RUN/${N}_ventana"
  parar_muestreo
  echo "k6 termino con codigo $(cat "$RUN/${N}_exit") (99 = algun umbral no se cumplio; es un resultado, no un error)"

  # k6 ya espero a que cada carga del nivel llegara a ready (drenaje); la
  # pausa separa las ventanas de los niveles en Cloud Monitoring.
  if [ "$N" != "$ULTIMO" ]; then
    echo "Pausa de ${PAUSA_ENTRE_NIVELES_S} s antes del siguiente nivel..."
    sleep "$PAUSA_ENTRE_NIVELES_S"
  fi
done

say "Reporte"
"$DIR/generar_reporte.sh" "$RUN"
echo
echo "Listo. Abre $RUN/reporte.md y compara con resultados/entrega2_minima_20260928-0254/reporte.md"
