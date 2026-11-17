#!/bin/bash
# Opretter Python-miljøet til stemmetesten i tools/stemmetest/env (ligger ikke i git).
# Første kørsel af testen henter desuden talegenkendelsesmodellen (ca. 1,6 GB) til ~/.cache/huggingface.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x env/bin/python ]; then
  python3 -m venv env
  env/bin/pip -q install --upgrade pip
  env/bin/pip -q install -r requirements.txt
fi
echo "Miljøet er klar: $(pwd)/env"
