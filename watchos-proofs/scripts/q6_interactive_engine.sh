#!/usr/bin/env bash
# Q6 — EXPERIMENT: interactive loop in a watchOS process.
# Injects a tap via FlutterEngineSendPointerEvent, triggers setState in Dart,
# and verifies that Frame 2 is rendered and presented with updated content.
# Also logs Mach task memory footprint (resident & virtual memory).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${WATCH_UDID:?WATCH_UDID is not set}"
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }

rm -f /tmp/engine_frame1.bin /tmp/engine_frame1.png /tmp/engine_frame2.bin /tmp/engine_frame2.png
xcrun simctl spawn "$UDID" /tmp/engine/engine_host /tmp/engine/watchos/FlutterEmbedder \
  /tmp/engine/assets/flutter_assets /tmp/engine/icudtl.dat /tmp/engine_frame1.bin 198 242 60 /tmp/engine_frame2.bin > /tmp/engine/interactive.out 2>&1 &
PID=$!
for _ in $(seq 1 90); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; HOST_RC=$?
cat /tmp/engine/interactive.out | tail -n 40
grep -E "FlutterEngineRun|frames presented|injected tap|memory|wrote initial|wrote post-tap|NO FRAME|NO INITIAL|NO POST-TAP|DLOPEN FAIL|CRASH signal" /tmp/engine/interactive.out | while read -r l; do rl "Q6: host: $l"; done

if [ ! -f /tmp/engine_frame2.bin ]; then
  awk '/^CRASH signal/{p=1} p' /tmp/engine/interactive.out | head -n 40 | while read -r l; do rl "Q6: crash: $l"; done
  echo "FAIL: Frame 2 was not produced after tap injection (host exit code $HOST_RC)"
  exit 1
fi

if cmp -s /tmp/engine_frame1.bin /tmp/engine_frame2.bin; then
  echo "FAIL: Frame 1 and Frame 2 are byte-identical; tap did not change pixels"
  exit 1
fi
rl "Q6: Frame 1 and Frame 2 differ (tap changed rendered pixels)"

python3 -m venv /tmp/pyenv >/dev/null 2>&1; /tmp/pyenv/bin/pip install --quiet pillow >/dev/null 2>&1
/tmp/pyenv/bin/python "$ROOT/scripts/frame_check.py" /tmp/engine_frame2.bin /tmp/engine_frame2.png --frame2
RC=$?
[ "$RC" -eq 0 ] && echo "PASS: Interactive loop verified on watchOS: tap -> setState -> frame 2 rendered; memory logged"
exit "$RC"
