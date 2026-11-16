#!/bin/bash
# Kør dette, før du afleverer en arbejdspakke. Alt skal være grønt.
#
#   1. Bygger og kører alle tests (herunder kernekontrakten).
#   2. Privatliv: ingen udskrift eller logning i app-koden, ingen filskrivning i kernen.
#   3. Netværk: kun filer på Scripts/network-allowlist.txt må bruge netværk.
#   4. Kerne: ændringer i kernen kræver en begrundelse i docs/KERNEAENDRINGER.md.
#
# Reglerne står i docs/PROJEKTPLAN.md afsnit 3.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

failed=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FEJL  $1"; failed=1; }

echo "1. Byg og test"
if swift build 2>&1 | tail -1 | grep -q "Build complete"; then ok "swift build"; else fail "swift build"; fi
test_output=$(swift test 2>&1)
if echo "$test_output" | grep -q "with 0 failures"; then
  ok "swift test ($(echo "$test_output" | grep -oE 'Executed [0-9]+ tests' | sort -t' ' -k2 -n | tail -1))"
else
  fail "swift test"; echo "$test_output" | grep -E "error:|failed" | head -20
fi

echo "2. Privatliv"
# Værktøjerne i Tools/ kører kun fra kommandolinjen og må skrive ud. Resten af appen må ikke.
hits=$(grep -rnE '(^|[^A-Za-z_.])(print|debugPrint|dump|NSLog|os_log)\(|Logger\(' \
  Sources/BaymowKit/Core Sources/BaymowKit/Engines Sources/BaymowKit/UI Sources/Baymow || true)
if [ -z "$hits" ]; then ok "ingen udskrift eller logning uden for DiagnosticsService"; else fail "udskrift/logning i app-koden:"; echo "$hits"; fi

hits=$(grep -rnE '\.write\(to|FileHandle\(forWriting|createFile\(' Sources/BaymowKit/Core \
  | grep -v 'Core/DiagnosticsService.swift' || true)
if [ -z "$hits" ]; then ok "kernen skriver kun til disk i DiagnosticsService"; else fail "filskrivning i kernen:"; echo "$hits"; fi

echo "3. Netværk"
allow=$(grep -v '^#' Scripts/network-allowlist.txt | grep -v '^$' || true)
hits=$(grep -rlE 'URLSession|URLRequest|NWConnection|NWPathMonitor|CFNetwork|WKWebView|URLProtocol' Sources || true)
bad=""
for file in $hits; do echo "$allow" | grep -qx "$file" || bad="$bad $file"; done
if [ -z "$bad" ]; then ok "netværk bruges kun i godkendte filer"; else fail "netværk i filer, der ikke står på Scripts/network-allowlist.txt:$bad"; fi

echo "4. Kerne"
if git rev-parse --git-dir >/dev/null 2>&1; then
  base=$(git merge-base HEAD "${BASE:-main}" 2>/dev/null || git rev-parse HEAD)
  changed=$( (git diff --name-only "$base"; git ls-files --others --exclude-standard) | sort -u)
  core=$(echo "$changed" | grep -E '^(Sources/BaymowKit/Core/|Tests/BaymowKitTests/CoreContractTests\.swift)' || true)
  if [ -z "$core" ]; then
    ok "kernen er uændret"
  elif echo "$changed" | grep -qx 'docs/KERNEAENDRINGER.md'; then
    ok "kernen er ændret, og ændringen er begrundet i docs/KERNEAENDRINGER.md"
  else
    fail "kernen er ændret uden begrundelse. Tilføj et afsnit i docs/KERNEAENDRINGER.md. Ændrede kernefiler:"; echo "$core"
  fi
else
  ok "ikke et git-arkiv – kernekontrol sprunget over"
fi

echo
if [ "$failed" = 0 ]; then echo "ALT GRØNT"; else echo "IKKE KLAR TIL AFLEVERING"; fi
exit $failed
