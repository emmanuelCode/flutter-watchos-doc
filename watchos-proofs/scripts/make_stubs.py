#!/usr/bin/env python3
"""Q4 helper: for every library the engine imports that the watchOS SDK does NOT have, build a stub dylib that
defines the imported symbols (as zeroed data), and repoint the engine at it. The stubs are never meant to run;
they only let dyld finish loading so we can see how far the engine gets.
Usage: make_stubs.py <engine-binary-to-patch> <stub-dir>"""
import os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import engine_gap as g


def main(binary, outdir):
    os.makedirs(outdir, exist_ok=True)
    watch_sdk = g.sdk_path("watchsimulator")
    syms, installs = g.load_sdk(watch_sdk)
    libs = g.linked_libs(binary)
    undef = g.undefined(binary)
    missing_libs = [l for l in libs if not l.startswith("@") and l not in installs]
    g.rl("Q4: stubbing libraries the watchOS SDK lacks: " + (", ".join(g.short(l) for l in missing_libs) or "none"))

    for lib in missing_libs:
        name = g.short(lib)
        wanted = sorted({s for s, f in undef if f == name})
        csrc = os.path.join(outdir, f"stub_{name}.c")
        with open(csrc, "w") as f:
            for i, s in enumerate(wanted):
                f.write(f'char stub_sym_{i}[256] __attribute__((used, aligned(16))) __asm__("{s}");\n')
            f.write("void stub_anchor(void) {}\n")
        dylib = os.path.join(outdir, f"stub_{name}.dylib")
        newpath = f"@loader_path/{os.path.basename(outdir)}/stub_{name}.dylib"
        subprocess.run(["xcrun", "--sdk", "watchsimulator", "clang", "-arch", "arm64", "-mwatchos-simulator-version-min=10.0",
                        "-dynamiclib", csrc, "-o", dylib, "-install_name", newpath], check=True)
        subprocess.run(["codesign", "--force", "-s", "-", dylib], check=True)
        subprocess.run(["install_name_tool", "-change", lib, newpath, binary], check=True)
        g.rl(f"Q4:   stub {name}: defines {len(wanted)} symbols")

    # symbols missing from libraries that DO exist in the watchOS SDK cannot be stubbed this way: report them
    present = {g.short(l) for l in libs if l in installs}
    blockers = [(s, f) for s, f in undef if f in present and s not in syms]
    g.rl(f"Q4: symbols missing from libraries the watchOS SDK does have: {len(blockers)}"
         + ("" if not blockers else " e.g. " + ", ".join(f"{s} (in {f})" for s, f in blockers[:8])))
    subprocess.run(["codesign", "--force", "-s", "-", binary], check=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
