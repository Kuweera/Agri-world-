extends RefCounted
# Arcade-plus suspension. Looks only: the tractor body and its implement lean and lag behind
# on springs. Work and driving use the plain position, so nothing here can change what gets
# worked. Pure logic, so the tests can check it.
# pitch: positive = nose down. roll: tilt sideways. impl_pitch: the implement swings a little
# behind the tractor. bounce: unused on flat ground (the farm has no bumps), always 0.
#
# Ground contact: the whole model (wheels included) is tilted, so a lean would push one end of
# the tyres into the ground and lift the other. Two things stop that: the lean is limited so the
# tyres differ by at most 4 x MAX_WHEEL_DEV (4 cm, about a tyre's squash) and body_y() lifts the model so its
# lowest tyre rests exactly on the ground. No tyre goes below the ground plane.

const K_BODY := 70.0
const C_BODY := 9.0
const K_IMPL := 28.0
const C_IMPL := 5.0
const MAX_PITCH := 0.03
const MAX_ROLL := 0.03
const MAX_BOUNCE := 0.0
const MAX_WHEEL_DEV := 0.01   # metres of lean at one end of the tyre footprint (pitch and roll add: at most 4x this between the highest and lowest tyre)
const MAX_IMPL_PITCH := 0.10
const MAX_DT := 0.05
const WRAP := TAU * 100.0

static func new_state() -> Dictionary:
	return {"pitch": 0.0, "pitch_v": 0.0, "roll": 0.0, "roll_v": 0.0,
		"bounce": 0.0, "bounce_v": 0.0, "impl_pitch": 0.0, "impl_pitch_v": 0.0, "dist": 0.0}

# One spring-damper step on s[key] (position) and s[key + "_v"] (velocity), kept inside +-limit.
# Plain floats are used on purpose: a Vector2 would round to 32 bits and could overshoot the limit.
static func _spring(s: Dictionary, key: String, target: float, k: float, c: float, dt: float, limit: float) -> void:
	var x: float = s[key]
	var v: float = s[key + "_v"]
	v += (k * (target - x) - c * v) * dt
	x += v * dt
	if absf(x) > limit:
		x = clampf(x, -limit, limit)
		v = 0.0
	s[key] = x
	s[key + "_v"] = v

# Largest lean (radians) that keeps every tyre within MAX_WHEEL_DEV, for a machine whose tyres
# are half_len ahead/behind and half_wid left/right of the middle.
static func pitch_limit(half_len: float) -> float:
	return minf(MAX_PITCH, MAX_WHEEL_DEV / maxf(0.5, half_len))

static func roll_limit(half_wid: float) -> float:
	return minf(MAX_ROLL, MAX_WHEEL_DEV / maxf(0.3, half_wid))

# Height of the tyre contact point at (x, z) for the current lean, before body_y() is applied.
# The model turns by roll first, then pitch (Godot's YXZ order), as tractor_view.gd sets it.
static func tyre_y(s: Dictionary, x: float, z: float) -> float:
	var p: float = s["pitch"]
	var r: float = s["roll"]
	return x * sin(r) * cos(p) - z * sin(p)

# How far the model must be raised so its lowest tyre rests exactly on the ground (never below 0).
static func body_y(s: Dictionary, half_len: float, half_wid: float) -> float:
	var lowest := 0.0
	for cx in [-half_wid, half_wid]:
		for cz in [-half_len, half_len]:
			lowest = minf(lowest, tyre_y(s, cx, cz))
	return float(s["bounce"]) - lowest

# accel: change of speed (units/s per second). speed: current speed. yaw_rate: turn rate (rad/s).
# half_len / half_wid: the machine's tyre footprint, used to limit the lean (see above).
static func step(s: Dictionary, accel: float, speed: float, yaw_rate: float, dt: float,
		half_len: float = 2.0, half_wid: float = 0.8) -> void:
	var d := clampf(dt, 0.0, MAX_DT)
	if d <= 0.0:
		return
	var a := clampf(accel, -20.0, 20.0)
	var lat := clampf(speed * yaw_rate, -20.0, 20.0)
	s["dist"] = fposmod(float(s["dist"]) + absf(speed) * d, WRAP)
	# The ground is flat, so there is nothing to make the machine bounce (no fake bump).
	var pl := pitch_limit(half_len)
	var rl := roll_limit(half_wid)
	_spring(s, "pitch", clampf(-a * 0.012, -pl, pl), K_BODY, C_BODY, d, pl)
	_spring(s, "roll", clampf(-lat * 0.012, -rl, rl), K_BODY, C_BODY, d, rl)
	_spring(s, "impl_pitch", -float(s["pitch"]) * 0.8, K_IMPL, C_IMPL, d, MAX_IMPL_PITCH)
