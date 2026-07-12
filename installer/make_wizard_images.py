#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the Inno Setup wizard BMP images with the UralCash teal identity.
   Run: python installer/make_wizard_images.py   (needs Pillow)
   Latin wordmark only (PIL doesn't shape Arabic) — Arabic UI text lives in the
   wizard strings, which Inno renders RTL correctly."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)
FONT = HERE.parent / "assets" / "fonts" / "Cairo-Regular.ttf"

TEAL900 = (19, 70, 87)
TEAL600 = (43, 115, 127)
TEAL400 = (70, 156, 165)
WHITE = (255, 255, 255)


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


def large():
    w, h = 164, 314
    img = vgrad(w, h, TEAL900, TEAL600)
    d = ImageDraw.Draw(img, "RGBA")
    # diagonal light accent band
    d.polygon([(0, 210), (w, 150), (w, 190), (0, 250)], fill=(70, 156, 165, 60))
    # concentric ring motif (register/coin feel), top area
    cx, cy = w // 2, 92
    for r, a in ((52, 40), (40, 60), (28, 90)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, a),
                  width=2)
    # "U" mark inside the rings
    fu = font(46)
    tb = d.textbbox((0, 0), "U", font=fu)
    d.text((cx - (tb[2] - tb[0]) / 2, cy - (tb[3] - tb[1]) / 2 - tb[1]), "U",
           font=fu, fill=WHITE)
    # wordmark near the bottom
    fw = font(26)
    d.text((14, 250), "Ural", font=fw, fill=WHITE)
    wb = d.textbbox((0, 0), "Ural", font=fw)
    d.text((14 + (wb[2] - wb[0]), 250), "Cash", font=fw, fill=TEAL400)
    d.text((15, 284), "ERP  —  نظام إدارة", font=font(12), fill=(255, 255, 255, 200))
    img.save(ASSETS / "wizard-large.bmp")


def small():
    w, h = 55, 58
    img = Image.new("RGB", (w, h), TEAL600)
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle([4, 4, w - 5, h - 5], radius=10, fill=TEAL900,
                        outline=TEAL400, width=2)
    fu = font(30)
    tb = d.textbbox((0, 0), "U", font=fu)
    d.text(((w - (tb[2] - tb[0])) / 2, (h - (tb[3] - tb[1])) / 2 - tb[1]), "U",
           font=fu, fill=WHITE)
    img.save(ASSETS / "wizard-small.bmp")


if __name__ == "__main__":
    large()
    small()
    print("Wrote", ASSETS / "wizard-large.bmp", "and wizard-small.bmp")
