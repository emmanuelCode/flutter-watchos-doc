#!/usr/bin/env bash
# Q3 — dependency-gap analysis: what do the OFFICIAL engines import that the watchOS SDK does not provide?
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RC=0
python3 "$ROOT/scripts/engine_gap.py" "desktop embedder" /tmp/engine/macos/FlutterEmbedder || RC=1
if [ -f /tmp/engine/ios_Flutter ]; then python3 "$ROOT/scripts/engine_gap.py" "iOS engine" /tmp/engine/ios_Flutter || RC=1; fi
[ "$RC" -eq 0 ] && echo "PASS: gap analysis complete (the numbers above are the findings, not pass/fail)"
exit "$RC"
