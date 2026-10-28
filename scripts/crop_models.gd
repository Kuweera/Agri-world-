extends RefCounted
# Crops as real plant pictures on crossed flat cards (like Farming Master 3D).
# The pictures (assets/textures/crops.png, 10 plants) are packed by tools/build_crop_atlas.py;
# crop_atlas.gd holds each picture's UV rectangle and width/height ratio.
# Plants stand in straight rows on the soil ridges.
# Five growth stages: 0 sprout, 1 young, 2 growing, 3 maturing/flowering, 4 ripe.
# detail: 2 = dense (close to the camera), 1 = medium, 0 = a few big plants (far away). The game draws
# each tile with the level that suits its distance (farm_grid.gd), because overlapping leaf cards
# are what is slow on a weak graphics chip.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const CropData := preload("res://scripts/crop_data.gd")
const CropAtlas := preload("res://scripts/crop_atlas.gd")

const ATLAS := "res://assets/textures/crops.png"
const STAGE_COUNT := 5
# Progress at which each stage starts. crop_data.gd uses the same numbers (a test checks it).
const STAGE_FROM := [0.0, 0.2, 0.45, 0.75, 1.0]
const RIDGE_TOP := 0.09   # soil ridge height (tile_models.gd)

# Atlas cells: maize stages 0-4 are cells 0-4, bean stages 0-4 are cells 5-9.
const MAIZE_CELL := 0
const BEAN_CELL := 5

# Height of a plant card in world units per stage (the width follows the picture's shape).
const MAIZE_HEIGHT := [0.3, 0.55, 0.85, 1.1, 1.3]
const BEAN_HEIGHT := [0.14, 0.3, 0.4, 0.5, 0.52]

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
		if detail >= 2:
			xs = [-0.5, 0.0, 0.5]
		elif detail == 1:
			xs = [-0.375, 0.375]
		else:
			xs = [0.0]
	elif crop_id == "beans":
		if detail >= 2:
			rows = [0, 1, 2, 3, 4]
			xs = [-0.5, 0.0, 0.5]
		elif detail == 1:
			xs = [-0.5, 0.0, 0.5]
		else:
			xs = [0.0]
	else:
		rows = [1, 3]
	var out: Array = []
	for r in rows:
		for x in xs:
			out.append(Vector2(float(x), -0.6 + 0.3 * float(r)))
	return out

static func build(crop_id: String, stage: int, variant: int = 0, detail: int = 2) -> ArrayMesh:
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
	var cell: int = (MAIZE_CELL if is_maize else BEAN_CELL) + stage
	var height: float = float(MAIZE_HEIGHT[stage]) if is_maize else float(BEAN_HEIGHT[stage])
	height *= 0.9 + 0.2 * _h(sd + 3)
	# Fewer plants are made bigger, so the field still looks full from a distance.
	height *= 1.0 + 0.15 * float(2 - clampi(detail, 0, 2))
	var width: float = height * float(CropAtlas.ASPECT[cell])
	var rect: Rect2 = CropAtlas.RECTS[cell]
	var yaw := _h(sd + 7) * PI
	var cards := 2
	var shade := 0.92 + 0.1 * _h(sd + 9)
	var c0 := Color(0.72 * shade, 0.74 * shade, 0.72 * shade)   # a little darker where it meets the soil
	var c1 := Color(shade, shade, shade)
	for k in cards:
		var a := yaw + float(k) * PI / float(cards)
		var side := Vector3(cos(a), 0.0, sin(a))
		mb.add_card([base - Vector3(0, 0.01, 0), base + Vector3(0, height, 0)], [width, width], side, rect, c0, c1)
