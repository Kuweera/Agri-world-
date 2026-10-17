extends RefCounted
# Pure game logic: money, inventory and field tiles. No nodes, no rendering.
# Time is passed in (unix seconds) so tests can control it.
# Every action returns "" on success or a short error message.

const CropData := preload("res://scripts/crop_data.gd")

const COLS := 8
const ROWS := 8
const START_MONEY := 500
const SCHEMA_VERSION := 1
const STATES := ["unploughed", "ploughed", "growing"]

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

# ---- Saving and loading ----

func to_dict() -> Dictionary:
	var out_tiles: Array = []
	for t in tiles:
		out_tiles.append({
			"state": t["state"],
			"crop": t["crop"],
			"planted_at": t["planted_at"],
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"money": money,
		"inventory": inventory.duplicate(),
		"tiles": out_tiles,
	}

# Future: upgrade older save versions here before validation.
func migrate(d: Dictionary) -> Dictionary:
	return d

func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

# Validates everything first, then applies. Returns "" on success.
# On any error the current state is left unchanged.
func from_dict(data: Dictionary) -> String:
	var d := migrate(data)
	if not _is_num(d.get("schema_version")) or int(d["schema_version"]) != SCHEMA_VERSION:
		return "Unsupported save version"
	if not d.has("money") or not _is_num(d["money"]) or d["money"] < 0:
		return "Bad money"
	if not d.has("inventory") or typeof(d["inventory"]) != TYPE_DICTIONARY:
		return "Bad stock"
	var inv := {}
	for k in d["inventory"]:
		var n = d["inventory"][k]
		if not CropData.CROPS.has(k) or not _is_num(n) or n < 0:
			return "Bad stock"
		if int(n) > 0:
			inv[k] = int(n)
	if not d.has("tiles") or typeof(d["tiles"]) != TYPE_ARRAY or d["tiles"].size() != COLS * ROWS:
		return "Bad tiles"
	var new_tiles: Array = []
	for i in d["tiles"].size():
		var t = d["tiles"][i]
		if typeof(t) != TYPE_DICTIONARY:
			return "Bad tile"
		var st = t.get("state", "")
		if typeof(st) != TYPE_STRING or not STATES.has(st):
			return "Bad tile state"
		var crop = t.get("crop", "")
		if typeof(crop) != TYPE_STRING:
			return "Bad crop"
		if st == "growing" and not CropData.CROPS.has(crop):
			return "Bad crop"
		if st != "growing":
			crop = ""
		var planted = t.get("planted_at", 0.0)
		if not _is_num(planted):
			return "Bad time"
		new_tiles.append({
			"col": i % COLS,
			"row": floori(float(i) / float(COLS)),
			"state": st,
			"crop": crop,
			"planted_at": float(planted),
		})
	money = int(d["money"])
	inventory = inv
	tiles = new_tiles
	return ""
