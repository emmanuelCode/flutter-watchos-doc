#!/usr/bin/env bash
# Usage: step.sh [--sim] <ID> <command...>
# Runs the command, saves its log, and appends a structured line to /tmp/proof_results.txt:
#   RESULT|<ID>|PASS|FAIL|BLOCKED[|blocker]     INFO|<ID>|<measurement>     EVID|<ID>|<error line>
# The exit code is the command's, so the GitHub step still goes red on failure.
# --sim: this step needs the watch simulator, so it is BLOCKED if P1 or P0 already failed.
RESULTS=/tmp/proof_results.txt
SIM=0
if [ "${1:-}" = "--sim" ]; then SIM=1; shift; fi
ID="$1"; shift
mkdir -p /tmp/proof_logs
LOG="/tmp/proof_logs/$ID.log"

if [ "$SIM" -eq 1 ]; then
  BLOCKER=""
  if grep -q "^RESULT|P1|FAIL" "$RESULTS" 2>/dev/null; then BLOCKER="P1"
  elif grep -q "^RESULT|P0|FAIL" "$RESULTS" 2>/dev/null; then BLOCKER="P0"; fi
  if [ -n "$BLOCKER" ]; then
    echo "RESULT|$ID|BLOCKED|$BLOCKER" >> "$RESULTS"
    echo "BLOCKED: $BLOCKER failed, so $ID cannot run"
    exit 1
  fi
fi

"$@" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}

if [ "$CODE" -eq 0 ]; then STATUS=PASS; else STATUS=FAIL; fi
echo "RESULT|$ID|$STATUS" >> "$RESULTS"

# measurements the tests print, e.g. "P2: pixelRatio 1.0 -> 191664 bytes, 85 ms"
grep -oE "(INFO: |P[0-9]+: |A[0-9]+: ).*" "$LOG" | head -n 10 | cut -c1-200 | sed "s/^/INFO|$ID|/" >> "$RESULTS"

if [ "$STATUS" = "FAIL" ]; then
  EV=$(grep -E "error:|Error:|FAIL|failed|XCTAssert|Exception|Testing failed|Unable to|TEST FAILED|No such|not found" "$LOG" | head -n 20 | cut -c1-240)
  [ -n "$EV" ] || EV=$(tail -n 20 "$LOG" | cut -c1-240)
  printf '%s\n' "$EV" | sed "s/^/EVID|$ID|/" >> "$RESULTS"
fi
exit "$CODE"
