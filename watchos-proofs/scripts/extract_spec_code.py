#!/usr/bin/env python3
"""Extracts the spec's REAL code blocks so the proofs test exactly what the spec says.
Usage: extract_spec_code.py <spec.md> [swift|dart]
Fails (exit 1) if a block cannot be found — the spec changed shape, update TARGETS."""
import os, sys

arg = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else None
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TARGETS = [  # (language, marker that identifies the block, destination under watchos-proofs/)
    ("swift", "init(argb: UInt32)", "swift_spec/Sources/SpecCode/ColorARGB.swift"),
    ("swift", "final class WatchFrameStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchFrame.swift"),
    ("swift", "final class WatchRenderStore: ObservableObject", "swift_spec/Sources/SpecCode/WatchRender.swift"),
    ("dart", "class WatchFrameStreamer {", "flutter_proofs/lib/spec/watch_frame_streamer.dart"),
    ("dart", "class WatchInputInjector {", "flutter_proofs/lib/spec/watch_input_injector.dart"),
]

def resolve_spec(path):
    """Use the given file if it exists; otherwise search the repo for the markdown file that holds the
    most of the spec's code blocks (ties -> the highest file name, so ..._v7 beats ..._v6)."""
    if os.path.isfile(path):
        return path
    base = os.environ.get("GITHUB_WORKSPACE") or os.path.abspath(os.path.join(root, ".."))
    print(f"INFO: spec file not found at {path}; searching {base} ...")
    found, all_md = [], []
    for dp, dns, fns in os.walk(base):
        dns[:] = [d for d in dns if d not in (".git", "node_modules", "results")]
        for fn in fns:
            if not fn.lower().endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            all_md.append(os.path.relpath(p, base))
            try:
                t = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            hits = sum(1 for _, marker, _ in TARGETS if marker in t)
            if hits:
                found.append((hits, p))
    if not found:
        print("FAIL: no markdown file in the repo contains the spec's code blocks.")
        print("      Markdown files the runner can see (is the spec committed and pushed?):")
        for m in sorted(all_md):
            print("       -", m)
        sys.exit(1)
    best = max(h for h, _ in found)
    pick = max(p for h, p in found if h == best)
    others = ", ".join(f"{os.path.relpath(p, base)} ({h}/{len(TARGETS)})" for h, p in sorted(found) if p != pick)
    print(f"INFO: auto-detected spec: {os.path.relpath(pick, base)} ({best}/{len(TARGETS)} code blocks)"
          + (f"; other candidates: {others}" if others else ""))
    return pick

spec = resolve_spec(arg)

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