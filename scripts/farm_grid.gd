extends Node3D
# Presentation only: land, boundary, farmhouse and the 8x8 field of tile nodes.
# The tile DATA lives in game_state.gd. farm_main.gd calls refresh_tile().

const GameStateScript := preload("res://scripts/game_state.gd")
const CropModels := preload("res://scripts/crop_models.gd")

const LAND_HALF := 12.0
const PITCH := 1.5
const TILE_SIZE := 1.4
const FIELD_CENTER := Vector3(0, 0, -4)

var cols: int = GameStateScript.COLS
var rows: int = GameStateScript.ROWS
var tile_nodes: Array = []
var crop_nodes: Array = []
var crop_keys: Array = []
var crop_mesh_cache := {}
var mat_raw := StandardMaterial3D.new()
var mat_ploughed := StandardMaterial3D.new()
var mat_sel := StandardMaterial3D.new()
var mat_crop := StandardMaterial3D.new()

func _box(size: Vector3, pos: Vector3, color: Color, casts_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _ready() -> void:
	mat_raw.albedo_color = Color(0.55, 0.42, 0.25)
	mat_ploughed.albedo_color = Color(0.3, 0.18, 0.08)
	mat_sel.albedo_color = Color(0.95, 0.8, 0.2)
	mat_crop.vertex_color_use_as_albedo = true

	# Outside ground and owned land (flat, so they never need to cast shadows)
	_box(Vector3(120, 0.2, 120), Vector3(0, -0.25, 0), Color(0.25, 0.45, 0.2), false)
	_box(Vector3(24, 0.2, 24), Vector3(0, -0.1, 0), Color(0.4, 0.62, 0.3), false)

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
	for row in rows:
		for col in cols:
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = mat_raw
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(
				FIELD_CENTER.x + (col - (cols - 1) / 2.0) * PITCH,
				0.05,
				FIELD_CENTER.z + (row - (rows - 1) / 2.0) * PITCH)
			add_child(mi)
			tile_nodes.append(mi)
			crop_nodes.append(null)
			crop_keys.append("")

# Index = row * cols + col, same order as GameState.tiles.
func world_to_tile(p: Vector3) -> int:
	var lx := p.x - FIELD_CENTER.x + cols * PITCH / 2.0
	var lz := p.z - FIELD_CENTER.z + rows * PITCH / 2.0
	if lx < 0.0 or lz < 0.0:
		return -1
	var col := int(lx / PITCH)
	var row := int(lz / PITCH)
	if col >= cols or row >= rows:
		return -1
	return row * cols + col

func _crop_mesh(crop_id: String, stage: int) -> ArrayMesh:
	var key := "%s:%d" % [crop_id, stage]
	if not crop_mesh_cache.has(key):
		crop_mesh_cache[key] = CropModels.build(crop_id, stage)
	return crop_mesh_cache[key]

func refresh_tile(i: int, tile: Dictionary, progress: float, is_selected: bool) -> void:
	var node: MeshInstance3D = tile_nodes[i]
	if is_selected:
		node.material_override = mat_sel
	elif tile["state"] == "unploughed":
		node.material_override = mat_raw
	else:
		node.material_override = mat_ploughed

	var crop = crop_nodes[i]
	if tile["state"] == "growing":
		var crop_id: String = tile["crop"]
		var stage := CropModels.stage_for(progress)
		var key := "%s:%d" % [crop_id, stage]
		if crop == null:
			crop = MeshInstance3D.new()
			crop.material_override = mat_crop
			crop.position = Vector3(node.position.x, 0.1, node.position.z)
			add_child(crop)
			crop_nodes[i] = crop
		if crop_keys[i] != key:
			crop_keys[i] = key
			crop.mesh = _crop_mesh(crop_id, stage)
		crop.visible = true
	elif crop != null:
		crop.visible = false
		crop_keys[i] = ""
