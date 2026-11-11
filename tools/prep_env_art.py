# Crops the environment art in art_source/env/ to its visible pixels and
# scales it for the game, into assets/env/. Run: python3 tools/prep_env_art.py
# Needs: pillow, numpy.
from PIL import Image
import numpy as np, os

SRC, DST = 'art_source/env', 'assets/env'
# name -> height in pixels in the game texture (None = keep)
SIZES = {'hq': 320, 'crystals_1': 220, 'crystals_2': 220, 'quarry': None, 'mill': None, 'forge': None,
         'pine_1': 320, 'pine_2': 320, 'rocks_1': None, 'rocks_2': None,
         'icon_stone': 'icon', 'icon_wood': 'icon', 'icon_metal': 'icon'}
ICON = 128  # resource icons: square, this many pixels
os.makedirs(DST, exist_ok=True)
for name, height in SIZES.items():
    im = Image.open(f'{SRC}/{name}.png').convert('RGBA')
    a = np.array(im)
    a[a[..., 3] < 8] = 0  # clear near-invisible specks (and their colour)
    ys, xs = np.nonzero(a[..., 3] > 0)
    im = Image.fromarray(a).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    if height == 'icon':
        side = max(im.width, im.height)
        sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        sq.resize((ICON, ICON), Image.LANCZOS).save(f'{DST}/{name}.png')
        print(name, (ICON, ICON))
        continue
    if height and im.height > height:
        im = im.resize((round(im.width * height / im.height), height), Image.LANCZOS)
    # 2 px clear border so mipmaps don't bleed the edge.
    out = Image.new('RGBA', (im.width + 4, im.height + 4), (0, 0, 0, 0))
    out.paste(im, (2, 2))
    out.save(f'{DST}/{name}.png')
    print(name, out.size)

# The red team's town hall: the same picture with every blue (flag,
# banners, windows) turned red. Blue team uses hq.png as it is.
im = Image.open(f'{DST}/hq.png').convert('RGBA')
a = np.array(im).astype(float) / 255.0
r, g, b = a[..., 0], a[..., 1], a[..., 2]
mx, mn = a[..., :3].max(axis=2), a[..., :3].min(axis=2)
sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
# Hue (0..1) of each pixel.
d = np.maximum(mx - mn, 1e-6)
hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
blue = (hue > 0.52) & (hue < 0.665) & (sat > 0.18)  # not the lavender roof
# Same brightness and strength, rose-red hue (h = 0.97).
v, s2 = mx, np.clip(sat * 1.15, 0, 1)
f = 6 * 0.97 - 5
out = a.copy()
out[..., 0] = np.where(blue, v, r)
out[..., 1] = np.where(blue, v * (1 - s2), g)
out[..., 2] = np.where(blue, v * (1 - s2 * f), b)
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA').save(f'{DST}/hq_red.png')
print('hq_red', im.size)

# Round buttons: cropped to the button, 192 px. The cancel button's cold
# grey frame and white middle are warmed up to match the other two (a lilac
# frame, cream middle), keeping its shading.
BUTTON = 192
for name in ['button_build', 'button_attack', 'button_cancel']:
    im = Image.open(f'{SRC}/{name}.png').convert('RGBA')
    a = np.array(im).astype(float)
    a[a[..., 3] < 200, 3] = 0  # drop the faint glow baked onto black
    if name == 'button_cancel':
        rgb = a[..., :3]
        lum = rgb @ np.array([0.299, 0.587, 0.114])
        sat = rgb.max(axis=2) - rgb.min(axis=2)
        opaque = a[..., 3] > 0
        frame = opaque & (rgb[..., 2] - rgb[..., 0] > 12) & (lum > 140)
        middle = opaque & (lum > 228) & (sat < 22) & ~frame
        lilac = np.array([238, 222, 255]) / 226.0  # shade of the frame's own brightness
        cream = np.array([253, 246, 226]) / 248.0
        rgb[frame] = np.clip(lum[frame][:, None] * lilac, 0, 255)
        rgb[middle] = np.clip(lum[middle][:, None] * cream, 0, 255)
        a[..., :3] = rgb
    a[a[..., 3] == 0] = 0
    out = Image.fromarray(a.astype(np.uint8), 'RGBA')
    out = out.crop(out.getbbox())
    side = max(out.size)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.paste(out, ((side - out.width) // 2, (side - out.height) // 2))
    sq.resize((BUTTON, BUTTON), Image.LANCZOS).save(f'{DST}/{name}.png')
    print(name, BUTTON)
