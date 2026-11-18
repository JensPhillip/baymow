#!/bin/bash
# AP-51: stabilitets- og privatlivskørsel.
#
#   tools/stabilitet/soak.sh <minutter> <sekunder mellem oplæsninger> <resultatmappe>
#
# Starter en lydløs langtidskørsel (Baymow --soak-selftest) og overvåger imens både den og den rigtige,
# installerede Baymow for netværksforbindelser hvert minut. Bagefter: tools/stabilitet/check-privacy.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
minutes="${1:-480}"; interval="${2:-300}"; out="${3:?resultatmappe mangler}"
mkdir -p "$out"
APP=build/Baymow.app/Contents/MacOS/Baymow
[ -x "$APP" ] || ./Scripts/build-app.sh >/dev/null

"$APP" --soak-selftest "$minutes" "$interval" "$out" > "$out/soak-output.txt" 2>&1 &
soak=$!
echo "start $(date '+%F %T') · kørsel pid $soak" > "$out/network.txt"
while kill -0 "$soak" 2>/dev/null; do
  real=$(pgrep -f "/Applications/Baymow.app/Contents/MacOS/Baymow" | head -1)
  for pid in $soak $real; do
    # Kun internetforbindelser (TCP/UDP), ikke lokale Unix-sokler.
    lines=$(lsof -nP -a -p "$pid" -i 2>/dev/null | tail -n +2)
    [ -n "$lines" ] && { echo "$(date '+%F %T') pid $pid:"; echo "$lines"; } >> "$out/network.txt"
  done
  sleep 60
done
wait "$soak"; status=$?
echo "slut $(date '+%F %T') · kørslens afslutningskode $status" >> "$out/network.txt"
exit $status
