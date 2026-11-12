# Verificación funcional del frontend — Entrega 3

Evidencia de que los recorridos mínimos de **estudiante** y **profesor** se
completan **desde el navegador**, sobre el entorno cloud, sin llamadas manuales
a la API. Complementa la arquitectura (`arquitectura.md`) y el video de
sustentación (enlazado desde el `README.md` raíz).

## 1. Entorno verificado

| Dato | Valor |
|---|---|
| URL del frontend (HTTPS) | `https://34-149-212-102.sslip.io/` |
| URL del balanceador de API (HTTPS) | `https://34-149-212-102.sslip.io/api/v1`: es el mismo balanceador; el URL map envía `/api/v1/*` al grupo `mooc-api` y el resto al frontend ([arquitectura, 4.4](../arquitectura.md#44-balanceador)) |
| Versión desplegada del frontend | Imagen `mooc/web:61f22e4` (25-10-2026). **Es anterior a los últimos cambios del frontend.** Antes de la evidencia final se debe redesplegar desde el commit del tag ([arquitectura, 6.2](../arquitectura.md#62-desplegar-una-versión-nueva)) |
| Commit / tag evaluado | tag `entrega-3` |
| Base de datos | Cloud SQL PostgreSQL administrado |
| Cuentas usadas | Profesor de prueba, estudiante de prueba (sin contraseñas en este documento) |
| Navegador | Chrome |

Todas las capturas muestran la barra de direcciones con la URL del entorno
cloud (no `localhost`).

### Cómo se conecta el frontend con la API

El navegador **solo habla con Next.js** (same-origin). Next.js actúa como BFF:
guarda el token de sesión en una cookie `HttpOnly` y reenvía las peticiones a
la API con `Authorization: Bearer`. Por eso en DevTools → Network las
peticiones aparecen contra el dominio del frontend (`/api/...`) y no contra el
balanceador; la llamada a la API Go ocurre del lado del servidor. Las subidas de
archivos y las descargas sí van **directo al almacenamiento** con URLs
prefirmadas (la API nunca recibe el binario).

## 2. Matriz de flujos — Estudiante

| # | Flujo mínimo | Ruta de UI | Endpoint(s) de la API | Resultado | Evidencia |
|---|---|---|---|---|---|
| E1 | Iniciar sesión | `/login` | `POST /auth/login` | ✅ | `img/est-01-login.png` |
| E2 | Cerrar sesión | botón en la barra superior | `POST /auth/logout` | ✅ | `img/est-02-logout.png` |
| E3 | Consultar el catálogo | `/catalog` | `GET /catalog` | ✅ | `img/est-03-catalogo.png` |
| E4 | Ver el detalle de un curso publicado | `/catalog/[slug]` | `GET /catalog/:slug` | ✅ | `img/est-04-detalle.png` |
| E5 | Inscribirse | botón en `/catalog/[slug]` → redirige a `/learn/[enrollmentId]` | `POST /enrollments` | ✅| `img/est-05-inscripcion.png` |
| E6 | Acceder a mis cursos | `/learn` | `GET /enrollments` | ✅ | `img/est-06-mis-cursos.png` |
| E7 | Navegar módulos, unidades y recursos | `/learn/[enrollmentId]` | `GET /enrollments/:id/outline` | ✅ | `img/est-07-estructura.png` |
| E8 | Consumir video (HLS) | `/learn/[enrollmentId]` | `GET /assets/:id/playlist` (vía `/api/assets/[id]/playlist`) | ✅| `img/est-08-video.png` |
| E9 | Consumir documento / imagen / descarga | `/learn/[enrollmentId]` | `GET /assets/:id/url` (URL prefirmada) | ✅ | `img/est-09-documento.png` |
| E10 | Leer un recurso de texto | `/learn/[enrollmentId]` | `GET /enrollments/:id/resources/:resourceId/content` | ✅ | `img/est-10-texto.png` |
| E11 | Registrar y consultar progreso | barra de progreso en `/learn/[enrollmentId]` | `POST /progress/events` (el servidor calcula el %) | ✅ | `img/est-11-progreso.png` |
| E12 | Presentar un quiz | `/learn/[enrollmentId]` (recurso tipo quiz) | `POST /quizzes/:id/attempts`, `PATCH /attempts/:id`, `POST /attempts/:id/submit` | ✅ | `img/est-12-quiz.png` |
| E13 | Consultar el resultado del quiz | mismo recurso tras enviar | `GET /attempts/:id` | ✅ | `img/est-13-resultado.png` |

## 3. Matriz de flujos — Profesor

| # | Flujo mínimo | Ruta de UI | Endpoint(s) de la API | Resultado | Evidencia |
|---|---|---|---|---|---|
| P1 | Iniciar sesión | `/login` | `POST /auth/login` | ✅ | `img/prof-01-login.png` |
| P2 | Cerrar sesión | botón en la barra superior | `POST /auth/logout` | ✅ | `img/prof-02-logout.png` |
| P3 | Consultar mis cursos | `/teach` | `GET /courses` | ✅| `img/prof-03-mis-cursos.png` |
| P4 | Crear un curso | `/teach/new` → redirige a `/teach/[courseId]` | `POST /courses` | ✅| `img/prof-04-crear-curso.png` |
| P5 | Editar los datos del curso | `/teach/[courseId]` | `PATCH /courses/:id` | ✅| `img/prof-05-editar-curso.png` |
| P6 | Crear módulos | `/teach/[courseId]` | `POST /versions/:id/modules` | ✅| `img/prof-06-modulo.png` |
| P7 | Crear unidades | `/teach/[courseId]` | `POST /modules/:id/units` | ✅| `img/prof-07-unidad.png` |
| P8 | Agregar recurso de texto | `/teach/[courseId]` (diálogo "agregar recurso"), `/teach/[courseId]/resource/[resourceId]` | `POST /units/:id/resources`, `GET`/`PUT /resources/:id/content` | ✅ | `img/prof-08-recurso-texto.png` |
| P9 | Cargar un archivo (reanudable) | diálogo de recurso en `/teach/[courseId]` | `POST /uploads` → PUT directo al almacenamiento → `POST /uploads/:id/complete` | ✅| `img/prof-09-carga.png` |
| P10 | Consultar el estado de procesamiento del archivo | indicador de estado del recurso | `GET /assets/:id` (sondeo) | ✅ | `img/prof-10-procesando.png` |
| P11 | Crear / editar un quiz básico | `/teach/[courseId]/quiz/[quizId]` | `PATCH /quizzes/:id`, `POST /quizzes/:id/questions`, `PATCH`/`DELETE /questions/:id` | ✅| `img/prof-11-quiz.png` `img/prof-11-crear-pregunta.png` |
| P12 | Publicar el curso | botón de publicar en `/teach/[courseId]` | `POST /versions/:id/publish` | ✅ | `img/prof-12-publicar.png` |
| P13 | Consultar el resultado de la publicación (éxito o lista de problemas) | `/teach/[courseId]` | respuesta de `POST /versions/:id/publish` (422 con `problems`) | ✅|`img/prof-13-publicacion-error.png` |

## 4. Estados de la interfaz

| Estado | Dónde se ve | Texto o comportamiento | Resultado | Evidencia |
|---|---|---|---|---|
| Carga | `/catalog`, `/learn` | Esqueletos (`loading.tsx`) | ✅| `img/est-03-catalogo.png` |
| Vacío | `/learn` sin inscripciones | "Aún no te has inscrito" | ✅ | `img/est-vacio-learn.png` |
| Vacío | `/teach` sin cursos | "Aún no has creado cursos…" | ✅| `img/prof-03-mis-cursos.png` |
| Vacío | Curso sin módulos | "Esta versión aún no tiene módulos." | ✅| `img/prof-vacio-modulos.png` |
| Procesamiento | Archivo en `scanning` / `processing` | "Preparando el archivo" / "Procesando…". **No se muestra como disponible**: el contenido solo se entrega con `asset_status = ready` (el backend responde 409 en otro caso) | ✅| `img/prof-10-procesando.png` |
| Éxito | Quiz aprobado, publicación correcta | "¡Aprobado!", confirmación de publicación | ✅| `img/est-13-resultado.png` |
| Error | Credenciales inválidas, publicación con problemas, archivo infectado | "Credenciales inválidas.", lista de problemas, "Archivo no disponible" | ✅| `img/est-error.png` |

## 4.1 Autorización entre roles

El enunciado exige verificar que un estudiante no pueda ejecutar acciones
reservadas al profesor y que un profesor no pueda modificar cursos ajenos. La
interfaz oculta esas acciones, pero la regla se aplica **en la API**:

- el rol se exige con `requireRole("teacher", "admin")` en `internal/api/router.go`;
- la propiedad se resuelve en el `WHERE` de cada consulta (`s.guard`).

Por eso se verifica desde el navegador y también llamando directo a la API.

| # | Caso | Desde el navegador | Esperado en la interfaz | Llamada directa a la API | Esperado en la API | Resultado | Evidencia |
|---|---|---|---|---|---|---|---|
| A1 | Estudiante abre la autoría | Con sesión de estudiante, ir a `/teach` o `/teach/new` | `requireTeacher` redirige a `/forbidden` (`frontend/src/lib/auth/guards.ts`) | `POST /api/v1/courses` con el token del estudiante | **403** "Tu rol no permite esta operacion." | PENDIENTE | `img/aut-01-estudiante-teach.png` |
| A2 | Estudiante intenta editar o publicar | Ir a `/teach/<courseId>` de un curso existente | `/forbidden` | `PATCH /api/v1/courses/<id>` y `POST /api/v1/versions/<id>/publish` con el token del estudiante | **403** | PENDIENTE | `img/aut-02-estudiante-editar.png` |
| A3 | Profesor B abre el curso del profesor A | Con sesión de B, ir a `/teach/<courseId de A>` | "No encontrado": la página llama a `notFound()` cuando la API responde 404 (`teach/[courseId]/page.tsx`) | `PATCH /api/v1/courses/<id de A>` con el token de B | **404** (restricción 8: lo ajeno responde 404, no 403) | PENDIENTE | `img/aut-03-profesor-ajeno.png` |
| A4 | Profesor B modifica la estructura del curso de A | — | — | `POST /api/v1/versions/<versión de A>/modules` con el token de B | **404** | PENDIENTE | salida de `curl` |
| A5 | Un estudiante consulta la inscripción de otro | — | — | `GET /api/v1/enrollments/<inscripción ajena>/outline` | **404** | ✅ en local (`smoke.sh`, paso 13) | `docs/entrega1/testdata/smoke.sh` |

Para A1 a A4 contra el entorno cloud, los tokens se obtienen con
`POST /api/v1/auth/login` y **no se pegan en la evidencia**:

```bash
API=https://34-149-212-102.sslip.io/api/v1
curl -s -o /dev/null -w "%{http_code}\n" -X PATCH "$API/courses/$CURSO_A" \
  -H "Authorization: Bearer $TOKEN_PROFESOR_B" -H 'Content-Type: application/json' \
  -d '{"title":"intento ajeno"}'          # esperado: 404
```

## 4.2 Recorrido conectado

Debe demostrarse sobre un **mismo curso**, en el entorno cloud y en este
orden:

1. El profesor crea el curso (P4 a P8).
2. Sube un video y espera a que esté procesado (P9 y P10).
3. Crea el quiz (P11) y publica (P12).
4. El estudiante encuentra el curso en el catálogo (E3 y E4) y se inscribe
   (E5).
5. Reproduce el video (E8), registra progreso (E11) y presenta el quiz (E12 y
   E13).

En las capturas y en el video conviene que se vean el título del curso y la
URL del entorno. Si las capturas de las secciones 2 y 3 se tomaron sobre
cursos distintos, o sobre una versión del frontend distinta de la
desplegada, hay que repetir el recorrido sobre un solo curso después del
redespliegue.

## 5. Evidencia complementaria

| Evidencia | Qué demuestra | Ubicación |
|---|---|---|
| Prueba de humo del flujo completo | Reglas de negocio vía API (progreso, idempotencia, aislamiento) | `docs/entrega1/testdata/smoke.sh` |
| Auditoría de accesibilidad WCAG 2.2 AA (Playwright + axe) | 19 páginas de los cuatro roles, tema claro y oscuro | `docs/entrega3/FuncionalidadFront/PruebaAccesibilidad/resultados/REPORTE.md` |
| Colección de Postman (entorno Nube) | Contrato de la API desplegada | `postman/` |

## 6. Limitaciones conocidas

- La interfaz permite **crear y eliminar** módulos y unidades, pero **no
  renombrarlos** (la API sí expone `PATCH /modules/:id` y `PATCH /units/:id`).
  Si el enunciado se lee como "editar la estructura", conviene decidir si se
  agrega o se documenta como fuera de alcance.
- Subtítulos y transcripciones de video/audio (WCAG 1.2.2 y 1.2.5) siguen
  pendientes.
