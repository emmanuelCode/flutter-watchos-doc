#!/usr/bin/env python3
"""Extracts the spec's REAL code blocks so the proofs test exactly what the spec says.
Usage: extract_spec_code.py <spec.md> [swift|dart]
Fails (exit 1) if a block cannot be found — the spec changed shape, update TARGETS."""
import os, sys

spec = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else None
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

blocks, lang, buf = [], None, []
for line in open(spec, encoding="utf-8").read().split("\n"):
    if line.startswith("```"):
        if lang is None:
            lang, buf = (line[3:].strip() or "text"), []
        else:
            blocks.append((lang, "\n".join(buf) + "\n"))
            lang = None
    elif lang is not None:
        buf.append(line)

TARGETS = [  # (language, marker that identifies the block, destination under watchos-proofs/)
    ("swift", "init(argb: UInt32)", "swift_spec/Sources/SpecCode/ColorARGB.swift"),
    ("swift", "final class WatchFrameStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchFrame.swift"),
    ("swift", "final class WatchRenderStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchRender.swift"),
    ("dart", "class WatchFrameStreamer {", "flutter_proofs/lib/spec/watch_frame_streamer.dart"),
    ("dart", "class WatchInputInjector {", "flutter_proofs/lib/spec/watch_input_injector.dart"),
]

ok = True
for lang_, marker, dest in TARGETS:
    if only and lang_ != only:
        continue
    code = next((c for l, c in blocks if l == lang_ and marker in c), None)
    if code is None:
        print(f"FAIL: no ```{lang_} block containing '{marker}' in {spec}")
        ok = False
        continue
    path = os.path.normpath(os.path.join(root, dest))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("// GENERATED from the spec by scripts/extract_spec_code.py - do not edit, do not commit.\n" + code)
    print(f"INFO: extracted {dest} ({code.count(chr(10))} lines)")
sys.exit(0 if ok else 1)
