extends Node3D
# The farm: land, boundary, farmhouse and one 8x8 field of tiles.
# Tile DATA lives in `tiles` (plain dictionaries) so later stages can add
# crops and saving without touching the 3D nodes.

signal selection_changed(index: int)

const LAND_HALF := 12.0
const COLS := 8
const ROWS := 8
const PITCH := 1.5
const TILE_SIZE := 1.4
const FIELD_CENTER := Vector3(0, 0, -4)

var tiles: Array = []
var tile_nodes: Array = []
var selected := -1
var mat_soil := StandardMaterial3D.new()
var mat_sel := StandardMaterial3D.new()

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi

func _ready() -> void:
	mat_soil.albedo_color = Color(0.45, 0.3, 0.15)
	mat_sel.albedo_color = Color(0.95, 0.8, 0.2)

	# Outside ground and owned land
	_box(Vector3(120, 0.2, 120), Vector3(0, -0.25, 0), Color(0.25, 0.45, 0.2))
	_box(Vector3(24, 0.2, 24), Vector3(0, -0.1, 0), Color(0.4, 0.62, 0.3))

	# Land boundary (four low fence strips)
	var fence := Color(0.5, 0.35, 0.2)
	_box(Vector3(24.4, 0.6, 0.4), Vector3(0, 0.3, -LAND_HALF), fence)
	_box(Vector3(24.4, 0.6, 0.4), Vector3(0, 0.3, LAND_HALF), fence)
	_box(Vector3(0.4, 0.6, 24.4), Vector3(-LAND_HALF, 0.3, 0), fence)
	_box(Vector3(0.4, 0.6, 24.4), Vector3(LAND_HALF, 0.3, 0), fence)

	# Farmhouse: box body + prism roof
	_box(Vector3(5, 2.5, 4), Vector3(0, 1.25, 7.5), Color(0.9, 0.85, 0.7))
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(5.4, 1.6, 4.4)
	roof.mesh = pm
	roof.position = Vector3(0, 3.3, 7.5)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.7, 0.25, 0.2)
	roof.material_override = roof_mat
	add_child(roof)

	# Field tiles (shared mesh + shared materials, so they are cheap)
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(TILE_SIZE, 0.1, TILE_SIZE)
	for row in ROWS:
		for col in COLS:
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = mat_soil
			mi.position = Vector3(
				FIELD_CENTER.x + (col - (COLS - 1) / 2.0) * PITCH,
				0.05,
				FIELD_CENTER.z + (row - (ROWS - 1) / 2.0) * PITCH)
			add_child(mi)
			tile_nodes.append(mi)
			tiles.append({"col": col, "row": row, "state": "unplowed"})

func world_to_tile(p: Vector3) -> int:
	var lx := p.x - FIELD_CENTER.x + COLS * PITCH / 2.0
	var lz := p.z - FIELD_CENTER.z + ROWS * PITCH / 2.0
	if lx < 0.0 or lz < 0.0:
		return -1
	var col := int(lx / PITCH)
	var row := int(lz / PITCH)
	if col >= COLS or row >= ROWS:
		return -1
	return row * COLS + col

func select_tile(i: int) -> void:
	if selected >= 0:
		tile_nodes[selected].material_override = mat_soil
	selected = i
	if selected >= 0:
		tile_nodes[selected].material_override = mat_sel
	selection_changed.emit(selected)

func tile_text(i: int) -> String:
	if i < 0 or i >= tiles.size():
		return "Tap a tile"
	var t: Dictionary = tiles[i]
	return "Field tile %d, %d\nSoil: %s\nCrop: none" % [t["col"] + 1, t["row"] + 1, t["state"]]
