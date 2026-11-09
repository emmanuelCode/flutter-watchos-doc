#!/usr/bin/env python3
"""Q4 helper. Makes the retagged macOS embedder library loadable by a watchOS process:
  1. libraries that EXIST on watchOS but at a flat path (macOS says X.framework/Versions/A/X, watchOS has X.framework/X)
     -> rewrite the load command to the flat path;
  2. libraries watchOS does NOT have (AppKit, OpenGL, ...) -> build a stub dylib that defines the symbols the engine
     imports from them (zeroed data; never meant to run) and point the engine at it.
Symbols missing from libraries that DO exist on watchOS cannot be fixed this way and are reported.
Usage: make_stubs.py <engine-binary-to-patch> <stub-dir>"""
import os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import engine_gap as g


def main(binary, outdir):
    os.makedirs(outdir, exist_ok=True)
    syms, installs = g.load_sdk(g.sdk_path("watchsimulator"), "watchos")
    libs = g.linked_libs(binary)
    undef = g.undefined(binary)

    rewritten = 0
    for lib in libs:
        f = g.flat(lib)
        if f != lib and f in installs:
            subprocess.run(["install_name_tool", "-change", lib, f, binary], check=True)
            rewritten += 1
    g.rl(f"Q4: rewrote {rewritten} macOS-style versioned framework paths to the flat watchOS layout")

    missing_libs = [l for l in libs if not l.startswith("@") and g.flat(l) not in installs]
    g.rl("Q4: stubbing libraries the watchOS SDK lacks: " + (", ".join(g.short(l) for l in missing_libs) or "none"))
    for lib in missing_libs:
        name = g.short(lib)
        wanted = sorted({s for s, f in undef if f == name})
        csrc = os.path.join(outdir, f"stub_{name}.c")
        with open(csrc, "w") as f:
            for i, s in enumerate(wanted):
                # the assembler label must come directly after the declarator, attributes after it
                f.write(f'char stub_sym_{i}[256] __asm__("{s}") __attribute__((used, aligned(16)));\n')
            f.write("void stub_anchor(void) {}\n")
        dylib = os.path.join(outdir, f"stub_{name}.dylib")
        newpath = f"@loader_path/{os.path.basename(outdir)}/stub_{name}.dylib"
        subprocess.run(["xcrun", "--sdk", "watchsimulator", "clang", "-arch", "arm64", "-mwatchos-simulator-version-min=10.0",
                        "-dynamiclib", csrc, "-o", dylib, "-install_name", newpath], check=True)
        subprocess.run(["codesign", "--force", "-s", "-", dylib], check=True)
        subprocess.run(["install_name_tool", "-change", lib, newpath, binary], check=True)
        g.rl(f"Q4:   stub {name}: defines {len(wanted)} symbols")

    present = {g.short(l) for l in libs if g.flat(l) in installs}
    blockers = [(s, f) for s, f in undef if f in present and s not in syms]
    g.rl(f"Q4: symbols missing from libraries the watchOS SDK does have: {len(blockers)}"
         + ("" if not blockers else " e.g. " + ", ".join(f"{s} (in {f})" for s, f in blockers[:10])))
    subprocess.run(["codesign", "--force", "-s", "-", binary], check=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
