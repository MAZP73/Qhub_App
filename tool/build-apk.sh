#!/usr/bin/env bash
# Compila el APK de Android en Docker (gratis, sin cuenta de Expo) y lo deja en ./apk/qhub.apk (teléfonos, arm64).
#   tool/build-apk.sh emulador   → ./apk/qhub-emulador.apk (x86_64, para el emulador de Android del PC; ver tool/emulator.sh)
# Tarda bastante la primera vez (descarga el SDK de Android y compila); las siguientes usan la caché de Docker.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
ARCHS=arm64-v8a; OUT=qhub.apk
if [[ "${1:-}" == "emulador" ]]; then ARCHS=x86_64; OUT=qhub-emulador.apk; fi
mkdir -p apk
docker build --network host -f docker/Dockerfile.apk --target apk --build-arg ARCHS=$ARCHS --output type=local,dest=./apk/.tmp-$ARCHS \
  --build-arg EXPO_PUBLIC_APP_ENV="$APP_ENV" \
  --build-arg EXPO_PUBLIC_SUPABASE_URL="$SUPABASE_URL" \
  --build-arg EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" .
mv "apk/.tmp-$ARCHS/qhub.apk" "apk/$OUT" && rmdir "apk/.tmp-$ARCHS"
ls -lh "apk/$OUT"
