#!/usr/bin/env bash
# Abre la app móvil con Expo: escanea el QR con Expo Go (Android o iPhone) y listo, sin compilar nada.
#   npm start                 → mismo Wi‑Fi que el PC
#   npm run start:tunnel      → si el teléfono no ve el PC (WSL, redes con aislamiento): usa un túnel de Expo
#   npm run android | ios     → abre la app en un emulador/simulador si tienes uno instalado (opcional)
# Lee el .env central de la raíz y reparte lo público como EXPO_PUBLIC_* (las secretas nunca entran a la app).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Falta el .env de la raíz (APP_ENV, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)." >&2; exit 1; }
set -a; . ./.env; set +a
export EXPO_PUBLIC_APP_ENV="${EXPO_PUBLIC_APP_ENV:-${APP_ENV:?falta APP_ENV en .env}}"
export EXPO_PUBLIC_SUPABASE_URL="${EXPO_PUBLIC_SUPABASE_URL:-${SUPABASE_URL:?falta SUPABASE_URL en .env}}"
export EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY="${EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_PUBLISHABLE_KEY:?falta SUPABASE_PUBLISHABLE_KEY en .env}}"
export EXPO_NO_TELEMETRY=1
cd apps/mobile
exec npx expo start "$@"
