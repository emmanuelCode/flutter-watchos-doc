#!/usr/bin/env bash
# Usage: run_with_server.sh <server .dart path relative to watchos-proofs> <port> <Swift test class in swift_proofs>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$1"; PORT="$2"; TESTCLASS="$3"

dart run "$ROOT/$SERVER" > "/tmp/server_$PORT.log" 2>&1 &
trap 'pkill -f "$SERVER" 2>/dev/null; true' EXIT

for _ in $(seq 1 60); do
  nc -z 127.0.0.1 "$PORT" && break
  sleep 0.5
done
nc -z 127.0.0.1 "$PORT" || { echo "FAIL: server on $PORT did not start"; cat "/tmp/server_$PORT.log"; exit 1; }

bash "$ROOT/scripts/run_swift_test.sh" "$TESTCLASS"
