# Changelog

Short summary of major milestones. Full version history (`v1.0`–`v9.1` and detailed audit logs) is preserved untouched in [docs/history/CHANGELOG-full.md](docs/history/CHANGELOG-full.md).

- **2026-11-14 — Repo hygiene & maintainer summary:** Removed checked-in `packages/watchos_ui` build/cache/lock artifacts and duplicate `q6_engine_pointer.sh`; added CI floating-runner comments and Linux tool-version logging; added [docs/SUMMARY.md](docs/SUMMARY.md); archived the full changelog to [docs/history/CHANGELOG-full.md](docs/history/CHANGELOG-full.md).
- **Nov 2026 — Audit fixes, SDK probes & spec split:** Fixed `engine_gap.py` TBD v5 / Simulator host-kernel parsing; added `--sdk watchos` Clang/Swift header probes (`Q3`) and `fml`/`embedder` compile checks (`Q1`); extracted `docs/display-list-research.md` and `docs/wearables-ui-strategy.md`; added `packages/watchos_ui` v0.1 PoC and `Gate 0a–0d` / `Phase 6` gates.
- **Nov 2026 (v9.0–v9.1) — Modern profiles & catalog sync:** Added 42/46 mm dimensions, Skia CPU deprecation framing, and `Q7` proof-catalog sync on Flutter `3.50.0` / Dart `3.14.0`.
- **Nov 2026 (v8.0–v8.1) — Condensation & scroll signal (`Q7`):** Corrected Mac JIT memory labeling, added compliance principles, and added `Q7` (`signal_kind=scroll` + `FlutterEngineNotifyLowMemoryWarning`).
- **Nov 2026 (v7.0–v7.4) — Path A decision, Simulator E2E & engine smoke test (`Q0–Q6`):** Selected engine rasterization (`Path A`) over display-list `Path B`, verified Simulator `ws://` E2E (`E1`), and ran retagged `embedder.h` Simulator smoke tests (`Q4–Q6`).
- **Nov 2026 (v6.0) — Engine dependency correction:** Moved production onto `embedder.h` and dev capture onto `RepaintBoundary.toImage` + `GestureBinding`.
- **May 2026 (v1.0–v5.0) — Initial architecture & archived display-list sketches:** Initial spec, `watchos_ui` concept, and early Dart FFI / triple-buffer / wire-protocol prototypes.
