#!/usr/bin/env bash
# Q0 — what does a hosted runner actually give us? (Context for why a full engine build is not attempted here.)
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }
rl "Q0: cpu cores: $(sysctl -n hw.ncpu), memory: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB, arch: $(uname -m)"
FREE=$(df -k /Users 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
rl "Q0: free disk on the runner volume: ${FREE:-?} GB"
rl "Q0: hosted job time limit is 6 h; this job is capped at 60 min. A from-source Flutter engine build (gclient sync + ninja) is expected to need far more than that: not attempted here"
exit 0
