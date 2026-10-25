extends RefCounted
# Crop plants built from textured leaf cards (atlas assets/textures/crops.png) on stalks.
# One mesh per field tile (one draw call). Plants stand in straight rows on the soil ridges.
# Five growth stages: 0 sprout, 1 young, 2 growing, 3 maturing, 4 ripe.
# Ripe crops are fresh and ready to pick (green leaves, plump cobs and pods), not dry.
# detail 0 = fewer plants and leaves (for weak phones), detail 1 = full.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const CropData := preload("res://scripts/crop_data.gd")

const ATLAS := "res://assets/textures/crops.png"
const STAGE_COUNT := 5
# Progress at which each stage starts. crop_data.gd uses the same numbers (a test checks it).
const STAGE_FROM := [0.0, 0.2, 0.45, 0.75, 1.0]
const RIDGE_TOP := 0.09   # soil ridge height (tile_models.gd)

# Atlas cells (see tools/gen_crop_atlas.py)
const LEAF_A := 0
const LEAF_B := 1
const BEAN_LEAF := 2
const PODS := 3
const COB := 4
const TASSEL := 5
const BLADES := 6
const FLOWERS := 7

static func stage_for(progress: float) -> int:
	var idx := 0
	for i in STAGE_FROM.size():
		if progress >= float(STAGE_FROM[i]):
			idx = i
	return idx

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 78.233) * 43758.5453, 1.0)

# Plant positions inside one tile (x along the ridges, z across). The soil has 5 ridges at
# z = -0.6, -0.3, 0, 0.3, 0.6; plants stand on them. Spacing also lines up from tile to tile.
static func _spots(crop_id: String, detail: int) -> Array:
	var rows: Array = [0, 2, 4]
	var xs: Array = [-0.36, 0.36]
	if crop_id == "maize":
		xs = [-0.5, 0.0, 0.5] if detail == 1 else [-0.375, 0.375]
	elif crop_id == "beans":
		rows = [0, 1, 2, 3, 4] if detail == 1 else [0, 2, 4]
		xs = [-0.5, 0.0, 0.5] if detail == 1 else [-0.375, 0.375]
	else:
		rows = [1, 3]
	var out: Array = []
	for r in rows:
		for x in xs:
			out.append(Vector2(float(x), -0.6 + 0.3 * float(r)))
	return out

static func build(crop_id: String, stage: int, variant: int = 0, detail: int = 1) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var spots := _spots(crop_id, detail)
	stage = clampi(stage, 0, STAGE_COUNT - 1)
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var sd := variant * 97 + i * 13 + 5
		var base := Vector3(sp.x + (_h(sd) - 0.5) * 0.08, RIDGE_TOP, sp.y + (_h(sd + 1) - 0.5) * 0.03)
		if crop_id == "maize":
			_maize_plant(mb, base, stage, sd, detail)
		elif crop_id == "beans":
			_bean_plant(mb, base, stage, sd, detail)
		else:
			var h := 0.15 + 0.15 * float(stage)
			var col := Color(0.3, 0.7, 0.25)
			if stage == STAGE_COUNT - 1 and CropData.CROPS.has(crop_id):
				col = CropData.CROPS[crop_id]["color"]
			mb.add_box(base + Vector3(0, h / 2.0, 0), Vector3(0.4, h, 0.4), col)
	return mb.build()

# A card standing on its own, crossed with a second one so it is visible from every side.
static func _crossed(mb, p0: Vector3, p1: Vector3, width: float, cell: int, c0: Color, c1: Color, yaw: float) -> void:
	var axis := p1 - p0
	if axis.length() < 0.001:
		return
	var a := axis.normalized()
	var ref := Vector3(cos(yaw), 0.0, sin(yaw))
	var s1 := a.cross(ref).normalized()
	if s1.length() < 0.5:
		s1 = a.cross(Vector3.RIGHT).normalized()
	var s2 := a.cross(s1).normalized()
	mb.add_card([p0, p1], [width, width], s1, cell, c0, c1)
	mb.add_card([p0, p1], [width, width], s2, cell, c0, c1)

static func _maize_plant(mb, base: Vector3, stage: int, sd: int, detail: int) -> void:
	var up := Vector3.UP
	if stage == 0:
		for k in 2:
			var a := float(k) * 1.6 + _h(sd) * 2.0
			var d := Vector3(cos(a), 0.0, sin(a))
			mb.add_card([base, base + up * 0.17 + d * 0.03], [0.2, 0.2], d.cross(up).normalized(), BLADES,
				Color(0.3, 0.62, 0.16), Color(0.55, 0.85, 0.3))
		return
	var heights := [0.0, 0.3, 0.65, 1.05, 1.2]
	var h: float = float(heights[stage]) * (0.9 + 0.2 * _h(sd + 3))
	var stalk0 := Color(0.28, 0.48, 0.14)
	var stalk1 := Color(0.42, 0.66, 0.24)
	mb.add_prism(base, base + up * h, 0.03 if stage >= 2 else 0.02, 0.016, 5, stalk0, stalk1)
	var counts := [0, 4, 6, 8, 8]
	var n: int = int(counts[stage])
	if detail == 0:
		n = maxi(3, n - 2)
	var lmax := clampf(0.16 + 0.34 * h, 0.18, 0.52)
	var wscale := 0.6 + 0.1 * float(stage)
	var c0 := Color(0.17, 0.4, 0.09)
	var c1 := Color(0.46, 0.76, 0.22) if stage < 4 else Color(0.58, 0.78, 0.24)
	for k in n:
		var t := 0.12 + 0.75 * float(k) / float(maxi(n - 1, 1))
		var a := float(k) * 2.4 + _h(sd + 10 + k) * 0.9
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := dir.cross(up).normalized()
		var ln := lmax * (0.7 + 0.3 * sin(PI * t)) * (0.9 + 0.2 * _h(sd + 30 + k))
		var origin := base + up * (h * t)
		var pts: Array = []
		var wid: Array = []
		var steps := 3 if detail == 0 else 4
		for s in steps:
			var u := float(s) / float(steps - 1)
			pts.append(origin + dir * (ln * u) + up * (ln * (0.7 * u - 0.8 * u * u)))
			wid.append(wscale * (0.1 + 0.07 * sin(PI * u)))
		var shade := 0.9 + 0.2 * _h(sd + 50 + k)
		mb.add_card(pts, wid, side, LEAF_A if k % 2 == 0 else LEAF_B,
			MeshBuilder.shade(c0, shade), MeshBuilder.shade(c1, shade))
	if stage >= 3:
		var ripe := stage == 4
		var ts := 0.24 if ripe else 0.16
		var top := base + up * h
		_crossed(mb, top - up * 0.02, top + up * ts, ts * 0.9, TASSEL,
			Color(0.62, 0.72, 0.3), Color(0.9, 0.8, 0.38), _h(sd + 60) * TAU)
		var cs := 0.21 if ripe else 0.12
		var ea := _h(sd + 40) * TAU
		var edir := Vector3(cos(ea), 0.0, sin(ea))
		var eb := base + up * (h * 0.55) + edir * 0.03
		_crossed(mb, eb, eb + edir * cs * 0.45 + up * cs * 0.9, cs * 0.55, COB,
			Color(0.6, 0.78, 0.32), Color(0.88, 0.68, 0.28), ea)
		if ripe and detail == 1 and _h(sd + 41) > 0.45:
			var eb2 := base + up * (h * 0.38) - edir * 0.03
			_crossed(mb, eb2, eb2 - edir * cs * 0.4 + up * cs * 0.9, cs * 0.5, COB,
				Color(0.6, 0.78, 0.32), Color(0.88, 0.68, 0.28), ea + 1.0)

static func _bean_plant(mb, base: Vector3, stage: int, sd: int, detail: int) -> void:
	var up := Vector3.UP
	if stage == 0:
		for k in 2:
			var a := float(k) * PI + _h(sd) * 2.0
			var d := Vector3(cos(a), 0.0, sin(a))
			mb.add_card([base, base + d * 0.05 + up * 0.04, base + d * 0.09 + up * 0.05], [0.09, 0.09, 0.09],
				d.cross(up).normalized(), BEAN_LEAF, Color(0.28, 0.6, 0.15), Color(0.5, 0.82, 0.3))
		return
	var heights := [0.0, 0.12, 0.22, 0.32, 0.36]
	var h: float = float(heights[stage]) * (0.9 + 0.2 * _h(sd + 1))
	mb.add_prism(base, base + up * h, 0.012, 0.006, 4, Color(0.3, 0.5, 0.15), Color(0.45, 0.7, 0.25))
	var counts := [0, 3, 5, 7, 7]
	var n: int = int(counts[stage])
	if detail == 0:
		n = maxi(3, n - 2)
	var lsize := [0.0, 0.13, 0.19, 0.24, 0.25]
	var c0 := Color(0.2, 0.48, 0.11)
	var c1 := Color(0.38, 0.74, 0.2) if stage < 4 else Color(0.52, 0.78, 0.24)
	for k in n:
		var t := 0.2 + 0.8 * float(k) / float(maxi(n - 1, 1))
		var a := float(k) * 2.4 + _h(sd + 10 + k)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var origin := base + up * (h * t)
		var ln := float(lsize[stage]) * (0.85 + 0.3 * _h(sd + 20 + k))
		var shade := 0.9 + 0.2 * _h(sd + 50 + k)
		mb.add_card([origin, origin + dir * ln * 0.5 + up * ln * 0.3, origin + dir * ln * 0.95 + up * ln * 0.22],
			[ln * 1.05, ln * 1.05, ln * 1.05], dir.cross(up).normalized(), BEAN_LEAF,
			MeshBuilder.shade(c0, shade), MeshBuilder.shade(c1, shade))
	if stage == 3:
		var fn := 2 if detail == 0 else 3
		for k in fn:
			var fa := float(k) * 2.1 + _h(sd + 20)
			var fd := Vector3(cos(fa), 0.0, sin(fa))
			var fb := base + up * (h * 0.85) + fd * 0.07
			_crossed(mb, fb, fb + up * 0.06, 0.08, FLOWERS, Color(0.95, 0.9, 0.97), Color(0.9, 0.72, 0.88), fa)
	if stage >= 3:
		var ps := 1.0 if stage == 4 else 0.6
		var pn := (2 if detail == 0 else 4) if stage == 4 else 2
		for k in pn:
			var pa := float(k) * 1.7 + 0.7 + _h(sd + 30 + k)
			var pd := Vector3(cos(pa), 0.0, sin(pa))
			var pb := base + up * (h * (0.4 + 0.12 * float(k % 3))) + pd * 0.03
			_crossed(mb, pb + pd * 0.06 - up * 0.2 * ps, pb + pd * 0.02, 0.15 * ps, PODS,
				Color(0.58, 0.78, 0.28), Color(0.32, 0.56, 0.16), pa)
