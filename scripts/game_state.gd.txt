extends RefCounted
# Pure game logic: money, inventory and field tiles. No nodes, no rendering.
# Time is passed in (unix seconds) so tests can control it.
# Every action returns "" on success or a short error message.

const CropData := preload("res://scripts/crop_data.gd")

const COLS := 8
const ROWS := 8
const START_MONEY := 500

var money: int = START_MONEY
var inventory: Dictionary = {}
var tiles: Array = []

func _init() -> void:
	for row in ROWS:
		for col in COLS:
			tiles.append({
				"col": col,
				"row": row,
				"state": "unploughed",
				"crop": "",
				"planted_at": 0.0,
			})

func _valid(i: int) -> bool:
	return i >= 0 and i < tiles.size()

func plough(i: int) -> String:
	if not _valid(i):
		return "Select a tile first"
	if tiles[i]["state"] != "unploughed":
		return "Already ploughed"
	tiles[i]["state"] = "ploughed"
	return ""

func plant(i: int, crop_id: String, now: float) -> String:
	if not _valid(i):
		return "Select a tile first"
	if not CropData.CROPS.has(crop_id):
		return "Unknown crop"
	var t: Dictionary = tiles[i]
	if t["state"] == "unploughed":
		return "Plough the tile first"
	if t["state"] != "ploughed":
		return "Tile is busy"
	var cost: int = CropData.CROPS[crop_id]["seed_cost"]
	if money < cost:
		return "Not enough money"
	money -= cost
	t["state"] = "growing"
	t["crop"] = crop_id
	t["planted_at"] = now
	return ""

func progress(i: int, now: float) -> float:
	if not _valid(i) or tiles[i]["state"] != "growing":
		return 0.0
	var grow: float = CropData.CROPS[tiles[i]["crop"]]["grow_seconds"]
	return clampf((now - tiles[i]["planted_at"]) / grow, 0.0, 1.0)

func is_ripe(i: int, now: float) -> bool:
	return _valid(i) and tiles[i]["state"] == "growing" and progress(i, now) >= 1.0

func harvest(i: int, now: float) -> String:
	if not _valid(i):
		return "Select a tile first"
	if tiles[i]["state"] != "growing":
		return "Nothing to harvest"
	if not is_ripe(i, now):
		return "Not ripe yet"
	var crop_id: String = tiles[i]["crop"]
	var amount: int = CropData.CROPS[crop_id]["yield"]
	inventory[crop_id] = int(inventory.get(crop_id, 0)) + amount
	tiles[i]["state"] = "ploughed"
	tiles[i]["crop"] = ""
	tiles[i]["planted_at"] = 0.0
	return ""

# Sells everything in stock. Returns the money earned.
func sell_all() -> int:
	var total := 0
	for crop_id in inventory:
		total += int(inventory[crop_id]) * int(CropData.CROPS[crop_id]["sell_price"])
	inventory.clear()
	money += total
	return total

func inventory_text() -> String:
	var parts := PackedStringArray()
	for crop_id in CropData.CROPS:
		var n := int(inventory.get(crop_id, 0))
		if n > 0:
			parts.append("%s %d" % [CropData.CROPS[crop_id]["name"], n])
	if parts.is_empty():
		return "Stock: empty"
	return "Stock: " + ", ".join(parts)
