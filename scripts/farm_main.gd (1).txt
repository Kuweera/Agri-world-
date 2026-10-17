extends Node3D
# Entry point: wires light, sky, farm, camera, HUD, game state and saving together.

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")

var rig
var grid
var hud
var state
var selected := -1
var refresh_timer := 0.0
var reset_armed_until := 0

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
	var load_result: String = SaveManager.load_into(state)

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

	if load_result == "":
		var ripe := _count_ripe()
		if ripe > 0:
			hud.set_message("Welcome back! %d crop(s) ripe" % ripe)
		else:
			hud.set_message("Welcome back!")
	elif load_result == "corrupt":
		hud.set_message("Save was damaged - new farm started")

func _now() -> float:
	return Time.get_unix_time_from_system()

func _count_ripe() -> int:
	var n := 0
	var now := _now()
	for i in state.tiles.size():
		if state.is_ripe(i, now):
			n += 1
	return n

func _save() -> void:
	if not SaveManager.save_state(state) and hud != null:
		hud.set_message("Could not save")

# Save when the app goes to the background or is closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state != null:
			_save()

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

func _handle_reset() -> void:
	var t := Time.get_ticks_msec()
	if t < reset_armed_until:
		reset_armed_until = 0
		state = GameStateScript.new()
		selected = -1
		for i in state.tiles.size():
			_refresh_tile(i)
		_save()
		_update_ui()
		hud.set_message("Farm reset")
	else:
		reset_armed_until = t + 3000
		hud.set_message("Tap Reset again to wipe the farm")

func _on_action(action: String) -> void:
	if action == "reset":
		_handle_reset()
		return
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
	else:
		_save()
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
