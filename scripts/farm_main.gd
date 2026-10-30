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
const MapViewScript := preload("res://scripts/map_view.gd")
const PlotData := preload("res://scripts/plot_data.gd")
const FarmLayout := preload("res://scripts/farm_layout.gd")

const QUALITY_NAMES := ["Low", "Medium", "High"]
const DRIVE_SAVE_INTERVAL := 8.0   # seconds; saving more often can cause hitches on slow storage

var env_setup
var rig
var grid
var hud
var state
var tractor_view          # view of the machine being driven
var autopilot             # autopilot of the machine being driven
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
var map_view              # farm map screen (an overlay)
var map_button: Button
var focus_plot := ""      # the plot the autopilot works; set by tapping a plot or on the map
var selected_plot := ""   # the plot that was tapped (owned or for sale)
var refresh_pos := 0      # where the slow crop refresh continues
var machines := {}       # vehicle id -> {"view", "ap", "cfg", "cfg_impl"}: every machine runs at once
var vehicle_text_timer := 0.0
var last_heading := 0.0
var cam_resetting := false
var lift_hint_shown := false

func _ready() -> void:
	settings = SettingsScript.load_settings()

	env_setup = EnvironmentSetupScript.new()
	add_child(env_setup)

	cfg = VehicleData.VEHICLES["tractor"]
	state = GameStateScript.new()
	var load_result: String = SaveManager.load_into(state)

	grid = FarmGridScript.new()
	add_child(grid)
	for pid in state.plots:
		grid.build_plot(str(pid))

	_sync_machines()

	rig = CameraRigScript.new()
	rig.position = Vector3(0, 0, -7)
	rig.max_dist = 140.0
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

	# Farm map: a "Map" button under the Shop button and a full-screen overlay.
	map_button = Button.new()
	map_button.text = "Map"
	map_button.add_theme_font_size_override("font_size", 26)
	map_button.anchor_left = 1.0
	map_button.anchor_right = 1.0
	map_button.offset_left = -190.0
	map_button.offset_right = -20.0
	map_button.offset_top = 184.0
	map_button.offset_bottom = 248.0
	map_button.pressed.connect(_open_map)
	shop_layer.add_child(map_button)
	map_view = MapViewScript.new()
	shop_layer.add_child(map_view)
	map_view.plot_bought.connect(_on_plot_bought)
	map_view.go_requested.connect(_on_map_go)
	map_view.send_requested.connect(_on_map_send)
	map_view.closed.connect(_on_map_closed)

	_refresh_all_tiles()
	_update_drive_texts()
	_update_lift_text()
	_update_machine_text()
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
	grid.set_quality(q)
	grid.set_blob_shadows(q == 0)
	for id in machines:
		machines[id]["view"].set_blob_visible(q == 0)

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

# Vehicle settings of the machine being driven, with its tool's weight applied.
func _refresh_cfg() -> void:
	var id := _active_id()
	if machines.has(id):
		machines[id]["cfg_impl"] = "?"
		cfg = _cfg_for(id)

func _active_id() -> String:
	return str(state.tractor.get("vehicle", "tractor"))

# Vehicle settings of any machine, with its tool's weight applied (cached until the tool changes).
func _cfg_for(id: String) -> Dictionary:
	var rt: Dictionary = machines[id]
	var impl: String = state.machine_implement(state.fleet[id])
	if str(rt["cfg_impl"]) != impl:
		rt["cfg"] = VehicleModel.loaded_config(VehicleData.VEHICLES[id], impl)
		rt["cfg_impl"] = impl
	return rt["cfg"]

func _machine_name(id: String) -> String:
	return str(VehicleData.VEHICLES[id]["name"])

# Every machine of the fleet gets its own view and its own autopilot, so they can all work
# at once. Machines that are gone lose theirs.
func _sync_machines() -> void:
	for id in state.fleet:
		if not machines.has(id):
			var view = TractorViewScript.new()
			add_child(view)
			view.update_from(state.fleet[id])
			if settings.has("quality"):
				view.set_blob_visible(int(settings["quality"]) == 0)
			machines[id] = {"view": view, "ap": AutoPilotScript.new(), "cfg": {}, "cfg_impl": "?"}
	for id in machines.keys():
		if not state.fleet.has(id):
			machines[id]["view"].queue_free()
			machines.erase(id)
	_bind_active()

# Points tractor_view / autopilot / cfg at the machine being driven.
func _bind_active() -> void:
	var id := _active_id()
	tractor_view = machines[id]["view"]
	autopilot = machines[id]["ap"]
	_refresh_cfg()

func _open_shop() -> void:
	if hud.has_method("hide"):
		hud.hide()
	rig.set_process_input(false)
	rig.set_process_unhandled_input(false)
	shop_button.hide()
	map_button.hide()
	shop.open(state)

func _on_shop_closed() -> void:
	if hud.has_method("show"):
		hud.show()
	rig.set_process_input(true)
	rig.set_process_unhandled_input(true)
	shop_button.show()
	map_button.show()
	_update_drive_texts()
	_update_ui()

# ---- Farm map ----

func _open_map() -> void:
	if hud.has_method("hide"):
		hud.hide()
	rig.set_process_input(false)
	rig.set_process_unhandled_input(false)
	shop_button.hide()
	map_button.hide()
	map_view.open(state, _active_id(), _machine_name(_active_id()), _work_plot())

func _on_map_closed() -> void:
	if hud.has_method("show"):
		hud.show()
	rig.set_process_input(true)
	rig.set_process_unhandled_input(true)
	shop_button.show()
	map_button.show()
	_update_ui()

# A plot was bought on the map: draw its tiles, and save.
func _on_plot_bought(id: String) -> void:
	grid.build_plot(id)
	_refresh_all_tiles()
	dirty = true
	_save()

# "Look at plot": the camera moves over the plot and the autopilot will work it.
func _on_map_go(id: String) -> void:
	if driving:
		_enter_manage()
	var r := PlotData.rect_of(id)
	rig.position = Vector3(r.get_center().x, 0.0, r.get_center().y)
	rig.dist = clampf(maxf(r.size.x, r.size.y) * 0.75, 14.0, 130.0)
	rig.pitch = 0.9
	rig.apply_view()
	if state.owns_plot(id):
		focus_plot = id
		hud.set_message("%s: autopilot will work this plot" % str(PlotData.get_plot(id)["name"]), 3500)
	else:
		hud.set_message("%s is for sale: open the map to buy it" % str(PlotData.get_plot(id)["name"]), 3500)

# "Send machine here": the machine you are using drives to the plot on autopilot (no work).
func _on_map_send(id: String) -> void:
	var mid := _active_id()
	var ap = machines[mid]["ap"]
	if float(state.tractor["fuel"]) < 1.0:
		hud.set_message("Refuel first")
		return
	if ap.active:
		_stop_auto("")
	focus_plot = id
	state.last_work_tile = -1
	if ap.travel_to_plot(state.tractor, id):
		hud.set_auto_active(true)
		hud.set_message("%s is driving to %s" % [_machine_name(mid), str(PlotData.get_plot(id)["name"])], 3500)
	else:
		hud.set_message("Cannot drive there")

# The plot the autopilot works: the one picked on the map or by tapping a tile, otherwise the
# plot the machine is in (or nearest to).
func _work_plot() -> String:
	if focus_plot != "" and state.owns_plot(focus_plot):
		return focus_plot
	var m: Dictionary = state.tractor
	var here := FarmLayout.plot_at(float(m["x"]), float(m["z"]), state.plots)
	if here != "":
		return here
	return FarmLayout.nearest_plot(float(m["x"]), float(m["z"]), state.plots)

# What the info box says about a plot: its size and what is on it, in percent (never in tiles).
func _plot_text(id: String, now: float) -> String:
	var p := PlotData.get_plot(id)
	var n := PlotData.tile_count(id)
	var head := "%s\n%s plot, %s\n" % [str(p["name"]), str(p["size"]), PlotData.ha_text(n)]
	if not state.owns_plot(id):
		return head + "For sale: %d\nOpen the Map to buy it" % PlotData.price_of(id)
	var st: Dictionary = state.plot_status(id, now)
	var lines: Array = []
	if int(st["ripe"]) > 0:
		lines.append("Ripe, ready to harvest: %s" % _pct(int(st["ripe"]), n))
	if int(st["growing"]) > 0:
		lines.append("%s growing: %s" % [_main_crop(id), _pct(int(st["growing"]), n)])
	if int(st["ploughed"]) > 0:
		lines.append("Ploughed, ready to plant: %s" % _pct(int(st["ploughed"]), n))
	if int(st["empty"]) > 0:
		lines.append("Not ploughed: %s" % _pct(int(st["empty"]), n))
	return head + "\n".join(lines)

func _pct(part: int, whole: int) -> String:
	if whole <= 0 or part <= 0:
		return "0%"
	return "%d%%" % maxi(1, int(round(100.0 * float(part) / float(whole))))

# The crop most of the growing tiles of a plot are.
func _main_crop(id: String) -> String:
	var counts := {}
	var start: int = state.plot_start(id)
	for i in range(start, start + PlotData.tile_count(id)):
		if state.tiles[i]["state"] == "growing":
			var c: String = state.tiles[i]["crop"]
			counts[c] = int(counts.get(c, 0)) + 1
	var best := ""
	var best_n := 0
	for c in counts:
		if int(counts[c]) > best_n:
			best_n = int(counts[c])
			best = str(c)
	if best == "" or not CropData.CROPS.has(best):
		return "Crops"
	return str(CropData.CROPS[best]["name"])

# A machine was bought or put to use: refresh the machines, texts and the save.
func _on_shop_changed() -> void:
	if autopilot.active:
		_stop_auto("")
	_sync_machines()
	_update_lift_text()
	_update_machine_text()
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
	_simulate(dt)
	if driving:
		_drive_view(dt)

	if dirty:
		save_timer += delta
		if save_timer >= DRIVE_SAVE_INTERVAL:
			save_timer = 0.0
			_save()

	refresh_timer += delta
	if refresh_timer < 0.5:
		return
	refresh_timer = 0.0
	# Growing crops change look slowly: refresh a slice of the tiles each time, round and round.
	var n: int = state.tiles.size()
	if n > 0:
		var slice: int = mini(n, 600)
		for k in slice:
			var i: int = (refresh_pos + k) % n
			if state.tiles[i]["state"] == "growing":
				_refresh_tile(i)
		refresh_pos = (refresh_pos + slice) % n
	if selected_plot != "":
		_update_ui()
	_check_relief()

# Every machine moves every frame: the one you drive follows your controls, the others follow
# their autopilot (or stand still).
func _simulate(dt: float) -> void:
	var act := _active_id()
	for id in state.fleet.keys():
		if not machines.has(id):
			continue
		if id == act and driving:
			_run_machine(id, dt, hud.get_throttle(), hud.get_steer(), true, hud.get_brake())
		else:
			_run_machine(id, dt, 0.0, 0.0, false)

# One machine for one frame: autopilot or controls, physics (other machines are solid), the
# tool going down or up, the work itself, and its picture.
func _run_machine(id: String, dt: float, thr_in: float, st_in: float, manual: bool, brk_in: float = 0.0) -> void:
	var m: Dictionary = state.fleet[id]
	var rt: Dictionary = machines[id]
	var ap = rt["ap"]
	var view = rt["view"]
	var mcfg: Dictionary = _cfg_for(id)
	var thr := thr_in
	var st := st_in

	if ap.active:
		if manual and (absf(thr) > 0.2 or absf(st) > 0.2 or brk_in > 0.2):
			_stop_auto("Manual control", id)
		else:
			ap.holding = bool(m.get("_blocked", false))
			var ctl: Vector2 = ap.update(m, dt, mcfg)
			thr = ctl.x
			st = ctl.y
			if not ap.active:
				_auto_ended(id)

	# The tool's load only slows the machine while it is down and working; raised, it only adds weight.
	m["_working"] = not view.raised
	m["_brake"] = 0.0 if ap.active else brk_in   # brake pedal / handbrake (0 to 1); the autopilot never brakes this way
	VehicleModel.step(m, mcfg, thr, st, dt, state.others_of(id))

	if id == _active_id():
		if float(m["fuel"]) <= 0.0 and not empty_warned:
			empty_warned = true
			hud.set_message("Out of fuel - tap Refuel")
		elif float(m["fuel"]) > 0.0:
			empty_warned = false

	# The autopilot puts the tool down on a work lane and lifts it for turns and travel.
	if ap.active and view.raised == ap.working:
		view.set_raised(not ap.working)
		if id == _active_id():
			_update_lift_text()

	# Work only happens with the tool all the way down.
	if ((not ap.active) or ap.working) and view.is_down():
		_apply_work(id)
	elif manual and view.raised and not ap.active and not lift_hint_shown \
			and state.machine_kind(m) != "none" and absf(float(m["speed"])) > 0.5 \
			and float(m["z"]) < 1.0 and absf(float(m["x"])) < 7.0:
		lift_hint_shown = true
		hud.set_message("Tool is up - tap Lower to work", 3500)

	view.update_from(m, dt)
	if absf(float(m["speed"])) > 0.05:
		dirty = true

# Camera and readouts follow the machine being driven.
func _drive_view(dt: float) -> void:
	var tr: Dictionary = state.tractor
	rig.position = Vector3(tr["x"], 0.0, tr["z"])

	# The camera keeps its angle around the machine (you can drag to orbit freely).
	# It turns along with it, and "Camera: behind" swings it back.
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

func _vehicle_text(tr: Dictionary) -> String:
	var secs := int(float(tr["hours"]) * 3600.0)
	return "Fuel %.1f/%d   Speed %.1f/%.1f   Run %d:%02d" % [
		tr["fuel"], int(cfg["fuel_capacity"]), absf(float(tr["speed"])), float(cfg["max_speed"]),
		floori(secs / 60.0), secs % 60]

# A message about one machine: plain for the machine you drive, named for the others.
func _say(id: String, text: String) -> void:
	if id == _active_id():
		hud.set_message(text)
	else:
		hud.set_message("%s: %s" % [_machine_name(id), text])

func _apply_work(id: String) -> void:
	var m: Dictionary = state.fleet[id]
	var ap = machines[id]["ap"]
	var res: String = state.work_with_tractor(_cfg_for(id), _now(), seed_crop, m)
	if res == "":
		var worked_n: int = state.last_worked_tiles.size()
		ap.job_worked += worked_n
		ap.pass_worked += worked_n
		for ti in state.last_worked_tiles:
			_refresh_tile(ti)
		_update_ui()
		dirty = true
		_check_relief()
		if state.last_work_error != "":
			if ap.active:
				_stop_auto(state.last_work_error, id)
			else:
				_say(id, state.last_work_error)
	elif res != "skip":
		if ap.active:
			_stop_auto(res, id)
		else:
			_say(id, res)

func _update_lift_text() -> void:
	hud.set_lift_text(tractor_view.raised, state.is_combine())

func _update_machine_text() -> void:
	var ids: Array = state.machine_ids()
	hud.set_machine_text(_machine_name(_active_id()), maxi(0, ids.find(_active_id())), ids.size())

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
	var plot := _work_plot()
	var skip := _rows_taken(_active_id(), kind, plot)
	var jobs: Array = state.jobs_for(kind, now, skip, plot)
	if jobs.is_empty():
		if skip.is_empty():
			hud.set_message("Nothing to do for this tool")
		else:
			hud.set_message("Other machines are working the rest")
		return
	if float(state.tractor["fuel"]) < 1.0:
		hud.set_message("Refuel first")
		return
	state.last_work_tile = -1
	autopilot.kind = kind
	autopilot.pass_no = 1
	autopilot.job_worked = 0
	autopilot.pass_worked = 0
	var width: int = state.active_width()
	if not autopilot.start(state.tractor, jobs, float(cfg["work_offset"]), width, int(PlotData.get_plot(plot)["rows"]), plot):
		return
	hud.set_auto_active(true)
	var note := "Autopilot on: %s" % str(PlotData.get_plot(plot)["name"])
	if width > 1:
		note = "Autopilot on: %s, %d lanes, %.1f m wide" % [str(PlotData.get_plot(plot)["name"]), autopilot.lane_count, float(width) * PlotData.PITCH]
	var need: float = autopilot.estimate_fuel(state.tractor, cfg)
	if float(state.tractor["fuel"]) < need:
		note = "Autopilot on - low fuel (need ~%d)" % int(ceil(need))
	if float(cfg.get("speed_factor", 1.0)) < 0.8:
		note += " - heavy load, top speed %.1f" % float(cfg["max_speed"])
	if kind == "seeder":
		var n: int = state.count_work(kind, now)
		var cost: int = CropData.CROPS[seed_crop]["seed_cost"]
		if state.money < n * cost:
			note = "Autopilot on - money covers %s of %s" % [PlotData.ha_text(int(state.money / cost)), PlotData.ha_text(n)]
	hud.set_message(note, 4000)

# Field rows other machines of the same kind are already working, so a second machine takes
# the rest of the field instead of driving into the first.
func _rows_taken(except_id: String, kind: String, plot: String = "farm") -> Array:
	var rows: Array = []
	for oid in machines:
		if oid == except_id:
			continue
		var oap = machines[oid]["ap"]
		if oap.active and oap.kind == kind and oap.plot_id == plot:
			for r in oap.reserved_rows:
				if not rows.has(r):
					rows.append(r)
	return rows

func _count_tiles(st: String) -> int:
	var n := 0
	for t in state.tiles:
		if t["state"] == st:
			n += 1
	return n

# What was done, why it stopped and what is left.
func _auto_summary(kind: String, ap = null) -> String:
	if ap == null:
		ap = autopilot
	var text := ""
	if kind == "travel":
		return "Arrived at %s" % str(PlotData.get_plot(ap.plot_id)["name"]) if ap.finished else "%s" % ap.message
	if ap.finished:
		text = "Autopilot finished: %s" % PlotData.ha_text(ap.job_worked)
	else:
		text = "%s: %s done" % [ap.message, PlotData.ha_text(ap.job_worked)]
	var now := _now()
	var st: Dictionary = state.plot_status(ap.plot_id, now)
	if kind == "harvester":
		if int(st["ripe"]) > 0:
			text += ", %s ripe left" % PlotData.ha_text(int(st["ripe"]))
		if int(st["growing"]) > 0:
			text += ", %s still growing" % PlotData.ha_text(int(st["growing"]))
	elif kind == "seeder":
		if int(st["ploughed"]) > 0:
			text += ", %s not planted" % PlotData.ha_text(int(st["ploughed"]))
	elif kind == "plough":
		if int(st["empty"]) > 0:
			text += ", %s not ploughed" % PlotData.ha_text(int(st["empty"]))
	return text

# Stops a machine's autopilot (the machine being driven when id is empty) and lifts its tool.
func _stop_auto(reason: String, id: String = "") -> void:
	if id == "":
		id = _active_id()
	var ap = machines[id]["ap"]
	var kind: String = ap.kind
	ap.stop(reason)
	machines[id]["view"].set_raised(true)
	if id == _active_id():
		hud.set_auto_active(false)
		_update_lift_text()
	if reason != "":
		_say(id, _auto_summary(kind, ap))
	dirty = true

func _auto_ended(id: String = "") -> void:
	if id == "":
		id = _active_id()
	var ap = machines[id]["ap"]
	var m: Dictionary = state.fleet[id]
	var kind: String = ap.kind
	if ap.finished:
		# More work may have appeared during the pass (crops ripening, missed
		# tiles). Look again and go where work is still needed, up to 3 passes.
		var jobs: Array = state.jobs_for(kind, _now(), _rows_taken(id, kind, ap.plot_id), ap.plot_id)
		if kind != "travel" and not jobs.is_empty() and ap.pass_worked > 0 and ap.pass_no < 3:
			ap.pass_no += 1
			ap.pass_worked = 0
			m["_lwt"] = -1
			if ap.start(m, jobs, float(_cfg_for(id)["work_offset"]), state.machine_width(m), int(PlotData.get_plot(ap.plot_id)["rows"]), ap.plot_id):
				_say(id, "Autopilot: pass %d" % ap.pass_no)
				return
	machines[id]["view"].set_raised(true)
	if id == _active_id():
		hud.set_auto_active(false)
		_update_lift_text()
	_say(id, _auto_summary(kind, ap))
	_save()

# ---- Mode switching ----

func _enter_drive() -> void:
	driving = true
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
	empty_warned = false
	lift_hint_shown = false
	_update_lift_text()
	_update_machine_text()
	vehicle_text_timer = 1.0
	hud.set_drive_mode(true)
	hud.set_auto_active(autopilot.active)
	_update_drive_texts()
	_update_ui()

# Back to the overview. Machines on autopilot keep working; the one you were driving stops.
func _enter_manage() -> void:
	hud.set_auto_active(false)
	driving = false
	rig.allow_rotate = true
	rig.position = Vector3(0, 0, -7)
	rig.yaw = 0.5
	rig.pitch = 0.9
	rig.dist = 18.0
	rig.apply_view()
	hud.set_drive_mode(false)
	_save()
	_update_ui()

# ---- Switching machines ----

# Takes the wheel of the next (or previous) owned machine without going back to the shop.
func _switch_machine(step: int) -> void:
	var ids: Array = state.machine_ids()
	if ids.size() < 2:
		hud.set_message("Only one machine - buy more in the shop")
		return
	var i := ids.find(_active_id())
	_activate(str(ids[posmod(i + step, ids.size())]))

func _activate(id: String) -> void:
	if state.select_vehicle(id) != "":
		return
	_bind_active()
	var tr: Dictionary = state.tractor
	last_heading = float(tr["heading"])
	cam_resetting = false
	empty_warned = false
	lift_hint_shown = false
	if driving:
		rig.position = Vector3(tr["x"], 0.0, tr["z"])
		rig.yaw = last_heading + PI
		rig.apply_view()
	hud.set_auto_active(autopilot.active)
	_update_lift_text()
	_update_machine_text()
	_update_drive_texts()
	vehicle_text_timer = 1.0
	_update_ui()
	dirty = true

# ---- Input ----

func _on_tapped(pos: Vector2) -> void:
	if driving:
		return
	var hit = rig.ray_to_ground(pos)
	var pid := ""
	if hit != null:
		pid = _plot_under(hit.x, hit.z)
	selected_plot = pid
	if pid != "" and state.owns_plot(pid):
		focus_plot = pid
	if pid != "":
		grid.show_plot_frame(pid)
	else:
		grid.hide_plot_frame()
	_update_ui()

# The plot (owned or for sale) at a point on the ground, or "".
func _plot_under(x: float, z: float) -> String:
	for p in PlotData.PLOTS:
		if PlotData.rect_of(str(p["id"])).grow(0.5).has_point(Vector2(x, z)):
			return str(p["id"])
	return ""

func _handle_reset() -> void:
	var t := Time.get_ticks_msec()
	if t < reset_armed_until:
		reset_armed_until = 0
		for id in machines:
			machines[id]["ap"].stop("")
			machines[id]["view"].queue_free()
		machines = {}
		state = GameStateScript.new()
		grid.reset_plots()
		focus_plot = ""
		selected_plot = ""
		selected = -1
		_refresh_all_tiles()
		_sync_machines()
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
		tractor_view.set_raised(not tractor_view.raised)
		_update_lift_text()
		return
	if action == "machine_prev":
		_switch_machine(-1)
		return
	if action == "machine_next" or action == "machine_next2":
		_switch_machine(1)
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
	var text := "Tap a plot"
	if selected_plot != "":
		text = _plot_text(selected_plot, now)
	hud.set_tile_text(text)
	hud.show_actions(actions)
