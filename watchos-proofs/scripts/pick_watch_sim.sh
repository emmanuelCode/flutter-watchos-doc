#!/usr/bin/env bash
# P1 — a watchOS Simulator exists on this runner and can boot. Picks the newest watchOS runtime.
set -euo pipefail

find_watch() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
best = None
for runtime, devs in json.load(sys.stdin)["devices"].items():
    m = re.search(r"watchOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        if "Apple Watch" in d["name"] and (best is None or ver > best[0]):
            best = (ver, d["udid"], d["name"], runtime.split(".")[-1])
if best:
    print(best[1] + "|" + best[2] + "|" + best[3])
else:
    sys.exit(1)'
}

FOUND=$(find_watch || true)
if [ -z "$FOUND" ]; then
  echo "No watch simulator yet - trying to download the watchOS platform..."
  xcodebuild -downloadPlatform watchOS || true
  FOUND=$(find_watch || true)
fi
[ -n "$FOUND" ] || { echo "FAIL: no Apple Watch simulator available"; xcrun simctl list runtimes; exit 1; }

IFS='|' read -r UDID NAME RUNTIME <<< "$FOUND"
echo "INFO: watch simulator $NAME ($RUNTIME) $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
echo "WATCH_UDID=$UDID" >> "${GITHUB_ENV:-/dev/null}"
echo "PASS: watchOS Simulator booted"
