extends Node3D
# Entry point: wires light, sky, farm, camera, HUD and game state together.

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")

var rig
var grid
var hud
var state
var selected := -1
var refresh_timer := 0.0

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = env
	add_child(we)

	state = GameStateScript.new()

	grid = FarmGridScript.new()
	add_child(grid)

	rig = CameraRigScript.new()
	rig.position = Vector3(0, 0, -1)
	add_child(rig)

	hud = HudScript.new()
	add_child(hud)

	rig.tapped.connect(_on_tapped)
	hud.action_pressed.connect(_on_action)

	for i in state.tiles.size():
		_refresh_tile(i)
	_update_ui()

func _now() -> float:
	return Time.get_unix_time_from_system()

func _refresh_tile(i: int) -> void:
	grid.refresh_tile(i, state.tiles[i], state.progress(i, _now()), i == selected)

func _process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer < 0.5:
		return
	refresh_timer = 0.0
	for i in state.tiles.size():
		if state.tiles[i]["state"] == "growing":
			_refresh_tile(i)
	if selected >= 0 and state.tiles[selected]["state"] == "growing":
		_update_ui()

func _on_tapped(pos: Vector2) -> void:
	var hit = rig.ray_to_ground(pos)
	var idx := -1
	if hit != null:
		idx = grid.world_to_tile(hit)
	var old := selected
	selected = idx
	if old >= 0:
		_refresh_tile(old)
	if selected >= 0:
		_refresh_tile(selected)
	_update_ui()

func _on_action(action: String) -> void:
	var now := _now()
	var err := ""
	if action == "sell":
		var earned: int = state.sell_all()
		if earned > 0:
			hud.set_message("Sold for %d" % earned)
		else:
			hud.set_message("Nothing to sell")
	elif action == "plough":
		err = state.plough(selected)
	elif action == "harvest":
		err = state.harvest(selected, now)
	elif action.begins_with("plant_"):
		err = state.plant(selected, action.substr(6), now)
	if err != "":
		hud.set_message(err)
	if selected >= 0:
		_refresh_tile(selected)
	_update_ui()

func _update_ui() -> void:
	var now := _now()
	hud.set_status("Money: %d\n%s" % [state.money, state.inventory_text()])
	var actions: Array = ["sell"]
	var text := "Tap a tile"
	if selected >= 0:
		var t: Dictionary = state.tiles[selected]
		var head := "Field tile %d, %d\n" % [t["col"] + 1, t["row"] + 1]
		match t["state"]:
			"unploughed":
				text = head + "Soil: unploughed"
				actions.append("plough")
			"ploughed":
				text = head + "Soil: ploughed\nReady to plant"
				for id in CropData.CROPS:
					actions.append("plant_" + id)
			"growing":
				var c: Dictionary = CropData.CROPS[t["crop"]]
				var p: float = state.progress(selected, now)
				if p >= 1.0:
					text = head + "%s: ripe!" % c["name"]
					actions.append("harvest")
				else:
					text = head + "%s: growing %d%%" % [c["name"], int(p * 100.0)]
	hud.set_tile_text(text)
	hud.show_actions(actions)
