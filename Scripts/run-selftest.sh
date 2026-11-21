#!/bin/bash
# Kører en selvtest, der skal startes som en rigtig app (for Tilgængelighed-tilladelsen), med tidsgrænse.
#
#   ./Scripts/run-selftest.sh <sekunder> --inplace-selftest
#   ./Scripts/run-selftest.sh 20 --ax-bounds com.apple.Safari
#
# Bygger først; fejler bygningen, køres intet (så en gammel udgave aldrig startes og bliver hængende).
set -uo pipefail
cd "$(dirname "$0")/.."
limit="$1"; shift
if ! ./Scripts/build-app.sh > /tmp/baymow-selftest-build.log 2>&1; then
  echo "Bygningen fejlede – selvtesten er ikke kørt:"; grep -E "error:" /tmp/baymow-selftest-build.log | head -5; exit 1
fi
( sleep "$limit"; pkill -f "$PWD/build/Baymow.app/Contents/MacOS/Baymow" ) & killer=$!
open -n -W build/Baymow.app --args "$@"
kill "$killer" 2>/dev/null
exit 0
