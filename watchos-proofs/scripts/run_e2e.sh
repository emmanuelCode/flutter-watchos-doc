#!/usr/bin/env bash
# E1 — the whole dev loop: real Flutter streamer + injector (flutter test plays the Mac-side server)
# <-> watchOS client test in the Simulator. Needs $WATCH_UDID (set by e2e_setup.sh / pick_watch_sim.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_LOG=/tmp/e2e_server.log

echo "== build the Swift package first (so the Flutter side does not wait on a compile) =="
bash "$ROOT/scripts/swift_pkg.sh" build swift_spec SpecCode || { echo "FAIL: swift_spec did not build"; exit 1; }

echo "== start the Flutter side: real WatchFrameStreamer + WatchInputInjector behind a WebSocket =="
( cd "$ROOT/flutter_proofs" && flutter test test/e2e_server_test.dart > "$SERVER_LOG" 2>&1 ) &
FLUTTER_PID=$!
trap 'kill $FLUTTER_PID 2>/dev/null; pkill -f e2e_server_test 2>/dev/null; true' EXIT

for _ in $(seq 1 360); do
  nc -z 127.0.0.1 8767 && break
  sleep 0.5
done
nc -z 127.0.0.1 8767 || { echo "FAIL: the Flutter e2e server did not start"; tail -n 40 "$SERVER_LOG"; exit 1; }

echo "== run the watchOS client test =="
bash "$ROOT/scripts/swift_pkg.sh" test swift_spec SpecCode SpecCodeTests/E1_EndToEndTests
SWIFT_CODE=$?

if [ "$SWIFT_CODE" -ne 0 ]; then
  kill "$FLUTTER_PID" 2>/dev/null
  FLUTTER_CODE=1
else
  wait "$FLUTTER_PID"
  FLUTTER_CODE=$?
fi

echo "== Flutter side output =="
grep -E "E1:|EXCEPTION|Expected|Actual|reason|All tests passed|failed" "$SERVER_LOG" | cut -c1-240 | head -n 30
echo "swift exit=$SWIFT_CODE  flutter exit=$FLUTTER_CODE"
[ "$SWIFT_CODE" -eq 0 ] && [ "$FLUTTER_CODE" -eq 0 ]
