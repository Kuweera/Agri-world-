extends SceneTree
# Headless logic tests. Run with:
#   godot --headless --script res://scripts/tests/test_game_state.gd
# Prints PASS/FAIL lines and exits with the number of failures.

const GameState := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const AutoPilotScript := preload("res://scripts/autopilot.gd")
const Dubins := preload("res://scripts/dubins.gd")
const DriveControls := preload("res://scripts/drive_controls.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const CropModels := preload("res://scripts/crop_models.gd")
const TileModels := preload("res://scripts/tile_models.gd")
const CropStages := preload("res://scripts/crop_stages.gd")
const EnvironmentSetup := preload("res://scripts/environment_setup.gd")
const FarmSceneryScript := preload("res://scripts/farm_scenery.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const ImplementModels := preload("res://scripts/implement_models.gd")
const Suspension := preload("res://scripts/suspension.gd")
const ShopCatalog := preload("res://scripts/shop_catalog.gd")
const MachineModels := preload("res://scripts/machine_models.gd")
const MachineryShop := preload("res://scripts/machinery_shop.gd")
const TractorViewScript := preload("res://scripts/tractor_view.gd")
const Hitbox := preload("res://scripts/hitbox.gd")
const PlotData := preload("res://scripts/plot_data.gd")
const RoadNet := preload("res://scripts/road_net.gd")

var failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		failures += 1

func _cleanup(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

# Puts the tractor so its work point is the given world point (heading 0, moving) and works once.
func _wide_work(s, c: Vector2, impl: String, vcfg: Dictionary, now: float, crop: String) -> String:
	s.tractor["implement"] = impl
	s.tractor["heading"] = 0.0
	s.tractor["speed"] = 1.0
	s.tractor["x"] = c.x
	s.tractor["z"] = c.y + float(vcfg["work_offset"])
	s.last_work_tile = -1
	return s.work_with_tractor(vcfg, now, crop)

func _states(s, st: String) -> Array:
	var out: Array = []
	for k in s.tiles.size():
		if s.tiles[k]["state"] == st:
			out.append(k)
	return out

func _run(v: Dictionary, cfg: Dictionary, throttle: float, steer: float, frames: int) -> void:
	for i in frames:
		VehicleModel.step(v, cfg, throttle, steer, 1.0 / 60.0)

# Simulates an autopilot job headlessly using the same logic as the game.
func _auto_job(s, kind: String, now0: float, fuel: float = 20.0) -> Dictionary:
	var ap = AutoPilotScript.new()
	# Harvesting is done by a combine (its own header, cutting ahead); the rest by the tractor.
	var is_comb := kind == "harvester"
	var vcfg: Dictionary = VehicleData.VEHICLES["combine_small" if is_comb else "tractor"]
	if not is_comb:
		s.tractor["implement"] = kind
	s.tractor["fuel"] = fuel
	s.last_work_tile = -1
	var jobs: Array = s.jobs_for(kind, now0)
	var lane_w: int = int(vcfg.get("work_width", 1)) if is_comb else 1
	if not ap.start(s.tractor, jobs, float(vcfg["work_offset"]), lane_w, 8):
		return {"started": false}
	var t := 0.0
	var dt := 1.0 / 60.0
	while ap.active and t < 300.0:
		var ctl: Vector2 = ap.update(s.tractor, dt, vcfg)
		VehicleModel.step(s.tractor, vcfg, ctl.x, ctl.y, dt)
		if ap.working:
			s.work_with_tractor(vcfg, now0 + t, "beans")
		t += dt
	return {"started": true, "time": t, "finished": ap.finished, "message": ap.message, "est": 0.0}

# Runs the autopilot with any catalogue implement (loaded speed, wide lanes). Returns what happened.
func _auto_wide(s, impl: String, now0: float, fuel: float = 20.0) -> Dictionary:
	var ap = AutoPilotScript.new()
	var vcfg: Dictionary = VehicleModel.loaded_config(VehicleData.VEHICLES["tractor"], impl)
	var kind: String = ImplementData.type_of(impl)
	s.tractor["implement"] = impl
	s.tractor["fuel"] = fuel
	s.last_work_tile = -1
	var jobs: Array = s.jobs_for(kind, now0)
	if not ap.start(s.tractor, jobs, float(vcfg["work_offset"]), ImplementData.width_of(impl), GameState.ROWS):
		return {"started": false}
	var length: float = ap.estimate_length(s.tractor)
	var lanes: int = ap.lane_count
	var t := 0.0
	var dt := 1.0 / 60.0
	while ap.active and t < 400.0:
		var ctl: Vector2 = ap.update(s.tractor, dt, vcfg)
		VehicleModel.step(s.tractor, vcfg, ctl.x, ctl.y, dt)
		if ap.working:
			s.work_with_tractor(vcfg, now0 + t, "beans")
		t += dt
	return {"started": true, "time": t, "finished": ap.finished, "length": length, "lanes": lanes,
		"fuel_used": fuel - float(s.tractor["fuel"])}

# Runs a whole job on a plot (no crops needed) and measures how far the body leaves the field while working.
func _turn_run(vid: String, impl: String, plot: String) -> Dictionary:
	var base: Dictionary = VehicleData.VEHICLES[vid]
	var cfg: Dictionary = VehicleModel.loaded_config(base, impl)
	var width := int(base.get("work_width", 1))
	if impl != "none":
		width = ImplementData.width_of(impl)
	var pl := PlotData.get_plot(plot)
	var rows := int(pl["rows"])
	var jobs: Array = []
	for r in rows:
		jobs.append({"row": r, "c0": 0, "c1": int(pl["cols"]) - 1})
	var rect := PlotData.rect_of(plot)
	var v := {"x": rect.position.x - 9.0, "z": FarmLayout.row_z(0, plot) + FarmLayout.PITCH * float((width - 1) / 2), "heading": PI / 2.0,
		"speed": 0.0, "fuel": 9999.0, "hours": 0.0, "implement": impl, "vehicle": vid}
	var ap = AutoPilotScript.new()
	if not ap.start(v, jobs, float(base["work_offset"]), width, rows, plot):
		return {"finished": false, "reverse_turns": 0, "over": 99.0, "lane": 0.0}
	var hl := float(base["hit_len"]) * 0.5
	var hw := float(base["hit_wid"]) * 0.5
	var lane := 0.0
	for wp in ap.wps:
		if bool(wp["pose"]):
			var wh: float = wp["h"]
			var wf := Vector2(sin(wh), cos(wh))
			var ws := Vector2(wf.y, -wf.x)
			for a in [-1.0, 1.0]:
				for b in [-1.0, 1.0]:
					var wc: Vector2 = Vector2(float(wp["x"]), float(wp["z"])) + wf * hl * a + ws * hw * b
					lane = maxf(lane, maxf(maxf(rect.position.x - wc.x, wc.x - rect.end.x), maxf(rect.position.y - wc.y, wc.y - rect.end.y)))
	var over := 0.0
	var started := false
	var t := 0.0
	while ap.active and t < 900.0:
		var ctl: Vector2 = ap.update(v, 1.0 / 60.0, cfg)
		v["_working"] = ap.working
		VehicleModel.step(v, cfg, ctl.x, ctl.y, 1.0 / 60.0)
		t += 1.0 / 60.0
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
				over = maxf(over, maxf(maxf(rect.position.x - c.x, c.x - rect.end.x), maxf(rect.position.y - c.y, c.y - rect.end.y)))
	return {"finished": ap.finished, "reverse_turns": int(ap.get("reverse_turns")) if "reverse_turns" in ap else 0, "over": over, "lane": lane}

func _count_state(s, st: String) -> int:
	var n := 0
	for tl in s.tiles:
		if tl["state"] == st:
			n += 1
	return n

func _init() -> void:
	var t0 := 1000.0
	var s = GameState.new()

	_check(s.money == 500, "starts with 500 money")
	_check(s.tiles.size() == 64, "has 64 tiles")
	_check(s.tiles[0]["state"] == "unploughed", "tiles start unploughed")

	# Invalid tiles
	_check(s.plough(-1) != "", "plough rejects tile -1")
	_check(s.plough(64) != "", "plough rejects tile 64")

	# Planting before ploughing fails and costs nothing
	_check(s.plant(0, "maize", t0) != "", "cannot plant on unploughed tile")
	_check(s.money == 500, "failed plant costs nothing")

	# Plough
	_check(s.plough(0) == "", "plough tile 0")
	_check(s.tiles[0]["state"] == "ploughed", "tile 0 is ploughed")
	_check(s.plough(0) != "", "cannot plough twice")

	# Plant maize
	_check(s.plant(0, "bogus", t0) != "", "unknown crop rejected")
	_check(s.plant(0, "maize", t0) == "", "plant maize")
	_check(s.money == 480, "maize seed costs 20")
	_check(s.tiles[0]["state"] == "growing", "tile 0 is growing")
	_check(s.plant(0, "beans", t0) != "", "cannot plant on growing tile")
	_check(s.money == 480, "rejected plant costs nothing")

	# Growth
	_check(absf(s.progress(0, t0 + 20.0) - 0.5) < 0.001, "half grown after 20s")
	_check(not s.is_ripe(0, t0 + 39.0), "not ripe at 39s")
	_check(s.harvest(0, t0 + 39.0) != "", "cannot harvest early")
	_check(s.tiles[0]["state"] == "growing", "early harvest leaves tile growing")
	_check(s.is_ripe(0, t0 + 40.0), "ripe at 40s")
	_check(s.harvest(0, t0 + 40.0) == "", "harvest ripe maize")
	_check(int(s.inventory.get("maize", 0)) == 4, "harvest gives 4 maize")
	_check(s.tiles[0]["state"] == "stubble", "harvested tile is left as stubble")
	_check(s.harvest(0, t0 + 41.0) != "", "cannot harvest twice")
	_check(int(s.inventory.get("maize", 0)) == 4, "double harvest adds nothing")

	# Beans on another tile
	_check(s.plough(1) == "", "plough tile 1")
	_check(s.plant(1, "beans", t0) == "", "plant beans")
	_check(s.money == 468, "beans seed costs 12")
	_check(s.harvest(1, t0 + 30.0) == "", "harvest beans after 30s")
	_check(int(s.inventory.get("beans", 0)) == 3, "harvest gives 3 beans")

	# Selling: 4 maize x 15 + 3 beans x 14 = 102
	_check(s.sell_all() == 102, "sell_all earns 102")
	_check(s.money == 570, "money after selling is 570")
	_check(s.inventory.is_empty(), "inventory empty after selling")
	_check(s.sell_all() == 0, "selling nothing earns 0")
	_check(s.money == 570, "money unchanged after empty sale")

	# Cannot overspend
	s.money = 5
	_check(s.plough(2) == "", "plough tile 2")
	_check(s.plant(2, "maize", t0) != "", "cannot afford maize at 5 money")
	_check(s.money == 5, "money never goes negative")
	_check(s.tiles[2]["state"] == "ploughed", "unaffordable plant leaves tile ploughed")

	# --- Save / load round trip ---
	var a = GameState.new()
	a.plough(0)
	a.plant(0, "maize", t0)
	a.plough(1)
	a.plant(1, "beans", t0 + 5.0)
	a.money = 300
	a.inventory["beans"] = 2
	var parsed = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b = GameState.new()
	_check(typeof(parsed) == TYPE_DICTIONARY, "save JSON parses to a dictionary")
	_check(b.from_dict(parsed) == "", "from_dict accepts a valid save")
	_check(b.money == 300, "money survives save/load")
	_check(int(b.inventory.get("beans", 0)) == 2, "stock survives save/load")
	_check(b.tiles[0]["state"] == "growing" and b.tiles[0]["crop"] == "maize", "growing maize survives")
	_check(b.tiles[2]["state"] == "unploughed", "untouched tile survives")
	_check(absf(b.progress(0, t0 + 20.0) - 0.5) < 0.001, "growth continues after load")
	_check(b.is_ripe(0, t0 + 3600.0), "crop ripens while the app is closed")
	_check(b.tiles[9]["col"] == 1 and b.tiles[9]["row"] == 1, "tile col/row rebuilt on load")

	# --- Bad saves are rejected and change nothing ---
	var good: Dictionary = a.to_dict()
	var c = GameState.new()
	c.money = 123
	var bad: Dictionary = good.duplicate(true)
	bad["schema_version"] = 99
	_check(c.from_dict(bad) != "", "rejects unknown schema version")
	bad = good.duplicate(true)
	bad["money"] = -5
	_check(c.from_dict(bad) != "", "rejects negative money")
	bad = good.duplicate(true)
	bad["inventory"] = {"gold": 5}
	_check(c.from_dict(bad) != "", "rejects unknown crop in stock")
	bad = good.duplicate(true)
	bad["inventory"] = {"maize": -1}
	_check(c.from_dict(bad) != "", "rejects negative stock")
	bad = good.duplicate(true)
	bad["tiles"] = []
	_check(c.from_dict(bad) != "", "rejects wrong tile count")
	bad = good.duplicate(true)
	bad["tiles"][0]["crop"] = "gold"
	_check(c.from_dict(bad) != "", "rejects growing tile with unknown crop")
	_check(c.money == 123, "rejected saves leave state unchanged")

	# Clock set backwards: no crash, no negative progress
	var fz = GameState.new()
	fz.plough(0)
	fz.plant(0, "maize", t0 + 100000.0)
	_check(fz.progress(0, t0) == 0.0, "future planted_at gives zero progress")

	# --- Save file on disk ---
	var path := "user://test_save.json"
	_cleanup(path)
	_check(SaveManager.load_into(GameState.new(), path) == "none", "no save file reports none")
	_check(SaveManager.save_state(a, path), "save_state writes a file")
	var d = GameState.new()
	_check(SaveManager.load_into(d, path) == "", "load_into reads the file")
	_check(d.money == 300, "file round trip keeps money")
	a.money = 400
	_check(SaveManager.save_state(a, path), "second save works")
	_check(FileAccess.file_exists(path + ".bak"), "second save keeps a backup")
	var cf := FileAccess.open(path, FileAccess.WRITE)
	cf.store_string("{ not json")
	cf.close()
	var e = GameState.new()
	_check(SaveManager.load_into(e, path) == "", "falls back to backup when save is corrupt")
	_check(e.money == 300, "backup holds the previous save")
	_cleanup(path)

	# --- Vehicle physics ---
	var cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	var v := GameState.default_tractor()
	_check(v["fuel"] == 20.0 and v["speed"] == 0.0, "tractor starts full and stopped")
	_run(v, cfg, 1.0, 0.0, 60)
	_check(v["speed"] > 3.0 and v["speed"] < 5.5, "accelerates hard from rest (grip-limited): %.2f u/s after 1 s" % float(v["speed"]))
	# --- Drivetrain: power, mass, brake, steering ---
	var dt_t := {}
	for dt_id in ["tractor", "tractor_heavy", "tractor_tracked", "combine_small", "combine_large", "combine_large_b"]:
		var dt_cfg: Dictionary = VehicleData.VEHICLES[dt_id]
		var dt_v := GameState.default_tractor()
		dt_v["fuel"] = 999.0
		var dt_n := 0
		while float(dt_v["speed"]) < 0.9 * float(dt_cfg["max_speed"]) and dt_n < 3600:
			VehicleModel.step(dt_v, dt_cfg, 1.0, 0.0, 1.0 / 60.0)
			dt_n += 1
			dt_v["z"] = -100.0   # stay clear of the farmhouse
		dt_t[dt_id] = float(dt_n) / 60.0
	_check(dt_t["tractor"] > 1.5 and dt_t["tractor_heavy"] > dt_t["tractor"], "a heavier tractor takes longer to reach speed (%.1f vs %.1f s)" % [dt_t["tractor_heavy"], dt_t["tractor"]])
	_check(dt_t["tractor"] != dt_t["tractor_heavy"] and dt_t["tractor_heavy"] != dt_t["tractor_tracked"], "tractors do not perform identically")
	var dt_pl := VehicleModel.loaded_config(VehicleData.VEHICLES["tractor"], "plough_5")
	var dt_un := VehicleData.VEHICLES["tractor"]
	_check(VehicleModel.drive_accel(dt_pl, 5.0) < VehicleModel.drive_accel(dt_un, 5.0), "an implement's weight slows the acceleration")
	_check(VehicleModel.brake_decel(dt_pl) < VehicleModel.brake_decel(dt_un), "an implement's weight lengthens the stop")
	var dt_big := VehicleModel.drive_accel(VehicleData.VEHICLES["tractor_heavy"], 8.0)
	var dt_small := VehicleModel.drive_accel(VehicleData.VEHICLES["tractor"], 8.0)
	_check(dt_big > 0.0 and dt_small > 0.0 and dt_big != dt_small, "power and mass decide the pull at speed")
	# Brake versus coast, from top speed on open ground
	var br_v := GameState.default_tractor()
	var co_v := GameState.default_tractor()
	for bv in [br_v, co_v]:
		bv["speed"] = float(cfg["max_speed"])
		bv["z"] = -100.0
	var br_d := 0.0
	var co_d := 0.0
	for bi in 600:
		VehicleModel.step(br_v, cfg, -1.0, 0.0, 1.0 / 60.0)
		VehicleModel.step(co_v, cfg, 0.0, 0.0, 1.0 / 60.0)
		if br_v["speed"] > 0.0:
			br_d += float(br_v["speed"]) / 60.0
		if co_v["speed"] > 0.0:
			co_d += float(co_v["speed"]) / 60.0
	_check(br_d > 3.0 and br_d < co_d, "braking stops shorter than coasting (%.1f vs %.1f m)" % [br_d, co_d])
	_check(float(br_v["speed"]) < 0.0, "holding reverse after braking backs up")
	# Steering: bicycle model, turning circle follows the wheelbase and steering lock
	var st_v := GameState.default_tractor()
	st_v["x"] = 100.0
	st_v["z"] = -100.0
	st_v["speed"] = 1.0
	VehicleModel.step(st_v, cfg, 0.111, 1.0, 1.0 / 60.0)
	_check(absf(float(st_v["_steer"])) <= VehicleModel.STEER_RATE / 60.0 + 0.000001, "the steering wheel angle cannot jump")
	var st_h0: float = st_v["heading"]
	var st_sum := 0.0
	for si in 180:
		VehicleModel.step(st_v, cfg, 0.111, 1.0, 1.0 / 60.0)
		st_sum += wrapf(float(st_v["heading"]) - st_h0, -PI, PI)
		st_h0 = float(st_v["heading"])
	var st_r := float(st_v["speed"]) * 3.0 / absf(st_sum)
	var st_expect := float(cfg["wheelbase"]) / tan(VehicleModel.steer_limit(cfg, float(st_v["speed"])))
	_check(absf(st_r - st_expect) / st_expect < 0.15, "turning circle follows wheelbase and lock (%.2f vs %.2f)" % [st_r, st_expect])
	_check(st_sum < 0.0, "steering right turns the heading down")
	var gr_v := GameState.default_tractor()
	gr_v["x"] = 100.0
	gr_v["z"] = -100.0
	gr_v["speed"] = float(cfg["max_speed"])
	var gr_max := 0.0
	for gi in 240:
		var gr_h: float = gr_v["heading"]
		VehicleModel.step(gr_v, cfg, 1.0, 1.0, 1.0 / 60.0)
		gr_max = maxf(gr_max, absf(wrapf(float(gr_v["heading"]) - gr_h, -PI, PI)) * 60.0 * float(gr_v["speed"]))
	_check(gr_max <= VehicleModel.LAT_MU * VehicleModel.G * 1.01, "sideways acceleration stays within grip (%.2f)" % gr_max)
	var ns_v := GameState.default_tractor()
	var ns_h: float = ns_v["heading"]
	for ni in 60:
		VehicleModel.step(ns_v, cfg, 0.0, 1.0, 1.0 / 60.0)
	_check(is_equal_approx(float(ns_v["heading"]), ns_h), "cannot steer while standing still")
	_check(v["z"] < 3.0, "default heading drives toward -z")
	_check(v["fuel"] < 20.0, "driving uses fuel")
	_check(v["hours"] > 0.0, "driving adds running hours")

	var v2 := GameState.default_tractor()
	_run(v2, cfg, 1.0, 1.0, 60)
	_check(v2["heading"] < PI, "steering right turns right (heading decreases)")
	_check(v2["x"] > 8.0, "turning right while facing -z moves toward +x")

	var v3 := GameState.default_tractor()
	_run(v3, cfg, 0.0, 1.0, 30)
	_check(absf(v3["heading"] - PI) < 0.0001, "cannot steer while stopped")

	var v4 := GameState.default_tractor()
	_run(v4, cfg, -1.0, 0.0, 120)
	_check(absf(v4["speed"] + float(cfg["max_speed"]) * 0.5) < 0.001, "reverse is half speed")

	var v5 := GameState.default_tractor()
	v5["fuel"] = 0.0
	_run(v5, cfg, 1.0, 0.0, 60)
	_check(v5["speed"] == 0.0 and v5["x"] == 8.0 and v5["z"] == 4.0, "no fuel means no movement")

	var v6 := GameState.default_tractor()
	v6["x"] = 10.9
	v6["z"] = 0.0
	v6["heading"] = PI / 2.0
	_run(v6, cfg, 1.0, 0.0, 120)
	_check(v6["x"] <= VehicleData.DRIVE_BOUNDS + 0.001, "tractor stays inside the fence")

	var v7 := GameState.default_tractor()
	v7["x"] = 0.0
	v7["z"] = 4.0
	v7["heading"] = 0.0
	_run(v7, cfg, 1.0, 0.0, 300)
	_check(v7["z"] > 4.0 and v7["z"] < 5.3, "tractor cannot drive into the farmhouse")

	# --- Tools ---
	var w = GameState.new()
	_check(w.apply_implement("none", 5, "maize", t0) == "skip", "no tool does nothing")
	_check(w.apply_implement("plough", 5, "maize", t0) == "", "plough tool ploughs")
	_check(w.tiles[5]["state"] == "ploughed", "tile 5 ploughed by tool")
	_check(w.apply_implement("plough", 5, "maize", t0) == "skip", "plough tool skips ploughed tile")
	_check(w.apply_implement("seeder", 6, "maize", t0) == "skip", "seeder skips unploughed tile")
	_check(w.apply_implement("seeder", 5, "maize", t0) == "", "seeder plants")
	_check(w.money == 480, "seeder costs seed money")
	_check(w.apply_implement("seeder", 5, "maize", t0) == "skip", "seeder skips growing tile")
	_check(w.apply_implement("harvester", 5, "maize", t0 + 10.0) == "skip", "harvester skips unripe crop")
	_check(w.apply_implement("harvester", 5, "maize", t0 + 40.0) == "", "harvester harvests ripe crop")
	_check(int(w.inventory.get("maize", 0)) == 4, "harvester adds stock")
	w.money = 5
	w.plough(7)
	_check(w.apply_implement("seeder", 7, "maize", t0) == "Not enough money", "seeder reports no money")
	_check(w.apply_implement("laser", 7, "maize", t0) == "Unknown tool", "unknown tool rejected")

	var cy = GameState.new()
	var seq: Array = []
	for n in 5:
		cy.next_implement()
		seq.append(cy.tractor["implement"])
	_check(seq == ["plough", "seeder", "none", "plough", "seeder"], "tools you start with cycle in order")

	# --- Fuel ---
	var r = GameState.new()
	r.tractor["fuel"] = 10.0
	r.money = 100
	_check(r.refuel() == "", "refuel succeeds")
	_check(r.tractor["fuel"] == 20.0 and r.money == 80, "refuel fills tank for 2 per unit")
	_check(r.refuel() == "Tank is full", "full tank refuses refuel")
	_check(r.money == 80, "full-tank refuel costs nothing")
	r.tractor["fuel"] = 5.0
	r.money = 7
	_check(r.refuel() == "", "partial refuel with little money")
	_check(r.tractor["fuel"] == 8.0 and r.money == 1, "partial refuel buys 3 units")
	_check(r.refuel() == "Not enough money", "cannot refuel with 1 money")
	_check(r.tractor["fuel"] == 8.0 and r.money == 1, "failed refuel changes nothing")

	# --- Tractor in saves, migration ---
	var tsave = GameState.new()
	tsave.tractor["x"] = 3.5
	tsave.tractor["z"] = -2.0
	tsave.tractor["fuel"] = 7.5
	tsave.tractor["hours"] = 0.5
	tsave.tractor["heading"] = 1.25
	tsave.tractor["implement"] = "plough"
	tsave.tractor["speed"] = 3.0
	var tp = JSON.parse_string(JSON.stringify(tsave.to_dict()))
	var tload = GameState.new()
	_check(tload.from_dict(tp) == "", "save with tractor loads")
	_check(tload.tractor["x"] == 3.5 and tload.tractor["z"] == -2.0, "tractor position survives")
	_check(tload.tractor["fuel"] == 7.5 and tload.tractor["implement"] == "plough", "fuel and tool survive")
	_check(absf(tload.tractor["heading"] - 1.25) < 0.0001, "heading survives")
	_check(tload.tractor["speed"] == 0.0, "tractor is stopped after load")

	var old: Dictionary = a.to_dict()
	old["schema_version"] = 1
	old.erase("tractor")
	var mig = GameState.new()
	_check(mig.from_dict(old) == "", "old v1 save is accepted")
	_check(mig.tractor["fuel"] == 20.0 and mig.tractor["x"] == 8.0, "v1 save gets a default tractor")
	_check(mig.money == a.money, "v1 save keeps money")

	var btest = GameState.new()
	btest.money = 321
	var tgood: Dictionary = tsave.to_dict()
	var tbad: Dictionary = tgood.duplicate(true)
	tbad["tractor"]["fuel"] = -1.0
	_check(btest.from_dict(tbad) != "", "rejects negative fuel")
	tbad = tgood.duplicate(true)
	tbad["tractor"]["fuel"] = 999.0
	_check(btest.from_dict(tbad) != "", "rejects fuel above capacity")
	tbad = tgood.duplicate(true)
	tbad["tractor"]["implement"] = "bogus"
	_check(btest.from_dict(tbad) != "", "rejects unknown tool")
	tbad = tgood.duplicate(true)
	tbad["tractor"]["x"] = 5000.0
	_check(btest.from_dict(tbad) != "", "rejects tractor outside the land")
	tbad = tgood.duplicate(true)
	tbad.erase("tractor")
	_check(btest.from_dict(tbad) != "", "rejects v2 save without tractor")
	_check(btest.money == 321, "rejected tractor saves change nothing")

	# --- Field layout ---
	_check(FarmLayout.COLS == GameState.COLS and FarmLayout.ROWS == GameState.ROWS, "layout size matches game state")
	_check(FarmLayout.world_to_tile(FarmLayout.col_x(3), FarmLayout.row_z(5)) == 5 * 8 + 3, "tile centre maps to its own index")
	_check(FarmLayout.world_to_tile(0.0, 5.0) == -1, "point outside the field is -1")
	var gridn = FarmGridScript.new()
	var mismatches := 0
	for xi in range(-90, 91):
		for zi in range(-190, -10):
			# a small offset keeps the points off the tile edges (the grid uses 32-bit floats)
			var gx := xi * 0.1 + 0.013
			var gz := zi * 0.1 + 0.013
			if gridn.world_to_tile(Vector3(gx, 0.0, gz)) != FarmLayout.world_to_tile(gx, gz):
				mismatches += 1
	gridn.free()
	_check(mismatches == 0, "farm_grid and farm_layout agree on every sampled point")

	# --- Work helpers ---
	var wk = GameState.new()
	wk.plough(0)
	_check(wk.can_work("plough", 1, t0) and not wk.can_work("plough", 0, t0), "can_work plough")
	_check(wk.can_work("seeder", 0, t0) and not wk.can_work("seeder", 1, t0), "can_work seeder")
	_check(wk.rows_with_work("plough", t0).size() == 8, "plough work on all 8 rows")
	_check(wk.rows_with_work("harvester", t0).is_empty(), "no harvest work at the start")

	# --- Autopilot (full headless simulation) ---
	var job = GameState.new()
	job.money = 5000
	var res: Dictionary = _auto_job(job, "plough", t0)
	_check(res["started"], "autopilot starts a ploughing job")
	_check(res["finished"], "autopilot finishes ploughing (" + str(res.get("message", "")) + ")")
	_check(res["time"] < 150.0, "ploughing the field takes under 150 s")
	_check(_count_state(job, "ploughed") == 64, "autopilot ploughs all 64 tiles")
	_check(job.tractor["fuel"] > 5.0, "ploughing the whole field leaves fuel")

	res = _auto_job(job, "seeder", t0)
	_check(res["started"] and res["finished"], "autopilot finishes seeding")
	_check(_count_state(job, "growing") == 64, "autopilot plants all 64 tiles")
	_check(job.money == 5000 - 64 * 12, "seeding charges 12 per tile")

	res = _auto_job(job, "harvester", t0 + 1000.0, 60.0)
	_check(res["started"] and res["finished"], "autopilot finishes harvesting")
	_check(int(job.inventory.get("beans", 0)) == 64 * 3, "autopilot harvests all 64 tiles")
	_check(_count_state(job, "stubble") == 64, "harvested tiles are left as stubble")
	_check(job.rows_with_work("plough", t0 + 1000.0).size() == 8, "stubble must be ploughed again")
	_check(not AutoPilotScript.new().start(job.tractor, [], 1.8), "autopilot refuses an empty job")

	# Partial job: only some rows need work
	var part = GameState.new()
	for pr in [1, 2, 5]:
		for pc in 8:
			part.plough(pr * 8 + pc)
	res = _auto_job(part, "plough", t0)
	_check(res["finished"] and _count_state(part, "unploughed") == 0, "autopilot ploughs only the rows that need it")

	# Blocked: tractor behind the farmhouse, facing it, cannot get through (the autopilot does not plan around obstacles yet)
	var blk = GameState.new()
	blk.tractor["x"] = 0.0
	blk.tractor["z"] = 10.5
	blk.tractor["heading"] = PI
	res = _auto_job(blk, "plough", t0)
	_check(res["started"] and not res["finished"], "autopilot gives up when blocked")

	# --- Brake pedal and the touch controls ---
	var bp_full := GameState.default_tractor()
	var bp_half := GameState.default_tractor()
	var bp_none := GameState.default_tractor()
	for bv2 in [bp_full, bp_half, bp_none]:
		bv2["speed"] = 8.0
		bv2["x"] = 100.0
		bv2["z"] = -100.0
	bp_full["_brake"] = 1.0
	bp_half["_brake"] = 0.5
	for bi2 in 60:
		VehicleModel.step(bp_full, cfg, 0.0, 0.0, 1.0 / 60.0)
		VehicleModel.step(bp_half, cfg, 0.0, 0.0, 1.0 / 60.0)
		VehicleModel.step(bp_none, cfg, 0.0, 0.0, 1.0 / 60.0)
	_check(float(bp_full["speed"]) < float(bp_half["speed"]) and float(bp_half["speed"]) < float(bp_none["speed"]), "a harder brake pedal slows more")
	var bp_hold := GameState.default_tractor()
	bp_hold["_brake"] = 1.0
	bp_hold["z"] = -100.0
	for bi3 in 120:
		VehicleModel.step(bp_hold, cfg, 1.0, 0.0, 1.0 / 60.0)
	_check(float(bp_hold["speed"]) == 0.0, "the brake holds the machine against the accelerator")
	var dc = DriveControls.new()
	dc.lever_rect = Rect2(0, 100, 80, 400)
	dc.lever = dc._lever_value(Vector2(40, dc._lever_y(0.6)))
	dc._update_outputs()
	_check(absf(dc.throttle - 0.6) < 0.01 and dc.brake == 0.0, "lever forward drives forward")
	dc.lever = dc._lever_value(Vector2(40, dc._lever_y(-0.5)))
	dc._update_outputs()
	_check(absf(dc.throttle + 0.5) < 0.01, "lever below the notch reverses")
	_check(dc._lever_value(Vector2(40, dc._lever_y(0.03))) == 0.0, "lever clicks to zero at the notch")
	_check(dc._lever_value(Vector2(40, -500)) == 1.0 and dc._lever_value(Vector2(40, 5000)) == -1.0, "lever is clamped at both ends")
	dc.lever = 0.6
	dc.lever_zero()
	_check(dc.lever == 0.0 and dc.throttle == 0.0, "lever_zero puts the throttle back to zero")
	dc.lever = 0.6
	dc.handbrake = true
	dc._update_outputs()
	_check(dc.throttle == 0.0 and dc.brake == 1.0, "handbrake: no drive, full brake")
	dc.handbrake = false
	dc.wheel_angle = DriveControls.WHEEL_MAX
	dc._update_outputs()
	_check(absf(dc.steer - 1.0) < 0.0001, "wheel at full lock is full steering")
	dc.wheel_angle = 0.02
	dc._update_outputs()
	_check(dc.steer == 0.0, "a tiny wheel angle is a dead zone")
	_check(dc._pedal_value(Rect2(0, 0, 100, 200), Vector2(50, 0)) == DriveControls.PEDAL_MIN and dc._pedal_value(Rect2(0, 0, 100, 200), Vector2(50, 200)) == 1.0, "pedal: light at the top, full at the bottom")
	dc.free()

	# --- Autopilot turns like a real machine: never spins on the spot, never turns faster than the drivetrain allows ---
	var rt_s = GameState.new()
	rt_s.tractor["implement"] = "plough"
	rt_s.tractor["fuel"] = 20.0
	rt_s.last_work_tile = -1
	var rt_cfg: Dictionary = VehicleModel.loaded_config(VehicleData.VEHICLES["tractor"], "plough")
	var rt_ap = AutoPilotScript.new()
	rt_ap.start(rt_s.tractor, rt_s.jobs_for("plough", t0), float(rt_cfg["work_offset"]), 1, 8)
	var rt_t := 0.0
	var rt_slow := 0.0      # radians turned while standing still
	var rt_worst_ratio := 0.0
	var rt_prev_h: float = rt_s.tractor["heading"]
	while rt_ap.active and rt_t < 200.0:
		var rt_ctl: Vector2 = rt_ap.update(rt_s.tractor, 1.0 / 60.0, rt_cfg)
		VehicleModel.step(rt_s.tractor, rt_cfg, rt_ctl.x, rt_ctl.y, 1.0 / 60.0)
		if rt_ap.working:
			rt_s.work_with_tractor(rt_cfg, t0 + rt_t, "beans")
		var rt_yaw := absf(wrapf(float(rt_s.tractor["heading"]) - rt_prev_h, -PI, PI)) * 60.0
		rt_prev_h = float(rt_s.tractor["heading"])
		var rt_sp := absf(float(rt_s.tractor["speed"]))
		# The most it can turn at this speed: the steering lock over the wheelbase (plus a little rounding).
		var rt_max_yaw: float = rt_sp * tan(VehicleModel.steer_limit(rt_cfg, rt_sp)) / VehicleModel.wheelbase_of(rt_cfg)
		if rt_sp > 0.5:
			rt_worst_ratio = maxf(rt_worst_ratio, rt_yaw / maxf(0.001, rt_max_yaw))
		if rt_t > 3.0 and rt_ap.active and rt_sp < 0.02:
			rt_slow += rt_yaw / 60.0
		rt_t += 1.0 / 60.0
	_check(rt_ap.finished and _count_state(rt_s, "ploughed") == 64, "steered autopilot ploughs the whole field")
	_check(rt_slow < 0.02, "autopilot never turns on the spot (%.3f rad while standing)" % rt_slow)
	_check(rt_worst_ratio < 1.05, "autopilot never turns faster than the steering allows (%.2f of the limit)" % rt_worst_ratio)
	# RECOVERY BASELINE (update 8): the update 4 autopilot is back, forward-only turns. Reverse-turn and headland
	# checks are suspended until reverse turns are rebuilt and proven in the real game.
	var tn_t = _turn_run("tractor", "plough", "farm")
	_check(tn_t["finished"], "tractor finishes the field (recovery baseline)")
	var tn_c = _turn_run("combine_small", "none", "farm")
	_check(tn_c["finished"], "combine finishes the field (recovery baseline)")

	# Turn paths (dubins.gd): exact end pose, and a lane-to-lane turn only 1.5 apart is possible
	var dub_rng := RandomNumberGenerator.new()
	dub_rng.seed = 11
	var dub_worst := 0.0
	for dub_i in 200:
		var dub_q := [dub_rng.randf_range(-10, 10), dub_rng.randf_range(-10, 10), dub_rng.randf_range(0, TAU),
			dub_rng.randf_range(-10, 10), dub_rng.randf_range(-10, 10), dub_rng.randf_range(0, TAU)]
		var dub_rho := dub_rng.randf_range(1.5, 6.0)
		var dub_p: Dictionary = Dubins.shortest(dub_q[0], dub_q[1], dub_q[2], dub_q[3], dub_q[4], dub_q[5], dub_rho)
		var dub_s: Dictionary = Dubins.sample(dub_q[0], dub_q[1], dub_q[2], dub_rho, dub_p, 0.05)
		var dub_e: Vector2 = dub_s["pts"][dub_s["pts"].size() - 1]
		dub_worst = maxf(dub_worst, dub_e.distance_to(Vector2(dub_q[3], dub_q[4])))
		dub_worst = maxf(dub_worst, absf(wrapf(float(dub_s["th"][dub_s["th"].size() - 1]) - dub_q[5], -PI, PI)))
	_check(dub_worst < 0.001, "turn paths end exactly on the target pose (%.6f)" % dub_worst)
	_check(not Dubins.shortest(0, 0, 0.0, 0, 1.5, PI, 2.5).is_empty(), "a turn between lanes 1.5 apart exists")

	# --- Autopilot: only goes where work is needed ---
	var jt = GameState.new()
	for jr in 8:
		for jc in 8:
			jt.plough(jr * 8 + jc)
	jt.tiles[3 * 8 + 2]["state"] = "unploughed"
	jt.tiles[3 * 8 + 4]["state"] = "unploughed"
	jt.tiles[6 * 8 + 3]["state"] = "unploughed"
	var jobs_t: Array = jt.jobs_for("plough", t0)
	_check(jobs_t.size() == 2, "jobs_for lists only rows with work")
	_check(jobs_t[0]["row"] == 3 and jobs_t[0]["c0"] == 2 and jobs_t[0]["c1"] == 4, "job covers only the columns that need work")
	_check(jt.count_work("plough", t0) == 3, "count_work counts workable tiles")
	res = _auto_job(jt, "plough", t0)
	_check(res["finished"] and _count_state(jt, "unploughed") == 0, "autopilot ploughs just those tiles")
	_check(res["time"] < 40.0, "partial job is quick (" + str(res["time"]) + " s)")

	# Resume: stops when fuel runs out, then carries on with what is left
	var lowf = GameState.new()
	res = _auto_job(lowf, "plough", t0, 1.5)
	var done_before := _count_state(lowf, "ploughed")
	_check(not res["finished"] and res["message"] == "Out of fuel", "autopilot stops when fuel runs out")
	_check(done_before > 0 and done_before < 64, "some tiles done before fuel ran out (" + str(done_before) + ")")
	res = _auto_job(lowf, "plough", t0)
	_check(res["finished"] and _count_state(lowf, "ploughed") == 64, "second run finishes the rest")
	_check(res["time"] < 110.0, "second run only does what is left (" + str(res["time"]) + " s)")

	# Starting where the last job ended
	var endr = GameState.new()
	for er in 8:
		for ec in 8:
			endr.plough(er * 8 + ec)
	for ec2 in 8:
		endr.tiles[7 * 8 + ec2]["state"] = "unploughed"
	endr.tractor["x"] = 7.8
	endr.tractor["z"] = 1.25
	endr.tractor["heading"] = PI / 2.0
	res = _auto_job(endr, "plough", t0)
	_check(res["finished"] and res["time"] < 20.0, "nearby row is done quickly (" + str(res["time"]) + " s)")
	var far = GameState.new()
	for fr in 8:
		for fc in 8:
			far.plough(fr * 8 + fc)
	for fc2 in 8:
		far.tiles[0 * 8 + fc2]["state"] = "unploughed"
	far.tractor["x"] = 7.8
	far.tractor["z"] = 1.25
	far.tractor["heading"] = PI / 2.0
	res = _auto_job(far, "plough", t0)
	_check(res["finished"] and res["time"] < 20.0, "distant row does not re-drive finished rows (" + str(res["time"]) + " s)")

	# Fuel estimate
	var est_state = GameState.new()
	var est_ap = AutoPilotScript.new()
	est_ap.start(est_state.tractor, est_state.jobs_for("plough", t0), float(cfg["work_offset"]))
	var est: float = est_ap.estimate_fuel(est_state.tractor, cfg)
	_check(est > 1.5 and est < 20.0, "fuel estimate for a full field is realistic (" + str(est) + ")")

	# --- Settings ---
	var sp := "user://test_settings.json"
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)
	_check(SettingsScript.load_settings(sp)["quality"] == 0, "missing settings file gives defaults")
	_check(SettingsScript.save_settings({"quality": 2, "debug": false}, sp), "settings save")
	var sl: Dictionary = SettingsScript.load_settings(sp)
	_check(sl["quality"] == 2 and sl["debug"] == false, "settings round trip")
	var sbad: Dictionary = SettingsScript.sanitize({"quality": 9, "debug": "yes"})
	_check(sbad["quality"] == 0 and sbad["debug"] == true, "bad settings fall back to defaults")
	var snull: Dictionary = SettingsScript.sanitize(null)
	_check(snull["quality"] == 0 and snull["debug"] == true, "null settings give defaults")
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)

	# --- Money safety net ---
	var rl = GameState.new()
	rl.money = 5
	_check(rl.relief_grant() == 100 and rl.money == 105, "broke player gets a farm grant")
	_check(rl.relief_grant() == 0, "no second grant once there is money")
	var rl2 = GameState.new()
	rl2.money = 5
	rl2.inventory["maize"] = 4
	_check(rl2.relief_grant() == 0, "no grant while there is stock to sell")
	var rl3 = GameState.new()
	rl3.plough(0)
	rl3.plant(0, "beans", t0)
	rl3.money = 0
	_check(rl3.relief_grant() == 0, "no grant while a crop is growing")
	var rl4 = GameState.new()
	rl4.money = 12
	_check(rl4.relief_grant() == 0, "enough money for the cheapest seed means no grant")

	# --- Stubble ---
	var sb = GameState.new()
	sb.plough(0)
	sb.plant(0, "beans", t0)
	_check(sb.harvest(0, t0 + 30.0) == "", "harvest beans for the stubble test")
	_check(sb.tiles[0]["state"] == "stubble", "harvest leaves stubble")
	_check(sb.plant(0, "beans", t0 + 40.0) == "Plough the tile first", "cannot plant on stubble")
	_check(sb.apply_implement("seeder", 0, "beans", t0) == "skip", "seeder skips stubble")
	_check(sb.can_work("plough", 0, t0), "stubble needs ploughing")
	_check(sb.plough(0) == "" and sb.tiles[0]["state"] == "ploughed", "stubble can be ploughed again")
	sb.tiles[1]["state"] = "stubble"
	var sbd: Dictionary = sb.to_dict()
	var sb2 = GameState.new()
	_check(sb2.from_dict(sbd) == "" and sb2.tiles[1]["state"] == "stubble", "stubble survives save and load")

	# --- Mesh builder, tiles, crops, scenery: finite, bounded and within triangle budgets ---
	_check(CropModels.stage_for(0.0) == 0 and CropModels.stage_for(0.3) == 1 and CropModels.stage_for(0.5) == 2 and CropModels.stage_for(0.8) == 3 and CropModels.stage_for(0.99) == 3 and CropModels.stage_for(1.0) == 4, "crop stages by progress")

	# --- Crop stages come from crop_data.gd and agree with the 3D models ---
	for cs_id in CropData.CROPS:
		var cs_list: Array = CropStages.stages_for(cs_id)
		var cs_ok: bool = cs_list.size() == CropModels.STAGE_COUNT and absf(float(cs_list[0]["from"])) < 0.0001
		cs_ok = cs_ok and absf(float(cs_list[cs_list.size() - 1]["from"]) - 1.0) < 0.0001
		for cs_i in range(1, cs_list.size()):
			if float(cs_list[cs_i]["from"]) <= float(cs_list[cs_i - 1]["from"]):
				cs_ok = false
		_check(cs_ok, "crop %s has %d ordered stages from 0.0 to 1.0" % [cs_id, CropModels.STAGE_COUNT])
		var cs_agree := true
		for cs_p in 101:
			var cs_prog := float(cs_p) / 100.0
			if CropStages.get_stage_index(cs_id, cs_prog) != CropModels.stage_for(cs_prog):
				cs_agree = false
		_check(cs_agree, "crop %s stages match the 3D models" % cs_id)
	_check(CropStages.get_stage_index("maize", 0.19) == 0, "maize stage at 19%")
	_check(CropStages.get_stage_index("maize", 0.2) == 1, "maize stage at 20%")
	_check(CropStages.get_stage_index("maize", 0.99) == 3, "maize stage at 99%")
	_check(CropStages.get_stage_index("maize", 1.0) == 4, "maize stage at 100%")
	_check(CropStages.get_stage_name("beans", 0.5) == "growing", "beans stage name")
	_check(CropStages.get_stage_index("other", 1.0) == 4, "unknown crop uses defaults")
	_check(CropStages.get_stage_name("other", 0.0) == "sprout", "unknown crop stage name")

	# --- Graphics quality profiles (sun shadows, sky) ---
	var ev_p0: Dictionary = EnvironmentSetup.profile(0)
	var ev_p1: Dictionary = EnvironmentSetup.profile(1)
	var ev_p2: Dictionary = EnvironmentSetup.profile(2)
	_check(EnvironmentSetup.PROFILES.size() == 3, "3 graphics quality profiles")
	_check(ev_p0["name"] == "Low" and ev_p1["name"] == "Medium", "quality profile names")
	_check(ev_p2["name"] == "High", "high quality profile name")
	_check(not ev_p0["shadows"] and not ev_p0["sky"], "Low has no sun shadows and a flat sky")
	_check(ev_p1["shadows"] and ev_p2["shadows"], "Medium and High have sun shadows")
	_check(float(ev_p2["shadow_distance"]) > float(ev_p1["shadow_distance"]), "High shadow distance")
	_check(int(ev_p2["atlas"]) > int(ev_p1["atlas"]), "High shadow atlas is bigger")
	_check(EnvironmentSetup.profile(-5)["name"] == "Low", "quality below 0 gives Low")
	_check(EnvironmentSetup.profile(99)["name"] == "High", "quality above 2 gives High")

	# --- Ground detail textures (soil, grass) ---
	for tx_path in ["res://assets/textures/soil.png", "res://assets/textures/grass.png"]:
		_check(ResourceLoader.exists(tx_path), "texture file imported: %s" % tx_path)
		var tx_mat: StandardMaterial3D = MeshBuilder.textured_material(tx_path, 0.5, 1.2)
		var tx_ok: bool = tx_mat.albedo_texture != null
		_check(tx_ok, "texture material loads: %s" % tx_path)
		if tx_ok:
			_check(tx_mat.albedo_texture.get_width() <= 1024, "texture size within budget: %s" % tx_path)
	_check(MeshBuilder.textured_material("res://nope.png", 1.0, 1.0).albedo_texture == null,
		"missing texture falls back to plain colours")

	# --- Machinery catalogue: every entry is complete and sensible ---
	var cat_i_keys := ["id", "name", "type", "price", "work_width", "weight", "model_path", "paint"]
	for cat_id in ImplementData.ITEMS:
		var cat_it: Dictionary = ImplementData.ITEMS[cat_id]
		var cat_ok := true
		for cat_k in cat_i_keys:
			if not cat_it.has(cat_k):
				cat_ok = false
		_check(cat_ok, "implement %s has all fields" % cat_id)
		if not cat_ok:
			continue
		var cat_w: int = int(cat_it["work_width"])
		cat_ok = cat_it["id"] == cat_id and ImplementData.TYPES.has(cat_it["type"])
		cat_ok = cat_ok and cat_w >= 1 and cat_w % 2 == 1 and int(cat_it["price"]) > 0
		cat_ok = cat_ok and float(cat_it["weight"]) > 0.0 and str(cat_it["name"]) != ""
		_check(cat_ok, "implement %s values are valid" % cat_id)
		var cat_mp: String = str(cat_it["model_path"])
		_check(cat_mp == "" or cat_mp.begins_with("res://"), "implement %s model path" % cat_id)
	for cat_t in ImplementData.TYPES:
		var cat_ids: Array = ImplementData.ids_of_type(cat_t)
		_check(cat_ids.size() >= 1, "implement type %s has an entry" % cat_t)
		var cat_inc := true
		for cat_n in range(1, cat_ids.size()):
			var cat_p: Dictionary = ImplementData.ITEMS[cat_ids[cat_n - 1]]
			var cat_q: Dictionary = ImplementData.ITEMS[cat_ids[cat_n]]
			var cat_wider: bool = int(cat_q["work_width"]) > int(cat_p["work_width"])
			var cat_heavier: bool = float(cat_q["weight"]) > float(cat_p["weight"])
			if not (cat_wider and cat_heavier):
				cat_inc = false
		_check(cat_inc, "%s: wider means pricier and heavier" % cat_t)
	for cat_s in ImplementData.ids_of_type("fertilizer"):
		_check(int(ImplementData.ITEMS[cat_s].get("fert_per_tile", 0)) >= 1, "%s uses fertilizer" % cat_s)
	for cat_l in VehicleData.IMPLEMENT_ORDER:
		if cat_l != "none":
			_check(ImplementData.ITEMS.has(cat_l), "tool %s exists in the catalogue" % cat_l)
	for cat_old in ["plough", "seeder"]:
		_check(int(ImplementData.get_item(cat_old).get("work_width", 0)) == 1, "tool %s is 1 tile wide" % cat_old)
	_check(ImplementData.get_item("nope").is_empty(), "unknown implement gives empty entry")
	var cat_v_keys := ["id", "name", "type", "price", "power_hp", "max_speed", "reverse_factor", "accel",
		"turn_rate", "fuel_capacity", "fuel_use", "fuel_price", "work_offset", "model_path", "paint"]
	for cat_vid in VehicleData.VEHICLES:
		var cat_v: Dictionary = VehicleData.VEHICLES[cat_vid]
		var cat_vok := true
		for cat_vk in cat_v_keys:
			if not cat_v.has(cat_vk):
				cat_vok = false
		_check(cat_vok, "vehicle %s has all fields" % cat_vid)
		if not cat_vok:
			continue
		cat_vok = cat_v["id"] == cat_vid and VehicleData.VEHICLE_TYPES.has(cat_v["type"])
		cat_vok = cat_vok and int(cat_v["price"]) >= 0 and int(cat_v["power_hp"]) > 0
		cat_vok = cat_vok and float(cat_v["max_speed"]) > 0.0 and float(cat_v["fuel_capacity"]) > 0.0
		cat_vok = cat_vok and float(cat_v["accel"]) > 0.0 and float(cat_v["turn_rate"]) > 0.0
		_check(cat_vok, "vehicle %s values are valid" % cat_vid)
		if cat_v["type"] == "harvester":
			var cat_hw: int = int(cat_v.get("work_width", 0))
			_check(cat_hw >= 1 and cat_hw % 2 == 1, "combine %s has an odd work width" % cat_vid)
	for cat_vt in VehicleData.VEHICLE_TYPES:
		var cat_vids: Array = VehicleData.ids_of_type(cat_vt)
		_check(cat_vids.size() >= 2, "vehicle type %s has a small and a large entry" % cat_vt)
		var cat_vinc := true
		for cat_vn in range(1, cat_vids.size()):
			var cat_hp_now: int = int(VehicleData.VEHICLES[cat_vids[cat_vn]]["power_hp"])
			var cat_hp_prev: int = int(VehicleData.VEHICLES[cat_vids[cat_vn - 1]]["power_hp"])
			if cat_hp_now <= cat_hp_prev:
				cat_vinc = false
		_check(cat_vinc, "%s: pricier means more power" % cat_vt)
	_check(VehicleData.VEHICLES.has(VehicleData.DEFAULT_VEHICLE), "default vehicle exists")
	var cat_dt: Dictionary = VehicleData.get_vehicle("tractor")
	var cat_same: bool = float(cat_dt["max_speed"]) == 9.0 and float(cat_dt["fuel_capacity"]) == 20.0
	cat_same = cat_same and float(cat_dt["work_offset"]) == 1.8
	_check(cat_same, "default tractor numbers unchanged")
	_check(VehicleData.get_vehicle("nope").is_empty(), "unknown vehicle gives empty entry")

	# --- Power versus weight (arcade drag) ---
	var dr_cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	var dr_none: Dictionary = VehicleModel.loaded_config(dr_cfg, "none")
	_check(float(dr_none["max_speed"]) == float(dr_cfg["max_speed"]), "no tool: full top speed")
	for dr_t in ["plough", "seeder"]:
		var dr_l: Dictionary = VehicleModel.loaded_config(dr_cfg, dr_t)
		var dr_same: bool = float(dr_l["max_speed"]) == float(dr_cfg["max_speed"])
		dr_same = dr_same and float(dr_l["accel"]) == float(dr_cfg["accel"])
		dr_same = dr_same and float(dr_l["fuel_use"]) == float(dr_cfg["fuel_use"])
		_check(dr_same, "1-tile %s does not slow the farm tractor" % dr_t)
	var dr_heavy: Dictionary = VehicleModel.loaded_config(dr_cfg, "plough_5")
	var dr_top: float = float(dr_cfg["max_speed"])
	_check(float(dr_heavy["max_speed"]) < dr_top * 0.5, "5-wide plough slows the farm tractor a lot")
	_check(float(dr_heavy["max_speed"]) >= dr_top * VehicleModel.MIN_SPEED_FACTOR - 0.0001, "slowdown has a floor")
	_check(float(dr_heavy["fuel_use"]) > float(dr_cfg["fuel_use"]), "heavy load burns more fuel")
	_check(float(dr_heavy["accel"]) < float(dr_cfg["accel"]), "heavy load accelerates slower")
	var dr_light: Dictionary = VehicleData.VEHICLES["tractor"].duplicate()
	dr_light["power_hp"] = 20
	var dr_weak: Dictionary = VehicleModel.loaded_config(dr_light, "plough_5")
	var dr_floor: float = float(dr_light["max_speed"]) * VehicleModel.MIN_SPEED_FACTOR
	_check(absf(float(dr_weak["max_speed"]) - dr_floor) < 0.0001, "weak tractor crawls with the heaviest plough")
	var dr_big: Dictionary = VehicleData.VEHICLES["tractor_heavy"]
	var dr_strong: Dictionary = VehicleModel.loaded_config(dr_big, "plough_5")
	_check(float(dr_strong["max_speed"]) > float(dr_big["max_speed"]) * 0.9, "heavy tractor pulls the heaviest plough")
	var dr_ids: Array = ImplementData.ITEMS.keys()
	dr_ids.sort_custom(func(a, b): return ImplementData.weight_of(a) < ImplementData.weight_of(b))
	for dr_vid in VehicleData.VEHICLES:
		var dr_prev := 999.0
		var dr_mono := true
		for dr_id in dr_ids:
			var dr_lc: Dictionary = VehicleModel.loaded_config(VehicleData.VEHICLES[dr_vid], dr_id)
			var dr_sp: float = float(dr_lc["max_speed"])
			if dr_sp > dr_prev + 0.0001:
				dr_mono = false
			dr_prev = dr_sp
		_check(dr_mono, "%s: a heavier implement never goes faster" % dr_vid)
	var dr_v := GameState.default_tractor()
	_run(dr_v, dr_heavy, 1.0, 0.0, 600)
	_check(absf(float(dr_v["speed"]) - float(dr_heavy["max_speed"])) < 0.01, "loaded tractor settles at reduced speed")
	# Tool raised: free speed and fuel use, tool down: loaded speed and fuel use
	var up_v := GameState.default_tractor()
	var dn_v := GameState.default_tractor()
	for uv in [up_v, dn_v]:
		uv["x"] = 100.0
		uv["z"] = -100.0
		uv["fuel"] = 50.0
	up_v["_working"] = false
	dn_v["_working"] = true
	for ui in 900:
		VehicleModel.step(up_v, dr_heavy, 1.0, 0.0, 1.0 / 60.0)
		VehicleModel.step(dn_v, dr_heavy, 1.0, 0.0, 1.0 / 60.0)
	_check(absf(float(up_v["speed"]) - float(dr_cfg["max_speed"])) < 0.01, "tool raised: drives at full free speed")
	_check(absf(float(dn_v["speed"]) - float(dr_heavy["max_speed"])) < 0.01, "tool down: slowed by the load")
	_check(50.0 - float(up_v["fuel"]) < (50.0 - float(dn_v["fuel"])) * 3.0 and float(up_v["fuel"]) < 50.0, "fuel is still used with the tool raised")
	_check(VehicleModel.total_mass(dr_heavy) > float(dr_cfg["mass_kg"]), "a raised tool still adds weight")
	_check(ImplementData.type_of("plough_3") == "plough" and ImplementData.type_of("none") == "none", "id maps to type")
	_check(ImplementData.type_of("bogus") == "none", "unknown id has no type")
	_check(ImplementData.name_of("seeder_3") == "Wide Seeder" and ImplementData.name_of("none") == "None", "names")
	_check(ImplementData.width_of("seeder_5") == 5 and ImplementData.width_of("none") == 1, "widths")
	_check(ImplementData.weight_of("none") == 0.0 and ImplementData.weight_of("plough_5") == 1800.0, "weights")
	var dr_save = GameState.new()
	dr_save.owned.append("seeder_3")
	dr_save.tractor["implement"] = "seeder_3"
	var dr_back = GameState.new()
	var dr_json = JSON.parse_string(JSON.stringify(dr_save.to_dict()))
	_check(dr_back.from_dict(dr_json) == "" and dr_back.tractor["implement"] == "seeder_3", "wide tool survives save and load")
	var dr_work = GameState.new()
	var dr_tile := -1
	var dr_px := 0.0
	var dr_pz := 0.0
	for dr_gx in range(-40, 41):
		for dr_gz in range(-90, -9):
			if dr_tile < 0 and FarmLayout.world_to_tile(dr_gx * 0.25, dr_gz * 0.25) == 0:
				dr_tile = 0
				dr_px = dr_gx * 0.25
				dr_pz = dr_gz * 0.25
	_check(dr_tile == 0, "found a point on tile 0")
	dr_work.tractor["implement"] = "plough_3"
	dr_work.tractor["heading"] = 0.0
	dr_work.tractor["speed"] = 1.0
	dr_work.tractor["x"] = dr_px
	dr_work.tractor["z"] = dr_pz + float(dr_cfg["work_offset"])
	_check(dr_work.work_with_tractor(dr_cfg, 0.0, "maize") == "", "wide plough works a tile")
	_check(dr_work.tiles[0]["state"] == "ploughed", "wide plough ploughs the tile")

	# --- Wide work and fertilizer ---
	_check(GameState.SCHEMA_VERSION == 6, "save format is version 6")
	var fw_cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	var fw_sum := {}
	var fw_cnt := {}
	for fw_gx in range(-48, 49):
		for fw_gz in range(-72, 1):
			var fw_i: int = FarmLayout.world_to_tile(fw_gx * 0.25, fw_gz * 0.25)
			if fw_i >= 0:
				fw_sum[fw_i] = fw_sum.get(fw_i, Vector2.ZERO) + Vector2(fw_gx * 0.25, fw_gz * 0.25)
				fw_cnt[fw_i] = int(fw_cnt.get(fw_i, 0)) + 1
	_check(fw_cnt.size() == 64, "all 64 tiles found on the ground")
	var fw_c27: Vector2 = fw_sum[27] / float(fw_cnt[27])
	var fw_c0: Vector2 = fw_sum[0] / float(fw_cnt[0])
	_check(FarmLayout.world_to_tile(fw_c27.x + GameState.TILE_PITCH, fw_c27.y) == 28, "tile pitch matches the layout")
	var fw_s = GameState.new()
	_check(_wide_work(fw_s, fw_c27, "plough", fw_cfg, 0.0, "maize") == "", "1-wide plough works")
	_check(_states(fw_s, "ploughed") == [27], "1-wide plough works only one tile")
	fw_s = GameState.new()
	_check(_wide_work(fw_s, fw_c27, "plough_3", fw_cfg, 0.0, "maize") == "", "3-wide plough works")
	_check(_states(fw_s, "ploughed") == [26, 27, 28], "3-wide plough takes both neighbours")
	_check(fw_s.last_worked_tiles.size() == 3, "3-wide plough reports 3 tiles")
	fw_s = GameState.new()
	_wide_work(fw_s, fw_c27, "plough_5", fw_cfg, 0.0, "maize")
	_check(_states(fw_s, "ploughed") == [25, 26, 27, 28, 29], "5-wide plough takes 5 tiles")
	fw_s = GameState.new()
	_wide_work(fw_s, fw_c0, "plough_3", fw_cfg, 0.0, "maize")
	_check(_states(fw_s, "ploughed") == [0, 1], "wide plough stops at the field edge")
	fw_s = GameState.new()
	for fw_t in [26, 27, 28]:
		fw_s.tiles[fw_t]["state"] = "ploughed"
	_check(_wide_work(fw_s, fw_c27, "seeder_3", fw_cfg, 0.0, "maize") == "", "wide seeder works")
	_check(_states(fw_s, "growing") == [26, 27, 28] and fw_s.money == 440, "wide seeder pays 3 seeds")
	fw_s = GameState.new()
	for fw_t in [26, 27, 28]:
		fw_s.tiles[fw_t]["state"] = "ploughed"
	fw_s.money = 30
	_check(_wide_work(fw_s, fw_c27, "seeder_3", fw_cfg, 0.0, "maize") == "", "partly paid wide pass still works")
	_check(_states(fw_s, "growing") == [27] and fw_s.money == 10, "wide seeder plants what money allows")
	_check(fw_s.last_work_error == "Not enough money", "wide seeder says money ran out")
	fw_s = GameState.new()
	for fw_t in [26, 27, 28]:
		fw_s.tiles[fw_t]["state"] = "ploughed"
	fw_s.money = 5
	_check(_wide_work(fw_s, fw_c27, "seeder_3", fw_cfg, 0.0, "maize") == "Not enough money", "no money plants nothing")
	_check(_states(fw_s, "growing").is_empty(), "no seeds without money")
	fw_s = GameState.new()
	for fw_t in [26, 27, 28]:
		fw_s.tiles[fw_t]["state"] = "growing"
		fw_s.tiles[fw_t]["crop"] = "maize"
		fw_s.tiles[fw_t]["planted_at"] = 0.0
	# Fertilizer rules
	var fe = GameState.new()
	fe.tiles[5]["state"] = "ploughed"
	fe.fertilizer = 2
	_check(fe.fertilize(5, 0.0) == "" and fe.tiles[5]["fertilized"], "fertilize a ploughed tile")
	_check(fe.fertilizer == 1, "fertilizing uses stock first")
	_check(fe.fertilize(5, 0.0) == "skip", "a fertilized tile is skipped")
	fe.tiles[6]["state"] = "ploughed"
	fe.fertilizer = 0
	_check(fe.fertilize(6, 0.0) == "" and fe.money == 495, "missing fertilizer is bought at 5")
	fe.tiles[7]["state"] = "ploughed"
	fe.money = 3
	_check(fe.fertilize(7, 0.0) == "Not enough money" and not fe.tiles[7]["fertilized"], "cannot afford fertilizer")
	_check(fe.fertilize(8, 0.0) == "skip", "unploughed ground is skipped")
	fe.tiles[9]["state"] = "stubble"
	_check(fe.fertilize(9, 0.0) == "skip", "stubble is skipped")
	_check(fe.fertilize(-1, 0.0) == "Select a tile first", "bad tile index")
	fe.money = 500
	fe.tiles[10]["state"] = "ploughed"
	fe.plant(10, "maize", 0.0)
	_check(fe.fertilize(10, 5.0) == "" and fe.tiles[10]["fertilized"], "fertilize a growing crop")
	fe.tiles[11]["state"] = "ploughed"
	fe.plant(11, "maize", 0.0)
	_check(fe.fertilize(11, 1000.0) == "skip" and not fe.tiles[11]["fertilized"], "a ripe crop is not fertilized")
	var fz2 = GameState.new()
	fz2.tiles[0]["state"] = "ploughed"
	fz2.tiles[1]["state"] = "ploughed"
	fz2.fertilize(1, 0.0)
	fz2.plant(0, "maize", 0.0)
	fz2.plant(1, "maize", 0.0)
	fz2.harvest(0, 100.0)
	fz2.harvest(1, 100.0)
	_check(int(fz2.inventory.get("maize", 0)) == 10, "fertilized maize gives 6 and plain gives 4")
	_check(not fz2.tiles[1]["fertilized"] and fz2.tiles[1]["state"] == "stubble", "harvest clears fertilizer")
	fw_s = GameState.new()
	for fw_t in [26, 27, 28]:
		fw_s.tiles[fw_t]["state"] = "ploughed"
	fw_s.fertilizer = 3
	_check(_wide_work(fw_s, fw_c27, "spreader_3", fw_cfg, 0.0, "maize") == "", "wide spreader works")
	_check(fw_s.fertilizer == 0 and fw_s.tiles[26]["fertilized"] and fw_s.tiles[28]["fertilized"], "wide spreader uses 3 units")
	fw_s.fertilizer = 3
	_check(fw_s.inventory_text() == "Stock: Fertilizer 3", "fertilizer shows in stock text")
	_check(GameState.new().inventory_text() == "Stock: empty", "no fertilizer: stock text unchanged")
	var fz3 = GameState.new()
	fz3.fertilizer = 4
	fz3.inventory["maize"] = 2
	fz3.sell_all()
	_check(fz3.fertilizer == 4, "selling crops never sells fertilizer")
	_check(fz3.can_work("fertilizer", 0, 0.0) == false, "fertilizer cannot work unploughed ground")
	fz3.tiles[0]["state"] = "ploughed"
	_check(fz3.can_work("fertilizer", 0, 0.0), "fertilizer can work ploughed ground")
	# Saving: version 3, migration from version 2, and bad data
	var sv = GameState.new()
	sv.fertilizer = 7
	sv.tiles[5]["state"] = "ploughed"
	sv.tiles[5]["fertilized"] = true
	var sv_json = JSON.parse_string(JSON.stringify(sv.to_dict()))
	var sv_back = GameState.new()
	_check(sv_back.from_dict(sv_json) == "", "version 3 save loads")
	_check(sv_back.fertilizer == 7 and sv_back.tiles[5]["fertilized"], "fertilizer stock and tile flag survive")
	var sv2: Dictionary = sv.to_dict()
	sv2["schema_version"] = 2
	sv2.erase("fertilizer")
	for fw_t in sv2["tiles"]:
		fw_t.erase("fertilized")
	var sv_mig = GameState.new()
	_check(sv_mig.from_dict(sv2) == "", "version 2 save is accepted")
	_check(sv_mig.fertilizer == 0 and not sv_mig.tiles[5]["fertilized"], "version 2 save gets no fertilizer")
	var sv3: Dictionary = sv.to_dict()
	sv3["fertilizer"] = -1
	_check(GameState.new().from_dict(sv3) != "", "rejects negative fertilizer")
	sv3["fertilizer"] = "lots"
	_check(GameState.new().from_dict(sv3) != "", "rejects text fertilizer")
	sv3 = sv.to_dict()
	sv3["tiles"][0]["fertilized"] = "yes"
	_check(GameState.new().from_dict(sv3) != "", "rejects a bad fertilized flag")
	sv3 = sv.to_dict()
	sv3["tiles"][0]["fertilized"] = true
	var sv_clean = GameState.new()
	_check(sv_clean.from_dict(sv3) == "" and not sv_clean.tiles[0]["fertilized"], "flag on bare ground is dropped")

	# --- Autopilot lanes for wide implements ---
	var ln_rows: Array = []
	for ln_r in 8:
		ln_rows.append({"row": ln_r, "c0": 0, "c1": 7})
	_check(AutoPilotScript.plan_lanes(ln_rows, 1, 8).size() == 8, "1-wide: one lane per row")
	var ln_3: Array = AutoPilotScript.plan_lanes(ln_rows, 3, 8)
	_check(ln_3.size() == 3 and ln_3[0]["row"] == 1 and ln_3[1]["row"] == 4 and ln_3[2]["row"] == 7, "3-wide: 3 lanes on rows 1, 4, 7")
	var ln_5: Array = AutoPilotScript.plan_lanes(ln_rows, 5, 8)
	_check(ln_5.size() == 2 and ln_5[0]["row"] == 2 and ln_5[1]["row"] == 7, "5-wide: 2 lanes on rows 2, 7")
	var ln_sparse: Array = AutoPilotScript.plan_lanes([{"row": 1, "c0": 2, "c1": 3}, {"row": 6, "c0": 0, "c1": 1}], 3, 8)
	_check(ln_sparse.size() == 2 and ln_sparse[0]["row"] == 2 and ln_sparse[1]["row"] == 7, "far-apart rows get their own lanes")
	var ln_union: Array = AutoPilotScript.plan_lanes([{"row": 0, "c0": 2, "c1": 3}, {"row": 1, "c0": 5, "c1": 7}], 3, 8)
	_check(ln_union.size() == 1 and ln_union[0]["c0"] == 2 and ln_union[0]["c1"] == 7, "a lane runs over every column its rows need")
	var ln_edge: Array = AutoPilotScript.plan_lanes([{"row": 7, "c0": 0, "c1": 7}], 5, 8)
	_check(ln_edge.size() == 1 and ln_edge[0]["row"] == 7, "a lane stays inside the field")
	_check(AutoPilotScript.plan_lanes([], 3, 8).is_empty(), "no jobs gives no lanes")
	var ln_cover := true
	for ln_w in [3, 5]:
		var ln_h: int = (ln_w - 1) / 2
		for ln_mask in range(1, 256):
			var ln_j: Array = []
			for ln_r in 8:
				if ((ln_mask >> ln_r) & 1) == 1:
					ln_j.append({"row": ln_r, "c0": 0, "c1": 7})
			var ln_l: Array = AutoPilotScript.plan_lanes(ln_j, ln_w, 8)
			for ln_x in ln_j:
				var ln_hit := false
				for ln_y in ln_l:
					if absi(int(ln_y["row"]) - int(ln_x["row"])) <= ln_h:
						ln_hit = true
				if not ln_hit:
					ln_cover = false
	_check(ln_cover, "every row that needs work is inside a lane (all 255 row patterns)")
	# Whole-field runs with wide implements
	var ln_s1 = GameState.new()
	var ln_a1: Dictionary = _auto_wide(ln_s1, "plough", t0)
	_check(ln_a1["finished"] and _count_state(ln_s1, "ploughed") == 64, "1-wide autopilot ploughs the field")
	var ln_s3 = GameState.new()
	var ln_a3: Dictionary = _auto_wide(ln_s3, "plough_3", t0)
	_check(ln_a3["finished"] and _count_state(ln_s3, "ploughed") == 64, "3-wide autopilot ploughs the whole field")
	_check(ln_a3["lanes"] == 3, "3-wide autopilot drives 3 lanes")
	_check(float(ln_a3["length"]) < float(ln_a1["length"]) * 0.6, "3-wide route is much shorter")
	_check(float(ln_a3["fuel_used"]) < float(ln_a1["fuel_used"]) * 0.7, "3-wide autopilot burns much less fuel")
	var ln_s5 = GameState.new()
	var ln_a5: Dictionary = _auto_wide(ln_s5, "plough_5", t0)
	_check(ln_a5["finished"] and _count_state(ln_s5, "ploughed") == 64 and ln_a5["lanes"] == 2, "5-wide autopilot ploughs in 2 lanes")
	ln_s3.money = 5000
	var ln_sd: Dictionary = _auto_wide(ln_s3, "seeder_3", t0)
	_check(ln_sd["finished"] and _count_state(ln_s3, "growing") == 64, "3-wide seeder autopilot plants the field")
	var ln_sf: Dictionary = _auto_wide(ln_s5, "spreader_3", t0)
	_check(ln_sf["finished"], "spreader autopilot finishes")
	var ln_ok := true
	for ln_t in ln_s5.tiles:
		if not ln_t["fertilized"]:
			ln_ok = false
	_check(ln_ok, "spreader autopilot fertilizes every tile")

	# --- Machinery shop: owning, buying, using ---
	var sh_s = GameState.new()
	_check(sh_s.owned == ["tractor", "plough", "seeder", "combine_small"], "start owning the tractor, two tools and a free combine")
	_check(sh_s.can_buy("plough_3") == "Not enough money", "cannot afford the wide plough")
	_check(sh_s.buy("plough_3") == "Not enough money" and sh_s.money == 500, "failed buy keeps the money")
	sh_s.money = 2000
	_check(sh_s.buy("plough_3") == "" and sh_s.money == 500 and sh_s.owns("plough_3"), "buy the wide plough")
	_check(sh_s.buy("plough_3") == "Already owned" and sh_s.money == 500, "cannot buy a machine twice")
	_check(sh_s.buy("combine_large") == "Not enough money", "a combine needs the money like any machine")
	_check(sh_s.buy("bogus") == "Unknown machine", "unknown machine cannot be bought")
	sh_s.tractor["implement"] = "plough"
	sh_s.next_implement()
	_check(sh_s.tractor["implement"] == "plough_3", "a bought tool joins the tool cycle")
	_check(sh_s.equip_implement("seeder_5") == "Not owned" and sh_s.tractor["implement"] == "plough_3", "cannot use a tool you do not own")
	_check(sh_s.equip_implement("seeder") == "" and sh_s.tractor["implement"] == "seeder", "use an owned tool")
	_check(sh_s.equip_implement("none") == "" and sh_s.tractor["implement"] == "none", "use no tool")
	sh_s.money = 20000
	_check(sh_s.select_vehicle("tractor_heavy") == "Not owned", "cannot drive a tractor you do not own")
	_check(sh_s.buy("tractor_heavy") == "" and sh_s.money == 11000, "buy the heavy tractor")
	sh_s.tractor["fuel"] = 5.0
	_check(sh_s.select_vehicle("tractor_heavy") == "" and sh_s.tractor["vehicle"] == "tractor_heavy", "drive the heavy tractor")
	_check(int(sh_s.vehicle_cfg()["power_hp"]) == 160 and float(sh_s.tractor["fuel"]) == 40.0, "a bought machine starts with a full tank of its own")
	sh_s.tractor["fuel"] = 5.0
	sh_s.money = 500
	_check(sh_s.refuel() == "" and float(sh_s.tractor["fuel"]) == 40.0, "refuel fills the heavy tractor's bigger tank")
	sh_s.money = 30000
	_check(sh_s.buy("tractor_tracked") == "" and sh_s.select_vehicle("tractor_tracked") == "", "switch to the tracked tractor")
	_check(float(sh_s.tractor["fuel"]) == 70.0, "the tracked tractor starts with its full 70 tank")
	_check(sh_s.select_vehicle("tractor") == "" and float(sh_s.tractor["fuel"]) == 5.0, "the farm tractor keeps its own fuel")
	_check(sh_s.select_vehicle("tractor_tracked") == "", "back to the tracked tractor")
	_check(sh_s.select_vehicle("combine_large") == "Not owned", "cannot drive a combine you do not own")
	var sh_json = JSON.parse_string(JSON.stringify(sh_s.to_dict()))
	var sh_b = GameState.new()
	_check(sh_b.from_dict(sh_json) == "", "save with bought machines loads")
	_check(sh_b.owns("plough_3") and sh_b.owns("tractor_heavy") and sh_b.tractor["vehicle"] == "tractor_tracked", "owned machines and the chosen tractor survive")
	var sh_v3: Dictionary = GameState.new().to_dict()
	sh_v3["schema_version"] = 3
	sh_v3.erase("owned")
	sh_v3["tractor"].erase("vehicle")
	sh_v3["tractor"]["implement"] = "plough_3"
	var sh_m = GameState.new()
	_check(sh_m.from_dict(sh_v3) == "", "version 3 save is accepted")
	_check(sh_m.owns("plough_3") and sh_m.owns("tractor") and sh_m.tractor["vehicle"] == "tractor", "old save keeps its tool and gets the starter machines")
	var sh_bad: Dictionary = GameState.new().to_dict()
	sh_bad["owned"] = ["tractor", "ghost"]
	_check(GameState.new().from_dict(sh_bad) != "", "rejects an unknown owned machine")
	sh_bad = GameState.new().to_dict()
	sh_bad["owned"] = "everything"
	_check(GameState.new().from_dict(sh_bad) != "", "rejects a text owned list")
	sh_bad = GameState.new().to_dict()
	sh_bad["tractor"]["vehicle"] = "tractor_heavy"
	_check(GameState.new().from_dict(sh_bad) != "", "rejects a tractor that is not owned")
	sh_bad = GameState.new().to_dict()
	sh_bad["tractor"]["implement"] = "plough_5"
	_check(GameState.new().from_dict(sh_bad) != "", "rejects a tool that is not owned")
	sh_bad = GameState.new().to_dict()
	sh_bad["owned"].append("combine_small")
	sh_bad["tractor"]["vehicle"] = "combine_small"
	_check(GameState.new().from_dict(sh_bad) == "", "a combine can be the driven machine")
	sh_bad = GameState.new().to_dict()
	sh_bad["owned"].append("tractor_light")
	sh_bad["tractor"]["vehicle"] = "tractor_light"
	sh_bad["money"] = 100
	var sh_old = GameState.new()
	_check(sh_old.from_dict(sh_bad) == "", "a save with the removed compact tractor loads")
	_check(not sh_old.owns("tractor_light") and sh_old.tractor["vehicle"] == "tractor" and sh_old.money == 1900, "the compact tractor is refunded and the farm tractor takes over")
	# What the shop shows
	var sh_all := {}
	for sh_c in ShopCatalog.CATEGORIES:
		var sh_ids: Array = ShopCatalog.ids_in(sh_c["id"])
		_check(sh_ids.size() >= 1, "shop tab %s has machines" % sh_c["id"])
		for sh_id in sh_ids:
			sh_all[sh_id] = true
	_check(sh_all.size() == VehicleData.VEHICLES.size() + ImplementData.ITEMS.size(), "every machine is in a shop tab")
	var sh_gs = GameState.new()
	var sh_e: Dictionary = ShopCatalog.entry("plough", sh_gs)
	_check(sh_e["owned"] and not sh_e["in_use"] and sh_e["tag"] == "Owned", "owned machine entry")
	sh_gs.tractor["implement"] = "plough"
	_check(ShopCatalog.entry("plough", sh_gs)["tag"] == "In use", "machine in use entry")
	var sh_p: Dictionary = ShopCatalog.entry("seeder_3", sh_gs)
	_check(not sh_p["owned"] and sh_p["can_buy"] == "Not enough money" and sh_p["tag"] == "1700", "machine for sale entry")
	_check(sh_p["stats"].contains("3 tiles wide") and sh_p["stats"].contains(" hp") and sh_p["stats"].contains("top speed"), "implement stats text")
	_check(ShopCatalog.entry("tractor_heavy", sh_gs)["stats"].contains("160 hp"), "vehicle stats text")
	_check(ShopCatalog.entry("spreader", sh_gs)["stats"].contains("fertilizer per tile"), "spreader stats mention fertilizer")
	_check(ShopCatalog.entry("combine_large", sh_gs)["can_buy"] == "Not enough money", "combine entry can be bought")
	_check(not VehicleData.VEHICLES.has("tractor_light") and VehicleData.VEHICLES.has("tractor_tracked"), "tractor lineup: farm, heavy, tracked")
	_check(ShopCatalog.entry("bogus", sh_gs)["name"] == "", "unknown id gives an empty entry")
	# Preview models (the .glb files, or the built-in fallback)
	_check(MachineModels.glb_scene("") == null and MachineModels.glb_scene("res://nope.glb") == null, "missing model file gives no scene")
	_check(MachineModels.instance_for("bogus") == null, "unknown id has no preview")
	for sh_mid in ImplementData.ITEMS:
		var sh_n = MachineModels.instance_for(sh_mid)
		_check(sh_n != null and sh_n is Node3D, "%s has a preview model" % sh_mid)
		if sh_n != null:
			sh_n.free()
	for sh_vid in ["tractor", "tractor_heavy", "tractor_tracked"]:
		var sh_t = MachineModels.instance_for(sh_vid)
		_check(sh_t != null and sh_t is Node3D, "%s has a preview model" % sh_vid)
		if sh_t != null:
			sh_t.free()
	var sh_cb = MachineModels.instance_for("combine_small")
	var sh_has_file: bool = MachineModels.glb_scene(str(VehicleData.VEHICLES["combine_small"]["model_path"])) != null
	_check((sh_cb != null) == sh_has_file, "a combine preview needs its model file")
	if sh_cb != null:
		sh_cb.free()
	for sh_k in ImplementData.ITEMS:
		var sh_it: Dictionary = ImplementData.ITEMS[sh_k]
		var sh_path: String = str(sh_it["model_path"])
		_check(float(sh_it["model_scale"]) > 0.0 and int(sh_it["model_gang"]) >= 1, "%s model scale and gang" % sh_k)
		_check(sh_path == "" or (sh_path.begins_with("res://assets/models/") and sh_path.ends_with(".glb")), "%s model path" % sh_k)
	for sh_k in VehicleData.VEHICLES:
		var sh_vp: String = str(VehicleData.VEHICLES[sh_k]["model_path"])
		_check(float(VehicleData.VEHICLES[sh_k]["model_scale"]) > 0.0, "%s model scale" % sh_k)
		_check(sh_vp == "" or (sh_vp.begins_with("res://assets/models/") and sh_vp.ends_with(".glb")), "%s model path" % sh_k)
	# The shop screen itself (built in code, driven here without a window)
	var sh_ui = MachineryShop.new()
	var sh_g = GameState.new()
	sh_g.money = 2000
	sh_ui.open(sh_g)
	_check(sh_ui.list.item_count == ShopCatalog.ids_in("tractor").size(), "shop lists the tractors")
	sh_ui._on_category("plough")
	_check(sh_ui.list.item_count == 3 and sh_ui.selected == "plough", "shop switches category")
	sh_ui._on_item(1)
	_check(sh_ui.selected == "plough_3" and sh_ui.buy_button.visible and not sh_ui.buy_button.disabled, "wide plough can be bought")
	sh_ui._on_buy()
	_check(sh_g.owns("plough_3") and sh_g.money == 500, "shop buys the machine")
	_check(sh_ui.use_button.visible and not sh_ui.buy_button.visible, "after buying, the shop offers Use")
	sh_ui._on_use()
	_check(sh_g.tractor["implement"] == "plough_3", "shop puts the tool on the tractor")
	sh_ui.free()

	# --- S7: real models in the field ---
	var fv_n = MachineModels.instance_for("tractor")
	if fv_n != null:
		var fv_b: AABB = MachineModels.bounds_of(fv_n)
		_check(fv_b.size.x > 0.5 and fv_b.size.y > 0.5 and fv_b.size.z > 1.0, "tractor model box has a size")
		_check(fv_b.size.x < 4.0 and fv_b.size.z < 6.0, "tractor model box is game size")
		fv_n.free()
	var fv_empty := Node3D.new()
	_check(MachineModels.bounds_of(fv_empty).size.x > 0.0, "empty node gets a default box")
	fv_empty.free()
	var fv_tv = TractorViewScript.new()
	var fv_tr: Dictionary = {"x": 1.0, "z": 2.0, "heading": 0.5, "speed": 1.0, "implement": "plough_3", "vehicle": "tractor"}
	fv_tv.update_from(fv_tr, 0.1)
	fv_tv.update_from(fv_tr, 0.1)
	var fv_has_tractor: bool = MachineModels.glb_scene(str(VehicleData.VEHICLES["tractor"]["model_path"])) != null
	_check((fv_tv.glb_vehicle != null) == fv_has_tractor, "field tractor uses the real model when its file loads")
	_check(fv_tv.cur_vehicle == "tractor", "field view remembers the vehicle")
	if fv_tv.glb_vehicle != null:
		_check(fv_tv.body_mi == null or not fv_tv.body_mi.visible, "built-in body is not shown while the real tractor shows")
	else:
		_check(fv_tv.body_mi != null and fv_tv.body_mi.visible, "built-in tractor stands in when the model file is missing")
	_check(fv_tv.wheels.size() == 4, "field tractor has four wheels to spin")
	var fv_has_impl: bool = MachineModels.glb_scene(str(ImplementData.ITEMS["plough_3"]["model_path"])) != null
	_check(fv_tv.glb_impl.has("plough_3") == fv_has_impl, "field implement uses the real model when its file loads")
	if fv_tv.glb_impl.has("plough_3"):
		_check(fv_tv.glb_impl["plough_3"].visible, "equipped real implement is visible")
	fv_tr["implement"] = "none"
	fv_tr["vehicle"] = "tractor_heavy"
	fv_tv.update_from(fv_tr, 0.1)
	_check(fv_tv.cur_vehicle == "tractor_heavy", "field view switches tractor")
	_check(not fv_tv.glb_impl.has("plough_3") or not fv_tv.glb_impl["plough_3"].visible, "unequipped implement is hidden")
	fv_tr["vehicle"] = "bogus"
	fv_tv.update_from(fv_tr, 0.1)
	_check(fv_tv.glb_vehicle == null and fv_tv.body_mi.visible, "unknown vehicle falls back to the built-in tractor")
	fv_tv.free()

	# --- Lift, tracks, combines and the yard ---
	var lf_tv = TractorViewScript.new()
	var lf_tr: Dictionary = {"x": 0.0, "z": 0.0, "heading": 0.0, "speed": 0.0, "implement": "plough", "vehicle": "tractor"}
	lf_tv.update_from(lf_tr, 0.05)
	_check(not lf_tv.is_down() and lf_tv.lift == 1.0, "the tool starts raised")
	lf_tv.set_raised(false)
	for lf_i in 20:
		lf_tv.update_from(lf_tr, 0.05)
	_check(lf_tv.is_down() and lf_tv.lift == 0.0, "the tool comes down in about half a second")
	var lf_low_y: float = lf_tv.attach.position.y
	lf_tv.set_raised(true)
	lf_tv.update_from(lf_tr, 0.1)
	_check(lf_tv.attach.position.y > lf_low_y and not lf_tv.is_down(), "raising lifts the tool off the ground")
	lf_tr["vehicle"] = "tractor_tracked"
	lf_tv.update_from(lf_tr, 0.1)
	var lf_has_tracks: bool = MachineModels.glb_scene(str(VehicleData.VEHICLES["tractor_tracked"]["model_path"])) != null
	_check(lf_tv.cur_vehicle == "tractor_tracked", "field view takes the tracked tractor")
	_check(lf_tv.wheels.is_empty() == lf_has_tracks, "track pods do not spin like wheels")
	_check(lf_tv.track_spin.is_empty() != lf_has_tracks or not lf_has_tracks, "the tracked tractor has parts to spin")
	if lf_has_tracks:
		lf_tr["speed"] = 2.0
		var lf_ring: int = lf_tv.track_vi
		var lf_rot0: float = lf_tv.track_spin[0]["angle"]
		for lf_k in 30:
			lf_tv.update_from(lf_tr, 0.05)
		_check(lf_tv.track_vi != lf_ring or float(lf_tv.track_spin[0]["angle"]) != lf_rot0, "the tracks move when the tractor drives")
		var lf_shown := 0
		for lf_ringset in lf_tv.track_cleats:
			for lf_node in lf_ringset:
				if lf_node.visible:
					lf_shown += 1
		_check(lf_shown == lf_tv.track_cleats.size(), "one cleat ring shows on each track")
		lf_tr["speed"] = 0.0
	lf_tr["vehicle"] = "combine_small"
	lf_tr["implement"] = "plough_3"
	lf_tv.update_from(lf_tr, 0.1)
	var lf_has_comb: bool = MachineModels.glb_scene(str(VehicleData.VEHICLES["combine_small"]["model_path"])) != null
	_check(lf_tv.is_combine == lf_has_comb and lf_tv.rear_steer == lf_has_comb, "the combine view steers with its rear wheels")
	_check(not lf_tv.glb_impl.has("plough_3") or not lf_tv.glb_impl["plough_3"].visible, "a combine shows no tractor tool")
	lf_tv.free()

	var cb_s = GameState.new()
	cb_s.money = 50000
	_check(cb_s.owns("combine_small") and cb_s.select_vehicle("combine_small") == "", "the free combine can be driven at once")
	_check(cb_s.is_combine() and cb_s.active_kind() == "harvester" and cb_s.active_implement() == "none", "a combine works with its own header")
	_check(cb_s.active_width() == 3, "the small combine cuts three tiles")
	# A ripe field: the header cuts ahead of the combine, three tiles across.
	for cb_i in cb_s.tiles.size():
		cb_s.tiles[cb_i]["state"] = "growing"
		cb_s.tiles[cb_i]["crop"] = "maize"
		cb_s.tiles[cb_i]["planted_at"] = -100000.0
	var cb_cfg: Dictionary = VehicleModel.loaded_config(cb_s.vehicle_cfg(), cb_s.active_implement())
	cb_s.tractor["x"] = -3.0
	cb_s.tractor["heading"] = 0.5 * PI
	cb_s.tractor["speed"] = 2.0
	cb_s.tractor["z"] = FarmLayout.row_z(3)
	var cb_res: String = cb_s.work_with_tractor(cb_cfg, 0.0, "maize")
	_check(cb_res == "" and cb_s.last_worked_tiles.size() == 3, "the combine header cuts three tiles ahead of it")
	var cb_ahead := FarmLayout.world_to_tile(-3.0 + 2.6, FarmLayout.row_z(3))
	_check(cb_s.last_worked_tiles.has(cb_ahead), "the header works ahead of the combine, not behind it")
	var cb_stopped = GameState.new()
	cb_stopped.money = 50000
	cb_stopped.buy("combine_large")
	cb_stopped.select_vehicle("combine_large")
	_check(cb_stopped.active_width() == 5 and float(cb_stopped.vehicle_cfg()["work_offset"]) < 0.0, "the large combine cuts five tiles with its header ahead")
	# Machines standing in the yard do not overlap each other, the house or the field.
	var py_s = GameState.new()
	py_s.money = 500000
	for py_id in VehicleData.VEHICLES:
		if not py_s.owns(py_id):
			_check(py_s.buy(py_id) == "", "buy %s" % py_id)
	_check(py_s.fleet.size() == VehicleData.VEHICLES.size(), "every owned vehicle has a machine")
	var py_ids: Array = py_s.fleet.keys()
	for py_a in py_ids.size():
		var py_m: Dictionary = py_s.fleet[py_ids[py_a]]
		_check(float(py_m["z"]) >= -11.0 and absf(float(py_m["x"])) <= VehicleData.DRIVE_BOUNDS, "%s stands in the yard" % py_ids[py_a])
		for py_r in VehicleData.OBSTACLES:
			_check(not py_r.has_point(Vector2(float(py_m["x"]), float(py_m["z"]))), "%s is not inside the house" % py_ids[py_a])
		for py_b in range(py_a + 1, py_ids.size()):
			var py_o: Dictionary = py_s.fleet[py_ids[py_b]]
			_check(Hitbox.penetration(Hitbox.of_machine(py_m), Hitbox.of_machine(py_o)) <= 0.0, "%s and %s do not overlap" % [py_ids[py_a], py_ids[py_b]])

	# Machines push each other: a moving one shoves a parked one aside and keeps going.
	var hb_a: Dictionary = {"x": 0.0, "z": 0.0, "heading": 0.0, "speed": 0.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	var hb_b: Dictionary = {"x": 0.0, "z": 4.0, "heading": 0.0, "speed": 0.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	var hb_cfg: Dictionary = VehicleData.VEHICLES["tractor"]
	for hb_i in 60:
		VehicleModel.step(hb_a, hb_cfg, 1.0, 0.0, 0.05, [hb_b])
	_check(float(hb_a["z"]) > 1.5 and not bool(hb_a["_blocked"]), "a tractor drives on into a parked one")
	_check(float(hb_b["z"]) > 4.2, "the parked tractor is pushed along")
	_check(Hitbox.penetration(Hitbox.of_machine(hb_a), Hitbox.of_machine(hb_b)) <= 0.05, "pushed tractors do not stay overlapped")
	# The stronger moving machine pushes the weaker one aside; the weaker one is not stopped.
	var hv_a: Dictionary = {"x": 0.0, "z": 0.0, "heading": 0.0, "speed": 0.0, "fuel": 40.0, "hours": 0.0, "implement": "none", "vehicle": "tractor_heavy"}
	var hv_b: Dictionary = {"x": 0.0, "z": 4.0, "heading": 0.0, "speed": 1.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	var hv_cfg: Dictionary = VehicleData.VEHICLES["tractor_heavy"]
	for hb_i in 60:
		VehicleModel.step(hv_a, hv_cfg, 1.0, 0.0, 0.05, [hv_b])
	_check(float(hv_a["z"]) > 1.0 and float(hv_b["z"]) > 4.2, "the stronger tractor pushes the weaker moving one")
	_check(absf(float(hv_b["speed"]) - 1.0) < 0.001, "the pushed tractor keeps working (its speed is untouched)")
	# A machine against the farmhouse cannot be pushed into it.
	var hh_a: Dictionary = {"x": 0.0, "z": 3.0, "heading": 0.0, "speed": 0.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	var hh_b: Dictionary = {"x": 0.0, "z": 4.6, "heading": 0.0, "speed": 0.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	for hb_i in 80:
		VehicleModel.step(hh_a, hb_cfg, 1.0, 0.0, 0.05, [hh_b])
	var hh_in := false
	for hh_r in VehicleData.OBSTACLES:
		if hh_r.has_point(Vector2(float(hh_b["x"]), float(hh_b["z"]))) or hh_r.has_point(Vector2(float(hh_a["x"]), float(hh_a["z"]))):
			hh_in = true
	_check(not hh_in, "machines are never pushed into the farmhouse")
	var hb_z: float = hb_a["z"]
	for hb_i in 20:
		VehicleModel.step(hb_a, hb_cfg, -1.0, 0.0, 0.05, [hb_b])
	_check(float(hb_a["z"]) < hb_z, "it can reverse away from the other tractor")
	var hb_free: Dictionary = {"x": 5.0, "z": 0.0, "heading": 0.0, "speed": 0.0, "fuel": 20.0, "hours": 0.0, "implement": "none", "vehicle": "tractor"}
	for hb_i in 20:
		VehicleModel.step(hb_free, hb_cfg, 1.0, 0.0, 0.05, [hb_b])
	_check(float(hb_free["z"]) > 0.5 and not bool(hb_free["_blocked"]), "a tractor beside the other one drives on")

	# Several machines at once: each keeps its own place, fuel and tool, and the save keeps them.
	var fl_s = GameState.new()
	fl_s.money = 500000
	fl_s.buy("tractor_heavy")
	fl_s.select_vehicle("tractor_heavy")
	fl_s.equip_implement("plough")
	fl_s.tractor["fuel"] = 7.0
	fl_s.tractor["x"] = -4.0
	fl_s.select_vehicle("tractor")
	_check(fl_s.tractor["implement"] == "none" and float(fl_s.tractor["fuel"]) == 20.0, "each machine has its own tool and fuel")
	_check(float(fl_s.fleet["tractor_heavy"]["x"]) == -4.0 and fl_s.fleet["tractor_heavy"]["implement"] == "plough", "the other machine stays where it was left")
	_check(fl_s.others_of("tractor").size() == fl_s.fleet.size() - 1, "the other machines are listed")
	var fl_t = GameState.new()
	_check(fl_t.from_dict(fl_s.to_dict()) == "", "a save with several machines loads")
	_check(float(fl_t.fleet["tractor_heavy"]["fuel"]) == 7.0 and fl_t.fleet["tractor_heavy"]["implement"] == "plough", "the machines come back as they were")
	var fl_old: Dictionary = fl_s.to_dict()
	fl_old.erase("fleet")
	var fl_u = GameState.new()
	_check(fl_u.from_dict(fl_old) == "" and fl_u.fleet.has("tractor_heavy"), "a save without the fleet starts the other machines in the yard")
	var fl_hv: Dictionary = fl_s.to_dict()
	fl_hv["owned"].append("harvester_3")
	fl_hv["money"] = 10
	fl_hv["tractor"]["implement"] = "harvester"
	var fl_h = GameState.new()
	_check(fl_h.from_dict(fl_hv) == "" and fl_h.money == 2010 and fl_h.tractor["implement"] == "none", "the removed tractor headers are refunded")
	# Two machines of the same kind take different rows.
	var fl_j: Array = fl_s.jobs_for("plough", 0.0, [0, 1, 2])
	_check(not fl_j.is_empty() and int(fl_j[0]["row"]) == 3, "rows another machine is working are left alone")

	# --- Implement models: sized from the catalogue ---
	var im_ids: Array = ImplementData.ITEMS.keys()
	for im_id in im_ids:
		var im_b = ImplementModels.build_builder(im_id)
		var im_w: float = float(ImplementData.width_of(im_id)) * 1.5
		var im_tris: int = im_b.triangle_count()
		_check(im_tris >= 30 and im_tris <= 800, "%s model size (%d triangles)" % [im_id, im_tris])
		var im_min := Vector3(1e9, 1e9, 1e9)
		var im_max := Vector3(-1e9, -1e9, -1e9)
		var im_finite := true
		for im_v in im_b.verts:
			if not (is_finite(im_v.x) and is_finite(im_v.y) and is_finite(im_v.z)):
				im_finite = false
			im_min = im_min.min(im_v)
			im_max = im_max.max(im_v)
		_check(im_finite, "%s model has finite vertices" % im_id)
		var im_span: float = im_max.x - im_min.x
		_check(im_span >= im_w * 0.9 and im_span <= im_w * 1.15, "%s is as wide as its work width" % im_id)
		_check(im_max.z <= 0.2 and im_min.z >= -2.2, "%s trails behind the hitch" % im_id)
		_check(im_min.y >= -0.02 and im_max.y <= 2.0, "%s stays between ground and 2 units" % im_id)
	for im_t in ImplementData.TYPES:
		var im_sorted: Array = ImplementData.ids_of_type(im_t)
		var im_grows := true
		for im_n in range(1, im_sorted.size()):
			var im_a = ImplementModels.build_builder(im_sorted[im_n - 1])
			var im_c = ImplementModels.build_builder(im_sorted[im_n])
			if im_c.triangle_count() <= im_a.triangle_count():
				im_grows = false
		_check(im_grows, "%s: wider models have more detail" % im_t)
	_check(ImplementModels.build_builder("bogus").triangle_count() == 0, "unknown implement has no model")
	_check(ImplementModels.width_units("plough_5") == 7.5, "5-wide model is 7.5 units")
	# --- Suspension (looks only) ---
	var sp_s := Suspension.new_state()
	for sp_i in 100:
		Suspension.step(sp_s, 0.0, 0.0, 0.0, 1.0 / 60.0)
	_check(absf(float(sp_s["pitch"])) < 0.000001 and absf(float(sp_s["bounce"])) < 0.000001, "rest stays still")
	sp_s = Suspension.new_state()
	for sp_i in 60:
		Suspension.step(sp_s, -8.0, 2.0, 0.0, 1.0 / 60.0)
	_check(float(sp_s["pitch"]) > 0.002 and float(sp_s["pitch"]) <= Suspension.pitch_limit(2.0), "braking dips the nose a little")
	_check(float(sp_s["impl_pitch"]) < 0.0, "the implement swings the other way")
	for sp_i in 300:
		Suspension.step(sp_s, 0.0, 0.0, 0.0, 1.0 / 60.0)
	_check(absf(float(sp_s["pitch"])) < 0.002 and absf(float(sp_s["impl_pitch"])) < 0.002, "springs settle after braking")
	var sp_up := Suspension.new_state()
	for sp_i in 60:
		Suspension.step(sp_up, 6.0, 2.0, 0.0, 1.0 / 60.0)
	_check(float(sp_up["pitch"]) < -0.002, "accelerating lifts the nose a little")
	var sp_l := Suspension.new_state()
	var sp_r := Suspension.new_state()
	for sp_i in 60:
		Suspension.step(sp_l, 0.0, 3.0, 1.0, 1.0 / 60.0)
		Suspension.step(sp_r, 0.0, 3.0, -1.0, 1.0 / 60.0)
	_check(absf(float(sp_l["roll"])) > 0.01 and absf(float(sp_l["roll"]) + float(sp_r["roll"])) < 0.000001, "turns lean opposite ways")
	var sp_b := Suspension.new_state()
	var sp_peak := 0.0
	for sp_i in 600:
		Suspension.step(sp_b, 0.0, 3.0, 0.0, 1.0 / 60.0)
		sp_peak = maxf(sp_peak, absf(float(sp_b["bounce"])))
	_check(sp_peak == 0.0, "flat ground: no fake bounce")
	# Tyres stay on the ground: whatever the lean, the lowest tyre rests on y = 0 and no tyre is
	# more than the allowed squash above it.
	var sp_t := Suspension.new_state()
	var sp_lo := 0.0
	var sp_hi := 0.0
	for sp_i in 3000:
		var sp_a2 := 30.0 * sin(float(sp_i) * 0.05)
		Suspension.step(sp_t, sp_a2, 8.0, sp_a2 * 0.1, 1.0 / 60.0, 1.65, 0.7)
		var sp_by := Suspension.body_y(sp_t, 1.65, 0.7)
		for sp_cx in [-0.7, 0.7]:
			for sp_cz in [-1.65, 1.65]:
				var sp_y := sp_by + Suspension.tyre_y(sp_t, sp_cx, sp_cz)
				sp_lo = minf(sp_lo, sp_y)
				sp_hi = maxf(sp_hi, sp_y)
	_check(sp_lo > -0.000001, "no tyre sinks below the ground")
	_check(sp_hi <= 4.0 * Suspension.MAX_WHEEL_DEV + 0.000001, "no tyre lifts more than 4 cm")
	var sp_x := Suspension.new_state()
	var sp_ok := true
	for sp_i in 5000:
		var sp_a := 1000000.0 if sp_i % 2 == 0 else -1000000.0
		Suspension.step(sp_x, sp_a, 50.0, sp_a, 1.0)
		for sp_k in ["pitch", "roll", "bounce", "impl_pitch"]:
			if not is_finite(float(sp_x[sp_k])):
				sp_ok = false
	_check(sp_ok, "extreme inputs stay finite")
	_check(absf(float(sp_x["pitch"])) <= Suspension.pitch_limit(2.0) and absf(float(sp_x["roll"])) <= Suspension.roll_limit(0.8), "lean stays limited")
	for kind in ["unploughed", "ploughed", "stubble"]:
		for tv in 3:
			var tm: ArrayMesh = TileModels.build(kind, tv)
			var tarr = tm.surface_get_arrays(0)
			var tn: int = tarr[Mesh.ARRAY_VERTEX].size()
			var tb: AABB = tm.get_aabb()
			_check(tn > 0 and tn % 3 == 0 and tn / 3 < 500, "tile %s v%d builds (%d triangles)" % [kind, tv, tn / 3])
			_check(tb.size.is_finite() and tb.size.x < 1.6 and tb.size.z < 1.6 and tb.size.y < 0.4, "tile %s v%d stays inside its cell" % [kind, tv])
	for cid in ["maize", "beans", "other"]:
		for stg in CropModels.STAGE_COUNT:
			for det in 4:
				var cm: ArrayMesh = CropModels.build(cid, stg, 0, det)
				var carr = cm.surface_get_arrays(0)
				var nv: int = carr[Mesh.ARRAY_VERTEX].size()
				var cb: AABB = cm.get_aabb()
				var budget := 450 if det == 0 else 900
				_check(nv > 0 and nv % 3 == 0 and carr[Mesh.ARRAY_COLOR].size() == nv and carr[Mesh.ARRAY_NORMAL].size() == nv, "crop %s stage %d detail %d builds (%d triangles)" % [cid, stg, det, nv / 3])
				_check(nv / 3 <= budget, "crop %s stage %d detail %d within triangle budget" % [cid, stg, det])
				_check(cb.size.is_finite() and cb.size.x < 3.0 and cb.size.z < 3.0 and cb.size.y < 2.2, "crop %s stage %d detail %d has sane size" % [cid, stg, det])
	var maize_ripe: ArrayMesh = CropModels.build("maize", 4, 0, 1)
	var maize_young: ArrayMesh = CropModels.build("maize", 2, 0, 1)
	_check(maize_ripe.get_aabb().size.y > maize_young.get_aabb().size.y, "ripe maize is taller than growing maize")

	var holder := Node3D.new()
	var scen = FarmSceneryScript.new()
	scen.build(holder, MeshBuilder.vc_material())
	var scen_tris := 0
	var scen_ok := true
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			scen_ok = false
			continue
		var sa = mi.mesh.surface_get_arrays(0)
		scen_tris += sa[Mesh.ARRAY_VERTEX].size() / 3
		if not mi.mesh.get_aabb().size.is_finite():
			scen_ok = false
	_check(scen_ok and holder.get_child_count() == 7, "scenery builds 7 finite meshes")
	_check(scen_tris < 20000, "scenery triangle budget (%d)" % scen_tris)
	holder.free()


	# --- Plots ---
	var pl := GameState.new()
	_check(pl.plots == ["farm"] and pl.tiles.size() == 64 and pl.tiles[0]["plot"] == "farm", "a new game owns only the home field")
	_check(PlotData.price_of("farm") == 0 and PlotData.price_of("nope") == 0, "the home field costs nothing")
	var pl_ids: Array = PlotData.ids()
	_check(pl_ids.size() == 21 and pl_ids[0] == "farm", "the home field and 20 plots")
	var pl_ok := true
	var pl_sizes := {}
	for pl_a in pl_ids:
		var pl_ra: Rect2 = PlotData.rect_of(pl_a)
		var pl_pd: Dictionary = PlotData.get_plot(pl_a)
		if PlotData.tile_count(pl_a) <= 0 or (pl_a != "farm" and PlotData.price_of(pl_a) <= 0):
			pl_ok = false
		if absf(pl_ra.position.x) > PlotData.WORLD_HALF or absf(pl_ra.end.x) > PlotData.WORLD_HALF \
				or absf(pl_ra.position.y) > PlotData.WORLD_HALF or absf(pl_ra.end.y) > PlotData.WORLD_HALF:
			pl_ok = false
		for pl_b in pl_ids:
			# two plots are at least two setbacks apart, so machines on different plots never meet
			if pl_b != pl_a and pl_ra.grow(PlotData.SETBACK - 0.01).intersects(PlotData.rect_of(pl_b).grow(PlotData.SETBACK - 0.01)):
				pl_ok = false
		pl_sizes[pl_pd["size"]] = true
	_check(pl_ok, "plots have tiles and prices, stay in the land and are far enough apart")
	# every plot is exactly SETBACK from the roads beside it and never nearer; and it has a road to enter from
	var pl_road_ok := true
	for pl_a in pl_ids:
		var pl_r2: Rect2 = PlotData.rect_of(pl_a)
		var pl_near := INF
		for pl_rd in PlotData.ROADS_H:
			if pl_r2.end.x > float(pl_rd[1]) and pl_r2.position.x < float(pl_rd[2]):
				var pl_dz: float = 0.0 if (float(pl_rd[0]) >= pl_r2.position.y and float(pl_rd[0]) <= pl_r2.end.y) else minf(absf(float(pl_rd[0]) - pl_r2.position.y), absf(float(pl_rd[0]) - pl_r2.end.y))
				pl_near = minf(pl_near, pl_dz)
		for pl_rd in PlotData.ROADS_V:
			if pl_r2.end.y > float(pl_rd[1]) and pl_r2.position.y < float(pl_rd[2]):
				var pl_dx: float = 0.0 if (float(pl_rd[0]) >= pl_r2.position.x and float(pl_rd[0]) <= pl_r2.end.x) else minf(absf(float(pl_rd[0]) - pl_r2.position.x), absf(float(pl_rd[0]) - pl_r2.end.x))
				pl_near = minf(pl_near, pl_dx)
		if pl_near < PlotData.SETBACK - 0.01 or pl_near > PlotData.SETBACK + 0.01:
			pl_road_ok = false
		# the access points are on a road
		for pl_sd in ["w", "e"]:
			var pl_ap_pt: Vector2 = PlotData.access_of(pl_a, pl_sd)
			if RoadNet.route(pl_ap_pt, pl_ap_pt).is_empty():
				pl_road_ok = false
	_check(pl_road_ok, "every plot is 7 units from the roads beside it and can be reached by road")
	_check(pl_sizes.has("Medium") and pl_sizes.has("Large") and pl_sizes.has("Very large") and pl_sizes.has("Estate"), "plots come in several sizes")
	_check(PlotData.price_of("p13") > PlotData.price_of("p09") and PlotData.price_of("p09") > PlotData.price_of("p01"), "bigger plots cost more")
	_check(PlotData.tile_count("p01") > GameState.COLS * GameState.ROWS, "new plots are bigger than the home field")
	_check(PlotData.ha_text(100) == "6.0 ha", "areas are shown in hectares")
	_check(pl.can_buy_plot("p01") == "Not enough money", "cannot buy a plot without the money")
	_check(pl.buy_plot("nope") == "Unknown plot", "unknown plot")
	pl.money = 500000
	var pl_price: int = PlotData.price_of("p01")
	var pl_cols: int = int(PlotData.get_plot("p01")["cols"])
	var pl_rows: int = int(PlotData.get_plot("p01")["rows"])
	_check(pl.buy_plot("p01") == "" and pl.money == 500000 - pl_price, "buying a plot takes its price")
	_check(pl.plots == ["farm", "p01"] and pl.tiles.size() == 64 + PlotData.tile_count("p01"), "the new plot's tiles are added")
	_check(pl.tiles[64]["plot"] == "p01" and pl.tiles[64]["col"] == 0 and pl.tiles[64 + pl_cols + 1]["row"] == 1 and pl.tiles[64 + pl_cols + 1]["col"] == 1, "plot tiles know their plot, column and row")
	_check(pl.buy_plot("p01") == "You already own this plot", "a plot can only be bought once")
	var pl_x: float = PlotData.col_x("p01", 3)
	var pl_z: float = PlotData.row_z("p01", 2)
	_check(FarmLayout.world_to_tile(pl_x, pl_z, pl.plots) == 64 + 2 * pl_cols + 3, "a point on the bought plot maps to its tile")
	_check(FarmLayout.world_to_tile(pl_x, pl_z) == -1, "the same point is no tile while the plot is not owned")
	_check(FarmLayout.plot_at(pl_x, pl_z, pl.plots) == "p01" and FarmLayout.plot_at(0.0, -9.4, pl.plots) == "farm", "plot_at finds the plot")
	_check(FarmLayout.tile_info(64 + pl_cols + 1, pl.plots)["plot"] == "p01" and FarmLayout.tile_info(5, pl.plots)["plot"] == "farm", "tile_info maps an index to its plot")
	var pl_c: Vector2 = PlotData.rect_of("p01").get_center()
	_check(FarmLayout.nearest_plot(pl_c.x - 5.0, pl_c.y, pl.plots) == "p01", "nearest plot")
	_check(FarmLayout.col_x(3) == PlotData.col_x("farm", 3) and FarmLayout.row_z(5) == PlotData.row_z("farm", 5), "home field positions are unchanged")
	# status, work and jobs on the new plot
	var pl_t0 := 5000.0
	_check(pl.rows_with_work("plough", pl_t0, "p01").size() == pl_rows and pl.rows_with_work("plough", pl_t0).size() == 8, "plough work is counted per plot")
	_check(pl.rows_with_work("plough", pl_t0, "p15").is_empty() and pl.jobs_for("plough", pl_t0, [], "p15").is_empty(), "no work on a plot that is not owned")
	var pl_jobs: Array = pl.jobs_for("plough", pl_t0, [], "p01")
	_check(pl_jobs.size() == pl_rows and int(pl_jobs[0]["c1"]) == pl_cols - 1, "jobs cover the rows and columns of the plot")
	_check(pl.plough(64) == "" and pl.plant(64, "maize", pl_t0) == "", "ploughing and planting on a new plot")
	var pl_st: Dictionary = pl.plot_status("p01", pl_t0)
	_check(int(pl_st["growing"]) == 1 and int(pl_st["ploughed"]) == 0 and int(pl_st["empty"]) == pl_cols * pl_rows - 1 and not bool(pl_st["ready"]), "plot status counts growing tiles")
	var pl_grow: float = float(CropData.CROPS["maize"]["grow_seconds"])
	pl_st = pl.plot_status("p01", pl_t0 + pl_grow + 1.0)
	_check(int(pl_st["ripe"]) == 1 and bool(pl_st["ready"]), "plot status shows ripe tiles as ready")
	_check(int(pl.plot_status("farm", pl_t0)["ripe"]) == 0 and int(pl.plot_status("p15", pl_t0)["tiles"]) == 0, "status of other plots")
	# save and load
	var pl_d: Dictionary = pl.to_dict()
	var pl2 := GameState.new()
	_check(pl2.from_dict(pl_d) == "" and pl2.plots == ["farm", "p01"] and pl2.tiles.size() == pl.tiles.size(), "a save with a bought plot loads")
	_check(pl2.tiles[64]["state"] == "growing" and pl2.tiles[64]["plot"] == "p01", "the plot's crops come back")
	var pl_old: Dictionary = GameState.new().to_dict()
	pl_old.erase("plots")
	pl_old["schema_version"] = 4
	var pl3 := GameState.new()
	_check(pl3.from_dict(pl_old) == "" and pl3.plots == ["farm"], "an old save (version 4) loads with the home field")
	# a version 5 save had other plot ids: the plots are taken back and refunded
	var pl_v5: Dictionary = GameState.new().to_dict()
	pl_v5["schema_version"] = 5
	pl_v5["plots"] = ["farm", "e1"]
	pl_v5["money"] = 1000
	for pl_k in 120:
		pl_v5["tiles"].append({"state": "unploughed", "crop": "", "planted_at": 0.0, "fertilized": false})
	var pl4 := GameState.new()
	_check(pl4.from_dict(pl_v5) == "" and pl4.plots == ["farm"] and pl4.tiles.size() == 64 and pl4.money == 1000 + 4200, "a version 5 save gets its old plots refunded")
	var pl_bad: Dictionary = pl.to_dict()
	pl_bad["plots"] = ["p01", "farm"]
	_check(GameState.new().from_dict(pl_bad) == "Bad plots", "the home field must come first")
	pl_bad["plots"] = ["farm", "p01", "p01"]
	_check(GameState.new().from_dict(pl_bad) == "Bad plots", "a plot cannot be listed twice")
	pl_bad["plots"] = ["farm", "mars"]
	_check(GameState.new().from_dict(pl_bad) == "Bad plots", "an unknown plot is refused")
	pl_bad["plots"] = ["farm", "p01"]
	pl_bad["tiles"] = pl_bad["tiles"].slice(0, 64)
	_check(GameState.new().from_dict(pl_bad) == "Bad tiles", "the tile count must match the plots")
	# roads: routes stay on the roads and never cross a plot
	var pl_from := Vector2(0.0, 8.0)
	var pl_goal: Vector2 = PlotData.access_of("p13", "e")
	var pl_route: Array = RoadNet.route(pl_from, pl_goal)
	_check(not pl_route.is_empty() and (pl_route[pl_route.size() - 1] as Vector2).distance_to(pl_goal) < 0.01, "a route leads from the yard to a far plot")
	var pl_route_ok := true
	var pl_prev: Vector2 = pl_from
	for pl_q in pl_route:
		var pl_seg: Vector2 = pl_q
		var pl_steps := int(pl_prev.distance_to(pl_seg)) + 1
		for pl_k in pl_steps + 1:
			var pl_pt := pl_prev.lerp(pl_seg, float(pl_k) / float(pl_steps))
			for pl_pid in pl_ids:
				if PlotData.rect_of(pl_pid).grow(-0.2).has_point(pl_pt):
					pl_route_ok = false
		pl_prev = pl_seg
	_check(pl_route_ok, "routes never cross a plot")
	_check(RoadNet.path_length(pl_from, pl_route) < 700.0, "the route is not absurdly long")
	_check(RoadNet.route(Vector2(0.0, 8.0), Vector2(1.0, 1.0)).is_empty(), "no route to a point that is not on a road")
	# autopilot on another plot, and travelling to a plot
	var pl_ap := AutoPilotScript.new()
	pl.tractor["x"] = 0.0
	pl.tractor["z"] = 8.0
	_check(pl_ap.start(pl.tractor, pl_jobs, 1.8, 1, pl_rows, "p01") and pl_ap.plot_id == "p01", "autopilot starts on another plot")
	var pl_rect: Rect2 = PlotData.rect_of("p01")
	var pl_lane_ok := true
	var pl_lanes := 0
	var pl_road := false
	for pl_pw in pl_ap.wps:
		if bool(pl_pw["work"]):
			pl_lanes += 1
			if float(pl_pw["z"]) < pl_rect.position.y or float(pl_pw["z"]) > pl_rect.end.y:
				pl_lane_ok = false
		elif PlotData.rect_of("p01").grow(-0.2).has_point(Vector2(float(pl_pw["x"]), float(pl_pw["z"]))) == false and absf(float(pl_pw["z"]) - 3.6) < 0.01:
			pl_road = true
	_check(pl_lane_ok and pl_lanes == pl_rows, "autopilot works all the rows of the plot")
	_check(pl_road, "a machine from the yard drives out along the main road")
	var pl_tr := AutoPilotScript.new()
	_check(pl_tr.travel_to_plot(pl.tractor, "p03") and pl_tr.kind == "travel" and pl_tr.active, "travel autopilot starts")
	var pl_last: Dictionary = pl_tr.wps[pl_tr.wps.size() - 1]
	_check(PlotData.rect_of("p03").has_point(Vector2(float(pl_last["x"]), float(pl_last["z"]))) and not bool(pl_last["work"]), "travel ends inside the plot without working")
	_check(not pl_tr.travel_to_plot(pl.tractor, "mars"), "cannot travel to an unknown plot")
	var pl_tr2 := AutoPilotScript.new()
	pl.tractor["z"] = 3.6
	_check(pl_tr2.travel_to_plot(pl.tractor, "p19") and float(pl_tr2.wps[pl_tr2.wps.size() - 1]["z"]) > 40.0, "travel to a south plot ends south of the road")

	print("---- ", failures, " failure(s)")
	quit(failures)
