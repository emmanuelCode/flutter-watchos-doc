#!/usr/bin/env python3
"""Merges the per-job result files into ONE paste-ready block (printed + job summary)."""
import glob, os, sys

TITLES = {
    "F0": "Flutter dependencies resolve",
    "P1": "A watchOS Simulator exists and boots",
    "P0": "Swift code compiles for watchOS",
    "P2": "Flutter captures a frame headless (toImage -> RGBA, sizes match)",
    "P3": "Injected tap changes the next frame",
    "P4": "RGBA bytes -> CGImage with correct pixels",
    "P5": "SwiftUI Canvas draws the frame (pixels checked)",
    "P6": "Dart WebSocket server <-> watchOS client (frame down, tap up)",
    "A1": "[App.A] Canvas text .topLeading vs .center",
    "A2": "[App.A] Triple-buffer mailbox",
    "A3": "[App.A] Dart-written bytes parse correctly in Swift",
    "A4": "[App.A] @_cdecl symbol found by dlsym",
}
ORDER = ["F0", "P1", "P0", "P2", "P3", "P4", "P5", "P6", "A1", "A2", "A3", "A4"]
EXPECTED_ARTIFACTS = ["results-flutter", "results-swift"]
ICON = {"PASS": "✅", "FAIL": "❌", "BLOCKED": "⛔", "MISSING": "⬜"}

root = sys.argv[1] if len(sys.argv) > 1 else "results"
env, results, info, evid = [], {}, [], {}
missing_jobs = [a for a in EXPECTED_ARTIFACTS if not os.path.isdir(os.path.join(root, a))]

for path in sorted(glob.glob(os.path.join(root, "**", "proof_results.txt"), recursive=True)):
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if "|" not in line:
            continue
        kind, rest = line.split("|", 1)
        if kind == "ENV":
            env.append(rest)
        elif kind == "RESULT":
            parts = rest.split("|")
            results[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else "")
        elif kind in ("INFO", "EVID") and "|" in rest:
            pid, text = rest.split("|", 1)
            (info if kind == "INFO" else evid.setdefault(pid, [])).append((pid, text) if kind == "INFO" else text)

out = []
out.append("=" * 8 + " WATCHOS PROOFS RESULT SHEET " + "=" * 8)
repo, run = os.environ.get("GITHUB_REPOSITORY", "?"), os.environ.get("GITHUB_RUN_ID", "?")
out.append(f"commit {os.environ.get('GITHUB_SHA', '?')[:7]} | run https://github.com/{repo}/actions/runs/{run}")
out.append("")
out.append("ENVIRONMENT")
out += [f"  {e}" for e in env] or ["  (none recorded)"]
out.append("")
out.append("RESULTS")
passed = 0
for pid in ORDER:
    status, extra = results.get(pid, ("MISSING", ""))
    passed += status == "PASS"
    note = {"BLOCKED": f"  <- blocked by {extra}",
            "MISSING": "  <- no result recorded (step skipped, timed out, or job crashed earlier)"}.get(status, "")
    out.append(f"  {ICON[status]} {pid:<3} {TITLES[pid]}{note}")
out.append(f"  => {passed}/{len(ORDER)} passed")
if missing_jobs:
    out.append(f"  !! no result file from: {', '.join(missing_jobs)} (job crashed before reporting - paste its red step instead)")

fails = [pid for pid in ORDER if results.get(pid, ("",))[0] == "FAIL"]
if fails:
    out.append("")
    out.append("FAILURE EVIDENCE")
    for pid in fails:
        out.append(f"  [{pid}] {TITLES[pid]}")
        out += [f"      {l}" for l in evid.get(pid, ["(no evidence captured)"])]

if info:
    out.append("")
    out.append("MEASUREMENTS / INFO")
    out += [f"  [{pid}] {text}" for pid, text in info]
out.append("=" * 8 + " END " + "=" * 8)

text = "\n".join(out)
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as f:
        f.write("### Result sheet - copy the block below\n\n```text\n" + text + "\n```\n")
