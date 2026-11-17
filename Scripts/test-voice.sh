#!/bin/bash
# Stemmetest: lader en stemme læse testsætningerne og kontrollerer dem med talegenkendelse.
#
#   ./Scripts/test-voice.sh piper
#   ./Scripts/test-voice.sh apple Sara
#
# Tilvalg efter stemmen:
#   --set engelsk     sætningerne med engelske ord (tools/stemmetest/sentences_engelsk.py) i stedet for de 36 danske
#   --no-overrides    uden motorens udtaleliste (til før/efter-måling)
#   --gate            afslut med fejl, hvis stemmeportens krav 1 ikke er opfyldt
source "$(dirname "$0")/voice-common.sh"

set_name="dansk"; gate=""; extra=""; suffix=""
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --set) set_name="${args[$((i + 1))]}" ;;
    --gate) gate="--gate" ;;
    --no-overrides) export NO_OVERRIDES=1; extra="--no-overrides"; suffix="-uden-udtaleliste" ;;
  esac
done
module="sentences"; [ "$set_name" = "dansk" ] || module="sentences_$set_name"

work="$(mktemp -d)"
python3 -c "
import sys, importlib; sys.path.insert(0, 'tools/stemmetest')
S = importlib.import_module('$module').SENTENCES
open('$work/sentences.txt', 'w').write('\\n'.join(w for _, w, _ in S) + '\\n')"

if [ "$KIND" = piper ]; then
  "$APP" --synthesize "$VOICE_DIR" "$work/sentences.txt" "$work/wav" $extra
else
  mkdir -p "$work/wav"; index=0
  while IFS= read -r line; do
    printf '%s\n' "$line" > "$work/line.txt"
    say_to_wav "$work/line.txt" "$work/wav/$(printf '%02d' "$index").wav"
    index=$((index + 1))
  done < "$work/sentences.txt"
fi

name="$NAME"; [ "$set_name" = "dansk" ] || name="$NAME-$set_name"
./tools/stemmetest/run.sh "$name$suffix" "$work/wav" --set "$set_name" $gate
