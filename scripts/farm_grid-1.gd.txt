extends Node3D
# Presentation only: scenery plus the 8x8 field of tile nodes and the crops on them.
# The tile DATA lives in game_state.gd. farm_main.gd calls refresh_tile().

const GameStateScript := preload("res://scripts/game_state.gd")
const CropModels := preload("res://scripts/crop_models.gd")
const TileModels := preload("res://scripts/tile_models.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const FarmSceneryScript := preload("res://scripts/farm_scenery.gd")
const CropData := preload("res://scripts/crop_data.gd")

const SOIL_TEXTURE := "res://assets/textures/soil.png"
const GRASS_TEXTURE := "res://assets/textures/grass.png"

const PITCH := 1.5
const FIELD_CENTER := Vector3(0, 0, -4)

var cols: int = GameStateScript.COLS
var rows: int = GameStateScript.ROWS
var tile_nodes: Array = []
var tile_keys: Array = []
var crop_nodes: Array = []
var crop_keys: Array = []
var mesh_cache := {}
var detail := 1            # crop detail: 0 = lighter, 1 = full
var mat_vc: StandardMaterial3D
var mat_ground: StandardMaterial3D
var mat_land: StandardMaterial3D
var cursor: MeshInstance3D
var cursor_index := -1
var scenery

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 4.1) * 43758.5453, 1.0)

func _variant(i: int, n: int) -> int:
	return mini(n - 1, int(_h(i * 7 + 3) * float(n)))

func _ready() -> void:
	mat_vc = MeshBuilder.vc_material()
	scenery = FarmSceneryScript.new()
	mat_ground = MeshBuilder.textured_material(SOIL_TEXTURE, 0.7, 1.25)
	mat_land = MeshBuilder.textured_material(GRASS_TEXTURE, 0.35, 1.25)
	scenery.build(self, mat_vc, mat_land)

	# Build all ground and crop meshes now, so nothing is created mid-game.
	for kind in ["unploughed", "ploughed", "stubble"]:
		for v in 3:
			_tile_mesh(kind, v)
	_prebuild_crops()

	for row in rows:
		for col in cols:
			var i := row * cols + col
			var mi := MeshInstance3D.new()
			mi.material_override = mat_ground
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(
				FIELD_CENTER.x + (col - (cols - 1) / 2.0) * PITCH, 0.0,
				FIELD_CENTER.z + (row - (rows - 1) / 2.0) * PITCH)
			mi.mesh = _tile_mesh("unploughed", _variant(i, 3))
			add_child(mi)
			tile_nodes.append(mi)
			tile_keys.append("unploughed:%d" % _variant(i, 3))
			crop_nodes.append(null)
			crop_keys.append("")

	# Selection frame (one node, moved to the selected tile)
	var cb := MeshBuilder.new()
	var yellow := Color(1.0, 0.85, 0.2)
	cb.add_box(Vector3(0, 0, -0.71), Vector3(1.46, 0.05, 0.08), yellow, 0.0, 1.0)
	cb.add_box(Vector3(0, 0, 0.71), Vector3(1.46, 0.05, 0.08), yellow, 0.0, 1.0)
	cb.add_box(Vector3(-0.71, 0, 0), Vector3(0.08, 0.05, 1.46), yellow, 0.0, 1.0)
	cb.add_box(Vector3(0.71, 0, 0), Vector3(0.08, 0.05, 1.46), yellow, 0.0, 1.0)
	cursor = MeshInstance3D.new()
	cursor.mesh = cb.build()
	cursor.material_override = MeshBuilder.vc_material(true)
	cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cursor.visible = false
	add_child(cursor)

func _tile_mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "t:%s:%d" % [kind, variant]
	if not mesh_cache.has(key):
		mesh_cache[key] = TileModels.build(kind, variant)
	return mesh_cache[key]

func _crop_mesh(crop_id: String, stage: int, variant: int) -> ArrayMesh:
	var key := "c:%s:%d:%d:%d" % [crop_id, stage, variant, detail]
	if not mesh_cache.has(key):
		mesh_cache[key] = CropModels.build(crop_id, stage, variant, detail)
	return mesh_cache[key]

func _prebuild_crops() -> void:
	for crop_id in CropData.CROPS:
		for stage in 3:
			for v in 2:
				_crop_mesh(crop_id, stage, v)

# Crop detail 0 (fewer plants and leaves) or 1 (full). Call refresh_tile for all tiles afterwards.
func set_detail(d: int) -> void:
	if d == detail:
		return
	detail = d
	for i in crop_keys.size():
		crop_keys[i] = ""
	if tile_nodes.size() > 0:
		_prebuild_crops()

func set_blob_shadows(on: bool) -> void:
	if scenery != null:
		scenery.set_blob_visible(on)

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

func refresh_tile(i: int, tile: Dictionary, progress: float, is_selected: bool) -> void:
	var node: MeshInstance3D = tile_nodes[i]
	var st: String = tile["state"]
	var kind := "ploughed"
	if st == "unploughed" or st == "stubble":
		kind = st
	var tkey := "%s:%d" % [kind, _variant(i, 3)]
	if tile_keys[i] != tkey:
		tile_keys[i] = tkey
		node.mesh = _tile_mesh(kind, _variant(i, 3))

	var crop = crop_nodes[i]
	if st == "growing":
		var crop_id: String = tile["crop"]
		var stage := CropModels.stage_for(progress)
		var cv := _variant(i, 2)
		var key := "%s:%d:%d" % [crop_id, stage, detail]
		if crop == null:
			crop = MeshInstance3D.new()
			crop.material_override = mat_vc
			crop.position = Vector3(node.position.x, TileModels.BASE_Y, node.position.z)
			crop.rotation.y = float(int(_h(i + 11) * 4.0)) * PI / 2.0
			add_child(crop)
			crop_nodes[i] = crop
		if crop_keys[i] != key:
			crop_keys[i] = key
			crop.mesh = _crop_mesh(crop_id, stage, cv)
		crop.visible = true
	elif crop != null:
		crop.visible = false
		crop_keys[i] = ""

	if is_selected:
		cursor_index = i
		cursor.position = Vector3(node.position.x, TileModels.BASE_Y + 0.16, node.position.z)
		cursor.visible = true
	elif cursor_index == i:
		cursor_index = -1
		cursor.visible = false
