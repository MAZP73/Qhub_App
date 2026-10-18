# Diseño técnico — Notificaciones en tiempo real (web), cifrado de la clave inicial y paridad del perfil móvil

Este documento cubre las tres mejoras sobre el monorepo `Qhub_App` (worktree `/.worktrees/mejoras-web-movil`). Todo el trabajo ocurre en los clientes (`apps/web`, `apps/mobile`), en los paquetes compartidos (`packages/*`) y en Supabase (`supabase/*`), que forman parte de `Qhub_App`. **La API Qhub (`/home/miguelzambrano/projects/Qhub`) es de solo lectura y no se toca.** Ninguna de las tres tareas necesita cambios en la API: todo lo que hace falta ya está expuesto.

Convenciones que se respetan (de `CLAUDE.md`, `docs/arquitectura.md`, `docs/estructura.md`):

- **Clean Architecture por feature con subcarpetas de capa.** La estructura real del worktree (verificada: `apps/web/src/features/{staff,notifications,invitation}/{domain,data,presentation}/`) es `features/<feature>/{domain,data,presentation}/`; **cada archivo nuevo va en la subcarpeta de su capa**. `domain/` es TypeScript puro (sin React, sin `fetch`, sin Supabase); `data/` es el único lugar con Supabase/WebSocket/`fetch`; `presentation/` usa React/React Native + TanStack Query y nunca ve errores crudos. (En este worktree no existe un `architecture.test.ts`; la disciplina de capas se mantiene por la ubicación de cada archivo en su subcarpeta y por no importar `data/` desde `domain/`.)
- **Errores tipados**: todo sale como `Result<T>`/`Failure` de `@qhub/core`; las pantallas usan `friendlyError(e)` o `failure.message` (ya saneado) y nunca muestran detalle técnico.
- **Design system**: solo utilidades de Tailwind sobre tokens (`@qhub/design`): web Tailwind v4, móvil NativeWind. Nada de hex/tamaños/radios sueltos. Español, tuteo, sentence case, botones de 1–3 palabras, 24 h, turnos `A-023`, IBM Plex.
- **No duplicar**: lo que comparten web y móvil vive en `packages/` (p. ej. geografía en `@qhub/core`, la API en `@qhub/api-client`).
- **Localhost intacto**: `QHUB_API_URL`/`QHUB_WS_URL` del `.env` raíz y `docker compose up -d --build` siguen igual.
- **Puerta de verificación**: `bash tool/verify.sh` debe terminar en exit 0 (instala, genera el design system, typecheck estricto, todos los tests, build de la web, export de Expo, tests Deno de las Edge Functions, contrato HTTP/WS contra la API real, ownership de turnos y RLS).

---

## Tarea 1 — Notificaciones en tiempo real en la plataforma web (`apps/web`)

Coexisten **dos** sistemas de avisos distintos y ambos pasan a tiempo real sin tocar la API:

1. **Avisos personales de la API Qhub** (`WS /ws/notificaciones`), ya implementado en `@qhub/api-client` (`RealtimeRepositoryImpl.subscribeNotifications`).
2. **Avisos del equipo** (`notificaciones_staff` en Supabase), hoy por *polling* con TanStack Query; pasan a Supabase Realtime con *fallback* al polling.

### 1A — Avisos personales de Qhub (`/ws/notificaciones`)

**Hallazgo y decisión de alcance.** El repositorio `notifications` (`NotificationRepositoryImpl`, REST `GET /notificaciones`) está cableado en `apps/web/src/app/container.tsx` pero **no se consume en ninguna pantalla**. El WS `/ws/notificaciones` entrega los avisos de **la persona** identificada en `?token=<access_token>:<usuario_id>:<rol>`; en la web ese actor es el integrante del staff (admin/agente) con el token de la **cuenta** Qhub de la organización (`ApiContext.token` + `ApiContext.actor = { userId, role }`, fijado por `AppSession`/`ConnectToQhub`). Los tipos de aviso personales (`turno_llamado`, `turno_pospuesto`, `turno_no_show`, `recordatorio`) son del punto de vista de **quien saca un turno**. Un integrante del staff solo recibirá avisos si él mismo tiene turnos en esa cuenta Qhub; en la operación normal del panel puede no recibir ninguno. Esto es inherente al contrato de la API (no se puede suscribir a «todos los avisos de la cuenta» sin cambiar la API, lo que está BLOQUEADO). **Decisión:** se implementa la suscripción personal de forma correcta y defensiva — se activa solo cuando hay conexión con Qhub (`session.connection.status === 'connected'`), se integra con el repositorio REST ya existente para la lista histórica y marca-leído, y alimenta el toast ya existente. No se inventa ningún canal nuevo ni se asume que el staff recibirá tráfico; si no llega nada, la superficie queda inerte y no estorba. Se documenta la limitación.

**Superficie elegida.** Un hook de presentación `useQhubNotifications` que: (a) carga el histórico con `notifications.list(...)` (REST, vía TanStack Query), (b) abre `realtime.subscribeNotifications(...)` mientras haya conexión Qhub, (c) ante cada aviso nuevo hace `queryClient.setQueryData`/`invalidateQueries` sobre la lista y dispara `toast.show(...)`. Se monta junto a `NoticePopups` en el shell del panel (una sola instancia). No se crea una página nueva: estos avisos personales son de bajo volumen y comparten el patrón de toast del equipo.

**Archivos (rutas absolutas bajo el worktree):**

- Crear `apps/web/src/features/notifications/domain/qhub-notifications.ts` — **capa domain** (TS puro). Reexporta/estrecha el tipo `AppNotification` de `@qhub/api-client` como modelo de presentación y define un `mapKindToText(kind)` puro (etiqueta en español por `tipo_aviso`) si hace falta un texto; sin React.
- Crear `apps/web/src/features/notifications/presentation/useQhubNotifications.ts` — **capa presentation**. Usa `useContainer()` (`notifications`, `realtime`), `useSession()` (para `connection`), TanStack Query y `useToast`. Suscribe/cancela en `useEffect` atado a `session.connection.status`.
- Crear `apps/web/src/features/notifications/presentation/QhubNotices.tsx` — **capa presentation**. Componente sin UI propia (como `NoticePopups`): monta el hook y emite toasts. Se añade al shell.
- Modificar `apps/web/src/features/shell/presentation/AppShell.tsx` — montar `<QhubNotices />` junto a `<NoticePopups />` (solo cuando hay sesión/organización).
- Crear tests: `apps/web/src/features/notifications/presentation/useQhubNotifications.test.ts(x)` usando `FakeRealtime` (que ya expone `subscribeNotifications`) y `FakeNotifications`.

**Capas y porqué:** el tipo/mapa va a `domain/` (regla pura, sin dependencias de framework). El hook y el componente van a `presentation/` (React + TanStack Query + toast). No se crea `data/` nuevo porque el adaptador WS (`RealtimeRepositoryImpl`) y el REST (`NotificationRepositoryImpl`) ya viven en `@qhub/api-client`.

**Diseño/tokens:** se reutiliza el `useToast`/`ToastProvider` existente; sin colores ni tamaños nuevos. Textos en español, tuteo.

**Errores (concretos):**
- WS cierra con **4401** (token inválido/vencido): `RealtimeRepositoryImpl` ya llama `onError(unauthorizedFailure())` y `context.onUnauthorized()`, que `AppSession` ya maneja (renueva o pide reconectar). El hook trata el `onError` como *no recuperable para esta suscripción*: no muestra toast de error técnico; a lo sumo deja de escuchar. **Logging:** a consola, nunca a pantalla.
- WS cae por red: `RealtimeRepositoryImpl` reconecta con backoff exponencial; el hook no hace nada (recuperable, transparente).
- `notifications.list()` REST falla: TanStack Query queda en `isError`; como es una superficie silenciosa (toasts), no se muestra error; el histórico simplemente no se rellena. **Logging:** a consola.
- Sin conexión Qhub (`connection !== 'connected'`): el hook **no** abre el socket (evita el `unauthorizedFailure` que `url()` lanza sin token/actor). Es el estado normal antes de conectar.

**Validación de entrada externa:** los mensajes del WS pasan por `notificationEventFromJson` (en `@qhub/api-client/data/mappers`), que ya descarta lo que no cumple el contrato; el JSON ajeno se ignora en silencio. No hay entrada de usuario nueva.

**Invariante y dueño:** «solo se escucha con sesión Qhub activa» lo hace cumplir la capa de presentación (el `useEffect` atado a `connection.status`); la API ya garantiza que cada persona solo recibe **sus** avisos de **esa** cuenta.

**Tests (qué cambia):** nuevos tests unitarios del hook con fakes. No se añade nada a `workspace.test.tsx`, pero debe **seguir pasando**: `QhubNotices` montado en el shell no abre socket en los tests porque `FakeRealtime.subscribeNotifications` devuelve un no-op y la conexión de prueba (`savedToken`) ya está `connected` — se verifica que el hook no rompe el render. Se mantiene `FakeNotifications` como está.

### 1B — Avisos del equipo (`notificaciones_staff`) en tiempo real con Supabase Realtime

Hoy `NotificationBell`, `NotificationsPage` y `NoticePopups` leen por polling (`useNotices` con `refetchInterval`, `NoticePopups` con `useQuery` cada 10 s) sobre `SupabaseNotificationsRepository`. Se añade un **adaptador de datos de tiempo real** que escucha `postgres_changes` de la tabla `notificaciones_staff` filtrado por organización, integrado con la caché de TanStack Query, con **fallback** al polling existente.

**Decisión de enfoque.** Supabase Realtime (`postgres_changes`) sobre `notificaciones_staff` acotado a `organizacion_id=eq.<org>`. Es la opción nativa, no requiere API ni worker, y la RLS ya protege la tabla. Alternativa descartada: Broadcast/Presence (pensado para efímero, no para cambios de fila). **Se elige `postgres_changes`.**

**Nota de verificación (requiere activación en Supabase, no es cambio de código del cliente):** `postgres_changes` exige que la tabla esté en la publicación `supabase_realtime`. Se añade esa configuración como **migración** (`alter publication supabase_realtime add table public.notificaciones_staff;`) para que forme parte del repo y del despliegue, de modo idempotente. La RLS de Realtime respeta las políticas `SELECT` existentes de la tabla (el usuario solo ve su organización), así que no se expone nada nuevo. Si en un entorno Realtime no está disponible, el fallback mantiene el comportamiento actual.

**Archivos:**

- Crear `apps/web/src/features/notifications/data/supabase-notifications-realtime.ts` — **capa data**. Clase `SupabaseNotificationsRealtime` que recibe el `SupabaseClient`, expone `subscribe(orgId, { onChange, onStatus }): () => void` usando `sb.channel('staff-notices:'+orgId).on('postgres_changes', { event: '*', schema: 'public', table: 'notificaciones_staff', filter: 'organizacion_id=eq.'+orgId }, cb).subscribe(...)`. Devuelve la función de baja (`sb.removeChannel`). No lanza: traduce fallos a `onStatus('error')`. Nombre `-realtime.ts` respeta la convención de datos.
- Crear el puerto en `apps/web/src/features/notifications/domain/notifications.ts` (archivo existente, **capa domain**): añadir interfaz `NotificationsRealtime { subscribe(orgId, handlers): () => void }` (TS puro, sin Supabase). El adaptador la implementa.
- Modificar `apps/web/src/app/container.tsx` — añadir `staffNoticesRealtime: NotificationsRealtime` al `Container` y construirlo con `new SupabaseNotificationsRealtime(sb)`.
- Modificar `apps/web/src/features/notifications/presentation/useNotices.ts` — tras montar las queries, abrir la suscripción realtime en un `useEffect`; en cada evento invalidar **por prefijo** (el comportamiento por defecto de TanStack Query, `exact: false`) con `qc.invalidateQueries({ queryKey: ['notices', orgId] })` + `qc.invalidateQueries({ queryKey: ['notices-count', orgId] })` (y `['notice-popups', orgId]` en `NoticePopups`). **Nota de la key:** la query real de la lista es `['notices', orgId, opts.limit ?? 100]` (tres elementos); invalidar con el prefijo de dos elementos `['notices', orgId]` cubre cualquier `limit`, exactamente como ya hace la función `refresh()` existente del hook. No hace falta conocer el `limit` para invalidar. **Fallback:** mantener `refetchInterval` tal cual, pero cuando la suscripción esté `connected` subir el intervalo a un valor largo (p. ej. a `false`/300 s) para no duplicar carga; si la suscripción reporta `error`/cae, restaurar el intervalo corto actual. Así nada se rompe si Realtime no está.
- Modificar `apps/web/src/features/notifications/presentation/NoticePopups.tsx` — misma suscripción para refrescar su query `['notice-popups', orgId]` al instante; mantiene el polling como fallback y su lógica de `seen`/toast intacta.
- Modificar `apps/web/src/testing/fakes.ts` — añadir `FakeNotificationsRealtime` (con `subscribe` que guarda handlers y un `emit()` para las pruebas, y `onStatus('connected')` al suscribir, igual que `FakeRealtime`).
- Modificar `apps/web/src/testing/harness.tsx` — cablear `staffNoticesRealtime` en `makeContainer` y en el tipo `TestContainer['fakes']`.
- Crear migración `supabase/migrations/20261025000001_realtime_avisos_staff.sql` — añade la tabla a la publicación `supabase_realtime` (idempotente, con guardas si ya está).
- Tests: `apps/web/src/features/notifications/presentation/useNotices.test.ts(x)` nuevo o ampliado para verificar que un `emit()` del fake invalida/refresca; `workspace.test.tsx` debe seguir verde (el fake entrega `connected` y no cambia los conteos salvo que se emita).

**Capas y porqué:** el adaptador Supabase es **data** (`*-realtime.ts`). El puerto `NotificationsRealtime` es **domain** (interfaz pura). El cableado en `useNotices`/`NoticePopups` es **presentation**. Se respeta «nada de Supabase fuera de `data/`»: la presentación solo toca el puerto a través del container.

**Diseño/tokens:** sin cambios visuales; la campana, la página y los popups son los existentes. El `LiveIndicator`/estado de conexión no se añade a la campana para no inventar UI; el tiempo real es transparente.

**Errores (concretos):**
- Canal no conecta o se cierra: `onStatus('error'|'closed')` → el hook **restaura el polling corto** (fallback). No se muestra error al usuario (recuperable). **Logging:** a consola.
- Evento con payload inesperado: se ignora; de todos modos el hook solo invalida la query (no confía en el payload para pintar). La fuente de verdad sigue siendo el `SELECT` con RLS.
- RLS niega (sesión caducada): Realtime deja de entregar; el fallback de polling recibirá el error normal de la query, que ya se maneja (`isError` en la campana/página muestra «No pudimos cargar los avisos.»).

**Validación de entrada externa:** el `filter` se arma con `orgId` que proviene de `session.membership.organization.id` (UUID del lado servidor, no entrada libre); aun así se interpola solo en el nombre del canal/filtro, sin construir SQL. La verdad la impone la RLS.

**Invariante y dueño:** «un integrante solo ve los avisos de su organización» lo garantiza la **RLS de la base** (política `SELECT` de `notificaciones_staff`), que Realtime respeta; el cliente no puede ampliarlo. El fallback a polling lo decide la **presentación**.

**Tests (qué cambia):** se añade `FakeNotificationsRealtime`; se verifica invalidación al emitir. No se regresa `workspace.test.tsx` porque el fake por defecto no emite y los conteos iniciales no cambian.

---

## Tarea 2 — Cifrar la clave inicial de la invitación (`claves_iniciales`)

### Situación actual (verificada en el código)

- La tabla `public.claves_iniciales` (`supabase/migrations/20261024000002_clave_inicial.sql`) guarda `clave text not null` **en texto plano**. Tiene RLS activa **sin políticas** y `revoke all` para `public/anon/authenticated`: nadie la lee por SQL directo.
- La escribe la Edge Function `qhub-invite` (`supabase/functions/qhub-invite/index.ts`) con el cliente `service_role`: `admin.from('claves_iniciales').upsert({ invitacion_id, clave: newPassword })`.
- La lee la función SQL `public.ver_clave_inicial(p_token)` (`security definer`), que valida que `auth.uid()` corresponda al **correo invitado** y que la invitación esté pendiente y no vencida. La web la llama vía `SupabaseStaffRepository.initialPassword` (RPC `ver_clave_inicial`) y la muestra una vez en `InvitationPage`.
- Un trigger borra la fila al aceptar (`trg_borrar_clave_inicial`).

El problema real: la contraseña está **en claro en reposo**. Aunque la RLS la oculta a los clientes, cualquier lectura con `service_role` (backups, un vistazo a la base) la ve en claro.

### Decisión de arquitectura y gestión de clave (justificada)

**Esto NO es un secreto por dispositivo**, así que el patrón de `device-credential-vault.ts` (clave AES-GCM no extraíble en IndexedDB del navegador) **no aplica**: la clave inicial la escribe un servidor (la Edge Function) y la lee otra persona en otro dispositivo. La clave de cifrado debe vivir **del lado servidor**, nunca en un binario de la app ni en el navegador.

Opciones evaluadas:

1. **Cifrar en una Edge Function con una clave del servidor (AES-GCM / Web Crypto en Deno), clave en `.env.secret` de las funciones.** Encripta `qhub-invite` al escribir; una función nueva desencripta al leer.
2. **Cifrar dentro de Postgres con `pgcrypto`** (`pgp_sym_encrypt`/`pgp_sym_decrypt`) usando una clave pasada como parámetro desde la Edge Function (nunca almacenada en la base).
3. **Supabase Vault** (`vault.create_secret`/`vault.decrypted_secrets`). PLAN.md ya recomienda Vault para *otro* secreto (la contraseña de Qhub). Vault cifra con una clave gestionada por Supabase fuera de la tabla.

**Elección: opción 1 — AES-GCM en Edge Functions con una clave simétrica del servidor.** Razones:

- **Coherencia criptográfica** con el repo: ya se usa AES-GCM/Web Crypto en `device-credential-vault.ts`; el mismo estilo (IV de 12 bytes, `AES-GCM`, `base64`) se reutiliza, ahora con una clave **del servidor**.
- **La clave jamás toca la base ni el cliente.** Vive en `CLAVE_INICIAL_KEY` dentro de `.env.secret` / secrets de las Edge Functions (misma disciplina que `SUPABASE_SERVICE_ROLE_KEY`). Un volcado de la tabla no revela nada sin esa clave.
- **No depende de extensiones ni de características de plataforma.** `pgcrypto` guardaría el cifrado en la base pero la clave tendría que viajar en cada RPC (más superficie); Vault ata la solución a disponibilidad/rotación de Supabase y complica el test RLS local. AES-GCM en Deno es autocontenido y usa la misma Web Crypto que ya emplea `device-credential-vault.ts`.

**Alcance real de la cobertura en el gate (importante, no se sobredimensiona):** el paso «Edge Functions» de `verify.sh` corre `deno test _shared/` — es decir, solo los **helpers puros** de `_shared/`. Los nuevos `_shared/crypto.ts` sí quedan cubiertos por su `crypto_test.ts` (ida y vuelta con una clave de prueba generada en el test). Lo que **NO** se ejercita en el gate es el flujo end-to-end de las funciones desplegadas (`qhub-invite`/`qhub-clave`) ni la presencia/validez real de `CLAVE_INICIAL_KEY`, porque el gate no levanta esas funciones con sus secrets. Por eso el cifrado/descifrado **se concentra en helpers de `_shared/` probados** y las funciones solo los orquestan; además se especifica abajo una validación de arranque de `CLAVE_INICIAL_KEY` con fallo controlado, y (recomendado) un test Deno de `qhub-clave`/`qhub-invite` con un fake de Supabase que cubra el caso «clave ausente» dentro de `_shared/` para que el gate lo alcance.
- **Separación de confianza correcta:** quien tiene `service_role` ya no basta para leer la clave; hace falta además `CLAVE_INICIAL_KEY`, que no está en la base.

Se descartan 2 y 3 por acoplar la clave a la base (2) o a una característica de plataforma difícil de verificar en el gate local (3); ambas son válidas pero menos alineadas con el patrón existente y con «la clave no sale del servidor».

### Flujo nuevo

**Escritura (al invitar).** En `qhub-invite`, en vez de `upsert({ clave: newPassword })`, se cifra: `clave_cifrada = AES-GCM(newPassword, CLAVE_INICIAL_KEY)` y se guarda el texto cifrado (base64 con IV). La columna deja de contener texto plano.

**Lectura (al aceptar, una sola vez).** `ver_clave_inicial` (SQL) **ya no puede devolver la clave en claro** porque la base ya no la tiene. Se mueve la autorización + descifrado a una **Edge Function nueva `qhub-clave`** (POST, con el JWT del invitado):
1. Verifica sesión. El invitado ya tiene sesión Supabase activa al abrir `/invitacion` (hoy mismo llama la RPC `ver_clave_inicial` como `authenticated`). **El JWT lo adjunta automáticamente `sb.functions.invoke` desde la sesión Supabase activa**; no hay que pasar el token a mano. `qhub-clave` lo lee de `req.headers.get("Authorization")` y valida con `auth.getUser()` **exactamente como `qhub-invite`**.
2. Llama a una función SQL `security definer` (adaptada de `ver_clave_inicial`, renombrada `clave_inicial_cifrada`) que devuelve el **texto cifrado** solo si `auth.uid()` corresponde al correo invitado y la invitación está pendiente/vigente; si no, devuelve `null`.
3. Si hay sobre cifrado, lo descifra con `CLAVE_INICIAL_KEY` y responde `200 { clave: string }`; si la SQL devolvió `null` (sin clave autorizada: ya aceptada, vencida, o correo que no coincide) responde `200 { clave: null }`. Siempre con `Cache-Control: no-store`.

**Contrato HTTP exacto de `qhub-clave` (fijado, no ambiguo):**
```
POST /functions/v1/qhub-clave
Authorization: Bearer <jwt del invitado>   // lo adjunta sb.functions.invoke solo
body: { "token": string }                   // requerido; string no vacío tras trim

200  { "clave": string }   // autorizado y hay clave -> se muestra una vez
200  { "clave": null }     // autorizado pero sin clave (aceptada/vencida) o correo no coincide
400  { "error": "Revisa los datos." }   // token ausente/no-string/vacío tras trim
401  { "error": "Inicia sesión" }       // sin JWT válido
500  { "error": "..." }    // fallo de descifrado o CLAVE_INICIAL_KEY ausente/inválida
```
Se elige deliberadamente **`200 { clave: null }`** en vez de `404` para el caso «sin clave»: así el repo obtiene `ok(null)` sin tener que reinterpretar un `Failure`, que es justo lo que `InvitationPage` ya espera (`clave.data ?? null`). El `404` queda reservado y no se usa en este flujo.

Así se preserva la UX: el invitado sigue viendo/copiando la clave exactamente una vez, con la misma autorización (correo invitado, invitación vigente), y el trigger de borrado al aceptar queda igual.

### Archivos

- Modificar `supabase/functions/qhub-invite/index.ts` — cifrar antes del `upsert`. Importa el helper de cifrado compartido.
- Crear `supabase/functions/_shared/crypto.ts` — **helpers puros** `encrypt(plain, keyB64)` / `decrypt(payload, keyB64)` con Web Crypto (AES-GCM, IV aleatorio de 12 bytes, formato `{ v:1, iv, d }` en base64), más `importKey(keyB64)` que **valida que la clave decodifique a exactamente 32 bytes** y lanza un error tipado si no. Sin red, probables por unidad.
- Crear `supabase/functions/_shared/crypto_test.ts` — tests Deno (ida y vuelta, IV distinto cada vez, formato del sobre, fallo con clave equivocada, `importKey` rechaza ≠32 bytes). Corren en el paso Edge Functions de `verify.sh` (`deno test _shared/`).
- (Recomendado) Crear `supabase/functions/_shared/clave_flow_test.ts` — test Deno del helper de decisión con fake de Supabase: `CLAVE_INICIAL_KEY` ausente → invite omite `upsert`, clave responde `500` controlado. Queda dentro del único paso Deno del gate.
- Crear `supabase/functions/qhub-clave/index.ts` — Edge Function de lectura+descifrado (patrón de `qhub-invite`/`qhub-recover`: CORS idénticos, `json(status, body)` con `Cache-Control: no-store`, cliente `asUser` con el `Authorization` del invitado para `auth.getUser()`, cliente `admin` con `service_role` para ejecutar la SQL `clave_inicial_cifrada`). Responde según el **contrato HTTP exacto** de arriba: `200 { clave: string }`, `200 { clave: null }`, `400`, `401`, `500`.
- Crear migración `supabase/migrations/20261025000002_clave_inicial_cifrada.sql`:
  - La columna pasa a contener texto cifrado. Como la columna ya es `text` y no hay datos productivos sensibles que migrar en el gate (la base de pruebas se arma en la transacción del test), se **mantiene el nombre `clave`** pero su contenido es el sobre cifrado (`{ v:1, iv, d }` en base64); se documenta con `comment on column public.claves_iniciales.clave is '...sobre cifrado AES-GCM, nunca texto plano...';`.
  - **Eliminar la función vieja explícitamente** (no basta con crear una con otro nombre): la antigua `public.ver_clave_inicial(text)` es `security definer` y, si quedara, devolvería el blob cifrado a quien la ejecute. La migración incluye:
    ```sql
    revoke all on function public.ver_clave_inicial(text) from public, anon, authenticated;
    drop function if exists public.ver_clave_inicial(text);
    ```
  - **Crear `public.clave_inicial_cifrada(p_token)`** (misma condición de autorización por correo invitado + invitación pendiente/vigente que la vieja) que devuelve el **texto cifrado** (o `null`). Blindar permisos:
    ```sql
    revoke all on function public.clave_inicial_cifrada(text) from public, anon, authenticated;
    grant execute on function public.clave_inicial_cifrada(text) to service_role;
    ```
    Nadie más que `service_role` (la Edge Function `qhub-clave`) puede ejecutarla; el cliente ya **no** lee la clave por RPC directo. No se otorga `execute ... to authenticated` (a diferencia de la función vieja), cerrando la superficie por la que un autenticado podría haber leído el blob.
- Modificar `apps/web/src/features/staff/data/supabase-staff-repository.ts` — `initialPassword(token)` deja de llamar la RPC `ver_clave_inicial` y pasa a invocar la Edge Function `qhub-clave` **a través del helper existente `invokeFunction`** (`apps/web/src/shared/data/invoke-function.ts`), que el repo **ya importa y usa** (línea 3). Nada de `sb.functions.invoke` crudo: eso duplicaría el mapeo de error a `Failure` y rompería la consistencia de capa `data`. Sigue siendo **capa data**, firma intacta `Result<string | null>`. Implementación exacta:
  ```ts
  initialPassword(token: string): Promise<Result<string | null>> {
    return this.run(async () => {
      const r = await invokeFunction<{ clave: string | null }>(this.sb, 'qhub-clave', { token: token.trim() });
      if (!r.ok) throw r.failure;          // 401/400/red -> Failure saneado; lo convierte run() en err()
      return r.value?.clave ?? null;        // 200 { clave: null } -> null, como hoy con la RPC
    });
  }
  ```
  Con el contrato `200 { clave: null }` elegido, el caso «sin clave» llega como éxito (`ok(null)`), sin necesidad de un `FunctionErrorMap` personalizado ni de reinterpretar un `404`. El `defaultFunctionError` del helper se queda para 400/401/red (todos → `Failure`), que es lo correcto para errores reales.
- `apps/web/src/features/invitation/presentation/InvitationPage.tsx` — **sin cambios** (se deja tal cual). Consume `staff.initialPassword(token)` vía la query `['invitation-password', token]` y hace `const password = clave.data ?? null`, renderizando el bloque de contraseña solo cuando `password` es truthy. El contrato nuevo (`200 { clave: string | null }`) devuelve `ok(string)` cuando hay clave y `ok(null)` cuando no, así que `password` se comporta idéntico a hoy: con `null` el bloque simplemente no aparece (caso normal tras aceptar/vencer). **Comportamiento real verificado:** la página **no** renderiza `clave.error` en ningún punto (solo muestra `preview.error`). Por tanto, un fallo real de descifrado (`500` → `Failure` → `clave.data === undefined` → `password = null`) hoy **oculta el bloque en silencio, sin mensaje de error ni oferta de recuperar por correo**. Esto es aceptable y es el comportamiento que se conserva: el invitado siempre puede usar «Olvidé mi contraseña» desde el login, y mostrar un error técnico de descifrado no aportaría acción útil. **Decisión: no se añade render de `clave.isError`**; se documenta explícitamente que el 500 de descifrado degrada a «sin clave visible» (silencioso) en vez de afirmar —como decía la versión anterior de este diseño, incorrectamente— que la página muestra un error genérico y ofrece recuperación. Si más adelante se quisiera avisar del fallo, sería un cambio aditivo (un `Notice` genérico ante `clave.isError`), pero no es necesario para esta entrega.
- Config: documentar `CLAVE_INICIAL_KEY` en el `.env`/`.env.secret` de las funciones (solo **nombre**, el valor lo pone el usuario; nunca se commitea ni se imprime). Añadir a `supabase/functions/deno.json`/entorno de despliegue según el patrón de los otros secretos de funciones.

### Capas y porqué

- `supabase/functions/_shared/crypto.ts` — lógica pura compartida entre funciones (equivale a `domain`/util del lado Edge); por eso vive en `_shared` con su test, como `invite.ts`/`policy.ts`.
- `qhub-invite`/`qhub-clave` — adaptadores de servidor (equivalen a `data`): tocan Supabase y la red.
- `SupabaseStaffRepository.initialPassword` — **data** del web (invoca una función).
- `InvitationPage`/`useQuery` — **presentation**; no cambia.

### Diseño/tokens

Sin UI nueva: la clave se sigue mostrando en `InvitationPage` con los componentes actuales. Cualquier mensaje de error usa `friendlyError`/`Failure` (genérico, español).

### Errores (concretos, por operación)

- **Cifrar en `qhub-invite` falla** (clave mal formada/ausente): es **fatal** para guardar la clave — se registra en consola del servidor y **no se bloquea la invitación**; se omite el `upsert` (igual que hoy cuando `newPassword` es null: la persona recupera por «Olvidé mi contraseña»). No se filtra detalle.
- **`qhub-clave`: token ausente/no-string/vacío tras trim** → `400 { error: "Revisa los datos." }` → `invokeFunction` lo mapea a `badRequestFailure` → `run()` lo envuelve en `err(...)` → `clave.data === undefined` → `password = null` (bloque oculto). Recuperable.
- **`qhub-clave`: sin sesión** → `401 { error: "Inicia sesión" }` → `invokeFunction` lo mapea a `unauthorizedFailure`. Recuperable (volver a loguear).
- **`qhub-clave`: token/correo no coincide o invitación vencida/aceptada** → la función SQL devuelve `null` → `200 { clave: null }` → `Result.ok(null)` en el repo → `password = null`. La página trata `null` como «sin clave para mostrar», que es lo correcto tras aceptar. Recuperable y silencioso **por diseño** (no es un error).
- **`qhub-clave`: descifrado falla o `CLAVE_INICIAL_KEY` ausente/inválida** → **fatal para esa lectura** → `500 { error: "..." }` genérico; el detalle va a la **consola del servidor**, nunca al cliente. `invokeFunction` lo mapea a `serverFailure`. En `InvitationPage` eso deja `clave.data === undefined` → `password = null`, por lo que el bloque **se oculta en silencio** (comportamiento real verificado; ver la nota de `InvitationPage`). No se expone detalle técnico.
- **`invokeFunction` falla por red** (`FunctionsFetchError`) → `networkFailure`; `friendlyError` genérico. Recuperable al reintentar.

### Validación de entrada externa

- `qhub-clave` recibe `{ token }`: campo **`token`** (nombre fijo), **requerido**, string; se recorta (`trim`) y se rechaza con `400` si no es string no vacío. El repo pasa exactamente `{ token: token.trim() }` y mapea ese `400` a `badRequestFailure` vía `invokeFunction` (no a `null`): un token vacío es un error, no «sin clave». La verdad de autorización la pone la función SQL `security definer` (correo invitado + invitación vigente), no el cliente.
- `CLAVE_INICIAL_KEY`: clave simétrica **base64 que decodifica a exactamente 32 bytes (AES-256)**. Validación de arranque explícita en ambas funciones:
  - En **`qhub-clave`**: si `CLAVE_INICIAL_KEY` falta o no decodifica a 32 bytes, se registra en consola del servidor y la función responde `500` controlado (el cliente ve `serverFailure` genérico; el bloque de clave se oculta). Nunca se intenta descifrar con una clave inválida.
  - En **`qhub-invite`**: si falta/invalida, se registra en consola y se **omite el `upsert` de la clave** (igual que hoy cuando `createUser` falla y `newPassword` queda `null`): la invitación se envía igual y la persona entra con «Olvidé mi contraseña». Nunca se guarda texto plano como fallback.
  - `importKey(keyB64)` (en `_shared/crypto.ts`) hace esa validación de longitud una sola vez y lanza un error tipado si no son 32 bytes; las funciones lo capturan para el fallo controlado anterior. Este camino de «clave ausente/invalida» es el que cubre el test Deno recomendado con fake de Supabase.

### Invariantes y dueños

- «La clave nunca está en claro en reposo»: lo garantiza la **Edge Function** (único lugar que cifra/descifra) + la **migración** (la columna solo guarda el sobre cifrado). La base nunca tiene la clave de cifrado.
- «Solo el correo invitado la lee, y solo mientras la invitación está vigente»: lo garantiza la **función SQL `security definer`** (misma condición que hoy), ahora devolviendo cifrado; la Edge Function solo descifra lo que esa función autorizó.
- «Se muestra una sola vez»: el **trigger de borrado al aceptar** sigue igual.

### Tests (qué cambia) y mantener el gate verde

- Nuevo `supabase/functions/_shared/crypto_test.ts` (Deno): ida y vuelta, IV distinto en cada cifrado, formato del sobre, fallo con clave equivocada, y **`importKey` rechaza una clave que no decodifica a 32 bytes**. Corre en `deno test _shared/` del gate (único paso Deno que el gate ejecuta — ver «Alcance real de la cobertura»).
- **Recomendado (para que el gate cubra el caso «clave ausente»):** un test Deno colocado en `_shared/` (p. ej. `_shared/clave_flow_test.ts`) que ejercite la lógica de decisión de `qhub-invite`/`qhub-clave` — extraída a un helper puro en `_shared/` que reciba un fake de cliente Supabase y la env var — verificando que con `CLAVE_INICIAL_KEY` ausente se omite el `upsert` (invite) y se responde `500` controlado (clave). Mantener la lógica orquestadora en `_shared/` es lo que permite que el gate la alcance; los `index.ts` quedan como cascarón delgado que llama al helper.
- Los tests Deno existentes de `invite` siguen pasando (no cambia `parseInvite`/`generatePassword`).
- **RLS (`supabase/tests/rls_test.sql`)**: ni `claves_iniciales` ni `ver_clave_inicial` aparecen en el test (verificado por búsqueda), así que el cambio de contenido de la columna y el `drop function` de `ver_clave_inicial` **no afectan** ese test. La política de la tabla sigue siendo «sin políticas + revoke all», que se mantiene. No hay que renombrar nada en el test.
- **Tests del web**: `FakeStaffRepository.initialPassword` ya existe y seguirá devolviendo de `initialPasswords[token]`; no cambia la firma, así que `invitations.test.tsx` sigue verde. El cambio real (invocar `qhub-clave`) es solo en el adaptador Supabase, que no se ejercita con fakes.
- El typecheck estricto cubre las firmas nuevas.

### Qué NO se toca / BLOQUEADO

- No hay cambios en la API Qhub: la clave inicial es un concepto de Supabase (`Qhub_App`), no de la API. **Nada BLOQUEADO.**
- No se toca el Supabase de la API (otro proyecto).

---

## Tarea 3 — Paridad del perfil móvil + selectores de país/ciudad (`apps/mobile`)

### Situación actual (verificada)

- `apps/mobile/src/features/profile/presentation/ProfileScreen.tsx` solo muestra `displayName`/`email` (de los metadatos de auth), un selector de tema y cerrar sesión. **No lee ni escribe `perfiles`.**
- El perfil persistente vive en la tabla `public.perfiles` con columnas `nombre, apellido, telefono, cargo, pais, ciudad, zona_horaria` (migración `20261018000002_perfil_completo.sql`), con `grant update (nombre, apellido, telefono, avatar_url, pais, ciudad, zona_horaria, cargo) to authenticated`.
- El web (`ProfilePage` → `PersonalTab`) edita exactamente esos campos usando `@qhub/core` (geografía) y sus componentes `LocationFields`/`PhoneField`.
- **Regla de cuenta gestionada (dueño: la base):** el trigger `trg_perfil_gestionado` (migración `20261023000002_equipo_gestionado.sql`) impide que un integrante **gestionado** (miembro activo, no admin, de una organización `empresa`) cambie `nombre`, `apellido`, `telefono` o `cargo` **si ya tienen valor** (sí puede completarlos si están vacíos). **`pais`, `ciudad`, `zona_horaria` NO están en esa lista: cualquiera puede editarlos.** El web refleja esto deshabilitando esos cuatro campos cuando `managed && saved.<campo>` ya tiene valor, y muestra el panel «Pedir un cambio al administrador».
- La app móvil es pública (personas/`cliente`), pero una misma persona **puede además** ser integrante gestionado de una organización. La paridad exige respetar la misma regla.

### Decisión

Llevar el perfil móvil a paridad de **datos personales** con el web: editar `nombre`, `apellido`, `telefono`, `cargo`, `pais`, `ciudad`, `zona_horaria`, con **selectores de país y ciudad** (y zona horaria derivada), reutilizando `@qhub/core` (geografía y validadores) y validando en dominio puro. Se respeta la cuenta gestionada deshabilitando los campos gestionados ya completos y mostrando un aviso (sin construir aquí el flujo de aprobación completo: en el móvil el equivalente es que el cambio lo rechaza la base; se informa a la persona que su administrador gestiona esos datos, igual que el web). El tema/cerrar sesión se conservan.

**Detección de cuenta gestionada en el móvil (sin nuevo grant):** la RLS de `miembros` permite `usuario_id = auth.uid()`, así que el móvil puede leer sus propias membresías y unir `organizaciones.tipo` para decidir `managed = existe miembro activo, rol <> 'admin', tipo = 'empresa'`. Replica `es_miembro_gestionado` desde el cliente sin tocar permisos del servidor (la función `es_miembro_gestionado` está `revoke`-ada de `authenticated`, por eso no se llama; se consulta la tabla directamente, que sí es legible por el dueño).

**Reutilización de dominio compartido:** la forma `Profile` y `validateProfile` viven hoy en `apps/web/src/features/staff/domain/profile.ts` (específico del web). Para no duplicar entre web y móvil, se **promueve a `@qhub/core`** el tipo `Profile`, `EMPTY_PROFILE`, `isProfileComplete` y `validateProfile` (ya dependen solo de `@qhub/core`: `isValidPhone`, `validatePersonName`). El web reexporta desde `@qhub/core` para no romper imports. La geografía (`COUNTRIES`, `citiesOf`, `countryByAny`, `timeZonesOf`, `timeZoneLabel`) ya está en `@qhub/core`.

### Archivos

**Paquete compartido:**
- Modificar `packages/core/src/index.ts` (+ crear `packages/core/src/profile.ts`) — mover ahí `Profile`, `EMPTY_PROFILE`, `isProfileComplete`, `validateProfile`. **Capa domain compartida** (TS puro).
- Crear/actualizar `packages/core/src/profile.test.ts` (o mover el existente `profile.test.ts` del web) para que corra en el paquete `@qhub/core` (`core · 8 tests` sube de cuenta; el gate corre `npm test` global).
- Modificar `apps/web/src/features/staff/domain/profile.ts` — reexportar desde `@qhub/core` (o actualizar los imports del web a `@qhub/core`). Mantener `EMPTY_PROFILE`/`validateProfile` disponibles donde el web los usa (`ProfilePage`, flows). Sin cambio de comportamiento.

**Móvil — feature `profile`:**
- Crear `apps/mobile/src/features/profile/domain/profile.ts` — **domain**. Reexporta `Profile`/`validateProfile` de `@qhub/core` y define las reglas propias del móvil si hiciera falta (p. ej. `managedFields` = `['firstName','lastName','phone','jobTitle']`). TS puro.
- Crear `apps/mobile/src/features/profile/data/supabase-profile-repository.ts` — **data**. `SupabaseProfileRepository` con:
  - `get(): Promise<Result<Profile>>` — `select('nombre, apellido, telefono, cargo, pais, ciudad, zona_horaria').eq('id', uid).single()` (mismo mapeo que el web).
  - `update(p: Profile): Promise<Result<Profile>>` — `update({...}).eq('id', uid).select(...).single()`; mapea el error del trigger (`42501`) a un `Failure` genérico vía `failureFromSupabase`.
  - `managementStatus(): Promise<Result<boolean>>` — lee `miembros(usuario_id=uid, activo=true, rol<>admin)` join `organizaciones(tipo='empresa')`.
  - Define su puerto `ProfileRepository` en `apps/mobile/src/features/profile/domain/profile.ts`.
- Crear `apps/mobile/src/features/profile/presentation/useProfileForm.ts` — **presentation**. Hook con TanStack Query (`['profile']`) + estado de formulario (como `PersonalTab` del web): carga, normaliza país con `countryByAny`, detecta `managed`, valida con `validateProfile`, guarda, toasts.
- Modificar `apps/mobile/src/features/profile/presentation/ProfileScreen.tsx` — añadir sección «Datos personales» (identidad, contacto, ubicación) con los selectores; conservar tema y cerrar sesión. Usa el kit móvil + los nuevos selectores.
- Modificar `apps/mobile/src/app/container.tsx` — añadir `profiles: ProfileRepository` al `Container`, construir `new SupabaseProfileRepository(sb)`.

**Móvil — primitivas de UI (faltan Select/Combobox):**
- El kit (`apps/mobile/src/shared/ui/kit.tsx`) tiene `TextField`, `Segmented`, `ListRow`, `ConfirmModal`, `Button`, pero **no** un selector tipo lista. Crear `apps/mobile/src/shared/ui/SelectField.tsx` (o añadir `SelectField` al kit) — **shared/ui**. Un campo que abre un `Modal` con lista buscable (`ListRow`/`Pressable`) para elegir de una lista de `{ value, label }`; estilos solo con tokens NativeWind (`bg-field`, `border-border-strong`, `t-*`, `h-control-*`). Reutiliza `TextField` como disparador visual para coherencia. Accesible (`accessibilityRole`, `accessibilityState.selected`).
  - Decisión: **un solo `SelectField` con búsqueda opcional** cubre país (con búsqueda), ciudad (con búsqueda) y zona horaria (lista corta). No se crean tres componentes.
- Crear `apps/mobile/src/features/profile/presentation/LocationFields.tsx` — **presentation** del móvil. Equivalente a la del web usando `SelectField`: País → Ciudad → Zona horaria con `citiesOf`/`timeZonesOf`/`countryByAny` de `@qhub/core`. (No se comparte el `LocationFields` del web porque usa componentes web; la **lógica/datos** sí se comparten vía `@qhub/core`.)
- Para el teléfono con prefijo, reutilizar `@qhub/core` (`isValidPhone`, `countryByAny().dial`): crear `apps/mobile/src/features/profile/presentation/PhoneField.tsx` que combine `SelectField` (prefijo por país) + `TextField`, o —si se decide simplicidad— un `TextField` con validación `isValidPhone`. **Decisión: `PhoneField` con prefijo seleccionable** para paridad real con el web.

**Tests:**
- Crear `apps/mobile/src/features/profile/domain/profile.test.ts` (si no basta el de `@qhub/core`) — valida reglas móviles (`managedFields`, validación).
- Crear `apps/mobile/src/features/profile/presentation/ProfileScreen.test.tsx` o `useProfileForm.test.ts` — con un `FakeProfileRepository` nuevo en `apps/mobile/src/testing/fakes.ts`: carga perfil, edita ciudad (permitido), intenta editar nombre gestionado (deshabilitado), guarda. Sigue el patrón de `app-flow.test.tsx`.
- Modificar `apps/mobile/src/testing/fakes.ts` y `makeContainer` — añadir `FakeProfileRepository` y cablear `profiles`.

### Capas y porqué

- `Profile`/`validateProfile` en `@qhub/core` → **domain compartido** (TS puro, sin React).
- `supabase-profile-repository.ts` → **data** (único con Supabase).
- `useProfileForm.ts`, `ProfileScreen.tsx`, `LocationFields.tsx`, `PhoneField.tsx` → **presentation**.
- `SelectField.tsx` → **shared/ui** (kit visual reutilizable, solo tokens).
- El puerto `ProfileRepository` → **domain** del feature móvil.

### Diseño/tokens

- NativeWind + tokens: `bg-field`, `border-border-strong`/`border-focus`/`border-support-error`, `h-control-md/lg`, `t-label`/`t-body`/`t-caption`, `text-text-primary`/`text-text-secondary`, `bg-interactive`/`bg-layer-02`. Nada de hex/medidas sueltas.
- Español, tuteo, sentence case. Botón primario único por vista («Guardar»). Aviso de cuenta gestionada con `Notice kind="info"`.
- **Posible token faltante:** si el `Modal` del `SelectField` necesita un color de *scrim*/overlay y no existe un token (p. ej. `bg-overlay`), **se anota como token faltante** y se reutiliza el que ya use `ConfirmModal` (verificar en `kit.tsx`/tokens); no se inventa un valor.

### Errores (concretos)

- `profiles.get()` falla (red/RLS): TanStack Query `isError` → la pantalla muestra `Notice kind="error"` con texto genérico (`friendlyError`). Recuperable (reintentar al reenfocar). **Logging:** consola.
- `profiles.update()` rechazado por el trigger de cuenta gestionada (`42501`): `failureFromSupabase` lo convierte en `Failure` genérico; además la UI **previene** el caso deshabilitando los campos gestionados ya completos, así que en la práctica no se envía. Si llegara (carrera), toast de error genérico. No se muestra el mensaje técnico de Postgres.
- Validación local (`validateProfile`) falla: se muestran errores por campo (`TextField error`), no se llama a la base.
- Sin sesión al abrir el perfil: no debería ocurrir (pantalla tras la puerta de acceso); si `uid` es null, `get()` devuelve `unauthorizedFailure` y la pantalla cae al estado de error genérico.

### Validación de entrada externa (reglas por campo)

- `firstName`/`lastName`: **requeridos** para guardar (si no gestionados o aún vacíos); `validatePersonName` (`@qhub/core`). Límite 60.
- `phone`: **opcional**; si viene, `isValidPhone` (7–20 dígitos, `+`/espacios). Límite 20.
- `jobTitle` (cargo): **opcional**; 2–80 caracteres.
- `country`: código ISO de la lista `COUNTRIES`; se elige, no se escribe. **Opcional**, pero si hay `city` sin `country` → error «Elige primero el país» (igual que el web).
- `city`: de `citiesOf(country)` (o conservada si era dato antiguo). **Opcional**.
- `timeZone`: de `timeZonesOf(country)`; se autocompleta al elegir país.
- Comportamiento ante fallo: no se persiste; se marca el campo.

### Invariantes y dueños

- «Un integrante gestionado no cambia nombre/apellido/teléfono/cargo ya completos»: **dueño: la base** (`trg_perfil_gestionado`). La presentación móvil **refleja** la regla (deshabilita) pero la **fuente de verdad** y el enforcement real es el trigger; así el móvil no puede saltárselo aunque tuviera un bug.
- «País/ciudad/zona los edita cualquiera»: también lo decide la base (no están en el trigger ni restringidos por grant). El móvil lo permite.
- Paridad exacta con el web: los mismos 4 campos gestionados, la misma lista de geografía (de `@qhub/core`), la misma validación (`validateProfile` compartida).

### Testabilidad

- **Unit (domain):** `validateProfile`, detección de `managed`, `managedFields` — puro, fácil.
- **Unit (presentation):** `useProfileForm`/`ProfileScreen` con `FakeProfileRepository` — carga, edición permitida vs. deshabilitada, guardado, errores. Patrón de `app-flow.test.tsx` y `notifications.test.ts`.
- **Integración (data):** `SupabaseProfileRepository` no se prueba contra Supabase real en el gate (los tests móviles usan fakes); el mapeo de columnas es idéntico al del web ya probado indirectamente. La RLS/trigger de cuenta gestionada ya se cubre en `supabase/tests/rls_test.sql` en la **prueba 27 (equipo gestionado)**, que verifica que un integrante gestionado no cambia por su cuenta `nombre/teléfono/cargo` ya completos (`insufficient_privilege`) y que **sí** puede cambiar `ciudad` y completar un campo vacío. (La prueba 28 es sobre Auth —contraseña/correo—, no sobre `perfiles`; no es la relevante aquí.) El móvil no añade reglas de base nuevas, así que esa cobertura existente es suficiente.

### Qué NO se toca / BLOQUEADO

- La API Qhub no interviene (el perfil es de Supabase `Qhub_App`). **Nada BLOQUEADO.**
- No se añaden columnas ni se cambia la RLS: las columnas y los grants ya existen; el trigger ya enforcea la regla gestionada. Si el gate RLS revelara que falta cubrir país/ciudad para móvil, se añadiría una aserción; (verificado: las columnas y grants ya están).

---

## Resumen de archivos

**Crear:**
- `apps/web/src/features/notifications/domain/qhub-notifications.ts`
- `apps/web/src/features/notifications/presentation/useQhubNotifications.ts` (+ `.test.ts`)
- `apps/web/src/features/notifications/presentation/QhubNotices.tsx`
- `apps/web/src/features/notifications/data/supabase-notifications-realtime.ts`
- `apps/web/src/features/notifications/presentation/useNotices.test.tsx` (ampliar/crear)
- `supabase/migrations/20261025000001_realtime_avisos_staff.sql`
- `supabase/functions/_shared/crypto.ts` (+ `crypto_test.ts`)
- `supabase/functions/_shared/clave_flow_test.ts` (recomendado)
- `supabase/functions/qhub-clave/index.ts`
- `supabase/migrations/20261025000002_clave_inicial_cifrada.sql`
- `packages/core/src/profile.ts` (+ `profile.test.ts`)
- `apps/mobile/src/features/profile/domain/profile.ts`
- `apps/mobile/src/features/profile/data/supabase-profile-repository.ts`
- `apps/mobile/src/features/profile/presentation/useProfileForm.ts` (+ test)
- `apps/mobile/src/features/profile/presentation/LocationFields.tsx`
- `apps/mobile/src/features/profile/presentation/PhoneField.tsx`
- `apps/mobile/src/shared/ui/SelectField.tsx`
- `apps/mobile/src/features/profile/presentation/ProfileScreen.test.tsx`

**Modificar:**
- `apps/web/src/features/notifications/domain/notifications.ts` (puerto `NotificationsRealtime`)
- `apps/web/src/features/notifications/presentation/useNotices.ts` · `NoticePopups.tsx`
- `apps/web/src/features/shell/presentation/AppShell.tsx`
- `apps/web/src/app/container.tsx`
- `apps/web/src/testing/fakes.ts` · `harness.tsx`
- `supabase/functions/qhub-invite/index.ts`
- `apps/web/src/features/staff/data/supabase-staff-repository.ts` (`initialPassword` → `qhub-clave`)
- `apps/web/src/features/staff/domain/profile.ts` (reexporta de `@qhub/core`)
- `packages/core/src/index.ts`
- `apps/mobile/src/app/container.tsx`
- `apps/mobile/src/features/profile/presentation/ProfileScreen.tsx`
- `apps/mobile/src/testing/fakes.ts`
- `apps/mobile/src/shared/ui/kit.tsx` (si `SelectField` se añade al kit)

## Supuestos no verificables desde el código

- **Supabase Realtime** (`postgres_changes`) está disponible en el proyecto `Qhub_App` y la tabla puede añadirse a la publicación `supabase_realtime`. Si no, el **fallback a polling** mantiene todo funcionando (diseñado para ello). No se puede verificar en el gate local porque `rls_test.sql` corre en una transacción que se deshace y no levanta el servicio Realtime.
- **`CLAVE_INICIAL_KEY`** la provee el usuario como secret de las Edge Functions (como `SUPABASE_SERVICE_ROLE_KEY`). El gate local de Edge Functions corre **solo** `deno test _shared/` (helpers puros con clave de prueba generada en el test, más el helper de decisión con fake de Supabase si se añade el test recomendado). El flujo **end-to-end** de las funciones desplegadas con su secret real no lo ejercita el gate; se prueba en despliegue. Por eso la validación de arranque de la clave (32 bytes, fallo controlado) se especifica explícitamente en el diseño en vez de delegarse al gate.
- El invitado abre `qhub-clave` con un JWT de Supabase válido (igual que hoy llamaba la RPC autenticada); la autorización fina sigue en la función SQL `security definer`.

## Elementos BLOQUEADOS

Ninguno. Las tres tareas se resuelven en los clientes y en Supabase (parte de `Qhub_App`) sin modificar la API Qhub. Los 5 pendientes de despliegue del usuario (publicar la API en Render + secret `QHUB_API_BASE_URL`, SMTP propio, rotar tokens, probar el APK, activar `ENFORCE_TURN_OWNERSHIP`) quedan **fuera de alcance** y no se bloquean con estos cambios.

---

## Respuesta a la revisión de diseño (`design-review.json` / `design-review.md`)

Veredicto previo: **CHANGES_REQUESTED** (1 HIGH, 4 MEDIUM, 4 NIT). Cada finding se resuelve a continuación; todos **atendidos**, ninguno backlogeado ni ignorado, y todos coherentes con los requisitos originales (preservar UX, no tocar la API, no regresar tests, mantener el gate verde).

1. **[HIGH] Contrato de `qhub-clave` (404→null y UX de error de descifrado) falso contra el código.** *Atendido.* Se fija el contrato en **`200 { clave: string | null }`** (no `404`), de modo que el caso «sin clave» llega al repo como `ok(null)` sin reinterpretar un `Failure`; se reserva `404` y no se usa. Se corrige la afirmación falsa sobre la UX: se verificó que `InvitationPage` **nunca** renderiza `clave.error` (solo `preview.error`), por lo que un `500` de descifrado **oculta el bloque en silencio**. Se decide explícitamente **no** añadir render de `clave.isError` (el invitado recupera por «Olvidé mi contraseña»; no aporta mostrar un error técnico) y se documenta el degradado silencioso en vez de prometer un mensaje+recuperación inexistentes. Ver «Flujo nuevo», «Errores» y la entrada de `InvitationPage`.

2. **[MEDIUM] La migración no dropea `ver_clave_inicial`.** *Atendido.* La migración ahora incluye `revoke all on function public.ver_clave_inicial(text) from public, anon, authenticated;` + `drop function if exists public.ver_clave_inicial(text);`, y crea `clave_inicial_cifrada(text)` con `revoke all ...` + `grant execute ... to service_role` (sin `authenticated`). No queda función `security definer` huérfana ni grant residual. Ver la entrada de la migración `20261025000002`.

3. **[MEDIUM] Se usaba `sb.functions.invoke` crudo en vez del helper.** *Atendido.* `initialPassword` ahora usa `invokeFunction<{ clave: string | null }>(this.sb, 'qhub-clave', { token })` (el helper que el repo ya importa y usa), con snippet exacto. Sin mapeo de error duplicado; la UI nunca ve el error crudo.

4. **[MEDIUM] Payload/entrada de `qhub-clave` ambiguos.** *Atendido.* Se documenta el contrato HTTP exacto (campo de entrada `token`, saneo con `trim` → `400` si vacío; salidas `200 {clave:string}`, `200 {clave:null}`, `400`, `401`, `500`) y su mapeo en el repo (400/401/red → `Failure`; `clave:null` → `null`).

5. **[MEDIUM] «Ya probado» sobredimensiona la cobertura del gate.** *Atendido.* Se reformula: el gate solo corre `deno test _shared/` (helpers puros); el flujo end-to-end y la env var real **no** se ejercitan. Se especifica la validación de arranque de `CLAVE_INICIAL_KEY` (base64 → 32 bytes; fallo controlado: `qhub-clave`→500, `qhub-invite` omite `upsert`), `importKey` valida la longitud, y se añade un test Deno recomendado (`_shared/clave_flow_test.ts`) con fake de Supabase para cubrir «clave ausente» dentro del único paso Deno del gate.

6. **[NIT] Referencia a «prueba 28/perfiles».** *Atendido.* Corregido a **prueba 27 (equipo gestionado)**; se aclara que la 28 es sobre Auth.

7. **[NIT] Nota de carpetas planas como excepción defensiva.** *Atendido.* Reescrita como regla afirmativa: `features/<feature>/{domain,data,presentation}/`, cada archivo en su subcarpeta de capa (verificado en el worktree). Sin framing de «no carpetas planas».

8. **[NIT] Fuente del JWT de `qhub-clave` no fijada.** *Atendido.* Se añade que `sb.functions.invoke` adjunta el JWT desde la sesión Supabase activa y que `qhub-clave` lo lee de `Authorization` como `qhub-invite`; no hay que pasar el token a mano.

9. **[NIT] Query key de `useNotices` escrita como de dos elementos.** *Atendido.* Se anota que la key real es `['notices', orgId, limit]` (tres elementos) y que la invalidación es **por prefijo** (`exact:false`, el default) sobre `['notices', orgId]`, cubriendo cualquier `limit`, igual que la función `refresh()` existente.
