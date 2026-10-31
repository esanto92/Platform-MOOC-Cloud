# Verificación funcional del frontend — Entrega 3

Evidencia de que los recorridos mínimos de **estudiante** y **profesor** se
completan **desde el navegador**, sobre el entorno cloud, sin llamadas manuales
a la API. Complementa la arquitectura (`arquitectura.md`) y el video de
sustentación (enlazado desde el `README.md` raíz).

## 1. Entorno verificado

| Dato | Valor |
|---|---|
| URL del frontend (HTTPS) | `https://34-149-212-102.sslip.io/` |
| URL del balanceador de API (HTTPS) | `<COMPLETAR>` |
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
