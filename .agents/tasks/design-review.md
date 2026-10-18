# Revisión de diseño — Notificaciones en tiempo real (web), cifrado de `claves_iniciales` y paridad del perfil móvil

Revisor: subagente de revisión de diseño (lectura en frío, verificación contra el código fuente).
Documento revisado: `.agents/tasks/design.md` (worktree `mejoras-web-movil`).
Alcance de la verificación: se leyó el código real de `Qhub_App` para confirmar cada afirmación del diseño. La API Qhub (`/home/miguelzambrano/projects/Qhub`) es de solo lectura; cualquier cambio en ella sería HIGH (BLOCKED).

Este diseño es una **segunda iteración**: ya respondió a una revisión previa (1 HIGH + 4 MEDIUM + 4 NIT) en su sección final. Esta revisión verifica de forma independiente que las correcciones afirmadas son ciertas contra el código, no solo prometidas.

---

## Veredicto

**APPROVED.** Cero findings HIGH, cero MEDIUM. Las observaciones registradas son todas NIT y no bloquean la implementación. La verificación del código confirma las afirmaciones clave del diseño (contrato de `qhub-clave`, comportamiento real de `InvitationPage`, wiring del `actor`/`ApiContext`, helpers de `@qhub/core`, RLS/trigger de cuenta gestionada, alcance real del gate Deno).

---

## Findings

### 1. [NIT] El token `bg-overlay` ya existe; el diseño lo trata como «posible token faltante»
**Dónde:** Tarea 3 → «Diseño/tokens» → «Posible token faltante: si el `Modal` del `SelectField` necesita un color de scrim/overlay y no existe un token (p. ej. `bg-overlay`)…».
**Problema:** Verificado en `apps/mobile/src/shared/ui/kit.tsx:197`, `ConfirmModal` ya usa `className="flex-1 justify-center bg-overlay p-4"`. El token `bg-overlay` **existe** y está en uso. La incertidumbre del diseño es obsoleta.
**Fix concreto:** Reemplazar la frase por una afirmación: «El `Modal` del `SelectField` reutiliza el token `bg-overlay` que ya usa `ConfirmModal` (kit.tsx:197) para el scrim. No se inventa ningún color.» Elimina la ambigüedad del condicional.

### 2. [NIT] El mecanismo exacto para «subir el intervalo» del polling cuando Realtime está conectado no está especificado
**Dónde:** Tarea 1B → `useNotices` → «Fallback: mantener `refetchInterval` tal cual, pero cuando la suscripción esté `connected` subir el intervalo a un valor largo (p. ej. a `false`/300 s)…».
**Problema:** Verificado en `useNotices.ts`: `refetchInterval` proviene de `useRefreshInterval()` (preferencia del usuario: `refreshSeconds === 0 ? false : refreshSeconds*1000`), no de una constante local. El diseño describe el *comportamiento* deseado (reducir el polling al conectar) pero no el *mecanismo* para sobrescribir un valor que hoy viene de una preferencia. No es incorrecto, pero deja al implementador decidir cómo combinar el estado de la suscripción con la preferencia.
**Fix concreto:** Fijar la regla: mantener un estado local `rtStatus` (`'connected' | 'off'`) alimentado por `onStatus`; pasar a la query `refetchInterval: rtStatus === 'connected' ? false : useRefreshInterval()`. Al reportar `error`/`closed`, volver a `useRefreshInterval()`. Así la preferencia del usuario sigue mandando cuando Realtime no está, y el polling se apaga (no «300 s») cuando sí lo está. Quitar el «300 s» ambiguo y dejar `false` como único valor «conectado».

### 3. [NIT] El montaje de `<QhubNotices />` se describe como «cuando hay sesión/organización» pero el shell lo gatea por permiso
**Dónde:** Tarea 1A → Archivos → «Modificar `AppShell.tsx` — montar `<QhubNotices />` junto a `<NoticePopups />` (solo cuando hay sesión/organización)».
**Problema:** Verificado en `AppShell.tsx:92`: `NoticePopups` se renderiza dentro de `{can(role, 'notifications.view') && <><NoticePopups /><NotificationBell /></>}`. «Junto a `NoticePopups`» lo colocaría tras el permiso `notifications.view` (un permiso de *avisos de equipo*), mientras que los avisos personales de Qhub (Tarea 1A) son del integrante y dependen de `connection.status`, no de ese permiso. No es un bug (el hook ya no abre socket sin conexión Qhub), pero la ubicación propuesta y la justificación («sesión/organización») no coinciden con el gate real.
**Fix concreto:** Decidir explícitamente el punto de montaje: o bien montar `<QhubNotices />` **fuera** del gate `notifications.view` (p. ej. junto al shell autenticado, siempre que haya sesión), ya que su activación real la controla el `useEffect` atado a `connection.status`; o bien documentar que se acepta reutilizar el gate `notifications.view`. Fijar uno en el diseño para no dejarlo a criterio del implementador.

---

## Verified Assumptions (comprobadas contra el código)

- **Estructura Clean Architecture por feature con subcarpetas de capa.** `apps/web/src/features/notifications/{domain,data,presentation}/` existe con esa forma exacta (`data/supabase-notifications-repository.ts`, `domain/notifications.ts`, `presentation/useNotices.ts`, etc.). La regla «cada archivo en su subcarpeta de capa» es real.
- **`verify.sh` (el gate).** Confirmado: instala, `npm run generate -w @qhub/design`, `npm run typecheck`, `npm test`, build web, `expo export` Android, **`deno test _shared/`** (único paso Deno), contrato HTTP/WS contra la API real, ownership de turnos y RLS (`rls_test.sql` si hay `.env.secret`). El diseño describe el alcance del paso Deno correctamente (solo `_shared/`).
- **Tarea 1A — WS personal.** `packages/api-client/src/data/realtime.ts`: `RealtimeRepositoryImpl.subscribeNotifications({ onNotification, onError?, onStatus? })` existe; `url()` lanza `unauthorizedFailure()` si no hay `token`/`actor`; cierre **4401** → `onError(unauthorizedFailure())` + `context.onUnauthorized()` y no reintenta; red → backoff exponencial. Mensajes pasan por `notificationEventFromJson` (descarta lo que no cumple el contrato). Todo coincide con el diseño.
- **`ApiContext.actor` se puebla en la web.** `transport.ts` define `actor`; `features/session/domain/app-session.ts` lo fija en `restore`/`autoConnect`/`login` con `{ userId: u.id, role: toActorRole(m.role) }` vía `connection.ts`. La premisa de la Tarea 1A (hay actor/token del staff) es real.
- **`notifications` (REST Qhub) cableado pero sin pantalla.** `container.tsx:58` construye `new NotificationRepositoryImpl(transport)`; `repositories.ts:41` expone `list(opts?: { limit?; offset? }): Promise<Result<AppNotification[]>>`; `AppNotification` existe en `entities.ts:70`. El hallazgo del diseño (está cableado y no se consume) es correcto.
- **`AppShell` monta `NoticePopups`.** Confirmado en `AppShell.tsx` (tras `can(role,'notifications.view')`).
- **Tarea 2 — estado actual.** Migración `20261024000002_clave_inicial.sql`: tabla `claves_iniciales(clave text not null)` en claro, RLS activa **sin políticas** + `revoke all`; `ver_clave_inicial(p_token)` es `security definer`, `grant execute ... to authenticated`; trigger `borrar_clave_inicial` borra al aceptar. `qhub-invite/index.ts` escribe `admin.from("claves_iniciales").upsert({ invitacion_id, clave: newPassword })` en claro, solo si `newPassword`. Todo coincide.
- **Patrón de Edge Function reutilizable.** `qhub-invite` usa `asUser` (Authorization header + `auth.getUser()`), `admin` (service_role), `json(status,body)` con `Cache-Control: no-store` y CORS. El diseño de `qhub-clave` reutiliza este patrón fielmente.
- **`invokeFunction`.** `apps/web/src/shared/data/invoke-function.ts`: devuelve `Result<T>`; `ok(data)` en 200; mapea 400→`badRequestFailure`, 401→`unauthorizedFailure`, `FunctionsFetchError`→`networkFailure`, resto→`serverFailure`. El snippet del diseño para `initialPassword` (`if (!r.ok) throw r.failure; return r.value?.clave ?? null;`) funciona: `run()` captura con `failureFromSupabase(e)`, que **devuelve el `Failure` tal cual** cuando `isFailure(e)` (verificado en `supabase-failure.ts:8`). El repo ya importa `invokeFunction` (línea 3) y lo usa en `sendInvite`.
- **`InvitationPage` NO renderiza `clave.error`.** Verificado línea por línea: solo muestra `preview.error` (y el estado local `error`). `password = clave.data ?? null`; el bloque de contraseña se renderiza solo cuando `password` es truthy. Por tanto un `500` de descifrado deja `clave.data === undefined` → `password = null` → bloque oculto en silencio. La corrección del diseño (HIGH previo) es **exacta**; la afirmación anterior «muestra error y ofrece recuperación» habría sido falsa.
- **RLS test no referencia `claves_iniciales`/`ver_clave_inicial`.** `grep` en `supabase/tests/rls_test.sql` → ninguna coincidencia. El `drop function` y el cambio de contenido de la columna no rompen el test. Correcto.
- **Numeración del RLS test.** Prueba **27** = «equipo gestionado» (bloquea cambiar `nombre` ya completo con `insufficient_privilege`; permite completar `telefono` vacío y cambiar `ciudad`); prueba **28** = Auth (contraseña/correo). La corrección del NIT previo es correcta.
- **Tarea 3 — estado actual.** `apps/mobile/.../ProfileScreen.tsx` solo muestra `displayName`/`email` + tema + cerrar sesión; no lee `perfiles`. El kit móvil (`kit.tsx`) tiene `TextField`, `Segmented`, `ListRow`, `ConfirmModal`, `Button` y **no** un `SelectField`. El trigger `trg_perfil_gestionado` (`20261023000002`) bloquea `nombre/apellido/telefono/cargo` ya completos y **no** `pais/ciudad/zona_horaria`. `es_miembro_gestionado` está `revoke`-ado de `authenticated`.
- **RLS permite la detección de cuenta gestionada desde el móvil sin nuevo grant.** `miembros_select`: `usuario_id = (select auth.uid()) or es_miembro(...)`; `org_select`: `(publica and activa) or es_miembro(id)`. Un miembro lee sus propias filas de `miembros` y la fila de su `organizaciones` (incluido `tipo`). El enfoque del diseño es viable.
- **`@qhub/core` geografía y perfil.** `geo.ts` exporta `COUNTRIES`, `countryByAny`, `citiesOf`, `timeZoneLabel`, `timeZonesOf`. `features/staff/domain/profile.ts` define `Profile`, `EMPTY_PROFILE`, `isProfileComplete`, `validateProfile` dependiendo solo de `@qhub/core` (`isValidPhone`, `validatePersonName`) — promovible a `@qhub/core` sin acoplar a React.
- **AES-GCM/Web Crypto ya se usa en el repo.** `apps/web/src/features/qhub/data/device-credential-vault.ts` existe; justifica la «coherencia criptográfica» del enfoque de la Tarea 2, y el diseño correctamente aclara que **no** aplica (clave por dispositivo) a datos visibles por el servidor.
- **`_shared/` del gate.** Contiene `invite.ts`, `policy.ts`, `qhub.ts`, `recover.ts` con sus `_test.ts`. Añadir `crypto.ts`/`crypto_test.ts` (+ `clave_flow_test.ts` recomendado) en `_shared/` queda cubierto por `deno test _shared/`.

## Unverified / Wrong Assumptions

**Wrong (ya corregidas en esta iteración del diseño, confirmado contra el código):**
- La versión previa del diseño afirmaba que `InvitationPage` muestra un error genérico y ofrece recuperación ante fallo de descifrado — **falso**; la página nunca renderiza `clave.error`. El diseño actual lo corrige y documenta el degradado silencioso. ✔ Resuelto.
- El contrato de `qhub-clave` se fijó en `200 { clave: string | null }` (no `404`), coherente con `password = clave.data ?? null`. ✔ Resuelto.

**Unverified (no comprobables desde el código; el diseño las declara y las mitiga):**
- **Supabase Realtime (`postgres_changes`) disponible y la publicación `supabase_realtime` acepta la tabla.** No hay ninguna referencia a `supabase_realtime` en las migraciones actuales (verificado), así que la nueva migración asume que la publicación existe (por defecto en Supabase). El gate no levanta Realtime (`rls_test.sql` corre en una transacción que se deshace). Mitigado por el **fallback a polling**, que el diseño mantiene y que es real en `useNotices`. Riesgo aceptable y documentado.
- **`CLAVE_INICIAL_KEY` presente y válida (base64 → 32 bytes) en despliegue.** El gate solo corre `deno test _shared/` con una clave de prueba; el flujo end-to-end no se ejercita. Mitigado por la validación de arranque especificada (`importKey` rechaza ≠32 bytes; `qhub-clave`→500 controlado; `qhub-invite` omite el `upsert`) y el test Deno recomendado con fake de Supabase. Riesgo aceptable y documentado.
- **El invitado abre `qhub-clave` con JWT de Supabase válido**, igual que hoy llamaba la RPC autenticada; `sb.functions.invoke` adjunta el `Authorization`. Consistente con el patrón de `qhub-invite` (`req.headers.get("Authorization")` + `auth.getUser()`), verificado.

## Elementos BLOQUEADOS (API Qhub de solo lectura)

Ninguno. Verificado que las tres tareas se resuelven en `apps/web`, `apps/mobile`, `packages/*` y `supabase/*`. La Tarea 1A **consume** `/ws/notificaciones` vía `@qhub/api-client` ya existente (no modifica la API). Las Tareas 2 y 3 son de Supabase (`Qhub_App`). No se detecta ninguna modificación implícita a `/home/miguelzambrano/projects/Qhub`.
