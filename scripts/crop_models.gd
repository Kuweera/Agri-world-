extends RefCounted
# Low-poly plant models, built from tapered stalks and curved leaf ribbons.
# One mesh per field tile (one draw call). Stage 0 = seedling, 1 = growing, 2 = ripe.
# detail 0 = fewer plants and leaves (for weak phones), detail 1 = full.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const CropData := preload("res://scripts/crop_data.gd")

static func stage_for(progress: float) -> int:
	if progress >= 1.0:
		return 2
	if progress >= 0.34:
		return 1
	return 0

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 78.233) * 43758.5453, 1.0)

static func _spots(detail: int) -> Array:
	if detail == 0:
		return [Vector2(-0.36, -0.3), Vector2(0.36, -0.3), Vector2(0.0, 0.38)]
	return [Vector2(-0.36, -0.36), Vector2(0.36, -0.36), Vector2(-0.36, 0.36), Vector2(0.36, 0.36)]

static func build(crop_id: String, stage: int, variant: int = 0, detail: int = 1) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var spots := _spots(detail)
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var sd := variant * 97 + i * 13 + 5
		var base := Vector3(sp.x + (_h(sd) - 0.5) * 0.16, 0.0, sp.y + (_h(sd + 1) - 0.5) * 0.16)
		if crop_id == "maize":
			_maize_plant(mb, base, stage, sd, detail)
		elif crop_id == "beans":
			_bean_plant(mb, base, stage, sd, detail)
		else:
			var h := 0.2 + 0.3 * float(stage)
			var col := Color(0.3, 0.7, 0.25)
			if stage == 2 and CropData.CROPS.has(crop_id):
				col = CropData.CROPS[crop_id]["color"]
			mb.add_box(base + Vector3(0, h / 2.0, 0), Vector3(0.4, h, 0.4), col)
	return mb.build()

static func _maize_plant(mb, base: Vector3, stage: int, sd: int, detail: int) -> void:
	var up := Vector3.UP
	if stage == 0:
		for k in 3:
			var a := float(k) * 2.1 + _h(sd + k) * 1.5
			var out := Vector3(cos(a), 0.0, sin(a))
			mb.add_ribbon([base, base + out * 0.04 + up * 0.13, base + out * 0.11 + up * 0.24],
				[0.035, 0.03, 0.004], out.cross(up).normalized(), Color(0.3, 0.6, 0.2), Color(0.55, 0.85, 0.35))
		return
	var ripe := stage == 2
	var h := 0.95 + 0.12 * _h(sd + 3)
	if ripe:
		h = 1.25 + 0.15 * _h(sd + 3)
	var stalk0 := Color(0.3, 0.5, 0.15) if not ripe else Color(0.55, 0.45, 0.2)
	var stalk1 := Color(0.5, 0.75, 0.3) if not ripe else Color(0.8, 0.7, 0.38)
	mb.add_prism(base, base + up * h, 0.04, 0.022, 5, stalk0, stalk1)
	var n := 4 if detail == 0 else 6
	if ripe:
		n += 1
	for k in n:
		var t := 0.2 + 0.62 * float(k) / float(n - 1)
		var a := float(k) * PI + 0.5 + _h(sd + 10 + k) * 0.8
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := dir.cross(up).normalized()
		var length := 0.38 + 0.18 * (1.0 - absf(t - 0.5))
		var droop := 0.55 if not ripe else 0.85
		var origin := base + up * (h * t)
		var pts := []
		for s in 5:
			var u := float(s) / 4.0
			pts.append(origin + dir * (length * u) + up * (sin(u * 1.7) * length * 0.35 - u * u * length * droop * 0.5))
		var lc0 := Color(0.2, 0.42, 0.1) if not ripe else Color(0.5, 0.42, 0.2)
		var lc1 := Color(0.4, 0.72, 0.22) if not ripe else Color(0.78, 0.68, 0.32)
		mb.add_ribbon(pts, [0.03, 0.075, 0.085, 0.06, 0.01], side, lc0, lc1)
	if ripe:
		var ea := _h(sd + 40) * TAU
		var edir := Vector3(cos(ea), 0.0, sin(ea))
		var eb := base + up * (h * 0.55) + edir * 0.045
		var emid := eb + edir * 0.05 + up * 0.14
		var etip := emid + edir * 0.03 + up * 0.1
		mb.add_prism(eb, emid, 0.04, 0.06, 6, Color(0.55, 0.5, 0.25), Color(0.75, 0.7, 0.38))
		mb.add_prism(emid, etip, 0.06, 0.03, 6, Color(0.95, 0.78, 0.12), Color(0.98, 0.86, 0.25), true)
		mb.add_ribbon([etip, etip + up * 0.05 + edir * 0.03, etip + up * 0.09 + edir * 0.06],
			[0.02, 0.015, 0.002], edir.cross(up).normalized(), Color(0.45, 0.28, 0.15), Color(0.6, 0.4, 0.2))
	var top := base + up * h
	var tn := 3 if detail == 0 else 5
	for k in tn:
		var ta := float(k) * TAU / float(tn) + _h(sd + 60) * 2.0
		var td := Vector3(cos(ta), 0.0, sin(ta))
		var tc0 := Color(0.55, 0.6, 0.3) if not ripe else Color(0.8, 0.7, 0.4)
		var tc1 := Color(0.75, 0.8, 0.45) if not ripe else Color(0.92, 0.85, 0.55)
		mb.add_ribbon([top, top + td * 0.05 + up * 0.1, top + td * 0.13 + up * 0.15],
			[0.014, 0.011, 0.002], td.cross(up).normalized(), tc0, tc1)

static func _bean_plant(mb, base: Vector3, stage: int, sd: int, detail: int) -> void:
	var up := Vector3.UP
	if stage == 0:
		mb.add_prism(base, base + up * 0.05, 0.008, 0.006, 4, Color(0.4, 0.6, 0.25), Color(0.5, 0.75, 0.35))
		for k in 2:
			var a := float(k) * PI + _h(sd) * 2.0
			var d := Vector3(cos(a), 0.0, sin(a))
			mb.add_diamond(base + up * 0.05 + d * 0.06, d * 0.07 - up * 0.02, d.cross(up).normalized() * 0.05,
				Color(0.3, 0.6, 0.2), Color(0.5, 0.82, 0.35))
		return
	var ripe := stage == 2
	var h := 0.32 + 0.08 * _h(sd + 1)
	if ripe:
		h = 0.38 + 0.08 * _h(sd + 1)
	var stem0 := Color(0.3, 0.45, 0.15) if not ripe else Color(0.5, 0.4, 0.2)
	var stem1 := Color(0.45, 0.65, 0.25) if not ripe else Color(0.6, 0.5, 0.25)
	mb.add_prism(base, base + up * h, 0.014, 0.008, 4, stem0, stem1)
	var leaves := (5 if detail == 0 else 8) if not ripe else 4
	var lc := Color(0.22, 0.52, 0.14) if not ripe else Color(0.58, 0.52, 0.2)
	var lt := Color(0.38, 0.72, 0.25) if not ripe else Color(0.78, 0.7, 0.3)
	for k in leaves:
		var t := 0.25 + 0.7 * float(k) / float(maxi(leaves - 1, 1))
		var a := float(k) * 2.4 + _h(sd + 10 + k)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := dir.cross(up).normalized()
		var origin := base + up * (h * t)
		var node := origin + dir * (0.13 + 0.05 * (1.0 - t)) + up * 0.02
		mb.add_ribbon([origin, node], [0.01, 0.008], side, stem0, stem1)
		mb.add_diamond(node + dir * 0.07, dir * 0.075 - up * 0.02, side * 0.055, lc, lt)
		mb.add_diamond(node + side * 0.06, side * 0.065, dir * 0.05, lc, lt)
		mb.add_diamond(node - side * 0.06, -side * 0.065, dir * 0.05, lc, lt)
	if stage == 1:
		for k in 3:
			var fa := float(k) * 2.1 + _h(sd + 20)
			var fd := Vector3(cos(fa), 0.0, sin(fa))
			mb.add_diamond(base + up * (h * 0.85) + fd * 0.07, up * 0.03, fd.cross(up).normalized() * 0.025,
				Color(0.95, 0.85, 0.95), Color(0.85, 0.6, 0.8))
		for k in 3:
			var pa := float(k) * 2.1 + 0.7
			var pd := Vector3(cos(pa), 0.0, sin(pa))
			var pb := base + up * (h * 0.5) + pd * 0.03
			mb.add_prism(pb, pb + pd * 0.05 - up * 0.1, 0.012, 0.006, 4, Color(0.3, 0.6, 0.18), Color(0.5, 0.8, 0.3))
	else:
		for k in 6:
			var pa := float(k) * 1.1 + _h(sd + 30 + k)
			var pd := Vector3(cos(pa), 0.0, sin(pa))
			var pb := base + up * (h * (0.35 + 0.1 * float(k % 3))) + pd * 0.03
			mb.add_prism(pb, pb + pd * 0.07 - up * 0.17, 0.016, 0.007, 4, Color(0.75, 0.58, 0.3), Color(0.5, 0.32, 0.15))
