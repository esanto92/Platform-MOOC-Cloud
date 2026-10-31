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
