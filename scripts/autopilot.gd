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
const LANE_END_SPEED := 1.5   # speed at the end of a lane (u/s)
const REVERSE_SPEED := 2.0   # speed when backing up in a turn (u/s)
const ROAD_CLEAR := 0.45   # a turn keeps the machine this far inside the road edge
const GEAR_COST := 4.0     # a gear change counts as this many metres when choosing a turn
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
var path_dir := PackedFloat32Array()   # +1 driving forward, -1 backing up, at each path point
var turn_cache := {}                   # found reverse turns, by shape
var steer_wait := false                # standing at a gear change while the wheel swings round
var reverse_turns := 0                 # how many turns used reverse gear (for tests and reports)
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


# ---- Turns that stay inside the field's headland (reversing when there is no room) ----

# Area the machine's body may use while turning at a lane end: the field plus the headland up to the
# edge of the road (so a turn never goes onto the road or the next field). It always includes the
# start and goal poses.
func _turn_box(sx: float, sy: float, sth: float, gx: float, gy: float, gth: float, hl: float, hw: float) -> Rect2:
	var box := PlotData.rect_of(plot_id).grow(PlotData.SETBACK - PlotData.ROAD_HALF - ROAD_CLEAR)
	for pose in [[sx, sy, sth], [gx, gy, gth]]:
		for c in _corners(Vector2(pose[0], pose[1]), pose[2], hl, hw):
			box = box.expand(c)
	return box.grow(0.35)   # the poses at the lane ends already touch the edge: a little slack

func _corners(p: Vector2, th: float, hl: float, hw: float) -> Array:
	var f := Vector2(cos(th), sin(th))
	var s := Vector2(-f.y, f.x)
	return [p + f * hl + s * hw, p + f * hl - s * hw, p - f * hl + s * hw, p - f * hl - s * hw]

func _fits(box: Rect2, p: Vector2, th: float, hl: float, hw: float) -> bool:
	for c in _corners(p, th, hl, hw):
		if not box.has_point(c):
			return false
	return true

func _put(o: Dictionary, p: Vector2, gear: float, turn: float, th: float) -> void:
	o["pts"].append(p)
	o["dir"].append(gear)
	o["turn"].append(turn)
	o["th"].append(th)

# One arc of the turn, sampled. gear +1 forward, -1 reverse; t = steering side (+1 left, -1 right).
# Returns the new [x, y, th] and appends points to pts/dirs/turns.
func _arc(st: Array, gear: int, t: int, ang: float, rho: float, o: Dictionary) -> void:
	var n := maxi(1, int(ceil(ang * rho / PATH_STEP)))
	var u := ang / float(n)
	var x: float = st[0]
	var y: float = st[1]
	var th: float = st[2]
	for i in n:
		if gear > 0:
			x += rho * t * (sin(th + t * u) - sin(th))
			y += rho * t * (cos(th) - cos(th + t * u))
			th += t * u
		else:
			var th2 := th - t * u
			x -= rho * t * (sin(th) - sin(th2))
			y -= rho * t * (cos(th2) - cos(th))
			th = th2
		_put(o, Vector2(x, y), float(gear), float(t), th)
	st[0] = x
	st[1] = y
	st[2] = th

func _straight(st: Array, gear: int, length: float, o: Dictionary) -> void:
	var n := maxi(1, int(ceil(length / PATH_STEP)))
	var d := length / float(n) * float(gear)
	for i in n:
		st[0] = float(st[0]) + d * cos(float(st[2]))
		st[1] = float(st[1]) + d * sin(float(st[2]))
		_put(o, Vector2(st[0], st[1]), float(gear), 0.0, float(st[2]))

# Builds one multi-point turn: alternating forward / reverse arcs that all rotate the machine the same way,
# with a straight piece (s > 0 backing up, s < 0 going forward) after the second arc. rot = +1 / -1 is the
# rotation sense. Returns {"pts", "dir", "turn", "th"} (th = heading at the last point) or {} if it misses the goal.
func _build_turn(sx: float, sy: float, sth: float, rot: int, angles: Array, s: float, rho: float) -> Dictionary:
	var o := {"pts": PackedVector2Array(), "dir": PackedFloat32Array(), "turn": PackedFloat32Array(), "th": PackedFloat32Array()}
	_put(o, Vector2(sx, sy), 1.0, 0.0, sth)
	var st: Array = [sx, sy, sth]
	for i in angles.size():
		var gear := 1 if i % 2 == 0 else -1
		_arc(st, gear, rot if gear > 0 else -rot, float(angles[i]), rho, o)
		if i == 1 and absf(s) > 0.001:
			_straight(st, -1 if s > 0.0 else 1, absf(s), o)
	o["end"] = st
	return o

# Adds the turn made of these arcs to cands when a straight piece can close the gap to the goal (lx, ly).
func _consider(angles: Array, rot: int, rho: float, lx: float, ly: float, cands: Array) -> void:
	var px := 0.0
	var py := 0.0
	var th := 0.0
	var th_after2 := 0.0
	var arc_len := 0.0
	for i in angles.size():
		var a: float = angles[i]
		var sg := 1.0 if i % 2 == 0 else -1.0
		var phi := th + a * 0.5
		px += sg * 2.0 * rho * sin(a * 0.5) * cos(phi)
		py += sg * 2.0 * rho * sin(a * 0.5) * sin(phi)
		th += a
		arc_len += a * rho * (1.0 if i % 2 == 0 else 1.4)
		if i == 1:
			th_after2 = th
	var ex := lx - px
	var ey := ly - py
	var s := -(ex * cos(th_after2) + ey * sin(th_after2))      # backing up along the heading moves by -s*d
	var rx := ex + s * cos(th_after2)
	var ry := ey + s * sin(th_after2)
	if rx * rx + ry * ry < 0.2 * 0.2:
		cands.append([arc_len + absf(s) + GEAR_COST * float(angles.size() - 1), rot, angles, s])

# Looks for a turn from the lane-end pose to the next lane's start pose that stays in `box`,
# using reverse gear. Pure geometry: tries 3-arc and 5-arc turns on a grid of angles.
func _reverse_turn(sx: float, sy: float, sth: float, gx: float, gy: float, gth: float, rho: float, box: Rect2, hl: float, hw: float) -> Dictionary:
	var cands: Array = []      # [approx cost, rot, angles, s]
	for rot in [1, -1]:
		var delta := fposmod(float(rot) * (gth - sth), TAU)
		if delta < 0.5 or delta > TAU - 0.5:
			continue
		# Goal in the frame of the start pose, mirrored for rot = -1.
		var dx := gx - sx
		var dy := gy - sy
		var lx := dx * cos(sth) + dy * sin(sth)
		var ly := (-dx * sin(sth) + dy * cos(sth)) * float(rot)
		var step := deg_to_rad(2.0)
		var a1 := step
		while a1 < delta:                      # 3 arcs: forward, back, forward
			var a2 := step
			while a1 + a2 < delta:
				_consider([a1, a2, delta - a1 - a2], rot, rho, lx, ly, cands)
				a2 += step
			a1 += step
		a1 = step                              # 5 arcs, mirror-symmetric
		while 2.0 * a1 < delta:
			var a2 := step
			while 2.0 * (a1 + a2) < delta:
				_consider([a1, a2, delta - 2.0 * (a1 + a2), a2, a1], rot, rho, lx, ly, cands)
				a2 += step
			a1 += step
		var step3 := deg_to_rad(5.0)           # 7 arcs, mirror-symmetric
		a1 = step3
		while 2.0 * a1 < delta:
			var a2 := step3
			while 2.0 * (a1 + a2) < delta:
				var a3 := step3
				while 2.0 * (a1 + a2 + a3) < delta:
					_consider([a1, a2, a3, delta - 2.0 * (a1 + a2 + a3), a3, a2, a1], rot, rho, lx, ly, cands)
					a3 += step3
				a2 += step3
			a1 += step3
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	# Cheapest first; the first one that stays inside the box and reaches the goal wins.
	for k in mini(cands.size(), 400):
		var c: Array = cands[k]
		var cand := _build_turn(sx, sy, sth, int(c[1]), c[2], float(c[3]), rho)
		if _score_turn(cand, gx, gy, gth, box, hl, hw) < INF:
			return cand
	return {}


# ---- Search for a turn with reverse gear (used when the simple multi-point turns do not fit) ----

# One move of the search: x, y, th after driving `ang` radians of arc (or `ang * rho` metres straight when t = 0).
func _move(x: float, y: float, th: float, gear: int, t: int, ang: float, rho: float) -> Array:
	if t == 0:
		var d := ang * rho * float(gear)
		return [x + d * cos(th), y + d * sin(th), th]
	if gear > 0:
		return [x + rho * t * (sin(th + t * ang) - sin(th)), y + rho * t * (cos(th) - cos(th + t * ang)), th + t * ang]
	var th2 := th - t * ang
	return [x - rho * t * (sin(th) - sin(th2)), y - rho * t * (cos(th2) - cos(th)), th2]

# Hybrid A*: forward and reverse arcs and straights on a heading lattice. At each node it tries to finish
# with one smooth Dubins path (forward) or one backed-up Dubins path straight to the goal pose.
# Returns {"pts", "dir", "turn", "th"} or {}.
func _search_turn(sx: float, sy: float, sth: float, gx: float, gy: float, gth: float, rho: float, box: Rect2, hl: float, hw: float) -> Dictionary:
	var u := deg_to_rad(15.0)
	var ds := maxf(0.6, rho * u)
	var cell := maxf(0.4, ds * 0.4)
	var nodes: Array = []       # [x, y, th, gear, g, parent, t]
	var open: Array = []        # binary heap of [f, node index]
	var seen := {}
	nodes.append([sx, sy, sth, 1, 0.0, -1, 0])
	_heap_push(open, [Vector2(sx, sy).distance_to(Vector2(gx, gy)), 0])
	var expansions := 0
	var finish_tries := 0
	var goal_p := Vector2(gx, gy)
	while not open.is_empty() and expansions < 6000:
		var top: Array = _heap_pop(open)
		var ni: int = top[1]
		var nd: Array = nodes[ni]
		expansions += 1
		var np := Vector2(nd[0], nd[1])
		# Try to finish from here.
		if np.distance_to(goal_p) < 1.6 * rho + 2.0 and absf(angle_difference(float(nd[2]), gth)) < 1.0 and finish_tries < 600:
			finish_tries += 1
			var fin := _finish(nd[0], nd[1], nd[2], gx, gy, gth, rho, box, hl, hw)
			if not fin.is_empty():
				return _assemble(nodes, ni, fin, rho, sth, sx, sy)
		for gear in [1, -1]:
			for st in [0, 1, -1]:
				var m := _move(nd[0], nd[1], nd[2], gear, st, u, rho) if st != 0 else _move(nd[0], nd[1], nd[2], gear, 0, ds / rho, rho)
				var mp := Vector2(m[0], m[1])
				# Body inside the box at the middle and the end of the move.
				var mid := _move(nd[0], nd[1], nd[2], gear, st, u * 0.5, rho) if st != 0 else _move(nd[0], nd[1], nd[2], gear, 0, ds * 0.5 / rho, rho)
				var th_m: float = mid[2]
				var th_e: float = m[2]
				if not _fits(box, Vector2(mid[0], mid[1]), th_m, hl, hw) or not _fits(box, mp, th_e, hl, hw):
					continue
				var key := Vector3i(roundi(mp.x / cell), roundi(mp.y / cell), roundi(wrapf(th_e - sth, 0.0, TAU) / u) * 2 + (0 if gear > 0 else 1))
				var cost: float = float(nd[4]) + ds * (1.0 if gear > 0 else 1.5)
				if int(nd[3]) != gear and ni != 0:
					cost += GEAR_COST
				if st != 0 and int(nd[6]) != 0 and st != int(nd[6]) * (1 if gear == int(nd[3]) else -1):
					cost += 0.5
				if seen.has(key) and float(seen[key]) <= cost:
					continue
				seen[key] = cost
				nodes.append([m[0], m[1], th_e, gear, cost, ni, st])
				_heap_push(open, [cost + mp.distance_to(goal_p) + 0.35 * rho * absf(angle_difference(th_e, gth)), nodes.size() - 1])
	return {}

func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p

func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var s := i
			if l < n and float(h[l][0]) < float(h[s][0]):
				s = l
			if r < n and float(h[r][0]) < float(h[s][0]):
				s = r
			if s == i:
				break
			var tmp = h[s]
			h[s] = h[i]
			h[i] = tmp
			i = s
	return top

# A smooth way from this pose to the goal: forward Dubins, or the same kind of path driven backwards.
# Returns {"pts", "th", "turn", "gear"} (points after the pose) or {}.
func _finish(x: float, y: float, th: float, gx: float, gy: float, gth: float, rho: float, box: Rect2, hl: float, hw: float) -> Dictionary:
	var best := {}
	var best_len := INF
	# Already at the goal pose: nothing left to drive.
	if Vector2(x, y).distance_to(Vector2(gx, gy)) < 0.35 and absf(angle_difference(th, gth)) < 0.1:
		return {"pts": PackedVector2Array([Vector2(x, y), Vector2(gx, gy)]), "th": PackedFloat32Array([th, gth]), "turn": PackedFloat32Array([0.0, 0.0]), "gear": 1}
	for gear in [1, -1]:
		var path: Dictionary
		var smp: Dictionary
		if gear > 0:
			path = Dubins.shortest(x, y, th, gx, gy, gth, rho)
			if path.is_empty():
				continue
			smp = Dubins.sample(x, y, th, rho, path, PATH_STEP)
		else:
			# Backing up from here to the goal follows the same curve as driving forward from the goal to here (the body points the same way).
			path = Dubins.shortest(gx, gy, gth, x, y, th, rho)
			if path.is_empty():
				continue
			smp = Dubins.sample(gx, gy, gth, rho, path, PATH_STEP)
		var length: float = float(path["length"]) * (1.0 if gear > 0 else 1.5)
		if length >= best_len:
			continue
		var pts: PackedVector2Array = smp["pts"]
		var ths: PackedFloat32Array = smp["th"]
		var turn: PackedFloat32Array = smp["turn"]
		var ok := true
		for k in pts.size():
			var tk := float(ths[k])
			if not _fits(box, pts[k], tk, hl, hw):
				ok = false
				break
		if not ok:
			continue
		best_len = length
		if gear > 0:
			best = {"pts": pts, "th": ths, "turn": turn, "gear": 1}
		else:
			# Reverse the sampled list so it runs from here to the goal; headings turn round.
			var rp := PackedVector2Array()
			var rt := PackedFloat32Array()
			var rn := PackedFloat32Array()
			for k in range(pts.size() - 1, -1, -1):
				rp.append(pts[k])
				rt.append(float(ths[k]))
				rn.append(-float(turn[k]))
			best = {"pts": rp, "th": rt, "turn": rn, "gear": -1}
	return best

func _assemble(nodes: Array, last: int, fin: Dictionary, rho: float, sth: float, sx: float, sy: float) -> Dictionary:
	var chain: Array = []
	var i := last
	while i >= 0:
		chain.push_front(i)
		i = int(nodes[i][5])
	var o := {"pts": PackedVector2Array(), "dir": PackedFloat32Array(), "turn": PackedFloat32Array(), "th": PackedFloat32Array()}
	_put(o, Vector2(sx, sy), 1.0, 0.0, sth)
	var u := deg_to_rad(15.0)
	var ds := maxf(0.6, rho * u)
	for k in range(1, chain.size()):
		var nd: Array = nodes[chain[k]]
		var prev: Array = nodes[chain[k - 1]]
		var st: Array = [prev[0], prev[1], prev[2]]
		if int(nd[6]) != 0:
			_arc(st, int(nd[3]), int(nd[6]), u, rho, o)
		else:
			_straight(st, int(nd[3]), ds, o)
	var gear: int = int(fin["gear"])
	var pts: PackedVector2Array = fin["pts"]
	var ths: PackedFloat32Array = fin["th"]
	var turn: PackedFloat32Array = fin["turn"]
	for k in range(1, pts.size()):
		_put(o, pts[k], float(gear), float(turn[k]), float(ths[k]))
	return o

# Cost of a candidate turn (length, reversing and gear changes), or INF if it misses the goal or leaves the box.
func _score_turn(c: Dictionary, gx: float, gy: float, gth: float, box: Rect2, hl: float, hw: float) -> float:
	var st: Array = c["end"]
	if Vector2(st[0], st[1]).distance_to(Vector2(gx, gy)) > 0.3 or absf(angle_difference(float(st[2]), gth)) > 0.06:
		return INF
	var pts: PackedVector2Array = c["pts"]
	var dirs: PackedFloat32Array = c["dir"]
	var ths: PackedFloat32Array = c["th"]
	var cost := 0.0
	for k in pts.size():
		if not _fits(box, pts[k], ths[k], hl, hw):
			return INF
		if k > 0:
			cost += pts[k].distance_to(pts[k - 1]) * (1.4 if dirs[k] < 0.0 else 1.0)
			if dirs[k] != dirs[k - 1]:
				cost += GEAR_COST
	return cost

# Lane-end turns repeat from lane to lane (same shape, only moved along the field), so a found turn is kept
# and reused: the search is only run for a shape not seen before.
func _cached_turn(sx: float, sy: float, sth: float, gx: float, gy: float, gth: float, rho: float, box: Rect2, hl: float, hw: float) -> Dictionary:
	var far := 45.0
	var q := 0.25     # positions are compared in 0.25 steps: the machine never stops exactly on the lane end
	var key := "%d|%d|%.2f|%.2f|%.2f|%d|%d|%d|%d|%d|%d" % [
		roundi(sth * 100.0), roundi(gth * 100.0), rho, hl, hw, roundi((gx - sx) / q), roundi((gy - sy) / q),
		roundi(clampf(box.position.x - sx, -far, far) / q), roundi(clampf(box.end.x - sx, -far, far) / q),
		roundi(clampf(box.position.y - sy, -far, far) / q), roundi(clampf(box.end.y - sy, -far, far) / q)]
	var org := Vector2(sx, sy)
	if turn_cache.has(key):
		var c: Dictionary = turn_cache[key]
		if c.is_empty():
			return {}
		var pts := PackedVector2Array()
		for p in (c["pts"] as PackedVector2Array):
			pts.append(p + org)
		return {"pts": pts, "dir": c["dir"], "turn": c["turn"], "th": c["th"]}
	var rt: Dictionary = _reverse_turn(sx, sy, sth, gx, gy, gth, rho, box, hl, hw)
	if rt.is_empty():
		rt = _search_turn(sx, sy, sth, gx, gy, gth, rho, box, hl, hw)
	if rt.is_empty():
		turn_cache[key] = {}
	else:
		var rel := PackedVector2Array()
		for p in (rt["pts"] as PackedVector2Array):
			rel.append(p - org)
		turn_cache[key] = {"pts": rel, "dir": rt["dir"], "turn": rt["turn"], "th": rt["th"]}
	return rt

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
	path_dir = PackedFloat32Array()
	path_dir.resize(n)
	path_dir.fill(1.0)
	# A turn at the end of a lane must not leave the field and its headland (the road edge). When the forward
	# turn would, look for one that backs up (a multi-point turn).
	if bool(w["pose"]) and not bool(w["work"]) and idx > 0 and bool(wps[idx - 1]["work"]):
		var hl := float(cfg.get("hit_len", 2.3)) * 0.5
		var hw := float(cfg.get("hit_wid", 1.4)) * 0.5
		var box := _turn_box(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), th1, hl, hw)
		var ths: PackedFloat32Array = smp["th"]
		var inside := true
		for k in n:
			if not _fits(box, path_pts[k], ths[k], hl, hw):
				inside = false
				break
		if not inside:
			var rt: Dictionary = _cached_turn(float(tr["x"]), float(tr["z"]), th0, float(w["x"]), float(w["z"]), th1, rho, box, hl, hw)
			if not rt.is_empty():
				path_pts = rt["pts"]
				path_dir = rt["dir"]
				turn = rt["turn"]
				n = path_pts.size()
				reverse_turns += 1
	path_v = PackedFloat32Array()
	path_v.resize(n)
	path_s = PackedFloat32Array()
	path_s.resize(n)
	var cruise := float(cfg["max_speed"])
	var vt := minf(_turn_speed(cfg), sqrt(5.0 * rho))
	var vr := minf(REVERSE_SPEED, vt)
	for k in n:
		path_v[k] = vt if turn[k] != 0.0 else cruise
		if path_dir[k] < 0.0:
			path_v[k] = vr
		path_s[k] = 0.0 if k == 0 else path_s[k - 1] + path_pts[k - 1].distance_to(path_pts[k])
	# End speed: stop at the very end, be ready to turn after a lane, otherwise cruise.
	var v_end := cruise
	if idx >= wps.size() - 1:
		v_end = 0.0
	elif bool(w["pose"]):
		v_end = vt
		if bool(w["work"]):
			v_end = minf(vt, LANE_END_SPEED)   # a lane end may be followed by backing up: arrive slowly
	path_v[n - 1] = minf(path_v[n - 1], v_end)
	# Come to a stop where the gear changes.
	for k in range(0, n - 1):
		if path_dir[k] != path_dir[k + 1]:
			path_v[k] = 0.0
	# Slow down in time for every slower point ahead.
	for k in range(n - 2, -1, -1):
		var reach := sqrt(path_v[k + 1] * path_v[k + 1] + 2.0 * BRAKE_PLAN * (path_s[k + 1] - path_s[k]))
		path_v[k] = minf(path_v[k], reach)
	path_i = 0
	steer_wait = false
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

	# Where on the path are we? Only look up to the next gear change: a reversing path doubles back
	# on itself, so the nearest point could otherwise jump to the wrong part.
	var n := path_pts.size()
	var cusp := _next_cusp(path_i)
	var best := path_i
	var bd := INF
	for k in range(path_i, mini(cusp + 1, mini(n, path_i + 80))):
		var d := pos.distance_to(path_pts[k])
		if d < bd:
			bd = d
			best = k
	path_i = best
	var gear := 1.0 if path_dir[mini(path_i + 1, n - 1)] >= 0.0 else -1.0
	if cusp < n - 1 and path_i >= cusp - 1 and absf(speed) < 0.3 and pos.distance_to(path_pts[cusp]) < 3.5:
		path_i = cusp + 1      # stopped at the gear change: carry on in the other gear
		steer_wait = true      # but first turn the wheel to where the next piece needs it
		cusp = _next_cusp(path_i)
		gear = 1.0 if path_dir[mini(path_i + 1, n - 1)] >= 0.0 else -1.0
		stuck_time = 0.0
	var w: Dictionary = wps[idx]
	var wp_pos := Vector2(float(w["x"]), float(w["z"]))
	var remaining: float = path_s[n - 1] - path_s[path_i]
	var arrived := false
	if bool(w["pose"]):
		arrived = remaining < END_TOL or (path_i >= n - 1 and pos.distance_to(wp_pos) < 1.0)
		if arrived and absf(angle_difference(heading, float(w["h"]))) > 0.5 and wp_time < PATH_TIMEOUT - 5.0:
			arrived = false   # not lined up yet: keep going toward the end point
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
		cusp = _next_cusp(path_i)
		gear = 1.0 if path_dir[mini(path_i + 1, n - 1)] >= 0.0 else -1.0

	working = bool(w["work"])

	# Pure pursuit: steer toward a point a little way ahead on the path (behind the machine when backing up).
	var ld := clampf(1.0 + 0.35 * absf(speed), 1.0, 3.0)
	var ti := path_i
	var acc := 0.0
	while ti < mini(n - 1, cusp) and acc < ld:
		acc += path_pts[ti].distance_to(path_pts[ti + 1])
		ti += 1
	var target := path_pts[ti]
	var to_t := target - pos
	var dist_t := maxf(to_t.length(), 0.3)
	var steer := 0.0
	var lim := maxf(0.05, VehicleModel.steer_limit(cfg, speed))
	if gear > 0.0:
		var alpha := angle_difference(heading, atan2(to_t.x, to_t.y))
		var wheel := atan(2.0 * VehicleModel.wheelbase_of(cfg) * sin(alpha) / dist_t)
		steer = clampf(-wheel / lim, -1.0, 1.0)
	else:
		# Backing up: the same circle is driven the other way round, so the steering sign flips.
		var alpha_r := angle_difference(heading + PI, atan2(to_t.x, to_t.y))
		var wheel_r := atan(2.0 * VehicleModel.wheelbase_of(cfg) * sin(alpha_r) / dist_t)
		steer = clampf(wheel_r / lim, -1.0, 1.0)

	# Speed from the path's speed plan.
	var free: bool = not bool(tr.get("_working", true))
	var vmax := float(cfg.get("free_speed", cfg["max_speed"])) if free else float(cfg["max_speed"])
	var thr := 0.0
	if gear > 0.0:
		thr = clampf(path_v[path_i] / maxf(0.1, vmax), 0.15, 1.0)
	else:
		thr = -clampf(path_v[path_i] / maxf(0.1, vmax * float(cfg.get("reverse_factor", 0.5))), 0.15, 1.0)
	# Right at a gear change: stop (brake with the opposite pedal if it is going too fast).
	if cusp < n - 1 and path_s[cusp] - path_s[path_i] < 0.45:
		thr = 0.0
	if absf(speed) > 0.1 and signf(speed) != gear and cusp < n - 1:
		thr = 0.0
	if absf(speed) > absf(path_v[path_i]) + 0.5 and absf(speed) > 0.4 and signf(speed) == gear:
		thr = -gear      # too fast for the plan: brake

	if steer_wait:
		var want := steer * lim
		if absf(float(tr.get("_steer", 0.0)) - want) > 0.08 and absf(speed) < 0.5:
			thr = 0.0
		else:
			steer_wait = false
	if absf(speed) < 0.05 and thr != 0.0 and not steer_wait:
		stuck_time += dt
	else:
		stuck_time = 0.0
	if stuck_time > (BLOCK_WAIT if holding else 1.5):
		stop("Autopilot blocked")
		return Vector2.ZERO
	return Vector2(thr, steer)

# Index of the last point before the next gear change at or after k (n - 1 when there is none).
func _next_cusp(k: int) -> int:
	var n := path_dir.size()
	for i in range(maxi(k, 0), n - 1):
		if path_dir[i] != path_dir[i + 1]:
			return i
	return n - 1
