# Qhub App (móvil)

App móvil de Qhub para el público (React Native + Expo + NativeWind), sobre la [API Qhub](../Qhub).
Repo independiente: la plataforma web vive en otro repo (`../Qhub_Web`, se despliega en Vercel).
Aquí está la app móvil, los paquetes compartidos, Supabase (migraciones y Edge Functions) y las herramientas.

| | |
|---|---|
| Para quién | Público (clientes que sacan turno) |
| Stack | React Native (Expo) · React Navigation · TanStack Query · NativeWind |
| Hace | Explorar organizaciones, vincularse, sacar turno (ahora o reservado), ver posición y espera, avisos, historial, perfil |
| API Qhub | **Nunca directa**: por la Edge Function `qhub-proxy` (Supabase) |

## Estructura

```
packages/
  core/          Result, Failure, formato de turnos, geografía, validaciones (TypeScript puro)
  api-client/    Cliente de la API Qhub: dominio (entidades, puertos, casos de uso) + datos (fetch, WebSocket)
  design/        Tokens → tema de NativeWind, íconos y logos (generado desde tokens.json)
apps/
  mobile/        features/{auth,organizations,gateway,tickets,notifications,history,profile,permissions}
supabase/        migrations · functions (qhub-proxy, qhub-link, qhub-invite, qhub-clave) · tests (RLS)
docker/ compose.yaml tool/
```

Clean Architecture por feature (carpetas planas; la capa se reconoce por el nombre del archivo).
Lo común a la web y al móvil vive en `packages/` (este repo tiene su propia copia).

> Diseño: sale **siempre** del design system (`@qhub/design`, generado desde `tokens.json`
> con `npm run generate -w @qhub/design`). Nada de hex/tamaños sueltos.

## Variables de entorno

Todo el entorno vive en el `.env` de la raíz (gitignored). Docker lo lee y reparte lo público al móvil (`EXPO_PUBLIC_*`); `tool/` lo usa para las migraciones y el despliegue de Edge Functions.

| Variable | Para qué |
|---|---|
| `APP_ENV`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Públicas |
| `EXPO_PUBLIC_APP_ENV`, `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Se incrustan en el APK al compilar |
| `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, `APP_URLS` | Secretas: solo `tool/`. **Nunca** llegan a la app |
| `SMTP_*` (opcional) | Correo propio con tu marca |

El móvil habla con **Supabase** (no directo con la API). El secret con la URL pública de la API
(`QHUB_API_BASE_URL`) va en **Supabase → Edge Functions**, no en este `.env`:

```bash
docker run --rm -e SUPABASE_ACCESS_TOKEN -v "$PWD:/work" -w /work node:22-slim \
  npx -y supabase@latest secrets set QHUB_API_BASE_URL=https://api.tu-dominio.com --project-ref <ref>
```

La clave inicial de una invitación se guarda **cifrada** en reposo (AES-GCM). Las funciones
`qhub-invite` (cifra) y `qhub-clave` (descifra) necesitan el secret `CLAVE_INICIAL_KEY`
(AES-256 en base64, 32 bytes):

```bash
docker run --rm -e SUPABASE_ACCESS_TOKEN -v "$PWD:/work" -w /work node:22-slim \
  npx -y supabase@latest secrets set CLAVE_INICIAL_KEY=$(openssl rand -base64 32) --project-ref <ref>
```

## Cómo se ejecuta (Docker)

```bash
tool/verify.sh                                             # tipos + tests + bundle + política del proxy + contrato contra la API + RLS
docker compose --profile tools run --rm node bash          # shell con Node 22
docker compose --profile local-api up -d qhub-api          # API local
docker compose --profile local-api run --rm contract-tests # pruebas de integración contra ella
```

**APK.** `tool/build-apk.sh` compila el APK de Android en Docker (`apk/qhub.apk`): cópialo al
teléfono e instálalo aceptando «instalar apps de orígenes desconocidos». Está firmado con llave
de depuración (para Google Play hace falta tu propia llave). La primera compilación tarda
(descarga el SDK de Android); las siguientes usan la caché.

**Verlo en el PC (emulador).** `tool/build-apk.sh emulador` genera un APK x86_64 y
`tool/emulator.sh` levanta un emulador de Android en Docker y lo muestra en `http://localhost:6080`.
Requiere KVM (tu usuario en el grupo `kvm`).

## Recuperación de contraseña y URLs permitidas

`python3 -I tool/supabase_auth.py` fija en Supabase la URL del sitio y las redirecciones
permitidas (`APP_URLS` en `.env`) y exige contraseñas de 8+ caracteres.

## Errores seguros

Ningún error muestra detalles técnicos: todo pasa por `Failure` (`@qhub/core`), que reemplaza lo
técnico por un mensaje genérico en español; una pantalla que falla muestra «Algo salió mal»
(`ErrorBoundary`) y los detalles van a la consola.

---

Documentación ampliada (plan, arquitectura, convenciones): ver el repo `../Qhub_Doc`.
