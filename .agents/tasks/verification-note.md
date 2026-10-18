# Nota de verificación

Todo se ejecutó dentro del worktree `/.worktrees/mejoras-web-movil`, a través de Docker (sin Node en el host).
Primero se instalaron las dependencias del worktree: `docker compose --profile tools run --rm -T -e UID=$(id -u) node bash -lc 'npm install'` (added 1249 packages).

## Comandos ejecutados y resultado

| Paso | Comando | Resultado |
|---|---|---|
| Typecheck (todos) | `docker compose --profile tools run --rm -T -e UID=$(id -u) node bash -lc 'npm run typecheck'` | **PASS** — api-client · core · design · mobile · web, `tsc --noEmit` sin errores |
| Tests (todos) | `docker compose --profile tools run --rm -T -e UID=$(id -u) node bash -lc 'npm test'` | **PASS** — core 49, api-client 49, design 7, web 224 (30 archivos), mobile 35 (10 suites) |
| Deno `_shared/` | `docker run --rm -v "$PWD/supabase/functions:/app" -w /app denoland/deno:latest deno test _shared/` | **PASS** — 30 passed / 0 failed (incluye `crypto_test.ts` y `clave_flow_test.ts` nuevos) |
| Build web | `docker compose --profile tools run --rm -T -e UID=$(id -u) node bash -lc 'npm run build -w @qhub/web'` | **PASS** — `✓ built` |

Nota: la suite móvil (Jest) emite el aviso "A worker process has failed to exit gracefully"; es un aviso de teardown de Jest, no una falla (reporta `10 passed, 35 passed`).

## Qué se verificó por tarea

- **Tarea 1 (tiempo real web).** `apps/web/src/app/flows/workspace.test.tsx` sigue verde (sin regresión). Tests nuevos: `useQhubNotifications.test.tsx` (abre socket solo con conexión; un aviso dispara toast) y `useNotices.test.tsx` (un evento del canal invalida y refresca lista/conteo). `invitations.test.tsx` verde.
- **Tarea 2 (cifrado de la clave inicial).** `crypto_test.ts` (ida y vuelta, IV distinto, sobre inválido, clave equivocada, `importKey` exige 32 bytes) y `clave_flow_test.ts` (clave ausente/inválida → invite omite upsert, clave responde 500; sobre autorizado null → 200 { clave: null }; descifrado OK → 200 { clave }). `deno test _shared/` cubre ambos. El flujo end-to-end de las funciones desplegadas y la presencia real de `CLAVE_INICIAL_KEY` quedan para despliegue (fuera del gate, documentado en README).
- **Tarea 3 (perfil móvil).** `apps/mobile/src/features/profile/domain/profile.test.ts` (campos gestionados + validación compartida) y `ProfileScreen.test.tsx` (carga, edita ciudad por selector y guarda; en cuenta gestionada los campos gestionados completos no son editables). `app-flow.test.tsx` verde.

## No verificable en el gate local
- Supabase Realtime (`postgres_changes`) y la publicación `supabase_realtime`: mitigado por el fallback a polling, que se conserva.
- `CLAVE_INICIAL_KEY` real y el flujo HTTP de `qhub-invite`/`qhub-clave` desplegadas: la lógica se concentró en helpers puros de `_shared/` probados por el gate.
