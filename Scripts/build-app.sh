#!/bin/bash
# Bygger Baymow.app i build/ og signerer den.
#
# Signeringen bruger et lokalt Apple Development-certifikat, hvis der findes et. En stabil
# signatur betyder, at macOS husker Tilgængelighed-tilladelsen på tværs af nye builds.
# Uden certifikat signeres ad hoc, og tilladelsen skal så gives igen efter hvert build.
set -euo pipefail
cd "$(dirname "$0")/.."

# Brug den fulde Xcode, også når xcode-select peger på Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64

APP=build/Baymow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Baymow" "$APP/Contents/MacOS/Baymow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
  echo "Signeret med: ${IDENTITY%% (*}"
else
  codesign --force --sign - "$APP"
  echo "Signeret ad hoc (intet certifikat fundet)"
fi
echo "Bygget: $PWD/$APP"

# --install: læg appen i Programmer og genstart den derfra.
if [ "${1:-}" = "--install" ]; then
  pkill -f 'Baymow.app/Contents/MacOS/Baymow' || true
  rm -rf /Applications/Baymow.app
  ditto "$APP" /Applications/Baymow.app
  open /Applications/Baymow.app
  echo "Installeret: /Applications/Baymow.app"
fi
