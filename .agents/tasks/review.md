# Realtime web notifications, encrypted invitation password, and mobile profile parity

Three independent improvements land in `Qhub_App` on `mejoras-web-movil`. Task 1 wires the existing `@qhub/api-client` WebSocket (`/ws/notificaciones`) into the web shell for personal Qhub notices and adds Supabase Realtime for team notices (`notificaciones_staff`), keeping TanStack Query polling as the fallback. Task 2 moves the invitation initial password from plaintext at rest to an AES-GCM envelope encrypted with a server-only key (`CLAVE_INICIAL_KEY`), read back once through a new `qhub-clave` Edge Function. Task 3 brings the mobile profile screen to parity with web, adding searchable país/ciudad/zona/prefijo selectors built on `@qhub/core` geography, while respecting managed-account limits. All work stays inside `apps/`, `packages/`, and `supabase/`; the read-only Qhub API was not touched.

Watch for: nothing blocking. The `architecture.test.ts` named in the task does not exist in the repo (confirmed), so there is nothing to regress — structure is enforced by convention and was verified by the prior design review (**possible**). Supabase Realtime availability and a correctly-provisioned `CLAVE_INICIAL_KEY` are deploy-time concerns, both mitigated in-code (polling fallback; fail-closed encryption) and documented in README (**confirmed**).

**Verdict**: APPROVED

## High-level view

The hard constraint holds. `/home/miguelzambrano/projects/Qhub` has a clean working tree and its last commit predates this work; nothing under it changed. `packages/api-client` is untouched, so the Qhub WS transport and contract are consumed, not modified.

Task 2 is the highest-risk surface and is sound. AES-GCM with a random 12-byte IV and a versioned `{ v, iv, d }` base64 envelope, a key validated to exactly 32 bytes, and a server-only secret that never touches the database. The design is fail-closed: with no key the invite skips the upsert entirely (no plaintext ever written) and the read path returns a controlled 500. The migration drops the old `ver_clave_inicial` (which would have leaked the ciphertext to any authenticated caller) and replaces it with a `service_role`-only reader that keeps the same email + pending-invitation authorization, so the invitee still reads their password exactly once.

Task 1 keeps polling as a graceful fallback rather than replacing it. `useNotices` turns the interval off only while the Realtime channel reports `connected` and restores the user's preferred interval the moment it drops. The Realtime channel is scoped to the organization and relies on the existing RLS SELECT policy, so it exposes nothing new. The personal Qhub WS only subscribes while the Qhub connection is active, reusing the pre-existing `actor`/token/`ApiContext` plumbing and the 4401 no-retry behavior already in `@qhub/api-client`.

Task 3 reuses `@qhub/core` for both validation and geography with no duplication — the shared `Profile` logic was promoted into core and web now re-exports it unchanged. Managed-account fields (nombre, apellido, teléfono, cargo) are locked once complete, matching the web trigger, while país/ciudad/zona stay editable. The mobile `SelectField`, `LocationFields`, and `PhoneField` use design-system tokens only.

Spanish UI and the `Result<T>`/`Failure`/`friendlyError` error contract are honored throughout. Existing behavior is preserved: `workspace.test.tsx` stays green per the verification note, fakes and the web harness were extended additively, and localhost wiring is unchanged.

<details>
<summary>Issues (3)</summary>

1. **Missing `architecture.test.ts`** — the task asks that `architecture.test.ts` still applies, but no such file exists in the repo. Not a regression (nothing to break); worth confirming structure enforcement is intentional-by-convention rather than a lost test. (possible)
2. **Stylistic import ordering in mobile `domain/profile.ts`** — a duplicate `import type { Profile }` and an `import` placed after an `export`. Valid TS and typecheck passes; tidy up for readability. (confirmed)
3. **Deploy-time preconditions** — Supabase Realtime publication acceptance and a valid `CLAVE_INICIAL_KEY` are not exercised by the local gate. Both are mitigated in-code (polling fallback; fail-closed crypto) and documented in README; verify during deploy. (confirmed, out of gate scope)

</details>

<details>
<summary>Details</summary>

### Hard constraint: Qhub API untouched

`git status --short` in `/home/miguelzambrano/projects/Qhub` returns nothing and its HEAD is `d963a6a` ("feat:arreglo api") dated before this work. The diff is confined to `Qhub_App` (`apps/`, `packages/`, `supabase/`, `PLAN.md`, `README.md`, `.agents/`). `packages/api-client` shows zero changes in `git diff main --stat`, so Task 1 consumes `/ws/notificaciones` through the already-shipped `RealtimeRepositoryImpl.subscribeNotifications` rather than altering the transport or contract (**confirmed**).

### Task 2 — invitation password encrypted at rest

`_shared/crypto.ts` implements AES-GCM with a 12-byte random IV and a versioned envelope `{ v: 1, iv, d }` in base64. `importKey` rejects anything that does not decode to 32 bytes, so a misconfigured key fails loudly rather than silently weakening the cipher. `decrypt` validates the envelope shape and version before attempting, and throws a typed error on a wrong key.

The orchestration in `_shared/clave.ts` is where the fail-closed posture lives. `loadKey` returns `null` when `CLAVE_INICIAL_KEY` is absent or invalid. `sealInitialPassword` returns `null` in that case, and `qhub-invite` then skips the `claves_iniciales` upsert entirely — so plaintext is never written as a fallback; the invite still sends and the person recovers via "forgot password." On the read side, `readInitialPassword` distinguishes three outcomes: no authorized envelope → `200 { clave: null }` (accepted/expired/email mismatch), a valid envelope → `200 { clave }`, and a present envelope with a missing or non-matching key → `500` with the detail kept to the server console.

```sql
revoke all on function public.ver_clave_inicial(text) from public, anon, authenticated;
drop function if exists public.ver_clave_inicial(text);
-- new reader: same auth, returns the ciphertext, service_role only
revoke all on function public.clave_inicial_cifrada(text) from public, anon, authenticated;
grant execute on function public.clave_inicial_cifrada(text) to service_role;
```

Dropping the old function closes the real leak: after this migration the stored value is ciphertext, and `ver_clave_inicial` would have handed that blob to any `authenticated` caller. The new `clave_inicial_cifrada` preserves the identical authorization (`lower(i.email) = lower(v_email)` on a pending, unexpired invitation) but is reachable only by `service_role`, i.e. the `qhub-clave` function. The web client's `SupabaseStaffRepository.initialPassword` now calls `qhub-clave` via `invokeFunction` and maps `200 { clave: null }` to `ok(null)`, so the invitee still reads the password once at accept time and `InvitationPage` renders it with no code change. The `200`-with-null contract matches `InvitationPage`'s existing `password = clave.data ?? null`, so a 500 degrades to a hidden block rather than an error surface — this was the HIGH finding from the prior design review and is confirmed fixed.

Coverage: `crypto_test.ts` exercises round-trip, IV uniqueness, wrong-key rejection, invalid-envelope rejection, and the 32-byte key requirement; `clave_flow_test.ts` covers key present/absent/invalid, seal-without-key skips, and all three read outcomes including both 500 paths. Both run under `deno test _shared/` in the gate.

### Task 1 — realtime notices with polling fallback

Team notices use `SupabaseNotificationsRealtime`, a `postgres_changes` subscription on `notificaciones_staff` filtered by `organizacion_id`. The migration adds the table to the `supabase_realtime` publication idempotently and leans on the existing per-organization RLS SELECT policy, so Realtime delivers nothing a user could not already read.

```
rtConnected ? refetchInterval = false        // realtime drives updates
            : refetchInterval = useRefreshInterval()  // user's polling preference
```

`useNotices` keeps polling as the fallback rather than replacing it: it suppresses the interval only while `onStatus` reports `connected`, and the moment the channel reports `error`/`closed` the user's preferred interval resumes. `NoticePopups` subscribes the same channel to invalidate its own query, keeping its 10s poll as backup. This directly addresses the design review's NIT about the fallback mechanism — the override is `false`-when-connected, preference-otherwise, not an ambiguous long interval.

The personal Qhub stream (`useQhubNotifications`) subscribes to `realtime.subscribeNotifications` only while `connection.status === 'connected'`, invalidates the REST history query on each event, and shows a Spanish toast titled by `mapKindToText`. A 4401 close is logged without surfacing technical detail and does not retry — behavior inherited from the untouched `@qhub/api-client`. `QhubNotices` is a headless mount placed in `<main>` outside the `notifications.view` permission gate, which is correct: personal notices are the member's own and gated by the Qhub connection, not by the team-notice permission (the design review's third NIT).

Coverage: `useQhubNotifications.test.tsx` asserts a toast fires on an event when connected and that no subscription opens without a connection; `useNotices.test.tsx` asserts a channel event invalidates and refetches both list and count.

### Task 3 — mobile profile parity

The shared `Profile` type, `EMPTY_PROFILE`, `isProfileComplete`, and `validateProfile` were promoted verbatim into `@qhub/core/profile`; web's `features/staff/domain/profile.ts` collapses to a single re-export, so no behavior changed and there is no duplication. Mobile imports the same core helpers plus the geography functions (`countryByAny`, `citiesOf`, `timeZonesOf`, `COUNTRIES`) used by `LocationFields` and `PhoneField`.

Managed-account limits mirror the web trigger: `managedFields` is `['firstName','lastName','phone','jobTitle']` (location is deliberately excluded), and `ProfileScreen`'s `locked(f) = managed && !!saved[f]` makes a managed field non-editable only once it is already complete. `SupabaseProfileRepository.managementStatus` replicates `es_miembro_gestionado` client-side (empresa + non-admin role) over RLS-visible rows, avoiding a new grant. The repository returns `Result<Profile>`, translating Supabase errors through `failureFromSupabase`, and the form surfaces failures via `friendlyError` — consistent with the error contract.

`SelectField`, `LocationFields`, `PhoneField`, and `ProfileScreen` use design-system tokens throughout (`min-h-control-lg`, `bg-field`, `border-border-strong`, `bg-overlay`, `supportError`, `textPlaceholder`) with no raw hex, pixel sizes, or invented radii. The modal scrim reuses the existing `bg-overlay` token.

Coverage: `profile.test.ts` pins the managed-field set and shared-validation reuse; `ProfileScreen.test.tsx` loads the profile, edits city via the selector and saves, and asserts a managed field is non-editable on a managed account. `packages/core/src/profile.test.ts` covers the promoted validation.

### Verification evidence

Per `.agents/tasks/verification-note.md` and the commit message, the coder ran (in Docker, inside the worktree): typecheck PASS across api-client, core, design, mobile, web; `npm test` PASS (core 49, api-client 49, design 7, web 224, mobile 35); `deno test _shared/` PASS (30, including the new `crypto_test.ts` and `clave_flow_test.ts`); and web build PASS. The Jest "worker process failed to exit gracefully" message is a teardown warning, not a failure. The evidence is specific and complete; per instructions the suites were not re-run. The only out-of-gate items — Supabase Realtime at runtime and a real `CLAVE_INICIAL_KEY` — are explicitly documented and mitigated in-code.

</details>

<details>
<summary>File map</summary>

- `supabase/functions/_shared/crypto.ts` — AES-GCM encrypt/decrypt, 32-byte key validation, versioned envelope.
- `supabase/functions/_shared/clave.ts` — fail-closed seal/read orchestration and key loading.
- `supabase/functions/qhub-invite/index.ts` — encrypts and upserts the sealed password (skips when no key).
- `supabase/functions/qhub-clave/index.ts` — new function: authorizes and decrypts the initial password once.
- `supabase/migrations/20261025000002_clave_inicial_cifrada.sql` — drops `ver_clave_inicial`, adds `service_role`-only reader, documents the column.
- `supabase/migrations/20261025000001_realtime_avisos_staff.sql` — idempotently adds `notificaciones_staff` to the realtime publication.
- `apps/web/src/features/notifications/data/supabase-notifications-realtime.ts` — Realtime channel scoped by org.
- `apps/web/src/features/notifications/{domain/notifications.ts,domain/qhub-notifications.ts,presentation/useNotices.ts,presentation/useQhubNotifications.ts,presentation/QhubNotices.tsx,presentation/NoticePopups.tsx}` — realtime + WS wiring and kind labels.
- `apps/web/src/features/staff/{data/supabase-staff-repository.ts,domain/profile.ts}` — `initialPassword` via `qhub-clave`; profile re-export from core.
- `apps/web/src/{app/container.tsx,features/shell/presentation/AppShell.tsx,testing/fakes.ts,testing/harness.tsx}` — container/shell/test wiring.
- `apps/mobile/src/features/profile/**` — domain, repository, `useProfileForm`, `ProfileScreen`, `LocationFields`, `PhoneField` and tests.
- `apps/mobile/src/{shared/ui/SelectField.tsx,app/container.tsx,testing/fakes.ts}` — searchable selector and wiring.
- `packages/core/src/{profile.ts,profile.test.ts,index.ts}` — promoted shared profile logic.
- `PLAN.md`, `README.md` — status updates and `CLAVE_INICIAL_KEY` setup.

Full diff: `git -C /home/miguelzambrano/projects/Qhub_App/.worktrees/mejoras-web-movil diff main`.

</details>
