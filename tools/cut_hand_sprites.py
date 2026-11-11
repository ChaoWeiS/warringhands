# Cuts the hand frames out of art_source/hands_sheet_v2.png into
# assets/units/hands.png.
#   python3 tools/cut_hand_sprites.py art_source/hands_sheet_v2.png assets/units/hands.png
# Needs: pillow, numpy, scipy.
"""The sheet: 5 panels (idle, moving, attack, defend, dying) x 3 rows (rock,
paper, scissors) x 5 numbered frames, on white, split by thin coloured lines.

Atlas: 5 columns (frames) x 15 rows of CELL px cells; row = kind * 5 + state
(state: 0 idle, 1 move, 2 attack, 3 defend, 4 death).

Background: alpha comes from how far a pixel is from white, so motion
trails, dust and the ghost stay see-through; anything inside a dark outline
(the hands, the POW! burst) is solid. Each kind is scaled by one factor (so
its idle hand matches HAND_HEIGHT) and every frame keeps its place inside its
sheet cell, so the hop of the moving frames and the lunge of the attack stay
as drawn. The ground line (bottom of the idle hands) sits GROUND px above the
bottom of the atlas cell.
"""
from PIL import Image
import numpy as np, sys
from scipy import ndimage as ndi

CELL = 192
HAND_HEIGHT = 103   # px, idle hand in the atlas (same size as before)
GROUND = 24         # px above the cell bottom (room for squashed / fallen frames)
# Sheet grid (pixels in hands_sheet_v2.png).
# Cell lines of each panel (x), measured from the sheet; cells aren't evenly spaced.
PANELS = [
    [138, 254, 372, 490, 609, 728],      # idle
    [744, 860, 978, 1099, 1218, 1340],   # moving
    [1354, 1469, 1593, 1718, 1842, 1953],  # attack
    [1968, 2080, 2195, 2311, 2426, 2533],  # defend
    [2545, 2651, 2754, 2857, 2961, 3062],  # dying
]
ROWS = [(122, 395), (404, 676), (688, 977)]
BADGE = 51          # start just under the numbered badge (art starts lower)
EDGE_PAD = 1        # px kept clear of a line (its anti-aliased edge)
ROW_PAD = 6         # px above the row's bottom border

src = np.array(Image.open(sys.argv[1]).convert('RGB')).astype(float)
lum = src @ np.array([0.299, 0.587, 0.114])


def line_band(x_centre, y0, y1):
    """The pixel columns of a cell line near x_centre: the ones painted (not
    white) nearly all the way down the row. Art stops short of that."""
    painted = (src[y0:y1, :].min(axis=2) < 235).mean(axis=0)
    cols = [x for x in range(x_centre - 8, x_centre + 9) if painted[x] > 0.85]
    if not cols:
        return x_centre, x_centre
    # The run of line columns containing (or nearest) the centre.
    cols.sort(key=lambda x: abs(x - x_centre))
    lo = hi = cols[0]
    while lo - 1 in cols:
        lo -= 1
    while hi + 1 in cols:
        hi += 1
    return lo, hi


def cells(lines, y0, y1):
    """x ranges of a panel's 5 cells in one row, right up to (not including)
    the lines between them."""
    bands = [line_band(x, y0, y1) for x in lines]
    return [(bands[i][1] + 1 + EDGE_PAD, bands[i + 1][0] - EDGE_PAD) for i in range(5)]


def cut(x0, x1, y0, y1):
    """RGBA of one cell, background removed, and its solid mask."""
    c = src[y0:y1, x0:x1]
    L = lum[y0:y1, x0:x1]
    lo = c.min(axis=2)
    whiteness_alpha = np.clip((250 - lo) / 55.0, 0, 1)
    # Solid: outline or clearly coloured paint (skin, effects), small gaps
    # closed, holes (highlights inside a hand) filled...
    paint = (L < 170) | (lo < 205)
    solid = ndi.binary_fill_holes(ndi.binary_closing(paint, iterations=3))
    # ...except big pure-white areas that got closed in (paper between spikes).
    white = solid & ~paint & (lo > 238)
    lab, n = ndi.label(white)
    if n:
        sizes = ndi.sum(white, lab, range(1, n + 1))
        solid &= ~np.isin(lab, np.nonzero(sizes > 300)[0] + 1)
    alpha = np.maximum(whiteness_alpha, solid.astype(float))
    alpha[alpha < 0.08] = 0
    # Un-mix half see-through pixels (trails, dust, ghost) from the paper.
    a3 = np.maximum(alpha, 1e-3)[..., None]
    rgb = np.clip((c - (1 - a3) * 255) / a3, 0, 255)
    rgb[alpha == 0] = 0
    return np.dstack([rgb, alpha * 255]).astype(np.uint8), solid


atlas = Image.new('RGBA', (CELL * 5, CELL * 15), (0, 0, 0, 0))
clipped = []
for k, (ry0, ry1) in enumerate(ROWS):
    y0, y1 = ry0 + BADGE, ry1 - ROW_PAD
    # Scale and ground line for this kind, from its idle frames.
    heights, bottoms = [], []
    for (x0, x1) in cells(PANELS[0], y0, y1):
        _, solid = cut(x0, x1, y0, y1)
        lab, n = ndi.label(solid)
        sizes = ndi.sum(solid, lab, range(1, n + 1))
        body = lab == (np.argmax(sizes) + 1)
        ys = np.nonzero(body.any(axis=1))[0]
        heights.append(ys.max() - ys.min() + 1)
        bottoms.append(ys.max() + 1)
    s = HAND_HEIGHT / float(np.median(heights))
    ground = float(np.median(bottoms))  # in cell pixels
    for state, panel in enumerate(PANELS):
        for f, (x0, x1) in enumerate(cells(panel, y0, y1)):
            rgba, _ = cut(x0, x1, y0, y1)
            img = Image.fromarray(rgba, 'RGBA')
            img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
            # Cell centre on the atlas cell centre; ground line on GROUND.
            ox = round(CELL / 2 - img.width / 2)
            oy = round(CELL - GROUND - ground * s)
            cell = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
            cell.alpha_composite(img.crop((-ox, -oy, -ox + CELL, -oy + CELL)))
            atlas.paste(cell, (f * CELL, (k * 5 + state) * CELL))
            edge = np.array(cell)[..., 3]
            if edge[-1].max() > 40 or edge[0].max() > 40:
                clipped.append((k, state, f))
atlas.save(sys.argv[2])
print('atlas', atlas.size, 'cut off at top/bottom (kind, state, frame):', clipped)
