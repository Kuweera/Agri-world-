extends RefCounted
# Vehicle and implement configuration. All numbers live here.

# Tractor may not leave this square (inside the fence).
const DRIVE_BOUNDS := 11.0

# Solid rectangles as Rect2(x, z, width, depth). The farmhouse for now.
const OBSTACLES := [Rect2(-2.7, 5.3, 5.4, 4.4)]

const VEHICLES := {
	"tractor": {
		"name": "Farm Tractor",
		"max_speed": 4.0,        # units per second
		"reverse_factor": 0.5,   # reverse is half speed
		"accel": 5.0,
		"turn_rate": 1.5,        # radians per second at full steering
		"fuel_capacity": 20.0,
		"fuel_use": 0.2,         # units per second while moving
		"fuel_price": 2,         # money per unit
		"work_offset": 1.8,      # implement works this far behind the tractor
	},
}

const IMPLEMENT_ORDER := ["none", "plough", "seeder", "harvester"]

const IMPLEMENTS := {
	"none": {"name": "None"},
	"plough": {"name": "Plough"},
	"seeder": {"name": "Seeder"},
	"harvester": {"name": "Harvester"},
}
