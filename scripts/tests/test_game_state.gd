extends SceneTree

const GameState := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")

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

func _run(v: Dictionary, cfg: Dictionary, th: float, st: float, fr: int) -> void:
	for i in fr:
		VehicleModel.step(v, cfg, th, st, 1.0 / 60.0)

func _init() -> void:
	var t0 := 1000.0
	var s = GameState.new()

	_check(s.money == 500, "starts with 500 money")
	_check(s.tiles.size() == 64, "has 64 tiles")

	_check(s.plough(-1) != "", "plough rejects tile -1")
	_check(s.plough(64) != "", "plough rejects tile 64")

	_check(s.plant(0, "maize", t0) != "", "no plant on unploughed")
	_check(s.money == 500, "failed plant costs nothing")

	_check(s.plough(0) == "", "plough tile 0")
	_check(s.plough(0) != "", "cannot plough twice")

	_check(s.plant(0, "bogus", t0) != "", "unknown crop rejected")
	_check(s.plant(0, "maize", t0) == "", "plant maize")
	_check(s.money == 480, "maize seed costs 20")
	_check(s.plant(0, "beans", t0) != "", "no plant on growing")

	_check(absf(s.progress(0, t0 + 20.0) - 0.5) < 0.001, "half grown 20s")
	_check(not s.is_ripe(0, t0 + 39.0), "not ripe at 39s")
	_check(s.harvest(0, t0 + 39.0) != "", "no early harvest")
	_check(s.is_ripe(0, t0 + 40.0), "ripe at 40s")
	_check(s.harvest(0, t0 + 40.0) == "", "harvest ripe maize")
	_check(int(s.inventory.get("maize", 0)) == 4, "yield 4 maize")
	
	# Accounts for your visual overhaul logic where harvesting results in stubble
	var post_harvest_state: String = s.tiles[0]["state"]
	_check(post_harvest_state == "stubble" or post_harvest_state == "ploughed", "valid post-harvest state")

	s.money = 5
	_check(s.plough(2) == "", "plough tile 2")
	_check(s.plant(2, "maize", t0) != "", "cannot afford maize")

	var a = GameState.new()
	a.plough(0)
	a.plant(0, "maize", t0)
	a.money = 300
	var parsed = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b = GameState.new()
	_check(b.from_dict(parsed) == "", "from_dict valid save")
	_check(b.money == 300, "money survives save")

	var path := "user://test_save.json"
	_cleanup(path)
	_check(SaveManager.save_state(a, path), "save file write")
	var d = GameState.new()
	_check(SaveManager.load_into(d, path) == "", "load file read")
	_cleanup(path)

	var cfg_tr: Dictionary = VehicleData.VEHICLES["tractor"]
	var v := GameState.default_tractor()
	_run(v, cfg_tr, 1.0, 0.0, 60)
	_check(absf(v["speed"] - 4.0) < 0.001, "top speed forward")
	_check(v["fuel"] < 20.0, "driving uses fuel")

	var v4 := GameState.default_tractor()
	_run(v4, cfg_tr, -1.0, 0.0, 120)
	_check(absf(v4["speed"] + 2.0) < 0.001, "reverse half speed")

	var w = GameState.new()
	_check(w.apply_implement("plough", 5, "maize", t0) == "", "tool ploughs")

	print("---- ", failures, " failure(s)")
	quit(failures)
