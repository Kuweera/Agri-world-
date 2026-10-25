extends RefCounted
# Crops as painted whole-plant pictures on crossed flat cards (like Farming Master 3D).
# The pictures are in assets/textures/crops.png (made by tools/gen_crop_atlas.py). A field looks
# dense and real but costs only a few triangles. Plants stand in straight rows on the soil ridges.
# Five growth stages: 0 sprout, 1 young, 2 growing, 3 maturing, 4 ripe.
# Ripe crops are fresh and ready to pick (green leaves, cobs, pods), not dry.
# detail 0 = fewer plants (for weak phones), detail 1 = full.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const CropData := preload("res://scripts/crop_data.gd")

const ATLAS := "res://assets/textures/crops.png"
const STAGE_COUNT := 5
# Progress at which each stage starts. crop_data.gd uses the same numbers (a test checks it).
const STAGE_FROM := [0.0, 0.2, 0.45, 0.75, 1.0]
const RIDGE_TOP := 0.09   # soil ridge height (tile_models.gd)

# Atlas cells: maize stages 1-4 are cells 0-3, bean stages 1-4 are cells 4-7, seedling blades are cell 8.
const MAIZE_CELL := 0
const BEAN_CELL := 4
const BLADES_CELL := 8

# Card size (height; width is WIDTH_RATIO of it) per stage.
const MAIZE_SIZE := [0.2, 0.42, 0.75, 1.0, 1.15]
const BEAN_SIZE := [0.2, 0.22, 0.32, 0.42, 0.46]
const WIDTH_RATIO := 0.85

static func stage_for(progress: float) -> int:
	var idx := 0
	for i in STAGE_FROM.size():
		if progress >= float(STAGE_FROM[i]):
			idx = i
	return idx

static func _h(sd: int) -> float:
	return fposmod(sin(float(sd) * 12.9898 + 78.233) * 43758.5453, 1.0)

# Plant positions inside one tile (x along the ridges, z across). The soil has 5 ridges at
# z = -0.6, -0.3, 0, 0.3, 0.6; plants stand on them. Spacing also lines up from tile to tile.
static func _spots(crop_id: String, detail: int) -> Array:
	var rows: Array = [0, 2, 4]
	var xs: Array = [-0.36, 0.36]
	if crop_id == "maize":
		xs = [-0.5, 0.0, 0.5] if detail == 1 else [-0.375, 0.375]
	elif crop_id == "beans":
		rows = [0, 1, 2, 3, 4] if detail == 1 else [0, 2, 4]
		xs = [-0.5, 0.0, 0.5] if detail == 1 else [-0.375, 0.375]
	else:
		rows = [1, 3]
	var out: Array = []
	for r in rows:
		for x in xs:
			out.append(Vector2(float(x), -0.6 + 0.3 * float(r)))
	return out

static func build(crop_id: String, stage: int, variant: int = 0, detail: int = 1) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var spots := _spots(crop_id, detail)
	stage = clampi(stage, 0, STAGE_COUNT - 1)
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var sd := variant * 97 + i * 13 + 5
		var base := Vector3(sp.x + (_h(sd) - 0.5) * 0.08, RIDGE_TOP, sp.y + (_h(sd + 1) - 0.5) * 0.03)
		if crop_id == "maize" or crop_id == "beans":
			_plant(mb, crop_id == "maize", base, stage, sd, detail)
		else:
			var h := 0.15 + 0.15 * float(stage)
			var col := Color(0.3, 0.7, 0.25)
			if stage == STAGE_COUNT - 1 and CropData.CROPS.has(crop_id):
				col = CropData.CROPS[crop_id]["color"]
			mb.add_box(base + Vector3(0, h / 2.0, 0), Vector3(0.4, h, 0.4), col)
	return mb.build()

# One plant: its picture on two (or three) vertical cards crossed at the plant's base.
static func _plant(mb, is_maize: bool, base: Vector3, stage: int, sd: int, detail: int) -> void:
	var cell := BLADES_CELL
	var size: float = 0.2
	if stage > 0:
		cell = (MAIZE_CELL if is_maize else BEAN_CELL) + stage - 1
	if is_maize:
		size = float(MAIZE_SIZE[stage])
	else:
		size = float(BEAN_SIZE[stage])
	size *= 0.9 + 0.2 * _h(sd + 3)
	var width := size * WIDTH_RATIO
	var yaw := _h(sd + 7) * PI
	var cards := 2 if detail == 0 else 3
	var shade := 0.92 + 0.12 * _h(sd + 9)
	var c0 := Color(0.7 * shade, 0.72 * shade, 0.7 * shade)   # a little darker where it meets the soil
	var c1 := Color(shade, shade, shade)
	for k in cards:
		var a := yaw + float(k) * PI / float(cards)
		var side := Vector3(cos(a), 0.0, sin(a))
		mb.add_card([base - Vector3(0, 0.01, 0), base + Vector3(0, size, 0)], [width, width], side, cell, c0, c1)
