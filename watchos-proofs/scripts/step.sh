#!/usr/bin/env bash
# Usage: step.sh [--sim | --needs ID1,ID2] <ID> <command...>
# Runs the command, saves its log, and appends structured lines to /tmp/proof_results.txt:
#   RESULT|<ID>|PASS|FAIL|BLOCKED[|blocker]     INFO|<ID>|<measurement>     EVID|<ID>|<error line>
# The exit code is the command's, so the GitHub step still goes red on failure.
# --sim          = --needs P1,P0 (needs the watch simulator and a compiling swift_proofs package)
# --needs a,b    = BLOCKED if any listed step FAILED or was itself BLOCKED
RESULTS=/tmp/proof_results.txt
NEEDS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sim)   NEEDS="P1,P0"; shift ;;
    --needs) NEEDS="$2"; shift 2 ;;
    *) break ;;
  esac
done
ID="$1"; shift
mkdir -p /tmp/proof_logs
LOG="/tmp/proof_logs/$ID.log"

if [ -n "$NEEDS" ]; then
  BLOCKER=""
  for dep in ${NEEDS//,/ }; do
    if grep -qE "^RESULT\|$dep\|(FAIL|BLOCKED)" "$RESULTS" 2>/dev/null; then BLOCKER="$dep"; break; fi
  done
  if [ -n "$BLOCKER" ]; then
    echo "RESULT|$ID|BLOCKED|$BLOCKER" >> "$RESULTS"
    echo "BLOCKED: $BLOCKER did not pass, so $ID cannot run"
    exit 1
  fi
fi

"$@" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}

if [ "$CODE" -eq 0 ]; then STATUS=PASS; else STATUS=FAIL; fi
echo "RESULT|$ID|$STATUS" >> "$RESULTS"

# measurements the tests print, e.g. "P2: pixelRatio 1.0 -> 191664 bytes, 85 ms"
grep -oE "(INFO: |[PASEWQ][0-9]+: ).*" "$LOG" | head -n 10 | cut -c1-200 | sed "s/^/INFO|$ID|/" >> "$RESULTS"

if [ "$STATUS" = "FAIL" ]; then
  # Flutter prints the real reason in an "EXCEPTION CAUGHT" block (Expected/Actual/Which/stack)
  EXC=$(awk '/EXCEPTION CAUGHT/{f=1} f{print; if(++n>=30) exit}' "$LOG" | cut -c1-240)
  EV=$(grep -E "error:|Error:|FAIL|failed|XCTAssert|Exception|Testing failed|Unable to|TEST FAILED|No such|not found" "$LOG" | head -n 20 | cut -c1-240)
  [ -n "$EXC$EV" ] || EV=$(tail -n 20 "$LOG" | cut -c1-240)
  DG=$(grep "DIAG:" "$LOG" | head -n 40 | cut -c1-240)
  { [ -n "$EXC" ] && printf '%s\n' "$EXC"; [ -n "$EV" ] && printf '%s\n' "$EV"; [ -n "$DG" ] && printf '%s\n' "$DG"; } | sed "s/^/EVID|$ID|/" >> "$RESULTS"
fi
exit "$CODE"
