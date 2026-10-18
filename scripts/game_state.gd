extends RefCounted
# Pure game logic: money, inventory and field tiles. No nodes, no rendering.
# Time is passed in (unix seconds) so tests can control it.
# Every action returns "" on success or a short error message.

const CropData := preload("res://scripts/crop_data.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")

const COLS := 8
const ROWS := 8
const START_MONEY := 500
const SCHEMA_VERSION := 2
const RELIEF_AMOUNT := 100
const STATES := ["unploughed", "ploughed", "growing"]

var money: int = START_MONEY
var inventory: Dictionary = {}
var tiles: Array = []
var tractor: Dictionary = {}
var last_work_tile := -1   # not saved: stops a tile being worked twice in one pass

func _init() -> void:
	tractor = default_tractor()
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

# ---- Tractor, tools and fuel ----

static func default_tractor() -> Dictionary:
	return {
		"x": 8.0,
		"z": 4.0,
		"heading": PI,
		"speed": 0.0,
		"fuel": VehicleData.VEHICLES["tractor"]["fuel_capacity"],
		"hours": 0.0,
		"implement": "none",
	}

func next_implement() -> void:
	var order: Array = VehicleData.IMPLEMENT_ORDER
	var idx := order.find(tractor["implement"])
	tractor["implement"] = order[(idx + 1) % order.size()]

# Applies the tractor's tool to a tile. Returns "" if it did something,
# "skip" if there was nothing to do (not an error), or an error message.
func apply_implement(kind: String, i: int, crop_id: String, now: float) -> String:
	if not _valid(i):
		return "skip"
	var st: String = tiles[i]["state"]
	if kind == "none":
		return "skip"
	if kind == "plough":
		if st != "unploughed":
			return "skip"
		return plough(i)
	if kind == "seeder":
		if st != "ploughed":
			return "skip"
		return plant(i, crop_id, now)
	if kind == "harvester":
		if not is_ripe(i, now):
			return "skip"
		return harvest(i, now)
	return "Unknown tool"

func _min_seed_cost() -> int:
	var lowest := 1000000
	for id in CropData.CROPS:
		lowest = mini(lowest, int(CropData.CROPS[id]["seed_cost"]))
	return lowest

# Safety net so the farm can never get stuck: if you cannot afford any seed, have
# nothing to sell and nothing is growing, you receive a small grant.
# Returns the amount given (0 if none).
func relief_grant() -> int:
	if money >= _min_seed_cost() or not inventory.is_empty():
		return 0
	for t in tiles:
		if t["state"] == "growing":
			return 0
	money += RELIEF_AMOUNT
	return RELIEF_AMOUNT

# Can this tool do something useful on tile i right now?
func can_work(kind: String, i: int, now: float) -> bool:
	if not _valid(i):
		return false
	var st: String = tiles[i]["state"]
	if kind == "plough":
		return st == "unploughed"
	if kind == "seeder":
		return st == "ploughed"
	if kind == "harvester":
		return is_ripe(i, now)
	return false

# Field rows (0..ROWS-1) where the tool has at least one tile to work.
func rows_with_work(kind: String, now: float) -> Array:
	var rows: Array = []
	for row in ROWS:
		for col in COLS:
			if can_work(kind, row * COLS + col, now):
				rows.append(row)
				break
	return rows

# How many tiles the tool could work right now.
func count_work(kind: String, now: float) -> int:
	var n := 0
	for i in tiles.size():
		if can_work(kind, i, now):
			n += 1
	return n

# One job per row that needs work: {"row", "c0", "c1"} (first and last column to visit).
func jobs_for(kind: String, now: float) -> Array:
	var jobs: Array = []
	for row in ROWS:
		var c0 := -1
		var c1 := -1
		for col in COLS:
			if can_work(kind, row * COLS + col, now):
				if c0 < 0:
					c0 = col
				c1 = col
		if c0 >= 0:
			jobs.append({"row": row, "c0": c0, "c1": c1})
	return jobs

# Works the tile behind the tractor, once each time it enters a new tile.
# Returns "" (did something), "skip" (nothing to do) or an error message.
# After "", `last_work_tile` is the tile that changed.
func work_with_tractor(cfg: Dictionary, now: float, crop_id: String) -> String:
	if tractor["implement"] == "none" or absf(float(tractor["speed"])) < 0.1:
		return "skip"
	var off: float = cfg["work_offset"]
	var h: float = tractor["heading"]
	var idx := FarmLayout.world_to_tile(
		float(tractor["x"]) - sin(h) * off,
		float(tractor["z"]) - cos(h) * off)
	if idx < 0:
		last_work_tile = -1
		return "skip"
	if idx == last_work_tile:
		return "skip"
	last_work_tile = idx
	return apply_implement(tractor["implement"], idx, crop_id, now)

# Buys fuel up to a full tank, as much as the player can afford.
func refuel() -> String:
	var cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	var needed := float(cfg["fuel_capacity"]) - float(tractor["fuel"])
	if needed <= 0.01:
		return "Tank is full"
	var price: int = cfg["fuel_price"]
	var units := mini(int(ceil(needed)), int(money / price))
	if units <= 0:
		return "Not enough money"
	money -= units * price
	tractor["fuel"] = minf(float(cfg["fuel_capacity"]), float(tractor["fuel"]) + float(units))
	return ""

# ---- Saving and loading ----

func to_dict() -> Dictionary:
	var out_tiles: Array = []
	for t in tiles:
		out_tiles.append({
			"state": t["state"],
			"crop": t["crop"],
			"planted_at": t["planted_at"],
		})
	var tr := tractor.duplicate()
	tr.erase("speed")
	return {
		"schema_version": SCHEMA_VERSION,
		"money": money,
		"inventory": inventory.duplicate(),
		"tiles": out_tiles,
		"tractor": tr,
	}

# Upgrades older save versions to the current one before validation.
func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	if _is_num(d.get("schema_version")) and int(d["schema_version"]) == 1:
		var tr := default_tractor()
		tr.erase("speed")
		d["tractor"] = tr
		d["schema_version"] = 2
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
	var tr = d.get("tractor")
	if typeof(tr) != TYPE_DICTIONARY:
		return "Bad tractor"
	var cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	for key in ["x", "z", "heading", "fuel", "hours"]:
		if not _is_num(tr.get(key)) or not is_finite(float(tr[key])):
			return "Bad tractor"
	var bnd: float = VehicleData.DRIVE_BOUNDS + 0.01
	if absf(float(tr["x"])) > bnd or absf(float(tr["z"])) > bnd:
		return "Bad tractor"
	if float(tr["fuel"]) < 0.0 or float(tr["fuel"]) > float(cfg["fuel_capacity"]) + 0.01:
		return "Bad tractor"
	if float(tr["hours"]) < 0.0:
		return "Bad tractor"
	var impl = tr.get("implement", "none")
	if typeof(impl) != TYPE_STRING or not VehicleData.IMPLEMENTS.has(impl):
		return "Bad tractor"
	money = int(d["money"])
	inventory = inv
	tiles = new_tiles
	tractor = {
		"x": float(tr["x"]),
		"z": float(tr["z"]),
		"heading": float(tr["heading"]),
		"speed": 0.0,
		"fuel": float(tr["fuel"]),
		"hours": float(tr["hours"]),
		"implement": impl,
	}
	return ""
