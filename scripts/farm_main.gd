extends Node3D
# Entry point: wires light, sky, farm, tractor, camera, HUD, game state, settings and saving.

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CropData := preload("res://scripts/crop_data.gd")
const SaveManager := preload("res://scripts/save_manager.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const VehicleModel := preload("res://scripts/vehicle_model.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const MachineryShopScript := preload("res://scripts/machinery_shop.gd")
const TractorViewScript := preload("res://scripts/tractor_view.gd")
const AutoPilotScript := preload("res://scripts/autopilot.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const EnvironmentSetupScript := preload("res://scripts/environment_setup.gd")
const ParkingScript := preload("res://scripts/parking.gd")
const MachineModels := preload("res://scripts/machine_models.gd")

const QUALITY_NAMES := ["Low", "Medium", "High"]
const DRIVE_SAVE_INTERVAL := 8.0   # seconds; saving more often can cause hitches on slow storage

var env_setup
var rig
var grid
var hud
var state
var tractor_view
var autopilot
var settings: Dictionary = {}
var cfg: Dictionary = {}
var selected := -1
var refresh_timer := 0.0
var reset_armed_until := 0
var driving := false
var seed_crop := "maize"
var dirty := false
var save_timer := 0.0
var empty_warned := false
var shop                  # machinery shop screen (an overlay)
var shop_button: Button
var auto_pass := 0       # which autopilot pass we are on (max 3)
var pass_worked := 0     # tiles worked in this pass
var job_worked := 0      # tiles worked in the whole autopilot job
var vehicle_text_timer := 0.0
var last_heading := 0.0
var cam_resetting := false
var tool_raised := true        # the tool (or combine header) is up for travel; work needs it down
var lift_hint_shown := false
var parked_root: Node3D        # machines waiting in the yard by the house

func _ready() -> void:
	settings = SettingsScript.load_settings()

	env_setup = EnvironmentSetupScript.new()
	add_child(env_setup)

	cfg = VehicleData.VEHICLES["tractor"]
	autopilot = AutoPilotScript.new()
	state = GameStateScript.new()
	var load_result: String = SaveManager.load_into(state)
	_refresh_cfg()

	grid = FarmGridScript.new()
	add_child(grid)

	tractor_view = TractorViewScript.new()
	add_child(tractor_view)
	tractor_view.update_from(state.tractor)
	_refresh_parked()

	rig = CameraRigScript.new()
	rig.position = Vector3(0, 0, -1)
	add_child(rig)

	_apply_quality(int(settings["quality"]))

	hud = HudScript.new()
	add_child(hud)
	hud.set_menu_state(int(settings["quality"]), bool(settings["debug"]))
	hud.set_debug_visible(bool(settings["debug"]))

	rig.tapped.connect(_on_tapped)
	hud.action_pressed.connect(_on_action)

	# Machinery shop: a "Shop" button and a full-screen overlay on their own layer.
	var shop_layer := CanvasLayer.new()
	shop_layer.layer = 20
	add_child(shop_layer)
	shop_button = Button.new()
	shop_button.text = "Shop"
	shop_button.add_theme_font_size_override("font_size", 26)
	shop_button.anchor_left = 1.0
	shop_button.anchor_right = 1.0
	shop_button.offset_left = -190.0
	shop_button.offset_right = -20.0
	shop_button.offset_top = 112.0
	shop_button.offset_bottom = 176.0
	shop_button.pressed.connect(_open_shop)
	shop_layer.add_child(shop_button)
	shop = MachineryShopScript.new()
	shop_layer.add_child(shop)
	shop.changed.connect(_on_shop_changed)
	shop.closed.connect(_on_shop_closed)

	_refresh_all_tiles()
	_update_drive_texts()
	_update_lift_text()
	_update_ui()

	if load_result == "":
		var ripe := _count_ripe()
		if ripe > 0:
			hud.set_message("Welcome back! %d crop(s) ripe" % ripe)
		else:
			hud.set_message("Welcome back!")
	elif load_result == "corrupt":
		hud.set_message("Save was damaged - new farm started")
	_check_relief()

# Low: flat sky colour, no shadows, lighter crops, blob shadows (safest for weak phones).
# Medium/High: procedural sky, real sun shadows, full crop detail.
func _apply_quality(q: int) -> void:
	env_setup.apply_quality(q)
	grid.set_detail(0 if q == 0 else 1)
	grid.set_blob_shadows(q == 0)
	tractor_view.set_blob_visible(q == 0)

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

func _refresh_all_tiles() -> void:
	for i in state.tiles.size():
		_refresh_tile(i)

# Extra line for the tile info box when the tile has been fertilized.
func _fertilized_note(t: Dictionary) -> String:
	if not t.get("fertilized", false):
		return ""
	return "\nFertilized (+%d%% yield)" % int(float(CropData.FERTILIZER["yield_bonus"]) * 100.0)

# Vehicle settings with the current implement's weight applied (slower with heavy tools).
func _refresh_cfg() -> void:
	cfg = VehicleModel.loaded_config(state.vehicle_cfg(), state.active_implement())

# ---- Machinery shop ----
func _open_shop() -> void:
	if autopilot.active:
		_stop_auto("")
	if hud.has_method("hide"):
		hud.hide()
	rig.set_process_input(false)
	rig.set_process_unhandled_input(false)
	shop_button.hide()
	shop.open(state)

func _on_shop_closed() -> void:
	if hud.has_method("show"):
		hud.show()
	rig.set_process_input(true)
	rig.set_process_unhandled_input(true)
	shop_button.show()
	_update_drive_texts()
	_update_ui()

# A machine was bought or put to use: refresh the vehicle settings, texts and the save.
func _on_shop_changed() -> void:
	if autopilot.active:
		_stop_auto("")
	tool_raised = true
	tractor_view.set_raised(true)
	_refresh_cfg()
	_refresh_parked()
	_update_lift_text()
	_update_drive_texts()
	_update_ui()
	tractor_view.update_from(state.tractor)
	dirty = true

func _update_drive_texts() -> void:
	var tool_name: String = "Header" if state.is_combine() else ImplementData.name_of(state.tractor["implement"])
	var crop_name: String = CropData.CROPS[seed_crop]["name"]
	hud.set_drive_texts(tool_name, crop_name)

# Out of money with nothing to sell and nothing growing: a small grant.
func _check_relief() -> void:
	var given: int = state.relief_grant()
	if given > 0:
		hud.set_message("Farm grant: +%d (you were out of money)" % given, 4000)
		dirty = true
		_update_ui()

# ---- Frame update ----

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if driving:
		_drive(dt)

	if dirty:
		save_timer += delta
		if save_timer >= DRIVE_SAVE_INTERVAL:
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
	_check_relief()

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
	# The autopilot puts the tool down on a work lane and lifts it for turns and travel.
	if autopilot.active and tool_raised == autopilot.working:
		tool_raised = not autopilot.working
		tractor_view.set_raised(tool_raised)
		_update_lift_text()

	# Work only happens with the tool all the way down.
	if ((not autopilot.active) or autopilot.working) and tractor_view.is_down():
		_apply_work()
	elif tool_raised and not autopilot.active and not lift_hint_shown \
			and state.active_kind() != "none" and absf(float(tr["speed"])) > 0.5 \
			and float(tr["z"]) < 1.0 and absf(float(tr["x"])) < 7.0:
		lift_hint_shown = true
		hud.set_message("Tool is up - tap Lower to work", 3500)

	tractor_view.update_from(tr, dt)
	rig.position = Vector3(tr["x"], 0.0, tr["z"])

	# The camera keeps its angle around the tractor (you can drag to orbit freely).
	# It turns along with the tractor, and "Camera: behind" swings it back.
	var heading: float = tr["heading"]
	rig.yaw += angle_difference(last_heading, heading)
	last_heading = heading
	if cam_resetting:
		var target := heading + PI
		rig.yaw = lerp_angle(rig.yaw, target, minf(1.0, 6.0 * dt))
		if absf(angle_difference(rig.yaw, target)) < 0.03:
			cam_resetting = false
	rig.apply_view()

	vehicle_text_timer += dt
	if vehicle_text_timer >= 0.2:
		vehicle_text_timer = 0.0
		hud.set_vehicle_text(_vehicle_text(tr))
	if absf(float(tr["speed"])) > 0.05:
		dirty = true

func _vehicle_text(tr: Dictionary) -> String:
	var secs := int(float(tr["hours"]) * 3600.0)
	return "Fuel %.1f/%d   Speed %.1f/%.1f   Run %d:%02d" % [
		tr["fuel"], int(cfg["fuel_capacity"]), absf(float(tr["speed"])), float(cfg["max_speed"]),
		floori(secs / 60.0), secs % 60]

func _apply_work() -> void:
	var res: String = state.work_with_tractor(cfg, _now(), seed_crop)
	if res == "":
		var worked_n: int = state.last_worked_tiles.size()
		job_worked += worked_n
		pass_worked += worked_n
		for ti in state.last_worked_tiles:
			_refresh_tile(ti)
		_update_ui()
		dirty = true
		_check_relief()
		if state.last_work_error != "":
			if autopilot.active:
				_stop_auto(state.last_work_error)
			else:
				hud.set_message(state.last_work_error)
	elif res != "skip":
		if autopilot.active:
			_stop_auto(res)
		else:
			hud.set_message(res)

func _update_lift_text() -> void:
	hud.set_lift_text(tool_raised, state.is_combine())

# Machines the player owns but is not driving wait in the yard beside the farmhouse.
func _refresh_parked() -> void:
	if parked_root == null:
		parked_root = Node3D.new()
		add_child(parked_root)
	for c in parked_root.get_children():
		parked_root.remove_child(c)
		c.free()
	var current := str(state.tractor.get("vehicle", "tractor"))
	for id in state.owned:
		var sid := str(id)
		if sid == current or not ParkingScript.has_slot(sid):
			continue
		var node: Node3D = MachineModels.parked_vehicle(sid)
		if node == null:
			continue
		var slot: Dictionary = ParkingScript.SLOTS[sid]
		node.position = Vector3(float(slot["x"]), 0.0, float(slot["z"]))
		node.rotation.y = float(slot["heading"])
		parked_root.add_child(node)

# ---- Autopilot ----

func _toggle_auto() -> void:
	if autopilot.active:
		_stop_auto("Autopilot stopped")
		return
	var kind: String = state.active_kind()
	if kind == "none":
		hud.set_message("Pick a tool first")
		return
	var now := _now()
	var jobs: Array = state.jobs_for(kind, now)
	if jobs.is_empty():
		hud.set_message("Nothing to do for this tool")
		return
	if float(state.tractor["fuel"]) < 1.0:
		hud.set_message("Refuel first")
		return
	state.last_work_tile = -1
	auto_pass = 1
	job_worked = 0
	pass_worked = 0
	var width: int = state.active_width()
	if not autopilot.start(state.tractor, jobs, float(cfg["work_offset"]), width, GameStateScript.ROWS):
		return
	hud.set_auto_active(true)
	var note := "Autopilot on"
	if width > 1:
		note = "Autopilot on: %d lanes, %d tiles wide" % [autopilot.lane_count, width]
	var need: float = autopilot.estimate_fuel(state.tractor, cfg)
	if float(state.tractor["fuel"]) < need:
		note = "Autopilot on - low fuel (need ~%d)" % int(ceil(need))
	if float(cfg.get("speed_factor", 1.0)) < 0.8:
		note += " - heavy load, top speed %.1f" % float(cfg["max_speed"])
	if kind == "seeder":
		var n: int = state.count_work(kind, now)
		var cost: int = CropData.CROPS[seed_crop]["seed_cost"]
		if state.money < n * cost:
			note = "Autopilot on - money covers %d of %d tiles" % [int(state.money / cost), n]
	hud.set_message(note, 4000)

func _count_tiles(st: String) -> int:
	var n := 0
	for t in state.tiles:
		if t["state"] == st:
			n += 1
	return n

# What was done, why it stopped and what is left.
func _auto_summary(kind: String) -> String:
	var text := ""
	if autopilot.finished:
		text = "Autopilot finished: %d tiles" % job_worked
	else:
		text = "%s: %d tiles done" % [autopilot.message, job_worked]
	var now := _now()
	if kind == "harvester":
		var ripe: int = state.count_work(kind, now)
		var unripe := _count_tiles("growing") - ripe
		if ripe > 0:
			text += ", %d ripe left" % ripe
		if unripe > 0:
			text += ", %d still growing" % unripe
	elif kind == "seeder":
		var unplanted := _count_tiles("ploughed")
		if unplanted > 0:
			text += ", %d not planted" % unplanted
	elif kind == "plough":
		var raw: int = state.count_work(kind, now)
		if raw > 0:
			text += ", %d not ploughed" % raw
	return text

func _stop_auto(reason: String) -> void:
	var kind: String = state.active_kind()
	autopilot.stop(reason)
	hud.set_auto_active(false)
	tool_raised = true
	tractor_view.set_raised(true)
	_update_lift_text()
	if reason != "":
		hud.set_message(_auto_summary(kind), 5000)
	dirty = true

func _auto_ended() -> void:
	var kind: String = state.active_kind()
	if autopilot.finished:
		# More work may have appeared during the pass (crops ripening, missed
		# tiles). Look again and go where work is still needed, up to 3 passes.
		var jobs: Array = state.jobs_for(kind, _now())
		if not jobs.is_empty() and pass_worked > 0 and auto_pass < 3:
			auto_pass += 1
			pass_worked = 0
			state.last_work_tile = -1
			if autopilot.start(state.tractor, jobs, float(cfg["work_offset"]),
					state.active_width(), GameStateScript.ROWS):
				hud.set_message("Autopilot: pass %d" % auto_pass)
				return
	hud.set_auto_active(false)
	tool_raised = true
	tractor_view.set_raised(true)
	_update_lift_text()
	hud.set_message(_auto_summary(kind), 5000)
	_save()

# ---- Mode switching ----

func _enter_drive() -> void:
	driving = true
	state.tractor["speed"] = 0.0
	var old := selected
	selected = -1
	if old >= 0:
		_refresh_tile(old)
	var heading: float = state.tractor["heading"]
	last_heading = heading
	cam_resetting = false
	rig.allow_rotate = true
	rig.yaw = heading + PI
	rig.pitch = 0.7
	rig.dist = 10.0
	state.last_work_tile = -1
	empty_warned = false
	tool_raised = true
	lift_hint_shown = false
	tractor_view.set_raised(true)
	_update_lift_text()
	vehicle_text_timer = 1.0
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
		_refresh_all_tiles()
		tractor_view.update_from(state.tractor)
		_refresh_parked()
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
	if action.begins_with("quality_"):
		settings["quality"] = clampi(int(action.substr(8)), 0, 2)
		_apply_quality(int(settings["quality"]))
		_refresh_all_tiles()
		SettingsScript.save_settings(settings)
		hud.set_menu_state(int(settings["quality"]), bool(settings["debug"]))
		hud.set_message("Quality: " + QUALITY_NAMES[int(settings["quality"])])
		return
	if action == "debug":
		settings["debug"] = not bool(settings["debug"])
		SettingsScript.save_settings(settings)
		hud.set_debug_visible(bool(settings["debug"]))
		hud.set_menu_state(int(settings["quality"]), bool(settings["debug"]))
		return
	if action == "drive":
		_enter_drive()
		return
	if action == "manage":
		_enter_manage()
		return
	if action == "camera_reset":
		cam_resetting = true
		return
	if action == "auto":
		_toggle_auto()
		return
	if action == "lift":
		if autopilot.active:
			hud.set_message("Autopilot works the tool")
			return
		tool_raised = not tool_raised
		tractor_view.set_raised(tool_raised)
		_update_lift_text()
		return
	if action == "implement_next":
		if state.is_combine():
			hud.set_message("The combine works with its own header")
			return
		if autopilot.active:
			_stop_auto("Tool changed")
		state.next_implement()
		_refresh_cfg()
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
	_check_relief()

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
			"stubble":
				text = head + "Harvested - plough before replanting"
				actions.append("plough")
			"ploughed":
				text = head + "Soil: ploughed\nReady to plant"
				text += _fertilized_note(t)
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
					text += _fertilized_note(t)
	hud.set_tile_text(text)
	hud.show_actions(actions)
