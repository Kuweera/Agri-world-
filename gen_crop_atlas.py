"""Draws assets/textures/crops.png: a 4x4 atlas (128 px cells) of crop cards.
RGB is a grey light/dark pattern (veins, shading) and alpha is the shape. The game tints
it with vertex colours, so one atlas serves every growth stage. Run: python3 tools/gen_crop_atlas.py
Cell index = row * 4 + col. UV of a cell = (col/4, row/4, 1/4, 1/4)."""
import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 512          # hi-res size of one cell
random.seed(7)
rng = np.random.default_rng(7)

def new_cell():
    base = np.clip(0.82 + rng.normal(0, 0.035, (S, S)), 0, 1)
    rgb = Image.fromarray((base * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(3))
    return rgb, Image.new("L", (S, S), 0)

def finish(rgb, alpha):
    a = alpha.filter(ImageFilter.GaussianBlur(1.2)).resize((128, 128), Image.LANCZOS)
    g = rgb.resize((128, 128), Image.LANCZOS)
    a = a.point(lambda v: 0 if v < 40 else (255 if v > 215 else v))
    return Image.merge("LA", (g, a))

def leaf_poly(width_fn, n=40, y0=498, y1=10, cx=256, wobble=0.0):
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        y = y0 + (y1 - y0) * t
        w = width_fn(t) * (1 + wobble * math.sin(t * 38.0))
        left.append((cx - w, y))
        right.append((cx + w, y))
    return left + right[::-1]

def maize_leaf(narrow):
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    mw = 46 if narrow else 78
    fn = lambda t: max(0.5, 8 * (1 - t) + (mw - 8) * math.sin(math.pi * t ** 0.75) * (1 - 0.15 * t))
    poly = leaf_poly(fn, wobble=0.05)
    da.polygon(poly, fill=255)
    for k in range(-9, 10):                      # parallel veins
        x0 = 256 + k * (mw / 11.0)
        dr.line([(256 + (x0 - 256) * 0.2, 498), (x0, 200), (256 + (x0 - 256) * 0.1, 18)], fill=int(205 + 20 * (k % 2)), width=3)
    dr.line([(256, 498), (256, 14)], fill=250, width=12)    # midrib
    dr.line([(256, 498), (256, 14)], fill=235, width=5)
    edge = Image.new("L", (S, S), 0)
    ImageDraw.Draw(edge).polygon(poly, fill=255)
    edge = edge.filter(ImageFilter.GaussianBlur(22))
    e = np.asarray(edge, dtype=np.float32) / 255.0
    arr = np.asarray(rgb, dtype=np.float32) * (0.62 + 0.38 * np.clip(e * 1.6, 0, 1))
    return finish(Image.fromarray(arr.astype(np.uint8), "L"), al)

def ellipse_leaf(draw_a, draw_r, cx, cy, rx, ry, ang):
    pts = []
    for i in range(60):
        th = i / 60 * math.tau
        px = rx * math.cos(th) * (1 - 0.18 * math.sin(th))   # a little pointed at the tip (top)
        py = ry * math.sin(th)
        x = cx + px * math.cos(ang) - py * math.sin(ang)
        y = cy + px * math.sin(ang) + py * math.cos(ang)
        pts.append((x, y))
    draw_a.polygon(pts, fill=255)
    tip = (cx + ry * math.sin(ang) * -1, cy - ry * math.cos(ang))
    return pts

def bean_leaf():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    da.line([(256, 505), (256, 330)], fill=255, width=14)
    leaflets = [(256, 175, 92, 140, 0.0), (118, 300, 82, 110, -1.0), (394, 300, 82, 110, 1.0)]
    for cx, cy, rx, ry, a in leaflets:
        # ellipse with the long axis along the leaflet direction (a rotates it from vertical)
        pts = []
        for i in range(64):
            th = i / 64 * math.tau
            px = rx * math.cos(th)
            py = ry * math.sin(th) * (1.0 if math.sin(th) < 0 else 0.85)
            x = cx + px * math.cos(a) - py * math.sin(a)
            y = cy + px * math.sin(a) + py * math.cos(a)
            pts.append((x, y))
        da.polygon(pts, fill=255)
        tipx, tipy = cx + ry * math.sin(a), cy - ry * math.cos(a)
        basex, basey = cx - ry * math.sin(a) * 0.9, cy + ry * math.cos(a) * 0.9
        dr.line([(basex, basey), (tipx, tipy)], fill=250, width=8)
        for k in (-0.5, -0.2, 0.2, 0.5):
            mx, my = (basex + tipx) / 2, (basey + tipy) / 2
            dr.line([(mx - (tipx - basex) * 0.2, my - (tipy - basey) * 0.2),
                     (mx + (tipx - basex) * 0.05 + k * 150 * math.cos(a), my + (tipy - basey) * 0.05 + k * 150 * math.sin(a))], fill=225, width=3)
    dr.line([(256, 505), (256, 330)], fill=215, width=8)
    arr = np.asarray(rgb, dtype=np.float32)
    shade = Image.new("L", (S, S), 255)
    ImageDraw.Draw(shade).ellipse([60, 60, 450, 420], fill=255)
    return finish(Image.fromarray(arr.astype(np.uint8), "L"), al)

def bean_pods():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    da.line([(256, 6), (256, 60)], fill=255, width=10)
    for (x0, bend, length, wd) in [(256, 0, 450, 30), (215, -45, 390, 26), (300, 55, 410, 27)]:
        pts_l, pts_r, mid = [], [], []
        for i in range(31):
            t = i / 30
            y = 40 + length * t
            x = x0 + bend * math.sin(t * 1.8)
            w = wd * (0.5 + 0.5 * math.sin(math.pi * min(1.0, t * 0.9 + 0.1))) * (1.0 - 0.7 * t ** 6) * (1 + 0.12 * math.sin(t * 40))
            pts_l.append((x - w, y)); pts_r.append((x + w, y)); mid.append((x, y))
        da.polygon(pts_l + pts_r[::-1], fill=255)
        dr.line(mid, fill=240, width=4)
        for i in range(2, 29, 3):
            dr.ellipse([mid[i][0] - 9, mid[i][1] - 9, mid[i][0] + 9, mid[i][1] + 9], fill=232)
    return finish(rgb, al)

def maize_cob():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    # husk: fat capsule, overlapped by leaf layers; silk tuft at the tip
    for layer, (wx, y0, y1) in enumerate([(78, 500, 120), (62, 500, 100)]):
        fn = lambda t, wx=wx: wx * math.sin(math.pi * min(1.0, 0.18 + 0.82 * t) ** 0.8) * (1 - 0.35 * t)
        poly = leaf_poly(fn, y0=y0, y1=y1, cx=256 + (-14 if layer == 0 else 16))
        da.polygon(poly, fill=255)
        dr.polygon(poly, fill=int(232 - 25 * layer))
        dr.line([(256 + (-14 if layer == 0 else 16), y0), (256 + (-6 if layer == 0 else 8), y1)], fill=250, width=6)
    for k in range(7):
        a = -0.7 + k * 0.23
        dr.line([(256, 130), (256 + 70 * math.sin(a) * 1.4, 18 + 22 * abs(a))], fill=255, width=4)
        da.line([(256, 130), (256 + 70 * math.sin(a) * 1.4, 18 + 22 * abs(a))], fill=255, width=5)
    return finish(rgb, al)

def tassel():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    da.line([(256, 505), (256, 20)], fill=255, width=14)
    for i in range(9):
        y = 90 + i * 45
        for side in (-1, 1):
            pts = [(256, y), (256 + side * 70, y - 28), (256 + side * 130, y + 10 + i * 4), (256 + side * 165, y + 55 + i * 5)]
            da.line(pts, fill=255, width=9)
            dr.line(pts, fill=235, width=5)
    return finish(rgb, al)

def blades():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    for k in range(7):
        a = -0.75 + k * 0.25 + random.uniform(-0.05, 0.05)
        ln = random.uniform(330, 470)
        pts_l, pts_r, mid = [], [], []
        for i in range(25):
            t = i / 24
            x = 256 + math.sin(a) * ln * t + 40 * a * t * t * 2
            y = 500 - math.cos(a) * ln * t
            w = 20 * (1 - t) ** 0.8 + 1
            pts_l.append((x - w, y)); pts_r.append((x + w, y)); mid.append((x, y))
        da.polygon(pts_l + pts_r[::-1], fill=255)
        dr.line(mid, fill=245, width=4)
    return finish(rgb, al)

def flowers():
    rgb, al = new_cell()
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    for (x, y, r) in [(160, 330, 55), (330, 250, 62), (250, 130, 48), (380, 400, 45)]:
        da.ellipse([x - r, y - r, x + r, y + r], fill=255)
        dr.ellipse([x - r * 0.4, y - r * 0.4, x + r * 0.4, y + r * 0.4], fill=200)
    return finish(rgb, al)

cells = [maize_leaf(False), maize_leaf(True), bean_leaf(), bean_pods(),
         maize_cob(), tassel(), blades(), flowers()]
atlas = Image.new("LA", (512, 512), (200, 0))
for i, c in enumerate(cells):
    atlas.paste(c, ((i % 4) * 128, (i // 4) * 128))
atlas.save("assets/textures/crops.png", optimize=True)
print("saved", len(cells), "cells")
