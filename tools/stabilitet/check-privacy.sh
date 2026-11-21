#!/bin/bash
# AP-51: søger efter spor-ordene fra langtidskørslen og ord fra testteksterne i alle Baymows filer.
#
#   tools/stabilitet/check-privacy.sh [resultatmappe fra soak.sh]
set -uo pipefail
words=(zebrafinkeflokken kartoffelsalatsfestivalen Hvedebrødsdagenes solsikkemarken
       Ordblindhed Kommunen bibliotek Fotosyntese værkstedet)
places=("$HOME/Library/Application Support/Baymow" "$HOME/Library/Logs/Baymow")
for id in dk.jpmag.baymow dk.baymow.app; do  # nuværende og tidligere app-id
  places+=("$HOME/Library/Caches/$id" "$HOME/Library/Preferences/$id.plist" "$HOME/Library/Saved Application State/$id.savedState")
done
[ -n "${1:-}" ] && places+=("$1/log")
found=0
for place in "${places[@]}"; do
  [ -e "$place" ] || continue
  for word in "${words[@]}"; do
    # -a: også binære filer (fx stemmemodeller); -I ville springe dem over.
    hits=$(grep -rail -- "$word" "$place" 2>/dev/null | grep -v "/Voices/" || true)
    if [ -n "$hits" ]; then echo "FUNDET \"$word\" i:"; echo "$hits"; found=1; fi
  done
done
[ "$found" = 0 ] && echo "Rent: ingen af ordene findes i Baymows filer." || echo "IKKE RENT"
exit $found
