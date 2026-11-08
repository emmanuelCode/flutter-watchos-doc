#!/usr/bin/env bash
# E0 — everything the end-to-end job needs: a booted watch simulator, the spec code extracted, Flutter deps.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/pick_watch_sim.sh"
python3 "$ROOT/scripts/extract_spec_code.py" "${GITHUB_WORKSPACE:-.}/${SPEC_FILE:-spec.md}"
( cd "$ROOT/flutter_proofs" && flutter pub get )
