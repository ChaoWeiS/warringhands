#!/usr/bin/env python3
"""The menu logo (assets/ui/logo.png) from art_source/ui/logo.jpg.

The art came with a grey-and-white checkerboard painted in where it should
be see-through. That's removed: pale grey / white pixels joined to the edge
of the picture go see-through (with a soft edge); the sign, its frame, the
hands and the dust puffs (warm, not grey) stay.

Run from the project root: python3 tools/make_logo.py
"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

src = np.array(Image.open("art_source/ui/logo.jpg").convert("RGB")).astype(float)
lo, hi = src.min(axis=2), src.max(axis=2)
grey = (hi - lo < 14) & (lo > 182)  # the checkerboard: white (255) and grey (~195)
lab, _ = ndi.label(grey)
edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
background = np.isin(lab, list(edge))
# Close up specks inside the checkerboard (JPEG noise), and soften the edge.
background = ndi.binary_closing(background, iterations=2) | background
art = ~background
art = ndi.binary_fill_holes(art)
alpha = ndi.gaussian_filter(art.astype(float), 0.8)
alpha = np.where(art, np.maximum(alpha, 0.5), alpha * 0.9)
alpha[alpha < 0.06] = 0
out = np.dstack([src, alpha * 255]).astype(np.uint8)
img = Image.fromarray(out, "RGBA")
img = img.crop(img.getbbox())
img = img.resize((1400, round(img.height * 1400 / img.width)), Image.LANCZOS)
img.save("assets/ui/logo.png", optimize=True)
print("wrote assets/ui/logo.png", img.size)
