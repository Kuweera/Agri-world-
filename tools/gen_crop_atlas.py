"""Paints assets/textures/crops.png: a 4x4 atlas of 256 px cells, each a whole plant (side view)
on a transparent background, like the crops in Farming Master 3D. The game puts each picture on
a few crossed flat cards (crop_models.gd), so a field is dense and cheap to draw.
Cells: 0-3 maize stages 1-4, 4-7 bean stages 1-4, 8 seedling blades.
Run from the repo root: python3 tools/gen_crop_atlas.py"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

H = 1024            # hi-res cell size; downsampled to 256
CELL = 256
random.seed(11)

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def mul(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

def new_cell():
    im = Image.new("RGBA", (H, H), (60, 110, 40, 0))
    return im, ImageDraw.Draw(im)

def curve(nx, ny, side, L, rise, droop, n=26):
    pts = []
    for i in range(n + 1):
        u = i / n
        pts.append((nx + side * L * u, ny - L * (rise * u - droop * u * u)))
    return pts

def offsets(pts, widths):
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        w = widths[i]
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left, right

def draw_leaf(d, pts, wmax, base, tip, vein=True, fold=0.18):
    n = len(pts) - 1
    widths = [max(1.5, wmax * math.sin(math.pi * min(1.0, (i / n)) ** 0.75) * (1 - 0.1 * i / n) + 3 * (1 - i / n)) for i in range(n + 1)]
    widths[-1] = 1.0
    left, right = offsets(pts, widths)
    # two tones either side of the midrib gives a folded blade
    for i in range(n):
        t = i / n
        col = mix(base, tip, max(0.0, (t - 0.45) / 0.55) ** 1.2)
        col = mul(col, 0.78 + 0.3 * t)          # darker at the base, lighter to the tip
        d.polygon([pts[i], left[i], left[i + 1], pts[i + 1]], fill=mul(col, 1.0 + fold))
        d.polygon([pts[i], right[i], right[i + 1], pts[i + 1]], fill=mul(col, 1.0 - fold))
    if vein:
        d.line(pts, fill=mul(mix(base, tip, 0.5), 1.35), width=max(2, int(wmax / 9)))
        for i in range(3, n - 1, 2):
            for s in (left, right):
                x0, y0 = pts[i]
                x1, y1 = s[min(n, i + 2)]
                d.line([(x0, y0), (x0 + (x1 - x0) * 0.9, y0 + (y1 - y0) * 0.9)], fill=mul(mix(base, tip, 0.4), 0.82), width=2)

def maize(stage):
    im, d = new_cell()
    cx = H // 2
    bottom = H - 14
    tops = {1: 560, 2: 330, 3: 190, 4: 170}
    top = tops[stage]
    nleaf = {1: 4, 2: 6, 3: 8, 4: 9}[stage]
    # stalk
    if stage >= 2:
        for y in range(top + 40, bottom, 6):
            t = (y - top) / (bottom - top)
            w = 9 + 11 * t
            d.rectangle([cx - w, y, cx + w, y + 7], fill=mix((150, 185, 85), (105, 150, 55), t))
        for y in range(top + 120, bottom - 40, 95):
            d.line([(cx - 20, y), (cx + 20, y)], fill=(95, 130, 50), width=5)
    base_c = (38, 92, 28)
    tip_c = (120, 168, 52) if stage < 4 else (140, 178, 58)
    Lmax = {1: 330, 2: 380, 3: 430, 4: 450}[stage]
    for k in range(nleaf):
        t = k / max(1, nleaf - 1)
        ny = bottom - 60 - t * (bottom - top - 190)
        side = -1 if k % 2 == 0 else 1
        L = Lmax * (0.78 + 0.22 * math.sin(math.pi * (0.15 + 0.85 * t))) * random.uniform(0.92, 1.05)
        rise = 0.85 + 0.55 * t
        droop = 0.75 + 0.45 * (1 - t) + random.uniform(-0.1, 0.1)
        pts = curve(cx + side * 10, ny, side, L, rise, droop)
        jit = random.uniform(0.9, 1.08)
        draw_leaf(d, pts, 34 + 6 * (1 - t), mul(base_c, jit), mul(tip_c, jit))
    if stage >= 3:  # tassel
        n_br = 7 if stage == 4 else 5
        sz = 1.0 if stage == 4 else 0.65
        gold = (205, 188, 98)
        d.line([(cx, top + 70), (cx, top - 40 * sz + 20)], fill=gold, width=9)
        for i in range(n_br):
            y0 = top + 60 - i * 14 * sz
            for s in (-1, 1):
                pts = [(cx, y0), (cx + s * 45 * sz, y0 - 40 * sz), (cx + s * 90 * sz, y0 - 20 * sz), (cx + s * 120 * sz, y0 + 40 * sz)]
                d.line(pts, fill=mix(gold, (160, 140, 70), i / n_br), width=6)
    if stage == 4:  # cobs with husk and silk
        for (hy, s) in ((0.50, 1), (0.66, -1)):
            ay = top + (bottom - top) * hy
            ax = cx + s * 14
            ang = math.radians(32) * s
            ln, wd = 250, 62
            pts = []
            for i in range(21):
                u = i / 20
                px = wd * math.sin(math.pi * min(1.0, 0.12 + 0.88 * u) ** 0.85) * (1 - 0.25 * u)
                pts.append((u * ln, px))
            def rot(px, py):
                return (ax + px * math.sin(ang) * 1.0 - 0 + 0, ay - px * math.cos(ang) + 0)
            poly_l, poly_r = [], []
            for (along, wid) in pts:
                bx = ax + math.sin(ang) * along
                by = ay - math.cos(ang) * along
                nx, ny2 = math.cos(ang), math.sin(ang)
                poly_l.append((bx + nx * wid, by + ny2 * wid))
                poly_r.append((bx - nx * wid, by - ny2 * wid))
            d.polygon(poly_l + poly_r[::-1], fill=(142, 182, 78))
            d.polygon(poly_l[:] + [ (ax + math.sin(ang) * ln * 0.0, ay) ], fill=(158, 196, 92))
            for k in (0.25, 0.5, 0.75):
                i = int(k * 20)
                d.line([(ax, ay), ((poly_l[i][0] + poly_r[i][0]) / 2, (poly_l[i][1] + poly_r[i][1]) / 2)], fill=(120, 160, 60), width=3)
            tipx = ax + math.sin(ang) * ln
            tipy = ay - math.cos(ang) * ln
            for j in range(9):
                a2 = ang + (j - 4) * 0.12
                d.line([(tipx, tipy), (tipx + math.sin(a2) * 70, tipy - math.cos(a2) * 70)], fill=(185 - j % 3 * 12, 135, 70), width=4)
    return im

def trifoliate(d, px, py, ang, size, base, tip, a_spread=0.95):
    # petiole is drawn by the caller; this draws three leaflets at (px, py) pointing along ang
    for (da, sc) in ((0.0, 1.0), (-a_spread, 0.82), (a_spread, 0.82)):
        a = ang + da
        L = size * sc
        pts = []
        for i in range(25):
            u = i / 24
            pts.append((px + math.sin(a) * L * u + math.sin(a) * 2, py - math.cos(a) * L * u))
        n = 24
        wid = [size * 0.42 * sc * math.sin(math.pi * (i / n) ** 0.8) + 1 for i in range(n + 1)]
        wid[-1] = 1.0
        left, right = offsets(pts, wid)
        col = mix(base, tip, random.uniform(0.2, 0.7))
        d.polygon(left + right[::-1], fill=mul(col, 0.9))
        # lighter half
        d.polygon(pts + right[::-1], fill=mul(col, 1.18))
        d.line(pts, fill=mul(col, 1.4), width=max(2, int(size / 40)))
        for i in (6, 10, 14, 18):
            d.line([pts[i], left[i + 2]], fill=mul(col, 0.8), width=2)
            d.line([pts[i], right[i + 2]], fill=mul(col, 0.8), width=2)

def bean(stage):
    im, d = new_cell()
    cx = H // 2
    bottom = H - 20
    n = {1: 3, 2: 7, 3: 11, 4: 13}[stage]
    top = {1: 640, 2: 470, 3: 330, 4: 300}[stage]
    d.line([(cx, bottom), (cx, top)], fill=(95, 140, 55), width=14)
    base_c = (34, 96, 28)
    tip_c = (84, 156, 48) if stage < 4 else (110, 168, 52)
    items = []
    for k in range(n):
        t = k / max(1, n - 1)
        ny = bottom - 40 - t * (bottom - top - 60)
        side = -1 if k % 2 == 0 else 1
        spread = random.uniform(0.35, 1.2) * (1.25 - 0.5 * t)
        ang = side * spread
        plen = random.uniform(60, 130) * (1.1 - 0.3 * t)
        size = {1: 190, 2: 205, 3: 215, 4: 220}[stage] * random.uniform(0.85, 1.1)
        items.append((ny, ang, plen, size, 0.8 + 0.3 * t))
    for (ny, ang, plen, size, br) in items:
        ex = cx + math.sin(ang) * plen
        ey = ny - math.cos(ang) * plen * 0.6
        d.line([(cx, ny), (ex, ey)], fill=(100, 145, 55), width=8)
        trifoliate(d, ex, ey, ang * 0.9, size, mul(base_c, br), mul(tip_c, br))
    if stage == 3:
        for i in range(7):
            fx = cx + random.uniform(-230, 230)
            fy = random.uniform(top + 40, bottom - 260)
            for k in range(5):
                a = k * math.tau / 5
                d.ellipse([fx + math.cos(a) * 16 - 11, fy + math.sin(a) * 16 - 11, fx + math.cos(a) * 16 + 11, fy + math.sin(a) * 16 + 11], fill=(245, 235, 245))
            d.ellipse([fx - 7, fy - 7, fx + 7, fy + 7], fill=(235, 190, 90))
    if stage == 4:
        for (px, py, ln, bend) in [(cx - 120, 560, 230, -0.2), (cx - 70, 600, 260, -0.1), (cx + 90, 540, 250, 0.15), (cx + 140, 600, 220, 0.25), (cx + 20, 660, 240, 0.05)]:
            pts = [(px + bend * ln * (i / 16) ** 1.5 * 0.8, py + ln * i / 16) for i in range(17)]
            wid = [20 * math.sin(math.pi * (0.1 + 0.8 * i / 16)) + 2 for i in range(17)]
            left, right = offsets(pts, wid)
            d.polygon(left + right[::-1], fill=(138, 184, 66))
            d.polygon(pts + right[::-1], fill=(120, 168, 52))
            d.line(pts, fill=(95, 140, 40), width=3)
            for i in range(3, 15, 3):
                d.ellipse([pts[i][0] - 7, pts[i][1] - 7, pts[i][0] + 7, pts[i][1] + 7], fill=(155, 198, 80))
    return im

def blades():
    im, d = new_cell()
    cx = H // 2
    for k in range(9):
        a = -0.9 + k * 0.225 + random.uniform(-0.04, 0.04)
        L = random.uniform(430, 640)
        pts = [(cx + math.sin(a) * L * (i / 24) + 40 * a * (i / 24) ** 2 * 3, H - 14 - math.cos(a) * L * (i / 24)) for i in range(25)]
        draw_leaf(d, pts, 20, (40, 100, 30), (120, 180, 60), vein=False, fold=0.12)
    return im

cells = [maize(1), maize(2), maize(3), maize(4), bean(1), bean(2), bean(3), bean(4), blades()]
atlas = Image.new("RGBA", (4 * CELL, 4 * CELL), (60, 110, 40, 0))
for i, c in enumerate(cells):
    atlas.paste(c.resize((CELL, CELL), Image.LANCZOS), ((i % 4) * CELL, (i // 4) * CELL))
atlas.save("assets/textures/crops.png", optimize=True)
print("saved", len(cells), "cells")
