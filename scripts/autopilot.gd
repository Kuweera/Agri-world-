extends RefCounted
# Autopilot for field work. Pure logic, no nodes.
#
# It plans straight lanes along the field rows, alternating direction, and
# drives them with the normal vehicle model. Between lanes it PIVOTS on the spot
# (a simplification: the tractor cannot make a 1.5-unit-wide U-turn).
# It only works the field while driving a lane (`working` is true).
#
# Each tick: call update(), feed the returned Vector2(throttle, steer) to
# VehicleModel.step(). It may set the tractor's heading/speed directly while pivoting.

const FarmLayout := preload("res://scripts/farm_layout.gd")

const EDGE := 7.8          # lanes run from -EDGE to +EDGE (outside the field)
const CORRIDOR_Z := 3.6    # free strip between the field and the farmhouse
const PIVOT_RATE := 2.0    # radians per second
const ARRIVE := 0.08

var active := false
var working := false
var finished := false
var message := ""
var wps: Array = []
var idx := 0
var aligned := false
var stuck_time := 0.0

func _add(x: float, z: float, work: bool) -> void:
	wps.append({"x": x, "z": z, "work": work})

# rows: field row numbers (0..ROWS-1) that need work. Returns false if there is none.
func start(tr: Dictionary, rows: Array) -> bool:
	if rows.is_empty():
		return false
	var dir := -1 if float(tr["x"]) >= 0.0 else 1
	var start_x := -dir * EDGE
	wps = []
	_add(float(tr["x"]), CORRIDOR_Z, false)
	_add(start_x, CORRIDOR_Z, false)
	_add(start_x, FarmLayout.row_z(rows[0]), false)
	for k in rows.size():
		var end_x := dir * EDGE
		_add(end_x, FarmLayout.row_z(rows[k]), true)
		if k < rows.size() - 1:
			_add(end_x, FarmLayout.row_z(rows[k + 1]), false)
			dir = -dir
	idx = 0
	active = true
	working = false
	finished = false
	aligned = false
	stuck_time = 0.0
	message = ""
	return true

func stop(reason: String) -> void:
	active = false
	working = false
	message = reason

# Returns Vector2(throttle, steer).
func update(tr: Dictionary, dt: float) -> Vector2:
	if not active:
		return Vector2.ZERO
	if float(tr["fuel"]) <= 0.0:
		stop("Out of fuel")
		return Vector2.ZERO

	var w: Dictionary = wps[idx]
	var dx: float = float(w["x"]) - float(tr["x"])
	var dz: float = float(w["z"]) - float(tr["z"])
	var length := sqrt(dx * dx + dz * dz)
	var heading: float = tr["heading"]
	var along := dx * sin(heading) + dz * cos(heading)

	# Arrived at this waypoint (or just passed it): snap onto it and move on.
	if length < ARRIVE or (aligned and along < 0.05):
		tr["x"] = w["x"]
		tr["z"] = w["z"]
		tr["speed"] = 0.0
		idx += 1
		aligned = false
		working = false
		stuck_time = 0.0
		if idx >= wps.size():
			active = false
			finished = true
			message = "Done"
		return Vector2.ZERO

	# Pivot on the spot until facing the waypoint.
	var want := atan2(dx, dz)
	var diff := angle_difference(heading, want)
	if absf(diff) > 0.02:
		tr["speed"] = 0.0
		aligned = false
		working = false
		var rot := clampf(diff, -PIVOT_RATE * dt, PIVOT_RATE * dt)
		tr["heading"] = fposmod(heading + rot, TAU)
		return Vector2.ZERO

	# Drive straight, slowing down near the waypoint.
	tr["heading"] = fposmod(want, TAU)
	aligned = true
	working = bool(w["work"])
	if absf(float(tr["speed"])) < 0.05:
		stuck_time += dt
	else:
		stuck_time = 0.0
	if stuck_time > 1.5:
		stop("Autopilot blocked")
		return Vector2.ZERO
	return Vector2(clampf(length / 2.0, 0.25, 1.0), 0.0)
