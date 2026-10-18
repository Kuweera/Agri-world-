extends CanvasLayer
# On-screen UI.
# Always: debug readout (top-left), Menu button, Money/Stock (top-right), messages.
# Manage mode: tile panel (bottom-left) + action buttons (bottom-right).
# Drive mode: steering and throttle strips, tool buttons (left), vehicle readout (top).
# Menu: graphics quality, debug readout on/off, reset farm.

signal action_pressed(action: String)

const CropData := preload("res://scripts/crop_data.gd")
const DriveControlsScript := preload("res://scripts/drive_controls.gd")
const QUALITY_NAMES := ["Low", "Medium", "High"]

var stats := Label.new()
var status := Label.new()
var msg := Label.new()
var vehicle_label := Label.new()
var tile_panel := PanelContainer.new()
var tile_label := Label.new()
var action_box := VBoxContainer.new()
var drive_box := VBoxContainer.new()
var menu_panel := PanelContainer.new()
var quality_buttons: Array = []
var debug_button: Button
var buttons := {}
var drive_buttons := {}
var drive_controls
var msg_until := 0
var frame_times := PackedFloat32Array()
var ft_idx := 0
var stats_timer := 0.0

func _style(l: Label, font_size: int) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)

func _ready() -> void:
	var vp := get_viewport().get_visible_rect().size
	frame_times.resize(300)
	frame_times.fill(1.0 / 60.0)

	stats.position = Vector2(20, 16)
	_style(stats, 20)
	add_child(stats)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.position = Vector2(20, 56)
	menu_btn.custom_minimum_size = Vector2(150, 56)
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.pressed.connect(_on_button.bind("menu"))
	add_child(menu_btn)

	status.position = Vector2(vp.x - 520, 16)
	status.size = Vector2(500, 100)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(status, 28)
	add_child(status)

	msg.position = Vector2(vp.x / 2.0 - 450, 70)
	msg.size = Vector2(900, 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(msg, 30)
	add_child(msg)

	vehicle_label.position = Vector2(vp.x / 2.0 - 300, 116)
	vehicle_label.size = Vector2(600, 40)
	vehicle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(vehicle_label, 26)
	add_child(vehicle_label)

	# Manage mode widgets
	tile_panel.custom_minimum_size = Vector2(420, 120)
	tile_panel.position = Vector2(20, vp.y - 140)
	add_child(tile_panel)
	tile_label.add_theme_font_size_override("font_size", 28)
	tile_label.text = "Tap a tile"
	tile_panel.add_child(tile_label)

	action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_box.alignment = BoxContainer.ALIGNMENT_END
	action_box.position = Vector2(vp.x - 360, 130)
	action_box.size = Vector2(340, vp.y - 150)
	action_box.add_theme_constant_override("separation", 10)
	add_child(action_box)
	_add_button(action_box, buttons, "drive", "Drive tractor")
	_add_button(action_box, buttons, "plough", "Plough")
	for id in CropData.CROPS:
		var c: Dictionary = CropData.CROPS[id]
		_add_button(action_box, buttons, "plant_" + id, "Plant %s (%d)" % [c["name"], c["seed_cost"]])
	_add_button(action_box, buttons, "harvest", "Harvest")
	_add_button(action_box, buttons, "sell", "Sell all")

	# Drive mode widgets
	drive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drive_box.position = Vector2(20, 130)
	drive_box.size = Vector2(320, 390)
	drive_box.add_theme_constant_override("separation", 6)
	add_child(drive_box)
	_add_button(drive_box, drive_buttons, "implement_next", "Tool: None", 320.0, 58.0, 24)
	_add_button(drive_box, drive_buttons, "seed_next", "Seed: Maize", 320.0, 58.0, 24)
	_add_button(drive_box, drive_buttons, "auto", "Auto: Start", 320.0, 58.0, 24)
	_add_button(drive_box, drive_buttons, "refuel", "Refuel", 320.0, 58.0, 24)
	_add_button(drive_box, drive_buttons, "camera_reset", "Camera: behind", 320.0, 58.0, 24)
	_add_button(drive_box, drive_buttons, "manage", "Manage view", 320.0, 58.0, 24)

	drive_controls = DriveControlsScript.new()
	add_child(drive_controls)

	_build_menu(vp)

	show_actions(["sell", "drive"])
	set_drive_mode(false)

func _build_menu(vp: Vector2) -> void:
	menu_panel.custom_minimum_size = Vector2(620, 0)
	menu_panel.position = Vector2(vp.x / 2.0 - 310, vp.y / 2.0 - 220)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	menu_panel.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)

	var q_label := Label.new()
	q_label.text = "Graphics quality (Medium and High add shadows)"
	q_label.add_theme_font_size_override("font_size", 22)
	box.add_child(q_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for q in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_on_button.bind("quality_%d" % q))
		row.add_child(b)
		quality_buttons.append(b)

	debug_button = Button.new()
	debug_button.custom_minimum_size = Vector2(590, 64)
	debug_button.add_theme_font_size_override("font_size", 26)
	debug_button.pressed.connect(_on_button.bind("debug"))
	box.add_child(debug_button)

	var reset_btn := Button.new()
	reset_btn.text = "Reset farm (tap twice)"
	reset_btn.custom_minimum_size = Vector2(590, 64)
	reset_btn.add_theme_font_size_override("font_size", 26)
	reset_btn.pressed.connect(_on_button.bind("reset"))
	box.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(590, 64)
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.pressed.connect(_on_button.bind("close_menu"))
	box.add_child(close_btn)

	menu_panel.visible = false
	add_child(menu_panel)
	set_menu_state(0, true)

func _add_button(parent: Control, store: Dictionary, action: String, text: String,
		w := 340.0, h := 84.0, font_size := 30) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(_on_button.bind(action))
	parent.add_child(b)
	store[action] = b

func _on_button(action: String) -> void:
	if action == "menu":
		menu_panel.visible = not menu_panel.visible
		return
	if action == "close_menu":
		menu_panel.visible = false
		return
	action_pressed.emit(action)

func show_actions(names: Array) -> void:
	for key in buttons:
		buttons[key].visible = key in names

func set_drive_mode(on: bool) -> void:
	tile_panel.visible = not on
	action_box.visible = not on
	drive_box.visible = on
	vehicle_label.visible = on
	drive_controls.visible = on
	drive_controls.reset()

func set_drive_texts(tool_name: String, seed_name: String) -> void:
	drive_buttons["implement_next"].text = "Tool: " + tool_name
	drive_buttons["seed_next"].text = "Seed: " + seed_name

# The strips stay active during Auto (touching one takes control back) but are dimmed.
func set_auto_active(on: bool) -> void:
	drive_buttons["auto"].text = "Auto: Stop" if on else "Auto: Start"
	drive_controls.modulate.a = 0.45 if on else 1.0

func set_menu_state(quality: int, debug_on: bool) -> void:
	for q in quality_buttons.size():
		var label: String = QUALITY_NAMES[q]
		quality_buttons[q].text = "[%s]" % label if q == quality else label
	debug_button.text = "Debug info: %s" % ("On" if debug_on else "Off")

func set_debug_visible(on: bool) -> void:
	stats.visible = on

func set_vehicle_text(t: String) -> void:
	vehicle_label.text = t

func get_steer() -> float:
	return drive_controls.steer

func get_throttle() -> float:
	return drive_controls.throttle

func set_tile_text(t: String) -> void:
	tile_label.text = t

func set_status(t: String) -> void:
	status.text = t

func set_message(t: String, ms: int = 2500) -> void:
	msg.text = t
	msg_until = Time.get_ticks_msec() + ms

func _process(delta: float) -> void:
	# Rolling 300-frame window: current, average and lowest FPS.
	frame_times[ft_idx] = delta
	ft_idx = (ft_idx + 1) % frame_times.size()
	stats_timer += delta
	if stats_timer >= 0.5:
		stats_timer = 0.0
		var total := 0.0
		var worst := 0.0
		for t in frame_times:
			total += t
			worst = maxf(worst, t)
		var avg_fps := float(frame_times.size()) / maxf(total, 0.001)
		var low_fps := 1.0 / maxf(worst, 0.001)
		var mem := OS.get_static_memory_usage() / 1048576.0
		stats.text = "FPS %d (avg %d, low %d)  Mem %.0f MB" % [
			Engine.get_frames_per_second(), int(avg_fps), int(low_fps), mem]
	if msg.text != "" and Time.get_ticks_msec() > msg_until:
		msg.text = ""
