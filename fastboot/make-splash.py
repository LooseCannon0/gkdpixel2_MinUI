#!/usr/bin/env python3
"""Generate raw framebuffer splash images for the GKD Pixel 2 (480x640 XRGB8888,
pre-rotated 90 deg CCW to match the portrait panel). Usage:
    make-splash.py "LOADING..." loading.raw [fontsize]
Requires Pillow and a TTF (path below or edit FONT)."""
import sys
from PIL import Image, ImageDraw, ImageFont
FONT = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
text = sys.argv[1] if len(sys.argv) > 1 else "LOADING..."
out  = sys.argv[2] if len(sys.argv) > 2 else "loading.raw"
size = int(sys.argv[3]) if len(sys.argv) > 3 else 44
W, H = 640, 480
img = Image.new("RGB", (W, H), (12, 12, 14))
d = ImageDraw.Draw(img)
f = ImageFont.truetype(FONT, size)
b = d.textbbox((0, 0), text, font=f)
d.text(((W-(b[2]-b[0]))//2, (H-(b[3]-b[1]))//2 - 8), text, font=f, fill=(235, 235, 235))
img = img.rotate(90, expand=True)  # panel is portrait-mounted
px = img.tobytes("raw", "RGB"); buf = bytearray()
for i in range(0, len(px), 3):
    buf += bytes((px[i+2], px[i+1], px[i], 0))  # XRGB8888 little-endian
open(out, "wb").write(buf)
print(out, len(buf), "bytes")
