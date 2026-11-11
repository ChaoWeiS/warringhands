#!/usr/bin/env python3
"""Hold, Settings and Surrender buttons in the same frame as Build and Attack.

The Build button's frame (rounded border, soft cream face) is taken from
assets/env/button_build.png, its pick and hammer painted over with the face
colour, the border turned lilac, and a symbol put in the middle: the
paper hand's open palm on a red stop octagon (Hold), a gear, or a white
flag (Surrender). (no_sign()
makes the old cancel picture, from art_source/env/button_cancel_sign.png.)

Run from the project root: python3 tools/make_buttons.py
"""
import colorsys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

SIZE = 192
LILAC_HUE = 268 / 360.0


def empty_frame() -> np.ndarray:
    """The Build button with its tools painted out and its border lilac."""
    im = np.array(Image.open("assets/env/button_build.png").convert("RGBA")).astype(float)
    rgb = im[..., :3] / 255.0
    hsv = np.array([colorsys.rgb_to_hsv(*p) for p in rgb.reshape(-1, 3)]).reshape(rgb.shape)
    # Border: orange / dark-orange pixels joined to the outside of the button.
    orange = (hsv[..., 1] > 0.33) & (hsv[..., 0] < 0.13) & (im[..., 3] > 0)
    outside = im[..., 3] < 10
    lab, _ = ndi.label(orange | outside)
    edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    frame = np.isin(lab, list(edge_labels)) & ~outside
    # Its antialiased inner edge too (a pixel or two of blend into the face).
    frame_wide = ndi.binary_dilation(frame, iterations=2) & ~outside
    face = ndi.binary_fill_holes(frame | outside) == False  # noqa: E712
    face = ~(frame | outside)
    # The face: soft cream, a touch darker towards the top (like the art).
    cream_top = np.array([253, 236, 203]) / 255.0
    cream = np.array([252, 240, 213]) / 255.0
    ys = np.linspace(0, 1, SIZE)[:, None, None]
    shade = np.clip((ys - 0.1) / 0.15, 0, 1)
    face_rgb = cream_top * (1 - shade) + cream * shade
    out = rgb.copy()
    out[face] = np.broadcast_to(face_rgb, rgb.shape)[face]
    # Blend pixels on the inner edge of the border towards the face.
    blend = frame_wide & ~frame
    out[blend] = (out[blend] + np.broadcast_to(face_rgb, rgb.shape)[blend]) / 2
    # Border to lilac: same lightness pattern, lilac hue, softer colour.
    for y, x in zip(*np.nonzero(frame | blend)):
        h, s, v = colorsys.rgb_to_hsv(*out[y, x])
        if s > 0.12:
            out[y, x] = colorsys.hsv_to_rgb(LILAC_HUE, min(1.0, s * 0.42), min(1.0, v * (0.98 if s < 0.7 else 0.62)))
    alpha = im[..., 3:4] / 255.0
    return np.concatenate([out, alpha], axis=2)


def no_sign() -> Image.Image:
    """The red no sign (with its dark outline) from the old cancel art."""
    src = Image.open("art_source/env/button_cancel_sign.png").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    a = np.array(src).astype(int)
    red = (a[..., 0] > 200) & (a[..., 1] < 130) & (a[..., 2] < 130)
    centre = np.zeros(red.shape, bool)
    centre[40:152, 40:152] = True
    red &= centre
    ys, xs = np.nonzero(red)
    cy, cx = ys.mean(), xs.mean()
    r = np.percentile(np.sqrt((ys - cy) ** 2 + (xs - cx) ** 2), 99.5) + 4.0  # + the outline
    mask = Image.new("L", (SIZE * 4, SIZE * 4), 0)
    ImageDraw.Draw(mask).ellipse([(cx - r) * 4, (cy - r) * 4, (cx + r) * 4, (cy + r) * 4], fill=255)
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)
    # Cream inside the ring: make it the face's cream.
    inside = (a[..., 0] > 235) & (a[..., 1] > 225) & (a[..., 2] > 190)
    a[inside, :3] = [252, 240, 213]
    sign = Image.fromarray(a.astype(np.uint8), "RGBA")
    sign.putalpha(mask)
    # Centre it on the button.
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(sign, (round(SIZE / 2 - cx), round(SIZE / 2 - cy)))
    return out


def gear() -> Image.Image:
    """A soft blue-grey gear with a dark outline, drawn big then shrunk."""
    k = 4
    big = SIZE * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    c = big / 2
    teeth, r_out, r_in, r_hole = 8, 58 * k, 44 * k, 17 * k
    pts = []
    for i in range(teeth * 4):
        ang = i / (teeth * 4) * 2 * np.pi
        r = r_out if (i % 4) in (1, 2) else r_in
        pts.append((c + r * np.cos(ang), c + r * np.sin(ang)))
    outline = (92, 37, 28, 255)
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=outline)
    inner = Image.new("L", (big, big), 0)
    shrink = [(c + (x - c) * 0.9, c + (y - c) * 0.9) for x, y in pts]
    ImageDraw.Draw(inner).polygon(shrink, fill=255)
    body = Image.new("RGBA", (big, big), (176, 183, 214, 255))
    img.paste(body, (0, 0), inner)
    d = ImageDraw.Draw(img)
    d.ellipse([c - r_hole - 5 * k, c - r_hole - 5 * k, c + r_hole + 5 * k, c + r_hole + 5 * k], fill=outline)
    d.ellipse([c - r_hole, c - r_hole, c + r_hole, c + r_hole], fill=(252, 240, 213, 255))
    # A highlight on the upper left.
    hl = Image.new("L", (big, big), 0)
    ImageDraw.Draw(hl).pieslice([c - r_in * 0.8, c - r_in * 0.8, c + r_in * 0.8, c + r_in * 0.8], 190, 260, fill=110)
    hl = hl.filter(ImageFilter.GaussianBlur(6 * k))
    shine = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    shine.putalpha(Image.fromarray((np.array(hl) * (np.array(inner) > 0)).astype(np.uint8)))
    img.alpha_composite(shine)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def stop_palm() -> Image.Image:
    """Hold: the paper hand's open palm ("halt!") on a red stop octagon."""
    import os
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    import cut_hand_sprites as cutter
    k = 4
    big = SIZE * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    c = big / 2
    def octagon(r):
        return [(c + r * np.cos(np.pi / 8 + i * np.pi / 4), c + r * np.sin(np.pi / 8 + i * np.pi / 4)) for i in range(8)]
    d = ImageDraw.Draw(img)
    d.polygon(octagon(64 * k), fill=(92, 37, 28, 255))      # outline
    d.polygon(octagon(60 * k), fill=(255, 255, 255, 255))   # white rim
    d.polygon(octagon(54 * k), fill=(92, 37, 28, 255))
    d.polygon(octagon(51 * k), fill=(246, 92, 80, 255))     # red face
    # Soft shine on the upper left of the face.
    hl = Image.new("L", (big, big), 0)
    ImageDraw.Draw(hl).ellipse([c - 44 * k, c - 46 * k, c + 6 * k, c - 8 * k], fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(8 * k))
    face = Image.new("L", (big, big), 0)
    ImageDraw.Draw(face).polygon(octagon(51 * k), fill=255)
    shine = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    shine.putalpha(Image.fromarray((np.array(hl).astype(int) * (np.array(face) > 0)).astype(np.uint8)))
    img.alpha_composite(shine)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    # The open palm (paper idle frame 4: a thumb and four fingers).
    ry0, ry1 = cutter.ROWS[1]
    y0, y1 = ry0 + cutter.BADGE, ry1 - cutter.ROW_PAD
    x0, x1 = cutter.cells(cutter.PANELS[0], y0, y1)[3]
    rgba, _ = cutter.cut(x0, x1, y0, y1)
    rgba = cutter.erase(rgba, cutter.ERASE[(1, 0, 3)], x0, y0)
    hand = Image.fromarray(rgba, "RGBA")
    hand = hand.crop(hand.getbbox())
    h = 86
    hand = hand.resize((round(hand.width * h / hand.height), h), Image.LANCZOS)
    img.alpha_composite(hand, (round(SIZE / 2 - hand.width / 2), round(SIZE / 2 - h / 2) + 2))
    return img


def white_flag() -> Image.Image:
    """Surrender: a white flag on a wooden pole."""
    k = 4
    big = SIZE * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (92, 37, 28, 255)
    # Pole (wood), with a round knob on top.
    px, top, bottom = 62 * k, 40 * k, 156 * k
    d.rounded_rectangle([px - 7 * k, top, px + 7 * k, bottom], radius=6 * k, fill=outline)
    d.rounded_rectangle([px - 4 * k, top + 3 * k, px + 4 * k, bottom - 3 * k], radius=4 * k, fill=(214, 160, 104, 255))
    d.ellipse([px - 11 * k, top - 14 * k, px + 11 * k, top + 8 * k], fill=outline)
    d.ellipse([px - 8 * k, top - 11 * k, px + 8 * k, top + 5 * k], fill=(240, 196, 92, 255))
    # The flag: a wavy white cloth from the pole.
    def cloth(grow):
        pts = []
        x0, x1 = px + 4 * k, 150 * k
        y_top, y_bot = 48 * k, 112 * k
        n = 40
        for i in range(n + 1):
            t = i / n
            x = x0 + (x1 - x0) * t
            pts.append((x, y_top + np.sin(t * 2 * np.pi) * 7 * k * t - grow))
        for i in range(n, -1, -1):
            t = i / n
            x = x0 + (x1 - x0) * t
            pts.append((x, y_bot + np.sin(t * 2 * np.pi + 0.6) * 7 * k * t + grow))
        return [(x + (grow if x > px + 10 * k else 0), y) for x, y in pts]
    d.polygon(cloth(4 * k), fill=outline)
    d.polygon(cloth(0), fill=(255, 255, 255, 255))
    # A soft grey fold in the cloth.
    fold = Image.new("L", (big, big), 0)
    ImageDraw.Draw(fold).ellipse([100 * k, 60 * k, 135 * k, 110 * k], fill=60)
    fold = fold.filter(ImageFilter.GaussianBlur(7 * k))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(cloth(0), fill=255)
    shade = Image.new("RGBA", (big, big), (190, 186, 214, 255))
    shade.putalpha(Image.fromarray((np.array(fold).astype(int) * (np.array(mask) > 0)).astype(np.uint8)))
    img.alpha_composite(shade)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def save(symbol: Image.Image, path: str) -> None:
    frame = Image.fromarray((empty_frame() * 255).round().astype(np.uint8), "RGBA")
    frame.alpha_composite(symbol)
    frame.save(path)
    print("wrote", path)


if __name__ == "__main__":
    save(stop_palm(), "assets/env/button_hold.png")
    save(gear(), "assets/env/button_settings.png")
    save(white_flag(), "assets/env/button_surrender.png")
