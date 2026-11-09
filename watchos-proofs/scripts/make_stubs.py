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


def overlay_one(binary, outdir, symbol):
    """Q4 iteration. dyld reports ONE missing symbol per failed load. Find which library the engine imports it from
    and replace that library's load command with an overlay dylib that (a) defines the missing symbols and
    (b) re-exports the real library, so every other symbol still resolves to the genuine one.
    State (the symbols collected so far per library) is kept in <outdir>/overlay_state.json.
    Returns False if the symbol is not imported by the engine at all (cannot help)."""
    import json
    state_path = os.path.join(outdir, "overlay_state.json")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {}
    lib_short = next((f for s, f in g.undefined(binary) if s == symbol), None)
    if lib_short is not None:
        # after an overlay, nm prints the full @loader_path/... install name instead of the short name
        lib_short = g.short(lib_short)
    if lib_short is None:
        g.rl(f"Q4:   {symbol}: the engine does not import it; cannot overlay")
        return False
    linked = g.linked_libs(binary)
    current = next((l for l in linked if g.short(l) == lib_short), None)
    if current is None:
        g.rl(f"Q4:   {symbol}: no load command found for library {lib_short}")
        return False
    entry = state.setdefault(lib_short, {"orig": current, "symbols": []})
    if symbol not in entry["symbols"]:
        entry["symbols"].append(symbol)
    orig = entry["orig"]
    base = os.path.basename(orig)
    ovdir = os.path.join(outdir, f"ov_{lib_short}")
    os.makedirs(ovdir, exist_ok=True)
    csrc = os.path.join(ovdir, "ov.c")
    with open(csrc, "w") as f:
        for i, s in enumerate(entry["symbols"]):
            f.write(f'char ov_sym_{i}[256] __asm__("{s}") __attribute__((used, aligned(16)));\n')
        f.write("void ov_anchor(void) {}\n")
    # re-export the real library (frameworks by name, /usr/lib dylibs by -l name)
    m = g.re.match(r"/System/Library/(?:Private)?Frameworks/([^/]+)\.framework/", g.flat(orig))
    if m:
        reexp = ["-Wl,-reexport_framework," + m.group(1)]
    else:
        ln = g.re.sub(r"^lib", "", g.short(orig))
        reexp = ["-Wl,-reexport-l" + ln]
    newpath = f"@loader_path/{os.path.basename(outdir)}/ov_{lib_short}/{base}"
    dylib = os.path.join(ovdir, base)
    subprocess.run(["xcrun", "--sdk", "watchsimulator", "clang", "-arch", "arm64", "-mwatchos-simulator-version-min=10.0",
                    "-dynamiclib", csrc, "-o", dylib, "-install_name", newpath] + reexp, check=True)
    subprocess.run(["codesign", "--force", "-s", "-", dylib], check=True)
    subprocess.run(["install_name_tool", "-change", current, newpath, binary], check=True)
    subprocess.run(["codesign", "--force", "-s", "-", binary], check=True)
    json.dump(state, open(state_path, "w"))
    g.rl(f"Q4:   overlay {lib_short}: now defines {len(entry['symbols'])} symbol(s), re-exports the real library")
    return True


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--add":
        sys.exit(0 if overlay_one(sys.argv[2], sys.argv[3], sys.argv[4]) else 1)
    main(sys.argv[1], sys.argv[2])
