# Escenario 2 - Carga, procesamiento y consumo multimedia (prueba minima)

Profesores que suben video y audio **directamente** al almacenamiento de
objetos mientras estudiantes consumen contenido HLS ya disponible.

En la Entrega 2 se corrio una **prueba minima** de tres niveles (L1, L2, L3)
desde la VM de pruebas. En la Entrega 3 se repite **la misma prueba**, ahora
contra el balanceador y los grupos elasticos, para comparar. Esta carpeta
contiene solo lo necesario para eso.

```
capacity-planning/escenario2/
├── README.md               <- esta guia
├── niveles.json            <- L1, L2, L3 (iguales a la Entrega 2: no cambiarlos)
├── generar_perfiles.sh     <- crea P1, P2, P3 y A1 si media/ esta vacia
├── preparar_datos.sh       <- profesores, estudiantes y curso con contenido HLS listo
├── correr_minima.sh        <- corre L1, L2 y L3 seguidos y arma el reporte
├── generar_reporte.sh      <- reporte.md a partir de los archivos de una corrida
├── k6/escenario2.js        <- guion de k6 (profesores + espectadores)
├── media/perfiles.json     <- ficha tecnica de los 4 archivos (los archivos NO se versionan)
├── datos/                  <- (generado, NO se versiona: tiene tokens)
└── resultados/
    ├── entrega2_minima_20260928-0254/   <- linea base (Entrega 2, Web Server + Worker Server)
    └── entrega3_minima_<fecha>/         <- lo que deja correr_minima.sh
```

---

## 1. Que mide

```
              VM de pruebas (k6)  -- fuera de los grupos de la aplicacion --
          ┌───────────────────────┴──────────────────────────┐
   PROFESORES (N cargas/min)                         ESPECTADORES (M usuarios)
   1 POST /uploads ─────────────┐                    1 GET master .m3u8 ─────┐
   3 POST /uploads/{id}/complete├──► Balanceador ──► mooc-api (1-3 VMs)      │
   4 GET /assets/{id} cada 3 s ─┘        │ encola                            │
                                         ▼                                   │
   2 PUT partes de 8 MiB ──────┐   Redis (infra-server) ─► mooc-worker (1-3 VMs)
                               ▼                              │              │
                        Cloud Storage ◄───────────────────────┘  3 GET segmentos
                                      ◄──────────────────────────────────────┘
```

- El **trafico de control** (firmar, confirmar, consultar estado, pedir
  listas de reproduccion) pasa por el balanceador y la API. La
  **transferencia de archivos** (partes y segmentos) va directo a Cloud
  Storage. El reporte los separa.
- Un HTTP 2xx no basta: una carga solo cuenta como exitosa si llega a
  `ready`, la duracion detectada coincide (+-2 s) y el master HLS tiene
  exactamente las rendiciones esperadas.

| Aspecto | Definicion |
|---|---|
| Herramienta | k6 v1.3.0 (la misma de la Entrega 2). Modela los dos recorridos en paralelo, corta los archivos en partes para la carga multipart, respeta la cadencia HLS, valida con `check` y exporta resumen JSON y reporte HTML. |
| Niveles | `niveles.json`: **L1** 1 carga/min + 10 espectadores, **L2** 2/20, **L3** 4/40. Cada uno: 30 s de calentamiento + 3 min de medicion; despues k6 sigue cada carga iniciada hasta `ready` (maximo 15 min). |
| Actores | Profesores: tasa constante de llegada (`constant-arrival-rate`). Espectadores: usuarios concurrentes (`ramping-vus`: rampa en el calentamiento y luego constantes). |
| Recorrido profesor | `POST /uploads` -> `PUT` de cada parte a la URL firmada -> `POST /uploads/{id}/complete` -> `POST /units/{id}/resources` -> `GET /assets/{id}` cada 3 s hasta `ready`/`failed`/`infected` -> validacion. |
| Recorrido espectador | master -> playlist de una rendicion (rota por usuario) -> pre-carga 3 segmentos -> un segmento al ritmo de `#EXTINF` (~8.3 s) manteniendo 3 de ventaja -> 20 segmentos por sesion -> pausa 5 s -> siguiente contenido. |
| Mezcla de archivos | Patron fijo de 10 cargas: 4xP1, 3xP2, 2xA1, 1xP3. |
| Perfiles | `media/perfiles.json`: P1 30 s 480p, P2 90 s 720p, P3 178 s 1080p, A1 178 s audio. Rendiciones esperadas: P1 {480,360}, P2 {720,480,360}, P3 {1080,720,480,360}, A1 {a128}. Sin upscaling. |
| Datos sinteticos | 20 profesores de carga (cada uno con curso y unidad), 40 estudiantes inscritos, 1 curso publicado con los 4 assets en HLS. |
| Autenticacion | Fuera del recorrido medido: las sesiones se preparan antes (`preparar_datos.sh`). |
| Exito del nivel | Todos los umbrales de k6: p95 firmar/confirmar/crear recurso < 1 s, p95 consultar estado < 500 ms, p95 manifiestos < 1 s, p95 segmentos < 2 s, errores < 1 %, riesgo de corte < 1 %, >= 99 % de cargas en `ready` y validadas. |

---

## 2. Preparar la VM de pruebas (una sola vez)

Todo se hace en la VM de pruebas (`vm-pruebas`), nunca en las VMs de los
grupos. Conectarse con:

```bash
gcloud compute ssh vm-pruebas --zone=us-central1-a
```

**Utilidades y k6 v1.3.0** (la misma version de la Entrega 2; si ya esta
instalada, `k6 version` lo confirma):

```bash
sudo apt-get update && sudo apt-get install -y git jq curl tmux
cd /tmp && curl -LO https://github.com/grafana/k6/releases/download/v1.3.0/k6-v1.3.0-linux-amd64.tar.gz
tar xzf k6-v1.3.0-linux-amd64.tar.gz && sudo mv k6-v1.3.0-linux-amd64/k6 /usr/local/bin/ && k6 version
```

**Codigo:** clonar el repositorio (o `git pull` si ya esta) y quedar en la
rama de la Entrega 3.

**Archivos multimedia:** `media/` debe tener `p1_corto_480p.mp4`,
`p2_medio_720p.mp4`, `p3_largo_1080p.mp4` y `a1_audio.m4a`. Lo mejor es
reutilizar los de la Entrega 2 (si siguen en la VM o en tu PC):

```bash
# desde tu PC, si los tienes ahi
gcloud compute scp media/*.mp4 media/*.m4a vm-pruebas:~/Platform-MOOC-Cloud/capacity-planning/escenario2/media/ --zone=us-central1-a
```

Si no estan, regenerarlos desde el video original de 1080p
(`sudo apt-get install -y ffmpeg` primero):

```bash
./capacity-planning/escenario2/generar_perfiles.sh ~/original_1080p.mp4
git diff capacity-planning/escenario2/media/perfiles.json   # si cambian tamano o SHA-256, declararlo en el informe
```

**gcloud (opcional, recomendado):** si la cuenta de servicio de la VM puede
leer Compute Engine (`roles/compute.viewer`), `correr_minima.sh` registra
cuantas instancias de `mooc-api` y `mooc-worker` hay durante cada nivel y
que plantilla (version) usan. Si no, sigue igual y esas cifras se toman de
Cloud Monitoring. Comprobar con:

```bash
gcloud compute instance-groups managed list --zones=us-central1-a
```

---

## 3. Antes de cada dia de pruebas

1. **Plataforma arriba** (desde tu PC): `./deploy/gcp/provision.sh resumen`
   muestra la URL del balanceador (`https://<ip>.sslip.io`). Anotar tambien
   `RATE_LIMIT_PER_MIN` y `WORKER_CONCURRENCY` de las plantillas: van en el
   informe.
2. **Datos de prueba** en la VM de pruebas (~5-10 min; tarda lo que el
   worker en transcodificar el P3). La clave del admin se lee de tu copia
   local de secretos, nunca del repo:

   ```bash
   cd ~/Platform-MOOC-Cloud
   export API_URL=https://<ip-del-balanceador>.sslip.io
   read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
   ./capacity-planning/escenario2/preparar_datos.sh
   ```

   Deja `datos/seed.json` (tokens de 24 h, no se versiona). Si pasa un dia,
   volver a correrlo.

---

## 4. Correr la prueba minima

Dura ~45-50 min (tres niveles de ~15 min y pausas de 1 min). Correrla dentro
de `tmux` para que no se corte si se cae la conexion SSH:

```bash
tmux new -s e2
cd ~/Platform-MOOC-Cloud
WORKER_CONCURRENCY=2 ./capacity-planning/escenario2/correr_minima.sh
# Ctrl+B y luego D para salir sin detenerla; "tmux attach -t e2" para volver
```

`WORKER_CONCURRENCY` es la concurrencia **por instancia** de worker (la de
`deploy/gcp/mig/worker/worker.env.example`, hoy 2). Es obligatoria porque
cambio frente a la Entrega 2 (4 en una sola VM) y el reporte debe decirlo.

Para correr solo algunos niveles: `NIVELES_A_CORRER="L3" ...`.

**Panel en vivo de k6** (sirve para el video). En otra terminal de tu PC:

```bash
gcloud compute ssh vm-pruebas --zone=us-central1-a -- -N -L 5665:localhost:5665
```

y abrir http://localhost:5665 mientras corre un nivel.

**Durante la corrida**, en la consola de GCP (Cloud Monitoring), guardar
capturas o exportar, para la ventana de cada nivel (queda en
`L<n>_ventana`):

- CPU de los grupos `mooc-api` y `mooc-worker` y numero de instancias.
- La metrica de la cola que publica `queue-metrics` (la senal del
  autoescalado de workers).
- Conexiones y CPU de Cloud SQL.

---

## 5. Resultados

Al terminar, `correr_minima.sh` deja `resultados/entrega3_minima_<fecha>/`
con, por nivel, `L<n>_params`, `L<n>_ventana`, `L<n>_consola.log`,
`L<n>_salida.txt`, `L<n>_resumen.json`, `L<n>_reporte_k6.html`,
`L<n>_exit` y (si hay gcloud) `L<n>_instancias.csv`; ademas
`condiciones.json` y `reporte.md`.

`reporte.md` tiene **las mismas tablas** que
[`resultados/entrega2_minima_20260928-0254/reporte.md`](resultados/entrega2_minima_20260928-0254/reporte.md)
(se comprobo regenerando el de la Entrega 2 con `generar_reporte.sh`: las
cifras coinciden), mas una tabla de instancias y ventanas de tiempo. Si hace
falta rehacerlo: `./capacity-planning/escenario2/generar_reporte.sh <carpeta>`.

Traer la carpeta a tu PC y versionarla (no contiene secretos: los tokens
solo estan en `datos/seed.json`):

```bash
gcloud compute scp --recurse vm-pruebas:~/Platform-MOOC-Cloud/capacity-planning/escenario2/resultados/entrega3_minima_<fecha> \
  capacity-planning/escenario2/resultados/ --zone=us-central1-a
```

### Diferencias con la Entrega 2 que hay que declarar en el informe

| Aspecto | Entrega 2 | Entrega 3 |
|---|---|---|
| Entrada | Caddy en el Web Server (`https://136-114-53-21.sslip.io`) | Balanceador HTTPS externo |
| API | 1 VM fija | Grupo `mooc-api`, 1 a 3 VMs por CPU |
| Workers | 1 VM fija, `WORKER_CONCURRENCY=4` | Grupo `mooc-worker`, 1 a 3 VMs por trabajos en cola, concurrencia por instancia (registrada en `condiciones.json`) |
| Cola | Redis en el Worker Server | Redis en `infra-server` |
| Igual | Niveles, perfiles, patron, cadencia, umbrales, k6 v1.3.0, generador en `vm-pruebas`, Cloud SQL y Cloud Storage | |

La prueba minima mide desde el cliente: no separa espera en cola de tiempo de
transcodificacion. Esas cifras, y la CPU y memoria de las instancias, vienen
de Cloud Monitoring con las ventanas de cada nivel.

---

## 6. Problemas frecuentes

| Sintoma | Causa / solucion |
|---|---|
| `seed.json tiene mas de 22 h` | Los tokens vencen a las 24 h: volver a correr `preparar_datos.sh`. |
| `falta media/...` | Copiar los archivos de la Entrega 2 o correr `generar_perfiles.sh` (seccion 2). |
| `AVISO: media/... no coincide con el SHA-256` | Los archivos no son los de la Entrega 2. Se puede correr, pero hay que declararlo. |
| `la API no responde en .../readyz` | Revisar el balanceador (`provision.sh resumen`) y que el certificado este `ACTIVE`. |
| Muchos `429` | Limite de tasa por usuario (`RATE_LIMIT_PER_MIN`). Subir `PROFESORES`/`ESTUDIANTES` en `preparar_datos.sh` o el limite en la plantilla; los 429 se cuentan aparte. |
| Cargas en `timeout` | Los workers no alcanzan en 15 min: es un resultado (saturacion), no un error del script. |
| `k6 termino con codigo 99` | Algun umbral no se cumplio. Es un resultado; queda en la tabla de umbrales del reporte. |
| El panel de :5665 no abre | Solo existe mientras k6 corre y hace falta el tunel SSH; el reporte final queda en `L<n>_reporte_k6.html`. |
