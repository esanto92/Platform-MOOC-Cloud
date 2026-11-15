# CLAUDE.md

Contexto para Claude Code al trabajar sobre este repositorio.

## Que es esto

Plataforma MOOC (cursos masivos abiertos en linea) del curso ISIS4426
"Desarrollo de Soluciones Cloud" (Universidad de los Andes). Backend en Go
(monolito modular + workers asincronos) y frontend Next.js que actua como BFF.
Las cuatro entregas estan terminadas: 1 (backend local), 2 (despliegue en dos
VMs de Google Cloud), 3 (arquitectura elastica con MIG y balanceador) y 4
(Cloud Run + Cloud Pub/Sub). **La API esta desplegada en su estado final.**

- La arquitectura vigente es la de la **Entrega 4**:
  [`docs/entrega4/arquitectura.md`](docs/entrega4/arquitectura.md). Tres
  servicios de Cloud Run (`mooc-web`, `mooc-api`, `mooc-worker`, 0 a 3
  instancias cada uno) y Cloud Pub/Sub como cola: la API publica en el topic
  `mooc-tasks` y la suscripcion push `mooc-tasks-push` (token OIDC,
  ackDeadline 600 s) entrega cada mensaje al worker, que confirma tras
  persistir. Cloud SQL, Cloud Storage e `infra-server` (Redis, Mailpit) se
  alcanzan por Direct VPC egress.
- La mensajeria es conmutable con `QUEUE_BACKEND`: `pubsub` (Cloud Run,
  Pub/Sub entrega cada mensaje por HTTP al worker) o `asynq` (local, el
  worker busca trabajos en Redis). Los handlers de `internal/tasks` son los
  mismos en ambos modos; solo cambia como llega el trabajo.
- URLs: frontend https://mooc-web-mhuknn2hva-uc.a.run.app, API
  https://mooc-api-mhuknn2hva-uc.a.run.app/api/v1 (estado en `/readyz`; no
  usar `/healthz` desde fuera, Cloud Run reserva esa ruta).
- La arquitectura logica (modulos, reglas, modelo de datos) sigue en
  [`docs/entrega1/ARQUITECTURA.md`](docs/entrega1/ARQUITECTURA.md) y la
  documentacion archivo por archivo en `docs/entrega1/DOCUMENTACION.md`. Las
  Entregas 2 y 3 se conservan como lineas base en `docs/entrega2/` y
  `docs/entrega3/`.
- Las diferencias entre local y nube van en variables de entorno, no en
  codigo (MinIO/Cloud Storage, Postgres local/Cloud SQL, asynq/Pub/Sub).
  Mantenerlo asi.
- El frontend (`frontend/`) tiene su propio README y su propio stack
  (TypeScript). No modificarlo al trabajar en el backend salvo peticion
  explicita; si cambia el contrato OpenAPI, avisar que el frontend regenera
  sus tipos con `npm run gen:api`.
- El frontend debe cumplir **WCAG 2.2 AA** (criterio de calificacion). Al
  tocarlo, seguir las convenciones de la seccion "Accesibilidad" de
  `frontend/README.md` (tokens de color, `Field`, `ButtonLink`, titulos por
  pagina, nada de texto atenuado con `opacity`) y volver a correr la auditoria
  de `docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/`. La ultima
  ejecucion (2026-10-24) aprobo las 38 auditorias. Los subtitulos y
  transcripciones de video/audio (1.2.2 y 1.2.5) siguen pendientes: necesitan
  que el backend guarde pistas WebVTT.

Un proyecto anterior del mismo autor, `okf-platform` (conversion de documentos
a bundles OKF), sirvio de referencia: se conservan a proposito su estructura de
carpetas, su estilo de comentarios en espanol y sus convenciones de despliegue.

## Idioma

**Todo el codigo, los comentarios, los mensajes de error, los commits y las
respuestas se escriben en espanol.** Los comentarios evitan tildes para no
depender de la codificacion del terminal. Los mensajes de error de la API van
dirigidos a un desarrollador y son concretos.

## Restricciones que NO se pueden romper

Vienen del enunciado del curso y son criterios de calificacion:

1. **La API no guarda estado local.** Nada en memoria entre peticiones, nada
   en el disco del contenedor. Si algo necesita persistir va a Postgres, a
   Redis o al almacenamiento de objetos.
2. **Los archivos no pasan por la API.** Se suben con URLs prefirmadas
   directamente al almacenamiento y se descargan igual.
3. **Postgres es la fuente de verdad.** Redis solo tiene cache de sesiones,
   contadores de rate limit, llaves de `Idempotency-Key` y, en modo asynq, la
   cola. Si Redis se vacia, el sistema debe seguir siendo correcto.
4. **Ningun binario en la base relacional.** Solo la llave del objeto.
5. **El progreso lo calcula el servidor.** Un porcentaje enviado por el
   cliente se rechaza con 422 y se audita.
6. **La clave de un quiz nunca sale hacia el cliente.** Vive en el campo `key`
   del snapshot y solo la lee `gradeAttempt`.
7. **Una version publicada es inmutable.** Para editar se crea una version
   nueva clonando la anterior y conservando los `stable_id`.
8. **El acceso a un recurso ajeno responde 404, no 403.**
9. **Los quizzes son de seleccion multiple SOLO DE TEXTO.** Sin imagenes,
   video ni archivos en enunciados ni en opciones. No agregar ese soporte sin
   que lo pidan.
10. **Los profesores solo los crea un administrador.** El registro publico
    siempre produce un `student`.
11. **Siempre debe quedar al menos un administrador activo.**
12. **Maximo 3 instancias por servicio de Cloud Run** (enunciado de la
    Entrega 4). `MAX_INSTANCIAS` en `deploy/gcp/cloudrun.sh`.

## Mapa del repositorio

```
cmd/api/          proceso HTTP (no hace trabajo pesado)
cmd/worker/       trabajo pesado (ffmpeg, escaneo, correo, insignias). Con
                  QUEUE_BACKEND=pubsub es un servidor HTTP que recibe el push
                  (/pubsub/push, /readyz); con asynq consume la cola de Redis
cmd/queue-metrics/ Entrega 3: publicaba pendientes + activos de la cola asynq
                  en Cloud Monitoring para autoescalar el MIG de workers. No
                  se usa en Cloud Run
internal/
  api/            handlers, middlewares, rutas. Un archivo handlers_*.go por dominio
  auth/           contrasenas, tokens opacos, sesiones revocables
  audit/          bitacora append-only
  badge/          generacion del SVG de la insignia
  config/         TODAS las variables de entorno se leen aqui y en ningun otro lugar
  database/       conexiones a Postgres y Redis con reintentos
  mailer/         SMTP (Mailpit en local y en infra-server)
  metrics/        series de Prometheus
  progress/       reglas de avance, finalizacion y aprobacion
  queue/          contrato de tareas entre API y workers. Publisher con dos
                  implementaciones: asynq (queue.go) y Pub/Sub (pubsub.go);
                  factory.go elige con QUEUE_BACKEND
  pubsubpush/     servidor HTTP que recibe la suscripcion push de Pub/Sub,
                  valida el token OIDC y despacha al handler
  queuemetrics/   medicion de la cola asynq y escritura en Cloud Monitoring
                  (Entrega 3)
  storage/        cliente del almacenamiento de objetos (API S3: MinIO en local, Cloud Storage en la nube)
  tasks/          handlers de los workers
  telemetry/      arranque del exportador OpenTelemetry
db/init.sql       esquema completo. Solo se ejecuta al CREAR el volumen
internal/openapi/ contrato de la API (openapi.yaml embebido; se sirve en /docs y /openapi.yaml)
frontend/         Next.js 15 (BFF). Ver frontend/README.md
deploy/           Prometheus, Grafana y exportadores para el entorno local
deploy/gcp/       Entrega 4: cloudrun.sh (apis, red, secretos, api, web,
                  worker, pubsub, resumen), verificar-e4.sh (solo lee el
                  estado de GCP y reporta OK/FALLA/AVISO) y escalamiento-e4.sh
                  (carga controlada + reporte). Comunes: build.sh (imagenes a
                  Artifact Registry con el sha del commit), migrate.sh,
                  provision.sh, cors.json. Entregas 2 y 3: startup.sh, mig/
                  y un compose por VM (web/, worker/, monitor/)
capacity-planning/ pruebas de carga k6 e informes de capacidad (Entregas 2 y 3)
postman/          coleccion de la API y entornos local y nube
docs/entrega1/    ARQUITECTURA.md, DOCUMENTACION.md, CREDENCIALES.md (locales)
docs/entrega2/    arquitectura del despliegue en dos VMs y diagramas
docs/entrega3/    arquitectura.md (MIG y balanceador), guia-mig.md,
                  deuda-tecnica.md, calidad/ (SonarQube) y
                  FuncionalidadFront/ (verificacion del frontend y
                  PruebaAccesibilidad/: auditoria WCAG 2.2 AA con Playwright +
                  axe en un contenedor, ejecutar.sh, reporte en
                  resultados/REPORTE.md)
docs/entrega4/    arquitectura.md (Cloud Run + Pub/Sub), diagramas/ (Mermaid)
                  y resultados-escalamiento/
.github/          workflows/calidad.yml: en cada push corre go test con
                  cobertura y el analisis de SonarQube Cloud, verifica los
                  umbrales de la Entrega 3 (duplicacion <= 20 %,
                  mantenibilidad C o mejor) y publica el reporte JSON del
                  commit como artefacto. Lo que se analiza lo define
                  sonar-project.properties en la raiz
docs/entrega1/testdata/
                  smoke.sh, otros smoke_*.sh (cada uno demuestra un
                  comportamiento concreto: un formato de archivo, un
                  camino de falla, una regla de negocio). smoke_eicar.sh
                  genera el archivo EICAR al ejecutarse.
                  Agregar un smoke_*.sh nuevo esta bien cuando cubre un
                  comportamiento que los demas no cubren; no crear
                  variantes redundantes de uno ya existente ni agregar
                  binarios de prueba sueltos sin un script que los use.
                  Mantener docs/entrega1/testdata/README.md al dia con la tabla de
                  que hace cada script.
```

## Convenciones de codigo

- Los handlers son metodos sobre `*api.Server`, que tiene las dependencias.
- Errores de API: usar los ayudantes de `internal/api/errors.go`
  (`badRequest`, `notFound`, `conflict`, `unprocessable`, `internalError`).
  Nunca escribir un JSON de error a mano.
- **El aislamiento por propietario va en el `WHERE` de la consulta**, no en un
  `if` posterior. Es la regla mas importante del proyecto: si esta en el SQL,
  no hay camino que la omita.
- Para autoria, usar `s.guard(c, nivel, id)`: resuelve propiedad e
  inmutabilidad de una vez. Los niveles son `course`, `version`, `module`,
  `unit`, `resource`, `quiz`, `question`.
- Los comentarios explican **por que**, no **que**. El codigo ya dice que hace.
- Consultas SQL en linea con `database/sql`. No hay ORM y no se va a agregar.
- Evitar el problema N+1: ver `buildOutline`, que arma el arbol con tres
  consultas.

## Idempotencia (a proposito)

1. `asynq.TaskID(llave)` impide encolar dos veces el mismo efecto. **Solo en
   modo asynq**: Pub/Sub no deduplica por llave, asi que en Cloud Run no se
   puede depender de esta capa.
2. La tabla `processed_jobs` registra el trabajo terminado en Postgres. Es la
   capa que importa en ambos modos: una reentrega de Pub/Sub de un trabajo ya
   hecho se detecta aqui (`alreadyProcessed`).
3. Restricciones de integridad, como `uniq_badge_alive`. Esta es la unica que
   no se puede esquivar en una carrera entre dos workers.
4. **Lease de transcodificacion** (`assets.transcode_lease_until`,
   `claimTranscode` en `internal/tasks/transcode.go`): con la suscripcion push,
   una reentrega puede llegar mientras otro worker aun transcodifica (la tarea
   puede durar mas que el ackDeadline). El claim atomico deja que solo el
   worker con el lease vigente trabaje; los demas hacen ack sin duplicar. La
   ventana (`TranscodeLease`, 20 min) es mayor que el ackDeadline (600 s) y
   menor que el umbral del reaper (2 h).

Semantica del push (`internal/pubsubpush/server.go`): `2xx` solo despues de
persistir; un fallo transitorio responde `5xx` y Pub/Sub reintenta; un error
"no reintentar" (payload corrupto, asset inexistente, duplicado) responde
`2xx` para no reentregar en bucle.

Al agregar una tarea nueva, implementar las capas que le apliquen. Las tareas
que fallan por contenido (archivo corrupto) marcan el asset `failed` y dejan
una alerta de auditoria (`ActionAssetFailed`, `alertAssetFailed`); esa alerta
vive en el dominio, no en un hook de la cola.

La cabecera `Idempotency-Key` de la API (`internal/api/idempotency.go`,
obligatoria en `POST /attempts/:id/submit`) es otra cosa: guarda en Redis la
respuesta de la primera peticion y la repite ante un reintento del cliente.

## Cambios que exigen recrear el volumen

`db/init.sql` solo se ejecuta la **primera** vez que se crea el volumen de
Postgres. Despues de tocarlo hay que correr `make reset` (`docker compose
down -v`). Avisarlo siempre que se modifique ese archivo.

En la nube, donde Cloud SQL ya tiene datos, los cambios aditivos de esquema se
aplican con una migracion idempotente en vez de recrear la base. La Entrega 4
agrego `assets.transcode_lease_until`; se aplica con
`./deploy/gcp/migrate.sh migrate-e4` (`ALTER TABLE ... ADD COLUMN IF NOT
EXISTS`) desde una maquina dentro de `mooc-vpc`, porque Cloud SQL solo tiene
IP privada.

## Despliegue en Google Cloud (Entrega 4, vigente)

- **Cloud Run** gen2 en `us-central1`, minimo 0 y maximo 3 instancias por
  servicio. `mooc-web` y `mooc-api`: 1 vCPU, 512 MiB, concurrencia 80,
  timeout 60 s, publicos (la autenticacion la hace la aplicacion).
  `mooc-worker`: 2 vCPU, 4 GiB (el `/tmp` de ffmpeg vive en memoria),
  concurrencia 1 (mas mensajes = mas instancias), timeout 600 s (= ackDeadline),
  ingreso interno y `roles/run.invoker` solo para `mooc-pubsub-push`.
- **Red:** Direct VPC egress desde la subred `mooc-run` (`10.20.5.0/24`) con
  `private-ranges-only`; `mooc-web` no entra a la VPC.
- **Secretos:** uno por valor sensible (`mooc-run-*`) en Secret Manager,
  inyectado con `--set-secrets`. La configuracion no sensible la toma
  `cloudrun.sh` de los `.env` de la Entrega 3 guardados en Secret Manager.
  Nunca versionar secretos.
- **Identidades:** `mooc-api` publica en el topic y no puede borrar objetos
  del bucket; `mooc-worker` si puede (archivos infectados) y tambien publica
  (tareas derivadas scan->transcode, badge->email). Cada uno tiene su propia
  llave HMAC; no usar una sola.
- `PUBSUB_PROJECT` se pasa explicito: el cliente de Pub/Sub no lo infiere de
  los metadatos.
- La API Go no usa cookies (sesion en `Authorization: Bearer`, inmune a CSRF
  por construccion). La cookie HttpOnly `mooc_session` es solo del BFF; el
  navegador nunca llama a la API, asi que CORS en la API no aplica. CORS si
  aplica en el bucket (`deploy/gcp/cors.json`).
- `infra-server` debe estar encendida antes de la API: la API no arranca sin
  Redis.
- Infraestructura anterior: los MIG de la Entrega 3 quedaron en 0 instancias
  con plantillas y balanceador conservados; los archivos de la Entrega 2
  (`deploy/gcp/web|worker|monitor`) siguen para reconstruir esa linea base.
  `WORKER_CONCURRENCY=2` y `MAX_RETRIES=3` se mantuvieron fijos en las pruebas
  de capacidad de esas entregas; cambiarlos invalida la comparacion.

## Comandos

```bash
make deps    # go mod tidy en un contenedor efimero (genera go.sum)
make up      # levanta todo
make reset   # BORRA los volumenes; obligatorio tras cambiar db/init.sql
make logs    # sigue los logs de api y worker
make psql    # consola SQL
docker compose up -d --build --no-deps web   # reconstruye solo el frontend
./docs/entrega1/testdata/smoke.sh   # prueba de humo de extremo a extremo
"./docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/ejecutar.sh"   # auditoria WCAG 2.2 AA

# Nube (ver docs/entrega4/arquitectura.md seccion 8)
export PROJECT=dsc-uniandes-20262
./deploy/gcp/build.sh api web worker                     # exige arbol limpio
./deploy/gcp/cloudrun.sh apis red secretos
./deploy/gcp/migrate.sh migrate-e4                       # desde una VM en mooc-vpc
./deploy/gcp/cloudrun.sh worker pubsub api web resumen   # worker antes que pubsub
./deploy/gcp/verificar-e4.sh                             # solo lectura
./deploy/gcp/escalamiento-e4.sh                          # carga controlada + reporte
```

## Deuda tecnica conocida

Cosas que estan asi a proposito y que no hay que "arreglar" sin hablarlo:

- **Redis sigue en `infra-server`.** Ya no es la cola, pero la API lo usa para
  datos que sus replicas sin estado deben compartir: cache de sesiones,
  contadores del rate limit y respuestas de `Idempotency-Key`. No se movio
  porque Cloud Run no puede alojar un Redis con estado, Memorystore suma un
  costo fijo que la entrega no justificaba y llevarlo a Postgres cargaria a
  Cloud SQL (el cuello de botella de la Entrega 3). Es punto unico de falla:
  la API no arranca sin Redis (el rate limit si deja pasar el trafico si
  Redis falla, y la sesion se relee de Postgres).
- `TRUSTED_PROXIES` esta vacio en Cloud Run (los rangos eran los del
  balanceador de la Entrega 3), asi que Gin confia en cualquier
  `X-Forwarded-For`. Ademas, todas las peticiones llegan a la API desde el
  BFF y comparten el limite de tasa por IP (afecta al login). Arreglarlo
  exige que el BFF reenvie la IP del navegador y que la API confie en el.
- `/metrics`, `/readyz` y `/docs` quedan publicos en la URL de `mooc-api`.
- Sin dead-letter en Pub/Sub (no lo exige el enunciado): tras los reintentos
  el asset queda `failed` con `failure_reason` y alerta `asset.failed`.
- El reaper (`internal/tasks/reap.go`) solo se agenda en modo asynq. En Cloud
  Run la recuperacion depende de la reentrega de Pub/Sub y del lease; el
  barrido periodico (cargas multipart vencidas, sesiones caducadas) exigiria
  Cloud Scheduler -> endpoint.
- Cloud Run da 10 s entre SIGTERM y SIGKILL; un trabajo interrumpido no se
  confirma y Pub/Sub lo reentrega. Con minimo 0 hay arranque en frio
  (`API_MIN=1` para demostraciones).
- El antimalware es un stub que detecta EICAR. La interfaz permite enchufar
  ClamAV mas adelante.
- Hay trazas OpenTelemetry (OTLP -> Jaeger) en la API (otelgin), el worker
  (un span por trabajo) y Postgres (otelsql), ademas de `X-Request-ID` y
  metricas. Pendiente: propagar el `traceparent` de la API dentro del trabajo
  publicado para unir en una sola traza la peticion HTTP y su procesamiento
  en el worker. En la nube las trazas estan apagadas
  (`OTEL_EXPORTER_OTLP_ENDPOINT` vacio).
- El `Markdown extendido canonico` se normaliza (finales de linea y espacios).
  La biyeccion completa con el AST del editor es trabajo del frontend.
- No hay CDN: `CDN_BASE_URL` vacio significa "firma contra el almacenamiento"
  (MinIO o Cloud Storage). Se activa cambiando esa variable.
- `GET /resources/:id/content` es solo de autoria (profesor/admin). El
  estudiante lee el Markdown de un recurso `rich_text` por
  `GET /enrollments/:id/resources/:resourceId/content`, con la misma regla de
  acceso que los archivos dentro del `WHERE` (inscripcion activa, curso
  publicado, version vigente, recurso visible); cualquier otro caso es 404.
- Los filtros de "Mis cursos" (`/teach`) y de la bitacora (`/admin/audit`) se
  resuelven en parte en el servidor de Next, no en la API: `GET /courses` no
  acepta filtros ni devuelve nivel ni idioma, y `GET /admin/audit` filtra por
  `action` pero no por fecha (el frontend pide las ultimas 500 lineas y
  recorta). Llevarlos al `WHERE` es un cambio pequeno de backend pendiente de
  aprobar. La lista de tipos del filtro de auditoria copia las constantes
  `Action*` de `internal/audit/audit.go`: al agregar una accion, agregarla
  tambien en `frontend/src/components/admin/audit-filters.tsx`.
- Los smoke tests no leen el token de verificacion de correo desde Mailpit;
  en produccion (`APP_ENV` distinto de `dev`) hay que leerlo a mano.
- Pocas pruebas unitarias (`go test ./...`): el servidor push de Pub/Sub
  (`internal/pubsubpush/server_test.go`), `internal/queuemetrics`, la IP del
  cliente detras de un proxy (`internal/api/proxies_test.go`), los trabajos
  interrumpidos (`internal/tasks/interrupted_test.go`) y la auditoria de la
  DLQ de asynq con el contexto cancelado (`internal/tasks/errorhandler_test.go`).
  Las demas pruebas automatizadas son la prueba de humo (`smoke*.sh`) y la
  auditoria de accesibilidad. Faltan, segun la retroalimentacion de la
  Entrega 1, compatibilidad y recuperacion.
