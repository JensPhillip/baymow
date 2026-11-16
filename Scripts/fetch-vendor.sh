#!/bin/bash
# Henter de færdigbyggede biblioteker og testmodellen, som ikke ligger i git (ca. 90 MB).
# Kontrollerer SHA-256, før noget pakkes ud.
set -euo pipefail
cd "$(dirname "$0")/.."

fetch() { # url sha256 -> sti til den hentede fil
  local url="$1" sha="$2" file
  file="$(mktemp -d)/$(basename "$url")"
  curl -sfL -o "$file" "$url"
  if [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
    echo "Kontrolsummen passer ikke for $url" >&2; exit 1
  fi
  echo "$file"
}

if [ ! -f Vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.a ]; then
  archive=$(fetch https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-static-lib.tar.bz2 \
    9091bf160dc7fdacedbc906b212badf53c2993f4e5277a0e03998e96c31d60da)
  mkdir -p Vendor/sherpa-onnx/lib
  tar -xjf "$archive" -C Vendor/sherpa-onnx/lib --strip-components 2
  echo "Hentet: Vendor/sherpa-onnx/lib"
fi

if [ ! -f Vendor/piper-da-test/tokens.txt ]; then
  archive=$(fetch https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-da_DK-talesyntese-medium.tar.bz2 \
    f2e2cbcdb2b21e76f93635b35105d07b37997ace434d7289d04b689a97c19bd0)
  mkdir -p Vendor/piper-da-test
  tar -xjf "$archive" -C Vendor/piper-da-test --strip-components 1
  echo "Hentet: Vendor/piper-da-test"
fi
echo "Vendor er klar."
