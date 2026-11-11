#!/usr/bin/env python3
"""The app icon (assets/icon.png, 512 px): the three hands, idle pose, cut
at full size from art_source/hands_sheet_v2.png (the same cut as the unit
sprites, so the paper hand has its five fingers) on a soft green rounded
square. Paper in the middle at
the back, rock on the left, scissors on the right.

Run from the project root: python3 tools/make_icon.py
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import cut_hand_sprites as cutter  # noqa: E402

SIZE = 512


def hand(kind: int, height: int) -> Image.Image:
    """Idle frame 0 of a kind, cropped to the hand and scaled to a height."""
    ry0, ry1 = cutter.ROWS[kind]
    y0, y1 = ry0 + cutter.BADGE, ry1 - cutter.ROW_PAD
    x0, x1 = cutter.cells(cutter.PANELS[0], y0, y1)[0]
    rgba, _ = cutter.cut(x0, x1, y0, y1)
    cell = Image.fromarray(rgba, "RGBA")
    cell = cell.crop(cell.getbbox())
    w = round(cell.width * height / cell.height)
    return cell.resize((w, height), Image.LANCZOS)


icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=96, fill=255)
icon.paste(Image.new("RGBA", (SIZE, SIZE), (199, 232, 186, 255)), (0, 0), mask)

paper = hand(1, 300)
rock = hand(0, 230)
scissors = hand(2, 290)
icon.alpha_composite(paper, ((SIZE - paper.width) // 2, 70))
icon.alpha_composite(rock, (40, SIZE - rock.height - 50))
icon.alpha_composite(scissors, (SIZE - scissors.width - 40, SIZE - scissors.height - 50))
icon.save("assets/icon.png")
print("wrote assets/icon.png")
