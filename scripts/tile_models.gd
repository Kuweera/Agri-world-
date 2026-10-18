extends RefCounted
# Ground meshes for one field tile. Tiles are exactly as big as the field pitch,
# so neighbouring tiles touch and the field looks like one continuous piece of land.
# kinds: "unploughed" (rough ground with grass tufts), "ploughed" (furrows and clods),
# "stubble" (cut stalks and straw after harvest).

const MeshBuilder := preload("res://scripts/mesh_builder.gd")

const HALF := 0.75
const BASE_Y := 0.06

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 78.233) * 43758.5453, 1.0)

static func build(kind: String, variant: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	if kind == "ploughed":
		_ploughed(mb, variant)
	elif kind == "stubble":
		_stubble(mb, variant)
	else:
		_raw(mb, variant)
	_skirt(mb)
	return mb.build()

# Dark soil edge from the tile top down to the ground (hidden between tiles).
static func _skirt(mb) -> void:
	var c := Color(0.25, 0.16, 0.09)
	var y0 := 0.0
	var y1 := BASE_Y
	mb.add_flat_quad(Vector3(-HALF, y0, -HALF), Vector3(HALF, y0, -HALF), Vector3(HALF, y1, -HALF), Vector3(-HALF, y1, -HALF), c)
	mb.add_flat_quad(Vector3(-HALF, y0, HALF), Vector3(HALF, y0, HALF), Vector3(HALF, y1, HALF), Vector3(-HALF, y1, HALF), c)
	mb.add_flat_quad(Vector3(-HALF, y0, -HALF), Vector3(-HALF, y0, HALF), Vector3(-HALF, y1, HALF), Vector3(-HALF, y1, -HALF), c)
	mb.add_flat_quad(Vector3(HALF, y0, -HALF), Vector3(HALF, y0, HALF), Vector3(HALF, y1, HALF), Vector3(HALF, y1, -HALF), c)

# Flat top split into 3x3 patches with varied colour.
static func _flat_top(mb, c_a: Color, c_b: Color, variant: int) -> void:
	var step := HALF * 2.0 / 3.0
	for i in 3:
		for j in 3:
			var x0 := -HALF + step * float(i)
			var z0 := -HALF + step * float(j)
			var col := c_a.lerp(c_b, _h(variant * 100 + i * 10 + j))
			mb.add_flat_quad(Vector3(x0, BASE_Y, z0), Vector3(x0 + step, BASE_Y, z0),
				Vector3(x0 + step, BASE_Y, z0 + step), Vector3(x0, BASE_Y, z0 + step), col)

static func _raw(mb, variant: int) -> void:
	_flat_top(mb, Color(0.40, 0.48, 0.2), Color(0.5, 0.42, 0.24), variant)
	var up := Vector3.UP
	for k in 6:
		var sd := variant * 50 + k * 7
		var base := Vector3((_h(sd) - 0.5) * 1.3, BASE_Y, (_h(sd + 1) - 0.5) * 1.3)
		for b in 3:
			var a := _h(sd + 2 + b) * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			mb.add_ribbon([base, base + dir * 0.03 + up * 0.07, base + dir * 0.07 + up * 0.14],
				[0.025, 0.02, 0.003], dir.cross(up).normalized(), Color(0.2, 0.42, 0.12), Color(0.5, 0.72, 0.28))

static func _ploughed(mb, variant: int) -> void:
	var valley := Color(0.22, 0.13, 0.07)
	for k in 5:
		var zc := -0.6 + 0.3 * float(k)
		var top_y := BASE_Y + 0.09 + (_h(variant * 31 + k) - 0.5) * 0.03
		var ridge := Color(0.42, 0.27, 0.14).lerp(Color(0.36, 0.22, 0.11), _h(variant * 17 + k))
		var z0 := zc - 0.15
		var z1 := zc + 0.15
		mb.add_quad(Vector3(-HALF, BASE_Y, z0), Vector3(HALF, BASE_Y, z0), Vector3(HALF, top_y, zc), Vector3(-HALF, top_y, zc), valley, valley, ridge, ridge)
		mb.add_quad(Vector3(-HALF, BASE_Y, z1), Vector3(HALF, BASE_Y, z1), Vector3(HALF, top_y, zc), Vector3(-HALF, top_y, zc), valley, valley, ridge, ridge)
		mb.add_tri(Vector3(-HALF, BASE_Y, z0), Vector3(-HALF, BASE_Y, z1), Vector3(-HALF, top_y, zc), valley, valley, ridge)
		mb.add_tri(Vector3(HALF, BASE_Y, z0), Vector3(HALF, BASE_Y, z1), Vector3(HALF, top_y, zc), valley, valley, ridge)
	for k in 6:
		var sd := variant * 60 + k * 11
		var pos := Vector3((_h(sd) - 0.5) * 1.3, BASE_Y + 0.1, (_h(sd + 1) - 0.5) * 1.3)
		var s := 0.05 + 0.05 * _h(sd + 2)
		mb.add_box(pos, Vector3(s, s * 0.7, s), Color(0.3, 0.19, 0.1), _h(sd + 3) * PI, 0.8)

static func _stubble(mb, variant: int) -> void:
	_flat_top(mb, Color(0.5, 0.38, 0.22), Color(0.42, 0.32, 0.19), variant)
	var up := Vector3.UP
	var spots := [Vector2(-0.36, -0.36), Vector2(0.36, -0.36), Vector2(-0.36, 0.36), Vector2(0.36, 0.36)]
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var sd := variant * 70 + i * 9
		var base := Vector3(sp.x + (_h(sd) - 0.5) * 0.16, BASE_Y, sp.y + (_h(sd + 1) - 0.5) * 0.16)
		mb.add_prism(base, base + up * (0.1 + 0.08 * _h(sd + 2)), 0.035, 0.028, 5,
			Color(0.55, 0.45, 0.22), Color(0.82, 0.72, 0.4), true)
	for k in 7:
		var sd := variant * 80 + k * 5
		var start := Vector3((_h(sd) - 0.5) * 1.2, BASE_Y + 0.012, (_h(sd + 1) - 0.5) * 1.2)
		var a := _h(sd + 2) * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		mb.add_ribbon([start, start + dir * 0.18, start + dir * 0.36], [0.03, 0.035, 0.01],
			Vector3.UP.cross(dir).normalized(), Color(0.7, 0.6, 0.3), Color(0.85, 0.75, 0.42))
