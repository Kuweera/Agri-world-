extends SceneTree
# Headless logic tests. Run with:
#   godot --headless --script res://scripts/tests/test_game_state.gd
# Prints PASS/FAIL lines and exits with the number of failures.

const GameState := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")

var failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		failures += 1

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

	print("---- ", failures, " failure(s)")
	quit(failures)
