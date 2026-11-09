#!/usr/bin/env python3
"""Q5: reads the frame file written by engine_host and checks the probe app's three stripes."""
import struct, sys
from PIL import Image

path, png = sys.argv[1], sys.argv[2]
raw = open(path, "rb").read()
w, h, row = struct.unpack("<III", raw[:12])
im = Image.frombuffer("RGBA", (w, h), raw[12:], "raw", "BGRA", row, 1).convert("RGB")
im.save(png)
print(f"Q5: frame is {w}x{h}, saved as PNG")

def near(got, want, tol=40):
    return all(abs(g - x) <= tol for g, x in zip(got, want))

s1 = im.getpixel((w // 2, int(h * 0.17)))
s3 = im.getpixel((w // 2, int(h * 0.83)))
y0, y1 = int(h * 0.36), int(h * 0.64)
bright = sum(1 for y in range(y0, y1) for x in range(w // 4, 3 * w // 4) if sum(im.getpixel((x, y))) > 600)
corner = im.getpixel((2, int(h * 0.5)))

checks = [
    ("stripe 1 green: Dart executed (fib(20) == 6765)", near(s1, (0, 255, 0)), s1),
    ("stripe 2: white 'W' glyph pixels in the middle (text shaping + fonts)", bright > 150, f"{bright} bright pixels"),
    ("stripe 2: black background", near(corner, (0, 0, 0), 30), corner),
    ("stripe 3 blue: a second region painted", near(s3, (0, 0, 255)), s3),
]
ok = True
for name, passed, detail in checks:
    ok = ok and passed
    print(f"Q5: {name}: {detail} -> {'ok' if passed else 'MISMATCH'}")
sys.exit(0 if ok else 1)
