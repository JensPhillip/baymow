#!/bin/bash
# Brug: run.sh <navn> <mappe med 00.wav, 01.wav …> [--gate]
# Lytter optagelserne igennem med talegenkendelse og sammenligner med det, der skulle siges.
# Kræver en bygget app (build/Baymow.app), fordi appens egen tekstforberedelse bruges til sammenligningen.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/setup.sh" >/dev/null
exec "$here/env/bin/python" "$here/evaluate.py" "$@"
