extends RefCounted
# Implement catalogue: ploughs, seeders and fertilizer spreaders. (Harvesting is done by the
# combines in vehicle_data.gd, which have their own header.)
# Every entry has the same fields. "id" must match the key.
# type: "plough", "seeder" or "fertilizer".
# work_width: how many tiles wide it works, always an odd number (centre tile plus equal sides).
# weight: kilograms. Heavy implements need more engine power (used by the drag logic).
# model_path: "" means it is built in code; otherwise a res:// .glb (the game falls back to the
# built-in model if the file is missing). model_scale shrinks the real-size (metres) model to
# game size. model_gang: how many copies stand side by side (one per tile of width).
# The ids "plough" and "seeder" are the original 1-tile tools; saves use them.

const TYPES := ["plough", "seeder", "fertilizer"]

const ITEMS := {
	"plough": {
		"id": "plough", "name": "Plough", "type": "plough",
		"price": 400, "work_width": 1, "weight": 350,
		"model_path": "res://assets/models/Plough.glb", "model_scale": 0.5, "model_gang": 1, "paint": Color(0.55, 0.15, 0.1),
	},
	"plough_3": {
		"id": "plough_3", "name": "Wide Plough", "type": "plough",
		"price": 1500, "work_width": 3, "weight": 900,
		"model_path": "res://assets/models/Cultivator.glb", "model_scale": 0.5, "model_gang": 3, "paint": Color(0.55, 0.15, 0.1),
	},
	"plough_5": {
		"id": "plough_5", "name": "Heavy Cultivator", "type": "plough",
		"price": 3800, "work_width": 5, "weight": 1800,
		"model_path": "res://assets/models/Cultivator.glb", "model_scale": 0.5, "model_gang": 5, "paint": Color(0.5, 0.12, 0.08),
	},
	"seeder": {
		"id": "seeder", "name": "Seeder", "type": "seeder",
		"price": 450, "work_width": 1, "weight": 250,
		"model_path": "res://assets/models/Seeder.glb", "model_scale": 0.5, "model_gang": 1, "paint": Color(0.9, 0.5, 0.1),
	},
	"seeder_3": {
		"id": "seeder_3", "name": "Wide Seeder", "type": "seeder",
		"price": 1700, "work_width": 3, "weight": 700,
		"model_path": "res://assets/models/Seeder.glb", "model_scale": 0.5, "model_gang": 3, "paint": Color(0.9, 0.5, 0.1),
	},
	"seeder_5": {
		"id": "seeder_5", "name": "Precision Seeder", "type": "seeder",
		"price": 4200, "work_width": 5, "weight": 1300,
		"model_path": "res://assets/models/Seeder.glb", "model_scale": 0.5, "model_gang": 5, "paint": Color(0.85, 0.45, 0.08),
	},
	"spreader": {
		"id": "spreader", "name": "Fertilizer Spreader", "type": "fertilizer",
		"price": 350, "work_width": 1, "weight": 200,
		"fert_per_tile": 1,      # fertilizer units used for each tile treated
		"model_path": "res://assets/models/Spreader.glb", "model_scale": 0.7, "model_gang": 1, "paint": Color(0.2, 0.45, 0.75),
	},
	"spreader_3": {
		"id": "spreader_3", "name": "Wide Spreader", "type": "fertilizer",
		"price": 1400, "work_width": 3, "weight": 800,
		"fert_per_tile": 1,
		"model_path": "res://assets/models/Spreader.glb", "model_scale": 0.7, "model_gang": 3, "paint": Color(0.2, 0.45, 0.75),
	},
	"spreader_5": {
		"id": "spreader_5", "name": "Heavy Spreader", "type": "fertilizer",
		"price": 3500, "work_width": 5, "weight": 1600,
		"fert_per_tile": 1,
		"model_path": "res://assets/models/Spreader.glb", "model_scale": 0.7, "model_gang": 5, "paint": Color(0.15, 0.4, 0.7),
	},
}

# Entry for one implement id, or an empty dictionary if the id is unknown.
static func get_item(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	return {}

# Implement ids of one type, narrowest (cheapest) first.
static func ids_of_type(item_type: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id]["type"] == item_type:
			out.append(id)
	out.sort_custom(func(a, b): return ITEMS[a]["price"] < ITEMS[b]["price"])
	return out

# What an implement id does. "none" and unknown ids have no type.
static func type_of(id: String) -> String:
	if ITEMS.has(id):
		return str(ITEMS[id]["type"])
	return "none"

static func name_of(id: String) -> String:
	if ITEMS.has(id):
		return str(ITEMS[id]["name"])
	return "None"

# Tiles wide it works. 1 for "none" and unknown ids.
static func width_of(id: String) -> int:
	if ITEMS.has(id):
		return int(ITEMS[id]["work_width"])
	return 1

# Kilograms. 0 for "none" and unknown ids.
static func weight_of(id: String) -> float:
	if ITEMS.has(id):
		return float(ITEMS[id]["weight"])
	return 0.0
