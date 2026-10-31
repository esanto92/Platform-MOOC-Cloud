#!/usr/bin/env bash
# =====================================================================
# Escenario 1 (Entrega 3): una corrida de la actividad academica
# concurrente contra el balanceador
#
# Repite la corrida de la Entrega 2 (escenario1/escenario1_summary.json)
# con el mismo script, los mismos niveles (5 -> 20 -> 50 -> 90 -> 90 -> 5
# usuarios/s), N_STUDENTS=20 y la misma version de k6. Lo unico que cambia
# es BASE_URL: ahora entra por el balanceador al grupo mooc-api.
#
# Uso (desde la raiz del repo, en el PC generador, FUERA de GCP):
#   export BASE_URL=https://<dominio-del-balanceador>/api/v1
#   export ADMIN_PASSWORD='...'
#   ./capacity-planning/escenario1/correr_entrega3.sh r1     # corrida 1
#   ./capacity-planning/escenario1/correr_entrega3.sh r2     # corrida 2 ...
#   RATE_SCALE=0.2 STAGE_DUR=30s BASE_DUR=15s \
#     ./capacity-planning/escenario1/correr_entrega3.sh humo # prueba corta
#
# Deja en escenario1/resultados/entrega3_<corrida>_<fecha>/:
#   condiciones.txt   version de k6, commit, generador y parametros
#   ventana.txt       inicio y fin (UTC) de la carga: con estas horas se
#                     exportan los CSV de Cloud Monitoring a esta carpeta
#   salida.txt        consola de k6
#   reporte.txt       reporte legible (el mismo formato de la Entrega 2)
#   summary.json      resumen completo de k6 (handleSummary)
#   raw.json.gz       todas las muestras, para rehacer cualquier analisis
#   generador.csv     CPU y memoria de este PC cada 5 s: demuestra que el
#                     generador no limito la medicion
#   instancias.csv    instancias de mooc-api cada 15 s (solo si hay gcloud)
#   exit              codigo de salida de k6 (99 = algun umbral fallo)
#
# Variables opcionales: N_STUDENTS (20), RATE_SCALE (1), STAGE_DUR (2m),
# BASE_DUR (1m), PRE_VUS (50), MAX_VUS (300), ZONE (us-central1-a).
# Requiere: Docker (o k6 v1.6.1 nativo), curl, jq y vmstat.
# =====================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
SCRIPT="capacity-planning/k6/escenario1_actividad_academica.js"
# La de la Entrega 2 (pruebas_de_carga_entrega2.md, seccion 1.2): otra
# version cambiaria una condicion de la comparacion.
K6_VERSION_E2="v1.6.1"
K6_IMG="grafana/k6:1.6.1"
ZONE="${ZONE:-us-central1-a}"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
die() { echo "ERROR: $*" >&2; exit 1; }

corrida="${1:?uso: correr_entrega3.sh <corrida> (p. ej. r1, r2, r3, humo)}"
: "${BASE_URL:?exporta BASE_URL (https://<dominio-del-balanceador>/api/v1)}"
: "${ADMIN_PASSWORD:?exporta ADMIN_PASSWORD}"
for c in curl jq vmstat; do command -v "$c" >/dev/null || die "falta $c"; done

if command -v k6 >/dev/null && k6 version | grep -q "$K6_VERSION_E2"; then
  K6=(k6)
  K6_DESC="$(k6 version | head -1) (nativo)"
else
  command -v docker >/dev/null || die "se necesita k6 $K6_VERSION_E2 o Docker"
  K6_DESC="$K6_IMG (Docker)"
fi

curl -fsS -m 10 "${BASE_URL%/api/v1}/readyz" >/dev/null ||
  die "la API no responde en ${BASE_URL%/api/v1}/readyz"

REL="capacity-planning/escenario1/resultados/entrega3_${corrida}_$(date -u +%Y%m%d-%H%M)"
RUN="$REPO/$REL"
mkdir -p "$RUN"
echo "Resultados de esta corrida: $REL"

# Docker monta el repo en /repo y k6 escribe ahi sus archivos, asi que las
# rutas que recibe k6 son relativas a la raiz del repo en los dos casos.
if [ -z "${K6+x}" ]; then
  envs=()
  for v in BASE_URL ADMIN_EMAIL ADMIN_PASSWORD N_STUDENTS RATE_SCALE STAGE_DUR BASE_DUR PRE_VUS MAX_VUS; do
    [ -n "${!v:-}" ] && envs+=(-e "$v=${!v}")
  done
  envs+=(-e "REPORT_FILE=$REL/reporte.txt" -e "JSON_FILE=$REL/summary.json")
  K6=(docker run --rm --user "$(id -u):$(id -g)" "${envs[@]}" -v "$REPO:/repo" -w /repo "$K6_IMG")
fi
export REPORT_FILE="$REL/reporte.txt" JSON_FILE="$REL/summary.json"

say "Condiciones"
{
  echo "corrida:    $corrida"
  echo "script:     $SCRIPT"
  echo "commit:     $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo desconocido)"
  echo "k6:         $K6_DESC"
  echo "generador:  $(hostname), $(nproc) vCPU, $(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo), $(uname -sr)"
  echo "base_url:   $BASE_URL"
  for v in N_STUDENTS RATE_SCALE STAGE_DUR BASE_DUR PRE_VUS MAX_VUS; do
    printf '%-11s %s\n' "$v:" "${!v:-<default del script>}"
  done
} | tee "$RUN/condiciones.txt"

# ---------------------------------------------------------------------
# Muestreos en segundo plano mientras corre k6
# ---------------------------------------------------------------------
PIDS=()
parar_muestreos() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap parar_muestreos EXIT

# CPU ocupada = 100 - idle; memoria usada en MiB. Si la CPU del generador
# llega a ~100 % la latencia medida incluye su propia espera y la corrida
# no vale.
(
  echo "ts_utc,cpu_usada_pct,mem_usada_mib"
  while :; do
    # vmstat 1 2: la segunda linea es el ultimo segundo (la primera es el
    # promedio desde el arranque)
    cpu=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}')
    echo "$(date -u +%FT%TZ),$cpu,$(free -m | awk '/^Mem:/{print $3}')"
    sleep 4
  done
) > "$RUN/generador.csv" &
PIDS+=($!)

# Operativa = RUNNING y sin accion en curso (no se esta creando ni borrando).
if command -v gcloud >/dev/null &&
   gcloud compute instance-groups managed describe mooc-api --zone="$ZONE" --format='value(name)' >/dev/null 2>&1; then
  (
    echo "ts_utc,api_existentes,api_operativas"
    while :; do
      e="$(gcloud compute instance-groups managed list-instances mooc-api --zone="$ZONE" \
            --format='value(instanceStatus,currentAction)' 2>/dev/null || true)"
      echo "$(date -u +%FT%TZ),$(grep -c . <<<"$e" || true),$(grep -c -P '^RUNNING\tNONE$' <<<"$e" || true)"
      sleep 15
    done
  ) > "$RUN/instancias.csv" &
  PIDS+=($!)
else
  echo "AVISO: sin gcloud no se muestrean las instancias; exporta instance_group/size de Cloud Monitoring."
fi

# ---------------------------------------------------------------------
say "k6 (la corrida completa dura ~13 min con los valores por defecto)"
echo "inicio_utc: $(date -u +%FT%TZ)" > "$RUN/ventana.txt"
set +e
(cd "$REPO" && "${K6[@]}" run --out "json=$REL/raw.json" "$SCRIPT") 2>&1 | tee "$RUN/salida.txt"
estado=${PIPESTATUS[0]}
set -e
echo "fin_utc:    $(date -u +%FT%TZ)" >> "$RUN/ventana.txt"
echo "$estado" > "$RUN/exit"
parar_muestreos

gzip -f "$RUN/raw.json" 2>/dev/null || true

# setup_data trae los tokens de sesion de los estudiantes (validos 24 h) y
# el repositorio es publico: se redactan antes de versionar el resumen.
if [ -f "$RUN/summary.json" ]; then
  jq '.setup_data.students |= map(.token = "<redactado>")' "$RUN/summary.json" > "$RUN/summary.json.tmp" &&
    mv "$RUN/summary.json.tmp" "$RUN/summary.json"
fi

say "Listo"
cat "$RUN/ventana.txt"
echo "Salida de k6: $estado (99 = algun umbral fallo; la corrida igual sirve, se analiza)"
echo "Siguiente: exportar de Cloud Monitoring los CSV de esa ventana a $REL/"
