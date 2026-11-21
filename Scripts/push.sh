#!/bin/bash
# Sender main til GitHub – men kun når alt er committet, og ./Scripts/check.sh er grøn.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
  echo "Ikke sendt: der er ændringer, som ikke er committet."; git status --short | head; exit 1
fi
if ! ./Scripts/check.sh > /tmp/baymow-push-check.log 2>&1; then
  echo "Ikke sendt: check.sh er ikke grøn:"; grep -E "FEJL" /tmp/baymow-push-check.log; exit 1
fi
git push
