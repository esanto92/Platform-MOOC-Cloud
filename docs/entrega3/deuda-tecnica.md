# Deuda tecnica - Entrega 3 (primera linea base)

Primer diagnostico formal de la calidad del codigo y de la deuda tecnica de
la Plataforma MOOC. Combina el analisis automatico de SonarQube Cloud con la
revision del equipo sobre arquitectura, infraestructura, pruebas y operacion.
El reporte del commit final de la Entrega 3 y el inventario de la seccion 4
son la linea base contra la que se mediran las entregas siguientes.

Contenido:

1. [Alcance y metodo](#1-alcance-y-metodo)
2. [Medicion inicial](#2-medicion-inicial)
3. [Correcciones realizadas en este ejercicio](#3-correcciones-realizadas-en-este-ejercicio)
4. [Inventario de deuda](#4-inventario-de-deuda)
5. [Priorizacion y plan de tratamiento](#5-priorizacion-y-plan-de-tratamiento)
6. [Linea base del commit final](#6-linea-base-del-commit-final)

---

## 1. Alcance y metodo

### Herramienta y configuracion

| Elemento | Valor |
|---|---|
| Herramienta | SonarQube Cloud (sonarcloud.io), organizacion `esanto92`, proyecto `esanto92_Platform-MOOC-Cloud` |
| Escaner | SonarScanner CLI 7.2.0.5079, via `SonarSource/sonarqube-scan-action@v6` |
| Perfil de reglas | `Sonar way core` (perfil por defecto) para Go, TypeScript, CSS y YAML. Dockerfiles con las reglas por defecto de Docker |
| Quality Gate | `Sonar way` (por defecto): condiciones sobre **codigo nuevo** (cobertura >= 80 %, duplicacion <= 3 %, ratings A, hotspots revisados) |
| Umbrales de la entrega | Verificados aparte por el pipeline sobre **todo el codigo**: duplicacion <= 20 % y mantenibilidad C o mejor |
| Pipeline | GitHub Actions, [`.github/workflows/calidad.yml`](../../.github/workflows/calidad.yml), en cada push a `main` y `entrega-3-infra` |
| Configuracion del analisis | [`sonar-project.properties`](../../sonar-project.properties) |

El pipeline ejecuta, en un solo job:

1. `go test -coverprofile=coverage.out ./...` (las pruebas que respaldan las
   correcciones; SonarQube lee la cobertura de ese archivo).
2. El analisis de SonarQube, esperando el resultado del Quality Gate
   (`sonar.qualitygate.wait=true`).
3. La exportacion del resultado de ese commit a JSON (medidas, hallazgos
   abiertos, hotspots, Quality Gate y metadatos con el SHA).
4. La verificacion de los umbrales de la entrega: el job falla si la
   duplicacion supera 20 % o la mantenibilidad es peor que C.
5. La publicacion del reporte como artefacto `reporte-sonarqube-<sha>`.

### Alcance analizado

| Componente | Ruta | Lenguaje | Lineas de codigo |
|---|---|---|---|
| API y workers (monolito modular) | `cmd/`, `internal/` | Go | 6 668 |
| Frontend (Next.js, BFF) | `frontend/src/` | TypeScript, CSS | 6 519 + 141 |
| Contrato de la API | `internal/openapi/openapi.yaml` | YAML | 728 |
| Imagenes desplegadas | `Dockerfile.api`, `.worker`, `.web`, `.queue-metrics` | Docker | 67 |
| **Total** | | | **14 123** |

### Exclusiones y limites del alcance

- `**/*_test.go` se excluye de `sonar.sources` y se declara en `sonar.tests`:
  son pruebas, no codigo de aplicacion. SonarQube las usa para la cobertura.
- `frontend/node_modules`, `frontend/.next` y `coverage.out` no se analizan
  porque son dependencias o artefactos generados, no codigo del equipo.
- **No se excluye ningun archivo de aplicacion.**
- No los cubre SonarQube y se revisaron a mano: los scripts de despliegue
  (`deploy/gcp/**/*.sh`, sin analizador de Bash en SonarQube Cloud), los
  `docker-compose.yml`, `db/init.sql` y las pruebas de carga k6. Sus hallazgos
  estan en el inventario como deuda de infraestructura u operacion.

### Actividades de revision del equipo

La herramienta no ve arquitectura, despliegue ni operacion. Por eso, ademas
del analisis automatico, el equipo hizo estas revisiones:

- Lectura de cada hallazgo de SonarQube en su contexto (quien llama a la
  funcion, de donde salen los datos) para separar riesgo real de falso
  positivo.
- Revision de los compromisos ya documentados en `CLAUDE.md` (seccion
  "Deuda tecnica conocida") y de los pendientes y riesgos de
  [`guia-mig.md`](guia-mig.md) (secciones 11 y riesgos).
- Revision de la cobertura de pruebas por paquete (`go test -cover ./...`) y
  de lo que valida el pipeline.
- Resultados de la auditoria de accesibilidad
  ([`FuncionalidadFront/`](FuncionalidadFront/)) y de las pruebas de carga
  ([`capacity-planning/`](../../capacity-planning/)).

### Equivalencia de severidades

La API de SonarQube Cloud devuelve la severidad clasica. La equivalencia con
la clasificacion por impacto (Software Qualities) y con la prioridad del
inventario es:

| Severidad clasica | Impacto (modo MQR) | Regla del enunciado |
|---|---|---|
| Blocker | Blocker | Resolver antes del cierre o plan explicito |
| Critical | High | Resolver antes del cierre o plan explicito |
| Major | Medium | Si queda abierto: registrar con regla, ubicacion, impacto y motivo |
| Minor | Low | Registrar |
| Info | Info | Opcional |

---

## 2. Medicion inicial

### Diagnostico inicial (antes de corregir)

Primer analisis completo del pipeline, sobre el codigo tal como estaba.

- Commit [`f8633b3`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/f8633b3c7f399ddf002eaf17405eca0f852c3d1f)
- Fecha: 2026-10-31
- Ejecucion: [run 41161818419](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41161818419)
- Reporte: [`calidad/f8633b3-diagnostico-inicial/`](calidad/f8633b3-diagnostico-inicial/)

| Indicador | Valor | Requisito | Cumple |
|---|---|---|---|
| Duplicacion | 1,5 % | <= 20 % | Si |
| Mantenibilidad | A (ratio de deuda 0,0 %) | A, B o C | Si |
| Deuda tecnica estimada | 15 min | Registrar | - |
| Fiabilidad | A (0 bugs) | - | - |
| Seguridad | C (9 vulnerabilidades) | - | - |
| Hotspots de seguridad | 0 | - | - |
| Cobertura (solo Go) | 3,8 % | - | - |
| Hallazgos abiertos | 12: 10 Major, 2 Minor, 0 Critical/Blocker | - | - |

### Despues de las correcciones

- Commit [`ef6e054`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/ef6e054c9a5cb76b6679d6f85edeb870caeaf414)
- Fecha: 2026-10-31
- Ejecucion: [run 41163150503](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41163150503)
- Reporte: [`calidad/ef6e054-tras-correcciones/`](calidad/ef6e054-tras-correcciones/)

| Indicador | Valor |
|---|---|
| Duplicacion | 1,5 % |
| Mantenibilidad | A, deuda estimada **0 min** |
| Seguridad | C (8 vulnerabilidades: 6 Major, 2 Minor) |
| Cobertura (solo Go) | 4,1 % |
| Quality Gate | Aprobado |

### Interpretacion

- **Unidad de la deuda.** SonarQube expresa la deuda en minutos de esfuerzo
  estimado para corregir los *code smells* de mantenibilidad. El ratio de
  deuda divide ese esfuerzo por el costo estimado de escribir el codigo, unos
  30 min por linea. Con 15 min sobre 14 115 lineas el ratio es practicamente
  0 % (rating A).
- **0 min no significa cero deuda.** La estimacion solo suma problemas de
  mantenibilidad. No incluye las vulnerabilidades: las 8 que siguen abiertas
  son de seguridad. Tampoco ve deuda de arquitectura, infraestructura,
  pruebas u operacion. El inventario de la seccion 4 tiene 18 elementos y
  solo 3 vienen del analizador.
- **La duplicacion y la mantenibilidad holgadas** reflejan convenciones que el
  proyecto ya sigue: un archivo de handlers por dominio, errores de API con
  ayudantes comunes (`internal/api/errors.go`) y componentes de UI
  reutilizables (`frontend/src/components/ui/`).
- **El indicador mas debil es la cobertura (4,1 %).** No es un umbral de la
  entrega, pero limita la confianza en cualquier refactorizacion: es el
  elemento DT-04 del inventario. El Quality Gate de codigo nuevo ya lo hace
  visible: el primer intento de corregir `godre:S8239` fallo el gate por
  falta de cobertura en las lineas cambiadas, y se resolvio escribiendo la
  prueba (seccion 3).
- **La seguridad en C** se debe a 4 consultas SQL armadas con `fmt.Sprintf`
  (DT-01) y a contrasenas de ejemplo en el contrato OpenAPI (DT-02). Tras la
  revision, ninguna permite hoy inyeccion ni expone una credencial
  productiva, pero ambas tienen tratamiento previsto.

---

## 3. Correcciones realizadas en este ejercicio

Estas correcciones no forman parte de la linea base de pendientes. Se
verificaron con el pipeline: el hallazgo desaparece y el Quality Gate pasa.

| Hallazgo | Ubicacion | Correccion | Commit | Verificacion |
|---|---|---|---|---|
| `godre:S8239` Major | `internal/tasks/tasks.go:159` | La auditoria de la DLQ usaba `context.Background()`. Ahora usa `context.WithoutCancel(ctx)`, que sigue escribiendo aunque el trabajo haya fallado por timeout y conserva la traza | [`e4e76cf`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/e4e76cf64e965bcf398cde0b6286a7f47e16410f), prueba en [`ef6e054`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/ef6e054c9a5cb76b6679d6f85edeb870caeaf414) | `internal/tasks/errorhandler_test.go`: falla si la auditoria se intenta con el contexto cancelado del trabajo |
| `docker:S6505` Major | `Dockerfile.web:7` | `npm ci --ignore-scripts`: ninguna dependencia ejecuta codigo al instalarse | `e4e76cf` | `docker build --target builder`: `next build`, lint y typecheck pasan |
| `typescript:S6850` Major | `frontend/src/components/ui/card.tsx:43` | `CardTitle` pasa `children` de forma explicita | `e4e76cf` | Mismo build; el HTML generado no cambia |
| `typescript:S6853` Major | `frontend/src/components/ui/input.tsx:42` | `Label` pasa `htmlFor` y `children` de forma explicita | `e4e76cf` | Mismo build; `Field` sigue asociando etiqueta y control |
| Pipeline sin umbrales ni evidencia | `.github/workflows/calidad.yml` | Verificacion de umbrales sobre todo el codigo y exportacion del reporte por commit | [`f8633b3`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/f8633b3c7f399ddf002eaf17405eca0f852c3d1f) | Probado con un umbral imposible (duplicacion maxima 0 %): el paso falla |

---

## 4. Inventario de deuda

Escala de prioridad:

- **P0**: antes del cierre de la Entrega 3.
- **P1**: Entrega 4.
- **P2**: Entrega 5.
- **P3**: aceptada; se revisa en cada entrega.

Los responsables se identifican por su usuario de GitHub.

### Resumen

| ID | Categoria | Deuda | Origen | Prioridad | Responsable | Estado |
|---|---|---|---|---|---|---|
| DT-01 | Codigo / seguridad | SQL dinamico en el reordenamiento de contenido | SonarQube | P2 | @esanto92 | Aceptada temporalmente |
| DT-02 | Codigo / seguridad | Contrasenas de demo en los ejemplos de OpenAPI | SonarQube | P0 | @esanto92 | Pendiente |
| DT-03 | Codigo / seguridad | ffmpeg y ffprobe resueltos por `PATH` | SonarQube | P3 | @esanto92 | Aceptada |
| DT-04 | Pruebas | Cobertura de pruebas unitarias de 4,1 % | Metrica | P1 | Todo el equipo | Pendiente |
| DT-05 | Pruebas | Frontend sin pruebas ni lint propio en el pipeline | Revision | P1 | @WhiteArctic | Pendiente |
| DT-06 | Pruebas | Faltan pruebas de recuperacion y compatibilidad | Retroalimentacion E1 | P2 | @Klealp | Pendiente |
| DT-07 | Arquitectura | `infra-server` es punto unico de falla (Redis) | Revision | P1 | @Klealp | Aceptada temporalmente |
| DT-08 | Arquitectura | Limite de tasa compartido por la IP del Cloud NAT | Revision | P1 | @esanto92 | Pendiente |
| DT-09 | Infraestructura | Argumentos de `gcloud` no verificados en GCP real | Revision | P0 | @esanto92 | En tratamiento |
| DT-10 | Infraestructura | `migrate.sh` no funciona con la topologia de la Entrega 3 | Revision | P0 | @Klealp | Pendiente |
| DT-11 | Operacion | Prometheus no descubre las VMs de los grupos | Revision | P1 | @brehynnermraz | Pendiente |
| DT-12 | Operacion | Trazas apagadas en la nube y sin propagacion API -> worker | Revision | P2 | @brehynnermraz | Aceptada temporalmente |
| DT-13 | Costo | VMs de la Entrega 2 siguen encendidas | Revision | P0 | @Klealp | Pendiente |
| DT-14 | Operacion | Correo en la nube via Mailpit, sin SMTP real | Revision | P2 | @esanto92 | Aceptada temporalmente |
| DT-15 | Seguridad | Antimalware de demostracion (solo detecta EICAR) | Decision documentada | P2 | @brehynnermraz | Aceptada temporalmente |
| DT-16 | Codigo | Filtros resueltos en el BFF y constantes duplicadas | Revision | P3 | @WhiteArctic | Aceptada |
| DT-17 | Accesibilidad | Sin subtitulos ni transcripciones de video y audio | Auditoria WCAG | P2 | @WhiteArctic | Pendiente |
| DT-18 | Pipeline | Acciones de GitHub en Node 20 (obsoleto) | Advertencia de GitHub Actions | P1 | @esanto92 | Pendiente |

### Detalle

#### DT-01 - SQL dinamico en el reordenamiento de contenido

- **Categoria:** codigo / seguridad.
- **Descripcion y ubicacion:** `reorder`, `updateOrdered` y `deleteOrdered`
  arman el nombre de la tabla y de la columna con `fmt.Sprintf`.
  Ubicacion: `internal/api/handlers_content.go:617, 652, 663, 683`.
- **Evidencia:** 4 hallazgos `go:S2077` (Major, vulnerabilidad).
  Revision: los seis llamadores (`handlers_content.go:73, 80, 131, 138, 310,
  322`) pasan literales fijos (`"modules"`, `"units"`, `"resources"`,
  `"version_id"`, `"module_id"`, `"unit_id"`). Los valores del usuario van
  como parametros `$1`, `$2`.
- **Impacto:** hoy no es explotable. Es fragil para la mantenibilidad y la
  seguridad: un llamador futuro que pase un valor del usuario abriria una
  inyeccion SQL que nada impediria.
- **Prioridad y justificacion:** P2. No hay riesgo actual, y la correccion
  toca la autoria de contenido, que tiene poca cobertura (DT-04). Conviene
  hacerla despues de tener pruebas de esos handlers.
- **Tratamiento:** reemplazar los parametros `table` y `parentCol` por un
  `map` cerrado de consultas por entidad (o validar contra una lista blanca)
  y agregar una prueba que rechace un nombre fuera de la lista.
  - **Verificacion:** los 4 hallazgos se cierran, o se marcan *Safe* en
    SonarQube con referencia al cambio, y la prueba pasa.
- **Responsable y plazo:** @esanto92, Entrega 5.
- **Estado y decision:** aceptada temporalmente. Motivo del aplazamiento:
  ningun llamador recibe datos del usuario y la correccion depende de DT-04.

#### DT-02 - Contrasenas de demo en los ejemplos de OpenAPI

- **Categoria:** codigo / seguridad.
- **Descripcion y ubicacion:** los ejemplos de registro y de creacion de
  usuario del contrato muestran `Estudiante2026` y `Profesor2026`.
  Ubicacion: `internal/openapi/openapi.yaml:71, 203`.
- **Evidencia:** 2 hallazgos `yaml:S2068` (Major). Son las mismas contrasenas
  de las cuentas de demo de `docs/entrega1/CREDENCIALES.md`. El contrato se
  publica en `/docs` y `/openapi.yaml`, tambien en la nube.
- **Impacto:** si en la nube existen cuentas con esas contrasenas, cualquiera
  que lea la documentacion publica de la API puede entrar.
- **Prioridad y justificacion:** P0. La documentacion es publica y la
  correccion es barata.
- **Tratamiento:**
  1. Confirmar que en Cloud SQL ninguna cuenta usa esas contrasenas y
     rotarlas si existen.
  2. Reemplazar los ejemplos por un texto que no sea una contrasena real.
  3. Si el analizador lo sigue marcando, marcarlo *Safe* con esa
     justificacion.
  - **Verificacion:** consulta en Cloud SQL sin coincidencias y hallazgos
    cerrados en el reporte del commit final.
- **Responsable y plazo:** @esanto92, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-03 - ffmpeg y ffprobe resueltos por `PATH`

- **Categoria:** codigo / seguridad.
- **Descripcion y ubicacion:** el worker ejecuta `ffmpeg` y `ffprobe` por
  nombre. Ubicacion: `internal/tasks/transcode.go:194, 271`.
- **Evidencia:** 2 hallazgos `go:S4036` (Minor).
- **Impacto:** bajo. El worker corre en un contenedor con `PATH` fijo de la
  imagen (`Dockerfile.worker` instala ffmpeg con `apk`) y nadie mas escribe
  en esos directorios.
- **Prioridad y justificacion:** P3. La mitigacion ya existe en la
  plataforma de ejecucion.
- **Tratamiento:** usar una ruta absoluta configurable (`FFMPEG_PATH`) si el
  worker llega a ejecutarse fuera del contenedor.
  - **Verificacion:** hallazgos cerrados.
- **Responsable y plazo:** @esanto92, sin plazo; se revisa en cada entrega.
- **Estado y decision:** aceptada, mitigada por el contenedor.

#### DT-04 - Cobertura de pruebas unitarias de 4,1 %

- **Categoria:** pruebas.
- **Descripcion y ubicacion:** solo 4 archivos de prueba en Go:
  `internal/queuemetrics`, `internal/api/proxies_test.go`,
  `internal/tasks/interrupted_test.go` y `internal/tasks/errorhandler_test.go`.
  Sin pruebas unitarias en `progress`, `auth`, la calificacion de quizzes ni
  la autoria.
- **Evidencia:** cobertura 4,1 % en SonarQube. Por paquete: `api` 6,0 %,
  `tasks` 4,4 %, `queuemetrics` 60,8 %. El Quality Gate rechazo una
  correccion sin prueba (seccion 3).
- **Impacto:** mantenibilidad y confiabilidad. Las reglas de negocio
  criticas (progreso calculado por el servidor, clave del quiz, inmutabilidad
  de versiones) solo se validan con las pruebas de humo, que requieren el
  entorno completo. Refactorizar (DT-01) es riesgoso.
- **Prioridad y justificacion:** P1. Bloquea otras correcciones y el gate de
  codigo nuevo exige 80 %.
- **Tratamiento:** pruebas unitarias en este orden: `internal/progress`, la
  calificacion de quizzes (`gradeAttempt`), `internal/auth` y los handlers de
  autoria. Toda correccion nueva va con su prueba (lo exige el gate).
  - **Verificacion:** cobertura global >= 30 % en el reporte de la Entrega 4.
- **Responsable y plazo:** todo el equipo, cada integrante sobre el modulo
  que mantiene. Entrega 4.
- **Estado:** pendiente.

#### DT-05 - Frontend sin pruebas ni lint propio en el pipeline

- **Categoria:** pruebas.
- **Descripcion y ubicacion:** `calidad.yml` solo corre las pruebas de Go.
  `npm run lint` y `npm run typecheck` solo se ejecutan dentro de
  `docker build` (`Dockerfile.web`), no en el pipeline. No hay pruebas de
  componentes en `frontend/`.
- **Evidencia:** el workflow de GitHub Actions y `frontend/package.json` (sin
  script `test`). SonarQube no recibe cobertura del frontend: 6 519 lineas
  de TypeScript sin cobertura.
- **Impacto:** un error de tipos o de lint del frontend se descubre al
  construir la imagen, ya en el despliegue.
- **Prioridad y justificacion:** P1. Agregar el job es barato; las pruebas
  de componentes son trabajo de mas largo plazo.
- **Tratamiento:**
  1. Un job `frontend` en `calidad.yml` con `npm ci --ignore-scripts`,
     `npm run lint` y `npm run typecheck`.
  2. Despues, pruebas de los flujos minimos con el reporte de cobertura
     enviado a SonarQube.
  - **Verificacion:** el job aparece en verde en el pipeline.
- **Responsable y plazo:** @WhiteArctic, Entrega 4.
- **Estado:** pendiente.

#### DT-06 - Faltan pruebas de recuperacion y compatibilidad

- **Categoria:** pruebas.
- **Descripcion y ubicacion:** las pruebas de humo
  (`docs/entrega1/testdata/smoke*.sh`) cubren los flujos principales, pero no
  la recuperacion ante la caida de un componente ni la compatibilidad entre
  navegadores.
- **Evidencia:** retroalimentacion de la Entrega 1, registrada en `CLAUDE.md`.
- **Impacto:** confiabilidad. La recuperacion segura de trabajos al retirar
  workers (`interrupted` en `internal/tasks/tasks.go`) solo tiene prueba
  unitaria, no prueba de extremo a extremo.
- **Prioridad y justificacion:** P2. Depende de tener el entorno de grupos
  estable (DT-09).
- **Tratamiento:** un `smoke_recuperacion.sh` que retire un worker con un
  trabajo en curso y verifique que otro lo completa.
  - **Verificacion:** el script pasa contra el entorno de la nube.
- **Responsable y plazo:** @Klealp, Entrega 5.
- **Estado:** pendiente.

#### DT-07 - `infra-server` es punto unico de falla

- **Categoria:** arquitectura.
- **Descripcion y ubicacion:** Redis (cola asynq, sesiones en cache, limite
  de tasa), Mailpit y el publicador de la metrica de la cola viven en una VM
  fija fuera de los grupos (`deploy/gcp/mig/`, rol `infra`).
- **Evidencia:** riesgo registrado en [`guia-mig.md`](guia-mig.md), seccion
  2 y riesgos.
- **Impacto:** confiabilidad. Si la VM cae, se pierde la cola y los workers
  no reciben trabajo. El autoescalado de workers queda sin senal. Postgres
  conserva la verdad, asi que no hay perdida de datos de negocio.
- **Prioridad y justificacion:** P1. Es el mayor riesgo de disponibilidad,
  pero Memorystore tiene un costo que el presupuesto del curso debe validar.
- **Tratamiento:** migrar Redis a Memorystore (servicio administrado) y
  mover `queue-metrics` a un grupo de tamano 1 con autorreparacion.
  - **Verificacion:** apagar `infra-server` no detiene el procesamiento.
- **Responsable y plazo:** @Klealp, Entrega 4.
- **Estado y decision:** aceptada temporalmente. Fuera del alcance minimo de
  la Entrega 3 por costo; Redis se mantiene sin estado de negocio
  (restriccion 3 de `CLAUDE.md`).

#### DT-08 - Limite de tasa compartido por la IP del Cloud NAT

- **Categoria:** arquitectura.
- **Descripcion y ubicacion:** las peticiones anonimas que pasan por el BFF
  (`frontend/`) llegan a la API con la IP del Cloud NAT. Afecta al limite de
  tasa por IP (`RATE_LIMIT_PER_MIN`, `internal/config/config.go:134`).
- **Evidencia:** documentado en `CLAUDE.md` y en [`guia-mig.md`](guia-mig.md).
- **Impacto:** confiabilidad y desempeno. Bajo carga, el login de todos los
  usuarios comparte un solo cupo: los primeros 120 intentos por minuto
  bloquean al resto. Distorsiona las pruebas de carga del login.
- **Prioridad y justificacion:** P1. Afecta a todos los usuarios en el
  escenario elastico, que es el objetivo de la entrega.
- **Tratamiento:** el BFF reenvia la IP del navegador en `X-Forwarded-For` y
  la API confia en ese encabezado solo si viene del frontend
  (`TRUSTED_PROXIES`).
  - **Verificacion:** prueba en `internal/api/proxies_test.go` y dos
    clientes distintos con cupos independientes.
- **Responsable y plazo:** @esanto92, Entrega 4.
- **Estado:** pendiente.

#### DT-09 - Argumentos de `gcloud` no verificados en GCP real

- **Categoria:** infraestructura.
- **Descripcion y ubicacion:** `deploy/gcp/provision.sh` (pasos `elastica`,
  `grupos`, `balanceador`, `desplegar`) se ensayo con un `gcloud` falso. No se verificaron:
  - el autoescalado por metrica de grupo (`--update-stackdriver-metric`,
    `--stackdriver-metric-single-instance-assignment`);
  - `url-maps import` desde `/dev/stdin`;
  - la subred como URL completa en las plantillas.
- **Evidencia:** [`guia-mig.md`](guia-mig.md), riesgos conocidos.
- **Impacto:** las instrucciones de reconstruccion pueden no ser
  reproducibles.
- **Prioridad y justificacion:** P0. La reconstruccion reproducible es un
  requisito obligatorio de la entrega; registrarla como deuda no la subsana.
- **Tratamiento:** ejecucion completa en GCP y correccion de cada argumento
  que falle.
  - **Verificacion:** `provision.sh` crea el entorno desde cero sin pasos
    manuales.
- **Responsable y plazo:** @esanto92, cierre de la Entrega 3.
- **Estado:** en tratamiento.

#### DT-10 - `migrate.sh` no funciona con la topologia de la Entrega 3

- **Categoria:** infraestructura.
- **Descripcion y ubicacion:** `deploy/gcp/migrate.sh` (linea 6) lee
  `/etc/mooc/web.env`, que no existe en las VMs de los grupos.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), seccion 11.
- **Impacto:** no se puede reconstruir la base desde cero con el
  procedimiento documentado.
- **Prioridad y justificacion:** P0, por la misma razon que DT-09.
- **Tratamiento:** leer la configuracion del `.env` del rol `api` o recibir
  la cadena de conexion por parametro.
  - **Verificacion:** `migrate.sh init-db` contra una instancia nueva de
    Cloud SQL.
- **Responsable y plazo:** @Klealp, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-11 - Prometheus no descubre las VMs de los grupos

- **Categoria:** operacion.
- **Descripcion y ubicacion:** la configuracion de Prometheus apunta a
  destinos fijos (`static_configs` en `deploy/gcp/monitor/prometheus.yml`) y
  no a las instancias que crea el autoescalador.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), seccion 11.
- **Impacto:** observabilidad. Las metricas de aplicacion
  (`internal/metrics`) de las replicas nuevas no se recolectan. Hoy el
  autoescalado se observa solo con Cloud Monitoring.
- **Prioridad y justificacion:** P1. Las pruebas de capacidad se apoyan en
  Cloud Monitoring, asi que no bloquea la entrega.
- **Tratamiento:** `gce_sd_configs` filtrado por la etiqueta de los grupos.
  - **Verificacion:** una VM creada por el autoescalador aparece como
    destino activo.
- **Responsable y plazo:** @brehynnermraz, Entrega 4.
- **Estado:** pendiente.

#### DT-12 - Trazas apagadas en la nube y sin propagacion API -> worker

- **Categoria:** operacion.
- **Descripcion y ubicacion:** `OTEL_EXPORTER_OTLP_ENDPOINT` esta vacio en la
  nube. El worker no recibe el `traceparent` de la API al encolar
  (`internal/queue`, `internal/tasks`).
- **Evidencia:** `CLAUDE.md`, "Deuda tecnica conocida". Jaeger no cabe en
  2 GiB junto a la aplicacion.
- **Impacto:** diagnostico. Un trabajo lento no se puede relacionar con la
  peticion que lo origino.
- **Prioridad y justificacion:** P2. Los logs y metricas cubren la operacion
  actual.
- **Tratamiento:**
  1. Agregar el `traceparent` al payload de la tarea.
  2. Exportar a Cloud Trace (administrado, sin VM propia).
  - **Verificacion:** una sola traza abarca la peticion HTTP y su
    procesamiento en el worker.
- **Responsable y plazo:** @brehynnermraz, Entrega 5.
- **Estado y decision:** aceptada temporalmente por falta de memoria en la VM.

#### DT-13 - VMs de la Entrega 2 siguen encendidas

- **Categoria:** costo.
- **Descripcion y ubicacion:** `web-server` y `worker-server` de la Entrega 2
  se conservan para reconstruir la linea base de capacidad.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), seccion 11.
- **Impacto:** costo. Dos `e2-highcpu-2` encendidas sin servir trafico, y
  ocupan cuota de vCPU que el autoescalado necesita.
- **Prioridad y justificacion:** P0, en cuanto terminen las pruebas
  comparativas.
- **Tratamiento:** detenerlas despues de los escenarios heredados. Sus
  archivos se conservan en el repositorio para recrearlas.
  - **Verificacion:** `gcloud compute instances list` sin esas VMs en
    ejecucion.
- **Responsable y plazo:** @Klealp, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-14 - Correo en la nube via Mailpit, sin SMTP real

- **Categoria:** operacion.
- **Descripcion y ubicacion:** el worker envia los correos a Mailpit
  (`internal/mailer`, `infra-server`). El token de verificacion de correo se
  lee a mano en Mailpit; las pruebas de humo no lo automatizan.
- **Evidencia:** `CLAUDE.md`, "Deuda tecnica conocida".
- **Impacto:** un usuario real no recibe el correo de verificacion. El flujo
  de registro requiere intervencion manual.
- **Prioridad y justificacion:** P2. El curso no exige correo real y los
  recorridos se demuestran con cuentas creadas.
- **Tratamiento:** configurar un proveedor SMTP por variables de entorno (sin
  cambiar codigo) y leer el token desde la API de Mailpit en las pruebas de
  humo.
  - **Verificacion:** registro completo sin pasos manuales.
- **Responsable y plazo:** @esanto92, Entrega 5.
- **Estado y decision:** aceptada temporalmente.

#### DT-15 - Antimalware de demostracion

- **Categoria:** seguridad.
- **Descripcion y ubicacion:** el escaneo de archivos subidos
  (`internal/tasks/scan.go`) solo detecta la firma de prueba EICAR. La
  interfaz permite conectar ClamAV.
- **Evidencia:** decision documentada en `CLAUDE.md`. Prueba de humo
  `smoke_eicar.sh`.
- **Impacto:** seguridad. Un archivo malicioso real se publicaria a los
  estudiantes.
- **Prioridad y justificacion:** P2. ClamAV necesita alrededor de 1 GiB de
  memoria por worker, lo que obliga a cambiar el tipo de maquina del grupo
  de workers.
- **Tratamiento:** contenedor `clamd` en las VMs worker detras de la interfaz
  existente.
  - **Verificacion:** `smoke_eicar.sh` sigue pasando con ClamAV y una firma
    real se rechaza.
- **Responsable y plazo:** @brehynnermraz, Entrega 5.
- **Estado y decision:** aceptada temporalmente por costo de memoria.

#### DT-16 - Filtros resueltos en el BFF y constantes duplicadas

- **Categoria:** codigo.
- **Descripcion y ubicacion:** `GET /courses` no filtra. `GET /admin/audit`
  no filtra por fecha: el frontend pide 500 lineas y recorta. La lista de
  acciones de auditoria esta copiada en
  `frontend/src/components/admin/audit-filters.tsx`, a partir de
  `internal/audit/audit.go`.
- **Evidencia:** `CLAUDE.md`, "Deuda tecnica conocida".
- **Impacto:** desempeno (transfiere datos de mas) y mantenibilidad (una
  accion nueva obliga a tocar dos archivos).
- **Prioridad y justificacion:** P3. Volumen bajo en el uso actual.
- **Tratamiento:** llevar los filtros al `WHERE` y exponer la lista de
  acciones en el contrato OpenAPI para que el frontend la genere con
  `npm run gen:api`.
  - **Verificacion:** el BFF ya no recorta resultados.
- **Responsable y plazo:** @WhiteArctic con apoyo de backend, sin plazo.
- **Estado y decision:** aceptada.

#### DT-17 - Sin subtitulos ni transcripciones de video y audio

- **Categoria:** accesibilidad.
- **Descripcion y ubicacion:** WCAG 2.2 criterios 1.2.2 y 1.2.5. El backend
  no guarda pistas WebVTT; el reproductor (`hls.js`) no las ofrece.
- **Evidencia:** auditoria de accesibilidad ([`FuncionalidadFront/`](FuncionalidadFront/)):
  38 auditorias automaticas aprobadas. Estos dos criterios requieren
  contenido que la plataforma no gestiona.
- **Impacto:** usuarios sordos o con hipoacusia no pueden consumir el video.
- **Prioridad y justificacion:** P2. Requiere cambio de modelo de datos
  (`db/init.sql`) y de la vista de autoria.
- **Tratamiento:**
  1. Recurso de pista WebVTT asociado al video, subido por URL prefirmada
     como los demas archivos.
  2. Elemento `<track>` en el reproductor.
  - **Verificacion:** un video con pista muestra subtitulos.
- **Responsable y plazo:** @WhiteArctic, Entrega 5.
- **Estado:** pendiente.

#### DT-18 - Acciones de GitHub en Node 20

- **Categoria:** pipeline.
- **Descripcion y ubicacion:** `actions/checkout@v4`, `actions/setup-go@v5`,
  `actions/upload-artifact@v4` y `sonarqube-scan-action@v6` declaran Node 20.
  Ademas, `ubuntu-latest` migra a Ubuntu 26.
- **Evidencia:** advertencias en las anotaciones del
  [run 41163150503](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41163150503).
- **Impacto:** el pipeline obligatorio puede dejar de funcionar cuando GitHub
  retire Node 20.
- **Prioridad y justificacion:** P1. Correccion de minutos, pero conviene no
  cambiar el pipeline justo antes del commit final de la linea base.
- **Tratamiento:** subir a las versiones mayores que declaran Node 24 y fijar
  `runs-on: ubuntu-24.04`.
  - **Verificacion:** run sin advertencias.
- **Responsable y plazo:** @esanto92, Entrega 4.
- **Estado:** pendiente.

---

## 5. Priorizacion y plan de tratamiento

Criterios, en orden: (1) requisitos obligatorios de la entrega y exposicion
de seguridad publica; (2) riesgo para la disponibilidad del escenario
elastico; (3) dependencias (lo que desbloquea otras correcciones); (4) costo
de la correccion.

| Plazo | Elementos | Motivo |
|---|---|---|
| Cierre de la Entrega 3 (P0) | DT-02, DT-09, DT-10, DT-13 | Contrasenas en documentacion publica; reconstruccion reproducible obligatoria; costo de VMs sin uso |
| Entrega 4 (P1) | DT-04, DT-05, DT-18, luego DT-08, DT-07, DT-11 | Primero las pruebas, que desbloquean refactorizaciones seguras; despues los riesgos del escenario elastico |
| Entrega 5 (P2) | DT-01, DT-06, DT-12, DT-14, DT-15, DT-17 | Dependen de DT-04 o de cambios de infraestructura con costo |
| Aceptadas (P3) | DT-03, DT-16 | Mitigadas o de bajo impacto; se revisan en cada entrega |

Hallazgos Major abiertos al cierre: los de DT-01 (4) y, si no se cierran
antes, los de DT-02 (2). Ambos estan registrados con regla, ubicacion,
impacto y motivo. No hay hallazgos Critical ni Blocker.

---

## 6. Linea base del commit final

La linea base oficial es el reporte del **commit final** de la Entrega 3.
Esta seccion se completa al cerrar la entrega, con el run del pipeline sobre
el commit etiquetado `entrega-3`:

| Campo | Valor |
|---|---|
| Commit evaluado | _pendiente_ |
| Fecha del analisis | _pendiente_ |
| Ejecucion del pipeline | _pendiente_ |
| Reporte | `calidad/<sha>-linea-base/` (copia del artefacto `reporte-sonarqube-<sha>`) |
| Duplicacion | _pendiente_ |
| Mantenibilidad | _pendiente_ |
| Deuda tecnica estimada | _pendiente_ |
| Hallazgos abiertos | _pendiente_ |

Procedimiento:

1. Ejecutar el pipeline sobre el commit final y verificar que pasa.
2. Descargar el artefacto con
   `gh run download <run> -R esanto92/Platform-MOOC-Cloud` y copiarlo a
   `docs/entrega3/calidad/<sha>-linea-base/`. GitHub borra los artefactos a
   los 90 dias; la copia en el repositorio es la que perdura.
3. Llenar la tabla y actualizar el estado de los elementos P0 del inventario.
