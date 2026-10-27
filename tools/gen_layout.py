"""Generates the plot and road tables in scripts/plot_data.gd.
Run from the repo root: python3 tools/gen_layout.py
The farm is laid out in bands. The main road (z = 3.6) runs east-west. North of it are three
bands of plots, south of it two (the farmhouse yard sits in the first south band). Between the
plots of a band run north-south roads, and between bands east-west roads. Every plot is
SETBACK units from every road centre, so implements never reach a road while working."""
PITCH = 1.5
ROAD_HALF = 2.5
SETBACK = 7.0
M_Z = 3.6
GAP = 2 * SETBACK
YARD_W = 38.0

# name, cols for each plot, west to east. "HOME" / "YARD" are fixed items in the middle.
north_bands = [
    {"rows": 16, "items": [("p03", "Willow Estate", 28), ("p02", "Brook Field", 20), ("p01", "Meadow Farm", 16), "HOME",
                           ("p04", "Orchard Field", 16), ("p05", "Sunrise Field", 20), ("p06", "Hilltop Estate", 28)]},
    {"rows": 22, "items": [("p09", "Great Meadows", 36), ("p08", "Long Acres", 28), ("p07", "Riverside", 20), None,
                           ("p10", "Eastgate Field", 20), ("p11", "Broad Acres", 28), ("p12", "Grand East Estate", 36)]},
    {"rows": 28, "items": [("p13", "North West Estate", 40), None, ("p14", "North East Estate", 40)]},
]
south_bands = [
    {"rows": 14, "items": [("p15", "Valley Farm", 24), ("p16", "Cherry Field", 16), "YARD", ("p17", "Maple Field", 16), ("p18", "Oak Farm", 24)]},
    {"rows": 24, "items": [("p19", "South West Estate", 40), None, ("p20", "South East Estate", 40)]},
]

def size_class(tiles):
    return "Medium" if tiles <= 350 else "Large" if tiles <= 650 else "Very large" if tiles <= 1000 else "Estate"

plots = []
roads_h = []   # (z, x0, x1)
roads_v = []   # (x, z0, z1)

def layout(band, edge_z, direction):
    """Returns list of (item, left, right) x positions with the middle gap / middle item at x = 0."""
    items = band["items"]
    widths = []
    for it in items:
        if it == "HOME":
            widths.append(8 * PITCH)
        elif it == "YARD":
            widths.append(YARD_W)
        elif it is None:
            widths.append(0.0)   # a plain road gap
        else:
            widths.append(it[2] * PITCH)
    x = 0.0
    pos = []
    for w in widths:
        pos.append([x, x + w])
        x += w + (GAP if w > 0 else 0.0)
    # centre: on the fixed item, or on the middle road
    if "HOME" in items or "YARD" in items:
        k = items.index("HOME") if "HOME" in items else items.index("YARD")
        centre = (pos[k][0] + pos[k][1]) / 2.0
    else:
        k = items.index(None)
        centre = pos[k][0] - GAP / 2.0 + 0.0
        centre = pos[k][0] - GAP / 2.0
        # the None item has width 0 and takes no gap of its own: its road is where it sits
        centre = pos[k][0] - GAP / 2.0 if k > 0 else pos[k][0]
        # the gap before item k is the middle road
        centre = pos[k][0] - GAP / 2.0
    return [(items[i], pos[i][0] - centre, pos[i][1] - centre) for i in range(len(items))]

def add_band(band, near_road_z, direction):
    """direction -1: band lies north of near_road_z, +1: south. Returns far road z."""
    rows = band["rows"]
    depth = rows * PITCH
    if direction < 0:
        south = near_road_z - SETBACK
        north = south - depth
        far = north - SETBACK
    else:
        north = near_road_z + SETBACK
        south = north + depth
        far = south + SETBACK
    lay = layout(band, 0, direction)
    xs_roads = []
    left_end = None
    right_end = None
    for item, l, r in lay:
        if item is None:
            continue
        if left_end is None:
            left_end = l
        right_end = r
        if item == "YARD":
            continue
        if item == "HOME":
            cols, rws, pid, name = 8, 8, "farm", "Home Farm"
        else:
            pid, name, cols = item
            rws = rows
        cx = (l + r) / 2.0
        h = rws * PITCH
        cz = (south - h / 2.0) if direction < 0 else (north + h / 2.0)
        plots.append({"id": pid, "name": name, "cols": cols, "rows": rws, "cx": round(cx, 3), "cz": round(cz, 3),
                      "side": "n" if direction < 0 else "s", "band": len(plots)})
    # vertical roads: at both ends and in every gap between items
    items = [(it, l, r) for it, l, r in lay if it is not None]
    vx = [left_end - SETBACK]
    for a, b in zip(items[:-1], items[1:]):
        vx.append((a[2] + b[1]) / 2.0)
    vx.append(right_end + SETBACK)
    # a plain road gap (None) sits in the gap before it: add its road, which is between neighbours
    z0, z1 = (far, near_road_z) if direction < 0 else (near_road_z, far)
    for x in vx:
        roads_v.append((round(x, 3), z0, z1))
    return far, (vx[0], vx[-1])

spans = {}
z_far = M_Z
spans_n = []
for b in north_bands:
    z_far_new, span = add_band(b, z_far, -1)
    spans_n.append((z_far, span))
    z_far = z_far_new
    spans_n[-1] = (z_far_new, span)
north_roads = spans_n
z_far_s = M_Z
spans_s = []
for b in south_bands:
    z_far_new, span = add_band(b, z_far_s, +1)
    spans_s.append((z_far_new, span))
    z_far_s = z_far_new

# horizontal roads: the main road spans the widest of the first north / first south bands
def hspan(*ss):
    return (min(s[0] for s in ss), max(s[1] for s in ss))
roads_h.append((M_Z,) + hspan(spans_n[0][1], spans_s[0][1]))
for i in range(len(spans_n)):
    z, span = spans_n[i]
    nxt = spans_n[i + 1][1] if i + 1 < len(spans_n) else span
    roads_h.append((round(z, 3),) + hspan(span, nxt))
for i in range(len(spans_s)):
    z, span = spans_s[i]
    nxt = spans_s[i + 1][1] if i + 1 < len(spans_s) else span
    roads_h.append((round(z, 3),) + hspan(span, nxt))

# the home field must be first (tile order); the rest sorted by id
plots.sort(key=lambda p: (p["id"] != "farm", p["id"]))

xmin = min(r[1] for r in roads_h)
xmax = max(r[2] for r in roads_h)
zmin = min(r[0] for r in roads_h)
zmax = max(r[0] for r in roads_h)

out = []
out.append("extends RefCounted")
out.append("# The farmland plots and roads. Pure data and maths, shared by game logic, autopilot, map and tests.")
out.append("# GENERATED by tools/gen_layout.py - change the layout there, not here.")
out.append("# North is -z. The main road runs east-west at z = ROAD_Z. The farm is laid out in bands of plots:")
out.append("# every plot is SETBACK units from the centre of every road around it, so implements never reach")
out.append("# a road while working, and two machines on different plots never meet. The farmhouse yard is in")
out.append("# the first band south of the main road.")
out.append("")
out.append("const PITCH := 1.5")
out.append('const HOME := "farm"')
out.append("const ROAD_Z := %s          # centre line of the main road" % M_Z)
out.append("const ROAD_HALF := %s       # half the width of a road" % ROAD_HALF)
out.append("const SETBACK := %s          # road centre to plot edge" % SETBACK)
out.append("const PRICE_PER_TILE := 30")
out.append("const HA_PER_TILE := 0.06    # area shown to the player: one tile is 0.06 hectares")
out.append("const WORLD_HALF := 204.0    # the farm land reaches this far from the centre")
out.append("const YARD_HALF := %s" % (YARD_W / 2))
out.append("")
out.append("# id, name, size class, tiles across (cols) and down (rows), world centre (cx, cz), side of the main road.")
out.append("const PLOTS := [")
for p in plots:
    t = p["cols"] * p["rows"]
    sz = "Home" if p["id"] == "farm" else size_class(t)
    out.append('\t{"id": "%s", "name": "%s", "size": "%s", "cols": %d, "rows": %d, "cx": %s, "cz": %s, "side": "%s"},' % (
        p["id"], p["name"], sz, p["cols"], p["rows"], p["cx"], p["cz"], p["side"]))
out.append("]")
out.append("")
out.append("# East-west roads: [z, x from, x to]. The first is the main road.")
out.append("const ROADS_H := [")
for z, a, b in roads_h:
    out.append("\t[%s, %s, %s]," % (round(z, 3), round(a, 3), round(b, 3)))
out.append("]")
out.append("")
out.append("# North-south roads: [x, z from, z to].")
out.append("const ROADS_V := [")
for x, a, b in roads_v:
    out.append("\t[%s, %s, %s]," % (round(x, 3), round(a, 3), round(b, 3)))
out.append("]")
out.append("")
tail = open("tools/plot_data_tail.gd").read()
out.append(tail)
open("scripts/plot_data.gd", "w").write("\n".join(out))
print("plots", len(plots), "roads_h", len(roads_h), "roads_v", len(roads_v), "x", xmin, xmax, "z", zmin, zmax)
