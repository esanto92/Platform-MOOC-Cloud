#!/usr/bin/env bash
# =====================================================================
# Escenario 2 - Arma reporte.md de una corrida de la prueba minima
#
# Lee L<n>_params, L<n>_resumen.json, L<n>_consola.log y, si existen,
# condiciones.json, L<n>_ventana y L<n>_instancias.csv. Produce las mismas
# tablas que el reporte de la Entrega 2 (resultados/entrega2_minima_*),
# para poder ponerlas lado a lado en pruebas_de_carga_entrega3.md.
#
# Uso:
#   ./capacity-planning/escenario2/generar_reporte.sh <carpeta de la corrida> [salida.md]
# Requiere: jq y awk.
# =====================================================================
set -euo pipefail
export LC_ALL=C   # printf con punto decimal

RUN="${1:?Uso: $0 <carpeta de la corrida> [salida.md]}"
RUN="$(cd "$RUN" && pwd)"
SALIDA="${2:-$RUN/reporte.md}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COND="$RUN/condiciones.json"

NIVELES=$(cd "$RUN" && ls L*_params 2>/dev/null | sed 's/_params$//' | sort -V)
[ -n "$NIVELES" ] || { echo "No hay L*_params en $RUN" >&2; exit 1; }

# "-" cuando k6 no reporto la metrica (p. ej. un nivel sin cargas).
f1()  { [ "$1" = "-" ] && echo "-" || printf '%.1f' "$1"; }
pct() { [ "$1" = "-" ] && echo "-" || printf '%.2f %%' "$1"; }
cond() { [ -f "$COND" ] && jq -r "$1 // \"?\"" "$COND" || echo "?"; }

# Una carga por linea (JSON), tomada de los E2_CARGA de la consola de k6.
cargas() { jq -cR 'fromjson? | .msg? // empty | select(startswith("E2_CARGA ")) | .[9:] | fromjson' "$RUN/$1_consola.log"; }

{
echo "## Escenario 2 - Carga, procesamiento y consumo multimedia (prueba minima)"
echo
echo "### Condiciones"
echo
echo "| Parametro | Valor |"
echo "|---|---|"
echo "| Fecha (UTC) | $(cond .fecha) |"
echo "| API (balanceador) | \`$(cond .api_url)\` |"
echo "| Generador de carga | $(cond .generador) (fuera de los grupos de la aplicacion) |"
echo "| Herramienta | $(cond .k6_version) |"
echo "| Concurrencia por instancia de worker | **$(cond .worker_concurrency_por_instancia)** |"
echo "| Plantillas (version desplegada) | API \`$(cond .plantilla_api)\`, worker \`$(cond .plantilla_worker)\` |"
echo "| Commit del generador | $(cond .git_commit_generador) |"
echo "| Archivos iguales a la Entrega 2 (SHA-256) | $(cond .media_igual_a_entrega2) |"
echo "| Duracion por nivel | 30s de calentamiento + 3m de medicion; se espera hasta 15m a que cada carga iniciada llegue a \`ready\` |"
echo
echo "### Recorridos"
echo
echo "- **Profesores** (llegadas a tasa constante): \`POST /uploads\` (la API autoriza y firma) -> \`PUT\` de cada parte de 8 MiB **directo al almacenamiento de objetos** con URL firmada -> \`POST /uploads/{id}/complete\` -> consulta de \`GET /assets/{id}\` cada 3 s hasta \`ready\` -> validacion funcional (duracion +-2 s y numero de rendiciones del master HLS)."
echo "- Orden de los archivos subidos (se repite): \`$(jq -r '.comun.patron_perfiles | join(" ")' "$DIR/niveles.json")\`."
echo "- **Estudiantes** (usuarios concurrentes): master \`.m3u8\` -> playlist de una rendicion (rotando por usuario) -> segmentos. Se precargan 3 segmentos y luego **cada segmento se pide al ritmo de reproduccion declarado en \`#EXTINF\`**. 20 segmentos por sesion y 5 s de pausa entre videos."
echo "- Contenido consumido: curso publicado \`$(cond .datos.curso_contenido)\` ($(cond '[.datos.contenido[]? | "\(.perfil): \(.variantes) rendiciones"] | join(", ")'))."
echo
echo "### Perfiles multimedia y rendiciones esperadas"
echo
echo "| Perfil | Archivo | Tipo | Duracion (s) | Resolucion | Tamano (MB) | Partes de 8 MiB | Rendiciones esperadas |"
echo "|---|---|---|---:|---:|---:|---:|---|"
jq -r '.perfiles[] | "| \(.id) | \(.archivo) | \(.kind) | \(.duracion_s) | \(if .kind == "audio" then "audio" else "\(.ancho)x\(.alto)" end) | \(.tamano_bytes / 1048576 * 10 | round / 10) | \(.partes_multipart) | \(.rendiciones_esperadas | join(", ")) |"' "$DIR/media/perfiles.json"
echo
echo "### Resultados por nivel"
echo
echo "Tiempos en segundos salvo que se indique. p50/p95 sobre las cargas del nivel."
echo
echo "**Carga y procesamiento (profesores)**"
echo
echo "| Nivel | Cargas/min | Cargas ok / iniciadas | API firma p95 (ms) | Confirmar p95 (ms) | Transferencia p50 / p95 | Mbps p50 | complete -> ready p50 / p95 | Extremo a extremo p95 | Errores control | Errores transferencia |"
echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
for N in $NIVELES; do
  # tr: los L<n>_params versionados pueden llegar con CRLF tras un checkout en Windows.
  IFS=: read -r CPM ESP < <(tr -d '\r' < "$RUN/${N}_params")
  OK=$(cargas "$N" | jq -s 'map(select(.estado_final == "ready")) | length')
  TOT=$(cargas "$N" | jq -s 'length')
  IFS=$'\t' read -r FIRMA CONF TR50 TR95 MBPS RD50 RD95 E2E ERRC ERRT < <(jq -r '
    def g(k; s): (.metrics[k][s] // null);
    def s: if . == null then null else . / 1000 end;
    def pct: if . == null then null else . * 100 end;
    [ g("http_req_duration{name:POST /uploads (autorizar y firmar)}"; "p(95)"),
      g("http_req_duration{name:POST /uploads/:id/complete (confirmar)}"; "p(95)"),
      (g("e2_transferencia_ms"; "med") | s), (g("e2_transferencia_ms"; "p(95)") | s),
      g("e2_transferencia_mbps"; "med"),
      (g("e2_carga_a_ready_ms"; "med") | s), (g("e2_carga_a_ready_ms"; "p(95)") | s),
      (g("e2_extremo_a_extremo_ms"; "p(95)") | s),
      (g("http_req_failed{tipo:control,fase:medicion}"; "value") | pct),
      (g("http_req_failed{tipo:transferencia,fase:medicion}"; "value") | pct)
    ] | map(. // "-") | @tsv' "$RUN/${N}_resumen.json")
  echo "| $N | $CPM | $OK / $TOT | $(f1 "$FIRMA") | $(f1 "$CONF") | $(f1 "$TR50") / $(f1 "$TR95") | $(f1 "$MBPS") | $(f1 "$RD50") / $(f1 "$RD95") | $(f1 "$E2E") | $(pct "$ERRC") | $(pct "$ERRT") |"
done
echo
echo "**Consumo HLS (estudiantes, fase de medicion)**"
echo
echo "| Nivel | Espectadores | Manifiestos | Manifiesto p95 (ms) | Segmentos | Segmento p50 / p95 (ms) | Mbps segmento p50 | Riesgo estimado de corte | Errores consumo | Rechazos 429 |"
echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
for N in $NIVELES; do
  IFS=: read -r CPM ESP < <(tr -d '\r' < "$RUN/${N}_params")
  # Segmento p50 y Mbps se toman del total del escenario (como en el
  # reporte de la Entrega 2); el resto, solo de la fase de medicion.
  IFS=$'\t' read -r NMAN MAN95 NSEG SEG50 SEG95 SMBPS CORTE ERRS R429 < <(jq -r '
    def g(k; s): (.metrics[k][s] // null);
    def pct: if . == null then null else . * 100 end;
    def fallos(k): [g(k; "passes"), g(k; "fails")];
    ([fallos("http_req_failed{tipo:consumo,fase:medicion}"), fallos("http_req_failed{tipo:consumo_api,fase:medicion}")]
      | map(map(. // 0)) | {f: (map(.[0]) | add), t: (map(add) | add)}) as $e
    | [ g("e2_manifiesto_ms{fase:medicion}"; "count"), g("e2_manifiesto_ms{fase:medicion}"; "p(95)"),
        g("e2_segmento_ms{fase:medicion}"; "count"), g("e2_segmento_ms"; "med"), g("e2_segmento_ms{fase:medicion}"; "p(95)"),
        g("e2_segmento_mbps"; "med"), (g("e2_riesgo_corte{fase:medicion}"; "value") | pct),
        (if $e.t > 0 then $e.f / $e.t * 100 else null end),
        g("e2_rechazos_429"; "count")
      ] | map(. // "-") | @tsv' "$RUN/${N}_resumen.json")
  echo "| $N | $ESP | $NMAN | $(f1 "$MAN95") | $NSEG | $(f1 "$SEG50") / $(f1 "$SEG95") | $(f1 "$SMBPS") | $(pct "$CORTE") | $(pct "$ERRS") | $R429 |"
done
echo
echo "**Por perfil (todas las cargas de cada nivel)**"
echo
echo "| Nivel | Perfil | Cargas ok / total | Transferencia prom. | complete -> ready prom. | complete -> ready max | Rendiciones obtenidas |"
echo "|---|---|---:|---:|---:|---:|---|"
for N in $NIVELES; do
  cargas "$N" | jq -rs --arg n "$N" '
    def r1: (. * 10 | round) / 10;
    def prom: if length == 0 then "-" else (add / length / 1000 | r1) end;
    def maximo: if length == 0 then "-" else (max / 1000 | r1) end;
    group_by(.perfil)[]
    | [ $n, .[0].perfil,
        "\(map(select(.estado_final == "ready")) | length) / \(length)",
        (map(.transferencia_ms // empty) | prom),
        (map(.carga_a_ready_ms // empty) | prom),
        (map(.carga_a_ready_ms // empty) | maximo),
        (map(.variantes // empty) | unique | map(tostring) | join(", ") | if . == "" then "-" else . end)
      ] | map(tostring) | "| " + join(" | ") + " |"'
done
echo
echo "**Criterios de exito (umbrales de k6)**"
echo
echo "| Nivel | Umbrales incumplidos |"
echo "|---|---|"
for N in $NIVELES; do
  # En --summary-export cada umbral vale true cuando NO se cumplio.
  echo "| $N | $(jq -r '[.metrics | to_entries[] | select(.value.thresholds) | .key as $k
      | .value.thresholds | to_entries[] | select(.value == true) | "`\($k)`: \(.key)"]
      | if length == 0 then "ninguno" else join("; ") end' "$RUN/${N}_resumen.json") |"
done
echo
echo "Fallos de carga (si los hubo):"
echo
FALLOS=$(for N in $NIVELES; do
  cargas "$N" | jq -r --arg n "$N" 'select(.estado_final != "ready")
    | "- \($n), carga \(.iter) (\(.perfil)): \(.motivo // "?")\(if .http then " (HTTP \(.http))" else "" end)\(if .ultimo_estado then ", ultimo estado " + .ultimo_estado else "" end)"'
done)
echo "${FALLOS:-- ninguno}"

if ls "$RUN"/L*_instancias.csv >/dev/null 2>&1 || ls "$RUN"/L*_ventana >/dev/null 2>&1; then
  WC=$(cond .worker_concurrency_por_instancia)
  echo
  echo "### Instancias y ventanas de tiempo"
  echo
  echo "Instancias operativas (RUNNING y sin accion en curso) muestreadas cada 15 s con gcloud. La concurrencia efectiva es workers operativos x concurrencia por instancia. Las ventanas sirven para tomar de Cloud Monitoring la CPU de los grupos, la metrica de la cola y las conexiones de Cloud SQL."
  echo
  echo "| Nivel | Inicio (UTC) | Fin (UTC) | API operativas min / max | Workers operativos min / max | Concurrencia efectiva max | Muestras |"
  echo "|---|---|---|---:|---:|---:|---:|"
  for N in $NIVELES; do
    INI="?"; FIN="?"
    [ -f "$RUN/${N}_ventana" ] && read -r INI FIN < <(tr -d '\r' < "$RUN/${N}_ventana")
    if [ -f "$RUN/${N}_instancias.csv" ]; then
      awk -F, -v n="$N" -v ini="$INI" -v fin="$FIN" -v wc="$WC" 'NR > 1 {
          if (c == 0 || $3 < amin) amin = $3; if ($3 > amax) amax = $3
          if (c == 0 || $5 < wmin) wmin = $5; if ($5 > wmax) wmax = $5; c++ }
        END { ef = (wc ~ /^[0-9]+$/) ? wmax * wc : "?"
          if (c == 0) printf "| %s | %s | %s | - | - | - | 0 |\n", n, ini, fin
          else printf "| %s | %s | %s | %d / %d | %d / %d | %s | %d |\n", n, ini, fin, amin, amax, wmin, wmax, ef, c }' "$RUN/${N}_instancias.csv"
    else
      echo "| $N | $INI | $FIN | - | - | - | 0 |"
    fi
  done
fi

echo
echo "### Limitaciones de esta prueba minima"
echo
echo "- Mide desde el cliente (k6): tiempos de la API, de la transferencia directa al almacenamiento, espera hasta \`ready\` (cola + procesamiento juntos) y latencia de manifiestos y segmentos."
echo "- No separa espera en cola de tiempo de transcodificacion. La CPU de los grupos, la profundidad de la cola y las conexiones de PostgreSQL se toman de Cloud Monitoring con las ventanas de arriba."
echo "- \"Riesgo estimado de corte\" = segmento que llego despues del momento en que el reproductor lo habria necesitado; es una estimacion, no una medicion de un reproductor real (no se mide tiempo hasta el primer cuadro)."
echo
echo "Datos crudos: \`capacity-planning/escenario2/resultados/$(basename "$RUN")\` (resumen JSON, consola y reporte HTML de k6 por nivel)."
} > "$SALIDA"

echo "Reporte escrito en $SALIDA"
