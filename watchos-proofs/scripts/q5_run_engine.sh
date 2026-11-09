#!/usr/bin/env bash
# Q5 — EXPERIMENT: run Flutter itself inside a watchOS process through embedder.h with the software renderer,
# using a host written from scratch (engine_probe/engine_host.c), and check the rendered pixels.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${WATCH_UDID:?WATCH_UDID is not set}"
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 -I /tmp/engine \
  "$ROOT/engine_probe/engine_host.c" -framework CoreFoundation -o /tmp/engine/engine_host \
  || { echo "FAIL: the embedder host does not compile against embedder.h for watchOS"; exit 1; }
rl "Q5: host compiled for watchOS Simulator against the real embedder.h"

# Diagnostic: does this engine library contain the built-in Dart VM snapshots (a JIT/debug engine does)?
SNAPSYMS=$(nm -gU -arch arm64 /tmp/engine/macos/FlutterEmbedder 2>/dev/null | grep -i "kDart.*Snapshot" | awk '{print $NF}' | tr '\n' ' ')
rl "Q5: snapshot symbols exported by the engine library: ${SNAPSYMS:-none}"
rm -f /tmp/engine_frame.bin /tmp/engine_frame.png
xcrun simctl spawn "$UDID" /tmp/engine/engine_host /tmp/engine/watchos/FlutterEmbedder \
  /tmp/engine/assets/flutter_assets /tmp/engine/icudtl.dat /tmp/engine_frame.bin 198 242 60 > /tmp/engine/host.out 2>&1 &
PID=$!
for _ in $(seq 1 90); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; HOST_RC=$?
cat /tmp/engine/host.out | tail -n 40
grep -E "FlutterEngineRun|frames presented|NO FRAME|DLOPEN FAIL|snapshot symbols visible|VM snapshot|Could not|Segmentation" /tmp/engine/host.out | while read -r l; do rl "Q5: host: $l"; done

if [ ! -f /tmp/engine_frame.bin ]; then
  echo "DIAG: host exit code $HOST_RC; last output lines:"; tail -n 15 /tmp/engine/host.out | sed 's/^/DIAG: /'
  exit 1
fi
python3 -m venv /tmp/pyenv >/dev/null 2>&1; /tmp/pyenv/bin/pip install --quiet pillow >/dev/null 2>&1
/tmp/pyenv/bin/python "$ROOT/scripts/frame_check.py" /tmp/engine_frame.bin /tmp/engine_frame.png
RC=$?
[ "$RC" -eq 0 ] && echo "PASS: Flutter ran inside a watchOS process: Dart executed, text rendered, pixels delivered through embedder.h"
exit "$RC"
