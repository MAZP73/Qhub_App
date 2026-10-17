# Qhub App — Plan

Fecha: 2026-10-17 · Estado: **propuesto, pendiente de aprobación** (no hay código aún).

Fuentes: API (`/home/miguelzambrano/projects/Qhub`: README, CLAUDE, CONTEXTO, PENDIENTES) y design system (https://claude.ai/artifact/359jKRUBxnvzJYn9nH8Srv). Reglas de trabajo en [CLAUDE.md](CLAUDE.md).

## 1. Qué se construye

| | Escritorio `admin_desktop` | Móvil `mobile` |
|---|---|---|
| Quién | Personal de una organización (admin / agente) | Público que hace fila |
| Plataformas | Linux, Windows, macOS | Android, iOS |
| Qué hace | Colas y horarios, fila en vivo, llamar/finalizar/no-show, historial, métricas, equipo | Explorar organizaciones, sacar turno (ahora o reservado), ver posición en vivo, avisos, historial |
| Supabase propio | Perfiles del staff, roles/agentes, preferencias, auditoría, snapshots para métricas/IA | Perfiles del público, directorio de organizaciones (dirección, geo), favoritos, tokens push, historial local |
| Conexión a la API | Directa (login de la organización) | Ver decisión **D1** |

Ambas apps son Flutter, Clean Architecture, y comparten dos paquetes: cliente de la API y UI (design system).

## 2. Estructura del repo

```
Qhub_App/
├── CLAUDE.md · PLAN.md
├── compose.yaml                 # servicios Docker (ver §6)
├── docker/                      # Dockerfile.tooling · Dockerfile.android · Dockerfile.linux
├── melos.yaml · pubspec.yaml    # workspace Dart
├── packages/
│   ├── qhub_core/               # Result/Failure, utilidades, zona horaria, formateo de turno
│   ├── qhub_api_client/         # cliente de la API Qhub (domain + data), WS, errores tipados
│   └── qhub_ui/                 # tokens generados de tokens.json, tema claro/oscuro, widgets qh-*, íconos, logo
├── apps/
│   ├── admin_desktop/           # .env · .env.example · .env.secret(.example)
│   └── mobile/                  # .env · .env.example · .env.secret(.example)
├── supabase/
│   ├── admin/                   # migraciones SQL + RLS del proyecto de escritorio
│   └── mobile/                  # migraciones SQL + RLS + Edge Functions del proyecto móvil
└── tool/                        # gen_tokens.dart (tokens.json → Dart), scripts
```

Cada feature de cada app: `domain/{entities,repositories,usecases}` · `data/{datasources,dtos,repositories}` · `presentation/{pages,widgets,state}`. Regla de dependencia: `presentation → domain ← data`; `domain` en Dart puro.

Stack: Riverpod, go_router, dio, web_socket_channel, freezed + json_serializable, supabase_flutter, flutter_secure_storage, flutter_svg, melos.

## 3. `.env` (los nombres; los valores los pones tú)

`apps/admin_desktop/.env` y `apps/mobile/.env` — **públicos**, se empaquetan en la app:
```
APP_ENV=
QHUB_API_BASE_URL=
QHUB_WS_BASE_URL=
SUPABASE_URL=
SUPABASE_ANON_KEY=          # publishable/anon: segura en cliente porque RLS protege
```
`.env.secret` en cada app — **nunca** en assets, gitignored, solo scripts/migraciones/Edge Functions:
```
SUPABASE_SERVICE_ROLE_KEY=  # secret key: JAMÁS dentro de la app instalada
SUPABASE_DB_PASSWORD=
SUPABASE_ACCESS_TOKEN=      # para el CLI de Supabase (migraciones/deploy de funciones)
SUPABASE_PROJECT_REF=
```
Solo móvil, si se adopta D1-A: `QHUB_ADMIN_API_KEY` y las api keys por organización viven como *secrets* de las Edge Functions (Supabase Vault), no en el `.env` de la app.

Se entregan `.env.example` (nombres) y `.env` vacíos + `.gitignore`. Pedirle a Dart un valor secreto está prohibido por lint/CI (grep de `SERVICE_ROLE` en `lib/`).

## 4. Decisiones abiertas (necesito tu respuesta)

**D1 — ¿Cómo habla el móvil con la API?** Es el punto delicado. La API autentica a la **organización**, no a la persona: quien tenga un token puede actuar como cualquier persona de esa cuenta (su propio README lo advierte: "el token debe quedar en el backend del integrador, no en una app pública"). Además, el público elige entre **muchas** organizaciones, y cada una tiene su credencial.
- **A (recomendada): Edge Functions en el Supabase del móvil como intermediario.** El móvil se autentica con Supabase Auth; la función guarda las api keys de cada organización (Vault), hace `POST /auth/token`, y llama a la API con `X-Usuario-Id = id del usuario Supabase` y rol cliente. El móvil nunca ve una credencial de la API. Aún es "directo" en el sentido de que no hay servidor propio que mantener. Cuesta: una capa más, y el tiempo real hay que reenviarlo (Supabase Realtime / polling corto al inicio).
- **B: móvil directo con un token embebido.** Más simple, pero el token queda extraíble del APK, solo sirve para una organización y cualquiera podría leer/cancelar turnos de otros usuarios. No lo recomiendo.
En ambos casos el código usa un puerto `QhubGateway` en `domain`, así que la decisión solo cambia el adaptador y **no bloquea** las fases 0–3.

**D2 — Alta de organizaciones en el directorio móvil.** Para que una organización aparezca en el móvil hay que registrar su api key en el Supabase móvil (y su dirección/geo). Propuesta: la registra el dueño de la plataforma con un script/función admin; luego se puede dar un botón "Publicar en la app móvil" en el escritorio.

**D3 — Notificaciones push (FCM/APNs).** La API solo entrega por WebSocket y por el canal `log`; no hay webhook. Sin push, el aviso "te toca" no llega con la app cerrada. Opciones sin tocar la API: la Edge Function consulta `GET /notificaciones` periódicamente (barato, con retraso) ; o **modificar la API** para añadir un canal webhook/FCM → eso requiere un plan aparte de tu aprobación (Regla #2).

**D4 — Sesión del escritorio.** El token dura 60 min y no hay refresh. Propuesta: opción "Mantener sesión" que guarda la credencial en `flutter_secure_storage` y re-loguea en silencio al recibir 401; sin ella, se pide login de nuevo.

**D5 — Rol del staff.** La API confía en `X-Usuario-Rol`. El escritorio decide el rol desde su propio Supabase (tabla de staff) y lo envía; la UI oculta lo que el rol no permite. Confirmar que quieres admin/agente.

## 5. Desajustes diseño ↔ API (a resolver, ninguno bloquea el arranque)

| El diseño muestra | La API tiene | Propuesta |
|---|---|---|
| Número `A-023` | `numero` entero por día, sin prefijo | Prefijo = inicial/código de la cola, calculado en cliente (`qhub_core`); mostrar 3 dígitos |
| "Sede", "Cómo llegar" | Sin dirección ni geo | Vive en el Supabase móvil (directorio) y en el de escritorio (ajustes de la organización) |
| "~9 min" y "personas delante" | Solo `posicion` y `GET /colas/{id}/estado` | Estimación en cliente: `posicion × duracion_turno_minutos / puestos`; después, IA con histórico (fase 6) |
| "Te avisamos cuando falten 2 turnos" | Avisos solo por llamado/pospuesto/no-show/recordatorio | Aviso local en cliente al cruzar el umbral vía WS; push depende de D3 |
| Métricas / AdminHistory | Solo histórico crudo `GET /turnos` | Calcular en cliente; cachear agregados en el Supabase del escritorio |

Cualquier cambio en la API que de aquí salga se presenta **como plan antes de tocar nada**.

## 6. Docker

`compose.yaml` en la raíz, con perfiles:

| Servicio | Imagen / Dockerfile | Para qué |
|---|---|---|
| `tooling` | `docker/Dockerfile.tooling` (Flutter SDK estable fijado + melos) | `analyze`, `test`, `build_runner`, `gen_tokens`, `pub get` |
| `build-android` | `docker/Dockerfile.android` (Flutter + Android SDK/JDK) | APK/AAB del móvil |
| `build-linux` | `docker/Dockerfile.linux` (Flutter + deps GTK/clang/cmake) | binario Linux del escritorio |
| `supabase-cli` | imagen oficial del CLI | migraciones y deploy de Edge Functions (usa `.env.secret`) |
| `qhub-api` (perfil `local-api`) | `include:` del compose de `/home/miguelzambrano/projects/Qhub` | levantar la API para desarrollo |

Notas honestas: Windows y macOS (y iOS) **no** se pueden compilar en contenedores Linux; para esos hay que usar CI con runners nativos. Para ejecutar la UI mientras desarrollas se usa Flutter en el host (Linux/WSL); Docker cubre calidad, builds y herramientas. El volumen de caché de `pub` y de Gradle se comparte entre servicios.

## 7. Fases

Cada fase termina con `flutter analyze` limpio, tests de la capa tocada y revisión visual contra el artefacto.

**Fase 0 — Fundaciones**
- [ ] Workspace melos, `compose.yaml`, Dockerfiles, `.gitignore`, `.env`/`.env.example`/`.env.secret.example`, `git init`
- [ ] Lints estrictos + regla anti-secretos
- [ ] Crear apps con `flutter create` dentro del contenedor `tooling`

**Fase 1 — `qhub_ui` (design system)**
- [ ] `tool/gen_tokens.dart`: `tokens.json` del artefacto → `QhTokens` + `ThemeExtension` claro/oscuro
- [ ] IBM Plex Sans/Mono como assets, escala tipográfica del artefacto
- [ ] 35 íconos SVG → `QhIcon`; logos (horizontal, negativo, ícono, símbolo)
- [ ] Widgets: Button (6 variantes), TextInput, Select, DateSlotPicker, Tabs, DataTable, QueueTile, TurnBadge, Notification/Toast, Modal, EmptyState, Skeleton, LiveIndicator
- [ ] Galería de widgets (golden tests claro/oscuro)

**Fase 2 — `qhub_api_client`**
- [ ] Entidades de dominio (Cola, Horario, Franja, Turno, Notificación, Cuenta) y puertos
- [ ] Dio + interceptores: Bearer, `X-Usuario-Id`/`X-Usuario-Rol`, mapeo 400/401/403/404/409/422/429 a `Failure`, paginación
- [ ] Endpoints: auth, colas (+horario, franjas, estado, límite), turnos, notificaciones, salud
- [ ] WebSocket: `/ws/turnos/{cola}` y `/ws/notificaciones`, ping, cierre 4401, reconexión con backoff
- [ ] Tests de contrato con fakes (la API no tiene suite)

**Fase 3 — Escritorio**
- [ ] Supabase admin: migraciones (`staff`, `ajustes`, `auditoria`, `snapshots`) + RLS; auth del staff
- [ ] Login/registro de organización (AdminLogin), sesión según D4
- [ ] Colas: listado con tiles y límite 6/3, crear/editar/eliminar/reactivar (AdminQueues, AdminQueueEdit)
- [ ] Horario: apertura/cierre, franja, días, duración de trámite, puestos, zona horaria; cupos derivados en vivo
- [ ] Fila en vivo (AdminLive): WS, llamar siguiente, finalizar, no-show con confirmación, estados con color+ícono+palabra
- [ ] Historial con filtros y paginación (AdminHistory); exportar CSV
- [ ] Equipo/roles (D5), ajustes de organización, tema claro/oscuro, atajos de teclado
- [ ] Builds: `build-linux` en Docker; Windows/macOS por CI nativo

**Fase 4 — Móvil**
- [ ] Supabase móvil: migraciones (`perfiles`, `organizaciones`, `favoritos`, `dispositivos`) + RLS; Supabase Auth
- [ ] Implementar D1 (Edge Function intermediaria o alternativa elegida) detrás de `QhubGateway`
- [ ] Explorar organizaciones y colas (MobileOrg) con estado de fila
- [ ] Sacar turno: ahora o reservar con DateSlotPicker contra `/colas/{id}/franjas`; manejo de 409 con propuesta de otra franja (MobileTakeTurn)
- [ ] Mi turno en vivo (MobileMyTurn): posición, estimado, posponer, cancelar
- [ ] Avisos (MobileNotifications) y historial (MobileHistory)
- [ ] Build `build-android` en Docker; iOS por CI macOS

**Fase 5 — Tiempo real y push**
- [ ] Reconexión/estado de conexión visible, aviso local "faltan N turnos"
- [ ] Push según D3 (plan separado si implica cambiar la API)

**Fase 6 — IA (en las apps, no en la API)**
- [ ] Estimación de espera con histórico de `GET /turnos`; detección de picos en escritorio; agente conversacional opcional

**Fase 7 — Endurecimiento**
- [ ] Accesibilidad (contraste AA, foco, lector de pantalla), i18n base es-EC
- [ ] Manejo offline, rate limit 429 con reintento, errores amigables
- [ ] Revisión de seguridad: nada secreto en binarios, RLS probada, `APP_ENV=production`
- [ ] CI: analyze + test + builds en Docker; runners nativos para Windows/macOS/iOS

## 8. Riesgos

- La API **no tiene tests ni `schema.sql`** y sus claves aparecen como pendientes de rotar (PENDIENTES.md): no usar las actuales fuera de desarrollo.
- Aislamiento entre cuentas: la API responde 404 para lo ajeno; la UI debe tratar 404 como "no existe", no como bug.
- CloudAMQP free: ~140 colas activas en total entre todas las organizaciones.
- Zona horaria: todo el cálculo de franjas es en hora local de la cola; el cliente nunca debe calcular con la hora del dispositivo.
- Límite de colas 6/3 y nombres únicos solo entre activas: el formulario debe anticipar el 409.

## 9. Estado (2026-10-17)

**Decisiones tomadas:** Flutter/Dart; **un solo proyecto Supabase `Qhub_APP`** (ref `dsxmehbusarzkgxzverg`) compartido por escritorio y móvil (un solo login; el rol decide qué ve cada app). D1–D5: se adoptan las recomendadas (D1-A Edge Functions intermediarias; D2 alta por superadmin; D3 sin push hasta tener plan aprobado para la API; D4 "Mantener sesión" opcional; D5 roles admin/agente).

**Roles definidos**
| Nivel | Rol | Puede |
|---|---|---|
| Plataforma | `superadmin` | Todo; publica organizaciones y registra sus api keys |
| Plataforma | `usuario` | Público del móvil: su perfil, favoritos, dispositivos, su historial |
| Organización | `admin` | Gestiona su organización, miembros, invitaciones, ajustes, prefijos, auditoría |
| Organización | `agente` | Opera la fila (llamar/finalizar/no-show), ve ajustes y métricas |
El rol nunca viene del cliente: todo registro nace `usuario`; los miembros se crean con `crear_organizacion()` / `aceptar_invitacion()`. Rol de plataforma `superadmin` solo se asigna con service_role.

**Hecho**
- [x] `CLAUDE.md`, `PLAN.md`
- [x] Migración `supabase/migrations/20261017000001_init.sql` **aplicada** a `Qhub_APP`: 12 tablas con RLS (perfiles, organizaciones, organizacion_credenciales, miembros, invitaciones, ajustes_organizacion, cola_prefijos, favoritos, dispositivos, historial_turnos, auditoria, snapshots_metricas), funciones de rol, RPC, `anon` sin permisos
- [x] `.env` / `.env.example` / `.env.secret(.example)` en ambas apps y `.gitignore`

**Pendiente inmediato**
- [ ] Pegar en `.env.secret`: `SUPABASE_SECRET_KEY` y `SUPABASE_DB_PASSWORD` (si hacen falta)
- [ ] Docker: `compose.yaml` + Dockerfiles; `flutter create` de las apps dentro del contenedor `tooling`
- [ ] Fase 1 en adelante (§7)
- [ ] **Rotar el Personal Access Token** que se compartió por chat cuando termine la configuración inicial
