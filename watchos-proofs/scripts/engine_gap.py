#!/usr/bin/env python3
"""Dependency-gap analysis: which imports of a Mach-O binary does the watchOS SDK NOT provide?
Usage: engine_gap.py <label> <binary>        (imported by make_stubs.py as a module)
Everything is derived from Apple's SDK .tbd stubs and `nm`/`otool`; nothing is guessed."""
import collections, json, os, re, subprocess, sys

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


PLATFORMS = ("macos", "ios", "watchos", "tvos", "xros", "visionos", "bridgeos", "maccatalyst", "driverkit")
EXPORTS_RX = re.compile(r"^exports:[ \t]*\n(.*?)(?=^(?:reexports|undefineds)\s*:|^\.\.\.|^---|\Z)", re.S | re.M)
BLOCK_SPLIT = re.compile(r"^[ \t]*-[ \t]+(?:targets|archs):", re.M)


def _add_tokens(key, body, syms):
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


def _parse_tbd_v5_lib(lib, syms, installs, platform=None):
    if not isinstance(lib, dict):
        return
    for item in lib.get("install_names", []):
        name = item.get("name") if isinstance(item, dict) else item
        if isinstance(name, str):
            installs.add(name)
    for exp in lib.get("exported_symbols", []):
        if not isinstance(exp, dict):
            continue
        targets = " ".join(str(t).lower() for t in exp.get("targets", []))
        if platform and targets and any(p in targets for p in PLATFORMS) and platform not in targets:
            continue
        data = exp.get("data", exp)
        if not isinstance(data, dict):
            continue
        for key in ("global", "weak", "thread_local"):
            for s in data.get(key, []):
                if isinstance(s, str):
                    syms.add(s)
        for cls in data.get("objc_class", []):
            if isinstance(cls, str):
                syms.add("_OBJC_CLASS_$_" + cls)
                syms.add("_OBJC_METACLASS_$_" + cls)
        for eh in data.get("objc_eh_type", []):
            if isinstance(eh, str):
                syms.add("_OBJC_EHTYPE_$_" + eh)
        for ivar in data.get("objc_ivar", []):
            if isinstance(ivar, str):
                syms.add("_OBJC_IVAR_$_" + ivar)


def parse_tbd(text, syms, installs, platform=None):
    """Collect install names and exported symbols from YAML TBD (v3/v4) and JSON TBD (v5)."""
    stripped = text.lstrip()
    if stripped.startswith("{"):
        try:
            doc = json.loads(stripped)
            _parse_tbd_v5_lib(doc.get("main_library"), syms, installs, platform)
            for sub in doc.get("libraries", []):
                _parse_tbd_v5_lib(sub, syms, installs, platform)
            return
        except Exception:
            pass
    for m in INSTALL_RX.finditer(text):
        installs.add(m.group(1).strip())
    for em in EXPORTS_RX.finditer(text):
        for block in BLOCK_SPLIT.split(em.group(1))[1:]:
            tm = re.match(r"\s*\[(.*?)\]", block, re.S)
            targets = tm.group(1).lower() if tm else ""
            if platform and any(p in targets for p in PLATFORMS) and platform not in targets:
                continue
            for key, body in LIST_RX.findall(block):
                _add_tokens(key, body, syms)


def load_sdk(sdk, platform=None):
    syms, installs = set(), set()
    for root, _dirs, files in os.walk(sdk):
        for fn in files:
            if fn.endswith(".tbd"):
                try:
                    parse_tbd(open(os.path.join(root, fn), encoding="utf-8", errors="replace").read(), syms, installs, platform)
                except OSError:
                    pass
    return syms, installs


FLAT_RX = re.compile(r"^(/System/Library/(?:Private)?Frameworks/[^/]+\.framework)/Versions/[^/]+/(.+)$")


def flat(libpath):
    """macOS frameworks are versioned (X.framework/Versions/A/X); iOS and watchOS are flat (X.framework/X)."""
    m = FLAT_RX.match(libpath)
    return f"{m.group(1)}/{m.group(2)}" if m else libpath


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


KEY_APIS = [  # (what, symbol) — direct facts about what the watchOS SDK exports for the watchOS target
    ("UIView", "_OBJC_CLASS_$_UIView"), ("UIViewController", "_OBJC_CLASS_$_UIViewController"),
    ("UIScreen", "_OBJC_CLASS_$_UIScreen"), ("UIApplication", "_OBJC_CLASS_$_UIApplication"),
    ("UITouch", "_OBJC_CLASS_$_UITouch"), ("UIImage", "_OBJC_CLASS_$_UIImage"),
    ("CALayer", "_OBJC_CLASS_$_CALayer"), ("CAMetalLayer", "_OBJC_CLASS_$_CAMetalLayer"),
    ("CADisplayLink", "_OBJC_CLASS_$_CADisplayLink"), ("MTLCreateSystemDefaultDevice", "_MTLCreateSystemDefaultDevice"),
    ("CGBitmapContextCreate", "_CGBitmapContextCreate"), ("CTFontCreateWithName", "_CTFontCreateWithName"),
    ("CFRunLoopRunInMode", "_CFRunLoopRunInMode"), ("WKInterfaceDevice", "_OBJC_CLASS_$_WKInterfaceDevice"),
    ("WKCrownSequencer", "_OBJC_CLASS_$_WKCrownSequencer"), ("IOSurfaceCreate", "_IOSurfaceCreate"),
]


def analyse(label, binary):
    watch_sdk, ios_sdk = sdk_path("watchsimulator"), sdk_path("iphonesimulator")
    watch_syms, watch_installs = load_sdk(watch_sdk, "watchos")
    ios_syms, _ = load_sdk(ios_sdk, "ios")
    libs = linked_libs(binary)
    undef = undefined(binary)

    missing_libs = [l for l in libs if not l.startswith("@") and flat(l) not in watch_installs]
    relocatable = [l for l in libs if flat(l) != l and flat(l) in watch_installs]
    missing = [(s, f) for s, f in undef if s not in watch_syms]
    on_ios = [s for s, _ in missing if s in ios_syms]

    rl(f"Q3: [{label}] {os.path.basename(binary)}: {len(libs)} linked libraries, {len(undef)} imported symbols")
    rl(f"Q3: [{label}] libraries that exist on watchOS but at a flat path (macOS-style versioned path must be rewritten): {len(relocatable)}")
    rl(f"Q3: [{label}] libraries NOT provided by the watchOS SDK at all: " + (", ".join(short(l) for l in missing_libs) or "none"))
    rl(f"Q3: [{label}] imported symbols missing on watchOS (platform-filtered): {len(missing)} of {len(undef)} ({len(on_ios)} of those exist in the iOS Simulator SDK)")
    by_lib = collections.defaultdict(list)
    for s_, f in missing:
        by_lib[f].append(s_)
    for lib, names in sorted(by_lib.items(), key=lambda kv: -len(kv[1]))[:12]:
        rl(f"Q3: [{label}]   {lib}: {len(names)} missing, e.g. " + ", ".join(names[:5]))
    return missing_libs, by_lib


def api_facts():
    watch_syms, _ = load_sdk(sdk_path("watchsimulator"), "watchos")
    have = [n for n, s in KEY_APIS if s in watch_syms]
    lack = [n for n, s in KEY_APIS if s not in watch_syms]
    rl("Q3: key APIs the watchOS SDK exports for the watchOS target: " + (", ".join(have) or "none"))
    rl("Q3: key APIs the watchOS SDK does NOT export for the watchOS target: " + (", ".join(lack) or "none"))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: engine_gap.py <label> <binary> | --api-facts")
    if sys.argv[1] == "--api-facts":
        api_facts()
    else:
        analyse(sys.argv[1], sys.argv[2])
