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
const SettingsScript := preload("res://scripts/settings.gd")
const CropModels := preload("res://scripts/crop_models.gd")

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

func _run(v: Dictionary, cfg: Dictionary, throttle: float, steer: float, frames: int) -> void:
	for i in frames:
		VehicleModel.step(v, cfg, throttle, steer, 1.0 / 60.0)

# Simulates an autopilot job headlessly using the same logic as the game.
func _auto_job(s, kind: String, now0: float, fuel: float = 20.0) -> Dictionary:
	var ap = AutoPilotScript.new()
	var vcfg: Dictionary = VehicleData.VEHICLES["tractor"]
	s.tractor["implement"] = kind
	s.tractor["fuel"] = fuel
	s.last_work_tile = -1
	var jobs: Array = s.jobs_for(kind, now0)
	if not ap.start(s.tractor, jobs, float(vcfg["work_offset"])):
		return {"started": false}
	var t := 0.0
	var dt := 1.0 / 60.0
	while ap.active and t < 300.0:
		var ctl: Vector2 = ap.update(s.tractor, dt)
		VehicleModel.step(s.tractor, vcfg, ctl.x, ctl.y, dt)
		if ap.working:
			s.work_with_tractor(vcfg, now0 + t, "beans")
		t += dt
	return {"started": true, "time": t, "finished": ap.finished, "message": ap.message, "est": 0.0}

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
	_check(s.tiles[0]["state"] == "ploughed", "tile returns to ploughed")
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
	_check(absf(v["speed"] - 4.0) < 0.001, "reaches top speed after 1s")
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
	_check(absf(v4["speed"] + 2.0) < 0.001, "reverse is half speed")

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
	_check(seq == ["plough", "seeder", "harvester", "none", "plough"], "tool cycles in order")

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
	tbad["tractor"]["x"] = 50.0
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
		for zi in range(-130, 51):
			var gx := xi * 0.1
			var gz := zi * 0.1
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

	res = _auto_job(job, "harvester", t0 + 1000.0)
	_check(res["started"] and res["finished"], "autopilot finishes harvesting")
	_check(int(job.inventory.get("beans", 0)) == 64 * 3, "autopilot harvests all 64 tiles")
	_check(_count_state(job, "ploughed") == 64, "harvested tiles return to ploughed")
	_check(job.rows_with_work("plough", t0 + 1000.0).is_empty(), "nothing left to plough")
	_check(not AutoPilotScript.new().start(job.tractor, [], 1.8), "autopilot refuses an empty job")

	# Partial job: only some rows need work
	var part = GameState.new()
	for pr in [1, 2, 5]:
		for pc in 8:
			part.plough(pr * 8 + pc)
	res = _auto_job(part, "plough", t0)
	_check(res["finished"] and _count_state(part, "unploughed") == 0, "autopilot ploughs only the rows that need it")

	# Blocked: tractor behind the farmhouse cannot reach the corridor
	var blk = GameState.new()
	blk.tractor["x"] = 0.0
	blk.tractor["z"] = 10.5
	blk.tractor["heading"] = 0.0
	res = _auto_job(blk, "plough", t0)
	_check(res["started"] and not res["finished"], "autopilot gives up when blocked")

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
	res = _auto_job(lowf, "plough", t0, 3.0)
	var done_before := _count_state(lowf, "ploughed")
	_check(not res["finished"] and res["message"] == "Out of fuel", "autopilot stops when fuel runs out")
	_check(done_before > 0 and done_before < 64, "some tiles done before fuel ran out (" + str(done_before) + ")")
	res = _auto_job(lowf, "plough", t0)
	_check(res["finished"] and _count_state(lowf, "ploughed") == 64, "second run finishes the rest")
	_check(res["time"] < 70.0, "second run only does what is left (" + str(res["time"]) + " s)")

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
	_check(res["finished"] and res["time"] < 15.0, "nearby row is done quickly (" + str(res["time"]) + " s)")
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
	_check(est > 8.0 and est < 14.0, "fuel estimate for a full field is realistic (" + str(est) + ")")

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

	# --- Crop models ---
	_check(CropModels.stage_for(0.0) == 0 and CropModels.stage_for(0.5) == 1 and CropModels.stage_for(1.0) == 2, "crop stages by progress")
	for cid in ["maize", "beans", "other"]:
		for stg in 3:
			var cm = CropModels.build(cid, stg)
			var carr = cm.surface_get_arrays(0)
			var nv: int = carr[Mesh.ARRAY_VERTEX].size()
			_check(cm.get_surface_count() == 1 and nv > 0 and carr[Mesh.ARRAY_COLOR].size() == nv, "crop model %s stage %d builds (%d vertices)" % [cid, stg, nv])

	print("---- ", failures, " failure(s)")
	quit(failures)
