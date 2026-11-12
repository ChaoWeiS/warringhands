#!/usr/bin/env python3
"""All the game's art on one editable sheet, and back again.

  python3 tools/art_sheet.py pack   [out.png]          -> art_sheet.png + art_sheet.json
  python3 tools/art_sheet.py unpack edited.png [json]  -> each cell back to its file

Every cell is the asset at its real size, with real transparency, in a
labelled section. Placeholders (dashed outline) are things drawn in code or
with no art yet: paint into them and they're picked up on unpack (empty
ones are skipped). Labels and outlines sit OUTSIDE the cells, so painting
inside a cell never touches them. The JSON manifest has every cell's exact
rectangle and where it goes.

If an edited sheet comes back without transparency (a painted grey-and-
white checkerboard, or a flat background), unpack cuts it out like
tools/make_logo.py does.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = str(ROOT / "assets/fonts/Fredoka.ttf")
MARGIN = 28          # around every cell
LABEL_H = 58         # label band under every cell
SECTION_H = 70       # section title band
SHEET_W = 4800
PAGE = (247, 244, 238, 255)
INK = (74, 69, 96, 255)
DASH = (176, 160, 196, 255)


def _font(size, bold=True):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([600 if bold else 400, 100])  # weight, width
    except Exception:
        pass
    return f


# What goes on the sheet: (section, [cells]). A cell is a dict:
#   name, path (where it lives in the game), and either an existing image
#   (path exists) or a placeholder: size [w, h], note, swatch (today's colour).
def cells():
    A = "assets/"
    sections = [
        ("Units: the hand atlas (5 frames x idle, move, attack, defend, death; rock, paper, scissors)", [
            {"name": "hands atlas", "path": A + "units/hands.png",
             "note": "192 px cells; feet on the line 24 px above each cell's bottom"},
        ]),
        ("Buildings", [
            {"name": "HQ (blue)", "path": A + "env/hq.png"},
            {"name": "HQ (red)", "path": A + "env/hq_red.png"},
            {"name": "quarry (rock)", "path": A + "env/quarry.png"},
            {"name": "mill (paper)", "path": A + "env/mill.png"},
            {"name": "forge (scissors)", "path": A + "env/forge.png"},
        ]),
        ("Nature and resources", [
            {"name": "pine 1", "path": A + "env/pine_1.png"},
            {"name": "pine 2", "path": A + "env/pine_2.png"},
            {"name": "rocks 1", "path": A + "env/rocks_1.png"},
            {"name": "rocks 2", "path": A + "env/rocks_2.png"},
            {"name": "crystals 1", "path": A + "env/crystals_1.png"},
            {"name": "crystals 2", "path": A + "env/crystals_2.png"},
            {"name": "icon stone", "path": A + "env/icon_stone.png"},
            {"name": "icon wood", "path": A + "env/icon_wood.png"},
            {"name": "icon metal", "path": A + "env/icon_metal.png"},
        ]),
        ("Buttons", [
            {"name": "build", "path": A + "env/button_build.png"},
            {"name": "attack", "path": A + "env/button_attack.png"},
            {"name": "hold", "path": A + "env/button_hold.png", "note": "drawn in code"},
            {"name": "queue", "path": A + "env/button_queue.png", "note": "drawn in code"},
            {"name": "settings", "path": A + "env/button_settings.png", "note": "drawn in code"},
            {"name": "surrender", "path": A + "env/button_surrender.png", "note": "drawn in code"},
            {"name": "full screen", "path": A + "new/button_fullscreen.png", "size": [192, 192],
             "note": "now: code-drawn corners"},
            {"name": "delete (code pad)", "path": A + "new/button_backspace.png", "size": [192, 128],
             "note": "now: code-drawn arrow"},
        ]),
        ("Logo, signs and app icon", [
            {"name": "logo", "path": A + "ui/logo.png"},
            {"name": "victory", "path": A + "ui/victory.png"},
            {"name": "defeat", "path": A + "ui/defeat.png"},
            {"name": "app icon", "path": A + "icon.png"},
        ]),
        ("Placeholders: terrain textures (tileable; now flat colours)", [
            {"name": "grass", "path": A + "new/tex_grass.png", "size": [256, 256], "swatch": "#c3e6ad"},
            {"name": "grass, dark (forest floor)", "path": A + "new/tex_grass_dark.png", "size": [256, 256], "swatch": "#addb96"},
            {"name": "sand / shore", "path": A + "new/tex_sand.png", "size": [256, 256], "swatch": "#f6e7c1"},
            {"name": "sea, shallow", "path": A + "new/tex_sea_shallow.png", "size": [256, 256], "swatch": "#b9e3f0"},
            {"name": "sea, deep", "path": A + "new/tex_sea_deep.png", "size": [256, 256], "swatch": "#8ec5e0"},
            {"name": "lake", "path": A + "new/tex_lake.png", "size": [256, 256], "swatch": "#a6d9ee"},
            {"name": "cliff face", "path": A + "new/tex_cliff.png", "size": [256, 256], "swatch": "#e8d3a8"},
            {"name": "hilltop", "path": A + "new/tex_hilltop.png", "size": [256, 256], "swatch": "#d3ecbf"},
            {"name": "hillside", "path": A + "new/tex_hillside.png", "size": [256, 256], "swatch": "#cbe9b6"},
        ]),
        ("Placeholders: on the ground (now drawn in code)", [
            {"name": "team circle (pink)", "path": A + "new/circle_team0.png", "size": [128, 128], "swatch": "#ff7f9a"},
            {"name": "team circle (blue)", "path": A + "new/circle_team1.png", "size": [128, 128], "swatch": "#6fb6ff"},
            {"name": "selection ring", "path": A + "new/ring_select.png", "size": [128, 128], "swatch": "#ffffff"},
            {"name": "move marker", "path": A + "new/marker_move.png", "size": [128, 128], "swatch": "#fff3b0"},
            {"name": "attack marker", "path": A + "new/marker_attack.png", "size": [128, 128], "swatch": "#ff7a7a"},
            {"name": "soft shadow", "path": A + "new/shadow.png", "size": [128, 64]},
            {"name": "route dash", "path": A + "new/route_dash.png", "size": [96, 24]},
            {"name": "build range circle", "path": A + "new/build_range.png", "size": [256, 256]},
            {"name": "health bar frame", "path": A + "new/hp_frame.png", "size": [128, 24]},
            {"name": "health bar fill", "path": A + "new/hp_fill.png", "size": [128, 24]},
            {"name": "tree stump (cut tree)", "path": A + "new/stump.png", "size": [128, 96]},
            {"name": "construction stage", "path": A + "new/construction.png", "size": [220, 220],
             "note": "a building going up"},
        ]),
        ("Placeholders: screen pieces (now plain shapes and fonts)", [
            {"name": "panel (9-slice)", "path": A + "new/panel.png", "size": [192, 192],
             "note": "windows, tutorial card"},
            {"name": "button plaque (9-slice)", "path": A + "new/plaque.png", "size": [192, 96]},
            {"name": "button plaque, pressed", "path": A + "new/plaque_pressed.png", "size": [192, 96]},
            {"name": "resource bar (9-slice)", "path": A + "new/resource_bar.png", "size": [192, 96]},
            {"name": "minimap frame (9-slice)", "path": A + "new/minimap_frame.png", "size": [192, 192]},
            {"name": "slider track", "path": A + "new/slider_track.png", "size": [256, 40]},
            {"name": "slider knob", "path": A + "new/slider_knob.png", "size": [88, 88]},
            {"name": "switch on", "path": A + "new/switch_on.png", "size": [176, 96]},
            {"name": "switch off", "path": A + "new/switch_off.png", "size": [176, 96]},
            {"name": "countdown 3", "path": A + "new/count_3.png", "size": [256, 256]},
            {"name": "countdown 2", "path": A + "new/count_2.png", "size": [256, 256]},
            {"name": "countdown 1", "path": A + "new/count_1.png", "size": [256, 256]},
            {"name": "Fight!", "path": A + "new/count_fight.png", "size": [512, 256]},
        ]),
        ("Placeholders: coming features", [
            {"name": "gym (upgrades)", "path": A + "new/gym.png", "size": [200, 200]},
            {"name": "library (research)", "path": A + "new/library.png", "size": [200, 200]},
            {"name": "defence tower", "path": A + "new/tower.png", "size": [200, 240]},
            {"name": "shifter (change gesture)", "path": A + "new/shifter.png", "size": [200, 200]},
            {"name": "upgrade: flight (paper)", "path": A + "new/upgrade_flight.png", "size": [128, 128]},
            {"name": "upgrade: tough (rock)", "path": A + "new/upgrade_tough.png", "size": [128, 128]},
            {"name": "upgrade: sharp (scissors)", "path": A + "new/upgrade_sharp.png", "size": [128, 128]},
            {"name": "fog of war", "path": A + "new/fog.png", "size": [256, 256], "note": "tileable cloud"},
        ]),
    ]
    return sections


def _dashed_rect(d, box, color, dash=10, gap=7, width=3):
    x0, y0, x1, y1 = box
    for (a, b, horizontal, fixed) in [(x0, x1, True, y0), (x0, x1, True, y1), (y0, y1, False, x0), (y0, y1, False, x1)]:
        p = a
        while p < b:
            q = min(p + dash, b)
            if horizontal:
                d.line([(p, fixed), (q, fixed)], fill=color, width=width)
            else:
                d.line([(fixed, p), (fixed, q)], fill=color, width=width)
            p = q + gap


def pack(out_png):
    font_title = _font(40)
    font_label = _font(24)
    font_note = _font(18, bold=False)
    # Lay out: rows of cells, wrapping at SHEET_W.
    placed = []
    y = MARGIN
    layout = []
    for title, items in cells():
        layout.append(("section", title, y))
        y += SECTION_H
        x = MARGIN
        row_h = 0
        for c in items:
            path = ROOT / c["path"]
            real = path.exists() and "size" not in c
            if real:
                img = Image.open(path).convert("RGBA")
                w, h = img.size
            else:
                img = None
                w, h = c["size"]
            label = c["name"] + ("" if real else "  (%dx%d)" % (w, h))
            slot = max(w, font_label.getlength(label) + (30 if c.get("swatch") else 0),
                       font_note.getlength(c.get("note", "")))
            if x + slot + MARGIN > SHEET_W and x > MARGIN:
                x = MARGIN
                y += row_h + LABEL_H + MARGIN
                row_h = 0
            placed.append({"name": c["name"], "path": c["path"], "rect": [x, y, w, h],
                           "placeholder": not real, "note": c.get("note", ""),
                           "swatch": c.get("swatch", ""), "img": img})
            x += int(slot) + MARGIN * 2
            row_h = max(row_h, h)
        y += row_h + LABEL_H + MARGIN * 2
    height = y
    sheet = Image.new("RGBA", (SHEET_W, height), PAGE)
    d = ImageDraw.Draw(sheet)
    for kind, title, ty in layout:
        d.text((MARGIN, ty + 10), title, font=font_title, fill=INK)
        d.line([(MARGIN, ty + SECTION_H - 10), (SHEET_W - MARGIN, ty + SECTION_H - 10)], fill=DASH, width=2)
    for p in placed:
        x, y0, w, h = p["rect"]
        # The cell itself: see-through (real transparency), outlined outside.
        sheet.paste(Image.new("RGBA", (w, h), (0, 0, 0, 0)), (x, y0))
        if p["img"] is not None:
            sheet.paste(p["img"], (x, y0))
            d.rectangle([x - 2, y0 - 2, x + w + 1, y0 + h + 1], outline=(200, 194, 210, 255), width=1)
        else:
            _dashed_rect(d, (x - 3, y0 - 3, x + w + 2, y0 + h + 2), DASH)
        label = p["name"] + ("" if not p["placeholder"] else "  (%dx%d)" % (w, h))
        ly = y0 + h + 8
        lx = x
        if p["swatch"]:
            d.rounded_rectangle([x, ly + 2, x + 22, ly + 24], radius=5, fill=p["swatch"], outline=INK, width=1)
            lx += 30
        d.text((lx, ly), label, font=font_label, fill=INK)
        if p["note"]:
            d.text((x, ly + 28), p["note"], font=font_note, fill=(120, 112, 140, 255))
    sheet.save(out_png, optimize=True)
    manifest = {"sheet": Path(out_png).name, "size": [SHEET_W, height],
                "cells": [{k: v for k, v in p.items() if k != "img"} for p in placed]}
    Path(out_png).with_suffix(".json").write_text(json.dumps(manifest, indent=1))
    print("wrote", out_png, (SHEET_W, height), len(placed), "cells")


def _restore_alpha(a):
    """An edited sheet that lost its transparency: the painted checkerboard
    (or flat page colour) round each picture goes see-through again."""
    from scipy import ndimage as ndi
    rgb = a[..., :3].astype(float)
    lo, hi = rgb.min(axis=2), rgb.max(axis=2)
    grey = (hi - lo < 14) & (lo > 182)
    lab, _ = ndi.label(grey)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(edge))
    art = ndi.binary_fill_holes(~background)
    out = a.copy()
    out[..., 3] = np.where(art, 255, 0).astype(np.uint8)
    return out


def unpack(edited_png, manifest_json):
    manifest = json.loads(Path(manifest_json).read_text())
    sheet = Image.open(edited_png).convert("RGBA")
    if list(sheet.size) != manifest["size"]:
        sx = sheet.size[0] / manifest["size"][0]
        print("note: sheet resized (x%.3f); scaling cell rectangles to match" % sx)
    else:
        sx = 1.0
    arr = np.array(sheet)
    no_alpha = arr[..., 3].min() == 255
    written = 0
    for c in manifest["cells"]:
        x, y, w, h = c["rect"]
        box = (round(x * sx), round(y * sx), round((x + w) * sx), round((y + h) * sx))
        cell = np.array(sheet.crop(box))
        if no_alpha:
            cell = _restore_alpha(cell)
        if c["placeholder"] and cell[..., 3].max() == 0:
            continue  # left empty
        img = Image.fromarray(cell, "RGBA")
        if img.size != (w, h):
            img = img.resize((w, h), Image.LANCZOS)
        out = ROOT / c["path"]
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out)
        written += 1
        print("  ", c["path"])
    print("wrote", written, "files")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "pack":
        pack(sys.argv[2] if len(sys.argv) > 2 else str(ROOT / "art_sheet.png"))
    elif len(sys.argv) >= 3 and sys.argv[1] == "unpack":
        unpack(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else str(Path(sys.argv[2]).with_suffix(".json")))
    else:
        print(__doc__)
