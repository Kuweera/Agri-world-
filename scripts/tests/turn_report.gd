extends SceneTree
# How far each machine's body leaves the field while the autopilot turns at the lane ends, and whether
# it reverses. godot --headless --script res://scripts/tests/turn_report.gd
const AP := preload("res://scripts/autopilot.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")
const PlotData := preload("res://scripts/plot_data.gd")
const ImplementData := preload("res://scripts/implement_data.gd")

func _run(vid: String, impl: String, plot: String) -> Dictionary:
	var base: Dictionary = VehicleData.VEHICLES[vid]
	var cfg: Dictionary = VehicleModel.loaded_config(base, impl)
	var width := int(base.get("work_width", 1))
	if impl != "none":
		width = ImplementData.width_of(impl)
	var p := PlotData.get_plot(plot)
	var rows := int(p["rows"])
	var cols := int(p["cols"])
	var jobs: Array = []
	for r in rows:
		jobs.append({"row": r, "c0": 0, "c1": cols - 1})
	var rect := PlotData.rect_of(plot)
	var cz := rect.position.y + rect.size.y + 3.0   # start just south of the plot
	var v := {"x": rect.position.x - 9.0, "z": FarmLayout.row_z(0, plot) + (FarmLayout.PITCH * float((width - 1) / 2)), "heading": PI / 2.0, "speed": 0.0, "fuel": 9999.0, "hours": 0.0,
		"implement": impl, "vehicle": vid}
	var ap = AP.new()
	if not ap.start(v, jobs, float(base["work_offset"]), width, rows, plot):
		return {"ok": false}
	var hl := float(base["hit_len"]) * 0.5
	var hw := float(base["hit_wid"]) * 0.5
	var over := 0.0
	var lane_over := 0.0     # the lane start/end poses themselves (a header ahead puts the body outside the field)
	for wp in ap.wps:
		if bool(wp["pose"]):
			var wh: float = wp["h"]
			var wf := Vector2(sin(wh), cos(wh))
			var wsd := Vector2(wf.y, -wf.x)
			for a in [-1.0, 1.0]:
				for b in [-1.0, 1.0]:
					var wc: Vector2 = Vector2(float(wp["x"]), float(wp["z"])) + wf * float(base["hit_len"]) * 0.5 * a + wsd * float(base["hit_wid"]) * 0.5 * b
					lane_over = maxf(lane_over, maxf(maxf(rect.position.x - wc.x, wc.x - rect.end.x), maxf(rect.position.y - wc.y, wc.y - rect.end.y)))
	var at := Vector3.ZERO
	var rev_t := 0.0
	var started := false
	var slowest := 0
	var t := 0.0
	var dt := 1.0 / 60.0
	while ap.active and t < 900.0:
		var tu := Time.get_ticks_usec()
		var ctl: Vector2 = ap.update(v, dt, cfg)
		slowest = maxi(slowest, Time.get_ticks_usec() - tu)
		v["_working"] = ap.working
		VehicleModel.step(v, cfg, ctl.x, ctl.y, dt)
		t += dt
		if float(v["speed"]) < -0.05:
			rev_t += dt
		if ap.working and rect.has_point(Vector2(float(v["x"]), float(v["z"]))):
			started = true
		if not started:
			continue
		var h: float = v["heading"]
		var f := Vector2(sin(h), cos(h))
		var s := Vector2(f.y, -f.x)
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var c: Vector2 = Vector2(float(v["x"]), float(v["z"])) + f * hl * a + s * hw * b
				var d := maxf(maxf(rect.position.x - c.x, c.x - rect.end.x), maxf(rect.position.y - c.y, c.y - rect.end.y))
				if d > over:
					over = d
					at = Vector3(t, float(v["x"]), float(v["z"]))
	return {"ok": true, "fin": ap.finished, "msg": ap.message, "t": t, "ms": float(slowest) / 1000.0, "over": over, "lane": lane_over, "rev": rev_t, "at": at}

func _init() -> void:
	print("| machine | tool | plot | finished | time s | body past field edge m (road edge = 4.5) | lane poses alone need | reversing s | longest plan ms |")
	print("|---|---|---|---|---|---|---|---|---|")
	for c in [["tractor", "none", "farm"], ["tractor", "plough", "farm"], ["tractor_heavy", "plough", "farm"], ["combine_small", "none", "farm"], ["combine_large", "none", "p01"], ["combine_large_b", "none", "p01"]]:
		var r := _run(c[0], c[1], c[2])
		if not r["ok"]:
			print("| %s | %s | %s | did not start |" % [c[0], c[1], c[2]])
			continue
		print("| %s | %s | %s | %s %s | %.0f | %.2f | %.2f | %.1f | %.0f |" % [c[0], c[1], c[2], str(r["fin"]), r["msg"], r["t"], r["over"], r["lane"], r["rev"], r["ms"]])
		print("   worst at t=%.0f x=%.1f z=%.1f (plot x %.1f..%.1f z %.1f..%.1f)" % [r["at"].x, r["at"].y, r["at"].z, PlotData.rect_of(c[2]).position.x, PlotData.rect_of(c[2]).end.x, PlotData.rect_of(c[2]).position.y, PlotData.rect_of(c[2]).end.y])
	quit()
