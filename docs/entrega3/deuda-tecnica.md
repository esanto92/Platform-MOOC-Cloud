# Deuda técnica - Entrega 3 (primera línea base)

Primer diagnóstico formal de la calidad del código y de la deuda técnica de
la Plataforma MOOC. Combina el análisis automático de SonarQube Cloud con la
revisión del equipo sobre arquitectura, infraestructura, pruebas y operación.
El reporte del commit final de la Entrega 3 y el inventario de la sección 4
son la línea base contra la que se medirán las entregas siguientes.

Contenido:

1. [Alcance y método](#1-alcance-y-método)
2. [Medición inicial](#2-medición-inicial)
3. [Correcciones realizadas en este ejercicio](#3-correcciones-realizadas-en-este-ejercicio)
4. [Inventario de deuda](#4-inventario-de-deuda)
5. [Priorización y plan de tratamiento](#5-priorización-y-plan-de-tratamiento)
6. [Línea base del commit final](#6-línea-base-del-commit-final)

---

## 1. Alcance y método

### Herramienta y configuración

| Elemento | Valor |
|---|---|
| Repositorio de entrega | [`esanto92/Platform-MOOC-Cloud`](https://github.com/esanto92/Platform-MOOC-Cloud): ahí corren el pipeline y el commit evaluado |
| Herramienta | SonarQube Cloud (sonarcloud.io), organización `esanto92`, proyecto `esanto92_Platform-MOOC-Cloud` |
| Escaner | SonarScanner CLI 7.2.0.5079, vía `SonarSource/sonarqube-scan-action@v6` |
| Perfil de reglas | `Sonar way core` (perfil por defecto) para Go, TypeScript, CSS y YAML. Dockerfiles con las reglas por defecto de Docker |
| Umbrales de la entrega | Verificados por el pipeline sobre el **código total** (*Overall Code*): duplicación <= 20 % y mantenibilidad C o mejor |
| Quality Gate | `Sonar way` (por defecto). Es una barrera complementaria, no la medición de la línea base: solo evalúa las líneas cambiadas desde el 2026-10-25 (*New Code*) y exige, entre otras, 80 % de cobertura en ellas. Impide que entre código nuevo sin pruebas |
| Pipeline | GitHub Actions, [`.github/workflows/calidad.yml`](../../.github/workflows/calidad.yml), en cada push a `main` y `entrega-3-infra` |
| Configuración del análisis | [`sonar-project.properties`](../../sonar-project.properties) |

El pipeline ejecuta, en un solo job:

1. `go test -coverprofile=coverage.out ./...` (las pruebas que respaldan las
   correcciones; SonarQube lee la cobertura de ese archivo).
2. El análisis de SonarQube, esperando el resultado del Quality Gate
   (`sonar.qualitygate.wait=true`).
3. La exportación del resultado de ese commit a JSON (medidas, hallazgos
   abiertos, hotspots, Quality Gate y metadatos con el SHA).
4. La verificación de los umbrales de la entrega: el job falla si la
   duplicación supera 20 % o la mantenibilidad es peor que C.
5. La publicación del reporte como artefacto `reporte-sonarqube-<sha>`.

### Alcance analizado

| Componente | Ruta | Lenguaje | Líneas de código |
|---|---|---|---|
| API y workers (monolito modular) | `cmd/`, `internal/` | Go | 6 668 |
| Frontend (Next.js, BFF) | `frontend/src/` | TypeScript, CSS | 6 519 + 141 |
| Contrato de la API | `internal/openapi/openapi.yaml` | YAML | 728 |
| Imágenes desplegadas | `Dockerfile.api`, `.worker`, `.web`, `.queue-metrics` | Docker | 67 |
| **Total** | | | **14 123** |

### Exclusiones y límites del alcance

- `**/*_test.go` se excluye de `sonar.sources` y se declara en `sonar.tests`:
  son pruebas, no código de aplicación. SonarQube las usa para la cobertura.
- `frontend/node_modules`, `frontend/.next` y `coverage.out` no se analizan
  porque son dependencias o artefactos generados, no código del equipo.
- **No se excluye ningún archivo de aplicación.**
- No los cubre SonarQube y se revisaron a mano: los scripts de despliegue
  (`deploy/gcp/**/*.sh`, sin analizador de Bash en SonarQube Cloud), los
  `docker-compose.yml`, `db/init.sql` y las pruebas de carga k6. Sus hallazgos
  están en el inventario como deuda de infraestructura u operación.

### Actividades de revisión del equipo

La herramienta no ve arquitectura, despliegue ni operación. Por eso, además
del análisis automático, el equipo hizo estas revisiones:

- Lectura de cada hallazgo de SonarQube en su contexto (quién llama a la
  función, de dónde salen los datos) para separar riesgo real de falso
  positivo.
- Revisión de los compromisos ya documentados en `CLAUDE.md` (sección
  "Deuda técnica conocida") y de los pendientes y riesgos de
  [`guia-mig.md`](guia-mig.md) (secciones 11 y riesgos).
- Revisión de la cobertura de pruebas por paquete (`go test -cover ./...`) y
  de lo que valida el pipeline.
- Resultados de la auditoría de accesibilidad
  ([`FuncionalidadFront/`](FuncionalidadFront/)) y de las pruebas de carga
  ([`capacity-planning/`](../../capacity-planning/)).

### Equivalencia de severidades

La API de SonarQube Cloud devuelve la severidad clásica. La equivalencia con
la clasificación por impacto (Software Qualities) y con la prioridad del
inventario es:

| Severidad clásica | Impacto (modo MQR) | Regla del enunciado |
|---|---|---|
| Blocker | Blocker | Resolver antes del cierre o plan explícito |
| Critical | High | Resolver antes del cierre o plan explícito |
| Major | Medium | Si queda abierto: registrar con regla, ubicación, impacto y motivo |
| Minor | Low | Registrar |
| Info | Info | Opcional |

---

## 2. Medición inicial

**Todos los valores de esta sección corresponden al código total del
proyecto (*Overall Code* en SonarQube), como exige el enunciado.**

### Diagnóstico inicial (antes de corregir)

Primer análisis completo del pipeline, sobre el código tal como estaba.

- Commit [`f8633b3`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/f8633b3c7f399ddf002eaf17405eca0f852c3d1f)
- Fecha: 2026-10-31
- Ejecución: [run 41161818419](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41161818419)
- Reporte: [`calidad/f8633b3-diagnostico-inicial/`](calidad/f8633b3-diagnostico-inicial/)

| Indicador | Valor | Requisito | Cumple |
|---|---|---|---|
| Duplicación | 1,5 % | <= 20 % | Sí |
| Mantenibilidad | A (ratio de deuda 0,0 %) | A, B o C | Sí |
| Deuda técnica estimada | 15 min | Registrar | - |
| Fiabilidad | A (0 bugs) | - | - |
| Seguridad | C (9 vulnerabilidades) | - | - |
| Hotspots de seguridad | 0 | - | - |
| Cobertura (solo Go) | 3,8 % | - | - |
| Hallazgos abiertos | 12: 10 Major, 2 Minor, 0 Critical/Blocker | - | - |

### Después de las correcciones

Tras las correcciones de la sección 3 (commit
[`ef6e054`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/ef6e054c9a5cb76b6679d6f85edeb870caeaf414),
[run 41163150503](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41163150503),
reporte en [`calidad/ef6e054-tras-correcciones/`](calidad/ef6e054-tras-correcciones/))
quedan 8 hallazgos abiertos (6 Major, 2 Minor), la deuda estimada baja a
0 min y el Quality Gate se aprueba. No es una comparación exigida: es la
evidencia de que las correcciones cerraron sus hallazgos.

### Interpretación

- **Unidad de la deuda.** SonarQube expresa la deuda en minutos de esfuerzo
  estimado para corregir los *code smells* de mantenibilidad. El ratio de
  deuda divide ese esfuerzo por el costo estimado de escribir el código, unos
  30 min por línea. Con 15 min sobre 14 115 líneas el ratio es prácticamente
  0 % (rating A).
- **0 min no significa cero deuda.** La estimación solo suma problemas de
  mantenibilidad. No incluye las vulnerabilidades: las 8 que siguen abiertas
  son de seguridad. Tampoco ve deuda de arquitectura, infraestructura,
  pruebas u operación. El inventario de la sección 4 tiene 16 elementos y
  solo 3 vienen del analizador.
- **La duplicación y la mantenibilidad holgadas** reflejan convenciones que el
  proyecto ya sigue: un archivo de handlers por dominio, errores de API con
  ayudantes comunes (`internal/api/errors.go`) y componentes de UI
  reutilizables (`frontend/src/components/ui/`).
- **El indicador más débil es la cobertura (4,1 %).** No es un umbral de la
  entrega, pero limita la confianza en cualquier refactorización: es el
  elemento DT-04 del inventario. El Quality Gate ya lo hace visible en los
  cambios: el primer intento de corregir `godre:S8239` falló el gate por
  falta de cobertura en las líneas cambiadas, y se resolvió escribiendo la
  prueba (sección 3).
- **La seguridad en C** se debe a 4 consultas SQL armadas con `fmt.Sprintf`
  (DT-01) y a contraseñas de ejemplo en el contrato OpenAPI (DT-02). Tras la
  revisión, ninguna permite hoy inyección ni expone una credencial
  productiva, pero ambas tienen tratamiento previsto.

---

## 3. Correcciones realizadas en este ejercicio

Estas correcciones no forman parte de la línea base de pendientes. Se
verificaron con el pipeline: el hallazgo desaparece y el Quality Gate pasa.

| Hallazgo | Ubicación | Corrección | Commit | Verificación |
|---|---|---|---|---|
| `godre:S8239` Major | `internal/tasks/tasks.go:159` | La auditoría de la DLQ usaba `context.Background()`. Ahora usa `context.WithoutCancel(ctx)`, que sigue escribiendo aunque el trabajo haya fallado por timeout y conserva la traza | [`e4e76cf`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/e4e76cf64e965bcf398cde0b6286a7f47e16410f), prueba en [`ef6e054`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/ef6e054c9a5cb76b6679d6f85edeb870caeaf414) | `internal/tasks/errorhandler_test.go`: falla si la auditoría se intenta con el contexto cancelado del trabajo |
| `docker:S6505` Major | `Dockerfile.web:7` | `npm ci --ignore-scripts`: ninguna dependencia ejecuta código al instalarse | `e4e76cf` | `docker build --target builder`: `next build`, lint y typecheck pasan |
| `typescript:S6850` Major | `frontend/src/components/ui/card.tsx:43` | `CardTitle` pasa `children` de forma explícita | `e4e76cf` | Mismo build; el HTML generado no cambia |
| `typescript:S6853` Major | `frontend/src/components/ui/input.tsx:42` | `Label` pasa `htmlFor` y `children` de forma explícita | `e4e76cf` | Mismo build; `Field` sigue asociando etiqueta y control |
| Pipeline sin umbrales ni evidencia | `.github/workflows/calidad.yml` | Verificación de umbrales sobre todo el código y exportación del reporte por commit | [`f8633b3`](https://github.com/esanto92/Platform-MOOC-Cloud/commit/f8633b3c7f399ddf002eaf17405eca0f852c3d1f) | Probado con un umbral imposible (duplicación máxima 0 %): el paso falla |

---

## 4. Inventario de deuda

Escala de prioridad:

- **P0**: antes del cierre de la Entrega 3.
- **P1**: Entrega 4.
- **P2**: Entrega 5.
- **P3**: aceptada; se revisa en cada entrega.

Los responsables se identifican por su usuario de GitHub.

### Resumen

| ID | Categoría | Deuda | Origen | Prioridad | Responsable | Estado |
|---|---|---|---|---|---|---|
| DT-01 | Código / seguridad | SQL dinámico en el reordenamiento de contenido | SonarQube | P2 | @esanto92 | Aceptada temporalmente |
| DT-02 | Código / seguridad | Contraseñas de demo en los ejemplos de OpenAPI | SonarQube | P0 | @esanto92 | Pendiente |
| DT-03 | Código / seguridad | ffmpeg y ffprobe resueltos por `PATH` | SonarQube | P3 | @esanto92 | Aceptada |
| DT-04 | Pruebas | Cobertura de pruebas unitarias de 4,1 % | Métrica | P1 | Todo el equipo | Pendiente |
| DT-05 | Pruebas | Frontend sin pruebas ni lint propio en el pipeline | Revisión | P1 | @WhiteArctic | Pendiente |
| DT-06 | Pruebas | Faltan pruebas de recuperación y compatibilidad | Retroalimentación E1 | P2 | @Klealp | Pendiente |
| DT-07 | Arquitectura | `infra-server` es punto único de falla (Redis) | Revisión | P1 | @Klealp | Aceptada temporalmente |
| DT-08 | Arquitectura | Límite de tasa compartido por la IP del Cloud NAT | Revisión | P1 | @esanto92 | Pendiente |
| DT-09 | Infraestructura | Argumentos de `gcloud` no verificados en GCP real | Revisión | P0 | @esanto92 | En tratamiento |
| DT-10 | Infraestructura | `migrate.sh` no funciona con la topología de la Entrega 3 | Revisión | P0 | @Klealp | Pendiente |
| DT-11 | Operación | Prometheus no descubre las VMs de los grupos | Revisión | P1 | @brehynnermraz | Pendiente |
| DT-12 | Operación | Trazas apagadas en la nube y sin propagación API -> worker | Revisión | P2 | @brehynnermraz | Aceptada temporalmente |
| DT-13 | Costo | VMs de la Entrega 2 siguen encendidas | Revisión | P0 | @Klealp | Pendiente |
| DT-14 | Seguridad | Antimalware de demostración (solo detecta EICAR) | Decisión documentada | P2 | @brehynnermraz | Aceptada temporalmente |
| DT-15 | Código | Filtros resueltos en el BFF y constantes duplicadas | Revisión | P3 | @WhiteArctic | Aceptada |
| DT-16 | Pipeline | Acciones de GitHub en Node 20 (obsoleto) | Advertencia de GitHub Actions | P1 | @esanto92 | Pendiente |

### Detalle

#### DT-01 - SQL dinámico en el reordenamiento de contenido

- **Categoría:** código / seguridad.
- **Descripción y ubicación:** `reorder`, `updateOrdered` y `deleteOrdered`
  arman el nombre de la tabla y de la columna con `fmt.Sprintf`.
  Ubicación: `internal/api/handlers_content.go:617, 652, 663, 683`.
- **Evidencia:** 4 hallazgos `go:S2077` (Major, vulnerabilidad).
  Revisión: los seis llamadores (`handlers_content.go:73, 80, 131, 138, 310,
  322`) pasan literales fijos (`"modules"`, `"units"`, `"resources"`,
  `"version_id"`, `"module_id"`, `"unit_id"`). Los valores del usuario van
  como parámetros `$1`, `$2`.
- **Impacto:** hoy no es explotable. Es frágil para la mantenibilidad y la
  seguridad: un llamador futuro que pase un valor del usuario abriría una
  inyección SQL que nada impediría.
- **Prioridad y justificación:** P2. No hay riesgo actual, y la corrección
  toca la autoría de contenido, que tiene poca cobertura (DT-04). Conviene
  hacerla después de tener pruebas de esos handlers.
- **Tratamiento:** reemplazar los parámetros `table` y `parentCol` por un
  `map` cerrado de consultas por entidad (o validar contra una lista blanca)
  y agregar una prueba que rechace un nombre fuera de la lista.
  - **Verificación:** los 4 hallazgos se cierran, o se marcan *Safe* en
    SonarQube con referencia al cambio, y la prueba pasa.
- **Responsable y plazo:** @esanto92, Entrega 5.
- **Estado y decisión:** aceptada temporalmente. Motivo del aplazamiento:
  ningún llamador recibe datos del usuario y la corrección depende de DT-04.

#### DT-02 - Contraseñas de demo en los ejemplos de OpenAPI

- **Categoría:** código / seguridad.
- **Descripción y ubicación:** los ejemplos de registro y de creación de
  usuario del contrato muestran `Estudiante2026` y `Profesor2026`.
  Ubicación: `internal/openapi/openapi.yaml:71, 203`.
- **Evidencia:** 2 hallazgos `yaml:S2068` (Major). Son las mismas contraseñas
  de las cuentas de demo de `docs/entrega1/CREDENCIALES.md`. El contrato se
  publica en `/docs` y `/openapi.yaml`, también en la nube.
- **Impacto:** si en la nube existen cuentas con esas contraseñas, cualquiera
  que lea la documentación pública de la API puede entrar.
- **Prioridad y justificación:** P0. La documentación es pública y la
  corrección es barata.
- **Tratamiento:**
  1. Confirmar que en Cloud SQL ninguna cuenta usa esas contraseñas y
     rotarlas si existen.
  2. Reemplazar los ejemplos por un texto que no sea una contraseña real.
  3. Si el analizador lo sigue marcando, marcarlo *Safe* con esa
     justificación.
  - **Verificación:** consulta en Cloud SQL sin coincidencias y hallazgos
    cerrados en el reporte del commit final.
- **Responsable y plazo:** @esanto92, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-03 - ffmpeg y ffprobe resueltos por `PATH`

- **Categoría:** código / seguridad.
- **Descripción y ubicación:** el worker ejecuta `ffmpeg` y `ffprobe` por
  nombre. Ubicación: `internal/tasks/transcode.go:194, 271`.
- **Evidencia:** 2 hallazgos `go:S4036` (Minor).
- **Impacto:** bajo. El worker corre en un contenedor con `PATH` fijo de la
  imagen (`Dockerfile.worker` instala ffmpeg con `apk`) y nadie más escribe
  en esos directorios.
- **Prioridad y justificación:** P3. La mitigación ya existe en la
  plataforma de ejecución.
- **Tratamiento:** usar una ruta absoluta configurable (`FFMPEG_PATH`) si el
  worker llega a ejecutarse fuera del contenedor.
  - **Verificación:** hallazgos cerrados.
- **Responsable y plazo:** @esanto92, sin plazo; se revisa en cada entrega.
- **Estado y decisión:** aceptada, mitigada por el contenedor.

#### DT-04 - Cobertura de pruebas unitarias de 4,1 %

- **Categoría:** pruebas.
- **Descripción y ubicación:** solo 4 archivos de prueba en Go:
  `internal/queuemetrics`, `internal/api/proxies_test.go`,
  `internal/tasks/interrupted_test.go` y `internal/tasks/errorhandler_test.go`.
  Sin pruebas unitarias en `progress`, `auth`, la calificación de quizzes ni
  la autoría.
- **Evidencia:** cobertura 4,1 % en SonarQube. Por paquete: `api` 6,0 %,
  `tasks` 4,4 %, `queuemetrics` 60,8 %. El Quality Gate rechazó una
  corrección sin prueba (sección 3).
- **Impacto:** mantenibilidad y confiabilidad. Las reglas de negocio
  críticas (progreso calculado por el servidor, clave del quiz, inmutabilidad
  de versiones) solo se validan con las pruebas de humo, que requieren el
  entorno completo. Refactorizar (DT-01) es riesgoso.
- **Prioridad y justificación:** P1. Bloquea otras correcciones, y el Quality
  Gate exige 80 % de cobertura en cada línea cambiada.
- **Tratamiento:** pruebas unitarias en este orden: `internal/progress`, la
  calificación de quizzes (`gradeAttempt`), `internal/auth` y los handlers de
  autoría. Toda corrección nueva va con su prueba (lo exige el gate).
  - **Verificación:** cobertura global >= 30 % en el reporte de la Entrega 4.
- **Responsable y plazo:** todo el equipo, cada integrante sobre el modulo
  que mantiene. Entrega 4.
- **Estado:** pendiente.

#### DT-05 - Frontend sin pruebas ni lint propio en el pipeline

- **Categoría:** pruebas.
- **Descripción y ubicación:** `calidad.yml` solo corre las pruebas de Go.
  `npm run lint` y `npm run typecheck` solo se ejecutan dentro de
  `docker build` (`Dockerfile.web`), no en el pipeline. No hay pruebas de
  componentes en `frontend/`.
- **Evidencia:** el workflow de GitHub Actions y `frontend/package.json` (sin
  script `test`). SonarQube no recibe cobertura del frontend: 6 519 líneas
  de TypeScript sin cobertura.
- **Impacto:** un error de tipos o de lint del frontend se descubre al
  construir la imagen, ya en el despliegue.
- **Prioridad y justificación:** P1. Agregar el job es barato; las pruebas
  de componentes son trabajo de más largo plazo.
- **Tratamiento:**
  1. Un job `frontend` en `calidad.yml` con `npm ci --ignore-scripts`,
     `npm run lint` y `npm run typecheck`.
  2. Después, pruebas de los flujos mínimos con el reporte de cobertura
     enviado a SonarQube.
  - **Verificación:** el job aparece en verde en el pipeline.
- **Responsable y plazo:** @WhiteArctic, Entrega 4.
- **Estado:** pendiente.

#### DT-06 - Faltan pruebas de recuperación y compatibilidad

- **Categoría:** pruebas.
- **Descripción y ubicación:** las pruebas de humo
  (`docs/entrega1/testdata/smoke*.sh`) cubren los flujos principales, pero no
  la recuperación ante la caída de un componente ni la compatibilidad entre
  navegadores.
- **Evidencia:** retroalimentación de la Entrega 1, registrada en `CLAUDE.md`.
- **Impacto:** confiabilidad. La recuperación segura de trabajos al retirar
  workers (`interrupted` en `internal/tasks/tasks.go`) solo tiene prueba
  unitaria, no prueba de extremo a extremo.
- **Prioridad y justificación:** P2. Depende de tener el entorno de grupos
  estable (DT-09).
- **Tratamiento:** un `smoke_recuperacion.sh` que retire un worker con un
  trabajo en curso y verifique que otro lo completa.
  - **Verificación:** el script pasa contra el entorno de la nube.
- **Responsable y plazo:** @Klealp, Entrega 5.
- **Estado:** pendiente.

#### DT-07 - `infra-server` es punto único de falla

- **Categoría:** arquitectura.
- **Descripción y ubicación:** Redis (cola asynq, sesiones en cache, límite
  de tasa), Mailpit y el publicador de la métrica de la cola viven en una VM
  fija fuera de los grupos (`deploy/gcp/mig/`, rol `infra`).
- **Evidencia:** riesgo registrado en [`guia-mig.md`](guia-mig.md), sección
  2 y riesgos.
- **Impacto:** confiabilidad. Si la VM cae, se pierde la cola y los workers
  no reciben trabajo. El autoescalado de workers queda sin señal. Postgres
  conserva la verdad, así que no hay pérdida de datos de negocio.
- **Prioridad y justificación:** P1. Es el mayor riesgo de disponibilidad,
  pero Memorystore tiene un costo que el presupuesto del curso debe validar.
- **Tratamiento:** migrar Redis a Memorystore (servicio administrado) y
  mover `queue-metrics` a un grupo de tamaño 1 con autorreparación.
  - **Verificación:** apagar `infra-server` no detiene el procesamiento.
- **Responsable y plazo:** @Klealp, Entrega 4.
- **Estado y decisión:** aceptada temporalmente. Fuera del alcance mínimo de
  la Entrega 3 por costo; Redis se mantiene sin estado de negocio
  (restricción 3 de `CLAUDE.md`).

#### DT-08 - Límite de tasa compartido por la IP del Cloud NAT

- **Categoría:** arquitectura.
- **Descripción y ubicación:** las peticiones anónimas que pasan por el BFF
  (`frontend/`) llegan a la API con la IP del Cloud NAT. Afecta al límite de
  tasa por IP (`RATE_LIMIT_PER_MIN`, `internal/config/config.go:134`).
- **Evidencia:** documentado en `CLAUDE.md` y en [`guia-mig.md`](guia-mig.md).
- **Impacto:** confiabilidad y desempeño. Bajo carga, el login de todos los
  usuarios comparte un solo cupo: los primeros 120 intentos por minuto
  bloquean al resto. Distorsiona las pruebas de carga del login.
- **Prioridad y justificación:** P1. Afecta a todos los usuarios en el
  escenario elástico, que es el objetivo de la entrega.
- **Tratamiento:** el BFF reenvía la IP del navegador en `X-Forwarded-For` y
  la API confía en ese encabezado solo si viene del frontend
  (`TRUSTED_PROXIES`).
  - **Verificación:** prueba en `internal/api/proxies_test.go` y dos
    clientes distintos con cupos independientes.
- **Responsable y plazo:** @esanto92, Entrega 4.
- **Estado:** pendiente.

#### DT-09 - Argumentos de `gcloud` no verificados en GCP real

- **Categoría:** infraestructura.
- **Descripción y ubicación:** `deploy/gcp/provision.sh` (pasos `elastica`,
  `grupos`, `balanceador`, `desplegar`) se ensayó con un `gcloud` falso. No se verificaron:
  - el autoescalado por métrica de grupo (`--update-stackdriver-metric`,
    `--stackdriver-metric-single-instance-assignment`);
  - `url-maps import` desde `/dev/stdin`;
  - la subred como URL completa en las plantillas.
- **Evidencia:** [`guia-mig.md`](guia-mig.md), riesgos conocidos.
- **Impacto:** las instrucciones de reconstrucción pueden no ser
  reproducibles.
- **Prioridad y justificación:** P0. La reconstrucción reproducible es un
  requisito obligatorio de la entrega; registrarla como deuda no la subsana.
- **Tratamiento:** ejecución completa en GCP y corrección de cada argumento
  que falle.
  - **Verificación:** `provision.sh` crea el entorno desde cero sin pasos
    manuales.
- **Responsable y plazo:** @esanto92, cierre de la Entrega 3.
- **Estado:** en tratamiento.

#### DT-10 - `migrate.sh` no funciona con la topología de la Entrega 3

- **Categoría:** infraestructura.
- **Descripción y ubicación:** `deploy/gcp/migrate.sh` (línea 6) lee
  `/etc/mooc/web.env`, que no existe en las VMs de los grupos.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), sección 11.
- **Impacto:** no se puede reconstruir la base desde cero con el
  procedimiento documentado.
- **Prioridad y justificación:** P0, por la misma razón que DT-09.
- **Tratamiento:** leer la configuración del `.env` del rol `api` o recibir
  la cadena de conexión por parámetro.
  - **Verificación:** `migrate.sh init-db` contra una instancia nueva de
    Cloud SQL.
- **Responsable y plazo:** @Klealp, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-11 - Prometheus no descubre las VMs de los grupos

- **Categoría:** operación.
- **Descripción y ubicación:** la configuración de Prometheus apunta a
  destinos fijos (`static_configs` en `deploy/gcp/monitor/prometheus.yml`) y
  no a las instancias que crea el autoescalador.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), sección 11.
- **Impacto:** observabilidad. Las métricas de aplicación
  (`internal/metrics`) de las réplicas nuevas no se recolectan. Hoy el
  autoescalado se observa solo con Cloud Monitoring.
- **Prioridad y justificación:** P1. Las pruebas de capacidad se apoyan en
  Cloud Monitoring, así que no bloquea la entrega.
- **Tratamiento:** `gce_sd_configs` filtrado por la etiqueta de los grupos.
  - **Verificación:** una VM creada por el autoescalador aparece como
    destino activo.
- **Responsable y plazo:** @brehynnermraz, Entrega 4.
- **Estado:** pendiente.

#### DT-12 - Trazas apagadas en la nube y sin propagación API -> worker

- **Categoría:** operación.
- **Descripción y ubicación:** `OTEL_EXPORTER_OTLP_ENDPOINT` está vacío en la
  nube. El worker no recibe el `traceparent` de la API al encolar
  (`internal/queue`, `internal/tasks`).
- **Evidencia:** `CLAUDE.md`, "Deuda técnica conocida". Jaeger no cabe en
  2 GiB junto a la aplicación.
- **Impacto:** diagnóstico. Un trabajo lento no se puede relacionar con la
  petición que lo originó.
- **Prioridad y justificación:** P2. Los logs y métricas cubren la operación
  actual.
- **Tratamiento:**
  1. Agregar el `traceparent` al payload de la tarea.
  2. Exportar a Cloud Trace (administrado, sin VM propia).
  - **Verificación:** una sola traza abarca la petición HTTP y su
    procesamiento en el worker.
- **Responsable y plazo:** @brehynnermraz, Entrega 5.
- **Estado y decisión:** aceptada temporalmente por falta de memoria en la VM.

#### DT-13 - VMs de la Entrega 2 siguen encendidas

- **Categoría:** costo.
- **Descripción y ubicación:** `web-server` y `worker-server` de la Entrega 2
  se conservan para reconstruir la línea base de capacidad.
- **Evidencia:** pendiente de [`guia-mig.md`](guia-mig.md), sección 11.
- **Impacto:** costo. Dos `e2-highcpu-2` encendidas sin servir tráfico, y
  ocupan cuota de vCPU que el autoescalado necesita.
- **Prioridad y justificación:** P0, en cuanto terminen las pruebas
  comparativas.
- **Tratamiento:** detenerlas después de los escenarios heredados. Sus
  archivos se conservan en el repositorio para recrearlas.
  - **Verificación:** `gcloud compute instances list` sin esas VMs en
    ejecución.
- **Responsable y plazo:** @Klealp, cierre de la Entrega 3.
- **Estado:** pendiente.

#### DT-14 - Antimalware de demostración

- **Categoría:** seguridad.
- **Descripción y ubicación:** el escaneo de archivos subidos
  (`internal/tasks/scan.go`) solo detecta la firma de prueba EICAR. La
  interfaz permite conectar ClamAV.
- **Evidencia:** decisión documentada en `CLAUDE.md`. Prueba de humo
  `smoke_eicar.sh`.
- **Impacto:** seguridad. Un archivo malicioso real se publicaría a los
  estudiantes.
- **Prioridad y justificación:** P2. ClamAV necesita alrededor de 1 GiB de
  memoria por worker, lo que obliga a cambiar el tipo de máquina del grupo
  de workers.
- **Tratamiento:** contenedor `clamd` en las VMs worker detrás de la interfaz
  existente.
  - **Verificación:** `smoke_eicar.sh` sigue pasando con ClamAV y una firma
    real se rechaza.
- **Responsable y plazo:** @brehynnermraz, Entrega 5.
- **Estado y decisión:** aceptada temporalmente por costo de memoria.

#### DT-15 - Filtros resueltos en el BFF y constantes duplicadas

- **Categoría:** código.
- **Descripción y ubicación:** `GET /courses` no filtra. `GET /admin/audit`
  no filtra por fecha: el frontend pide 500 líneas y recorta. La lista de
  acciones de auditoría está copiada en
  `frontend/src/components/admin/audit-filters.tsx`, a partir de
  `internal/audit/audit.go`.
- **Evidencia:** `CLAUDE.md`, "Deuda técnica conocida".
- **Impacto:** desempeño (transfiere datos de más) y mantenibilidad (una
  acción nueva obliga a tocar dos archivos).
- **Prioridad y justificación:** P3. Volumen bajo en el uso actual.
- **Tratamiento:** llevar los filtros al `WHERE` y exponer la lista de
  acciones en el contrato OpenAPI para que el frontend la genere con
  `npm run gen:api`.
  - **Verificación:** el BFF ya no recorta resultados.
- **Responsable y plazo:** @WhiteArctic con apoyo de backend, sin plazo.
- **Estado y decisión:** aceptada.

#### DT-16 - Acciones de GitHub en Node 20

- **Categoría:** pipeline.
- **Descripción y ubicación:** `actions/checkout@v4`, `actions/setup-go@v5`,
  `actions/upload-artifact@v4` y `sonarqube-scan-action@v6` declaran Node 20.
  Además, `ubuntu-latest` migra a Ubuntu 26.
- **Evidencia:** advertencias en las anotaciones del
  [run 41163150503](https://github.com/esanto92/Platform-MOOC-Cloud/actions/runs/41163150503).
- **Impacto:** el pipeline obligatorio puede dejar de funcionar cuando GitHub
  retire Node 20.
- **Prioridad y justificación:** P1. Corrección de minutos, pero conviene no
  cambiar el pipeline justo antes del commit final de la línea base.
- **Tratamiento:** subir a las versiones mayores que declaran Node 24 y fijar
  `runs-on: ubuntu-24.04`.
  - **Verificación:** run sin advertencias.
- **Responsable y plazo:** @esanto92, Entrega 4.
- **Estado:** pendiente.

---

## 5. Priorización y plan de tratamiento

Criterios, en orden: (1) requisitos obligatorios de la entrega y exposición
de seguridad pública; (2) riesgo para la disponibilidad del escenario
elástico; (3) dependencias (lo que desbloquea otras correcciones); (4) costo
de la corrección.

| Plazo | Elementos | Motivo |
|---|---|---|
| Cierre de la Entrega 3 (P0) | DT-02, DT-09, DT-10, DT-13 | Contraseñas en documentación pública; reconstrucción reproducible obligatoria; costo de VMs sin uso |
| Entrega 4 (P1) | DT-04, DT-05, DT-16, luego DT-08, DT-07, DT-11 | Primero las pruebas, que desbloquean refactorizaciones seguras; después los riesgos del escenario elástico |
| Entrega 5 (P2) | DT-01, DT-06, DT-12, DT-14 | Dependen de DT-04 o de cambios de infraestructura con costo |
| Aceptadas (P3) | DT-03, DT-15 | Mitigadas o de bajo impacto; se revisan en cada entrega |

Hallazgos Major abiertos al cierre: los de DT-01 (4) y, si no se cierran
antes, los de DT-02 (2). Ambos están registrados con regla, ubicación,
impacto y motivo. No hay hallazgos Critical ni Blocker.

---

## 6. Línea base del commit final

La línea base oficial es el reporte del **commit final** de la Entrega 3.
Esta sección se completa al cerrar la entrega, con el run del pipeline sobre
el commit etiquetado `entrega-3`:

| Campo | Valor |
|---|---|
| Commit evaluado | _pendiente_ |
| Fecha del análisis | _pendiente_ |
| Ejecución del pipeline | _pendiente_ |
| Reporte | `calidad/<sha>-linea-base/` (copia del artefacto `reporte-sonarqube-<sha>`) |
| Duplicación | _pendiente_ |
| Mantenibilidad | _pendiente_ |
| Deuda técnica estimada | _pendiente_ |
| Hallazgos abiertos | _pendiente_ |

Procedimiento:

1. Ejecutar el pipeline sobre el commit final y verificar que pasa.
2. Descargar el artefacto con
   `gh run download <run> -R esanto92/Platform-MOOC-Cloud` y copiarlo a
   `docs/entrega3/calidad/<sha>-linea-base/`. GitHub borra los artefactos a
   los 90 días; la copia en el repositorio es la que perdura.
3. Llenar la tabla y actualizar el estado de los elementos P0 del inventario.
