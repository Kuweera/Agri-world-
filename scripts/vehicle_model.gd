extends RefCounted
# Pure arcade vehicle physics. No nodes. Works on a plain dictionary:
# x, z, heading, speed, fuel, hours.
# Heading 0 faces +z. Steering > 0 turns right (heading decreases).

const VehicleData := preload("res://scripts/vehicle_data.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const Hitbox := preload("res://scripts/hitbox.gd")

# Power versus weight. Each kg of implement needs HP_PER_KG horsepower. While the
# needed power stays under FULL_SPEED_LOAD of the engine, nothing changes. Above that the
# top speed falls, never below MIN_SPEED_FACTOR of normal. Acceleration falls with it
# (never below MIN_ACCEL_FACTOR) and fuel use rises.
const HP_PER_KG := 0.06
const FULL_SPEED_LOAD := 0.6
const SPEED_LOSS_PER_LOAD := 0.8
const MIN_SPEED_FACTOR := 0.2
const MIN_ACCEL_FACTOR := 0.3
const FUEL_LOAD_BONUS := 0.5

# Machines push each other. A parked machine resists like this many times its engine power
# (brakes on), a push is limited per step, and the pusher slows down a little.
const PARKED_RESISTANCE := 1.6
const PUSH_STEP_MAX := 0.25
const PUSH_DRAG_RATE := 1.5   # extra slowing per second while pushing (the push itself already slows the pair)

# How hard the engine works: horsepower needed divided by horsepower available.
static func load_ratio(cfg: Dictionary, implement_id: String) -> float:
	return ImplementData.weight_of(implement_id) * HP_PER_KG / maxf(1.0, float(cfg["power_hp"]))

static func speed_factor(ratio: float) -> float:
	return clampf(1.0 - (ratio - FULL_SPEED_LOAD) * SPEED_LOSS_PER_LOAD, MIN_SPEED_FACTOR, 1.0)

# A copy of the vehicle settings with the implement's load applied.
# step() and the autopilot use this copy, so they need no changes.
static func loaded_config(cfg: Dictionary, implement_id: String) -> Dictionary:
	var out: Dictionary = cfg.duplicate()
	var ratio := load_ratio(cfg, implement_id)
	var f := speed_factor(ratio)
	var over := clampf(ratio - FULL_SPEED_LOAD, 0.0, 1.0)
	out["max_speed"] = float(cfg["max_speed"]) * f
	out["accel"] = float(cfg["accel"]) * maxf(f, MIN_ACCEL_FACTOR)
	out["fuel_use"] = float(cfg["fuel_use"]) * (1.0 + FUEL_LOAD_BONUS * over)
	out["load_ratio"] = ratio
	out["speed_factor"] = f
	return out

# others: the live machine dictionaries of the other machines. Driving into one pushes it.
static func step(v: Dictionary, cfg: Dictionary, throttle: float, steer: float, delta: float,
		others: Array = []) -> void:
	var max_speed: float = cfg["max_speed"]

	# No fuel means no power: the vehicle coasts to a stop.
	var target := 0.0
	if v["fuel"] > 0.0:
		if throttle >= 0.0:
			target = throttle * max_speed
		else:
			target = throttle * max_speed * float(cfg["reverse_factor"])
	v["speed"] = move_toward(float(v["speed"]), target, float(cfg["accel"]) * delta)

	# Steering only works while moving, and flips when reversing.
	var old_heading: float = v["heading"]
	var speed: float = v["speed"]
	var turn_scale := clampf(absf(speed) / max_speed * 2.0, 0.0, 1.0)
	v["heading"] = fposmod(
		float(v["heading"]) - steer * float(cfg["turn_rate"]) * turn_scale * signf(speed) * delta,
		TAU)

	# Move, stay inside the bounds, and stop at solid obstacles.
	var old_x: float = v["x"]
	var old_z: float = v["z"]
	var b: float = VehicleData.DRIVE_BOUNDS
	var nx := clampf(old_x + sin(float(v["heading"])) * speed * delta, -b, b)
	var nz := clampf(old_z + cos(float(v["heading"])) * speed * delta, -b, b)
	for r in VehicleData.OBSTACLES:
		if r.has_point(Vector2(nx, nz)):
			nx = old_x
			nz = old_z
			v["speed"] = 0.0
	# Other machines are pushed, not walls. A moving machine shoves a parked one aside; when two
	# moving machines meet, the more powerful one pushes the weaker one aside. Nobody stops
	# working: the pushed one is only moved, the pusher loses a little speed. A machine only
	# stops (v["_blocked"]) when the other cannot move (house, fence) and it has no way past.
	v["_blocked"] = false
	if not others.is_empty():
		var hl := float(cfg.get("hit_len", 2.0)) * 0.5
		var hw := float(cfg.get("hit_wid", 1.4)) * 0.5
		var my_power := maxf(1.0, float(cfg.get("power_hp", 75)))
		var bnd: float = VehicleData.DRIVE_BOUNDS
		for o in others:
			var now_c: Array = Hitbox.circles(nx, nz, float(v["heading"]), hl, hw)
			var ct: Vector3 = Hitbox.contact(now_c, Hitbox.of_machine(o))
			if ct.z <= 0.0:
				continue
			var push := minf(ct.z + 0.01, PUSH_STEP_MAX)
			var o_power := maxf(1.0, float(VehicleData.get_vehicle(str(o.get("vehicle", "tractor"))).get("power_hp", 75)))
			var parked := absf(float(o.get("speed", 0.0))) < 0.1
			var o_weight := o_power * (PARKED_RESISTANCE if parked else 1.0)
			# Share of the move that the other machine takes (it moves more when I am stronger).
			var share_o := my_power / (my_power + o_weight)
			var ox := float(o["x"]) - ct.x * push * share_o
			var oz := float(o["z"]) - ct.y * push * share_o
			var o_free := absf(ox) <= bnd and absf(oz) <= bnd
			if o_free:
				for r in VehicleData.OBSTACLES:
					if r.grow(0.6).has_point(Vector2(ox, oz)):
						o_free = false
			if not o_free:
				share_o = 0.0
			else:
				o["x"] = ox
				o["z"] = oz
			# What the other one did not take comes back on me.
			var mine := push * (1.0 - share_o)
			var back_x := clampf(nx + ct.x * mine, -bnd, bnd)
			var back_z := clampf(nz + ct.y * mine, -bnd, bnd)
			var hits_house := false
			for r in VehicleData.OBSTACLES:
				if r.has_point(Vector2(back_x, back_z)):
					hits_house = true
			if not hits_house:
				nx = back_x
				nz = back_z
			else:
				nx = old_x
				nz = old_z
			v["speed"] = float(v["speed"]) * (1.0 - minf(0.5, PUSH_DRAG_RATE * (1.0 - share_o) * delta))
			# Only a machine that could not get away is "blocked" (the autopilot waits, then gives up).
			if share_o <= 0.0 and absf(float(v["speed"])) < 0.3:
				v["_blocked"] = true
	v["x"] = nx
	v["z"] = nz

	# Fuel and running hours only count while moving.
	if absf(speed) > 0.05:
		v["fuel"] = maxf(0.0, float(v["fuel"]) - float(cfg["fuel_use"]) * delta)
		v["hours"] = float(v["hours"]) + delta / 3600.0
