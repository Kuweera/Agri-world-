extends RefCounted
# Low-poly crop models built from primitives and merged into ONE mesh each,
# so every field tile costs a single draw call. Colours are stored as vertex
# colours (use one material with vertex_color_use_as_albedo).
# Stage 0 = seedling, 1 = growing, 2 = ripe.

const CropData := preload("res://scripts/crop_data.gd")

static func stage_for(progress: float) -> int:
	if progress >= 1.0:
		return 2
	if progress >= 0.34:
		return 1
	return 0

static func build(crop_id: String, stage: int) -> ArrayMesh:
	var parts: Array = []
	if crop_id == "maize":
		_maize(parts, stage)
	elif crop_id == "beans":
		_beans(parts, stage)
	else:
		_generic(parts, crop_id, stage)
	return _merge(parts)

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 6
	m.rings = 3
	return m

static func _part(parts: Array, mesh: Mesh, pos: Vector3, yaw: float, color: Color, pitch: float = 0.0) -> void:
	var xf := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos)
	parts.append({"mesh": mesh, "xf": xf, "color": color})

static func _maize(parts: Array, stage: int) -> void:
	var spots := [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]
	for i in spots.size():
		var sp: Vector2 = spots[i]
		if stage == 0:
			_part(parts, _box(Vector3(0.07, 0.22, 0.07)), Vector3(sp.x, 0.11, sp.y), 0.0, Color(0.4, 0.8, 0.3))
			continue
		var h := 0.65 if stage == 1 else 0.95
		var stalk := Color(0.3, 0.7, 0.25) if stage == 1 else Color(0.8, 0.75, 0.35)
		var leaf := Color(0.25, 0.65, 0.25) if stage == 1 else Color(0.7, 0.7, 0.3)
		_part(parts, _box(Vector3(0.08, h, 0.08)), Vector3(sp.x, h / 2.0, sp.y), 0.0, stalk)
		_part(parts, _box(Vector3(0.5, 0.03, 0.1)), Vector3(sp.x, h * 0.7, sp.y), i * 0.4, leaf)
		_part(parts, _box(Vector3(0.5, 0.03, 0.1)), Vector3(sp.x, h * 0.5, sp.y), PI / 2.0 + i * 0.4, leaf)
		if stage == 2:
			_part(parts, _box(Vector3(0.13, 0.3, 0.13)), Vector3(sp.x + 0.06, h * 0.55, sp.y), 0.0, Color(0.95, 0.8, 0.15))
			_part(parts, _box(Vector3(0.1, 0.12, 0.1)), Vector3(sp.x, h + 0.05, sp.y), 0.0, Color(0.9, 0.85, 0.5))

static func _beans(parts: Array, stage: int) -> void:
	var spots := [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, 0.35), Vector2(0.0, 0.0)]
	for i in spots.size():
		var sp: Vector2 = spots[i]
		if stage == 0:
			_part(parts, _sphere(0.07, 0.14), Vector3(sp.x, 0.07, sp.y), 0.0, Color(0.45, 0.8, 0.35))
			continue
		var r := 0.2 if stage == 1 else 0.26
		var col := Color(0.35, 0.75, 0.3) if stage == 1 else Color(0.2, 0.55, 0.2)
		_part(parts, _sphere(r, r * 1.4), Vector3(sp.x, r * 0.7, sp.y), 0.0, col)
		if stage == 2:
			for k in 3:
				var a := float(k) * TAU / 3.0 + float(i)
				_part(parts, _box(Vector3(0.05, 0.05, 0.28)),
					Vector3(sp.x + cos(a) * 0.2, 0.3, sp.y + sin(a) * 0.2), a, Color(0.55, 0.3, 0.15), 0.3)

# Any crop without its own model: a simple box.
static func _generic(parts: Array, crop_id: String, stage: int) -> void:
	var h := 0.2 + 0.3 * float(stage)
	var col := Color(0.3, 0.7, 0.25)
	if stage == 2 and CropData.CROPS.has(crop_id):
		col = CropData.CROPS[crop_id]["color"]
	_part(parts, _box(Vector3(0.7, h, 0.7)), Vector3(0.0, h / 2.0, 0.0), 0.0, col)

static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xf"]
		var color: Color = p["color"]
		var arrays := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := verts.size()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((xf.basis * n[i]).normalized())
			cols.append(color)
		for i in ix:
			idx.append(i + base)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out
