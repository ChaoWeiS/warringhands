"""Little ground plants scattered over the grass: grass tufts, flower
clumps and a round bush, drawn in the hands' sticker style (warm ink
outline, soft two-tone shading, light from the upper left).

    python3 tools/make_plants.py   -> assets/env/plant_<name>.png (128 x 128)

Each stands on the bottom edge of its picture, centred.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/env"
SIZE = 128
K = 4  # drawn this many times larger, then shrunk (smooth edges)
INK = (72, 12, 10)
# Plants: a deep green-brown ink, so small tufts read as green, not dirt.
PLANT_INK = (46, 74, 30)
# Outline for pictures the game tints (it's multiplied by the ground colour).
TINTED_INK = (168, 180, 156)


def _blade(d, base, angle, length, width, fill):
    """One grass blade: a curved, tapering leaf from `base`."""
    pts_l, pts_r = [], []
    bend = 0.35 * (1 if angle > 0 else -1)
    for i in range(11):
        t = i / 10
        a = angle + bend * t * t
        x = base[0] + math.sin(a) * length * t
        y = base[1] - math.cos(a) * length * t
        w = width * (1 - t) ** 0.9
        nx, ny = math.cos(a), math.sin(a)
        pts_l.append((x - nx * w, y - ny * w))
        pts_r.append((x + nx * w, y + ny * w))
    d.polygon(pts_l + pts_r[::-1], fill=fill)


def _outline(shape: Image.Image, px: int, ink=PLANT_INK) -> Image.Image:
    """The shape with an ink outline round it."""
    alpha = shape.getchannel("A")
    grown = alpha.filter(ImageFilter.MaxFilter(px * 2 + 1))
    out = Image.new("RGBA", shape.size, ink + (0,))
    out.putalpha(grown)
    out.alpha_composite(shape)
    return out


def _finish(big: Image.Image, ink=PLANT_INK) -> Image.Image:
    big = _outline(big, 2 * K, ink)
    small = big.resize((SIZE, SIZE), Image.LANCZOS)
    return small


def tuft(light, dark, seed, blades=7, height=0.62, spread=0.9):
    rnd = random.Random(seed)
    s = SIZE * K
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base_y = s - 6 * K
    order = sorted(range(blades), key=lambda i: abs(i - blades / 2), reverse=True)
    for i in order:
        f = (i + 0.5) / blades - 0.5
        angle = f * spread * 1.6 + rnd.uniform(-0.12, 0.12)
        length = s * height * (1 - abs(f) * 0.7) * rnd.uniform(0.8, 1.05)
        bx = s / 2 + f * s * 0.32
        col = dark if abs(f) > 0.3 or i % 3 == 0 else light
        _blade(d, (bx, base_y), angle, length, s * 0.07, col)
        # Highlight down the left of the lighter blades.
        if col == light:
            _blade(d, (bx - s * 0.012, base_y - s * 0.03), angle, length * 0.75, s * 0.014,
                   tuple(min(255, c + 30) for c in light))
    return img


def flowers(petal, centre, seed, light=(150, 205, 120), dark=(105, 165, 85)):
    rnd = random.Random(seed)
    s = SIZE * K
    img = tuft(light, dark, seed, blades=7, height=0.42, spread=1.0)
    d = ImageDraw.Draw(img)
    heads = [(0.33, 0.47), (0.55, 0.36), (0.7, 0.52)]
    for hx, hy in heads:
        cx, cy = s * (hx + rnd.uniform(-0.03, 0.03)), s * (hy + rnd.uniform(-0.03, 0.03))
        d.line([(cx, cy), (cx + rnd.uniform(-8, 8) * K, s - 10 * K)], fill=dark, width=3 * K)
        r = s * 0.075
        for k in range(5):
            a = k * math.tau / 5 + 0.3
            px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
            d.ellipse([px - r * 0.75, py - r * 0.75, px + r * 0.75, py + r * 0.75], fill=petal)
        shade = tuple(max(0, c - 35) for c in petal)
        d.ellipse([cx - r * 0.2, cy + r * 0.05, cx + r * 1.2, cy + r * 1.2], fill=shade)
        for k in range(5):
            a = k * math.tau / 5 + 0.3
            px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
            if math.sin(a) < 0.3:
                d.ellipse([px - r * 0.7, py - r * 0.7, px + r * 0.7, py + r * 0.7], fill=petal)
        d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], fill=centre)
    return img


def bush(base, shade, light, seed):
    rnd = random.Random(seed)
    s = SIZE * K
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    blobs = [(0.30, 0.66, 0.2), (0.70, 0.66, 0.2), (0.5, 0.50, 0.25), (0.40, 0.72, 0.2), (0.62, 0.74, 0.19)]
    for x, y, r in blobs:
        d.ellipse([s * (x - r), s * (y - r), s * (x + r), s * (y + r)], fill=base)
    # Shade low and right, highlight top left of each lobe.
    mask = img.getchannel("A")
    sh = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    for x, y, r in blobs:
        ds.ellipse([s * (x - r * 0.6), s * (y - r * 0.2), s * (x + r * 1.05), s * (y + r * 1.05)], fill=shade)
    sh.putalpha(ImageChops.multiply(sh.getchannel("A"), mask))
    img.alpha_composite(sh)
    for x, y, r in blobs:
        ox, oy = s * (x - r * 0.35), s * (y - r * 0.4)
        rr = s * r * 0.32
        d.ellipse([ox - rr, oy - rr * 0.7, ox + rr, oy + rr * 0.7], fill=light)
    # Base flat on the ground.
    d.rectangle([0, s - 6 * K, s, s], fill=(0, 0, 0, 0))
    for _ in range(3):
        x, y = s * rnd.uniform(0.3, 0.7), s * rnd.uniform(0.45, 0.7)
        d.ellipse([x - 5 * K, y - 5 * K, x + 5 * K, y + 5 * K], fill=(255, 150, 175))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Grass tufts are drawn pale and tinted in the game by the ground
    # colour under them (a touch darker), so they sit in the grass instead
    # of standing out from it.
    for name, big in {
        "grass_1": tuft((255, 255, 250), (226, 234, 216), 1),
        "grass_2": tuft((250, 252, 244), (220, 230, 210), 2, blades=9, height=0.5, spread=1.1),
    }.items():
        _finish(big, TINTED_INK).save(OUT / f"plant_{name}.png")
        print("wrote", OUT / f"plant_{name}.png")
    pieces = {
        "flowers_pink": flowers((255, 160, 190), (255, 225, 120), 3),
        "flowers_white": flowers((255, 250, 240), (255, 205, 90), 4),
        "flowers_lilac": flowers((205, 175, 245), (255, 235, 150), 5),
        "bush": bush((122, 180, 98), (92, 148, 76), (170, 215, 140), 6),
    }
    for name, big in pieces.items():
        _finish(big).save(OUT / f"plant_{name}.png")
        print("wrote", OUT / f"plant_{name}.png")


if __name__ == "__main__":
    main()
