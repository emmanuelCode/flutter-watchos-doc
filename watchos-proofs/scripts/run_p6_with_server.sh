#!/usr/bin/env bash
# Starts the Dart WebSocket server, runs the Swift client test, always stops the server.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

dart run "$ROOT/dart_tools/ws_server.dart" > /tmp/ws_server.log 2>&1 &
trap 'pkill -f ws_server.dart 2>/dev/null; true' EXIT

for _ in $(seq 1 60); do
  nc -z 127.0.0.1 8765 && break
  sleep 0.5
done
nc -z 127.0.0.1 8765 || { echo "FAIL: server did not start"; cat /tmp/ws_server.log; exit 1; }

bash "$ROOT/scripts/run_swift_test.sh" P6_WebSocketLoopbackTests
