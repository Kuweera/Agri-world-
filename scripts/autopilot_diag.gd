extends RefCounted
# Autopilot diagnostics (recovery directive, phase 1.1). READ-ONLY: it never changes the autopilot,
# the machine or the game. It writes user://autopilot_diag.log while "Debug info" is On.
# Fields that an autopilot version does not have (e.g. path_dir/cusp in the reverse-turn version)
# are read with get() and logged as "-".
#
# Line types:  S = sample (4 per second while an autopilot is active)
#              E = event (waypoint change, tool up/down, direction change, stationary, start, end)

const LOG_PATH := "user://autopilot_diag.log"
const SAMPLE_DT := 0.25
const FLUSH_DT := 2.0
const MAX_BYTES := 1500000
const STILL_SPEED := 0.15
const STILL_REPORT := 2.0     # report a machine that has been standing this long during a job

var _buf := PackedStringArray()
var _clock := 0.0
var _flush_t := 0.0
var _m := {}       # per machine id: remembered state between frames

func _st(id: String) -> Dictionary:
	if not _m.has(id):
		_m[id] = {"active": false, "idx": -99, "work": false, "raised": false, "dir": 0, "still": 0.0,
			"still_rep": 0.0, "sample": 0.0, "t0": 0.0, "tiles0": 0, "stuck_rep": 0.0}
	return _m[id]

func tick(dt: float) -> void:
	_clock += dt
	_flush_t += dt
	if _flush_t >= FLUSH_DT:
		flush()

func flush() -> void:
	_flush_t = 0.0
	if _buf.is_empty():
		return
	var f: FileAccess
	if FileAccess.file_exists(LOG_PATH):
		f = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if f != null and f.get_length() > MAX_BYTES:
			f.close()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(LOG_PATH + ".old"))
			f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		elif f != null:
			f.seek_end()
	else:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		_buf.clear()
		return
	for line in _buf:
		f.store_line(line)
	f.close()
	_buf.clear()

func _put(kind: String, id: String, text: String) -> void:
	_buf.append("%s %7.2f %s %s" % [kind, _clock, id, text])
	if _buf.size() > 400:
		flush()

static func _f(x) -> String:
	return "%.2f" % float(x)

# Call once per machine per frame, after the autopilot and the physics step.
#   thr/st: the commands that went into the physics.  brk: brake input that went in (the autopilot has no brake channel yet).
func record(id: String, ap, m: Dictionary, thr: float, st: float, brk: float, tool_raised: bool, tiles_worked: int) -> void:
	var s := _st(id)
	var active: bool = ap.active
	if not active:
		if bool(s["active"]):
			s["active"] = false
			_put("E", id, "END reason='%s' finished=%s idx=%s tiles=%d (job %d) time=%.1f" % [
				str(ap.message), str(ap.finished), str(ap.idx), tiles_worked, tiles_worked - int(s["tiles0"]), _clock - float(s["t0"])])
			flush()
		return
	var dt := 1.0 / 60.0
	var speed: float = float(m.get("speed", 0.0))
	var wps: Array = ap.wps
	var idx: int = int(ap.idx)
	var wp: Dictionary = {}
	if idx >= 0 and idx < wps.size():
		wp = wps[idx]
	var dist_wp := -1.0
	if not wp.is_empty():
		dist_wp = Vector2(float(m["x"]) - float(wp["x"]), float(m["z"]) - float(wp["z"])).length()

	if not bool(s["active"]):
		s["active"] = true
		s["t0"] = _clock
		s["tiles0"] = tiles_worked
		s["idx"] = -99
		s["still"] = 0.0
		s["dir"] = 0
		_put("E", id, "START type=%s kind=%s waypoints=%d lanes=%s plot=%s pos=(%s,%s) heading=%s" % [
			str(m.get("vehicle", "?")), str(ap.kind), wps.size(), str(ap.lane_count), str(ap.plot_id),
			_f(m["x"]), _f(m["z"]), _f(m["heading"])])

	# Events
	if idx != int(s["idx"]):
		s["idx"] = idx
		var job_txt := "-"
		if not wp.is_empty():
			job_txt = "work=%s pose=%s target=(%s,%s) pass=%s" % [str(wp.get("work", "?")), str(wp.get("pose", "?")), _f(wp["x"]), _f(wp["z"]), str(ap.pass_no)]
		_put("E", id, "WP idx=%d/%d %s dist=%s speed=%s" % [idx, wps.size(), job_txt, _f(dist_wp), _f(speed)])
	if bool(ap.working) != bool(s["work"]):
		s["work"] = bool(ap.working)
		_put("E", id, "WORKING=%s tiles=%d" % [str(ap.working), tiles_worked])
	if tool_raised != bool(s["raised"]):
		s["raised"] = tool_raised
		_put("E", id, "TOOL %s" % ("raised" if tool_raised else "lowered"))
	var dir := 0
	if speed > 0.4:
		dir = 1
	elif speed < -0.4:
		dir = -1
	if dir != 0 and dir != int(s["dir"]):
		if int(s["dir"]) != 0:
			_put("E", id, "GEAR %s speed=%s idx=%d path_i=%s" % ["FORWARD" if dir > 0 else "REVERSE", _f(speed), idx, str(ap.path_i)])
		s["dir"] = dir
	if absf(speed) < STILL_SPEED:
		s["still"] = float(s["still"]) + dt
		if float(s["still"]) >= STILL_REPORT and _clock - float(s["still_rep"]) >= 3.0:
			s["still_rep"] = _clock
			_put("E", id, "STATIONARY %.1fs idx=%d dist_wp=%s thr=%s brk=%s blocked=%s holding=%s stuck_time=%s" % [
				float(s["still"]), idx, _f(dist_wp), _f(thr), _f(brk), str(m.get("_blocked", false)), str(ap.holding), _f(ap.stuck_time)])
	else:
		s["still"] = 0.0

	# Periodic sample
	s["sample"] = float(s["sample"]) + dt
	if float(s["sample"]) >= SAMPLE_DT:
		s["sample"] = 0.0
		var pv := "-"
		if ap.path_v.size() > 0 and int(ap.path_i) < ap.path_v.size():
			pv = _f(ap.path_v[int(ap.path_i)])
		var pdir = ap.get("path_dir")
		var pdir_txt := "-"
		if pdir != null and pdir.size() > 0 and int(ap.path_i) < pdir.size():
			pdir_txt = str(int(pdir[int(ap.path_i)]))
		var cusp = ap.get("cusp")
		_put("S", id, "idx=%d path_i=%s/%d dir=%s cusp=%s v=%s vt=%s thr=%s brk=%s st=%s dwp=%s raised=%s tiles=%d blocked=%s hold=%s still=%.1f stuck=%s wp_t=%s" % [
			idx, str(ap.path_i), ap.path_pts.size(), pdir_txt, "-" if cusp == null else str(cusp),
			_f(speed), pv, _f(thr), _f(brk), _f(st), _f(dist_wp), str(tool_raised), tiles_worked,
			str(m.get("_blocked", false)), str(ap.holding), float(s["still"]), _f(ap.stuck_time), _f(ap.wp_time)])
