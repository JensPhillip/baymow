#!/bin/bash
# Lyttepakke: lader en stemme læse de tre faste tekster i tools/lytteprove/tekster/ og lægger
# lydfilerne i stemmeproever/<navn>/. Brugeren bedømmer dem i docs/LYTTESKEMA.md.
#
#   ./Scripts/make-listening-pack.sh piper
#   ./Scripts/make-listening-pack.sh apple Sara
source "$(dirname "$0")/voice-common.sh"

out="stemmeproever/$NAME"; mkdir -p "$out"
for text in tools/lytteprove/tekster/*.txt; do
  target="$out/$(basename "${text%.txt}").wav"
  if [ "$KIND" = piper ]; then
    "$APP" --synthesize-text "$VOICE_DIR" "$text" "$PWD/$target" >/dev/null
  else
    say_to_wav "$text" "$target"
  fi
  echo "Skrevet: $target"
done
