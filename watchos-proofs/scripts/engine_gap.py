#!/usr/bin/env python3
"""Dependency-gap analysis: which imports of a Mach-O binary does the watchOS SDK NOT provide?
Usage: engine_gap.py <label> <binary> | --api-facts    (imported by make_stubs.py as a module)
Everything is derived from Apple's SDK .tbd stubs, clang/swiftc headers, and `nm`/`otool`."""
import collections, json, os, re, subprocess, sys

RL = "/tmp/watch_proofs/results.log"


def rl(line):
    os.makedirs(os.path.dirname(RL), exist_ok=True)
    with open(RL, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def sdk_path(name):
    return subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip()


LIST_RX = re.compile(
    r"\b(symbols|weak-symbols|thread-local-symbols|objc-classes|objc-eh-types|objc-ivars)\s*:\s*\[(.*?)\]",
    re.S,
)
INSTALL_RX = re.compile(r"install-name:\s*['\"]?([^'\"\n]+?)['\"]?\s*$", re.M)

PLATFORMS = ("macos", "ios", "watchos", "tvos", "xros", "visionos", "bridgeos", "maccatalyst", "driverkit")
EXPORTS_RX = re.compile(
    r"^(?:exports|reexports|re-exports):[ \t]*\n(.*?)(?=^(?=[a-zA-Z])[a-zA-Z0-9_-]*\s*:|^\.\.\.|^---|\Z)",
    re.S | re.M,
)
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


def _iter_v5_libs(libs_obj):
    if isinstance(libs_obj, dict):
        return list(libs_obj.values())
    if isinstance(libs_obj, list):
        return list(libs_obj)
    return []


def _parse_tbd_v5_lib(lib, syms, installs, platform=None):
    if not isinstance(lib, dict):
        return
    for item in lib.get("install_names", []):
        name = item.get("name") if isinstance(item, dict) else item
        if isinstance(name, str):
            installs.add(name)
    for section_key in ("exported_symbols", "reexported_symbols"):
        for exp in lib.get(section_key, []):
            if not isinstance(exp, dict):
                continue
            targets = " ".join(str(t).lower() for t in exp.get("targets", []))
            if platform and targets and any(p in targets for p in PLATFORMS) and platform not in targets:
                continue
            for section in (exp.get("text"), exp.get("data"), exp.get("thread_local"), exp):
                if not isinstance(section, dict):
                    continue
                for key in ("global", "weak", "thread_local", "symbols"):
                    for s in section.get(key, []):
                        if isinstance(s, str):
                            syms.add(s)
                for cls in section.get("objc_class", []):
                    if isinstance(cls, str):
                        syms.add("_OBJC_CLASS_$_" + cls)
                        syms.add("_OBJC_METACLASS_$_" + cls)
                for eh in section.get("objc_eh_type", []):
                    if isinstance(eh, str):
                        syms.add("_OBJC_EHTYPE_$_" + eh)
                for ivar in section.get("objc_ivar", []):
                    if isinstance(ivar, str):
                        syms.add("_OBJC_IVAR_$_" + ivar)


def _walk_v5_lib(lib, syms, installs, platform=None):
    if not isinstance(lib, dict):
        return
    _parse_tbd_v5_lib(lib, syms, installs, platform)
    for sub in _iter_v5_libs(lib.get("libraries")):
        _walk_v5_lib(sub, syms, installs, platform)


def parse_tbd(text, syms, installs, platform=None):
    """Collect install names and exported/re-exported symbols from YAML TBD (v3/v4) and JSON TBD (v5)."""
    stripped = text.lstrip()
    if stripped.startswith("{"):
        try:
            doc = json.loads(stripped)
            _walk_v5_lib(doc.get("main_library"), syms, installs, platform)
            for sub in _iter_v5_libs(doc.get("libraries")):
                _walk_v5_lib(sub, syms, installs, platform)
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


def _walk_tbds(sdk):
    seen = set()
    for root, dirs, files in os.walk(sdk, followlinks=True):
        real = os.path.realpath(root)
        if real in seen:
            dirs[:] = []
            continue
        seen.add(real)
        for fn in files:
            if fn.endswith(".tbd"):
                yield os.path.join(root, fn)


def load_sdk(sdk, platform=None):
    syms, installs = set(), set()
    for path in _walk_tbds(sdk):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                parse_tbd(f.read(), syms, installs, platform)
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


KEY_APIS = [  # (what, symbol) — direct .tbd facts for the watchOS linker target
    ("UIView", "_OBJC_CLASS_$_UIView"), ("UIViewController", "_OBJC_CLASS_$_UIViewController"),
    ("UIScreen", "_OBJC_CLASS_$_UIScreen"), ("UIApplication", "_OBJC_CLASS_$_UIApplication"),
    ("UITouch", "_OBJC_CLASS_$_UITouch"), ("UIImage", "_OBJC_CLASS_$_UIImage"),
    ("CALayer", "_OBJC_CLASS_$_CALayer"), ("CAMetalLayer", "_OBJC_CLASS_$_CAMetalLayer"),
    ("CADisplayLink", "_OBJC_CLASS_$_CADisplayLink"), ("MTLCreateSystemDefaultDevice", "_MTLCreateSystemDefaultDevice"),
    ("CGBitmapContextCreate", "_CGBitmapContextCreate"), ("CTFontCreateWithName", "_CTFontCreateWithName"),
    ("CFRunLoopRunInMode", "_CFRunLoopRunInMode"), ("WKInterfaceDevice", "_OBJC_CLASS_$_WKInterfaceDevice"),
    ("WKCrownSequencer", "_OBJC_CLASS_$_WKCrownSequencer"), ("IOSurfaceCreate", "_IOSurfaceCreate"),
    ("SKMutableTexture", "_OBJC_CLASS_$_SKMutableTexture"), ("SKView", "_OBJC_CLASS_$_SKView"),
    ("CVPixelBufferCreate", "_CVPixelBufferCreate"),
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

    try:
        dev_sdk = sdk_path("watchos")
        dev_syms, dev_installs = load_sdk(dev_sdk, "watchos")
        dev_missing = [(s, f) for s, f in undef if s not in dev_syms]
        dev_only_missing_libs = [short(l) for l in libs if not l.startswith("@") and flat(l) in watch_installs and flat(l) not in dev_installs]
        dev_only_missing_syms = [f"{s} (in {f})" for s, f in undef if s in watch_syms and s not in dev_syms]
        sim_only_missing_syms = [f"{s} (in {f})" for s, f in undef if s not in watch_syms and s in dev_syms]
        rl(f"Q3: [{label}] device SDK (watchos) direct check: {len(dev_missing)} of {len(undef)} missing; "
           f"delta vs watchsimulator: +{len(dev_only_missing_libs)} libs, +{len(dev_only_missing_syms)} / -{len(sim_only_missing_syms)} syms")
        if sim_only_missing_syms:
            rl(f"Q3: [{label}]   present in watchos device SDK but missed in watchsimulator: " + ", ".join(sim_only_missing_syms[:8]))
    except subprocess.CalledProcessError:
        rl(f"Q3: [{label}] device SDK (watchos) not installed on this host")

    return missing_libs, by_lib


def _log_api_facts(sdk_name, platform):
    try:
        path = sdk_path(sdk_name)
    except subprocess.CalledProcessError:
        rl(f"Q3: [{sdk_name}] SDK not installed on this host")
        return
    syms, _ = load_sdk(path, platform)
    have = [n for n, s in KEY_APIS if s in syms]
    lack = [n for n, s in KEY_APIS if s not in syms]
    rl(f"Q3: [{sdk_name}] key APIs exported for {platform}: " + (", ".join(have) or "none"))
    rl(f"Q3: [{sdk_name}] key APIs NOT exported for {platform}: " + (", ".join(lack) or "none"))


def _compile_probe(sdk_name, lang, code):
    try:
        sdk = sdk_path(sdk_name)
    except subprocess.CalledProcessError:
        return "SDK missing"
    if lang == "swift":
        target = "arm64-apple-watchos10.0-simulator" if "sim" in sdk_name else "arm64-apple-watchos10.0"
        cmd = ["xcrun", "--sdk", sdk_name, "swiftc", "-target", target, "-typecheck", "-"]
    else:
        min_flag = "-mwatchos-simulator-version-min=10.0" if "sim" in sdk_name else "-mwatchos-version-min=10.0"
        cmd = ["xcrun", "--sdk", sdk_name, "clang", "-arch", "arm64", min_flag, "-isysroot", sdk, "-x", lang]
        if lang == "objective-c":
            cmd.append("-fobjc-arc")
        cmd += ["-fsyntax-only", "-"]
    p = subprocess.run(cmd, input=code, text=True, capture_output=True)
    if p.returncode == 0:
        return "OK"
    err = next((ln.strip() for ln in p.stderr.splitlines() if "error:" in ln), "")
    if not err:
        err = (p.stderr.strip().splitlines() or ["failed"])[-1]
    return f"FAIL ({err[:140]})"


def _header_facts(sdk_name="watchos"):
    probes = [
        ("Metal.h / MTLCreateSystemDefaultDevice", "objective-c", "#import <Metal/Metal.h>\nid f(void) { return MTLCreateSystemDefaultDevice(); }\n"),
        ("QuartzCore / CAMetalLayer", "objective-c", "#import <QuartzCore/QuartzCore.h>\nClass f(void) { return [CAMetalLayer class]; }\n"),
        ("UIKit / UIView", "objective-c", "#import <UIKit/UIKit.h>\nClass f(void) { return [UIView class]; }\n"),
        ("SpriteKit / SKMutableTexture (ObjC initWithSize:)", "objective-c", "#import <SpriteKit/SpriteKit.h>\nSKMutableTexture *f(void) { return [[SKMutableTexture alloc] initWithSize:CGSizeMake(10, 10)]; }\n"),
        ("SpriteKit / SKMutableTexture (Swift)", "swift", "import SpriteKit\nlet _ = SKMutableTexture(size: CGSize(width: 10, height: 10))\n"),
        ("SpriteKit / SKTexture(data:size:) (Swift)", "swift", "import Foundation\nimport SpriteKit\nlet _ = SKTexture(data: Data(), size: CGSize(width: 10, height: 10))\n"),
        ("SwiftUI / SpriteView", "swift", "import SwiftUI\nimport SpriteKit\nlet _ = SpriteView.self\n"),
        ("CoreGraphics + CoreText", "objective-c", "#import <CoreGraphics/CoreGraphics.h>\n#import <CoreText/CoreText.h>\nvoid *f(void) { return (void *)&CGBitmapContextCreate; }\n"),
        ("WatchKit / WKCrownSequencer", "objective-c", "#import <WatchKit/WatchKit.h>\nClass f(void) { return [WKCrownSequencer class]; }\n"),
        ("POSIX chdir", "c", "#include <unistd.h>\nint f(void) { return chdir(\"/\"); }\n"),
        ("POSIX fork", "c", "#include <unistd.h>\npid_t f(void) { return fork(); }\n"),
    ]
    for label, lang, code in probes:
        try:
            res = _compile_probe(sdk_name, lang, code)
        except Exception as e:
            res = f"ERR ({e})"
        rl(f"Q3: [headers:{sdk_name}] {label} -> {res}")


def _diagnose_libsystem(sdk_name="watchsimulator"):
    try:
        sdk = sdk_path(sdk_name)
    except subprocess.CalledProcessError:
        return
    lib_tbd = os.path.join(sdk, "usr", "lib", "libSystem.B.tbd")
    sys_dir = os.path.join(sdk, "usr", "lib", "system")
    rl(f"Q3: [diag:{sdk_name}] libSystem.B.tbd exists={os.path.exists(lib_tbd)}; usr/lib/system exists={os.path.isdir(sys_dir)}")
    if os.path.exists(lib_tbd):
        try:
            with open(lib_tbd, encoding="utf-8", errors="replace") as f:
                lines = [ln.rstrip() for ln in f if ln.strip()][:8]
            for ln in lines:
                rl(f"Q3: [diag:{sdk_name}]   libSystem.B.tbd: {ln[:140]}")
        except OSError:
            pass
    targets = ("___error", "_chdir", "__exit")
    hits = {t: [] for t in targets}
    for p in _walk_tbds(sdk):
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for t in targets:
            if t in txt:
                s_one = set()
                parse_tbd(txt, s_one, set(), "watchos")
                hits[t].append((os.path.relpath(p, sdk), t in s_one))
    for t in targets:
        rl(f"Q3: [diag:{sdk_name}] raw .tbd matches for {t}: " + (", ".join(f"{p}(parsed={ok})" for p, ok in hits[t][:5]) or "NONE"))
        bad = next((p for p, ok in hits[t] if not ok), None)
        if bad and t == "___error":
            try:
                raw = open(os.path.join(sdk, bad), encoding="utf-8", errors="replace").read()
                idx = raw.find(t)
                top = [ln.rstrip() for ln in raw.splitlines()[:12] if ln.strip()]
                head = [ln.rstrip() for ln in raw[:idx].splitlines() if ln.strip() and not ln.lstrip().startswith("_")][-12:]
                rl(f"Q3: [diag:{sdk_name}]   top ({bad}): " + " | ".join(top)[:240])
                rl(f"Q3: [diag:{sdk_name}]   above {t} ({bad}): " + " | ".join(head)[:240])
            except OSError:
                pass


def api_facts():
    _log_api_facts("watchsimulator", "watchos")
    _log_api_facts("watchos", "watchos")
    _header_facts("watchos")
    _diagnose_libsystem("watchsimulator")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: engine_gap.py <label> <binary> | --api-facts")
    if sys.argv[1] == "--api-facts":
        api_facts()
    else:
        analyse(sys.argv[1], sys.argv[2])
