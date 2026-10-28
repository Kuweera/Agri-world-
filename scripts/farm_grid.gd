extends Node3D
# Presentation only: scenery, the plots' soil and crops, and the for-sale land.
# The tile DATA lives in game_state.gd. farm_main.gd calls refresh_tile().
#
# Tiles are drawn in batches: every plot is cut into chunks of CHUNK x CHUNK tiles, and in each
# chunk all tiles that look the same (same soil, same crop at the same growth stage) are ONE
# MultiMesh. A plot with hundreds of tiles costs only a handful of draw calls, and chunks far from
# the camera are not drawn at all.

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
const FIELD_CENTER := Vector3(0, 0, -9.4)   # the home field (PlotData "farm")
const CHUNK := 8               # tiles per chunk side
const GROUND_RANGE := 320.0    # soil is drawn this far from the camera
const CROP_RANGE := 95.0       # crops are drawn this far from the camera
const LOT_RANGE := 300.0

var cols: int = GameStateScript.COLS     # the home field (kept for older code and tests)
var rows: int = GameStateScript.ROWS
var built_plots: Array = []   # ids of the plots that have tiles, in the same order as GameState.plots
var lots: Dictionary = {}     # plot id -> {"mesh": MeshInstance3D, "sign": Node3D} for plots not owned yet
var tile_pos: Array = []      # world position of each tile (index = GameState tile index)
var tile_chunk: Array = []    # the chunk each tile belongs to
var tile_gkey: Array = []     # ground batch key of each tile ("" = none)
var tile_gslot: Array = []
var tile_ckey: Array = []     # crop batch key of each tile ("" = no crop)
var tile_cslot: Array = []
var chunks: Array = []
var mesh_cache := {}
var quality := 0              # graphics quality 0 Low, 1 Medium, 2 High (sets the crop detail layers)
var mat_vc: StandardMaterial3D
var mat_crop: StandardMaterial3D   # leaf-card atlas for crops
var mat_ground: StandardMaterial3D
var mat_land: StandardMaterial3D
var frame: MeshInstance3D          # outline of the selected plot
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

	frame = MeshInstance3D.new()
	frame.material_override = MeshBuilder.vc_material(true)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.visible = false
	add_child(frame)

# ---- Plots ----

# Creates the tiles of a plot. Call it for each owned plot in the order they were bought,
# so tile i here is GameState.tiles[i].
func build_plot(id: String) -> void:
	if built_plots.has(id) or not PlotData.has_plot(id):
		return
	var p := PlotData.get_plot(id)
	var pc := int(p["cols"])
	var pr := int(p["rows"])
	var by_key := {}
	for row in pr:
		for col in pc:
			var i := tile_pos.size()
			var ck := "%d:%d" % [floori(float(col) / float(CHUNK)), floori(float(row) / float(CHUNK))]
			if not by_key.has(ck):
				var c0 := floori(float(col) / float(CHUNK)) * CHUNK
				var r0 := floori(float(row) / float(CHUNK)) * CHUNK
				var c1 := mini(pc, c0 + CHUNK) - 1
				var r1 := mini(pr, r0 + CHUNK) - 1
				var chunk := {
					"plot": id,
					"center": Vector3((PlotData.col_x(id, c0) + PlotData.col_x(id, c1)) / 2.0, 0.0,
						(PlotData.row_z(id, r0) + PlotData.row_z(id, r1)) / 2.0),
					"capacity": (c1 - c0 + 1) * (r1 - r0 + 1),
					"ground": {},
					"crops": {},
				}
				by_key[ck] = chunk
				chunks.append(chunk)
			tile_pos.append(Vector3(PlotData.col_x(id, col), 0.0, PlotData.row_z(id, row)))
			tile_chunk.append(by_key[ck])
			tile_gkey.append("")
			tile_gslot.append(-1)
			tile_ckey.append("")
			tile_cslot.append(-1)
			_set_ground(i, "unploughed", _variant(i, 3))
	built_plots.append(id)
	_remove_lot(id)

# Back to the home field only (a new game): removes the other plots and puts the signs back.
func reset_plots() -> void:
	var home_n := PlotData.tile_count(PlotData.HOME)
	var keep: Array = []
	for ch in chunks:
		if ch["plot"] == PlotData.HOME:
			keep.append(ch)
			continue
		_free_batches(ch, "ground")
		_free_batches(ch, "crops")
	chunks = keep
	for arr in [tile_pos, tile_chunk, tile_gkey, tile_gslot, tile_ckey, tile_cslot]:
		(arr as Array).resize(home_n)
	var removed: Array = built_plots.duplicate()
	removed.erase(PlotData.HOME)
	built_plots = [PlotData.HOME]
	for id in removed:
		_make_lot(str(id))
	if frame != null:
		frame.visible = false

# ---- Batches ----

# Crop detail by distance from the camera: each layer is drawn between `begin` and `end` units from the
# camera. detail 2 = dense plants, 1 = medium, 0 = a few big plants. Weaker settings draw dense plants
# only very close (or never) because overlapping leaf cards cost a lot on weak graphics chips.
func _lod_layers() -> Array:
	if quality <= 0:
		return [{"detail": 1, "begin": 0.0, "end": 10.0}, {"detail": 0, "begin": 8.0, "end": 40.0}]
	if quality == 1:
		return [{"detail": 2, "begin": 0.0, "end": 11.0}, {"detail": 1, "begin": 9.0, "end": 26.0}, {"detail": 0, "begin": 22.0, "end": 60.0}]
	return [{"detail": 3, "begin": 0.0, "end": 14.0}, {"detail": 2, "begin": 11.0, "end": 30.0},
		{"detail": 1, "begin": 26.0, "end": 50.0}, {"detail": 0, "begin": 46.0, "end": 90.0}]

# Soil detail by distance: full ridges and clods close up, stripes further out, one flat square far away.
# (A ploughed tile has about 110 triangles, so thousands of tiles in view are too much for a weak phone.)
func _ground_layers() -> Array:
	var near: float = [12.0, 16.0, 22.0][clampi(quality, 0, 2)]
	var far_start: float = [38.0, 46.0, 60.0][clampi(quality, 0, 2)]
	return [{"begin": 0.0, "end": near}, {"begin": near - 3.0, "end": far_start + 3.0}, {"begin": far_start, "end": GROUND_RANGE}]

# Adds tile i to the batch `key` of a chunk's group ("ground" or "crops"), creating the batch (one
# MultiMeshInstance3D per layer) when needed. meshes/begins/ends have one entry per layer.
func _batch_add(ch: Dictionary, group: String, key: String, meshes: Array, mats: Array, begins: Array, ends: Array,
		i: int, slots: Array, y: float) -> void:
	var dict: Dictionary = ch[group]
	var b: Dictionary
	if dict.has(key):
		b = dict[key]
	else:
		var mms: Array = []
		var mmis: Array = []
		var half := float(CHUNK) * PITCH * 0.5 + 2.5
		for k in meshes.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[k]
			mm.instance_count = int(ch["capacity"])
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mats[k]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.position = ch["center"]
			mmi.custom_aabb = AABB(Vector3(-half, -0.5, -half), Vector3(half * 2.0, 4.0, half * 2.0))
			mmi.visibility_range_begin = float(begins[k])
			mmi.visibility_range_end = float(ends[k])
			add_child(mmi)
			mms.append(mm)
			mmis.append(mmi)
		b = {"mms": mms, "mmis": mmis, "tiles": []}
		dict[key] = b
	var tiles: Array = b["tiles"]
	var slot := tiles.size()
	tiles.append(i)
	slots[i] = slot
	var xf := Transform3D(Basis.IDENTITY, (tile_pos[i] as Vector3) - (ch["center"] as Vector3) + Vector3(0, y, 0))
	for mm2 in b["mms"]:
		(mm2 as MultiMesh).set_instance_transform(slot, xf)
		(mm2 as MultiMesh).visible_instance_count = slot + 1

func _batch_remove(ch: Dictionary, group: String, key: String, i: int, slots: Array, y: float) -> void:
	var b: Dictionary = (ch[group] as Dictionary)[key]
	var tiles: Array = b["tiles"]
	var slot: int = slots[i]
	var last := tiles.size() - 1
	if slot != last:
		var other: int = tiles[last]
		tiles[slot] = other
		slots[other] = slot
		var xf := Transform3D(Basis.IDENTITY, (tile_pos[other] as Vector3) - (ch["center"] as Vector3) + Vector3(0, y, 0))
		for mm in b["mms"]:
			(mm as MultiMesh).set_instance_transform(slot, xf)
	tiles.pop_back()
	for mm3 in b["mms"]:
		(mm3 as MultiMesh).visible_instance_count = tiles.size()
	slots[i] = -1

func _free_batches(ch: Dictionary, group: String) -> void:
	for key in ch[group]:
		for mmi in (ch[group][key] as Dictionary)["mmis"]:
			(mmi as Node).queue_free()
	ch[group] = {}

func _set_ground(i: int, kind: String, variant: int, crop_id: String = "", stage: int = 0) -> void:
	var key := "%s:%d" % [kind, variant]
	if crop_id != "":
		key = "g:%s:%d:%d" % [crop_id, stage, variant]
	if tile_gkey[i] == key:
		return
	var ch: Dictionary = tile_chunk[i]
	if tile_gkey[i] != "":
		_batch_remove(ch, "ground", tile_gkey[i], i, tile_gslot, 0.0)
	tile_gkey[i] = key
	var meshes := [_tile_mesh(kind, variant), _lite_mesh(kind, crop_id, stage), _flat_mesh(kind, crop_id, stage)]
	var mats := [mat_ground, mat_ground, mat_vc]
	var begins: Array = []
	var ends: Array = []
	for layer in _ground_layers():
		begins.append(float(layer["begin"]))
		ends.append(float(layer["end"]))
	_batch_add(ch, "ground", key, meshes, mats, begins, ends, i, tile_gslot, 0.0)

func _set_crop(i: int, key: String, crop_id: String, stage: int, variant: int) -> void:
	if tile_ckey[i] == key:
		return
	var ch: Dictionary = tile_chunk[i]
	if tile_ckey[i] != "":
		_batch_remove(ch, "crops", tile_ckey[i], i, tile_cslot, TileModels.BASE_Y)
	tile_ckey[i] = key
	if key != "":
		var meshes: Array = []
		var begins: Array = []
		var ends: Array = []
		for layer in _lod_layers():
			meshes.append(_crop_mesh(crop_id, stage, variant, int(layer["detail"])))
			begins.append(float(layer["begin"]))
			ends.append(float(layer["end"]))
		var mats: Array = []
		for k in meshes.size():
			mats.append(mat_crop)
		_batch_add(ch, "crops", key, meshes, mats, begins, ends, i, tile_cslot, TileModels.BASE_Y)

func _lite_mesh(kind: String, crop_id: String = "", stage: int = 0) -> ArrayMesh:
	var key := "l:%s:%s:%d" % [kind, crop_id, stage]
	if not mesh_cache.has(key):
		var tint := Color(0, 0, 0, 0)
		if crop_id != "":
			tint = TileModels.far_color(kind, crop_id, stage)
		mesh_cache[key] = TileModels.build_lite(kind, tint)
	return mesh_cache[key]

func _flat_mesh(kind: String, crop_id: String, stage: int) -> ArrayMesh:
	var key := "f:%s:%s:%d" % [kind, crop_id, stage]
	if not mesh_cache.has(key):
		mesh_cache[key] = TileModels.build_flat(TileModels.far_color(kind, crop_id, stage))
	return mesh_cache[key]

func _tile_mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "t:%s:%d" % [kind, variant]
	if not mesh_cache.has(key):
		mesh_cache[key] = TileModels.build(kind, variant)
	return mesh_cache[key]

func _crop_mesh(crop_id: String, stage: int, variant: int, detail: int) -> ArrayMesh:
	var key := "c:%s:%d:%d:%d" % [crop_id, stage, variant, detail]
	if not mesh_cache.has(key):
		mesh_cache[key] = CropModels.build(crop_id, stage, variant, detail)
	return mesh_cache[key]

func _prebuild_crops() -> void:
	for crop_id in CropData.CROPS:
		for stage in CropModels.STAGE_COUNT:
			for v in 2:
				for layer in _lod_layers():
					_crop_mesh(crop_id, stage, v, int(layer["detail"]))

# Graphics quality 0 Low, 1 Medium, 2 High: sets the crop detail layers. Call refresh_tile for all
# tiles afterwards (the crop batches are rebuilt).
func set_quality(q: int) -> void:
	if q == quality and not tile_ckey.is_empty():
		return
	quality = q
	for ch in chunks:
		_free_batches(ch, "crops")
		_free_batches(ch, "ground")
	for i in tile_ckey.size():
		tile_ckey[i] = ""
		tile_cslot[i] = -1
		tile_gkey[i] = ""
		tile_gslot[i] = -1
	_prebuild_crops()

func set_blob_shadows(on: bool) -> void:
	if scenery != null:
		scenery.set_blob_visible(on)

# Tile index across all built plots, same order as GameState.tiles. -1 if no tile is there.
func world_to_tile(p: Vector3) -> int:
	return FarmLayout.world_to_tile(p.x, p.z, built_plots if not built_plots.is_empty() else FarmLayout.HOME_ONLY)

func refresh_tile(i: int, tile: Dictionary, progress: float, _is_selected: bool = false) -> void:
	var st: String = tile["state"]
	if st == "growing":
		var crop_id: String = tile["crop"]
		var stage := CropModels.stage_for(progress)
		var cv := _variant(i, 2)
		_set_ground(i, "ploughed", _variant(i, 3), crop_id, stage)
		_set_crop(i, "%s:%d:%d" % [crop_id, stage, cv], crop_id, stage, cv)
	else:
		var kind := "ploughed"
		if st == "unploughed" or st == "stubble":
			kind = st
		_set_ground(i, kind, _variant(i, 3))
		_set_crop(i, "", "", 0, 0)

# ---- Selected plot outline ----

func show_plot_frame(id: String) -> void:
	if frame == null or not PlotData.has_plot(id):
		return
	var r := PlotData.rect_of(id).grow(0.8)
	var mb := MeshBuilder.new()
	var col := Color(1.0, 0.88, 0.2)
	var t := 0.5
	var y := 0.12
	for e in [[r.position.x, r.position.y, r.size.x, t], [r.position.x, r.end.y - t, r.size.x, t],
			[r.position.x, r.position.y, t, r.size.y], [r.end.x - t, r.position.y, t, r.size.y]]:
		mb.add_flat_quad(Vector3(e[0], y, e[1]), Vector3(e[0] + e[2], y, e[1]),
			Vector3(e[0] + e[2], y, e[1] + e[3]), Vector3(e[0], y, e[1] + e[3]), col)
	frame.mesh = mb.build()
	frame.visible = true

func hide_plot_frame() -> void:
	if frame != null:
		frame.visible = false

# ---- Land for sale ----
# Wild land with patchy ground, a fence, bushes and stones, and a sign with the name, size and price.

func _make_lot(id: String) -> void:
	var p := PlotData.get_plot(id)
	var r := PlotData.rect_of(id)
	var noise := FastNoiseLite.new()
	noise.seed = 100 + int(id.substr(1)) if id.length() > 1 and id.substr(1).is_valid_int() else 7
	noise.frequency = 0.06
	var mb := MeshBuilder.new()
	var y := 0.014
	var c := 3.0
	var nx := int(ceil(r.size.x / c))
	var nz := int(ceil(r.size.y / c))
	for i in nx:
		for j in nz:
			var x0 := r.position.x + float(i) * c
			var z0 := r.position.y + float(j) * c
			var x1 := minf(x0 + c, r.end.x)
			var z1 := minf(z0 + c, r.end.y)
			mb.add_flat_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
				_lot_color(noise, (x0 + x1) / 2.0, (z0 + z1) / 2.0))
	# Fence: posts every 6 units and two rails
	var wood := Color(0.5, 0.36, 0.2)
	var rail := Color(0.62, 0.46, 0.27)
	var edges := [[r.position.x, r.position.y, r.end.x, r.position.y], [r.position.x, r.end.y, r.end.x, r.end.y],
		[r.position.x, r.position.y, r.position.x, r.end.y], [r.end.x, r.position.y, r.end.x, r.end.y]]
	for e in edges:
		var a := Vector2(e[0], e[1])
		var b := Vector2(e[2], e[3])
		var edge_len := a.distance_to(b)
		var n := maxi(1, int(edge_len / 6.0))
		for k in n + 1:
			var q := a.lerp(b, float(k) / float(n))
			mb.add_box(Vector3(q.x, 0.55, q.y), Vector3(0.22, 1.1, 0.22), wood)
		var mid := (a + b) / 2.0
		for ry in [0.45, 0.85]:
			if absf(a.y - b.y) < 0.01:
				mb.add_box(Vector3(mid.x, ry, mid.y), Vector3(edge_len, 0.09, 0.07), rail)
			else:
				mb.add_box(Vector3(mid.x, ry, mid.y), Vector3(0.07, 0.09, edge_len), rail)
	# Bushes and stones scattered over the land (the same every time)
	var count := clampi(int(r.size.x * r.size.y / 140.0), 6, 22)
	for k in count:
		var bx := r.position.x + 3.0 + _h(k * 17 + int(r.position.x)) * (r.size.x - 6.0)
		var bz := r.position.y + 3.0 + _h(k * 31 + int(r.position.y) + 5) * (r.size.y - 6.0)
		var s := 0.7 + 0.9 * _h(k * 7 + 3)
		if k % 4 == 3:
			mb.add_box(Vector3(bx, 0.25 * s, bz), Vector3(1.1 * s, 0.5 * s, 0.9 * s), Color(0.55, 0.54, 0.5), 0.0, 0.7)
		else:
			var g := _h(k * 13 + 1)
			var base := Vector3(bx, 0.0, bz)
			mb.add_prism(base, base + Vector3(0, 1.1 * s, 0), 0.95 * s, 0.35 * s, 6,
				Color(0.17, 0.36, 0.12).lerp(Color(0.26, 0.46, 0.16), g), Color(0.3, 0.52, 0.2).lerp(Color(0.4, 0.6, 0.24), g), true)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.material_override = mat_vc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = LOT_RANGE
	add_child(mi)

	# The sign, next to the road side of the plot
	var gate := PlotData.gate_of(id)
	var sign_node := Node3D.new()
	var sb := MeshBuilder.new()
	sb.add_box(Vector3(-2.6, 1.5, 0), Vector3(0.22, 3.0, 0.22), Color(0.4, 0.28, 0.14))
	sb.add_box(Vector3(2.6, 1.5, 0), Vector3(0.22, 3.0, 0.22), Color(0.4, 0.28, 0.14))
	sb.add_box(Vector3(0, 3.2, 0), Vector3(6.4, 2.7, 0.14), Color(0.94, 0.91, 0.8))
	sb.add_box(Vector3(0, 4.6, 0), Vector3(6.4, 0.22, 0.2), Color(0.75, 0.15, 0.1))
	var board := MeshInstance3D.new()
	board.mesh = sb.build()
	board.material_override = mat_vc
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_node.add_child(board)
	var label := Label3D.new()
	label.text = "FOR SALE\n%s\n%s - %s\n%d" % [str(p["name"]), str(p["size"]), PlotData.ha_text(PlotData.tile_count(id)), PlotData.price_of(id)]
	label.font_size = 44
	label.pixel_size = 0.0125
	label.modulate = Color(0.1, 0.08, 0.04)
	label.outline_size = 0
	label.position = Vector3(0, 3.2, 0.09)
	sign_node.add_child(label)
	var back: Label3D = label.duplicate() as Label3D
	back.position = Vector3(0, 3.2, -0.09)
	back.rotation.y = PI
	sign_node.add_child(back)
	var side_dir := 1.0 if str(p["side"]) == "n" else -1.0   # outside the plot, towards the road
	sign_node.position = Vector3(gate.x, 0.0, gate.y + side_dir * 2.2)
	add_child(sign_node)
	lots[id] = {"mesh": mi, "sign": sign_node}

func _lot_color(noise: FastNoiseLite, x: float, z: float) -> Color:
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	var n2 := noise.get_noise_2d(x * 2.3 + 40.0, z * 2.3) * 0.5 + 0.5
	var c := Color(0.36, 0.52, 0.2).lerp(Color(0.52, 0.55, 0.26), n)   # green to dry grass
	if n2 > 0.62:
		c = c.lerp(Color(0.46, 0.37, 0.25), clampf((n2 - 0.62) * 5.0, 0.0, 0.8))   # bare earth patches
	return c

func _remove_lot(id: String) -> void:
	if not lots.has(id):
		return
	var l: Dictionary = lots[id]
	(l["mesh"] as Node).queue_free()
	(l["sign"] as Node).queue_free()
	lots.erase(id)
