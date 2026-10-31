extends RefCounted
# Autopilot for field work. Pure logic, no nodes.
#
# jobs: one entry per field row that needs work: {"row": r, "c0": first_col, "c1": last_col}.
# It drives a lane along each row, only as far as the tiles that need work,
# alternating direction. Between lanes it makes a real turn: the machine steers with the same
# drivetrain as the player (wheelbase, steering lock, grip). The turn is the shortest forward path
# for its turning radius (dubins.gd; three-arc "bulb" turns when the lanes are closer than two radii),
# followed by pure pursuit. Poses (position + heading) are used for lane ends; plain waypoints
# (roads) are just passed.
# It starts with the end of the job that is closest to the tractor, so it does not
# drive back over finished rows. It only works the field while driving a lane
# (`working` is true).
#
# Wide implements: a lane covers `width` rows at once (the tool works the rows beside it),
# so plan_lanes() groups the rows into lanes `width` rows apart instead of one lane per row.
#
# Each tick: call update(tr, dt, cfg) with the machine's (loaded) vehicle settings and feed the returned
# Vector2(throttle, steer) to VehicleModel.step(). It never sets the heading or speed itself.

const FarmLayout := preload("res://scripts/farm_layout.gd")
const PlotData := preload("res://scripts/plot_data.gd")
const RoadNet := preload("res://scripts/road_net.gd")
const Dubins := preload("res://scripts/dubins.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")

const MARGIN := 0.3        # lane runs this far past the first/last tile
const CORRIDOR_Z := 3.6    # the main road
const YARD_Z := 3.7        # tractor further south than this is in the yard
const NEAR_PLOT := 4.0     # within this distance of a plot a machine drives to its lanes directly
const RUN_IN := 1.2        # lane starts this far before the margin, so the machine is straight and the tool is down
const TURN_SPEED := 3.0    # speed in turns (u/s)
const BRAKE_PLAN := 3.0    # deceleration assumed when planning the slow-down before a turn
const PATH_STEP := 0.25
const END_TOL := 0.4       # a lane end counts as reached when this close along the path
const ARRIVE_R := 1.4      # a road waypoint counts as reached when this close
const TURN_MARGIN := 1.25  # planned turning radius is this much wider than the tightest the machine can do
const PATH_TIMEOUT := 90.0 # seconds on one waypoint before giving up
const TURN_ALLOWANCE := 6.0   # extra distance per lane for the headland turn (fuel estimate)
const BLOCK_WAIT := 8.0   # seconds to wait for another machine to move before giving up

var plot_id := "farm"    # the plot whose rows the jobs refer to
var active := false
var working := false
var finished := false
var message := ""
var wps: Array = []
var idx := 0
var aligned := false
var stuck_time := 0.0
var path_pts := PackedVector2Array()   # the path being followed to waypoint wps[idx]
var path_v := PackedFloat32Array()     # speed allowed at each path point
var path_s := PackedFloat32Array()     # distance along the path to each point
var path_i := 0
var path_wp := -1                      # the waypoint the path was planned for
var wp_time := 0.0
var lane_count := 0      # lanes in the current plan
var holding := false     # set by the game while another machine is in the way: wait longer
var kind := ""           # what this autopilot does: "plough", "seeder", "fertilizer", "harvester"
var reserved_rows: Array = []   # field rows its lanes cover, so another machine takes other rows
var pass_no := 0         # which pass of the job (the game allows 3)
var pass_worked := 0     # tiles worked in this pass
var job_worked := 0      # tiles worked in the whole job

func _add(x: float, z: float, work: bool) -> void:
	wps.append({"x": x, "z": z, "work": work, "pose": false, "h": 0.0})

# A waypoint the machine must reach exactly, facing heading h (the lane ends).
func _add_pose(x: float, z: float, h: float, work: bool) -> void:
	wps.append({"x": x, "z": z, "work": work, "pose": true, "h": h})

# Plain waypoints face the next waypoint.
func _face_next() -> void:
	for k in wps.size():
		if bool(wps[k]["pose"]):
			continue
		if k + 1 < wps.size():
			wps[k]["h"] = atan2(float(wps[k + 1]["x"]) - float(wps[k]["x"]), float(wps[k + 1]["z"]) - float(wps[k]["z"]))
		elif k > 0:
			wps[k]["h"] = float(wps[k - 1]["h"])

# Tractor x where a lane starts (.x) and ends (.y), for lane direction dir (+1 = toward +x).
# The tool works `off` behind the tractor, so the tractor runs `off` past the tiles.
func _lane_x(job: Dictionary, dir: int, off: float) -> Vector2:
	var half := FarmLayout.PITCH / 2.0
	var left := FarmLayout.col_x(int(job["c0"]), plot_id) - half
	var right := FarmLayout.col_x(int(job["c1"]), plot_id) + half
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
func start(tr: Dictionary, jobs: Array, work_offset: float = 1.8, width: int = 1, rows: int = 8, plot: String = "farm") -> bool:
	if jobs.is_empty():
		return false
	plot_id = plot
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
	var first_z := FarmLayout.row_z(int(list[0]["row"]), plot_id)
	var last_z := FarmLayout.row_z(int(list[list.size() - 1]["row"]), plot_id)
	if absf(tz - last_z) < absf(tz - first_z):
		list.reverse()

	var first: Dictionary = list[0]
	var mid := (FarmLayout.col_x(int(first["c0"]), plot_id) + FarmLayout.col_x(int(first["c1"]), plot_id)) / 2.0
	var first_row_z := FarmLayout.row_z(int(first["row"]), plot_id)
	# Far from the plot: drive along the roads and enter the lane from the road beside the plot.
	var near := PlotData.rect_of(plot_id).grow(NEAR_PLOT).has_point(Vector2(tx, tz))
	var from := Vector2(tx, tz)
	var route: Array = []
	var access := Vector2.ZERO
	# First lane runs away from the side the tractor is on (or the side it enters from).
	var dir := -1 if tx >= mid else 1
	if not near:
		var aw := PlotData.access_of(plot_id, "w")
		var ae := PlotData.access_of(plot_id, "e")
		var rw: Array = RoadNet.route(from, aw)
		var re: Array = RoadNet.route(from, ae)
		if RoadNet.path_length(from, rw) <= RoadNet.path_length(from, re):
			route = rw
			access = aw
			dir = 1
		else:
			route = re
			access = ae
			dir = -1
		if route.is_empty():
			near = true   # no road found: go straight
			dir = -1 if tx >= mid else 1
	wps = []
	if not near:
		for p in route:
			_add(p.x, p.y, false)
		_add(access.x, first_row_z, false)   # along the road to the row
	for k in list.size():
		var job: Dictionary = list[k]
		var lx := _lane_x(job, dir, work_offset)
		var z := FarmLayout.row_z(int(job["row"]), plot_id)
		var lane_h := PI / 2.0 if dir > 0 else 3.0 * PI / 2.0
		_add_pose(lx.x - float(dir) * RUN_IN, z, lane_h, false)   # lane start: turn in, straighten, lower the tool
		# Lane end: the tool works on the way. The end counts as reached END_TOL early, so put it that much further.
		_add_pose(lx.y + float(dir) * (END_TOL + 0.1), z, lane_h, true)
		dir = -dir
	_face_next()

	_reset_run()
	return true

func _reset_run() -> void:
	idx = 0
	active = true
	working = false
	finished = false
	aligned = false
	stuck_time = 0.0
	wp_time = 0.0
	path_wp = -1
	path_pts = PackedVector2Array()
	message = ""

# Drives to a plot without working: onto the roads, along them to the road beside the plot, then
# into the middle of the plot. kind is "travel" so the game knows nothing is worked.
func travel_to_plot(tr: Dictionary, id: String) -> bool:
	if not PlotData.has_plot(id):
		return false
	var from := Vector2(float(tr["x"]), float(tr["z"]))
	var aw := PlotData.access_of(id, "w")
	var ae := PlotData.access_of(id, "e")
	var rw: Array = RoadNet.route(from, aw)
	var re: Array = RoadNet.route(from, ae)
	var route: Array = rw
	var access := aw
	if RoadNet.path_length(from, re) < RoadNet.path_length(from, rw):
		route = re
		access = ae
	if route.is_empty():
		return false
	wps = []
	for p in route:
		_add(p.x, p.y, false)
	_add(float(PlotData.get_plot(id)["cx"]), access.y, false)   # into the middle of the plot
	plot_id = id
	kind = "travel"
	lane_count = 0
	reserved_rows = []
	pass_no = 3        # never starts another pass
	pass_worked = 0
	job_worked = 0
	_face_next()
	_reset_run()
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
	return total + float(lane_count) * TURN_ALLOWANCE

# Rough fuel needed for the planned path (driving at about 70% of top speed).
func estimate_fuel(tr: Dictionary, cfg: Dictionary) -> float:
	return estimate_length(tr) / (float(cfg["max_speed"]) * 0.7) * float(cfg["fuel_use"])

func stop(reason: String) -> void:
	active = false
	working = false
	reserved_rows = []
	message = reason

func _default_cfg() -> Dictionary:
	return VehicleModel.loaded_config(VehicleData.VEHICLES[VehicleData.DEFAULT_VEHICLE], "none")

func _turn_speed(cfg: Dictionary) -> float:
	return minf(TURN_SPEED, 0.6 * float(cfg["max_speed"]))

# Radius the turns are planned with: a little wider than the machine's tightest circle.
func turn_radius(cfg: Dictionary) -> float:
	var lim := VehicleModel.steer_limit(cfg, _turn_speed(cfg))
	return maxf(1.0, VehicleModel.wheelbase_of(cfg) / tan(lim)) * TURN_MARGIN

# True when reaching the road waypoint w going forward needs a big loop (or is impossible).
func _needs_loop(tr: Dictionary, th0: float, w: Dictionary, rho: float) -> bool:
	var p: Dictionary = Dubins.to_point(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), rho)
	if p.is_empty():
		return true
	var straight := Vector2(float(tr["x"]), float(tr["z"])).distance_to(Vector2(float(w["x"]), float(w["z"])))
	return float(p["length"]) > 1.6 * straight + rho

# Plans the path from the machine's real pose to waypoint wps[idx].
func _plan(tr: Dictionary, cfg: Dictionary) -> void:
	var rho := turn_radius(cfg)
	var th0 := PI / 2.0 - float(tr["heading"])
	# A road waypoint that lies inside the machine's turning circle cannot be reached going forward
	# (it would need a big loop or reversing). It is only a waypoint, so skip to the next one.
	while idx < wps.size() - 1 and not bool(wps[idx]["pose"]) and _needs_loop(tr, th0, wps[idx], rho):
		idx += 1
	var w: Dictionary = wps[idx]
	var th1 := PI / 2.0 - float(w["h"])
	var best: Dictionary = {}
	if bool(w["pose"]):
		best = Dubins.shortest(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), th1, rho)
	else:
		# A road waypoint only has to be passed: turn onto the tangent, then drive straight at it.
		best = Dubins.to_point(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), rho)
		if best.is_empty():
			best = Dubins.shortest(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), th1, rho)
	var smp: Dictionary = Dubins.sample(float(tr["x"]), float(tr["z"]), th0, rho, best, PATH_STEP)
	path_pts = smp["pts"]
	var turn: PackedFloat32Array = smp["turn"]
	var n := path_pts.size()
	path_v = PackedFloat32Array()
	path_v.resize(n)
	path_s = PackedFloat32Array()
	path_s.resize(n)
	var cruise := float(cfg["max_speed"])
	var vt := minf(_turn_speed(cfg), sqrt(5.0 * rho))
	for k in n:
		path_v[k] = vt if turn[k] != 0.0 else cruise
		path_s[k] = 0.0 if k == 0 else path_s[k - 1] + path_pts[k - 1].distance_to(path_pts[k])
	# End speed: stop at the very end, be ready to turn after a lane, otherwise cruise.
	var v_end := cruise
	if idx >= wps.size() - 1:
		v_end = 0.0
	elif bool(w["pose"]):
		v_end = vt
	path_v[n - 1] = minf(path_v[n - 1], v_end)
	# Slow down in time for every slower point ahead.
	for k in range(n - 2, -1, -1):
		var reach := sqrt(path_v[k + 1] * path_v[k + 1] + 2.0 * BRAKE_PLAN * (path_s[k + 1] - path_s[k]))
		path_v[k] = minf(path_v[k], reach)
	path_i = 0
	path_wp = idx
	wp_time = 0.0

# Returns Vector2(throttle, steer). cfg: the machine's vehicle settings with its tool's load.
func update(tr: Dictionary, dt: float, cfg: Dictionary = {}) -> Vector2:
	if not active:
		return Vector2.ZERO
	if float(tr["fuel"]) <= 0.0:
		stop("Out of fuel")
		return Vector2.ZERO
	if cfg.is_empty():
		cfg = _default_cfg()
	wp_time += dt
	if wp_time > PATH_TIMEOUT:
		stop("Autopilot could not reach its point")
		return Vector2.ZERO

	var pos := Vector2(float(tr["x"]), float(tr["z"]))
	var heading: float = tr["heading"]
	var speed: float = tr["speed"]
	if path_wp != idx:
		_plan(tr, cfg)   # may skip unreachable road waypoints, so idx can move

	# Where on the path are we?
	var n := path_pts.size()
	var best := path_i
	var bd := INF
	for k in range(path_i, mini(n, path_i + 80)):
		var d := pos.distance_to(path_pts[k])
		if d < bd:
			bd = d
			best = k
	path_i = best
	var w: Dictionary = wps[idx]
	var wp_pos := Vector2(float(w["x"]), float(w["z"]))
	var remaining: float = path_s[n - 1] - path_s[path_i]
	var arrived := false
	if bool(w["pose"]):
		arrived = remaining < END_TOL or (path_i >= n - 1 and pos.distance_to(wp_pos) < 1.0)
	else:
		arrived = pos.distance_to(wp_pos) < ARRIVE_R
	if arrived:
		idx += 1
		stuck_time = 0.0
		if idx >= wps.size():
			active = false
			finished = true
			working = false
			reserved_rows = []
			message = "Done"
			return Vector2.ZERO
		_plan(tr, cfg)
		w = wps[idx]
		n = path_pts.size()
		remaining = path_s[n - 1]

	working = bool(w["work"])

	# Pure pursuit: steer toward a point a little way ahead on the path.
	var ld := clampf(1.0 + 0.35 * absf(speed), 1.0, 3.0)
	var ti := path_i
	var acc := 0.0
	while ti < n - 1 and acc < ld:
		acc += path_pts[ti].distance_to(path_pts[ti + 1])
		ti += 1
	var target := path_pts[ti]
	var to_t := target - pos
	var dist_t := maxf(to_t.length(), 0.3)
	var alpha := angle_difference(heading, atan2(to_t.x, to_t.y))
	var wheel := atan(2.0 * VehicleModel.wheelbase_of(cfg) * sin(alpha) / dist_t)
	var steer := clampf(-wheel / maxf(0.05, VehicleModel.steer_limit(cfg, speed)), -1.0, 1.0)

	# Speed from the path's speed plan.
	var free: bool = not bool(tr.get("_working", true))
	var vmax := float(cfg.get("free_speed", cfg["max_speed"])) if free else float(cfg["max_speed"])
	var thr := clampf(path_v[path_i] / maxf(0.1, vmax), 0.15, 1.0)

	if absf(speed) < 0.05:
		stuck_time += dt
	else:
		stuck_time = 0.0
	if stuck_time > (BLOCK_WAIT if holding else 1.5):
		stop("Autopilot blocked")
		return Vector2.ZERO
	return Vector2(thr, steer)
