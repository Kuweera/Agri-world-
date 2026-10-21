extends RefCounted
# Built-in 3D models for the implements in implement_data.gd. Each is sized from the
# catalogue: work_width tiles across, so what you see matches the tiles it works.
# The hitch is the origin and the implement trails behind it (-z).
# A real model can replace any of these later through model_path.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const ImplementData := preload("res://scripts/implement_data.gd")

const TILE_PITCH := 1.5
const TOOLBAR_Z := -0.55
const DARK := Color(0.2, 0.2, 0.23)
const STEEL := Color(0.6, 0.62, 0.67)
const RUBBER := Color(0.08, 0.08, 0.09)

static func width_units(id: String) -> float:
	return float(ImplementData.width_of(id)) * TILE_PITCH

static func build(id: String) -> ArrayMesh:
	return build_builder(id).build()

# The mesh data before it becomes a mesh (the tests read the vertices from this).
static func build_builder(id: String):
	var mb := MeshBuilder.new()
	if not ImplementData.ITEMS.has(id):
		return mb
	var item: Dictionary = ImplementData.ITEMS[id]
	var w := width_units(id)
	var paint: Color = item["paint"]
	var kind: String = item["type"]
	_frame(mb, w)
	if kind == "plough":
		_plough(mb, w, paint)
	elif kind == "seeder":
		_seeder(mb, w, paint)
	elif kind == "fertilizer":
		_spreader(mb, w, paint)
	elif kind == "harvester":
		_header(mb, w, paint)
	return mb

# Drawbar, A-frame, toolbar across the full width, and transport wheels on wide machines.
static func _frame(mb, w: float) -> void:
	mb.add_box(Vector3(0, 0.2, -0.2), Vector3(0.16, 0.1, 0.4), DARK)
	var a := minf(w * 0.3, 1.4)
	var yaw := atan2(a, 0.4)
	var arm := sqrt(a * a + 0.16)
	for s in [-1.0, 1.0]:
		mb.add_box_xf(Transform3D(Basis(Vector3.UP, -s * yaw), Vector3(s * a * 0.5, 0.24, -0.22)),
			Vector3(0.08, 0.08, arm), DARK, 0.6)
	mb.add_box(Vector3(0, 0.45, TOOLBAR_Z), Vector3(w, 0.12, 0.14), DARK)
	if w >= 3.0:
		for s in [-1.0, 1.0]:
			var x: float = s * (w * 0.5 - 0.3)
			mb.add_prism(Vector3(x - 0.08, 0.25, TOOLBAR_Z - 0.05), Vector3(x + 0.08, 0.25, TOOLBAR_Z - 0.05),
				0.25, 0.25, 10, RUBBER, RUBBER, true, true)
			mb.add_prism(Vector3(x - 0.1, 0.25, TOOLBAR_Z - 0.05), Vector3(x + 0.1, 0.25, TOOLBAR_Z - 0.05),
				0.1, 0.1, 6, STEEL, STEEL, true, true)
			mb.add_box(Vector3(x, 0.35, TOOLBAR_Z - 0.05), Vector3(0.05, 0.2, 0.05), DARK)

# One share every 0.6 across the width: shank, painted mouldboard, steel tip.
static func _plough(mb, w: float, paint: Color) -> void:
	var n := maxi(1, roundi(w / 0.6))
	for i in n:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(n)
		mb.add_box(Vector3(x, 0.3, TOOLBAR_Z - 0.06), Vector3(0.06, 0.44, 0.06), DARK)
		mb.add_box_xf(Transform3D(Basis(Vector3.UP, 0.5), Vector3(x, 0.14, TOOLBAR_Z - 0.28)),
			Vector3(0.1, 0.26, 0.5), paint, 0.6)
		mb.add_box(Vector3(x, 0.03, TOOLBAR_Z - 0.46), Vector3(0.1, 0.04, 0.22), STEEL)

# A hopper for each tile across, a seed tube and a coulter disc every 0.75.
static func _seeder(mb, w: float, paint: Color) -> void:
	var hn := maxi(1, roundi(w / TILE_PITCH))
	var hw := w / float(hn) * 0.9
	for i in hn:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(hn)
		mb.add_box(Vector3(x, 0.95, TOOLBAR_Z + 0.05), Vector3(hw, 0.5, 0.55), paint)
		mb.add_box(Vector3(x, 1.22, TOOLBAR_Z + 0.05), Vector3(hw * 1.04, 0.06, 0.6), DARK)
	var rn := maxi(2, roundi(w / 0.75))
	for i in rn:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(rn)
		mb.add_prism(Vector3(x, 0.72, TOOLBAR_Z - 0.05), Vector3(x, 0.2, TOOLBAR_Z - 0.3), 0.03, 0.02, 5, STEEL, DARK)
		mb.add_prism(Vector3(x - 0.02, 0.16, TOOLBAR_Z - 0.32), Vector3(x + 0.02, 0.16, TOOLBAR_Z - 0.32),
			0.15, 0.15, 7, STEEL, STEEL, true, true)

# A tank across most of the width, a spinner disc for each tile, and a boom with nozzles.
static func _spreader(mb, w: float, paint: Color) -> void:
	mb.add_box(Vector3(0, 0.98, TOOLBAR_Z + 0.1), Vector3(w * 0.62, 0.45, 0.8), paint)
	mb.add_box(Vector3(0, 0.62, TOOLBAR_Z + 0.1), Vector3(w * 0.5, 0.28, 0.6), paint.darkened(0.2))
	mb.add_box(Vector3(0, 1.24, TOOLBAR_Z + 0.1), Vector3(w * 0.64, 0.05, 0.84), DARK)
	var sn := maxi(1, roundi(w / TILE_PITCH))
	for i in sn:
		var x := -w * 0.5 + (float(i) + 0.5) * w / float(sn)
		mb.add_prism(Vector3(x, 0.46, TOOLBAR_Z - 0.45), Vector3(x, 0.5, TOOLBAR_Z - 0.45),
			0.34, 0.34, 10, STEEL, STEEL, true, true)
		mb.add_box(Vector3(x, 0.53, TOOLBAR_Z - 0.45), Vector3(0.6, 0.04, 0.06), DARK)
	if w > TILE_PITCH * 1.2:
		mb.add_box(Vector3(0, 0.52, TOOLBAR_Z - 0.28), Vector3(w, 0.05, 0.05), DARK)
		var nn := maxi(2, roundi(w / 0.75))
		for i in nn:
			var x := -w * 0.5 + (float(i) + 0.5) * w / float(nn)
			mb.add_prism(Vector3(x, 0.5, TOOLBAR_Z - 0.28), Vector3(x, 0.25, TOOLBAR_Z - 0.28), 0.03, 0.02, 4, STEEL, DARK)

# Cutter bar, header body, side plates, a reel across the width and a divider for each tile.
static func _header(mb, w: float, paint: Color) -> void:
	mb.add_box(Vector3(0, 0.5, TOOLBAR_Z - 0.15), Vector3(w, 0.4, 0.55), paint)
	mb.add_box(Vector3(0, 0.3, TOOLBAR_Z - 0.5), Vector3(w, 0.05, 0.14), Color(0.75, 0.2, 0.15), 0.0, 1.0)
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(s * w * 0.5, 0.6, TOOLBAR_Z - 0.2), Vector3(0.06, 0.55, 0.8), paint)
	var reel := Color(0.75, 0.25, 0.15)
	mb.add_prism(Vector3(-w * 0.5, 0.95, TOOLBAR_Z - 0.35), Vector3(w * 0.5, 0.95, TOOLBAR_Z - 0.35),
		0.26, 0.26, 8, reel, reel, true, true)
	var hn := maxi(1, roundi(w / TILE_PITCH))
	for i in range(1, hn):
		var x := -w * 0.5 + float(i) * w / float(hn)
		mb.add_box(Vector3(x, 0.55, TOOLBAR_Z - 0.55), Vector3(0.04, 0.4, 0.35), paint.darkened(0.15))
