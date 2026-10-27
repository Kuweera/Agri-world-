extends Node3D
# Presentation only: scenery plus the 8x8 field of tile nodes and the crops on them.
# The tile DATA lives in game_state.gd. farm_main.gd calls refresh_tile().

const GameStateScript := preload("res://scripts/game_state.gd")
const CropModels := preload("res://scripts/crop_models.gd")
const TileModels := preload("res://scripts/tile_models.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const FarmSceneryScript := preload("res://scripts/farm_scenery.gd")
const CropData := preload("res://scripts/crop_data.gd")
const PlotData := preload("res://scripts/plot_data.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")

const SOIL_TEXTURE := "res://assets/textures/soil.png"
const GRASS_TEXTURE := "res://assets/textures/grass.png"

const PITCH := 1.5
const FIELD_CENTER := Vector3(0, 0, -4)

var cols: int = GameStateScript.COLS     # the home field (kept for older code and tests)
var rows: int = GameStateScript.ROWS
var built_plots: Array = []   # ids of the plots that have tile nodes, in the same order as GameState.plots
var lots: Dictionary = {}     # plot id -> {"mesh": MeshInstance3D, "sign": Node3D} for plots not owned yet
var tile_nodes: Array = []
var tile_keys: Array = []
var crop_nodes: Array = []
var crop_keys: Array = []
var mesh_cache := {}
var detail := 1            # crop detail: 0 = lighter, 1 = full
var mat_vc: StandardMaterial3D
var mat_crop: StandardMaterial3D   # leaf-card atlas for crops
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
	mat_crop = MeshBuilder.card_material(CropModels.ATLAS)
	scenery = FarmSceneryScript.new()
	mat_ground = MeshBuilder.textured_material(SOIL_TEXTURE, 0.7, 1.25)
	mat_land = MeshBuilder.textured_material(GRASS_TEXTURE, 0.35, 1.25)
	scenery.build(self, mat_vc, mat_land)

	# Build all ground and crop meshes now, so nothing is created mid-game.
	for kind in ["unploughed", "ploughed", "stubble"]:
		for v in 3:
			_tile_mesh(kind, v)
	_prebuild_crops()

	build_plot(PlotData.HOME)
	for p in PlotData.PLOTS:
		if p["id"] != PlotData.HOME:
			_make_lot(str(p["id"]))

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

# Creates the tile nodes of a plot. Call it for each owned plot in the order they were bought,
# so node i belongs to GameState.tiles[i].
func build_plot(id: String) -> void:
	if built_plots.has(id) or not PlotData.has_plot(id):
		return
	var p := PlotData.get_plot(id)
	var pc := int(p["cols"])
	var pr := int(p["rows"])
	for row in pr:
		for col in pc:
			var i := tile_nodes.size()
			var mi := MeshInstance3D.new()
			mi.material_override = mat_ground
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(PlotData.col_x(id, col), 0.0, PlotData.row_z(id, row))
			mi.mesh = _tile_mesh("unploughed", _variant(i, 3))
			add_child(mi)
			tile_nodes.append(mi)
			tile_keys.append("unploughed:%d" % _variant(i, 3))
			crop_nodes.append(null)
			crop_keys.append("")
	built_plots.append(id)
	_remove_lot(id)

# Back to the home field only (a new game): removes the other plots' tiles and puts the signs back.
func reset_plots() -> void:
	var home_n := PlotData.tile_count(PlotData.HOME)
	for i in range(tile_nodes.size() - 1, home_n - 1, -1):
		(tile_nodes[i] as Node).queue_free()
		if crop_nodes[i] != null:
			(crop_nodes[i] as Node).queue_free()
	tile_nodes.resize(home_n)
	tile_keys.resize(home_n)
	crop_nodes.resize(home_n)
	crop_keys.resize(home_n)
	var removed: Array = built_plots.duplicate()
	removed.erase(PlotData.HOME)
	built_plots = [PlotData.HOME]
	for id in removed:
		_make_lot(str(id))
	if cursor != null:
		cursor.visible = false
	cursor_index = -1

# A plot that is for sale: its ground, a boundary and a sign with its name, size and price.
func _make_lot(id: String) -> void:
	var p := PlotData.get_plot(id)
	var r := PlotData.rect_of(id)
	var mb := MeshBuilder.new()
	var y := 0.014
	var grass := Color(0.44, 0.58, 0.24)
	mb.add_flat_quad(Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y),
		Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), grass)
	var post := Color(0.9, 0.8, 0.25)
	var t := 0.18
	for rect in [
		[r.position.x, r.position.y, r.size.x, t], [r.position.x, r.end.y - t, r.size.x, t],
		[r.position.x, r.position.y, t, r.size.y], [r.end.x - t, r.position.y, t, r.size.y]]:
		mb.add_flat_quad(Vector3(rect[0], y + 0.004, rect[1]), Vector3(rect[0] + rect[2], y + 0.004, rect[1]),
			Vector3(rect[0] + rect[2], y + 0.004, rect[1] + rect[3]), Vector3(rect[0], y + 0.004, rect[1] + rect[3]), post)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.material_override = mat_vc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Sign at the road side of the plot
	var gate := PlotData.gate_of(id)
	var sign_node := Node3D.new()
	var sb := MeshBuilder.new()
	sb.add_box(Vector3(0, 0.9, 0), Vector3(0.12, 1.8, 0.12), Color(0.4, 0.28, 0.14))
	sb.add_box(Vector3(0, 1.9, 0), Vector3(3.6, 1.3, 0.1), Color(0.93, 0.9, 0.78))
	var board := MeshInstance3D.new()
	board.mesh = sb.build()
	board.material_override = mat_vc
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_node.add_child(board)
	var label := Label3D.new()
	label.text = "FOR SALE\n%s\n%s  (%d tiles)\n%d" % [str(p["name"]), str(p["size"]), PlotData.tile_count(id), PlotData.price_of(id)]
	label.font_size = 48
	label.pixel_size = 0.0055
	label.modulate = Color(0.12, 0.1, 0.05)
	label.outline_size = 0
	label.position = Vector3(0, 1.9, 0.07)
	sign_node.add_child(label)
	var back: Label3D = label.duplicate() as Label3D
	back.position = Vector3(0, 1.9, -0.07)
	back.rotation.y = PI
	sign_node.add_child(back)
	var side_dir := -1.0 if str(p["side"]) == "n" else 1.0   # towards the road
	sign_node.position = Vector3(gate.x, 0.0, gate.y + side_dir * 0.5)
	add_child(sign_node)
	lots[id] = {"mesh": mi, "sign": sign_node}

func _remove_lot(id: String) -> void:
	if not lots.has(id):
		return
	var l: Dictionary = lots[id]
	(l["mesh"] as Node).queue_free()
	(l["sign"] as Node).queue_free()
	lots.erase(id)

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
		for stage in CropModels.STAGE_COUNT:
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

# Tile index across all built plots, same order as GameState.tiles. -1 if no tile is there.
func world_to_tile(p: Vector3) -> int:
	return FarmLayout.world_to_tile(p.x, p.z, built_plots if not built_plots.is_empty() else FarmLayout.HOME_ONLY)

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
			crop.material_override = mat_crop
			crop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			crop.position = Vector3(node.position.x, TileModels.BASE_Y, node.position.z)
			# No rotation: the rows of plants must run along the soil ridges.
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
