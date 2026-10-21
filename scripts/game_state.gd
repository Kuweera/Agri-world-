extends RefCounted
# Pure game logic: money, inventory and field tiles. No nodes, no rendering.
# Time is passed in (unix seconds) so tests can control it.
# Every action returns "" on success or a short error message.

const CropData := preload("res://scripts/crop_data.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")

const COLS := 8
const ROWS := 8
const START_MONEY := 500
const SCHEMA_VERSION := 3
const RELIEF_AMOUNT := 100
const STATES := ["unploughed", "ploughed", "growing", "stubble"]
# After a harvest the land is left as stubble and must be ploughed again before replanting.
const HARVEST_LEAVES_STUBBLE := true
# Distance between tile centres, used to find the tiles beside a wide implement.
# farm_grid.gd uses the same spacing; a test checks they agree.
const TILE_PITCH := 1.5

var money: int = START_MONEY
var inventory: Dictionary = {}
var tiles: Array = []
var tractor: Dictionary = {}
var last_work_tile := -1   # not saved: stops a tile being worked twice in one pass
var fertilizer: int = 0    # units in stock (kept apart from crops so selling never touches it)
var last_worked_tiles: Array = []   # not saved: tiles changed by the last work_with_tractor call
var last_work_error := ""          # not saved: why part of a wide pass could not be done

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
				"fertilized": false,
			})

func _valid(i: int) -> bool:
	return i >= 0 and i < tiles.size()

func plough(i: int) -> String:
	if not _valid(i):
		return "Select a tile first"
	var st: String = tiles[i]["state"]
	if st == "ploughed":
		return "Already ploughed"
	if st == "growing":
		return "Tile is busy"
	tiles[i]["state"] = "ploughed"   # from unploughed ground or harvested stubble
	return ""

func plant(i: int, crop_id: String, now: float) -> String:
	if not _valid(i):
		return "Select a tile first"
	if not CropData.CROPS.has(crop_id):
		return "Unknown crop"
	var t: Dictionary = tiles[i]
	if t["state"] == "unploughed" or t["state"] == "stubble":
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
	if tiles[i].get("fertilized", false):
		amount = roundi(float(amount) * (1.0 + float(CropData.FERTILIZER["yield_bonus"])))
	inventory[crop_id] = int(inventory.get(crop_id, 0)) + amount
	tiles[i]["state"] = "stubble" if HARVEST_LEAVES_STUBBLE else "ploughed"
	tiles[i]["crop"] = ""
	tiles[i]["planted_at"] = 0.0
	tiles[i]["fertilized"] = false
	return ""

# Fertilizes a ploughed or growing (not yet ripe) tile. Uses stock first, and buys any
# missing units at the fertilizer price. Returns "" (done), "skip" (nothing to do)
# or an error message. Nothing is taken if it cannot be paid for.
func fertilize(i: int, now: float, per_tile: int = 1) -> String:
	if not _valid(i):
		return "Select a tile first"
	var t: Dictionary = tiles[i]
	if t["state"] != "ploughed" and t["state"] != "growing":
		return "skip"
	if t.get("fertilized", false) or is_ripe(i, now):
		return "skip"
	var from_stock := mini(fertilizer, per_tile)
	var to_buy := per_tile - from_stock
	var cost: int = to_buy * int(CropData.FERTILIZER["price"])
	if money < cost:
		return "Not enough money"
	fertilizer -= from_stock
	money -= cost
	t["fertilized"] = true
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
	if fertilizer > 0:
		parts.append("%s %d" % [CropData.FERTILIZER["name"], fertilizer])
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
		if st != "unploughed" and st != "stubble":
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
	if kind == "fertilizer":
		return fertilize(i, now)
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
		return st == "unploughed" or st == "stubble"
	if kind == "seeder":
		return st == "ploughed"
	if kind == "harvester":
		return is_ripe(i, now)
	if kind == "fertilizer":
		return (st == "ploughed" or st == "growing") and not tiles[i].get("fertilized", false) and not is_ripe(i, now)
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

# Works the tile behind the tractor, once each time it enters a new tile. A wide
# implement also works the tiles beside it (work_width tiles across, centred).
# Returns "" if at least one tile changed, "skip" if there was nothing to do, or an
# error message if nothing could be done. When part of a wide pass fails (for example
# the money ran out) the rest is still done and `last_work_error` says why.
# After "", `last_worked_tiles` lists every tile that changed.
func work_with_tractor(cfg: Dictionary, now: float, crop_id: String) -> String:
	last_worked_tiles = []
	last_work_error = ""
	var impl_id: String = tractor["implement"]
	if impl_id == "none" or absf(float(tractor["speed"])) < 0.1:
		return "skip"
	var off: float = cfg["work_offset"]
	var h: float = tractor["heading"]
	var cx := float(tractor["x"]) - sin(h) * off
	var cz := float(tractor["z"]) - cos(h) * off
	var idx := FarmLayout.world_to_tile(cx, cz)
	if idx < 0:
		last_work_tile = -1
		return "skip"
	if idx == last_work_tile:
		return "skip"
	last_work_tile = idx
	var targets: Array = [idx]
	var half := int((ImplementData.width_of(impl_id) - 1) / 2)
	for k in range(1, half + 1):
		for side in [-1.0, 1.0]:
			var nj := FarmLayout.world_to_tile(
				cx + cos(h) * side * float(k) * TILE_PITCH,
				cz - sin(h) * side * float(k) * TILE_PITCH)
			if nj >= 0 and not targets.has(nj):
				targets.append(nj)
	var kind: String = ImplementData.type_of(impl_id)
	var per_tile := int(ImplementData.get_item(impl_id).get("fert_per_tile", 1))
	for j in targets:
		var res := ""
		if kind == "fertilizer":
			res = fertilize(j, now, per_tile)
		else:
			res = apply_implement(kind, j, crop_id, now)
		if res == "":
			last_worked_tiles.append(j)
		elif res != "skip" and last_work_error == "":
			last_work_error = res
	if not last_worked_tiles.is_empty():
		return ""
	if last_work_error != "":
		return last_work_error
	return "skip"

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
			"fertilized": t.get("fertilized", false),
		})
	var tr := tractor.duplicate()
	tr.erase("speed")
	return {
		"schema_version": SCHEMA_VERSION,
		"money": money,
		"inventory": inventory.duplicate(),
		"fertilizer": fertilizer,
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
	if _is_num(d.get("schema_version")) and int(d["schema_version"]) == 2:
		d["fertilizer"] = 0
		d["schema_version"] = 3
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
	var fert = d.get("fertilizer", 0)
	if not _is_num(fert) or fert < 0 or not is_finite(float(fert)):
		return "Bad fertilizer"
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
		var fz = t.get("fertilized", false)
		if typeof(fz) != TYPE_BOOL:
			return "Bad tile"
		fz = fz and (st == "ploughed" or st == "growing")
		new_tiles.append({
			"col": i % COLS,
			"row": floori(float(i) / float(COLS)),
			"state": st,
			"crop": crop,
			"planted_at": float(planted),
			"fertilized": fz,
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
	if typeof(impl) != TYPE_STRING or not VehicleData.IMPLEMENT_ORDER.has(impl):
		return "Bad tractor"
	money = int(d["money"])
	inventory = inv
	fertilizer = int(fert)
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
