extends RefCounted
# Vehicle and implement configuration. All numbers live here.

# Tractor may not leave this square (inside the fence).
const DRIVE_BOUNDS := 19.0

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
		"hit_len": 2.3,          # footprint for collisions between machines (game units)
		"hit_wid": 1.4,
		"paint": Color(0.18, 0.5, 0.2),
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
		"hit_len": 3.3,          # footprint for collisions between machines (game units)
		"hit_wid": 1.4,
		"paint": Color(0.7, 0.12, 0.1),
	},
	"tractor_tracked": {
		"id": "tractor_tracked",
		"name": "Heavy Tracked Tractor",
		"type": "tractor",
		"price": 18000,
		"power_hp": 280,
		"max_speed": 4.6,
		"reverse_factor": 0.5,
		"accel": 5.0,
		"turn_rate": 1.1,
		"fuel_capacity": 70.0,
		"fuel_use": 0.5,
		"fuel_price": 2,
		"work_offset": 2.1,
		"model_path": "res://assets/models/Tractor_Heavy_Tracked.glb",
		"model_scale": 0.4,
		"tracked": true,         # four track pods: they do not spin like wheels
		"hit_len": 3.3,          # footprint for collisions between machines (game units)
		"hit_wid": 1.5,
		"paint": Color(0.1, 0.25, 0.6),
	},
	"combine_small": {
		"id": "combine_small",
		"name": "Small Combine Harvester",
		"type": "harvester",
		"price": 0,              # free: the combine you start with
		"power_hp": 120,
		"max_speed": 3.0,
		"reverse_factor": 0.4,
		"accel": 3.0,
		"turn_rate": 1.2,
		"fuel_capacity": 60.0,
		"fuel_use": 0.4,
		"fuel_price": 2,
		"work_offset": -2.8,     # negative: the header cuts this far AHEAD of the machine
		"work_width": 3,         # tiles cut per pass
		"model_path": "res://assets/models/Combine.glb",
		"model_scale": 0.7,
		"rear_steer": true,
		"hit_len": 6.0,          # footprint for collisions between machines (game units)
		"hit_wid": 1.8,
		"park_wid": 3.0,         # room needed when parked (header sticks out)
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
		"work_offset": -3.5,
		"work_width": 5,
		"model_path": "res://assets/models/Combine_Large.glb",
		"model_scale": 0.6,
		"rear_steer": true,
		"hit_len": 7.6,          # footprint for collisions between machines (game units)
		"hit_wid": 2.1,
		"park_wid": 3.2,         # room needed when parked (header sticks out)
		"paint": Color(0.15, 0.45, 0.3),
	},
	"combine_large_b": {
		"id": "combine_large_b",
		"name": "Tracked Combine Harvester",
		"type": "harvester",
		"price": 52000,
		"power_hp": 400,
		"max_speed": 3.9,
		"reverse_factor": 0.4,
		"accel": 3.6,
		"turn_rate": 1.0,
		"fuel_capacity": 140.0,
		"fuel_use": 0.8,
		"fuel_price": 2,
		"work_offset": -3.9,
		"work_width": 5,
		"model_path": "res://assets/models/Combine_Large_B.glb",
		"model_scale": 0.62,
		"rear_steer": true,
		"hit_len": 8.4,          # footprint for collisions between machines (game units)
		"hit_wid": 2.2,
		"park_wid": 3.2,         # room needed when parked (header sticks out)
		"paint": Color(0.95, 0.8, 0.1),
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
	"seeder_5", "spreader", "spreader_3", "spreader_5"]

const IMPLEMENTS := {
	"none": {"name": "None"},
	"plough": {"name": "Plough"},
	"seeder": {"name": "Seeder"},
}
