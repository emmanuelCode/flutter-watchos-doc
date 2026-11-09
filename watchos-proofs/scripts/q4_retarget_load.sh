#!/usr/bin/env bash
# Q4 — EXPERIMENT: retag the official desktop embedder library as a watchOS Simulator binary, stub the libraries
# watchOS lacks, and see whether a watchOS process can load it and find the embedder API.
# (A retagged macOS binary is NOT a shippable port; this only shows how far the real engine code gets.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${WATCH_UDID:?WATCH_UDID is not set}"
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }

OUT=/tmp/engine/watchos
rm -rf "$OUT"; mkdir -p "$OUT"
SDKVER=$(xcrun --sdk watchsimulator --show-sdk-version)
for plat in watchossim 9; do
  if xcrun vtool -set-build-version "$plat" 10.0 "$SDKVER" -replace -output "$OUT/FlutterEmbedder" /tmp/engine/macos/FlutterEmbedder 2>/tmp/vtool.err; then
    rl "Q4: retagged as watchOS Simulator (vtool platform '$plat', minos 10.0, sdk $SDKVER)"; break
  fi
done
[ -f "$OUT/FlutterEmbedder" ] || { echo "FAIL: vtool could not retag:"; cat /tmp/vtool.err; exit 1; }
codesign --force -s - "$OUT/FlutterEmbedder" 2>&1 | tail -n 2

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 "$ROOT/engine_probe/engine_dlopen.c" -o /tmp/engine/engine_dlopen || { echo "FAIL: cannot compile the loader for watchOS"; exit 1; }

try_load() { xcrun simctl spawn "$UDID" /tmp/engine/engine_dlopen "$OUT/FlutterEmbedder" 2>&1 | tee /tmp/engine/load.out; return "${PIPESTATUS[0]}"; }

echo "== attempt 1: load the retagged library as-is =="
if try_load; then rl "Q4: attempt 1 loaded as-is"; RC=0
else
  rl "Q4: attempt 1 failed: $(grep -m1 -E 'DLOPEN FAIL' /tmp/engine/load.out | cut -c1-300)"
  echo "== attempt 2: stub the libraries watchOS does not have =="
  python3 "$ROOT/scripts/make_stubs.py" "$OUT/FlutterEmbedder" "$OUT/stubs" || { echo "FAIL: stubbing failed"; exit 1; }
  if try_load; then rl "Q4: attempt 2 loaded after stubbing"; RC=0
  else RC=1; rl "Q4: attempt 2 failed: $(grep -m1 -E 'DLOPEN FAIL' /tmp/engine/load.out | cut -c1-400)"; fi
fi
grep -E "SYMBOL" /tmp/engine/load.out | while read -r l; do rl "Q4: $l"; done
[ "$RC" -eq 0 ] && echo "PASS: a watchOS process loaded the engine library and found the embedder API"
exit "$RC"
