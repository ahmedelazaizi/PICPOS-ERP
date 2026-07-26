#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the Inno Setup wizard BMP images for one brand.

   Run: python installer/make_wizard_images.py [uralcash|picpos|all]
   (needs Pillow). Default: all.

   Output is per-brand — `wizard-large-<brand>.bmp` / `wizard-small-<brand>.bmp`
   — because the .iss picks its images by BrandId. A single shared pair would
   put the teal UralCash splash on the PicPos installer.

   LATIN WORDMARK ONLY. PIL draws glyphs without shaping or bidi, so Arabic
   comes out disconnected and reversed. The UralCash image predates this note
   and still carries a broken Arabic subtitle ("نظام إدارة" renders mirrored);
   PicPos uses a Latin subtitle instead. Arabic UI text belongs in the wizard
   strings, which Inno renders RTL correctly.

   NOTE: the committed PicPos BMPs were produced with this geometry and
   palette. Regenerating is safe; re-running for `uralcash` reproduces the
   shipped teal artwork.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)
FONT = HERE.parent / "assets" / "fonts" / "Cairo-Regular.ttf"

WHITE = (255, 255, 255)

# Per-brand identity. `dark`/`mid` drive the gradient, `accent` the light
# band, the ring highlights and the second half of the wordmark.
# The PicPos values are the same ones in AppColors — pulled from the logo.
BRANDS = {
    "uralcash": {
        "dark": (19, 70, 87),      # teal 900
        "mid": (43, 115, 127),     # teal 600
        "accent": (70, 156, 165),  # teal 400
        "mark": "U",
        "word": ("Ural", "Cash"),
        "subtitle": "ERP  —  نظام إدارة",
        "mark_size": 46,
    },
    "picpos": {
        "dark": (1, 34, 88),       # #012258
        "mid": (2, 80, 211),       # #0250D3
        "accent": (90, 150, 240),  # #5A96F0
        "mark": "P",
        "word": ("Pic", "Pos"),
        "subtitle": "ERP  -  Point of Sale",
        "mark_size": 42,
    },
}


def font(sz):
    try:
        return ImageFont.truetype(str(FONT), sz)
    except Exception:
        return ImageFont.load_default()


def vgrad(w, h, top, bot):
    img = Image.new("RGB", (w, h), top)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def large(b):
    w, h = 164, 314
    img = vgrad(w, h, b["dark"], b["mid"])
    d = ImageDraw.Draw(img, "RGBA")
    # diagonal light accent band
    d.polygon([(0, 210), (w, 150), (w, 190), (0, 250)], fill=b["accent"] + (60,))
    # concentric ring motif (register/coin feel), top area
    cx, cy = w // 2, 92
    for r, a in ((52, 40), (40, 60), (28, 90)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, a),
                  width=2)
    # brand letter inside the rings
    fu = font(b["mark_size"])
    tb = d.textbbox((0, 0), b["mark"], font=fu)
    d.text((cx - (tb[2] - tb[0]) / 2, cy - (tb[3] - tb[1]) / 2 - tb[1]),
           b["mark"], font=fu, fill=WHITE)
    # wordmark near the bottom
    fw = font(26)
    head, tail = b["word"]
    d.text((14, 250), head, font=fw, fill=WHITE)
    wb = d.textbbox((0, 0), head, font=fw)
    d.text((14 + (wb[2] - wb[0]), 250), tail, font=fw, fill=b["accent"])
    d.text((15, 284), b["subtitle"], font=font(12), fill=(255, 255, 255, 200))
    return img


def small(b):
    w, h = 55, 58
    img = Image.new("RGB", (w, h), b["mid"])
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle([4, 4, w - 5, h - 5], radius=10, fill=b["dark"],
                        outline=b["accent"], width=2)
    fu = font(30)
    tb = d.textbbox((0, 0), b["mark"], font=fu)
    d.text(((w - (tb[2] - tb[0])) / 2, (h - (tb[3] - tb[1])) / 2 - tb[1]),
           b["mark"], font=fu, fill=WHITE)
    return img


def build(brand):
    b = BRANDS[brand]
    large(b).save(ASSETS / f"wizard-large-{brand}.bmp")
    small(b).save(ASSETS / f"wizard-small-{brand}.bmp")
    print("Wrote", ASSETS / f"wizard-large-{brand}.bmp",
          "and", ASSETS / f"wizard-small-{brand}.bmp")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which == "all":
        for name in BRANDS:
            build(name)
    elif which in BRANDS:
        build(which)
    else:
        sys.exit(f"unknown brand: {which} (expected {'|'.join(BRANDS)}|all)")
