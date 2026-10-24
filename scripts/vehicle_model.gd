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

# others: the machine dictionaries standing in the field. A machine cannot be driven into one;
# it stops, and v["_blocked"] says so (the autopilot waits a little before giving up).
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
	# Other machines are solid too. A move that makes the overlap worse is undone, so a machine
	# that already touches another can still drive away from it.
	v["_blocked"] = false
	if not others.is_empty():
		var hl := float(cfg.get("hit_len", 2.0)) * 0.5
		var hw := float(cfg.get("hit_wid", 1.4)) * 0.5
		var now_c: Array = Hitbox.circles(nx, nz, float(v["heading"]), hl, hw)
		var was_c: Array = Hitbox.circles(old_x, old_z, old_heading, hl, hw)
		for o in others:
			var oc: Array = Hitbox.of_machine(o)
			var pen_new := Hitbox.penetration(now_c, oc)
			if pen_new > 0.0 and pen_new >= Hitbox.penetration(was_c, oc) - 0.0005:
				nx = old_x
				nz = old_z
				v["heading"] = old_heading
				v["speed"] = 0.0
				v["_blocked"] = true
				break
	v["x"] = nx
	v["z"] = nz

	# Fuel and running hours only count while moving.
	if absf(speed) > 0.05:
		v["fuel"] = maxf(0.0, float(v["fuel"]) - float(cfg["fuel_use"]) * delta)
		v["hours"] = float(v["hours"]) + delta / 3600.0
