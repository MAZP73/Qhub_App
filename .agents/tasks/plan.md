# Plan de implementación — Notificaciones en tiempo real (web), cifrado de la clave inicial y paridad del perfil móvil

Este plan sigue el diseño aprobado (`.agents/tasks/design.md`, revisión `APPROVED` en `.agents/tasks/design-review.md`). Todo el trabajo ocurre **dentro del worktree** `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil` (tratarlo como raíz del proyecto; las rutas relativas caen en el workspace padre, úsense rutas absolutas). **La API Qhub `/home/miguelzambrano/projects/Qhub` es de solo lectura: no se toca.**

Convenciones obligatorias (de `CLAUDE.md`, `docs/estructura.md`, `docs/arquitectura.md`):
- Clean Architecture por feature: `features/<feature>/{domain,data,presentation}`. `domain/` es TS puro (sin React, sin `fetch`, sin Supabase). Supabase/WebSocket/`fetch` solo en `data/`. `presentation/` usa React/TanStack Query y nunca ve errores crudos. No hay `architecture.test.ts` en este worktree: la disciplina de capas se mantiene por la ubicación de cada archivo.
- Errores tipados: `Result<T>`/`Failure` de `@qhub/core`; la UI usa `friendlyError(e)` o `failure.message` (ya saneado), nunca detalle técnico; los detalles van a consola.
- Design system: solo utilidades de Tailwind sobre tokens (`@qhub/design`): web Tailwind v4, móvil NativeWind. Nada de hex/tamaños/radios sueltos. Español, tuteo, sentence case, botones 1–3 palabras, 24 h.
- No duplicar: lo que comparten web y móvil vive en `packages/*` (geografía/perfil en `@qhub/core`, API en `@qhub/api-client`).
- Localhost intacto: no cambiar `QHUB_API_URL`/`QHUB_WS_URL` del `.env` raíz ni el `docker compose`.

**Aceptación final (puerta de verificación):** `bash tool/verify.sh` ejecutado desde dentro del worktree debe terminar en **exit 0**. Ese gate instala, genera el design system, hace typecheck estricto, corre todos los tests (`core · api-client · design · web · móvil`), build de la web, export de Expo (Android), `deno test _shared/` (único paso Deno), contrato HTTP/WS contra la API real y RLS (si hay `.env.secret`). Las rutas de *verify* de cada ítem son pasos intermedios; la aceptación es el gate completo en verde.

Correspondencia con PLAN.md (pendientes a mover a «hecho» luego):
- Ítems 1–8 → PLAN.md «Revisión del móvil (acordado para el final): perfil y los mismos selectores» (Tarea 3) y el pendiente implícito de tiempo real en la web / cifrar la clave inicial. Concretamente: Tarea 1 (ítems 9–16) cubre notificaciones en tiempo real en la web; Tarea 2 (ítems 17–23) cubre «cifrar la clave inicial de la invitación»; Tarea 3 (ítems 1–8 + 24–30) cubre «Revisión del móvil: perfil y los mismos selectores».

---

## Grupo A — Dominio compartido del perfil (prerequisito de la Tarea 3)

- [ ] 1. Mover el modelo de perfil a `@qhub/core` para que web y móvil lo compartan sin duplicar.
      Crear `packages/core/src/profile.ts` con `Profile`, `EMPTY_PROFILE`, `isProfileComplete`, `validateProfile` (copiados tal cual de `apps/web/src/features/staff/domain/profile.ts`; ya dependen solo de `@qhub/core`: `isValidPhone`, `validatePersonName`, importados desde los módulos hermanos, no desde el índice, para evitar ciclos). Capa: **domain compartido** (TS puro).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/packages/core/src/profile.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 2. Exportar el perfil desde el índice de `@qhub/core`.
      Añadir `export * from './profile';` en `packages/core/src/index.ts`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/packages/core/src/index.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 3. Trasladar los tests del perfil a `@qhub/core` (o crearlos) para que corran en el paquete compartido.
      Crear `packages/core/src/profile.test.ts` cubriendo `validateProfile` (nombre/apellido requeridos, teléfono inválido, cargo fuera de rango, ciudad sin país) y `isProfileComplete`. Seguir el patrón de otros `*.test.ts` de `packages/core/src`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/packages/core/src/profile.test.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm test -w @qhub/core'` — nuevos tests pasan.

- [ ] 4. Reexportar `Profile`/`validateProfile`/`EMPTY_PROFILE`/`isProfileComplete` desde el dominio web, sin cambiar comportamiento ni romper imports existentes.
      Reemplazar el cuerpo de `apps/web/src/features/staff/domain/profile.ts` por `export { type Profile, EMPTY_PROFILE, isProfileComplete, validateProfile } from '@qhub/core';`. Verificar que el barrel `apps/web/src/features/staff/domain/index.ts` sigue reexportando estos nombres (si los reexporta por archivo, no cambia nada). No tocar `ProfilePage.tsx` ni los flujos que importan de `@/features/staff/domain`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/staff/domain/profile.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — todo verde (incluye `invitations.test.tsx`, flujos de perfil).

---

## Grupo B — Tarea 1: Notificaciones en tiempo real en la web (`apps/web`)

### 1A — Avisos personales de Qhub (`WS /ws/notificaciones`)

- [ ] 5. Crear el modelo de presentación de los avisos personales de Qhub en la capa domain.
      Crear `apps/web/src/features/notifications/domain/qhub-notifications.ts` (**domain**, TS puro, sin React): reexporta/estrecha `AppNotification` de `@qhub/api-client` como modelo de presentación y define `mapKindToText(kind)` puro (etiqueta en español por `tipo_aviso`) si hace falta un texto para el toast.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/domain/qhub-notifications.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 6. Crear el hook y el componente que consumen el WS personal y emiten toasts, montados en el shell.
      Crear `apps/web/src/features/notifications/presentation/useQhubNotifications.ts` (**presentation**): usa `useContainer()` (`notifications`, `realtime`), `useSession()` (`connection`), TanStack Query (`notifications.list(...)` para el histórico) y `useToast`; abre `realtime.subscribeNotifications({ onNotification, onError?, onStatus? })` en un `useEffect` atado a `session.connection.status === 'connected'` (no abre socket sin conexión, evitando el `unauthorizedFailure` que lanza `url()` sin token/actor); en cada aviso hace `queryClient.invalidateQueries`/`setQueryData` sobre la lista y `toast.show(...)`; trata `onError` (cierre 4401) como no recuperable para la suscripción (deja de escuchar, sin toast técnico, log a consola). Crear `apps/web/src/features/notifications/presentation/QhubNotices.tsx` (**presentation**, sin UI propia, como `NoticePopups`): monta el hook y devuelve `null`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/useQhubNotifications.ts`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/QhubNotices.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 7. Montar `<QhubNotices />` en el shell autenticado, **fuera** del gate `notifications.view` (su activación real la controla el `useEffect` atado a `connection.status`, no un permiso de avisos de equipo). Decisión del diseño (resuelve el NIT 3 de la revisión): se monta junto al shell siempre que haya sesión/organización.
      Modificar `apps/web/src/features/shell/presentation/AppShell.tsx`: renderizar `<QhubNotices />` en el `<main>`/shell autenticado (p. ej. junto a `<ReconnectBanner />`), no dentro del bloque `{can(role, 'notifications.view') && ...}`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/shell/presentation/AppShell.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — `workspace.test.tsx` sigue verde (el `FakeRealtime.subscribeNotifications` es no-op; el render no rompe).

- [ ] 8. Añadir el test unitario del hook personal con fakes.
      Crear `apps/web/src/features/notifications/presentation/useQhubNotifications.test.tsx` usando `FakeRealtime` (ya expone `subscribeNotifications`) y `FakeNotifications`; verificar que no abre socket sin conexión, que al conectar suscribe, y que un aviso dispara `toast.show`. Si el fake `FakeRealtime.subscribeNotifications` necesita poder emitir en el test, ampliarlo en `apps/web/src/testing/fakes.ts` para guardar el handler y exponer un `emitNotification(n)` (análogo al patrón de `FakeNotificationsRealtime` del ítem 12), sin romper su firma actual.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/useQhubNotifications.test.tsx`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/testing/fakes.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm test -w @qhub/web'` — nuevo test pasa, resto verde.

### 1B — Avisos del equipo (`notificaciones_staff`) en tiempo real con Supabase Realtime

- [ ] 9. Añadir el puerto `NotificationsRealtime` a la capa domain de notificaciones.
      Modificar `apps/web/src/features/notifications/domain/notifications.ts`: añadir `export interface NotificationsRealtime { subscribe(orgId: string, handlers: { onChange: () => void; onStatus: (s: 'connected' | 'error' | 'closed') => void }): () => void; }` (TS puro, sin Supabase).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/domain/notifications.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 10. Crear el adaptador de datos de Supabase Realtime (`postgres_changes`).
      Crear `apps/web/src/features/notifications/data/supabase-notifications-realtime.ts` (**data**): clase `SupabaseNotificationsRealtime` que recibe el `SupabaseClient` y expone `subscribe(orgId, { onChange, onStatus })` con `sb.channel('staff-notices:'+orgId).on('postgres_changes', { event: '*', schema: 'public', table: 'notificaciones_staff', filter: 'organizacion_id=eq.'+orgId }, () => onChange()).subscribe((status) => onStatus(mapStatus(status)))`; devuelve una función de baja que llama `sb.removeChannel(channel)`. No lanza: traduce fallos a `onStatus('error')`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/data/supabase-notifications-realtime.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 11. Cablear `staffNoticesRealtime` en el container de la web.
      Modificar `apps/web/src/app/container.tsx`: importar el puerto `NotificationsRealtime` y el adaptador, añadir `staffNoticesRealtime: NotificationsRealtime` a `Container` y construirlo con `new SupabaseNotificationsRealtime(sb)` en `buildContainer`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/app/container.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` (fallará hasta cablear el harness en el ítem 12; ejecutar juntos 11–12).

- [ ] 12. Añadir el fake de Realtime y cablearlo en el harness de pruebas.
      Modificar `apps/web/src/testing/fakes.ts`: añadir `FakeNotificationsRealtime` que implemente `NotificationsRealtime`, guarde los handlers, llame `onStatus('connected')` al suscribir y exponga `emit()` para las pruebas. Modificar `apps/web/src/testing/harness.tsx`: construir `staffNoticesRealtime` en `makeContainer`, añadirlo al objeto devuelto y al tipo `TestContainer['fakes']` (p. ej. `staffNoticesRealtime`).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/testing/fakes.ts`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/testing/harness.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — compila y toda la suite web sigue verde.

- [ ] 13. Integrar la suscripción Realtime en `useNotices` con fallback al polling.
      Modificar `apps/web/src/features/notifications/presentation/useNotices.ts`: mantener un estado local `rtStatus` (`'connected' | 'off'`) alimentado por `onStatus` del `subscribe`; abrir la suscripción en un `useEffect` atado a `orgId` (baja al desmontar/cambiar org); en `onChange` invalidar **por prefijo** `qc.invalidateQueries({ queryKey: ['notices', orgId] })` y `['notices-count', orgId]` (cubre cualquier `limit`, igual que `refresh()`); el `refetchInterval` de ambas queries pasa a `rtStatus === 'connected' ? false : useRefreshInterval()` (resuelve el NIT 2: la preferencia manda cuando Realtime no está; al conectar se apaga el polling; ante `error`/`closed` vuelve a `useRefreshInterval()`).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/useNotices.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — verde.

- [ ] 14. Integrar la misma suscripción en `NoticePopups` para refrescar al instante.
      Modificar `apps/web/src/features/notifications/presentation/NoticePopups.tsx`: en un `useEffect` atado a `orgId`, suscribirse vía `staffNoticesRealtime` e invalidar `['notice-popups', orgId]` en `onChange`; mantener el polling de 10 s como fallback y la lógica de `seen`/toast intacta.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/NoticePopups.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — verde.

- [ ] 15. Crear/ampliar el test de `useNotices` para verificar la invalidación por evento.
      Crear `apps/web/src/features/notifications/presentation/useNotices.test.tsx`: con `FakeNotificationsRealtime`, verificar que un `emit()` refresca/invalida la lista y el conteo; verificar el cambio de `refetchInterval` al estar `connected`. `workspace.test.tsx` debe seguir verde (el fake por defecto no emite).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/notifications/presentation/useNotices.test.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm test -w @qhub/web'` — nuevo test pasa, resto verde.

- [ ] 16. Crear la migración que añade `notificaciones_staff` a la publicación `supabase_realtime` (idempotente).
      Crear `supabase/migrations/20261025000001_realtime_avisos_staff.sql`: en un bloque `do $$ ... $$` guardado, `alter publication supabase_realtime add table public.notificaciones_staff;` solo si la tabla no está ya en la publicación (consultar `pg_publication_tables`). No cambia RLS. Documentar en comentario que Realtime respeta la política `SELECT` existente.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/migrations/20261025000001_realtime_avisos_staff.sql`
      Verify: la migración no rompe el gate; aceptación en `bash tool/verify.sh` (RLS corre en transacción que se deshace y no referencia esta tabla para Realtime). Revisar sintaxis SQL del bloque idempotente.

---

## Grupo C — Tarea 2: Cifrar la clave inicial de la invitación

- [ ] 17. Crear los helpers puros de cifrado AES-GCM compartidos por las Edge Functions.
      Crear `supabase/functions/_shared/crypto.ts` (equivale a util/`domain` del lado Edge): `importKey(keyB64)` que decodifica base64 y **valida exactamente 32 bytes** (AES-256), lanzando un error tipado si no; `encrypt(plain, keyB64)` que genera IV aleatorio de 12 bytes y devuelve el sobre `{ v:1, iv, d }` en base64; `decrypt(payload, keyB64)` inverso. Web Crypto (como `device-credential-vault.ts`). Sin red.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/functions/_shared/crypto.ts`
      Verify: cubierto por el test del ítem 18 (`deno test _shared/`).

- [ ] 18. Crear los tests Deno del helper de cifrado.
      Crear `supabase/functions/_shared/crypto_test.ts`: ida y vuelta con clave de prueba generada en el test, IV distinto en cada cifrado, formato del sobre, fallo con clave equivocada, y `importKey` rechaza una clave que no decodifica a 32 bytes.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/functions/_shared/crypto_test.ts`
      Verify: `docker run --rm -v "$PWD/supabase/functions:/app" -w /app denoland/deno:latest deno test _shared/` — nuevos tests pasan (desde dentro del worktree).

- [ ] 19. (Recomendado) Extraer la lógica de decisión «clave ausente» a un helper puro en `_shared/` y probarla con un fake de Supabase, para que el gate cubra ese caso.
      Crear `supabase/functions/_shared/clave_flow_test.ts` (+ el helper que ejercite, colocado en `_shared/`): con `CLAVE_INICIAL_KEY` ausente, `qhub-invite` omite el `upsert` y `qhub-clave` responde `500` controlado. Mantener la lógica orquestadora en `_shared/` para que `deno test _shared/` la alcance; los `index.ts` quedan como cascarón delgado.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/functions/_shared/clave_flow_test.ts` (+ helper en `_shared/` si se extrae)
      Verify: `docker run --rm -v "$PWD/supabase/functions:/app" -w /app denoland/deno:latest deno test _shared/` — pasa.

- [ ] 20. Cifrar la clave inicial al escribirla en `qhub-invite`.
      Modificar `supabase/functions/qhub-invite/index.ts`: importar `encrypt`/`importKey` de `_shared/crypto.ts`; validar `CLAVE_INICIAL_KEY` al arranque del camino que escribe la clave; donde hoy hace `admin.from("claves_iniciales").upsert({ invitacion_id, clave: newPassword })`, cifrar `newPassword` y guardar el sobre cifrado; si `CLAVE_INICIAL_KEY` falta/invalida, registrar en consola y **omitir el `upsert`** (no guardar texto plano; la invitación se envía igual). No alterar el resto del flujo (correo, auditoría, contrato de respuesta).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/functions/qhub-invite/index.ts`
      Verify: `docker run --rm -v "$PWD/supabase/functions:/app" -w /app denoland/deno:latest deno test _shared/` — `invite_test.ts` y `clave_flow_test.ts` pasan.

- [ ] 21. Crear la Edge Function `qhub-clave` (lectura + descifrado autorizado).
      Crear `supabase/functions/qhub-clave/index.ts` siguiendo el patrón de `qhub-invite`/`qhub-recover`: CORS idénticos, `json(status, body)` con `Cache-Control: no-store`, cliente `asUser` con el `Authorization` del invitado (`auth.getUser()`), cliente `admin` (`service_role`) que ejecuta la SQL `clave_inicial_cifrada`. Contrato exacto: `POST`, body `{ token: string }` (requerido, no vacío tras `trim`); `200 { clave: string }` cuando hay clave; `200 { clave: null }` cuando la SQL devuelve `null` (aceptada/vencida/correo no coincide); `400 { error: "Revisa los datos." }` si token ausente/no-string/vacío; `401 { error: "Inicia sesión" }` sin JWT; `500 { error: "..." }` si falla el descifrado o `CLAVE_INICIAL_KEY` falta/invalida (detalle solo a consola).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/functions/qhub-clave/index.ts`
      Verify: typecheck de Deno al correr `deno test _shared/` (el `index.ts` importa de `_shared/`); aceptación end-to-end queda para despliegue (fuera del gate, documentado).

- [ ] 22. Crear la migración que reemplaza la función de lectura y blinda permisos.
      Crear `supabase/migrations/20261025000002_clave_inicial_cifrada.sql`: (a) `comment on column public.claves_iniciales.clave is '...sobre cifrado AES-GCM, nunca texto plano...';`; (b) `revoke all on function public.ver_clave_inicial(text) from public, anon, authenticated;` + `drop function if exists public.ver_clave_inicial(text);`; (c) crear `public.clave_inicial_cifrada(p_token text)` `security definer` con la **misma** condición de autorización que la vieja (correo invitado + invitación pendiente/vigente) devolviendo el **texto cifrado** o `null`; (d) `revoke all on function public.clave_inicial_cifrada(text) from public, anon, authenticated;` + `grant execute on function public.clave_inicial_cifrada(text) to service_role;` (sin `authenticated`). No tocar el trigger de borrado al aceptar.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/supabase/migrations/20261025000002_clave_inicial_cifrada.sql`
      Verify: `rls_test.sql` no referencia estas funciones (no se rompe); aceptación en `bash tool/verify.sh`. Revisar sintaxis SQL.

- [ ] 23. Hacer que `initialPassword` invoque `qhub-clave` vía `invokeFunction`, manteniendo la firma `Result<string | null>`.
      Modificar `apps/web/src/features/staff/data/supabase-staff-repository.ts`: reemplazar la llamada RPC `ver_clave_inicial` por el bloque del diseño:
      ```ts
      initialPassword(token: string): Promise<Result<string | null>> {
        return this.run(async () => {
          const r = await invokeFunction<{ clave: string | null }>(this.sb, 'qhub-clave', { token: token.trim() });
          if (!r.ok) throw r.failure;
          return r.value?.clave ?? null;
        });
      }
      ```
      `invokeFunction` ya está importado (línea 3). No tocar `InvitationPage.tsx` (consume `staff.initialPassword` vía `['invitation-password', token]`; `null` oculta el bloque, como hoy). Documentar en el commit que el `200 { clave: null }` llega como `ok(null)` sin reinterpretar `Failure`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/web/src/features/staff/data/supabase-staff-repository.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/web'` — `invitations.test.tsx` sigue verde (`FakeStaffRepository.initialPassword` no cambia). Documentar `CLAVE_INICIAL_KEY` (solo el **nombre**) en `supabase/functions/deno.json`/entorno de despliegue según el patrón de los otros secretos; nunca commitear el valor.

---

## Grupo D — Tarea 3: Paridad del perfil móvil + selectores país/ciudad (`apps/mobile`)

- [ ] 24. Crear el `SelectField` del kit móvil (selector tipo lista buscable, solo tokens).
      Crear `apps/mobile/src/shared/ui/SelectField.tsx` (**shared/ui**): campo que reutiliza `TextField` como disparador visual y abre un `Modal` con lista buscable (`ListRow`/`Pressable`) sobre `{ value, label }[]`; búsqueda opcional (cubre país, ciudad y zona horaria con un solo componente). Estilos solo con tokens NativeWind (`bg-field`, `border-border-strong`, `t-*`, `h-control-*`); el scrim del `Modal` reutiliza el token `bg-overlay` que ya usa `ConfirmModal` (kit.tsx). Accesible (`accessibilityRole`, `accessibilityState.selected`).
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/shared/ui/SelectField.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 25. Crear el dominio del perfil móvil (reexporta `@qhub/core` y el puerto del repositorio).
      Crear `apps/mobile/src/features/profile/domain/profile.ts` (**domain**, TS puro): reexporta `Profile`/`EMPTY_PROFILE`/`validateProfile` de `@qhub/core`; define `managedFields = ['firstName','lastName','phone','jobTitle'] as const`; define el puerto `export interface ProfileRepository { get(): Promise<Result<Profile>>; update(p: Profile): Promise<Result<Profile>>; managementStatus(): Promise<Result<boolean>>; }`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/domain/profile.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 26. Crear el adaptador Supabase del perfil móvil.
      Crear `apps/mobile/src/features/profile/data/supabase-profile-repository.ts` (**data**): `SupabaseProfileRepository` que recibe el `SupabaseClient`, con `run()`/`failureFromSupabase` como en `supabase-user-repository.ts`: `get()` → `select('nombre, apellido, telefono, cargo, pais, ciudad, zona_horaria').eq('id', uid).single()` (mismo mapeo de columnas que el web); `update(p)` → `update({...}).eq('id', uid).select(...).single()`, el error del trigger (`42501`) se mapea a `Failure` genérico vía `failureFromSupabase`; `managementStatus()` → consulta `miembros(usuario_id=uid, activo=true, rol<>'admin')` unida a `organizaciones(tipo='empresa')` (replica `es_miembro_gestionado` desde el cliente, sin nuevo grant). Obtener `uid` de `sb.auth.getUser()`; si no hay, `unauthorizedFailure`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/data/supabase-profile-repository.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 27. Cablear `profiles` en el container móvil (exponiendo el `SupabaseClient` ya creado).
      Modificar `apps/mobile/src/app/container.tsx`: construir `new SupabaseProfileRepository(sb)` con el `sb` ya creado en `buildContainer`, añadir `profiles: ProfileRepository` a `Container`. Actualizar `apps/mobile/src/testing/fakes.ts` y `makeContainer` para añadir un `FakeProfileRepository` (carga perfil configurable, `update` que respeta/registra llamadas, `managementStatus` configurable) y exponerlo en `TestContainer['fakes']`.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/app/container.tsx`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/testing/fakes.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/mobile'` — compila y la suite móvil sigue verde.

- [ ] 28. Crear el hook de formulario del perfil móvil.
      Crear `apps/mobile/src/features/profile/presentation/useProfileForm.ts` (**presentation**): TanStack Query `['profile']` con `profiles.get()`; estado de formulario como `PersonalTab` del web (carga, normaliza país con `countryByAny`, detecta `managed` con `profiles.managementStatus()`, valida con `validateProfile`, guarda con `profiles.update()`, toasts de éxito/error con `friendlyError`); expone `form`, `set`, `save`, `managed`, `errs`, `busy`, estados de carga/error.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/presentation/useProfileForm.ts`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck'` sin errores.

- [ ] 29. Crear `LocationFields` y `PhoneField` del móvil y ampliar `ProfileScreen` con «Datos personales».
      Crear `apps/mobile/src/features/profile/presentation/LocationFields.tsx` (**presentation**): País → Ciudad → Zona horaria con `SelectField` y `citiesOf`/`timeZonesOf`/`countryByAny` de `@qhub/core` (misma lógica que el web, UI con el kit móvil). Crear `apps/mobile/src/features/profile/presentation/PhoneField.tsx` (**presentation**): `SelectField` de prefijo por país (`countryByAny().dial`) + `TextField`, validación `isValidPhone`. Modificar `apps/mobile/src/features/profile/presentation/ProfileScreen.tsx`: añadir sección «Datos personales» (identidad, contacto, ubicación) usando `useProfileForm`; deshabilitar los `managedFields` ya completos cuando `managed` (como el web) y mostrar `Notice kind="info"` de cuenta gestionada; botón primario único «Guardar»; conservar tema y cerrar sesión. Español, tuteo, sentence case; solo tokens.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/presentation/LocationFields.tsx`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/presentation/PhoneField.tsx`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/presentation/ProfileScreen.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm run typecheck && npm test -w @qhub/mobile'` — verde.

- [ ] 30. Añadir los tests del perfil móvil (dominio y pantalla con fake).
      Crear `apps/mobile/src/features/profile/domain/profile.test.ts` si hace falta cubrir reglas propias (`managedFields`); crear `apps/mobile/src/features/profile/presentation/ProfileScreen.test.tsx` (o `useProfileForm.test.ts`) con el `FakeProfileRepository` del ítem 27, siguiendo el patrón de `app-flow.test.tsx`: carga perfil, edita ciudad (permitido), intenta editar un campo gestionado ya completo (deshabilitado), guarda.
      Files: `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/domain/profile.test.ts`, `/home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil/apps/mobile/src/features/profile/presentation/ProfileScreen.test.tsx`
      Verify: `docker compose --profile tools run --rm -T node bash -lc 'npm test -w @qhub/mobile'` — nuevos tests pasan, resto verde.

---

## Verificación final (aceptación)

- [ ] 31. Ejecutar la puerta de verificación completa y dejarla en verde.
      Desde dentro del worktree: `bash tool/verify.sh`. Debe terminar en **exit 0** (instala, genera design system, typecheck estricto, `npm test` de los 5 paquetes, build web, export Expo Android, `deno test _shared/`, contrato contra la API real, RLS si hay `.env.secret`). No cambiar el wiring de localhost. Si un paso falla, corregir en la capa correspondiente y repetir.
      Files: — (ejecución del gate)
      Verify: `bash tool/verify.sh` → `✔ Verificación completa` y exit 0.

---

## Supuestos y huecos

- **Supabase Realtime** (`postgres_changes`) y la publicación `supabase_realtime`: no verificable en el gate local (RLS corre en transacción que se deshace y no levanta Realtime). Mitigado por el **fallback a polling**, que se conserva. Asunción documentada en el diseño.
- **`CLAVE_INICIAL_KEY`** (base64 → 32 bytes): la provee el usuario como secret de las Edge Functions; el gate solo corre `deno test _shared/` con clave de prueba. El flujo end-to-end de `qhub-invite`/`qhub-clave` desplegadas no lo ejercita el gate (se prueba en despliegue). Por eso la validación de arranque y el helper `importKey` son explícitos y probados.
- **Barrel `staff/domain`**: si `apps/web/src/features/staff/domain/index.ts` reexporta `profile.ts` por nombre, el ítem 4 no requiere más cambios; si importa símbolos sueltos, ajustar ese índice para seguir exponiendo `Profile`/`validateProfile`/`EMPTY_PROFILE`/`isProfileComplete`. Verificarlo al implementar el ítem 4.
- Los 5 pendientes de despliegue del usuario (publicar la API en Render + `QHUB_API_BASE_URL`, SMTP propio, rotar tokens, probar el APK, activar `ENFORCE_TURN_OWNERSHIP`) quedan **fuera de alcance** y no se bloquean con estos cambios.
