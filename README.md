# Plataforma MOOC

## ***VIDEO SUSTENTACIÓN ENTREGA 4:***  [MOOC Platform - Entrega 4]([ ](https://youtu.be/UKYf_Q5Nzx4))

Plataforma de cursos masivos abiertos en linea (MOOC).
Backend en Go (monolito modular + workers asincronos) y frontend Next.js (BFF),
todo en contenedores. En la nube corre sobre **Cloud Run** con **Cloud
Pub/Sub** para las tareas asincronas.

> La documentacion detallada de la arquitectura y de cada archivo esta en
> [`docs/entrega1/DOCUMENTACION.md`](docs/entrega1/DOCUMENTACION.md).
>
> **Despliegue local completo (backend + frontend) con un solo comando:**
> `docker compose up --build` levanta la API, los workers, el frontend y todas
> las dependencias. El **frontend queda en http://localhost:3001**.

## Documentacion por entrega

| Que | Donde |
|---|---|
| Arquitectura logica, documentacion de cada archivo y credenciales locales (Entrega 1) | [`docs/entrega1/`](docs/entrega1/) (`ARQUITECTURA.md`, `DOCUMENTACION.md`, `CREDENCIALES.md`) |
| Arquitectura del despliegue en GCP (Entrega 2) | [`docs/entrega2/README.md`](docs/entrega2/README.md) |
| Informe de capacidad (Entrega 2) | [`capacity-planning/pruebas_de_carga_entrega2.md`](capacity-planning/pruebas_de_carga_entrega2.md) |
| Aprovisionamiento, compose por VM y migracion | [`deploy/gcp/`](deploy/gcp/) |
| **Arquitectura elastica desplegada (Entrega 3)**: grupos, balanceador, autoescalado, operacion, costos | [`docs/entrega3/arquitectura.md`](docs/entrega3/arquitectura.md) |
| Verificacion funcional del frontend (Entrega 3): matriz de recorridos y rutas | [`docs/entrega3/FuncionalidadFront/verificacion-frontend.md`](docs/entrega3/FuncionalidadFront/verificacion-frontend.md) |
| Informe de capacidad (Entrega 3): escenarios 1, 2, 3A y 3B | [`capacity-planning/pruebas_de_carga_entrega3.md`](capacity-planning/pruebas_de_carga_entrega3.md) |
| Deuda tecnica y calidad (Entrega 3): linea base y reportes de SonarQube | [`docs/entrega3/deuda-tecnica.md`](docs/entrega3/deuda-tecnica.md), [`docs/entrega3/calidad/`](docs/entrega3/calidad/) |
| Guia de trabajo de los grupos de instancias | [`docs/entrega3/guia-mig.md`](docs/entrega3/guia-mig.md) |
| Prueba automatica de accesibilidad WCAG 2.2 AA (Entrega 3) | [`docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/README.md`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/README.md) |
| Ultimo reporte de accesibilidad | [`docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/resultados/REPORTE.md`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/resultados/REPORTE.md) |
| Convenciones de accesibilidad del frontend | [`frontend/README.md`](frontend/README.md), seccion "Accesibilidad (WCAG 2.2 AA)" |
| URL del frontend y del balanceador (Entrega 3) | https://34-149-212-102.sslip.io y `/api/v1` (fuera de servicio: los grupos de instancias quedaron en 0 al pasar a Cloud Run) |
| Video de sustentacion (Entrega 3) | [MOOC Platform - Entrega 3](https://www.youtube.com/watch?v=WBGPFwUp3Dk) |
| **Despliegue en Cloud Run y Pub/Sub (Entrega 4)**: servicios, red, secretos, Pub/Sub, escalamiento | [`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md) |
| Script de despliegue en Cloud Run (Entrega 4) | [`deploy/gcp/cloudrun.sh`](deploy/gcp/cloudrun.sh) |
| Script de verificacion de configuracion (Entrega 4) | [`deploy/gcp/verificar-e4.sh`](deploy/gcp/verificar-e4.sh) |
| Script y reporte de escalamiento (Entrega 4) | [`deploy/gcp/escalamiento-e4.sh`](deploy/gcp/escalamiento-e4.sh), [`docs/entrega4/resultados-escalamiento/`](docs/entrega4/resultados-escalamiento/) |
| URL del frontend (Entrega 4, Cloud Run) | https://mooc-web-mhuknn2hva-uc.a.run.app |
| URL del backend (Entrega 4, Cloud Run) | https://mooc-api-mhuknn2hva-uc.a.run.app/api/v1 (estado en `/readyz`) |

Las credenciales de la nube se entregan al equipo docente por el canal privado
del curso, nunca en este repositorio.

## Arquitectura actual (despliegue en Google Cloud)

La arquitectura vigente es la de la Entrega 4 (Cloud Run + Cloud Pub/Sub),
descrita en [`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md):

- tres servicios de **Cloud Run** (`mooc-web`, `mooc-api`, `mooc-worker`),
  cada uno con escalamiento automatico de 0 a 3 instancias;
- **Cloud Pub/Sub**: la API publica las tareas en un topic y una suscripcion
  push autenticada (token OIDC) las entrega al worker, que confirma tras
  persistir. Redis sigue en `infra-server` para la cache de sesiones, el
  limite de tasa y las llaves de idempotencia, pero ya no es la cola (el
  modo asynq/Redis se usa en el entorno local);
- **Direct VPC egress** desde Cloud Run hacia Cloud SQL y `infra-server`;
- secretos en **Secret Manager**;
- Cloud SQL y Cloud Storage (sin cambios).

La arquitectura elastica con MIG y balanceador de la Entrega 3 se conserva en
[`docs/entrega3/arquitectura.md`](docs/entrega3/arquitectura.md), y la de dos
VMs fijas de la Entrega 2 en [`docs/entrega2/`](docs/entrega2/README.md), como
lineas base historicas.

Despliegue y verificacion en la nube (detalle en la seccion 8 de
[`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md)):

```bash
export PROJECT=dsc-uniandes-20262
./deploy/gcp/build.sh api web worker
./deploy/gcp/cloudrun.sh apis red secretos
./deploy/gcp/migrate.sh migrate-e4                       # desde una VM dentro de mooc-vpc
./deploy/gcp/cloudrun.sh worker pubsub api web resumen
./deploy/gcp/verificar-e4.sh
```

No hace falta tener Go instalado: la compilacion ocurre dentro de Docker.

## Puesta en marcha

```bash
cp .env.example .env
make deps          # genera go.sum (go mod tidy en un contenedor Go)
docker compose up --build
```

La primera vez tarda varios minutos: descarga las imagenes y compila los dos
binarios de Go.

Cuando todo este arriba:

| Servicio               | URL                              | Credenciales        |
|------------------------|----------------------------------|---------------------|
| **Frontend (app web)** | http://localhost:3001            | ver admin abajo     |
| API (health)           | http://localhost:8080/healthz    | —                   |
| **Swagger UI (API docs)** | http://localhost:8080/docs    | —                   |
| Spec OpenAPI (crudo)   | http://localhost:8080/openapi.yaml | —                 |
| Bandeja de correo      | http://localhost:8025            | —                   |
| Consola de MinIO       | http://localhost:9001            | minioadmin / minioadmin |
| Prometheus             | http://localhost:9090            | —                   |
| Grafana                | http://localhost:3000            | admin / admin       |
| **Jaeger (trazas)**    | http://localhost:16686           | —                   |
| PostgreSQL             | localhost:5433                   | mooc / mooc         |

> El **frontend** (Next.js como BFF) es la única puerta de entrada para el
> navegador: habla con la API por la red interna de Docker (`api:8080`), nunca
> directo desde el cliente. Se publica en **3001** porque Grafana ya ocupa el
> 3000 en el host.

Administrador inicial: `admin@mooc.local` / `Admin123!`
(lo crea la API al arrancar a partir de `ADMIN_EMAIL` y `ADMIN_PASSWORD`).

## Prueba de humo

```bash
./docs/entrega1/testdata/smoke.sh
```

Recorre el flujo completo: crear profesor, armar el curso, publicarlo,
registrar un estudiante, inscribirlo, reportar progreso, presentar el quiz y
verificar la insignia. De paso comprueba tres condiciones de la rubrica:
el rechazo del porcentaje enviado por el cliente, la idempotencia del envio
del quiz y el aislamiento entre estudiantes.

## Prueba de accesibilidad

```bash
"./docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/ejecutar.sh"
```

Auditoria automatica WCAG 2.2 AA con Playwright + axe-core. Corre por completo
dentro de la imagen oficial de Playwright, conectada a la red de Docker
Compose: no instala nada en la maquina ni modifica la API. Recorre 19 paginas
de los cuatro roles (anonimo, estudiante, profesor, administrador) en tema
claro y oscuro, y aprueba solo si ninguna tiene incumplimientos `critical` o
`serious`. Requiere el proyecto levantado y los datos que deja la prueba de
humo. El reporte queda en
[`resultados/REPORTE.md`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/resultados/REPORTE.md); la ultima
ejecucion (2026-10-24) aprobo las 38 auditorias. Paso a paso en
[`docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/README.md`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/README.md).

## Comandos frecuentes

```bash
make up                     # levantar
make down                   # detener (conserva datos)
make reset                  # detener y BORRAR volumenes
make logs                   # seguir logs de api y worker
make psql                   # consola SQL
docker compose up --scale worker=3   # tres workers
docker compose up -d --build --no-deps web   # reconstruir solo el frontend sin tocar lo demas
```

> **Importante:** `db/init.sql` solo se ejecuta la primera vez que se crea el
> volumen de Postgres. Si lo modificas, ejecuta `make reset` antes de volver a
> levantar.

## Arquitectura en una pantalla

```
                          Internet (HTTPS *.run.app)
                                      │
  ┌─ Cloud Run (us-central1, max. 3 instancias por servicio) ─────────────┐
  │  mooc-web (Next.js BFF) ── HTTPS + Bearer ──▶ mooc-api (Go)           │
  │                                                 │ publica tareas      │
  │                                                 ▼                     │
  │                        Cloud Pub/Sub (topic + suscripcion push OIDC)  │
  │                                                 │ push autenticado    │
  │                                                 ▼                     │
  │                                    mooc-worker (Go + ffmpeg, interno) │
  └───────────────┬──────────────────────┬───────────────────┬────────────┘
                  │ Direct VPC egress    │                   │ firma URLs (HMAC)
                  ▼                      ▼                   ▼
          Cloud SQL (PG 16)      infra-server           Cloud Storage
          IP privada + TLS       Redis · Mailpit        (bucket privado)
                                                             ▲
         Navegador ── PUT/GET directo con URL firmada ───────┘
```

| Componente | Donde corre | Responsabilidad |
|---|---|---|
| **Frontend / BFF** (`frontend/`) | Cloud Run `mooc-web` | Interfaz web. Guarda el token en una cookie HttpOnly y llama a la API del lado del servidor con `Authorization: Bearer`. |
| **API** (`cmd/api`) | Cloud Run `mooc-api` | Autenticacion con tokens opacos, autoria versionada, inscripciones, progreso calculado en servidor, calificacion de quizzes, emision de URLs firmadas y publicacion de tareas en Pub/Sub. Sin estado; nunca transcodifica. |
| **Cloud Pub/Sub** | Administrado | Topic `mooc-tasks` y suscripcion push `mooc-tasks-push` con token OIDC. Reentrega lo que no se confirma. |
| **Worker** (`cmd/worker`) | Cloud Run `mooc-worker` | Recibe cada tarea por push y confirma tras persistir: antimalware (stub EICAR), transcodificacion HLS con ffmpeg, insignias y correo. Solo lo invoca la identidad de la suscripcion. |
| **Redis** | `infra-server` | Cache de sesiones, limite de tasa y llaves de idempotencia. No es la cola. |
| **Mailpit** | `infra-server` | Captura del correo saliente. |
| **Cloud SQL** | Administrado | PostgreSQL 16, fuente de verdad. IP privada y TLS obligatorio. |
| **Cloud Storage** | Administrado | Originales, derivados HLS e insignias. El cliente sube y descarga directamente con URLs firmadas. |

Principios que se mantienen desde la Entrega 1: la API no guarda estado local,
los archivos no pasan por la API, Postgres es la fuente de verdad (si Redis se
vacia el sistema sigue siendo correcto) y las reentregas de tareas no duplican
efectos: tabla `processed_jobs`, restricciones de integridad y un lease de
transcodificacion en `assets` (en modo asynq local se suma `asynq.TaskID`).

**Observabilidad en la nube:** metricas nativas de Cloud Run
(`container/instance_count`), de Pub/Sub (`num_undelivered_messages`) y de
Cloud SQL en Cloud Monitoring, y registros de cada servicio en Cloud Logging.
Las trazas OpenTelemetry estan apagadas en la nube.

Red, identidades, secretos, escalamiento, operacion y deuda tecnica en
[`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md).

## Mapa del repositorio

| Carpeta / archivo | Contenido | Mas documentacion |
|---|---|---|
| [`cmd/api/`](cmd/api/) | Punto de entrada del proceso HTTP (`main.go`). | `docs/entrega1/DOCUMENTACION.md` |
| [`cmd/worker/`](cmd/worker/) | Punto de entrada del worker (`main.go`): servidor push de Pub/Sub (`QUEUE_BACKEND=pubsub`, Cloud Run) o consumidor asynq (local). | `docs/entrega1/DOCUMENTACION.md` |
| [`cmd/queue-metrics/`](cmd/queue-metrics/) | Publicaba el tamano de la cola asynq en Cloud Monitoring para autoescalar los workers de la Entrega 3. No se usa en Cloud Run. | [`docs/entrega3/arquitectura.md`](docs/entrega3/arquitectura.md) |
| [`internal/`](internal/) | Paquetes del backend: `api` (handlers, middlewares, rutas), `auth`, `audit`, `badge`, `config` (unico lugar donde se leen variables de entorno), `database`, `mailer`, `metrics`, `openapi` (contrato embebido), `progress`, `queue` (publicador asynq o Pub/Sub segun `QUEUE_BACKEND`), `pubsubpush` (recepcion del push y validacion OIDC), `queuemetrics`, `storage`, `tasks` (handlers del worker) y `telemetry`. | `docs/entrega1/DOCUMENTACION.md` |
| [`db/`](db/) | `init.sql`, esquema completo de la base. Solo se ejecuta al crear el volumen. | `docs/entrega1/ARQUITECTURA.md` |
| [`frontend/`](frontend/) | Frontend Next.js 15 + TypeScript + Tailwind (BFF). | [`frontend/README.md`](frontend/README.md) |
| [`deploy/gcp/`](deploy/gcp/) | Entrega 4: `cloudrun.sh` (red, secretos, servicios de Cloud Run y Pub/Sub), `verificar-e4.sh` y `escalamiento-e4.sh`. Comunes: `build.sh`, `migrate.sh`, `provision.sh`, `cors.json`. Entregas 2 y 3: `startup.sh`, `mig/` y un compose por VM (`web/`, `worker/`, `monitor/`). | [`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md) |
| [`deploy/`](deploy/) | Configuracion local de Prometheus y Grafana (dashboard provisionado) y `docker-compose.metrics.yml` con exportadores. | — |
| [`capacity-planning/`](capacity-planning/) | Scripts de k6, resultados e informes de capacidad de las Entregas 2 y 3. | [`capacity-planning/README.md`](capacity-planning/README.md), [`capacity-planning/escenario2/README.md`](capacity-planning/escenario2/README.md) |
| [`postman/`](postman/) | Coleccion de la API y entornos local y nube. | [`postman/README.md`](postman/README.md) |
| [`.postman/`](.postman/) | Metadatos del workspace de Postman. | — |
| [`docs/`](docs/) | Documentacion de cada entrega (`entrega1/` a `entrega4/`). | — |
| [`docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/) | Auditoria automatica WCAG 2.2 AA (`ejecutar.sh`, script de Playwright + axe en `prueba/`) y su ultimo reporte en `resultados/`. | [`README.md`](docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/README.md) |
| [`docs/entrega1/testdata/`](docs/entrega1/testdata/) | Pruebas de humo de extremo a extremo (`smoke.sh` y `smoke_*.sh`, cada una demuestra un comportamiento concreto). | [`docs/entrega1/testdata/README.md`](docs/entrega1/testdata/README.md) |
| `Dockerfile.api`, `Dockerfile.worker`, `Dockerfile.web`, `Dockerfile.queue-metrics` | Imagenes de la API, el worker, el frontend y la medicion de cola de la Entrega 3. | — |
| `docker-compose.yml`, `Makefile` | Entorno local completo y atajos. | Esta pagina |

## Contrato de la API

El contrato vive en `internal/openapi/openapi.yaml` (OpenAPI 3.1), va embebido
en el binario y no necesita configuracion:

- **Swagger UI:** `/docs` (con ejemplos listos para "Try it out").
- **Spec crudo:** `/openapi.yaml` (util para Postman o para generar clientes;
  el frontend genera sus tipos desde aqui).

Flujo tipico: `POST /api/v1/auth/login`, copiar el `access_token`, pulsar
**Authorize** y recorrer los ejemplos. Para un flujo encadenado completo usar
la coleccion de [`postman/`](postman/README.md).

## Entorno local

Requisitos: Docker y Docker Compose. No hace falta Go ni Node: todo se compila
dentro de Docker.

```bash
make deps                  # genera go.sum en un contenedor Go
docker compose up --build  # requiere un archivo .env en la raiz (lo leen api y worker)
```

En local MinIO reemplaza a Cloud Storage y Postgres corre en un contenedor; el
codigo es el mismo y solo cambia la configuracion (`internal/config`).

| Servicio | URL |
|---|---|
| Frontend web | http://localhost:3001 |
| API (health / Swagger) | http://localhost:8080/healthz · http://localhost:8080/docs |
| Bandeja de correo (Mailpit) | http://localhost:8025 |
| Consola de MinIO | http://localhost:9001 |
| Prometheus / Grafana | http://localhost:9090 · http://localhost:3000 |
| Jaeger (trazas) | http://localhost:16686 |
| PostgreSQL | localhost:5433 |

Las credenciales locales estan en
[`docs/entrega1/CREDENCIALES.md`](docs/entrega1/CREDENCIALES.md).

```bash
make up | make down | make logs | make psql
make reset                           # BORRA los volumenes
docker compose up --scale worker=3   # varios workers
```

> `db/init.sql` solo se ejecuta la primera vez que se crea el volumen de
> Postgres. Si se modifica, hay que correr `make reset` antes de volver a
> levantar.

## Uso de agentes de inteligencia artificial

Segun lo permite el enunciado del curso, el equipo uso un agente de
inteligencia artificial como asistente a lo largo de las cuatro entregas. Su
aporte permitio avanzar mas rapido en cada etapa del proyecto:

- **Diseno e implementacion:** propuesta y discusion de alternativas de
  arquitectura, escritura de codigo del backend, del frontend y de los
  scripts de despliegue, y diagnostico de errores encontrados en las pruebas
  y en la nube.
- **Operacion en Google Cloud:** generacion de las instrucciones de `gcloud`
  y de los pasos que se ejecutaron en Cloud Shell para aprovisionar,
  desplegar, migrar y verificar la infraestructura de cada entrega.
- **Documentacion:** redaccion y actualizacion de los documentos de
  arquitectura, los informes de capacidad, las guias de operacion y este
  README.
- **Pruebas:** escritura de las pruebas de humo, las pruebas unitarias, los
  escenarios de carga con k6, la auditoria de accesibilidad y los scripts de
  verificacion y escalamiento.

Todo el trabajo se hizo bajo la supervision de los integrantes del grupo:
cada propuesta se reviso antes de incorporarla, los comandos se ejecutaron
y validaron manualmente sobre el entorno real, y los resultados reportados
(pruebas, metricas y evidencias) se verificaron contra lo observado en el
despliegue. Las decisiones de diseno y la responsabilidad sobre el resultado
final son del equipo. El uso de la herramienta se declara tambien en la
sustentacion.
