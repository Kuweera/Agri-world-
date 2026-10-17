extends Node3D
# Entry point: wires light, sky, farm, tractor, camera, HUD, game state and saving.

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const TractorViewScript := preload("res://scripts/tractor_view.gd")
const AutoPilotScript := preload("res://scripts/autopilot.gd")

var rig
var grid
var hud
var state
var tractor_view
var autopilot
var cfg: Dictionary = {}
var selected := -1
var refresh_timer := 0.0
var reset_armed_until := 0
var driving := false
var seed_crop := "maize"
var dirty := false
var save_timer := 0.0
var empty_warned := false

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

	cfg = VehicleData.VEHICLES["tractor"]
	autopilot = AutoPilotScript.new()
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

# Save when the app goes to the background or is closed.
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

# ---- Frame update ----

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
	var thr: float = hud.get_throttle()
	var st: float = hud.get_steer()

	if autopilot.active:
		if absf(thr) > 0.2 or absf(st) > 0.2:
			_stop_auto("Manual control")
		else:
			var ctl: Vector2 = autopilot.update(tr, dt)
			thr = ctl.x
			st = ctl.y
			if not autopilot.active:
				_auto_ended()

	VehicleModel.step(tr, cfg, thr, st, dt)

	if float(tr["fuel"]) <= 0.0 and not empty_warned:
		empty_warned = true
		hud.set_message("Out of fuel - tap Refuel")
	elif float(tr["fuel"]) > 0.0:
		empty_warned = false

	# Manual driving always works the field; the autopilot only while on a lane.
	if (not autopilot.active) or autopilot.working:
		_apply_work()

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

func _apply_work() -> void:
	var res: String = state.work_with_tractor(cfg, _now(), seed_crop)
	if res == "":
		_refresh_tile(state.last_work_tile)
		_update_ui()
		dirty = true
	elif res != "skip":
		if autopilot.active:
			_stop_auto(res)
		else:
			hud.set_message(res)

# ---- Autopilot ----

func _toggle_auto() -> void:
	if autopilot.active:
		_stop_auto("Autopilot stopped")
		return
	var kind: String = state.tractor["implement"]
	if kind == "none":
		hud.set_message("Pick a tool first")
		return
	var rows: Array = state.rows_with_work(kind, _now())
	if rows.is_empty():
		hud.set_message("Nothing to do for this tool")
		return
	if float(state.tractor["fuel"]) < 1.0:
		hud.set_message("Refuel first")
		return
	state.last_work_tile = -1
	if autopilot.start(state.tractor, rows):
		hud.set_auto_active(true)
		hud.set_message("Autopilot on")

func _stop_auto(reason: String) -> void:
	autopilot.stop(reason)
	hud.set_auto_active(false)
	if reason != "":
		hud.set_message(reason)
	dirty = true

func _auto_ended() -> void:
	hud.set_auto_active(false)
	if autopilot.finished:
		hud.set_message("Autopilot finished")
	else:
		hud.set_message(autopilot.message)
	_save()

# ---- Mode switching ----

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
	state.last_work_tile = -1
	empty_warned = false
	hud.set_drive_mode(true)
	hud.set_auto_active(false)
	_update_drive_texts()
	_update_ui()

func _enter_manage() -> void:
	if autopilot.active:
		autopilot.stop("")
	hud.set_auto_active(false)
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

# ---- Input ----

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
		if autopilot.active:
			autopilot.stop("")
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
	if action == "auto":
		_toggle_auto()
		return
	if action == "implement_next":
		if autopilot.active:
			_stop_auto("Tool changed")
		state.next_implement()
		state.last_work_tile = -1
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
				if p >= 1.0:
					text = head + "%s: ripe!" % c["name"]
					actions.append("harvest")
				else:
					text = head + "%s: growing %d%%" % [c["name"], int(p * 100.0)]
	hud.set_tile_text(text)
	hud.show_actions(actions)
