extends RefCounted
# Arcade-plus suspension. Looks only: the tractor body and its implement lean, bounce and
# lag behind on springs. Work and driving use the plain position, so nothing here can
# change what gets worked. Pure logic, so the tests can check it.
# pitch: positive = nose down. roll: tilt sideways. bounce: metres up. impl_pitch: the
# implement swings a little behind the tractor.

const K_BODY := 70.0
const C_BODY := 9.0
const K_IMPL := 28.0
const C_IMPL := 5.0
const MAX_PITCH := 0.07
const MAX_ROLL := 0.06
const MAX_BOUNCE := 0.07
const MAX_IMPL_PITCH := 0.10
const MAX_DT := 0.05
const WRAP := TAU * 100.0

static func new_state() -> Dictionary:
	return {"pitch": 0.0, "pitch_v": 0.0, "roll": 0.0, "roll_v": 0.0,
		"bounce": 0.0, "bounce_v": 0.0, "impl_pitch": 0.0, "impl_pitch_v": 0.0, "dist": 0.0}

# One spring-damper step. Returns Vector2(position, velocity), kept inside +-limit.
static func _spring(x: float, v: float, target: float, k: float, c: float, dt: float, limit: float) -> Vector2:
	v += (k * (target - x) - c * v) * dt
	x += v * dt
	if absf(x) > limit:
		x = clampf(x, -limit, limit)
		v = 0.0
	return Vector2(x, v)

# accel: change of speed (units/s per second). speed: current speed. yaw_rate: turn rate (rad/s).
static func step(s: Dictionary, accel: float, speed: float, yaw_rate: float, dt: float) -> void:
	var d := clampf(dt, 0.0, MAX_DT)
	if d <= 0.0:
		return
	var a := clampf(accel, -20.0, 20.0)
	var lat := clampf(speed * yaw_rate, -20.0, 20.0)
	s["dist"] = fposmod(float(s["dist"]) + absf(speed) * d, WRAP)
	var run := minf(absf(speed) / 3.0, 1.0)
	var dist: float = s["dist"]
	var bump := (sin(dist * 9.0) * 0.6 + sin(dist * 23.0 + 1.3) * 0.4) * run
	var p := _spring(float(s["pitch"]), float(s["pitch_v"]), clampf(-a * 0.012, -MAX_PITCH, MAX_PITCH),
		K_BODY, C_BODY, d, MAX_PITCH)
	var r := _spring(float(s["roll"]), float(s["roll_v"]), clampf(-lat * 0.012, -MAX_ROLL, MAX_ROLL),
		K_BODY, C_BODY, d, MAX_ROLL)
	var b := _spring(float(s["bounce"]), float(s["bounce_v"]), bump * 0.03, K_BODY, C_BODY, d, MAX_BOUNCE)
	var ip := _spring(float(s["impl_pitch"]), float(s["impl_pitch_v"]), -p.x * 0.8 + bump * 0.015,
		K_IMPL, C_IMPL, d, MAX_IMPL_PITCH)
	s["pitch"] = p.x
	s["pitch_v"] = p.y
	s["roll"] = r.x
	s["roll_v"] = r.y
	s["bounce"] = b.x
	s["bounce_v"] = b.y
	s["impl_pitch"] = ip.x
	s["impl_pitch_v"] = ip.y
