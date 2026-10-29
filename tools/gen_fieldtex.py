"""Makes assets/textures/fieldtex.png: what a far-away planted tile looks like. A 5 x 2 atlas of 64 px cells
(maize stages 1-5 on the first row, bean stages 1-5 on the second). Each cell is one tile: rows of plants
(the real average colour of the plant pictures) over dark soil, with speckle, so a distant field looks like
crop rows and not a flat colour.
Run from the repo root: python3 tools/gen_fieldtex.py /path/to/folder_with_maize_1..5.png_and_bean_1..5.png"""
import sys, os
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
C = 64
rng = np.random.default_rng(5)
soil = np.array([0.30, 0.20, 0.11])

def avg_color(path):
    im = np.asarray(Image.open(path).convert("RGBA").resize((256, 256), Image.LANCZOS), dtype=np.float32) / 255.0
    a = im[..., 3]
    m = a > 0.8
    return im[..., :3][m].mean(0) if m.any() else np.array([0.3, 0.5, 0.2])

def cell(color, rows, width, cover):
    yy = np.arange(C, dtype=np.float32)
    img = np.tile(soil, (C, C, 1)).astype(np.float32)
    img *= (0.85 + 0.3 * rng.random((C, C, 1)))
    for r in rows:
        cy = r * C
        w = np.exp(-((yy - cy) / (width * 0.5)) ** 2)[:, None]            # soft band
        speck = 0.75 + 0.5 * rng.random((C, C))
        gaps = (rng.random((C, C)) < cover).astype(np.float32)            # gaps in the row
        wt = np.clip(w * (0.35 + 0.65 * gaps) * 1.15, 0.0, 1.0)[..., None]
        plant = color[None, None, :] * speck[..., None] * 0.9
        img = img * (1 - wt) + plant * wt
    return np.clip(img, 0, 1)

atlas = np.zeros((2 * C, 5 * C, 3), dtype=np.float32)
for crop_i, (name, rows, width) in enumerate([("maize", [0.1, 0.5, 0.9], 15.0), ("bean", [0.1, 0.3, 0.5, 0.7, 0.9], 9.5)]):
    for st in range(5):
        col = avg_color(os.path.join(SRC, "%s_%d.png" % (name, st + 1)))
        cover = [0.45, 0.8, 0.9, 0.92, 0.94][st]
        wdt = width * [0.5, 0.8, 1.0, 1.05, 1.1][st]
        atlas[crop_i * C:(crop_i + 1) * C, st * C:(st + 1) * C] = cell(col, rows, wdt, cover)
Image.fromarray((atlas * 255).astype(np.uint8), "RGB").save("assets/textures/fieldtex.png", optimize=True)
print("ok")
