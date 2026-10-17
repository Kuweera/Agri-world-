extends SceneTree
# Headless logic tests. Run with:
#   godot --headless --script res://scripts/tests/test_game_state.gd
# Prints PASS/FAIL lines and exits with the number of failures.

const GameState := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")

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

	print("---- ", failures, " failure(s)")
	quit(failures)
