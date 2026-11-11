# Cuts the hand frames out of art_source/hands_sheet.png into
# assets/units/hands.png. Run: python3 tools/cut_hand_sprites.py art_source/hands_sheet.png assets/units/hands.png
# Needs: pillow, numpy, scipy, opencv-python.
"""Cuts the 45 hand frames out of the sprite sheet into a transparent atlas.

Atlas layout: 5 columns (frames) x 9 rows of 128 px cells.
Row = kind * 3 + state, kind: 0 rock, 1 paper, 2 scissors; state: 0 idle, 1 attack, 2 defend.
Each frame's bottom sits 2 px above the bottom of its cell, centred horizontally.
"""
from PIL import Image; import numpy as np, sys, cv2
from scipy import ndimage as ndi

src = np.array(Image.open(sys.argv[1]).convert('RGB'))
im = src.astype(int); R, G, B = im[..., 0], im[..., 1], im[..., 2]
lum = 0.299 * R + 0.587 * G + 0.114 * B
# Strict skin test finds the frames; a looser one shapes each cut-out.
strict = (R > 200) & (G > 140) & (B > 110) & (R >= G) & (G >= B - 10) & ((R - B) > 40)
strict[:, :120] = False; strict[:140, :] = False
skin = (R > 170) & (G > 110) & ((R - B) > 35) & (R >= G)
OUTLINE = 80      # darker than this next to a hand = its outline
SOFT = 110        # between OUTLINE and SOFT = half-transparent edge
OUTLINE_RGB = np.array([45, 24, 20])

lab, n = ndi.label(strict)
sizes = ndi.sum(strict, lab, range(1, n + 1)); objs = ndi.find_objects(lab)
comps = [(i + 1, objs[i]) for i, s in enumerate(sizes) if s > 500]
rows = [(150, 320), (400, 620), (700, 900)]
CELL = 128
atlas = Image.new('RGBA', (CELL * 5, CELL * 9), (0, 0, 0, 0))

# Group pieces into frames (pieces that overlap horizontally = same frame).
frames_by_row = []
for (y0, y1) in rows:
    cs = sorted([c for c in comps if y0 <= (c[1][0].start + c[1][0].stop) / 2 <= y1], key=lambda c: c[1][1].start)
    clusters = []
    for lid, sl in cs:
        if clusters and sl[1].start < clusters[-1]['x1']:
            cl = clusters[-1]
            cl['ids'].append(lid); cl['y0'] = min(cl['y0'], sl[0].start); cl['y1'] = max(cl['y1'], sl[0].stop)
            cl['x0'] = min(cl['x0'], sl[1].start); cl['x1'] = max(cl['x1'], sl[1].stop)
        else:
            clusters.append({'ids': [lid], 'y0': sl[0].start, 'y1': sl[0].stop, 'x0': sl[1].start, 'x1': sl[1].stop})
    assert len(clusters) == 15, len(clusters)
    frames_by_row.append(clusters)

# Body of every frame (skin near its own pieces, holes filled), whole sheet.
bodies = []
for clusters in frames_by_row:
    for cl in clusters:
        own = np.isin(lab, cl['ids'])
        body = skin & ndi.binary_dilation(own, iterations=6)
        body = ndi.binary_fill_holes(ndi.binary_closing(body, iterations=3))
        bodies.append(body)
# Each pixel belongs to the nearest frame body.
dists = np.stack([ndi.distance_transform_edt(~b) for b in bodies])
owner = np.argmin(dists, axis=0)

idx = 0
for k, clusters in enumerate(frames_by_row):
    for f, cl in enumerate(clusters):
        body = bodies[idx]; mine = owner == idx; idx += 1
        # The dark outline is the boundary: bright skin + nearby dark outline,
        # tiny gaps closed, then everything inside filled (shaded skin, faces).
        core = np.isin(lab, cl['ids'])
        dark = (lum < OUTLINE) & ndi.binary_dilation(core, iterations=14) & mine
        shape = ndi.binary_closing(core | dark, iterations=2)
        solid = ndi.binary_fill_holes(shape) & mine
        lb, nb = ndi.label(solid)
        if nb > 1:
            keep = np.unique(lb[core & solid]); keep = keep[keep > 0]
            solid = np.isin(lb, keep)
        # Drop thin dark specks that aren't attached to the outline ring.
        solid = ndi.binary_opening(solid, iterations=1) | (solid & ndi.binary_dilation(core, iterations=3))
        # Rock (a convex fist): patch notches where the artwork's outline is
        # open, by filling to the convex outline, painting skin from the
        # surrounding hand and outline along the patch's edge.
        patch = np.zeros_like(solid); patch_edge = np.zeros_like(solid)
        if k == 0:
            pts = np.argwhere(solid)[:, ::-1].astype(np.int32)
            hull = np.zeros(solid.shape, np.uint8)
            cv2.fillConvexPoly(hull, cv2.convexHull(pts), 1)
            hull = hull.astype(bool)
            added = hull & ~solid
            if 0 < added.sum() < 0.4 * solid.sum():
                patch_edge = added & ~ndi.binary_erosion(hull, iterations=3)
                patch = added & ~patch_edge
                solid = solid | added
        # Soft edge: one more pixel ring, partly transparent by brightness.
        edge = ndi.binary_dilation(solid, iterations=1) & ~solid & mine
        alpha = solid.astype(float)
        alpha[edge] = np.clip((SOFT - lum[edge]) / (SOFT - OUTLINE), 0, 1)
        rgb = src.astype(float).copy()
        rgb[edge] = OUTLINE_RGB  # edge pixels take the outline colour (no glow halo)
        if patch.any():
            # Colour of the nearest real skin pixel (never the dark outline).
            skin_px = solid & ~patch & ~patch_edge & skin & (lum > 150)
            _, (iy, ix) = ndi.distance_transform_edt(~skin_px, return_indices=True)
            rgb[patch] = src[iy[patch], ix[patch]]
            rgb[patch_edge] = OUTLINE_RGB
        ys, xs = np.nonzero(alpha > 0)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rgba = np.dstack([rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1] * 255]).astype(np.uint8)
        img = Image.fromarray(rgba, 'RGBA')
        if img.width > CELL - 4 or img.height > CELL - 4:
            s = min((CELL - 4) / img.width, (CELL - 4) / img.height)
            img = img.resize((int(img.width * s), int(img.height * s)), Image.LANCZOS)
        state, frame = f // 5, f % 5
        cell = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        cell.alpha_composite(img, ((CELL - img.width) // 2, CELL - 2 - img.height))
        atlas.alpha_composite(cell, (frame * CELL, (k * 3 + state) * CELL))

atlas.save(sys.argv[2])
# Previews on game-like backgrounds.
prev = Image.new('RGBA', (CELL * 15, CELL * 3))
for k in range(3):
    for st in range(3):
        for fr in range(5):
            prev.alpha_composite(atlas.crop((fr * CELL, (k * 3 + st) * CELL, (fr + 1) * CELL, (k * 3 + st + 1) * CELL)), ((st * 5 + fr) * CELL, k * CELL))
for name, col in [('green', (170, 215, 150, 255)), ('sand', (246, 231, 193, 255))]:
    bg = Image.new('RGBA', prev.size, col); bg.alpha_composite(prev); bg.convert('RGB').save(f'preview_{name}.png')
print('atlas', atlas.size)
