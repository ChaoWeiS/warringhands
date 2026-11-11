#!/usr/bin/env python3
"""Menu logo and end-of-game banners, cut out of their painted checkerboard.

  art_source/ui/logo.jpg           -> assets/ui/logo.png
  art_source/ui/victory_defeat.jpg -> assets/ui/victory.png, assets/ui/defeat.png
                                      (the left and right signs)

The art came with a grey-and-white checkerboard painted in where it should
be see-through. Pale grey / white pixels joined to the edge of the picture
go see-through (with a soft edge); the signs, hands and dust puffs stay.

Run from the project root: python3 tools/make_logo.py
"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def cut_out(path: str) -> np.ndarray:
    src = np.array(Image.open(path).convert("RGB")).astype(float)
    lo, hi = src.min(axis=2), src.max(axis=2)
    grey = (hi - lo < 14) & (lo > 182)  # the checkerboard: white (255) and grey (~195)
    lab, _ = ndi.label(grey)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(edge))
    background = ndi.binary_closing(background, iterations=2) | background
    art = ndi.binary_fill_holes(~background)
    alpha = ndi.gaussian_filter(art.astype(float), 0.8)
    alpha = np.where(art, np.maximum(alpha, 0.5), alpha * 0.9)
    alpha[alpha < 0.06] = 0
    return np.dstack([src, alpha * 255]).astype(np.uint8)


def save(rgba: np.ndarray, path: str, width: int) -> None:
    img = Image.fromarray(rgba, "RGBA")
    img = img.crop(img.getbbox())
    img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    img.save(path, optimize=True)
    print("wrote", path, img.size)


save(cut_out("art_source/ui/logo.jpg"), "assets/ui/logo.png", 1400)
# Two signs side by side: split at the emptiest column near the middle.
both = cut_out("art_source/ui/victory_defeat.jpg")
cols = (both[..., 3] > 0).sum(axis=0)
mid = both.shape[1] // 2
split = mid - 120 + int(np.argmin(cols[mid - 120:mid + 120]))
save(both[:, :split], "assets/ui/victory.png", 1000)
save(both[:, split:], "assets/ui/defeat.png", 1000)
