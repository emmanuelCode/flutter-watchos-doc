#!/usr/bin/env python3
"""Extracts the spec's REAL code blocks so the proofs test exactly what the spec says.
Usage: extract_spec_code.py <spec.md> [swift|dart]
Fails loudly (exit 1) if any source file or expected block cannot be found."""
import os, sys

arg = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else None
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
repo_root = os.path.abspath(os.path.join(root, ".."))
appendix_path = os.path.join(repo_root, "docs", "display-list-research.md")

# (source_key, language, marker that identifies the block, destination under watchos-proofs/)
TARGETS = [
    ("appendix", "swift", "init(argb: UInt32)", "swift_spec/Sources/SpecCode/ColorARGB.swift"),
    ("main", "swift", "final class WatchFrameStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchFrame.swift"),
    ("appendix", "swift", "final class WatchRenderStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchRender.swift"),
    ("main", "dart", "class WatchFrameStreamer {", "flutter_proofs/lib/spec/watch_frame_streamer.dart"),
    ("main", "dart", "class WatchInputInjector {", "flutter_proofs/lib/spec/watch_input_injector.dart"),
]

def parse_blocks(md_path):
    if not os.path.isfile(md_path):
        print(f"FAIL: spec file not found at {md_path}")
        sys.exit(1)
    blocks, lang, buf = [], None, []
    for line in open(md_path, encoding="utf-8").read().split("\n"):
        if line.startswith("```"):
            if lang is None:
                lang, buf = (line[3:].strip() or "text"), []
            else:
                blocks.append((lang, "\n".join(buf) + "\n"))
                lang = None
        elif lang is not None:
            buf.append(line)
    return blocks

sources = {"main": parse_blocks(arg)}
if any(src == "appendix" and (not only or lang_ == only) for src, lang_, _, _ in TARGETS):
    sources["appendix"] = parse_blocks(appendix_path)

ok = True
for src_key, lang_, marker, dest in TARGETS:
    if only and lang_ != only:
        continue
    src_file = arg if src_key == "main" else appendix_path
    code = next((c for l, c in sources[src_key] if l == lang_ and marker in c), None)
    if code is None:
        print(f"FAIL: no ```{lang_} block containing '{marker}' in {src_file}")
        ok = False
        continue
    path = os.path.normpath(os.path.join(root, dest))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("// GENERATED from the spec by scripts/extract_spec_code.py - do not edit, do not commit.\n" + code)
    print(f"INFO: extracted {dest} ({code.count(chr(10))} lines)")
sys.exit(0 if ok else 1)
