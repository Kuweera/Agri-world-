extends RefCounted
# Vehicle and implement configuration. All numbers live here.

# Tractor may not leave this square (inside the fence).
const DRIVE_BOUNDS := 11.0

# Solid rectangles as Rect2(x, z, width, depth). The farmhouse for now.
const OBSTACLES := [Rect2(-2.7, 5.3, 5.4, 4.4)]

# Vehicle catalogue. Every entry has the same fields so the shop, the physics and
# the visuals can all read it. "id" must match the key.
# type: "tractor" pulls implements (work width comes from the implement).
#       "harvester" is a combine with its own header (work_width, in tiles).
# power_hp is how strong the engine is. Speeds are units per second.
# model_path: "" means the vehicle is built in code; otherwise a res:// .glb (the game falls
# back to the built-in model if it is missing). model_scale shrinks the real-size model.
const VEHICLE_TYPES := ["tractor", "harvester"]

const VEHICLES := {
	"tractor": {
		"id": "tractor",
		"name": "Farm Tractor",
		"type": "tractor",
		"price": 3000,
		"power_hp": 75,
		"max_speed": 4.0,        # units per second
		"reverse_factor": 0.5,   # reverse is half speed
		"accel": 5.0,
		"turn_rate": 1.5,        # radians per second at full steering
		"fuel_capacity": 20.0,
		"fuel_use": 0.2,         # units per second while moving
		"fuel_price": 2,         # money per unit
		"work_offset": 1.8,      # implement works this far behind the tractor
		"model_path": "res://assets/models/Tractor.glb",
		"model_scale": 0.5,
		"paint": Color(0.18, 0.5, 0.2),
	},
	"tractor_light": {
		"id": "tractor_light",
		"name": "Compact Tractor",
		"type": "tractor",
		"price": 1800,
		"power_hp": 40,
		"max_speed": 3.2,
		"reverse_factor": 0.5,
		"accel": 4.0,
		"turn_rate": 1.8,
		"fuel_capacity": 12.0,
		"fuel_use": 0.12,
		"fuel_price": 2,
		"work_offset": 1.5,
		"model_path": "res://assets/models/Tractor.glb",
		"model_scale": 0.42,
		"paint": Color(0.85, 0.55, 0.15),
	},
	"tractor_heavy": {
		"id": "tractor_heavy",
		"name": "Heavy Tractor",
		"type": "tractor",
		"price": 9000,
		"power_hp": 160,
		"max_speed": 5.0,
		"reverse_factor": 0.5,
		"accel": 5.5,
		"turn_rate": 1.3,
		"fuel_capacity": 40.0,
		"fuel_use": 0.35,
		"fuel_price": 2,
		"work_offset": 2.1,
		"model_path": "res://assets/models/Tractor_Heavy.glb",
		"model_scale": 0.4,
		"paint": Color(0.7, 0.12, 0.1),
	},
	"combine_small": {
		"id": "combine_small",
		"name": "Small Combine Harvester",
		"type": "harvester",
		"price": 12000,
		"power_hp": 120,
		"max_speed": 3.0,
		"reverse_factor": 0.4,
		"accel": 3.0,
		"turn_rate": 1.2,
		"fuel_capacity": 60.0,
		"fuel_use": 0.4,
		"fuel_price": 2,
		"work_offset": 1.6,
		"work_width": 3,         # tiles cut per pass
		"model_path": "res://assets/models/Combine.glb",
		"model_scale": 0.45,
		"paint": Color(0.9, 0.75, 0.1),
	},
	"combine_large": {
		"id": "combine_large",
		"name": "Large Combine Harvester",
		"type": "harvester",
		"price": 28000,
		"power_hp": 250,
		"max_speed": 3.6,
		"reverse_factor": 0.4,
		"accel": 3.4,
		"turn_rate": 1.0,
		"fuel_capacity": 100.0,
		"fuel_use": 0.6,
		"fuel_price": 2,
		"work_offset": 2.2,
		"work_width": 5,
		"model_path": "res://assets/models/Combine_Large.glb",
		"model_scale": 0.6,
		"paint": Color(0.15, 0.45, 0.3),
	},
}

# The vehicle the player starts with.
const DEFAULT_VEHICLE := "tractor"

# Entry for one vehicle id, or an empty dictionary if the id is unknown.
static func get_vehicle(id: String) -> Dictionary:
	if VEHICLES.has(id):
		return VEHICLES[id]
	return {}

# Vehicle ids of one type, cheapest first.
static func ids_of_type(vehicle_type: String) -> Array:
	var out: Array = []
	for id in VEHICLES:
		if VEHICLES[id]["type"] == vehicle_type:
			out.append(id)
	out.sort_custom(func(a, b): return VEHICLES[a]["price"] < VEHICLES[b]["price"])
	return out

# Order the Tool button cycles through. Every id after "none" is in implement_data.gd.
const IMPLEMENT_ORDER := ["none", "plough", "plough_3", "plough_5", "seeder", "seeder_3",
	"seeder_5", "spreader", "spreader_3", "spreader_5", "harvester", "harvester_3"]

const IMPLEMENTS := {
	"none": {"name": "None"},
	"plough": {"name": "Plough"},
	"seeder": {"name": "Seeder"},
	"harvester": {"name": "Harvester"},
}
