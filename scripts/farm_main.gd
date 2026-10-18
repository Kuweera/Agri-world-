extends Node3D

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const TractorViewScript := preload("res://scripts/tractor_view.gd")
const EnvironmentSetupScript := preload("res://scripts/environment_setup.gd")

var rig
var grid
var hud
var state
var tractor_view
var env_setup
var cfg: Dictionary = {}
var selected := -1
var refresh_timer := 0.0
var reset_armed_until := 0
var driving := false
var last_work_tile := -1
var seed_crop := "maize"
var dirty := false
var save_timer := 0.0
var empty_warned := false

func _ready() -> void:
	# Instantiate our new dynamic environment and lighting tier setup
	env_setup = EnvironmentSetupScript.new()
	add_child(env_setup)
	env_setup.apply_quality_profile("low") # Baseline optimization for the PowerVR GPU

	cfg = VehicleData.VEHICLES["tractor"]
	state = GameStateScript.new()
	var load_result: String = SaveManager.load_into(state)

	grid = FarmGridScript.new()
	add_child(grid)

	tractor_view = TractorViewScript.new()
	add_child(tractor_view)
	tractor_view.update_from(state.tractor)

	rig = CameraRigScript.new()
	rig.position = Vector3(0, 0, -1)
	add_child(rig)

	hud = HudScript.new()
	add_child(hud)

	rig.tapped.connect(_on_tapped)
	hud.action_pressed.connect(_on_action)

	for i in state.tiles.size():
		_refresh_tile(i)
	_update_drive_texts()
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
	dirty = false
	if not SaveManager.save_state(state) and hud != null:
		hud.set_message("Could not save")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state != null:
			_save()

func _refresh_tile(i: int) -> void:
	grid.refresh_tile(i, state.tiles[i], state.progress(i, _now()), i == selected)

func _update_drive_texts() -> void:
	var tool_name: String = VehicleData.IMPLEMENTS[state.tractor["implement"]]["name"]
	var crop_name: String = CropData.CROPS[seed_crop]["name"]
	hud.set_drive_texts(tool_name, crop_name)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if driving:
		_drive(dt)

	if dirty:
		save_timer += delta
		if save_timer >= 2.0:
			save_timer = 0.0
			_save()

	refresh_timer += delta
	if refresh_timer < 0.5:
		return
	refresh_timer = 0.0
	for i in state.tiles.size():
		if state.tiles[i]["state"] == "growing":
			_refresh_tile(i)
	if selected >= 0 and state.tiles[selected]["state"] == "growing":
		_update_ui()

func _drive(dt: float) -> void:
	var tr: Dictionary = state.tractor
	VehicleModel.step(tr, cfg, hud.get_throttle(), hud.get_steer(), dt)
	if float(tr["fuel"]) <= 0.0 and not empty_warned:
		empty_warned = true
		hud.set_message("Out of fuel - tap Refuel")
	elif float(tr["fuel"]) > 0.0:
		empty_warned = false
	_apply_work(tr)
	tractor_view.update_from(tr)
	rig.position = Vector3(tr["x"], 0.0, tr["z"])
	rig.yaw = lerp_angle(rig.yaw, float(tr["heading"]) + PI, minf(1.0, 4.0 * dt))
	rig.apply_view()
	hud.set_vehicle_text(_vehicle_text(tr))
	if absf(float(tr["speed"])) > 0.05:
		dirty = true

func _vehicle_text(tr: Dictionary) -> String:
	var secs := int(float(tr["hours"]) * 3600.0)
	return "Fuel %.1f/%d   Speed %.1f   Run %d:%02d" % [
		tr["fuel"], int(cfg["fuel_capacity"]), absf(float(tr["speed"])),
		floori(secs / 60.0), secs % 60]

func _apply_work(tr: Dictionary) -> void:
	if tr["implement"] == "none" or absf(float(tr["speed"])) < 0.1:
		return
	var off: float = cfg["work_offset"]
	var heading: float = tr["heading"]
	var wx: float = float(tr["x"]) - sin(heading) * off
	var wz: float = float(tr["z"]) - cos(heading) * off
	var idx: int = grid.world_to_tile(Vector3(wx, 0.0, wz))
	if idx < 0:
		last_work_tile = -1
		return
	if idx == last_work_tile:
		return
	last_work_tile = idx
	var res: String = state.apply_implement(tr["implement"], idx, seed_crop, _now())
	if res == "":
		_refresh_tile(idx)
		_update_ui()
		dirty = true
	elif res != "skip":
		hud.set_message(res)

func _enter_drive() -> void:
	driving = true
	state.tractor["speed"] = 0.0
	var old := selected
	selected = -1
	if old >= 0:
		_refresh_tile(old)
	rig.allow_rotate = false
	rig.pitch = 0.55
	rig.dist = 9.0
	last_work_tile = -1
	empty_warned = false
	hud.set_drive_mode(true)
	_update_drive_texts()
	_update_ui()

func _enter_manage() -> void:
	driving = false
	state.tractor["speed"] = 0.0
	rig.allow_rotate = true
	rig.position = Vector3(0, 0, -1)
	rig.yaw = 0.5
	rig.pitch = 0.9
	rig.dist = 18.0
	rig.apply_view()
	hud.set_drive_mode(false)
	_save()
	_update_ui()

func _on_tapped(pos: Vector2) -> void:
	if driving:
		return
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
		tractor_view.update_from(state.tractor)
		if driving:
			_enter_manage()
		_save()
		_update_drive_texts()
		_update_ui()
		hud.set_message("Farm reset")
	else:
		reset_armed_until = t + 3000
		hud.set_message("Tap Reset again to wipe the farm")

func _on_action(action: String) -> void:
	if action == "reset":
		_handle_reset()
		return
	if action == "drive":
		_enter_drive()
		return
	if action == "manage":
		_enter_manage()
		return
	if action == "implement_next":
		state.next_implement()
		last_work_tile = -1
		_update_drive_texts()
		tractor_view.update_from(state.tractor)
		dirty = true
		return
	if action == "seed_next":
		var ids: Array = CropData.CROPS.keys()
		seed_crop = ids[(ids.find(seed_crop) + 1) % ids.size()]
		_update_drive_texts()
		return

	var now := _now()
	var err := ""
	if action == "sell":
		var earned: int = state.sell_all()
		if earned > 0:
			hud.set_message("Sold for %d" % earned)
		else:
			hud.set_message("Nothing to sell")
	elif action == "refuel":
		err = state.refuel()
		if err == "":
			hud.set_message("Refuelled")
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
	var actions: Array = ["sell", "drive"]
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
				var s_name := CropStages.get_stage_name(t["crop"], p)
				if p >= 1.0:
					text = head + "%s: ripe!" % c["name"]
					actions.append("harvest")
				else:
					text = head + "%s: growing %d%% (%s)" % [c["name"], int(p * 100.0), s_name.capitalize()]
	hud.set_tile_text(text)
	hud.show_actions(actions)
