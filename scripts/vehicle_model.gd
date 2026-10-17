extends RefCounted
# Pure arcade vehicle physics. No nodes. Works on a plain dictionary:
# x, z, heading, speed, fuel, hours.
# Heading 0 faces +z. Steering > 0 turns right (heading decreases).

const VehicleData := preload("res://scripts/vehicle_data.gd")

static func step(v: Dictionary, cfg: Dictionary, throttle: float, steer: float, delta: float) -> void:
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
	v["x"] = nx
	v["z"] = nz

	# Fuel and running hours only count while moving.
	if absf(speed) > 0.05:
		v["fuel"] = maxf(0.0, float(v["fuel"]) - float(cfg["fuel_use"]) * delta)
		v["hours"] = float(v["hours"]) + delta / 3600.0
