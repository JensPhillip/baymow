# Fælles for test-voice.sh og make-listening-pack.sh. Indlæses med `source`.
#
#   piper [stemmemappe]   Piper-model; standard er Vendor/piper-da-test
#   apple <Navn>          en af macOS' stemmer, fx "Sara" (se `say -v '?'`)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
APP="$PWD/build/Baymow.app/Contents/MacOS/Baymow"

usage() { echo "Brug: $(basename "$0") piper [stemmemappe] | apple <Navn>" >&2; exit 2; }

KIND="${1:-}"; ARG="${2:-}"
case "$ARG" in --*) ARG="" ;; esac  # et tilvalg er ikke et stemmenavn
case "$KIND" in
  piper) VOICE_DIR="${ARG:-$PWD/Vendor/piper-da-test}"; NAME="piper-$(basename "$VOICE_DIR" | sed "s/^piper-//; s/^da-test$/talesyntese/")"
         [ -f "$VOICE_DIR/tokens.txt" ] || { echo "Ingen Piper-model i $VOICE_DIR (kør Scripts/fetch-vendor.sh)" >&2; exit 1; } ;;
  apple) [ -n "$ARG" ] || usage; NAME="apple-$(echo "$ARG" | tr -d '()' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
         voices="$(say -v '?')"; grep -q "^$ARG " <<< "$voices" || { echo "macOS har ingen stemme, der hedder '$ARG'" >&2; exit 1; } ;;
  *) usage ;;
esac

./Scripts/build-app.sh >/dev/null

# say_to_wav <tekstfil> <ud.wav>: Apple-stemme på tekst, der er forberedt af appen – som i appen.
say_to_wav() {
  local prepared; prepared="$(mktemp)"
  if [ "${NO_OVERRIDES:-}" = 1 ]; then "$APP" --normalize < "$1" > "$prepared"; else "$APP" --prepare apple < "$1" > "$prepared"; fi
  say -v "$ARG" -f "$prepared" -o "${2%.wav}.aiff"
  afconvert -f WAVE -d LEI16 "${2%.wav}.aiff" "$2"
  rm -f "${2%.wav}.aiff" "$prepared"
}
