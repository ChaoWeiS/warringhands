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
