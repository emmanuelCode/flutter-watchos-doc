#!/usr/bin/env python3
"""Dependency-gap analysis: which imports of a Mach-O binary does the watchOS SDK NOT provide?
Usage: engine_gap.py <label> <binary>        (imported by make_stubs.py as a module)
Everything is derived from Apple's SDK .tbd stubs and `nm`/`otool`; nothing is guessed."""
import collections, os, re, subprocess, sys

RL = "/tmp/watch_proofs/results.log"


def rl(line):
    os.makedirs(os.path.dirname(RL), exist_ok=True)
    with open(RL, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def sdk_path(name):
    return subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip()


LIST_RX = re.compile(r"\b(symbols|weak-symbols|thread-local-symbols|objc-classes|objc-eh-types|objc-ivars)\s*:\s*\[(.*?)\]", re.S)
INSTALL_RX = re.compile(r"install-name:\s*'?([^'\n]+?)'?\s*$", re.M)


def parse_tbd(text, syms, installs):
    for m in INSTALL_RX.finditer(text):
        installs.add(m.group(1).strip())
    for key, body in LIST_RX.findall(text):
        for tok in re.split(r"[,\n]", body):
            t = tok.strip().strip("'\"")
            if not t:
                continue
            if key == "objc-classes":
                syms.add("_OBJC_CLASS_$_" + t)
                syms.add("_OBJC_METACLASS_$_" + t)
            elif key == "objc-eh-types":
                syms.add("_OBJC_EHTYPE_$_" + t)
            elif key == "objc-ivars":
                syms.add("_OBJC_IVAR_$_" + t)
            else:
                syms.add(t)


def load_sdk(sdk):
    syms, installs = set(), set()
    for root, _dirs, files in os.walk(sdk):
        for fn in files:
            if fn.endswith(".tbd"):
                try:
                    parse_tbd(open(os.path.join(root, fn), encoding="utf-8", errors="replace").read(), syms, installs)
                except OSError:
                    pass
    return syms, installs


NM_RX = re.compile(r"\(undefined\)\s+(?:weak\s+)?(?:private\s+)?external\s+(\S+)(?:\s+\(from ([^)]+)\))?")


def parse_nm(text):
    return [(m.group(1), m.group(2) or "?") for m in NM_RX.finditer(text)]


def linked_libs(binary):
    out = subprocess.check_output(["otool", "-arch", "arm64", "-L", binary], text=True, stderr=subprocess.STDOUT)
    libs = []
    for line in out.splitlines()[1:]:
        line = line.strip()
        if line:
            libs.append(line.split(" (")[0])
    return libs


def undefined(binary):
    out = subprocess.check_output(["nm", "-m", "-u", "-arch", "arm64", binary], text=True, stderr=subprocess.STDOUT)
    return parse_nm(out)


def short(libpath):
    """Library short name as `nm -m` prints it: libSystem.B.dylib -> libSystem, libc++.1.dylib -> libc++, AppKit -> AppKit."""
    name = os.path.basename(libpath)
    if name.endswith(".dylib"):
        name = name[: -len(".dylib")]
    return re.sub(r"(\.[0-9A-Z]+)+$", "", name)


def analyse(label, binary):
    watch_sdk, ios_sdk = sdk_path("watchsimulator"), sdk_path("iphonesimulator")
    watch_syms, watch_installs = load_sdk(watch_sdk)
    ios_syms, _ = load_sdk(ios_sdk)
    libs = linked_libs(binary)
    undef = undefined(binary)

    missing_libs = [l for l in libs if not l.startswith("@") and l not in watch_installs]
    missing = [(s, f) for s, f in undef if s not in watch_syms]
    on_ios = [s for s, _ in missing if s in ios_syms]

    rl(f"Q3: [{label}] {os.path.basename(binary)}: {len(libs)} linked libraries, {len(undef)} imported symbols")
    rl(f"Q3: [{label}] libraries NOT provided by the watchOS SDK: " + (", ".join(short(l) for l in missing_libs) or "none"))
    rl(f"Q3: [{label}] imported symbols missing on watchOS: {len(missing)} of {len(undef)} ({len(on_ios)} of those exist in the iOS Simulator SDK)")
    by_lib = collections.defaultdict(list)
    for s, f in missing:
        by_lib[f].append(s)
    for lib, names in sorted(by_lib.items(), key=lambda kv: -len(kv[1]))[:12]:
        rl(f"Q3: [{label}]   {lib}: {len(names)} missing, e.g. " + ", ".join(names[:5]))
    return missing_libs, by_lib


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: engine_gap.py <label> <binary>")
    analyse(sys.argv[1], sys.argv[2])
