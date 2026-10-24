extends RefCounted
# Autopilot for field work. Pure logic, no nodes.
#
# jobs: one entry per field row that needs work: {"row": r, "c0": first_col, "c1": last_col}.
# It drives a lane along each row, only as far as the tiles that need work,
# alternating direction. Between lanes it PIVOTS on the spot (a simplification:
# a real U-turn does not fit between rows 1.5 units apart).
# It starts with the end of the job that is closest to the tractor, so it does not
# drive back over finished rows. It only works the field while driving a lane
# (`working` is true).
#
# Wide implements: a lane covers `width` rows at once (the tool works the rows beside it),
# so plan_lanes() groups the rows into lanes `width` rows apart instead of one lane per row.
#
# Each tick: call update(), feed the returned Vector2(throttle, steer) to
# VehicleModel.step(). It may set the tractor's heading/speed directly while pivoting.

const FarmLayout := preload("res://scripts/farm_layout.gd")

const MARGIN := 0.3        # lane runs this far past the first/last tile
const CORRIDOR_Z := 3.6    # free strip between the field and the farmhouse
const YARD_Z := 3.7        # tractor further south than this is in the yard
const PIVOT_RATE := 2.0    # radians per second
const ARRIVE := 0.08
const BLOCK_WAIT := 8.0   # seconds to wait for another machine to move before giving up

var active := false
var working := false
var finished := false
var message := ""
var wps: Array = []
var idx := 0
var aligned := false
var stuck_time := 0.0
var lane_count := 0      # lanes in the current plan
var holding := false     # set by the game while another machine is in the way: wait longer
var kind := ""           # what this autopilot does: "plough", "seeder", "fertilizer", "harvester"
var reserved_rows: Array = []   # field rows its lanes cover, so another machine takes other rows
var pass_no := 0         # which pass of the job (the game allows 3)
var pass_worked := 0     # tiles worked in this pass
var job_worked := 0      # tiles worked in the whole job

func _add(x: float, z: float, work: bool) -> void:
	wps.append({"x": x, "z": z, "work": work})

# Tractor x where a lane starts (.x) and ends (.y), for lane direction dir (+1 = toward +x).
# The tool works `off` behind the tractor, so the tractor runs `off` past the tiles.
func _lane_x(job: Dictionary, dir: int, off: float) -> Vector2:
	var half := FarmLayout.PITCH / 2.0
	var left := FarmLayout.col_x(int(job["c0"])) - half
	var right := FarmLayout.col_x(int(job["c1"])) + half
	if dir > 0:
		return Vector2(left - MARGIN + off, right + MARGIN + off)
	return Vector2(right + MARGIN - off, left - MARGIN - off)

# Groups the rows that need work into lanes for an implement `width` tiles wide (odd).
# Each lane is a job {"row": centre row, "c0", "c1"}: it covers the rows from centre - half
# to centre + half, and runs over the widest column range any of them needs.
# jobs must be sorted by row (jobs_for gives that). width 1 gives the jobs back unchanged.
static func plan_lanes(jobs: Array, width: int, rows: int) -> Array:
	if width <= 1 or jobs.is_empty():
		return jobs.duplicate()
	var half := int((width - 1) / 2)
	var lanes: Array = []
	var k := 0
	while k < jobs.size():
		var centre := mini(int(jobs[k]["row"]) + half, rows - 1)
		var c0 := int(jobs[k]["c0"])
		var c1 := int(jobs[k]["c1"])
		var n := k + 1
		while n < jobs.size() and int(jobs[n]["row"]) <= centre + half:
			c0 = mini(c0, int(jobs[n]["c0"]))
			c1 = maxi(c1, int(jobs[n]["c1"]))
			n += 1
		lanes.append({"row": centre, "c0": c0, "c1": c1})
		k = n
	return lanes

# Returns false if there is nothing to do. width and rows plan wide lanes (see plan_lanes).
func start(tr: Dictionary, jobs: Array, work_offset: float = 1.8, width: int = 1, rows: int = 8) -> bool:
	if jobs.is_empty():
		return false
	var list: Array = plan_lanes(jobs, width, rows)
	lane_count = list.size()
	reserved_rows = []
	var half_w := int((width - 1) / 2)
	for lane in list:
		for r in range(int(lane["row"]) - half_w, int(lane["row"]) + half_w + 1):
			if r >= 0 and r < rows and not reserved_rows.has(r):
				reserved_rows.append(r)
	var tx := float(tr["x"])
	var tz := float(tr["z"])

	# Begin with whichever end of the job is nearest the tractor.
	var first_z := FarmLayout.row_z(int(list[0]["row"]))
	var last_z := FarmLayout.row_z(int(list[list.size() - 1]["row"]))
	if absf(tz - last_z) < absf(tz - first_z):
		list.reverse()

	# First lane runs away from the side the tractor is on.
	var first: Dictionary = list[0]
	var mid := (FarmLayout.col_x(int(first["c0"])) + FarmLayout.col_x(int(first["c1"]))) / 2.0
	var dir := -1 if tx >= mid else 1
	var sx := _lane_x(first, dir, work_offset).x
	var x0 := maxf(tx, sx) if dir < 0 else minf(tx, sx)
	var first_row_z := FarmLayout.row_z(int(first["row"]))

	wps = []
	if tz > YARD_Z:
		# In the yard: go round through the corridor in front of the house.
		_add(tx, CORRIDOR_Z, false)
		_add(x0, CORRIDOR_Z, false)
		_add(x0, first_row_z, false)
	else:
		_add(x0, tz, false)
		_add(x0, first_row_z, false)

	for k in list.size():
		var job: Dictionary = list[k]
		var lx := _lane_x(job, dir, work_offset)
		var z := FarmLayout.row_z(int(job["row"]))
		_add(lx.y, z, true)
		if k < list.size() - 1:
			var nxt: Dictionary = list[k + 1]
			var nz := FarmLayout.row_z(int(nxt["row"]))
			var nl := _lane_x(nxt, -dir, work_offset)
			var ex := lx.y
			# Keep going the same way if the next lane needs us further along.
			var xx := maxf(ex, nl.x) if dir > 0 else minf(ex, nl.x)
			if absf(xx - ex) > 0.05:
				_add(xx, z, false)
			_add(xx, nz, false)
			dir = -dir

	idx = 0
	active = true
	working = false
	finished = false
	aligned = false
	stuck_time = 0.0
	message = ""
	return true

func estimate_length(tr: Dictionary) -> float:
	var x := float(tr["x"])
	var z := float(tr["z"])
	var total := 0.0
	for w in wps:
		var dx: float = float(w["x"]) - x
		var dz: float = float(w["z"]) - z
		total += sqrt(dx * dx + dz * dz)
		x = float(w["x"])
		z = float(w["z"])
	return total

# Rough fuel needed for the planned path (driving at about 70% of top speed).
func estimate_fuel(tr: Dictionary, cfg: Dictionary) -> float:
	return estimate_length(tr) / (float(cfg["max_speed"]) * 0.7) * float(cfg["fuel_use"])

func stop(reason: String) -> void:
	active = false
	working = false
	reserved_rows = []
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
			reserved_rows = []
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
	if stuck_time > (BLOCK_WAIT if holding else 1.5):
		stop("Autopilot blocked")
		return Vector2.ZERO
	return Vector2(clampf(length / 2.0, 0.25, 1.0), 0.0)
