extends RefCounted
# Pure game logic: money, inventory and field tiles. No nodes, no rendering.
# Time is passed in (unix seconds) so tests can control it.
# Every action returns "" on success or a short error message.

const CropData := preload("res://scripts/crop_data.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")
const Parking := preload("res://scripts/parking.gd")

const COLS := 8
const ROWS := 8
const START_MONEY := 500
const SCHEMA_VERSION := 4
const RELIEF_AMOUNT := 100
const STATES := ["unploughed", "ploughed", "growing", "stubble"]
# After a harvest the land is left as stubble and must be ploughed again before replanting.
const HARVEST_LEAVES_STUBBLE := true
# Distance between tile centres, used to find the tiles beside a wide implement.
# farm_grid.gd uses the same spacing; a test checks they agree.
const TILE_PITCH := 1.5
# Machinery the player owns at the start: the farm tractor and the three original 1-tile tools.
const STARTER_OWNED := ["tractor", "plough", "seeder", "combine_small"]
# Vehicles taken out of the game, with the price refunded when an old save still owns one.
const REMOVED_VEHICLES := {"tractor_light": 1800}
# Tractor-mounted headers were replaced by combines; an old save is refunded for them.
const REMOVED_IMPLEMENTS := {"harvester": 0, "harvester_3": 2000}
const Hitbox := preload("res://scripts/hitbox.gd")

var money: int = START_MONEY
var inventory: Dictionary = {}
var tiles: Array = []
var tractor: Dictionary = {}      # the machine being driven: always the same dictionary as fleet[its id]
var fleet: Dictionary = {}        # vehicle id -> machine {x, z, heading, speed, fuel, hours, implement, vehicle}
# Not saved: stops a tile being worked twice in one pass (kept per machine).
var last_work_tile: int:
	get:
		return int(tractor.get("_lwt", -1))
	set(value):
		tractor["_lwt"] = value
var owned: Array = []      # ids of owned vehicles and implements (see vehicle_data / implement_data)
var fertilizer: int = 0    # units in stock (kept apart from crops so selling never touches it)
var last_worked_tiles: Array = []   # not saved: tiles changed by the last work_with_tractor call
var last_work_error := ""          # not saved: why part of a wide pass could not be done

func _init() -> void:
	tractor = default_tractor()
	fleet = {"tractor": tractor}
	owned = STARTER_OWNED.duplicate()
	_sync_fleet()
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
		"vehicle": "tractor",   # id of the tractor being driven
	}

# A new machine standing in the yard by the farmhouse, full tank, no tool.
func default_machine(id: String) -> Dictionary:
	var veh := VehicleData.get_vehicle(id)
	var others: Array = []
	for k in fleet:
		others.append(fleet[k])
	var spot := Parking.find_spot(id, others)
	if spot.is_empty():
		spot = {"x": 0.0, "z": 4.4, "heading": PI}
	return {
		"x": float(spot["x"]),
		"z": float(spot["z"]),
		"heading": float(spot["heading"]),
		"speed": 0.0,
		"fuel": float(veh.get("fuel_capacity", 20.0)),
		"hours": 0.0,
		"implement": "none",
		"vehicle": id,
	}

# Every owned vehicle has a machine in the field; machines of vehicles no longer owned go.
func _sync_fleet() -> void:
	for id in owned:
		if VehicleData.VEHICLES.has(id) and not fleet.has(id):
			fleet[id] = default_machine(str(id))
	var driven := str(tractor.get("vehicle", "tractor"))
	for k in fleet.keys():
		if not owned.has(k) and str(k) != driven:
			fleet.erase(k)

# Owned vehicle ids in the order the quick-switch buttons step through them.
func machine_ids() -> Array:
	var out: Array = []
	for id in owned:
		if VehicleData.VEHICLES.has(id) and fleet.has(id):
			out.append(str(id))
	return out

# The machines other than the one with this vehicle id (they are solid for it).
func others_of(id: String) -> Array:
	var out: Array = []
	for k in fleet:
		if k != id:
			out.append(fleet[k])
	return out

# Steps to the next tool the player owns (None is always available).
func next_implement() -> void:
	var avail: Array = []
	for id in VehicleData.IMPLEMENT_ORDER:
		if id == "none" or owned.has(id):
			avail.append(id)
	var idx := avail.find(tractor["implement"])
	tractor["implement"] = avail[(idx + 1) % avail.size()] if idx >= 0 else "none"

func owns(id: String) -> bool:
	return owned.has(id)

# Settings of the tractor being driven.
func vehicle_cfg() -> Dictionary:
	var cfg := VehicleData.get_vehicle(str(tractor.get("vehicle", "tractor")))
	if cfg.is_empty():
		return VehicleData.VEHICLES["tractor"]
	return cfg

# Price of a vehicle or implement id, or -1 if the id is unknown.
func price_of(id: String) -> int:
	if VehicleData.VEHICLES.has(id):
		return int(VehicleData.VEHICLES[id]["price"])
	if ImplementData.ITEMS.has(id):
		return int(ImplementData.ITEMS[id]["price"])
	return -1

# "" if the machine can be bought now, otherwise the reason it cannot.
func can_buy(id: String) -> String:
	var price := price_of(id)
	if price < 0:
		return "Unknown machine"
	if owns(id):
		return "Already owned"
	if money < price:
		return "Not enough money"
	return ""

func buy(id: String) -> String:
	var err := can_buy(id)
	if err != "":
		return err
	money -= price_of(id)
	owned.append(id)
	_sync_fleet()
	return ""

# Puts an owned implement on the tractor ("none" removes it).
func equip_implement(id: String) -> String:
	if id != "none" and (not ImplementData.ITEMS.has(id) or not owns(id)):
		return "Not owned"
	tractor["implement"] = id
	return ""

# Takes the wheel of an owned tractor or combine. Every machine keeps its own place, fuel
# and tool, so this just changes which one you drive; the others carry on where they are.
func select_vehicle(id: String) -> String:
	var veh := VehicleData.get_vehicle(id)
	if veh.is_empty() or not VehicleData.VEHICLE_TYPES.has(veh["type"]) or not owns(id):
		return "Not owned"
	_sync_fleet()
	tractor = fleet[id]
	return ""

# Settings of any machine in the fleet.
func cfg_of(m: Dictionary) -> Dictionary:
	var cfg := VehicleData.get_vehicle(str(m.get("vehicle", "tractor")))
	if cfg.is_empty():
		return VehicleData.VEHICLES["tractor"]
	return cfg

func machine_is_combine(m: Dictionary) -> bool:
	return str(cfg_of(m).get("type", "tractor")) == "harvester"

# The tool a machine works with: a combine always uses its built-in header.
func machine_implement(m: Dictionary) -> String:
	return "none" if machine_is_combine(m) else str(m["implement"])

func machine_kind(m: Dictionary) -> String:
	if machine_is_combine(m):
		return "harvester"
	return ImplementData.type_of(str(m["implement"]))

func machine_width(m: Dictionary) -> int:
	if machine_is_combine(m):
		return maxi(1, int(cfg_of(m).get("work_width", 1)))
	return ImplementData.width_of(str(m["implement"]))

# True while a combine is being driven: it has its own header, so the tool button is not used.
func is_combine() -> bool:
	return str(vehicle_cfg().get("type", "tractor")) == "harvester"

# The tool in use: a combine always works with its built-in header.
func active_implement() -> String:
	return "none" if is_combine() else str(tractor["implement"])

func active_kind() -> String:
	if is_combine():
		return "harvester"
	return ImplementData.type_of(str(tractor["implement"]))

# Tiles worked across by the machine being driven.
func active_width() -> int:
	if is_combine():
		return maxi(1, int(vehicle_cfg().get("work_width", 1)))
	return ImplementData.width_of(str(tractor["implement"]))

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
func jobs_for(kind: String, now: float, skip_rows: Array = []) -> Array:
	var jobs: Array = []
	for row in ROWS:
		if skip_rows.has(row):
			continue
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
func work_with_tractor(cfg: Dictionary, now: float, crop_id: String, machine: Dictionary = {}) -> String:
	last_worked_tiles = []
	last_work_error = ""
	var m: Dictionary = tractor if machine.is_empty() else machine
	var comb := str(cfg.get("type", "tractor")) == "harvester"
	var impl_id: String = m["implement"]
	if absf(float(m["speed"])) < 0.1 or (not comb and impl_id == "none"):
		return "skip"
	# Positive offset: the tool trails behind. Negative: a combine header cuts ahead.
	var off: float = cfg["work_offset"]
	var h: float = m["heading"]
	var cx := float(m["x"]) - sin(h) * off
	var cz := float(m["z"]) - cos(h) * off
	var idx := FarmLayout.world_to_tile(cx, cz)
	if idx < 0:
		m["_lwt"] = -1
		return "skip"
	if idx == int(m.get("_lwt", -1)):
		return "skip"
	m["_lwt"] = idx
	var width: int = maxi(1, int(cfg.get("work_width", 1))) if comb else ImplementData.width_of(impl_id)
	var targets: Array = [idx]
	var half := int((width - 1) / 2)
	for k in range(1, half + 1):
		for side in [-1.0, 1.0]:
			var nj := FarmLayout.world_to_tile(
				cx + cos(h) * side * float(k) * TILE_PITCH,
				cz - sin(h) * side * float(k) * TILE_PITCH)
			if nj >= 0 and not targets.has(nj):
				targets.append(nj)
	var kind: String = "harvester" if comb else ImplementData.type_of(impl_id)
	var per_tile := 1 if comb else int(ImplementData.get_item(impl_id).get("fert_per_tile", 1))
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
	var cfg: Dictionary = vehicle_cfg()
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
	var tr := _saved_machine(tractor)
	var out_fleet := {}
	for k in fleet:
		out_fleet[k] = _saved_machine(fleet[k])
	return {
		"schema_version": SCHEMA_VERSION,
		"money": money,
		"inventory": inventory.duplicate(),
		"fertilizer": fertilizer,
		"owned": owned.duplicate(),
		"tiles": out_tiles,
		"tractor": tr,
		"fleet": out_fleet,
	}

# A machine as saved: no speed and none of the working keys that start with "_".
func _saved_machine(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		if not str(k).begins_with("_") and k != "speed":
			out[k] = m[k]
	return out

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
	if _is_num(d.get("schema_version")) and int(d["schema_version"]) == 3:
		var own: Array = STARTER_OWNED.duplicate()
		var tr3 = d.get("tractor")
		if typeof(tr3) == TYPE_DICTIONARY:
			var cur = tr3.get("implement", "none")
			if typeof(cur) == TYPE_STRING and cur != "none" and not own.has(cur):
				own.append(cur)
			tr3["vehicle"] = "tractor"
		d["owned"] = own
		d["schema_version"] = 4
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
	var own_raw = d.get("owned")
	if typeof(own_raw) != TYPE_ARRAY:
		return "Bad machinery"
	var own: Array = []
	var refund := 0
	for o in own_raw:
		if typeof(o) == TYPE_STRING and REMOVED_VEHICLES.has(o):
			refund += int(REMOVED_VEHICLES[o])
			continue
		if typeof(o) == TYPE_STRING and REMOVED_IMPLEMENTS.has(o):
			refund += int(REMOVED_IMPLEMENTS[o])
			continue
		if typeof(o) != TYPE_STRING or not (VehicleData.VEHICLES.has(o) or ImplementData.ITEMS.has(o)):
			return "Bad machinery"
		if not own.has(o):
			own.append(o)
	if not own.has("combine_small"):
		own.append("combine_small")     # the free starter combine, for saves made before combines
	var tr = d.get("tractor")
	if typeof(tr) != TYPE_DICTIONARY:
		return "Bad tractor"
	var veh = tr.get("vehicle", "tractor")
	if typeof(veh) == TYPE_STRING and REMOVED_VEHICLES.has(veh):
		veh = "tractor"
	if typeof(veh) != TYPE_STRING or not VehicleData.VEHICLES.has(veh) or not own.has(veh):
		return "Bad tractor"
	if not VehicleData.VEHICLE_TYPES.has(VehicleData.VEHICLES[veh]["type"]):
		return "Bad tractor"
	var cfg: Dictionary = VehicleData.VEHICLES[veh]
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
	if typeof(impl) == TYPE_STRING and REMOVED_IMPLEMENTS.has(impl):
		impl = "none"
	if typeof(impl) != TYPE_STRING or not VehicleData.IMPLEMENT_ORDER.has(impl):
		return "Bad tractor"
	if impl != "none" and not own.has(impl):
		return "Bad tractor"
	money = int(d["money"]) + refund
	inventory = inv
	fertilizer = int(fert)
	owned = own
	tiles = new_tiles
	tractor = {
		"x": float(tr["x"]),
		"z": float(tr["z"]),
		"heading": float(tr["heading"]),
		"speed": 0.0,
		"fuel": float(tr["fuel"]),
		"hours": float(tr["hours"]),
		"implement": impl,
		"vehicle": veh,
	}
	# The other machines: each keeps its own place, fuel and tool. A damaged entry is dropped
	# and the machine starts again in the yard.
	var new_fleet := {str(veh): tractor}
	var fl = d.get("fleet")
	if typeof(fl) == TYPE_DICTIONARY:
		for k in fl:
			if str(k) == str(veh) or not (typeof(k) == TYPE_STRING and VehicleData.VEHICLES.has(k)):
				continue
			var pm := _parse_machine(str(k), fl[k], own)
			if not pm.is_empty():
				new_fleet[str(k)] = pm
	fleet = new_fleet
	_sync_fleet()
	return ""

# One saved machine, checked; an empty dictionary if anything is wrong with it.
func _parse_machine(id: String, raw: Variant, own: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or not own.has(id) or not VehicleData.VEHICLES.has(id):
		return {}
	var cfg: Dictionary = VehicleData.VEHICLES[id]
	for key in ["x", "z", "heading", "fuel", "hours"]:
		if not _is_num(raw.get(key)) or not is_finite(float(raw[key])):
			return {}
	var bnd: float = VehicleData.DRIVE_BOUNDS + 0.01
	if absf(float(raw["x"])) > bnd or absf(float(raw["z"])) > bnd:
		return {}
	if float(raw["fuel"]) < 0.0 or float(raw["fuel"]) > float(cfg["fuel_capacity"]) + 0.01 or float(raw["hours"]) < 0.0:
		return {}
	var impl = raw.get("implement", "none")
	if typeof(impl) == TYPE_STRING and REMOVED_IMPLEMENTS.has(impl):
		impl = "none"
	if typeof(impl) != TYPE_STRING or not VehicleData.IMPLEMENT_ORDER.has(impl):
		impl = "none"
	if impl != "none" and not own.has(impl):
		impl = "none"
	return {
		"x": float(raw["x"]),
		"z": float(raw["z"]),
		"heading": float(raw["heading"]),
		"speed": 0.0,
		"fuel": float(raw["fuel"]),
		"hours": float(raw["hours"]),
		"implement": impl,
		"vehicle": id,
	}
