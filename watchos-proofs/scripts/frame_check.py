#!/usr/bin/env python3
"""Q5 / Q6 / Q7: reads the frame file written by engine_host and checks the probe app's stripes."""
import struct, sys

try:
    from PIL import Image
except ImportError:
    Image = None

path, png = sys.argv[1], sys.argv[2]
is_frame2 = "--frame2" in sys.argv
is_frame3 = "--frame3" in sys.argv
prefix = "Q7" if is_frame3 else ("Q6" if is_frame2 else "Q5")

raw = open(path, "rb").read()
w, h, row = struct.unpack("<III", raw[:12])

def near(got, want, tol=40):
    return all(abs(g - x) <= tol for g, x in zip(got, want))

def get_pixel(x, y, order):
    offset = 12 + y * row + x * 4
    if offset + 3 <= len(raw):
        if order == "RGBA":
            return (raw[offset], raw[offset+1], raw[offset+2])
        else: # BGRA
            return (raw[offset+2], raw[offset+1], raw[offset])
    return (0, 0, 0)

def run_checks(order):
    s1 = get_pixel(w // 2, int(h * 0.17), order)
    s3 = get_pixel(w // 2, int(h * 0.83), order)
    y0, y1 = int(h * 0.36), int(h * 0.64)
    bright = 0
    for y in range(y0, y1):
        for x in range(w // 4, 3 * w // 4):
            if sum(get_pixel(x, y, order)) > 600:
                bright += 1
    corner = get_pixel(2, int(h * 0.5), order)
    if is_frame3:
        return [
            ("stripe 1 magenta: Crown scroll injected & setState executed", near(s1, (255, 0, 255)), s1),
            ("stripe 2: white 'CROWN' glyph pixels in the middle (text shaping + layout)", bright > 100, f"{bright} bright pixels"),
            ("stripe 2: black background", near(corner, (0, 0, 0), 30), corner),
            ("stripe 3 purple: second region repainted post-crown", near(s3, (136, 0, 255)), s3),
        ]
    elif is_frame2:
        return [
            ("stripe 1 yellow: tap injected & setState executed", near(s1, (255, 255, 0)), s1),
            ("stripe 2: white 'TAP' glyph pixels in the middle (text shaping + layout)", bright > 120, f"{bright} bright pixels"),
            ("stripe 2: black background", near(corner, (0, 0, 0), 30), corner),
            ("stripe 3 cyan: second region repainted post-tap", near(s3, (0, 255, 255)), s3),
        ]
    else:
        return [
            ("stripe 1 green: Dart executed (fib(20) == 6765)", near(s1, (0, 255, 0)), s1),
            ("stripe 2: white 'W' glyph pixels in the middle (text shaping + fonts)", bright > 150, f"{bright} bright pixels"),
            ("stripe 2: black background", near(corner, (0, 0, 0), 30), corner),
            ("stripe 3 blue: a second region painted", near(s3, (0, 0, 255)), s3),
        ]

results = {order: run_checks(order) for order in ("RGBA", "BGRA")}
passing = [o for o, cs in results.items() if all(p for _, p, _ in cs)]
chosen = passing[0] if len(passing) == 1 else "RGBA"

if Image is not None:
    try:
        Image.frombuffer("RGBA", (w, h), raw[12:], "raw", chosen, row, 1).convert("RGB").save(png)
        print(f"{prefix}: frame is {w}x{h}, saved as PNG ({png})")
    except Exception as e:
        print(f"{prefix}: frame is {w}x{h} (PNG save failed: {e})")
else:
    print(f"{prefix}: frame is {w}x{h} (pure byte parser; skipped PNG save)")

ok = True
for name, passed, detail in results[chosen]:
    ok = ok and passed
    print(f"{prefix}: {name}: {detail} -> {'ok' if passed else 'MISMATCH'}")
if len(passing) == 1:
    print(f"{prefix}: byte order of the software present callback in this engine build: {passing[0]}")
elif len(passing) == 2:
    print(f"{prefix}: MISMATCH: both byte orders pass, so the frame cannot tell them apart")
    ok = False
else:
    print(f"{prefix}: no byte order explains the frame")
    ok = False
sys.exit(0 if ok else 1)
