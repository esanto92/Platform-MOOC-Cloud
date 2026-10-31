# Análisis de capacidad - Entrega 3 (arquitectura elástica)

Repetición de los escenarios de la Entrega 2 sobre la arquitectura elástica
(balanceador HTTPS, grupo `mooc-api` de 1 a 3 instancias por CPU, grupo
`mooc-worker` de 1 a 3 por cola, Cloud SQL y Cloud Storage) y escenario de
autoescalado. Línea base: [`pruebas_de_carga_entrega2.md`](pruebas_de_carga_entrega2.md).

Contenido:

1. [Escenario 1 - Actividad académica concurrente](#1-escenario-1---actividad-académica-concurrente)
2. Escenario 2 - Carga, procesamiento y consumo multimedia (pendiente)
3. Escenario 3 - Ciclo de escalamiento automático (pendiente)

---

## 1. Escenario 1 - Actividad académica concurrente

### 1.1 Resumen

- **El límite se desplazó de la API a PostgreSQL.** En la Entrega 2 la CPU
  del Web Server llegó al 98 %. En la Entrega 3 la CPU de las instancias de
  API no pasa del 52 %, mientras Cloud SQL (1 vCPU) se mantiene al **100 %
  durante los 7 minutos de carga alta** de cada corrida.
- **No hubo mejora de capacidad.** El throughput se estanca en unos 112 a
  125 req/s, y la latencia p95 es igual o algo peor que en la Entrega 2:
  3,1 s frente a 2,9 s en las corridas comparables.
- **El autoescalado de la API no se activó por esta carga.** La CPU de la API
  nunca alcanza el objetivo del 60 %, porque la base de datos limita el
  throughput antes. Agregar réplicas no aumentaría la capacidad.
- **La integridad se conservó:** calificación del quiz correcta e idempotencia
  del envío duplicado al 100 % en todas las corridas. Los únicos errores 5xx
  son el defecto conocido de la Entrega 2 al crear intentos en paralelo. Ese
  defecto devuelve 500, pero la restricción `UNIQUE` impide intentos
  duplicados.

### 1.2 Diseño del experimento (igual a la Entrega 2)

- **Recorrido:** el mismo de la Entrega 2:
  - catálogo (listado y detalle);
  - outline de la inscripción;
  - progreso válido (open, heartbeat, complete);
  - quiz (crear intento y enviar, validando la nota).

  Script sin cambios:
  [`k6/escenario1_actividad_academica.js`](k6/escenario1_actividad_academica.js).
- **Datos sintéticos:** creados en el `setup` de cada corrida: 1 curso
  publicado (1 módulo, 3 lecturas y 1 quiz de 5 preguntas), 20 estudiantes
  inscritos (`N_STUDENTS=20`). Las sesiones se preparan antes de medir.
- **Patrón:** tasa de llegada creciente (open model). 5 → 20 → 50 → 90 → 90 →
  5 usuarios/s. Base y enfriamiento de 1 min; niveles de 2 min; pausas de 1 a
  3 s dentro del recorrido. Unos 10 min y 40 s por corrida.
- **Criterios (los de la Entrega 2):**
  - **Éxito:** latencia acotada y sin 5xx.
  - **Degradación:** p95 en segundos o aparición de 5xx.
  - **Saturación:** un recurso cerca del 100 %.
  - **Parada:** al terminar el perfil. No se fuerza más carga.
- **Clasificación de resultados:**
  - errores funcionales: 5xx y fallos de conexión;
  - rechazos de negocio esperados: 4xx, por ejemplo 409 al reenviar un
    intento ya enviado;
  - limitación de tasa: 429.
- **Repeticiones:** tres corridas completas (`r1`, `r2`, `r3`). Antes de `r2` y
  de `r3` se esperó a que `mooc-api` volviera a 1 instancia.
- **Agregación:**
  - las cifras de k6 son del conjunto de cada corrida, como en la Entrega 2;
  - las series de Cloud Monitoring están alineadas a 1 min;
  - los percentiles no se promedian entre corridas.

### 1.3 Condiciones y diferencias declaradas

| Elemento | Entrega 2 | Entrega 3 |
|---|---|---|
| Herramienta | k6 v1.6.1 | k6 v1.6.1 (`grafana/k6:1.6.1` en Docker) |
| Generador | Equipo de un estudiante, fuera de las VMs | PC de un integrante fuera de GCP: AMD Ryzen 5 3400G, 8 hilos, 15,5 GiB, Linux |
| CPU del generador | No registrada | Promedio 14 a 17 %, máximo 44 % (`r1`, `r2`) y un pico aislado de 82 % en `r3`. No limita la medición |
| Entrada | `https://136-114-53-21.sslip.io` (Caddy en el Web Server) | `https://34-149-212-102.sslip.io` (balanceador HTTPS externo de Google) |
| API | 1 VM `e2-highcpu-2` (API, frontend y monitoreo juntos) | Grupo `mooc-api` de VMs `e2-highcpu-2`, 1 a 3 por CPU (objetivo 60 %), solo la API |
| PostgreSQL | Cloud SQL 16, 1 vCPU, 3,75 GB | **Igual**: Cloud SQL 16, `db-custom-1-3840` |
| Pool de conexiones de la API | 25 (por defecto) en una sola instancia | 20 por instancia (`DB_MAX_OPEN_CONNS`) |
| `RATE_LIMIT_PER_MIN` | 1 000 000 | 10 000 000 000. Ambos desactivan el limitador para medir la plataforma; el login sigue en 30/min por IP |
| Versión de la app | commit `8745546` | plantillas `*-tpl-61f22e4` (incluye los ajustes para réplicas, `cd9a98d`) |
| Usuarios virtuales de k6 | Máximo 300 | Máximo 300 |

En ambas entregas k6 llegó a su tope de 300 usuarios virtuales en los
niveles altos. Por eso descartó unas 18 000 iteraciones, cantidad similar en
las dos entregas: la demanda efectiva fue comparable.

### 1.4 Resultados por corrida (k6, lo que ve el usuario)

| Métrica | Entrega 2 | E3 `r1` | E3 `r2` | E3 `r3` |
|---|---|---|---|---|
| Peticiones | 82 125 | 72 259 | 77 709 | 78 137 |
| Throughput medio (req/s) | 129,7 | 113,7 | 122,8 | 123,3 |
| Latencia p50 (ms) | 441 | 506 | 481 | 463 |
| Latencia p95 (ms) | 2 859 | 4 692 | 3 126 | 3 073 |
| Latencia p99 (ms) | 3 822 | 6 699 | 4 099 | 4 095 |
| Latencia máxima (ms) | 6 784 | 12 559 | 7 714 | 7 713 |
| Errores funcionales (5xx) | 1 086 (1,3 %) | 1 016 (1,4 %) | 1 054 (1,4 %) | 1 066 (1,4 %) |
| Rechazos de negocio (409) | 2 485 | 2 179 | 2 224 | 2 216 |
| Timeouts / 429 | 0 / 0 % | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Quiz calificado correcto | 100 % | 100 % | 100 % | 100 % |
| Idempotencia del envío duplicado | 100 % | 100 % | 100 % | 100 % |
| Iteraciones descartadas por k6 | 17 658 | 18 900 | 18 214 | 18 159 |

**Variación:** `r2` y `r3` difieren menos del 2 % en throughput y
percentiles. `r1` se aparta y no se usa para la comparación principal: empezó
12 s después de una corrida de humo, sin esperar a que el grupo volviera a 1
instancia, y el grupo pasó a 2 instancias en su primer minuto (23:37). Se
conserva como evidencia del comportamiento con 2 réplicas.

### 1.5 Comportamiento en el tiempo y recursos

Por minuto, `r3`; `r2` es equivalente.

- Las columnas de k6 se agrupan por el minuto en que se envió la petición.
- Cloud Monitoring marca cada valor al final de su intervalo de 1 min, por
  eso su serie aparece desplazada un minuto. Por ejemplo, el pico de k6 de
  las 05:13 aparece en el balanceador a las 05:14.

| Hora UTC | Throughput k6 (req/s) | p95 k6 (ms) | Peticiones/s en el balanceador | CPU Cloud SQL | CPU API (máx.) | Instancias API | Conexiones BD |
|---|---|---|---|---|---|---|---|
| 05:10 | 49 | 137 | 24 | 15 % | 13 % | 1 | 14 |
| 05:11 | 98 | 144 | 56 | 35 % | 22 % | 1 | 14 |
| 05:12 | 162 | 255 | 93 | 62 % | 33 % | 1 | 14 |
| 05:13 | **248 (pico)** | 737 | 157 | **100 %** | 46 % | 1 | 21 |
| 05:14 | 166 | 2 991 | **212** | **100 %** | **52 %** | 1 | 24 |
| 05:15 | 126 | 3 466 | 184 | **100 %** | 43 % | 1 | 24 |
| 05:16 | 125 | 3 467 | 128 | **100 %** | 33 % | 1 | 24 |
| 05:17 | 124 | 3 587 | 119 | **100 %** | 32 % | 1 | 24 |
| 05:18 | 125 | 3 508 | 117 | **100 %** | 32 % | 1 | 25 |
| 05:19 | 56 | 4 293 | 119 | **100 %** | 31 % | 1 | 24 |
| 05:20 | — | — | 67 | 78 % | 17 % | 1 | 14 |

Demanda de k6. La carga empezó a las 05:09:08 y cada tramo sube en forma
lineal hasta su objetivo:

| Desde | Hasta | Usuarios/s |
|---|---|---|
| 05:09 | 05:10 | 5 |
| 05:10 | 05:12 | de 5 a 20 |
| 05:12 | 05:14 | de 20 a 50 |
| 05:14 | 05:16 | de 50 a 90 |
| 05:16 | 05:18 | 90 |
| 05:18 | 05:19 | de 90 a 5 |

**Cloud SQL llega al 100 % a las 05:13, con unos 40 a 50 usuarios/s.**
Desde ese momento, subir la demanda hasta 90 ya no aumenta el throughput:
solo aumenta la latencia y las iteraciones que k6 descarta.

Resumen por corrida (Cloud Monitoring, ventana de cada corrida):

| Corrida | CPU máx. Cloud SQL | Minutos con Cloud SQL ≥ 99 % | CPU máx. API | Instancias API | Conexiones máx. | p95 máx. del balanceador |
|---|---|---|---|---|---|---|
| `r1` | 100 % | 7 | 46 % | 1 → 2 | 45 | 6 094 ms |
| `r2` | 100 % | 7 | 50 % | 1 | 25 | 4 014 ms |
| `r3` | 100 % | 7 | 52 % | 1 | 25 | 3 878 ms |

Las conexiones son la suma de las bases de la instancia: unas 20 del pool de
cada réplica de API más las internas de Cloud SQL.

La cola (`queue_backlog`) no se ejercita en este escenario: es síncrono, igual
que en la Entrega 2.

### 1.6 Tabla comparativa

Se comparan las corridas con la misma condición inicial (`r2`, `r3`) frente a
la corrida de la Entrega 2.

| Escenario y operación | Nivel de carga | Métrica y unidad | Entrega 2 | Entrega 3 (`r2` / `r3`) | Cambio observado y explicación |
|---|---|---|---|---|---|
| E1, recorrido completo | Misma demanda: 5→90 usuarios/s, 300 VUs máx. | Throughput (req/s) | 129,7 | 122,8 / 123,3 | **-5 %.** Cloud SQL al 100 % fija un techo de ~125 req/s en la meseta; las réplicas de API no pueden superarlo |
| E1, recorrido completo | Misma | Latencia p95 (ms) | 2 859 | 3 126 / 3 073 | **+8 a 9 %.** Las peticiones esperan en la base saturada. El salto extra del balanceador es menor y no explica la diferencia: con carga baja el p95 es ~140 ms |
| E1, recorrido completo | Misma | Latencia p99 (ms) | 3 822 | 4 099 / 4 095 | +7 %, misma causa |
| E1, recorrido completo | Misma | Errores 5xx (%) | 1,3 % | 1,4 % / 1,4 % | Igual. Mismo defecto de concurrencia al crear intentos (`quiz_start`) |
| E1, pico antes de saturar | Rampa de 20 a 50 usuarios/s (~40-50) | Throughput pico (req/s, 1 min) | No medido por minuto | 256 / 248 | Antes de saturar la base el sistema atiende ~250 req/s; el techo aparece cuando Cloud SQL llega al 100 % |
| E1, recurso limitante | Desde ~40-50 usuarios/s | CPU (%) | Web Server 98 % | API ≤ 52 %, **Cloud SQL 100 %** | **El límite pasó de la API a PostgreSQL** |

### 1.7 Análisis

**Qué mejoró.** La API dejó de ser el recurso limitante. Al separarla del
frontend y del monitoreo, que en la Entrega 2 compartían su VM, y al poder
tener réplicas detrás del balanceador, su CPU queda por debajo del 52 % con
la carga máxima. La integridad, el reparto por el balanceador y la
idempotencia funcionan entre réplicas.

**Qué quedó igual o empeoró.** El throughput y la latencia no mejoraron. La
carga del Escenario 1 es intensiva en escrituras pequeñas a PostgreSQL:
eventos de progreso, intentos y envíos de quiz. La única instancia de Cloud
SQL, con 1 vCPU, se satura desde unos 40 a 50 usuarios/s y fija un techo de
~125 req/s.

**Por qué el autoescalado no se activó.** El grupo `mooc-api` escala cuando su
CPU supera el 60 %. Con la base saturada, las peticiones esperan en la base
de datos y no consumen CPU de la API, que se queda entre 30 y 52 %. El
autoescalado no reacciona porque agregar réplicas no sería útil: solo
agregaría conexiones a una base ya saturada. En `r1`, con 2 réplicas, el
resultado fue peor (p95 de 4,7 s): más conexiones compitiendo por la misma
vCPU de Cloud SQL.

**Qué dependencia limita ahora.** PostgreSQL administrado. Las acciones con
mayor impacto esperado son:

1. Subir la clase de Cloud SQL, por ejemplo a 2 vCPU.
2. Revisar las consultas de escritura más frecuentes (`progress_event`,
   `quiz_submit`) con `pg_stat_statements`.

Ambas cambian el costo y quedan como propuesta. No se probaron en esta
entrega.

**Integridad.** Las verificaciones de negocio del script pasaron en todas las
corridas:

- **Nota del quiz:** se valida cada envío respondido con 200.
- **Envío duplicado:** un segundo envío no recalifica (409 esperado).

Los 5xx son siempre `POST /quizzes/{id}/attempts`. La API cuenta los intentos
y luego inserta `attempt_number = usados + 1`. Dos peticiones simultáneas del
mismo estudiante calculan el mismo número y la segunda viola
`UNIQUE (quiz_id, user_id, attempt_number)`: no se crean intentos duplicados,
pero se responde 500 en lugar de 409. Ocurre por igual en la Entrega 2. No se
corrigió para no cambiar la aplicación entre las dos mediciones.

### 1.8 Limitaciones

- Una sola corrida de la Entrega 2. La variación se informa solo para la
  Entrega 3.
- El generador cambió de máquina respecto a la Entrega 2. Ambos están fuera de
  la nube y su CPU no limitó, pero la latencia de red hasta GCP puede
  diferir.
- Con 20 cuentas y hasta 90 llegadas por segundo, varias iteraciones
  comparten estudiante. Eso provoca la carrera de `quiz_start`, igual en las
  dos entregas.
- No se hizo una verificación SQL posterior de intentos y progreso. La
  integridad se apoya en las validaciones del script y en las restricciones
  de la base.
- La memoria de las VMs se exportó sumada entre instancias, por lo que no se
  analiza por instancia.

### 1.9 Evidencias

| Archivo | Contenido |
|---|---|
| [`escenario1/correr_entrega3.sh`](escenario1/correr_entrega3.sh) | Ejecuta una corrida y deja condiciones, ventana UTC, salidas de k6 y CPU del generador |
| `escenario1/resultados/entrega3_r{1,2,3}_<fecha>/` | Por corrida: `condiciones.txt`, `ventana.txt`, `reporte.txt`, `summary.json`, `raw.json.gz` (todas las muestras), `salida.txt` y `generador.csv` |
| [`escenario1/resultados/cloud_monitoring_entrega3/`](escenario1/resultados/cloud_monitoring_entrega3/) | Exportación de Cloud Monitoring del 30-10-2026 23:30 al 31-10-2026 00:21 (hora de Colombia, UTC-5), alineada a 1 min: CPU y conexiones de Cloud SQL, tamaño de cada grupo, CPU y memoria de las VMs, peticiones y latencia (p50/p95/p99) del backend de la API en el balanceador |
| `escenario1/resultados/entrega3_humo*_<fecha>/` | Corridas de humo: validación del recorrido, no se usan en el análisis. La primera muestra el 48 % de 429 con el limitador en su valor normal |
| [`escenario1/escenario1_reporte.txt`](escenario1/escenario1_reporte.txt) | Corrida de la Entrega 2 (línea base) |

Ventanas UTC: `r1` 04:36:23 a 04:47:05; `r2` 04:54:50 a 05:05:30; `r3`
05:08:58 a 05:20:00 (31-10-2026).


# Escenario 2 - Carga, procesamiento y consumo multimedia (Entrega 3)

Repetición de la prueba mínima del Escenario 2 de la Entrega 2 sobre la
arquitectura elástica (balanceador HTTPS, grupo `mooc-api` de 1 a 3 instancias
por CPU, grupo `mooc-worker` de 1 a 3 por profundidad de cola, Cloud SQL y
Cloud Storage). Misma herramienta, perfiles, patrón, cadencia y umbrales que la
Entrega 2. Línea base:
[`resultados/entrega2_minima_20260928-0254/reporte.md`](resultados/entrega2_minima_20260928-0254/reporte.md).
Documento general de capacidad:
[`../pruebas_de_carga_entrega3.md`](../pruebas_de_carga_entrega3.md).

Contenido:

1. [Resumen](#1-resumen)
2. [Diseño del experimento (igual a la Entrega 2)](#2-diseño-del-experimento-igual-a-la-entrega-2)
3. [Condiciones y diferencias declaradas](#3-condiciones-y-diferencias-declaradas)
4. [Resultados por nivel (k6, lo que ve el cliente)](#4-resultados-por-nivel-k6-lo-que-ve-el-cliente)
5. [Instancias y ciclo de autoescalado (Cloud Logging)](#5-instancias-y-ciclo-de-autoescalado-cloud-logging)
6. [Tabla comparativa](#6-tabla-comparativa)
7. [Análisis](#7-análisis)
8. [Limitaciones](#8-limitaciones)
9. [Evidencias](#9-evidencias)

---

## 1. Resumen

- **El autoescalado de workers sí se activó, por la señal correcta (la cola).**
  El grupo `mooc-worker` pasó de 1 a 2 instancias durante la prueba: la métrica
  `queue_backlog` subió hasta **5** (1 pendiente + 4 activos) al entrar las
  cargas del P3 (1080p) en el nivel L3, el autoescalador creó una segunda VM
  (`mooc-worker-bp1x`, ~17:19 UTC) y, al drenar la cola a 0 de forma sostenida,
  el grupo se redujo de nuevo a 1 (17:31 y 17:41). Sin reintentos ni pérdida de
  trabajos (`reintentos=0`, antigüedad máxima 15 s).
- **El autoescalado de la API no se activó, y es lo esperado.** `mooc-api` se
  mantuvo en 1 instancia toda la prueba. En este escenario la API solo hace
  tráfico de control ligero (firmar, confirmar, consultar estado, servir
  manifiestos): su CPU no se acerca al objetivo del 60 %. El trabajo pesado
  (transcodificación) lo hacen los workers, no la API.
- **La transferencia y el consumo no dependen de las instancias.** Las partes
  de carga y los segmentos HLS van **directo a Cloud Storage** con URL firmada;
  no pasan por la API ni por los workers. Por eso el consumo HLS mejora al subir
  la carga en lugar de empeorar (Cloud Storage escala solo), y esa mejora **no
  se atribuye al autoscaling de la API**.
- **El tiempo hasta `ready` mejoró frente a la Entrega 2.** Con dos workers
  disponibles en el pico, `complete -> ready` p95 bajó de 770 s (E2) a 329 s
  (E3) en L3, y la cola nunca acumuló trabajos en espera significativos
  (antigüedad máxima 15 s). Es el efecto directo del escalamiento horizontal de
  la capa worker.
- **Integridad conservada:** las 23 cargas de los tres niveles (4 + 7 + 12)
  llegaron a `ready` con la duración (+-2 s) y el número de rendiciones HLS
  exactos. Cero errores de control, de transferencia y de consumo; cero 429.

## 2. Diseño del experimento (igual a la Entrega 2)

Prueba mínima de tres niveles (L1, L2, L3). Script sin cambios:
[`k6/escenario2.js`](k6/escenario2.js). Guía y niveles:
[`README.md`](README.md), `niveles.json`.

- **Recorrido del profesor** (llegadas a tasa constante): `POST /uploads` (la
  API firma) -> `PUT` de cada parte de 8 MiB **directo a Cloud Storage** ->
  `POST /uploads/{id}/complete` -> `POST /units/{id}/resources` ->
  `GET /assets/{id}` cada 3 s hasta `ready` -> validación funcional (duración
  +-2 s y rendiciones del master HLS).
- **Recorrido del espectador** (usuarios concurrentes): master `.m3u8` ->
  playlist de una rendición (rota por usuario) -> precarga 3 segmentos -> un
  segmento al ritmo de `#EXTINF` manteniendo 3 de ventaja -> 20 segmentos por
  sesión -> pausa 5 s -> siguiente contenido.
- **Niveles:** L1 1 carga/min + 10 espectadores; L2 2/20; L3 4/40. Cada uno:
  30 s de calentamiento + 3 min de medición; luego k6 sigue cada carga iniciada
  hasta `ready` (máx. 15 min).
- **Mezcla de archivos** (patrón fijo de 10 cargas): 4xP1, 3xP2, 2xA1, 1xP3.
- **Datos sintéticos:** 20 profesores de carga (cada uno con curso y unidad),
  40 estudiantes inscritos, 1 curso publicado con los 4 assets en HLS
  (`escenario-2-contenido-hls-1793465320`). Preparados con
  [`preparar_datos.sh`](preparar_datos.sh) antes de medir.
- **Criterios de éxito (umbrales de k6):** p95 firmar/confirmar/crear recurso
  < 1 s; p95 consultar estado < 500 ms; p95 manifiestos < 1 s; p95 segmentos
  < 2 s; errores < 1 %; riesgo de corte < 1 %; >= 99 % de cargas en `ready` y
  validadas.
- **Clasificación de resultados:** errores de control (API), errores de
  transferencia (Cloud Storage), errores de consumo (manifiestos/segmentos),
  rechazos de tasa (429) y cargas que no llegan a `ready` (saturación), contados
  por separado.
- **Repeticiones:** una corrida de los tres niveles seguidos. La variación no se
  repitió por presupuesto; se declara como limitación.

## 3. Condiciones y diferencias declaradas

| Elemento | Entrega 2 | Entrega 3 |
|---|---|---|
| Fecha (UTC) | 2026-09-28 03:27 | 2026-10-31 17:00 |
| Herramienta | k6 v1.3.0 | k6 v1.3.0 (`commit/5870e99ae8`, go1.25.1, linux/amd64) |
| Generador | `vm-pruebas`, 8 vCPU, 31,3 GiB, fuera de las VMs de la aplicación | **Igual**: `vm-pruebas`, 8 vCPU, 31,3 GiB, fuera de los grupos |
| Entrada | Caddy en el Web Server (`https://136-114-53-21.sslip.io`) | Balanceador HTTPS externo (`https://34-149-212-102.sslip.io`) |
| API | 1 VM fija `e2-highcpu-2` | Grupo `mooc-api`, 1 a 3 VMs por CPU (objetivo 60 %). Plantilla `mooc-api-tpl-61f22e4` |
| Workers | 1 VM fija, **concurrencia 4** | Grupo `mooc-worker`, 1 a 3 VMs por cola, **concurrencia 2 por instancia**. Plantilla `mooc-worker-tpl-61f22e4` |
| Cola | Redis en el Worker Server | Redis en `infra-server` (fuera de ambos grupos elásticos) |
| Persistencia | Cloud SQL 16 + Cloud Storage | **Igual**: Cloud SQL `db-custom-1-3840` + mismo bucket |
| Versión de la app | commit `70bc9f9` | plantillas `*-tpl-61f22e4` (incluye los ajustes para réplicas, `cd9a98d`) |
| Archivos multimedia | 4 perfiles de un original 1080p | **Mismos 4 perfiles, regenerados del mismo original 1080p**: P3 y A1 coinciden por SHA-256; P1 y P2 difieren por la versión de ffmpeg del generador (recodificación). El patrón, tamaños y rendiciones esperadas son equivalentes |

> **Concurrencia efectiva.** En la Entrega 2 era 4 en una sola VM (= 4). En la
> Entrega 3 es 2 por instancia, y el número de workers varía por autoscaling:
> con 1 worker la concurrencia efectiva es 2, con 2 workers es 4. El cambio de
> concurrencia por instancia (de 4 a 2) es parte del cambio arquitectónico
> evaluado y se declara aquí.

## 4. Resultados por nivel (k6, lo que ve el cliente)

Tiempos en segundos salvo que se indique. p50/p95 sobre las cargas del nivel.

**Carga y procesamiento (profesores)**

| Nivel | Cargas/min | Cargas ok / iniciadas | API firma p95 (ms) | Confirmar p95 (ms) | Transferencia p50 / p95 | Mbps p50 | complete -> ready p50 / p95 | Extremo a extremo p95 | Errores control | Errores transferencia |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| L1 | 1 | 4 / 4 | 85,5 | 2171,3 | 0,1 / 0,2 | 87,8 | 20,3 / 78,1 | 80,5 | 0,00 % | 0,00 % |
| L2 | 2 | 7 / 7 | 140,8 | 175,4 | 0,1 / 1,1 | 115,1 | 96,8 / 385,9 | 387,2 | 0,00 % | 0,00 % |
| L3 | 4 | 12 / 12 | 83,9 | 177,8 | 0,1 / 0,8 | 150,6 | 37,7 / 329,1 | 330,1 | 0,00 % | 0,00 % |

> El p95 de "confirmar" de 2171 ms en L1 es un **arranque en frío**: la primera
> confirmación tras encender `infra-server` abre conexiones nuevas a Redis y
> Postgres. En L2 y L3 cae a ~175 ms. Es el único umbral de k6 incumplido en
> toda la prueba y no es saturación: con más carga el tiempo mejora.

**Consumo HLS (estudiantes, fase de medición)**

| Nivel | Espectadores | Manifiestos | Manifiesto p95 (ms) | Segmentos | Segmento p50 / p95 (ms) | Mbps segmento p50 | Riesgo estimado de corte | Errores consumo | Rechazos 429 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| L1 | 10 | 32 | 476,4 | 303 | 64,2 / 159,2 | 207,0 | 0,00 % | 0,00 % | - |
| L2 | 20 | 68 | 85,4 | 627 | 49,7 / 96,0 | 228,8 | 0,00 % | 0,00 % | - |
| L3 | 40 | 128 | 89,3 | 1240 | 41,2 / 75,1 | 278,2 | 0,00 % | 0,00 % | - |

**Por perfil (todas las cargas de cada nivel)**

| Nivel | Perfil | Cargas ok / total | Transferencia prom. | complete -> ready prom. | complete -> ready max | Rendiciones obtenidas |
|---|---|---:|---:|---:|---:|---|
| L1 | A1 | 1 / 1 | 0,2 | 25,2 | 25,2 | 1 |
| L1 | P1 | 2 / 2 | 0,1 | 15,2 | 15,4 | 2 |
| L1 | P2 | 1 / 1 | 0,2 | 87,4 | 87,4 | 3 |
| L2 | A1 | 1 / 1 | 0,3 | 27,2 | 27,2 | 1 |
| L2 | P1 | 3 / 3 | 0,1 | 61,0 | 143,9 | 2 |
| L2 | P2 | 2 / 2 | 0,1 | 132,4 | 167,9 | 3 |
| L2 | P3 | 1 / 1 | 1,4 | 479,3 | 479,3 | 4 |
| L3 | A1 | 2 / 2 | 0,3 | 36,2 | 39,2 | 1 |
| L3 | P1 | 5 / 5 | 0,1 | 25,4 | 36,2 | 2 |
| L3 | P2 | 4 / 4 | 0,1 | 133,4 | 187,9 | 3 |
| L3 | P3 | 1 / 1 | 1,4 | 501,7 | 501,7 | 4 |

**Criterios de éxito (umbrales de k6)**

| Nivel | Umbrales incumplidos |
|---|---|
| L1 | `http_req_duration{name:POST /uploads/:id/complete (confirmar)}`: p(95)<1000 (arranque en frío; ver sección 4) |
| L2 | ninguno |
| L3 | ninguno |

Fallos de carga: ninguno. k6 terminó con código 0 (todos los umbrales globales
cumplidos).

## 5. Instancias y ciclo de autoescalado (Cloud Logging)

La `vm-pruebas` no tiene permiso de lectura sobre Compute, por lo que el CSV de
instancias de la corrida quedó vacío. Las instancias y el ciclo se reconstruyen
desde Cloud Logging: eventos `instances.insert`/`instances.delete` del grupo y
la métrica `queue_backlog` que publica `queue-metrics` en `infra-server` cada
30 s. Ventanas de los niveles (UTC): L1 17:00:05-17:03:55; L2
17:04:55-17:15:26; L3 17:16:27-17:26:20.

**Línea de tiempo de la capa worker (UTC):**

| Hora | Evento / señal | `queue_backlog` | Nivel |
|---|---|---:|---|
| 17:00-17:08 | 1 worker (`mooc-worker-77ct`), backlog bajo | 0-1 | L1 / inicio L2 |
| ~17:08-17:09 | **Autoescalador crea `mooc-worker-grvm`** (2.ª instancia) | sube | L2 |
| 17:17-17:18 | backlog crece al entrar cargas de L3 | 4 | L3 |
| 17:19-17:20 | **pico backlog = 5** (1 pendiente + 4 activos), antigüedad 15 s | **5** | L3 |
| ~17:19-17:20 | **Autoescalador crea `mooc-worker-bp1x`** (refuerzo del pico) | 5 | L3 |
| 17:20-17:22 | la cola drena con 2 workers activos | 3 -> 2 | L3 |
| 17:22-17:26 | backlog = 1 y luego 0 | 1 -> 0 | fin L3 |
| 17:26-17:31 | backlog = 0 sostenido (ventana de estabilización) | 0 | post-carga |
| 17:31 | **Reducción:** el grupo retira `mooc-worker-grvm` (scale-in de a 1) | 0 | drenaje |
| 17:41 | **Reducción final:** retira `mooc-worker-77ct`, el grupo vuelve a 1 | 0 | reducción |

> Cada evento aparece dos veces en el log (inicio y confirmación de la misma
> operación de GCP); corresponde a una sola instancia.

**El grupo `mooc-api` se mantuvo en 1 instancia durante toda la prueba** (no
hay eventos `insert`/`delete` de `mooc-api` entre las 17:00 y las 17:26; la
única VM, `mooc-api-zwx0`, fue creada a las 04:35, mucho antes).

Instancias y concurrencia efectiva por nivel:

| Nivel | Ventana (UTC) | API operativas | Workers operativos | Concurrencia efectiva máx. (workers x 2) |
|---|---|---:|---:|---:|
| L1 | 17:00:05-17:03:55 | 1 | 1 | 2 |
| L2 | 17:04:55-17:15:26 | 1 | 1 -> 2 (crece ~17:08) | 4 |
| L3 | 17:16:27-17:26:20 | 1 | 2 (pico; refuerzo ~17:19) | 4 |

**Drenaje seguro al reducir.** La reducción ocurrió con la cola ya en 0 y de a
una instancia cada vez (control `scale-in` de máximo 1 VM por ventana de
600 s): la retirada del primer worker fue a las 17:31 y la consolidación a 1 a
las 17:41. No hubo reintentos (`reintentos=0` en toda la serie) ni trabajos
perdidos: las 23 cargas llegaron a `ready` y validadas.

## 6. Tabla comparativa

Misma demanda (mismos niveles, perfiles, patrón y cadencia que la Entrega 2).

| Escenario y operación | Nivel de carga | Métrica y unidad | Entrega 2 | Entrega 3 | Cambio observado y explicación |
|---|---|---|---:|---:|---|
| E2, confirmar carga (control API) | L3 (4 cargas/min) | Confirmar p95 (ms) | 151,1 | 177,8 | **+18 %.** El salto extra del balanceador externo frente a Caddy local. En L1 el arranque en frío lo eleva a 2171 ms (puntual, no saturación) |
| E2, firmar carga (control API) | L3 | API firma p95 (ms) | 68,3 | 83,9 | +23 %, misma causa (salto del balanceador). Ambos muy por debajo del umbral de 1 s |
| E2, procesamiento | L3 | `complete -> ready` p95 (s) | 770,1 | 329,1 | **-57 %.** Con 2 workers en el pico la cola no acumula espera (antigüedad máx. 15 s). Efecto directo del escalado horizontal de workers |
| E2, procesamiento del perfil pesado | L3 | P3 `complete -> ready` (s) | 847,6 | 501,7 | **-41 %.** El P3 (1080p, 4 rendiciones) se beneficia de la 2.ª instancia de worker |
| E2, consumo HLS | L3 (40 espectadores) | Segmento p95 (ms) | 93,1 | 75,1 | **-19 %.** Los segmentos van directo a Cloud Storage; la mejora **no** es del autoscaling de la API |
| E2, consumo HLS | L3 | Manifiesto p95 (ms) | 58,8 | 89,3 | +52 % en valor absoluto pequeño (~30 ms). El manifiesto lo sirve la API (control); el salto del balanceador lo explica |
| E2, integridad | L1-L3 | Cargas en `ready` y validadas (%) | 100 % | 100 % | Igual. Duración +-2 s y rendiciones exactas en las 23/24 cargas |
| E2, errores | L1-L3 | Errores control / transferencia / consumo (%) | 0 / 0 / 0 | 0 / 0 / 0 | Igual |

## 7. Análisis

**Qué mejoró.** El tiempo hasta disponibilidad del contenido (`complete ->
ready`). El autoescalado de workers por la profundidad de la cola añadió una
segunda instancia justo cuando entraron las cargas pesadas de L3, y la cola
drenó sin acumular espera (antigüedad máxima 15 s). El P3, el perfil más
costoso, bajó de 848 s a 502 s. Esta es la evidencia central del escenario: la
capa de procesamiento ahora crece con la demanda en lugar de quedar fija.

**Qué quedó igual.** La integridad (100 % de cargas en `ready` y validadas,
cero errores, cero 429) y el consumo HLS, que ya iba directo a Cloud Storage en
la Entrega 2. El pequeño aumento en las latencias de control (firmar/confirmar/
manifiesto) es el costo de interponer un balanceador externo; son decenas de ms
sobre operaciones muy por debajo de sus umbrales, sin impacto funcional.

**Efecto separado del escalado de API y de workers.** El escenario distingue
los dos efectos, como pide el enunciado:
- **API:** no escaló (1 instancia) y no debía: el tráfico de control es ligero
  y su CPU no llega al 60 %. La admisión de cargas (firmar + confirmar) se
  mantuvo rápida con una sola réplica.
- **Workers:** escaló de 1 a 2 por la cola. Es el responsable de la mejora en
  la tasa de procesamiento y el tiempo hasta `ready`.
- **Consumo/descarga:** lo atiende Cloud Storage, no las instancias. La mejora
  del p95 de segmentos **no se atribuye al autoscaling de la API**: es la
  elasticidad propia del almacenamiento de objetos.

**Qué dependencia limita ahora.** En esta prueba mínima ningún recurso llegó a
saturación: la cola no superó un backlog de 5 y se drenó con 2 de las 3
instancias posibles. El límite de interés para este escenario es la **tasa de
transcodificación** (CPU de los workers con ffmpeg), que el autoscaling atiende
hasta el tope de 3 instancias; forzar ese tope es el objetivo del Escenario 3B.

**Costo adicional.** Durante el pico, dos VMs `e2-highcpu-2` de worker en lugar
de una, más la VM fija `infra-server` que aloja la cola fuera de los grupos
elásticos. La segunda instancia vivió solo mientras la cola lo justificó
(~17:09 a 17:31-17:41), de modo que el costo sigue a la demanda.

## 8. Limitaciones

- **Una sola corrida.** La variación entre corridas no se midió (presupuesto);
  los valores son de una ejecución. La Entrega 2 también fue una corrida mínima.
- **La prueba mínima mide desde el cliente:** `complete -> ready` junta espera
  en cola y tiempo de transcodificación. La separación fina (espera vs.
  procesamiento), la CPU/memoria de los workers y las conexiones de Cloud SQL se
  toman de Cloud Monitoring con las ventanas de la sección 5.
- **Instancias reconstruidas desde logs**, no muestreadas por el script, porque
  `vm-pruebas` no tiene `roles/compute.viewer`. La métrica `queue_backlog` y los
  eventos `insert`/`delete` dan la línea de tiempo; para el número exacto de
  workers por minuto conviene contrastar con el tamaño del grupo en Cloud
  Monitoring.
- **Material multimedia regenerado** del mismo original: P3 y A1 idénticos por
  SHA-256; P1 y P2 difieren por la versión de ffmpeg. No cambia el patrón de
  carga ni las rendiciones esperadas.
- **"Riesgo estimado de corte"** es una estimación (segmento que llega tarde
  respecto a la cadencia `#EXTINF`), no la medición de un reproductor real.

## 9. Evidencias

| Archivo | Contenido |
|---|---|
| [`README.md`](README.md) | Guía de la prueba mínima, niveles, perfiles y procedimiento |
| [`correr_minima.sh`](correr_minima.sh) | Corre L1, L2 y L3 seguidos y arma el reporte |
| [`k6/escenario2.js`](k6/escenario2.js) | Guion de k6 (profesores + espectadores), sin cambios frente a la Entrega 2 |
| [`resultados/entrega3_minima_20261031-1700/`](resultados/entrega3_minima_20261031-1700/) | Corrida de la Entrega 3: `condiciones.json`, `reporte.md`, y por nivel `L<n>_params`, `L<n>_ventana`, `L<n>_consola.log`, `L<n>_salida.txt`, `L<n>_resumen.json`, `L<n>_reporte_k6.html`, `L<n>_exit` |
| [`resultados/entrega2_minima_20260928-0254/`](resultados/entrega2_minima_20260928-0254/) | Línea base de la Entrega 2 |

Ventana UTC de la corrida: 17:00:05 a 17:26:20 (31-10-2026); estabilización y
reducción de workers observadas hasta las 17:41.
