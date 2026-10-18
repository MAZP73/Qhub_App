#!/usr/bin/env bash
# Verifica TODO el proyecto dentro de contenedores: tipos, tests, builds, política de Edge Functions,
# contrato contra la API real en un contenedor y seguridad de la base (RLS).
# Uso:  tool/verify.sh            (todo)
#       tool/verify.sh --web-image   (además construye la imagen de producción de la web con nginx)
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
NODE="docker compose --profile tools run --rm -T node bash -lc"

step "Instalación (npm workspaces)"
$NODE 'npm install --no-audit --no-fund 2>&1 | tail -2'

step "Generación del design system (tokens, Tailwind, íconos)"
$NODE 'npm run generate -w @qhub/design'

step "Tipos (TypeScript estricto) en todos los paquetes y apps"
$NODE 'npm run typecheck'

step "Tests: core · api-client · design · web · móvil"
$NODE 'npm test'

step "Build de la plataforma web"
$NODE 'npm run build -w @qhub/web 2>&1 | grep -E "built|error"'

step "Bundle de la app móvil (Metro + NativeWind, Android)"
$NODE 'cd apps/mobile && set -a && . ../../.env && set +a && export EXPO_PUBLIC_APP_ENV=$APP_ENV EXPO_PUBLIC_SUPABASE_URL=$SUPABASE_URL EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY && CI=1 npx expo export --platform android --output-dir /tmp/export 2>&1 | grep -E "hbc|Exported|rror"'

step "Edge Functions (política del proxy)"
# jsr.io a veces no responde desde Docker: se reintenta antes de dar el paso por fallido
for attempt in 1 2 3; do
  docker run --rm -v "$PWD/supabase/functions:/app" -w /app denoland/deno:latest deno test _shared/ && break
  [[ $attempt == 3 ]] && exit 1
  sleep 5
done

step "Contrato contra la API real"
if (echo > /dev/tcp/127.0.0.1/8000) 2>/dev/null; then
  # Ya hay una API en el puerto 8000 (p. ej. la tuya): se usa tal cual. Las pruebas de contrato solo leen (OpenAPI y rechazo de WebSocket).
  echo "Usando la API que ya corre en 127.0.0.1:8000 (solo lectura)"
  docker run --rm --network host -u "$(id -u):$(id -g)" -e HOME=/tmp/home -e npm_config_cache=/workspace/.npm-cache -e QHUB_API_URL=http://127.0.0.1:8000 \
    -v "$PWD":/workspace -w /workspace qhub_app/node npm run test:integration -w @qhub/api-client
else
  docker compose --profile local-api up -d qhub-api >/dev/null
  docker compose --profile local-api run --rm contract-tests
  docker compose stop qhub-api >/dev/null 2>&1 || true   # solo la API de pruebas: no tumba la web si está corriendo
  docker compose rm -f qhub-api contract-tests >/dev/null 2>&1 || true
fi

API_DIR="${QHUB_API_DIR:-/home/miguelzambrano/projects/Qhub/qhub-api}"
if [[ -d "$API_DIR/tests" ]]; then
  step "API: ownership de turnos (ENFORCE_TURN_OWNERSHIP)"
  docker run --rm -v "$API_DIR:/app" -w /app qhub_app/qhub-api python -m tests.test_turn_ownership
fi

if [[ -f .env ]]; then
  step "Seguridad de la base (RLS) — transacción que se deshace"
  python3 -I tool/supabase_sql.py supabase/tests/rls_test.sql || true
fi

if [[ "${1:-}" == "--web-image" ]]; then
  step "Imágenes de producción (web y móvil)"
  docker compose build web mobile
fi

printf '\n\033[32m✔ Verificación completa\033[0m\n'
