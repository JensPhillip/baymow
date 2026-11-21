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
# Licensen følger med appen (GPL-3.0 kræver det), sammen med oversigten over de dele, Baymow bygger på.
mkdir -p "$APP/Contents/Resources"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp docs/LICENSER.md "$APP/Contents/Resources/LICENSER.md"

# Developer ID (til udgivelse) foretrækkes frem for Apple Development (kun til egen Mac).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
[ -n "$IDENTITY" ] || IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  # Hardened runtime (--options runtime) altid. Tidsstempel kræves af Apples notarisering, men kræver internet,
  # så det bruges kun med et Developer ID-certifikat (udgivelse) – ikke ved almindelige builds.
  timestamp="--timestamp=none"; [[ "$IDENTITY" == Developer\ ID\ Application* ]] && timestamp="--timestamp"
  codesign --force --options runtime "$timestamp" --sign "$IDENTITY" "$APP"
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
  # Lige efter at den gamle proces er stoppet, kan macOS afvise at åbne appen. Prøv et par gange.
  for attempt in 1 2 3 4 5; do
    sleep 1
    if open /Applications/Baymow.app 2>/dev/null; then break; fi
  done
  echo "Installeret: /Applications/Baymow.app"
fi
