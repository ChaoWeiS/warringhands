# Cuts one animation (3 rows: rock, paper, scissors; 5 frames each) out of a
# gridded sprite sheet on a white background into rows of the unit atlas.
#
#   python3 tools/cut_grid_sprites.py SHEET ATLAS FIRST_ROW STEP [--trail]
#
# Frame k (kind) of the sheet goes to atlas row FIRST_ROW + k * STEP:
#   attack: art_source/attack_sheet.png assets/units/hands.png 1 3 --trail
#   death:  art_source/death_sheet.png  assets/units/hands.png 9 1
# Needs: pillow, numpy, scipy.
"""Background = everything light reachable from the cell's border without
crossing the dark outline. Inside the outline is solid. With --trail, tinted
pixels outside the outline (motion trails) are kept, half see-through.

Each row is scaled so its first frame is as tall as that kind's idle frames,
and frames keep about half their sideways motion inside the row (a lunge),
so it fits a cell; the hand itself is never cut off. Frames sit 2 px above the bottom of their 128 px cell.
"""
from PIL import Image
import numpy as np, sys
from scipy import ndimage as ndi

sheet_path, atlas_path, first_row, step = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
keep_trail = '--trail' in sys.argv
CELL = 128
ROWS_TOTAL = 12  # 9 (idle/attack/defend x 3 kinds) + 3 death rows
DAMP = 0.55  # how much of the sheet's sideways motion to keep
OUTLINE_RGB = np.array([60, 32, 26], float)

src = np.array(Image.open(sheet_path).convert('RGB')).astype(float)
H, W, _ = src.shape
lum = src @ np.array([0.299, 0.587, 0.114])


def grid_lines(profile, n):
    """Split points of the n cells, found from the grey grid lines."""
    edges = np.linspace(0, len(profile), n + 1)
    out = []
    for e in edges:
        lo, hi = int(max(0, e - 12)), int(min(len(profile), e + 12))
        out.append(lo + int(np.argmax(profile[lo:hi])) if hi > lo else int(e))
    return out


greyness = (np.abs(lum - 254) > 8)
xs = grid_lines(greyness.mean(axis=0), 5)
ys = grid_lines(greyness.mean(axis=1), 3)
M = 7  # skip the grid line itself

atlas = Image.open(atlas_path).convert('RGBA')
if atlas.height < CELL * ROWS_TOTAL:
    bigger = Image.new('RGBA', (CELL * 5, CELL * ROWS_TOTAL), (0, 0, 0, 0))
    bigger.paste(atlas, (0, 0))
    atlas = bigger
A = np.array(atlas)


def idle_height(kind):
    hs = []
    for f in range(5):
        a = A[kind * 3 * CELL:(kind * 3 + 1) * CELL, f * CELL:(f + 1) * CELL, 3]
        r = np.nonzero(a.max(axis=1) > 128)[0]
        hs.append(r.max() - r.min() + 1)
    return float(np.median(hs))


for k in range(3):
    cuts = []
    for f in range(5):
        y0, y1, x0, x1 = ys[k] + M, ys[k + 1] - M, xs[f] + M, xs[f + 1] - M
        c, L = src[y0:y1, x0:x1], lum[y0:y1, x0:x1]
        sat = c.max(axis=2) - c.min(axis=2)
        dark = (L < 110) & (c.max(axis=2) < 150)
        # Strong skin colour also stops the flood: on motion-blurred frames
        # the outline has gaps, but the trail is much paler than the hand.
        light = ~dark & (sat <= 50)
        border = np.zeros_like(light)
        border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
        lab, _ = ndi.label(light)
        bg = np.isin(lab, np.unique(lab[border & light]))
        solid = ~bg
        # Keep the biggest piece (the hand), drop specks.
        lab, n = ndi.label(solid)
        if n > 1:
            sz = ndi.sum(solid, lab, range(1, n + 1))
            solid = lab == (np.argmax(sz) + 1)
            solid = ndi.binary_fill_holes(solid)
        alpha = solid.astype(float)
        rgb = c.copy()
        # Anti-aliased ring just outside the outline: outline colour, alpha by darkness.
        ring = ndi.binary_dilation(solid, iterations=2) & ~solid
        ra = np.clip((235 - L) / 150, 0, 1)
        alpha[ring] = ra[ring]
        rgb[ring] = OUTLINE_RGB
        if keep_trail:
            # Tinted (not white, not grey) pixels outside: the motion trail.
            trail = bg & ~ring & (sat > 12) & (L > 150)
            trail = ndi.binary_opening(trail, iterations=1)
            ta = np.clip((255 - c.min(axis=2)) / 255 * 2.2, 0, 0.75)
            alpha[trail] = ta[trail]
            # Un-mix from white so it doesn't look washed out on grass.
            a3 = np.maximum(ta[trail], 1e-3)[:, None]
            rgb[trail] = np.clip((c[trail] - (1 - a3) * 255) / a3, 0, 255)
        r = np.nonzero(solid)
        cuts.append({'rgb': rgb, 'alpha': alpha, 'top': r[0].min(), 'bottom': r[0].max(),
                     'left': r[1].min(), 'right': r[1].max(), 'cx': (r[1].min() + r[1].max()) / 2,
                     'cy': (r[0].min() + r[0].max()) / 2})
    s = idle_height(k) / (cuts[0]['bottom'] - cuts[0]['top'] + 1)
    bottom = max(c['bottom'] for c in cuts)
    cx_mean = sum(c['cx'] for c in cuts) / 5
    for f, c in enumerate(cuts):
        h, w = c['alpha'].shape
        img = Image.fromarray(np.dstack([c['rgb'], c['alpha'] * 255]).astype(np.uint8), 'RGBA')
        img = img.resize((round(w * s), round(h * s)), Image.LANCZOS)
        # Row centred, with its movement (lunge, fall) kept but damped so
        # it fits a cell; lowest point of the row 2 px above the cell bottom.
        ox = CELL / 2 - (cx_mean + DAMP * (c['cx'] - cx_mean)) * s
        oy = CELL - 2 - (bottom + 1) * s
        # The hand itself must stay inside the cell (a trail may be cut).
        ox = min(max(ox, 1 - c['left'] * s), CELL - 1 - (c['right'] + 1) * s)
        oy = min(max(oy, 1 - c['top'] * s), CELL - 2 - (c['bottom'] + 1) * s)
        ox, oy = round(ox), round(oy)
        cell = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        cell.alpha_composite(img.crop((-ox, -oy, -ox + CELL, -oy + CELL)))
        row = first_row + k * step
        atlas.paste(cell, (f * CELL, row * CELL))

atlas.save(atlas_path)
print('rows', [first_row + k * step for k in range(3)], 'atlas', atlas.size)
