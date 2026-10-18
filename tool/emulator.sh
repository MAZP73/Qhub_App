#!/usr/bin/env bash
# Prueba la app móvil EN ESTE PC, sin teléfono: levanta un emulador de Android en Docker, instala el APK y lo muestra en el navegador.
#   1) tool/build-apk.sh emulador      (una vez; genera apk/qhub-emulador.apk, versión x86_64)
#   2) tool/emulator.sh                (abre http://localhost:6080)
#   Para apagarlo: docker compose --profile android rm -sf android
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f apk/qhub-emulador.apk ]] || { echo "Falta apk/qhub-emulador.apk: corre primero  tool/build-apk.sh emulador" >&2; exit 1; }
docker compose --profile android up -d android
C=$(docker compose --profile android ps -q android)
echo "Arrancando el emulador (la primera vez tarda unos minutos)…"
until [[ "$(docker exec "$C" adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do sleep 5; done
docker exec "$C" adb install -r /apk/qhub-emulador.apk
docker exec "$C" adb shell monkey -p com.qhub.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
echo "Listo: abre http://localhost:6080 y verás la app Qhub en el emulador."
