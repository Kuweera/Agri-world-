extends RefCounted
# Static scenery, each built as ONE mesh (one draw call): land with colour variation,
# distant hills, fence, trees, farmhouse and cheap "blob" shadows (shown when real
# shadows are off). Heights are decided by simple noise.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const PlotData := preload("res://scripts/plot_data.gd")

const LAND_HALF := 90.0      # the farm land (same as PlotData.WORLD_HALF)
const LAND_CELL := 3.0       # size of one ground square

var blobs: MeshInstance3D

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 78.233) * 43758.5453, 1.0)

func _node(parent: Node3D, mesh: ArrayMesh, mat: Material, casts_shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func build(parent: Node3D, mat: Material, land_mat: Material = null) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.05
	var land: Material = land_mat if land_mat != null else mat
	_node(parent, _inner_land(noise), land, false)
	_node(parent, _outer_land(noise), land, false)
	_node(parent, _roads(), mat, false)
	_node(parent, _fence(), mat, true)
	_node(parent, _trees(), mat, true)
	_node(parent, _house(), mat, true)
	var blob_mat := StandardMaterial3D.new()
	blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_mat.albedo_color = Color(0, 0, 0, 0.3)
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	blobs = _node(parent, _blob_mesh(), blob_mat, false)

func set_blob_visible(on: bool) -> void:
	if blobs != null:
		blobs.visible = on

# ---- Land ----

func _land_color(x: float, z: float, noise: FastNoiseLite) -> Color:
	var n := noise.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5
	var c := Color(0.30, 0.50, 0.17).lerp(Color(0.42, 0.58, 0.22), n)
	var d := Vector2(x * 0.6, z - 10.5).length()   # a wide dirt yard south of the house
	var yard := 1.0 - smoothstep(6.0, 9.0, d)
	var path := 0.0
	if z > 1.5 and z < 6.0:
		path = 1.0 - smoothstep(0.6, 1.4, absf(x))
	var dirt := Color(0.55, 0.45, 0.3).lerp(Color(0.48, 0.38, 0.25), n)
	return c.lerp(dirt, maxf(yard, path))

func _inner_land(noise: FastNoiseLite) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var n := int(LAND_HALF * 2.0 / LAND_CELL)
	var c := LAND_CELL
	for i in n:
		for j in n:
			var x0 := -LAND_HALF + c * float(i)
			var z0 := -LAND_HALF + c * float(j)
			mb.add_quad(
				Vector3(x0, 0.0, z0), Vector3(x0 + c, 0.0, z0),
				Vector3(x0 + c, 0.0, z0 + c), Vector3(x0, 0.0, z0 + c),
				_land_color(x0, z0, noise), _land_color(x0 + c, z0, noise),
				_land_color(x0 + c, z0 + c, noise), _land_color(x0, z0 + c, noise))
	return mb.build()

func _outer_height(x: float, z: float, noise: FastNoiseLite) -> float:
	var r := maxf(absf(x), absf(z))
	var f := smoothstep(88.0, 135.0, r)
	var n := noise.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5
	return -0.04 + f * (2.0 + 12.0 * n)

func _outer_color(x: float, z: float, noise: FastNoiseLite) -> Color:
	var r := maxf(absf(x), absf(z))
	var f := smoothstep(88.0, 160.0, r)
	var n := noise.get_noise_2d(x * 1.5, z * 1.5) * 0.5 + 0.5
	var c := Color(0.28, 0.48, 0.17).lerp(Color(0.38, 0.54, 0.2), n)
	return c.lerp(Color(0.2, 0.36, 0.22), f)

func _outer_land(noise: FastNoiseLite) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var cell := 8.0
	var cells := 46
	var origin := -LAND_HALF - 96.0   # a multiple of the cell size from the edge of the land
	for i in cells:
		for j in cells:
			var x0 := origin + cell * float(i)
			var z0 := origin + cell * float(j)
			var x1 := x0 + cell
			var z1 := z0 + cell
			if x0 >= -LAND_HALF and x1 <= LAND_HALF and z0 >= -LAND_HALF and z1 <= LAND_HALF:
				continue
			mb.add_quad(
				Vector3(x0, _outer_height(x0, z0, noise), z0), Vector3(x1, _outer_height(x1, z0, noise), z0),
				Vector3(x1, _outer_height(x1, z1, noise), z1), Vector3(x0, _outer_height(x0, z1, noise), z1),
				_outer_color(x0, z0, noise), _outer_color(x1, z0, noise),
				_outer_color(x1, z1, noise), _outer_color(x0, z1, noise))
	return mb.build()

# ---- Roads ----
# The main road runs east-west between the home field and the farmhouse yard. Every plot
# touches it, so a machine can always drive from the yard to any plot.

func _roads() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var asphalt := Color(0.24, 0.24, 0.26)
	var line := Color(0.85, 0.82, 0.7)
	var y := 0.025
	var h := PlotData.WORLD_HALF
	var z0 := PlotData.ROAD_Z - PlotData.ROAD_HALF
	var z1 := PlotData.ROAD_Z + PlotData.ROAD_HALF
	mb.add_flat_quad(Vector3(-h, y, z0), Vector3(h, y, z0), Vector3(h, y, z1), Vector3(-h, y, z1), asphalt)
	for zz in [z0 + 0.08, z1 - 0.2]:
		mb.add_flat_quad(Vector3(-h, y + 0.004, zz), Vector3(h, y + 0.004, zz), Vector3(h, y + 0.004, zz + 0.12), Vector3(-h, y + 0.004, zz + 0.12), line)
	var x := -h + 1.0
	while x < h - 2.0:
		mb.add_flat_quad(Vector3(x, y + 0.004, PlotData.ROAD_Z - 0.07), Vector3(x + 2.0, y + 0.004, PlotData.ROAD_Z - 0.07),
			Vector3(x + 2.0, y + 0.004, PlotData.ROAD_Z + 0.07), Vector3(x, y + 0.004, PlotData.ROAD_Z + 0.07), line)
		x += 4.0
	# A short driveway from the road to the farmhouse door
	var dirt := Color(0.5, 0.4, 0.28)
	mb.add_flat_quad(Vector3(-0.9, y, z1), Vector3(0.9, y, z1), Vector3(0.9, y, 5.2), Vector3(-0.9, y, 5.2), dirt)
	return mb.build()

# ---- Fence ----

func _fence() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var wood := Color(0.5, 0.35, 0.18)
	var rail := Color(0.6, 0.44, 0.25)
	var hh := LAND_HALF
	for k in int(hh / 2.0) + 1:
		var t := -hh + 4.0 * float(k)
		mb.add_box(Vector3(t, 0.45, -hh), Vector3(0.16, 0.9, 0.16), wood)
		mb.add_box(Vector3(t, 0.45, hh), Vector3(0.16, 0.9, 0.16), wood)
		mb.add_box(Vector3(-hh, 0.45, t), Vector3(0.16, 0.9, 0.16), wood)
		mb.add_box(Vector3(hh, 0.45, t), Vector3(0.16, 0.9, 0.16), wood)
	for y in [0.35, 0.7]:
		mb.add_box(Vector3(0, y, -hh), Vector3(2.0 * hh + 0.2, 0.07, 0.06), rail)
		mb.add_box(Vector3(0, y, hh), Vector3(2.0 * hh + 0.2, 0.07, 0.06), rail)
		mb.add_box(Vector3(-hh, y, 0), Vector3(0.06, 0.07, 2.0 * hh + 0.2), rail)
		mb.add_box(Vector3(hh, y, 0), Vector3(0.06, 0.07, 2.0 * hh + 0.2), rail)
	return mb.build()

# ---- Trees ----

func _tree_list() -> Array:
	var list: Array = []
	for i in 40:
		var a := TAU * float(i) / 40.0 + _h(i + 3) * 0.3
		var r := LAND_HALF + 8.0 + 22.0 * _h(i + 40)
		var p := Vector2(cos(a) * r, sin(a) * r)
		# push the tree out so it is outside the square fence
		var m := maxf(absf(p.x), absf(p.y))
		if m < LAND_HALF + 6.0:
			p *= (LAND_HALF + 6.0) / m
		list.append({"p": p, "s": 0.8 + 0.6 * _h(i + 80), "c": i})
	return list

func _trees() -> ArrayMesh:
	var mb := MeshBuilder.new()
	for t in _tree_list():
		var p: Vector2 = t["p"]
		var s: float = t["s"]
		var base := Vector3(p.x, -0.04, p.y)
		var up := Vector3.UP
		mb.add_prism(base, base + up * (1.7 * s), 0.24 * s, 0.14 * s, 6, Color(0.3, 0.2, 0.1), Color(0.42, 0.3, 0.17))
		var g := _h(int(t["c"]) + 7)
		var leaf0 := Color(0.18, 0.4, 0.14).lerp(Color(0.25, 0.5, 0.18), g)
		var leaf1 := Color(0.3, 0.58, 0.22).lerp(Color(0.4, 0.66, 0.25), g)
		mb.add_prism(base + up * (1.2 * s), base + up * (2.7 * s), 1.3 * s, 0.9 * s, 8, leaf0, leaf1, true)
		mb.add_prism(base + up * (2.3 * s), base + up * (3.6 * s), 1.0 * s, 0.15 * s, 8, leaf0.lerp(leaf1, 0.4), leaf1, true)
	return mb.build()

# ---- Farmhouse (front faces -z, toward the field; footprint x -2.5..2.5, z 5.5..9.5) ----

func _house() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var wall := Color(0.88, 0.82, 0.68)
	mb.add_box(Vector3(0, 0.15, 7.5), Vector3(5.2, 0.3, 4.2), Color(0.5, 0.5, 0.5), 0.0, 0.8)
	mb.add_box(Vector3(0, 1.4, 7.5), Vector3(5.0, 2.2, 4.0), wall, 0.0, 0.75)
	var rc0 := Color(0.5, 0.17, 0.12)
	var rc1 := Color(0.68, 0.26, 0.18)
	var l := -2.9
	var r := 2.9
	var y0 := 2.45
	var y1 := 4.0
	mb.add_quad(Vector3(l, y0, 5.3), Vector3(r, y0, 5.3), Vector3(r, y1, 7.5), Vector3(l, y1, 7.5), rc0, rc0, rc1, rc1)
	mb.add_quad(Vector3(l, y0, 9.7), Vector3(r, y0, 9.7), Vector3(r, y1, 7.5), Vector3(l, y1, 7.5), rc0, rc0, rc1, rc1)
	mb.add_tri(Vector3(-2.5, y0, 5.5), Vector3(-2.5, y0, 9.5), Vector3(-2.5, y1 - 0.2, 7.5), wall, wall, wall)
	mb.add_tri(Vector3(2.5, y0, 5.5), Vector3(2.5, y0, 9.5), Vector3(2.5, y1 - 0.2, 7.5), wall, wall, wall)
	mb.add_box(Vector3(0, 0.9, 5.47), Vector3(0.95, 1.7, 0.1), Color(0.35, 0.2, 0.1))
	mb.add_box(Vector3(0, 0.07, 5.2), Vector3(1.5, 0.14, 0.55), Color(0.55, 0.55, 0.55))
	var frame := Color(0.95, 0.95, 0.9)
	var glass := Color(0.22, 0.32, 0.46)
	for x in [-1.6, 1.6]:
		mb.add_box(Vector3(x, 1.5, 5.48), Vector3(0.95, 0.85, 0.08), frame)
		mb.add_box(Vector3(x, 1.5, 5.44), Vector3(0.8, 0.7, 0.06), glass)
		mb.add_box(Vector3(x, 1.5, 9.52), Vector3(0.95, 0.85, 0.08), frame)
		mb.add_box(Vector3(x, 1.5, 9.56), Vector3(0.8, 0.7, 0.06), glass)
	for sx in [-2.52, 2.52]:
		mb.add_box(Vector3(sx, 1.5, 7.5), Vector3(0.08, 0.85, 1.0), frame)
		mb.add_box(Vector3(sx * 1.003, 1.5, 7.5), Vector3(0.06, 0.7, 0.85), glass)
	mb.add_box(Vector3(1.6, 3.7, 8.3), Vector3(0.5, 1.4, 0.5), Color(0.58, 0.27, 0.2), 0.0, 0.8)
	return mb.build()

# ---- Cheap blob shadows ----

func _blob_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var c := Color(0, 0, 0, 1)
	var y := 0.03
	mb.add_flat_quad(Vector3(-2.7, y, 5.4), Vector3(2.7, y, 5.4), Vector3(2.7, y, 9.6), Vector3(-2.7, y, 9.6), c)
	mb.add_flat_quad(Vector3(-1.4, y, 3.6), Vector3(4.0, y, 3.6), Vector3(4.0, y, 7.8), Vector3(-1.4, y, 7.8), c)
	for t in _tree_list():
		var p: Vector2 = t["p"]
		var s: float = t["s"]
		var center := Vector3(p.x + 0.6 * s, y, p.y - 0.9 * s)
		for k in 8:
			var a0 := TAU * float(k) / 8.0
			var a1 := TAU * float(k + 1) / 8.0
			mb.add_tri(center, center + Vector3(cos(a0), 0.0, sin(a0)) * 1.3 * s,
				center + Vector3(cos(a1), 0.0, sin(a1)) * 1.3 * s, c, c, c)
	return mb.build()
