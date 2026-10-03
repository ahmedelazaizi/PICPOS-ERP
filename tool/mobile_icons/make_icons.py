"""Launcher-icon sources for mobile_admin (PicPos إدارة) and mobile_pos (PicPos كاشير).

ARCHITECTURE-M §4.3 "Icons": adaptive icon = assets/brand/picpos/logo.png mark
inside the 66 dp safe zone on a white background, a brand-blue (#0250D3)
badge (M-A: chart glyph, M-B: receipt glyph) and an Android 13 monochrome
layer. Writes, per app, assets/icon/{foreground,monochrome,legacy}.png; then
run `dart run flutter_launcher_icons` in the app folder.

Usage (Pillow required):  python tool/mobile_icons/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "assets" / "brand" / "picpos" / "logo.png"
BLUE = (2, 80, 211, 255)
WHITE = (255, 255, 255, 255)
SIZE = 1024  # 108 dp canvas; the safe zone is the centred 66 dp circle (r ≈ 313 px)


def logo_rgba() -> Image.Image:
    """The logo on transparent: un-mixes the white background into alpha."""
    src = Image.open(LOGO).convert("RGBA")
    out = Image.new("RGBA", src.size)
    px, po = src.load(), out.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = px[x, y]
            alpha = (255 - min(r, g, b)) * a // 255
            if alpha == 0:
                continue
            k = alpha / 255.0
            un = lambda c: max(0, min(255, round((c - (1 - k) * 255) / k)))
            po[x, y] = (un(r), un(g), un(b), alpha)
    return out


def chart_glyph(d: ImageDraw.ImageDraw, cx: int, cy: int, fill) -> None:
    base = cy + 42
    for i, h in enumerate((44, 70, 96)):
        x0 = cx - 48 + i * 34
        d.rounded_rectangle((x0, base - h, x0 + 24, base), radius=6, fill=fill)


def receipt_glyph(d: ImageDraw.ImageDraw, cx: int, cy: int, fill, hole) -> None:
    left, right, top, bottom = cx - 38, cx + 38, cy - 52, cy + 40
    d.rectangle((left, top, right, bottom), fill=fill)
    teeth = [(left, bottom)]
    step = (right - left) / 4
    for i in range(4):
        teeth += [(left + step * i + step / 2, bottom + 14), (left + step * (i + 1), bottom)]
    d.polygon(teeth, fill=fill)
    for i, w in enumerate((52, 52, 34)):
        y = top + 18 + i * 20
        d.rounded_rectangle((left + 12, y, left + 12 + w, y + 8), radius=4, fill=hole)


def compose(glyph: str, mono: bool) -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    logo = logo_rgba()
    w = 520
    h = round(logo.height * w / logo.width)
    logo = logo.resize((w, h), Image.LANCZOS)
    if mono:
        logo = Image.merge("RGBA", (*Image.new("RGB", logo.size, (255, 255, 255)).split(), logo.split()[3]))
    canvas.alpha_composite(logo, ((SIZE - w) // 2, 440 - h // 2))
    d = ImageDraw.Draw(canvas)
    cx, cy, r = 680, 660, 85
    ring = (0, 0, 0, 0) if mono else WHITE
    d.ellipse((cx - r - 10, cy - r - 10, cx + r + 10, cy + r + 10), fill=ring)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE if mono else BLUE)
    glyph_fill = (0, 0, 0, 0) if mono else WHITE
    if glyph == "chart":
        chart_glyph(d, cx, cy, glyph_fill)
    else:
        receipt_glyph(d, cx, cy, glyph_fill, (0, 0, 0, 0) if mono else BLUE)
    return canvas


def legacy(fg: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(bg).rounded_rectangle((40, 40, SIZE - 40, SIZE - 40), radius=200, fill=WHITE)
    bg.alpha_composite(fg)
    return bg


def main() -> None:
    for app, glyph in (("mobile_admin", "chart"), ("mobile_pos", "receipt")):
        out = ROOT / app / "assets" / "icon"
        out.mkdir(parents=True, exist_ok=True)
        fg = compose(glyph, mono=False)
        fg.save(out / "foreground.png")
        compose(glyph, mono=True).save(out / "monochrome.png")
        legacy(fg).save(out / "legacy.png")
        print(f"{app}: {out}")


if __name__ == "__main__":
    main()
