extends RefCounted
# What the machinery shop shows. Pure logic (no 3D, no UI), so the tests can check it.
# A category is a tab in the shop; entry() turns one catalogue id into the texts and flags
# the shop screen needs.

const VehicleData := preload("res://scripts/vehicle_data.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")

const CATEGORIES := [
	{"id": "tractor", "label": "Tractors"},
	{"id": "combine", "label": "Combines"},
	{"id": "plough", "label": "Ploughs"},
	{"id": "seeder", "label": "Seeders"},
	{"id": "fertilizer", "label": "Spreaders"},
	{"id": "header", "label": "Headers"},
]

# Ids in a category, cheapest first.
static func ids_in(category: String) -> Array:
	if category == "tractor":
		return VehicleData.ids_of_type("tractor")
	if category == "combine":
		return VehicleData.ids_of_type("harvester")
	if category == "header":
		return ImplementData.ids_of_type("harvester")
	return ImplementData.ids_of_type(category)

static func is_vehicle(id: String) -> bool:
	return VehicleData.VEHICLES.has(id)

# Everything the shop shows for one id, for the given game state.
static func entry(id: String, state) -> Dictionary:
	var out := {"id": id, "name": "", "price": 0, "vehicle": is_vehicle(id), "owned": false,
		"in_use": false, "can_use": false, "can_buy": "", "stats": "", "tag": ""}
	if is_vehicle(id):
		var v: Dictionary = VehicleData.VEHICLES[id]
		out["name"] = str(v["name"])
		out["price"] = int(v["price"])
		var lines: Array = [
			"Engine power: %d hp" % int(v["power_hp"]),
			"Top speed: %.1f" % float(v["max_speed"]),
			"Fuel tank: %d" % int(v["fuel_capacity"]),
		]
		if v["type"] == "harvester":
			lines.append("Cuts %d tiles wide" % int(v.get("work_width", 1)))
		elif bool(v.get("tracked", false)):
			lines.append("Tracks: strong pull, easy on the soil")
		out["stats"] = "\n".join(lines)
		out["can_use"] = true
		out["in_use"] = str(state.tractor.get("vehicle", "tractor")) == id
	elif ImplementData.ITEMS.has(id):
		var it: Dictionary = ImplementData.ITEMS[id]
		out["name"] = str(it["name"])
		out["price"] = int(it["price"])
		var w := int(it["work_width"])
		var need := float(it["weight"]) * VehicleModel.HP_PER_KG
		var lines2: Array = [
			"Works %d tile%s wide" % [w, "" if w == 1 else "s"],
			"Weight: %d kg" % int(it["weight"]),
			"Needs about %d hp" % int(round(need)),
		]
		if it["type"] == "fertilizer":
			lines2.append("Uses %d fertilizer per tile" % int(it.get("fert_per_tile", 1)))
		var loaded: Dictionary = VehicleModel.loaded_config(state.vehicle_cfg(), id)
		lines2.append("With your tractor: top speed %.1f of %.1f" % [float(loaded["max_speed"]), float(state.vehicle_cfg()["max_speed"])])
		out["stats"] = "\n".join(lines2)
		out["can_use"] = true
		out["in_use"] = str(state.tractor.get("implement", "none")) == id
	else:
		return out
	out["owned"] = state.owns(id)
	out["can_buy"] = state.can_buy(id)
	if out["in_use"]:
		out["tag"] = "In use"
	elif out["owned"]:
		out["tag"] = "Owned"
	else:
		out["tag"] = str(out["price"])
	return out
