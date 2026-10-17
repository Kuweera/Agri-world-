extends CanvasLayer
# On-screen UI.
# Manage mode: tile panel (bottom-left) + action buttons (bottom-right).
# Drive mode: steering and throttle strips, tool buttons (left), vehicle readout (top).

signal action_pressed(action: String)

const CropData := preload("res://scripts/crop_data.gd")
const DriveControlsScript := preload("res://scripts/drive_controls.gd")

var stats := Label.new()
var status := Label.new()
var msg := Label.new()
var vehicle_label := Label.new()
var tile_panel := PanelContainer.new()
var tile_label := Label.new()
var action_box := VBoxContainer.new()
var drive_box := VBoxContainer.new()
var buttons := {}
var drive_buttons := {}
var drive_controls
var msg_until := 0

func _ready() -> void:
	var vp := get_viewport().get_visible_rect().size

	stats.position = Vector2(20, 16)
	stats.add_theme_font_size_override("font_size", 22)
	add_child(stats)

	status.position = Vector2(vp.x - 520, 16)
	status.size = Vector2(500, 100)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override("font_size", 28)
	add_child(status)

	msg.position = Vector2(vp.x / 2.0 - 450, 70)
	msg.size = Vector2(900, 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 30)
	add_child(msg)

	vehicle_label.position = Vector2(vp.x / 2.0 - 300, 116)
	vehicle_label.size = Vector2(600, 40)
	vehicle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vehicle_label.add_theme_font_size_override("font_size", 26)
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
	drive_box.size = Vector2(320, 360)
	drive_box.add_theme_constant_override("separation", 8)
	add_child(drive_box)
	_add_button(drive_box, drive_buttons, "implement_next", "Tool: None", 320.0, 64.0, 26)
	_add_button(drive_box, drive_buttons, "seed_next", "Seed: Maize", 320.0, 64.0, 26)
	_add_button(drive_box, drive_buttons, "auto", "Auto: Start", 320.0, 64.0, 26)
	_add_button(drive_box, drive_buttons, "refuel", "Refuel", 320.0, 64.0, 26)
	_add_button(drive_box, drive_buttons, "manage", "Manage view", 320.0, 64.0, 26)

	drive_controls = DriveControlsScript.new()
	add_child(drive_controls)

	# Always visible
	var rb := Button.new()
	rb.text = "Reset"
	rb.position = Vector2(20, 56)
	rb.custom_minimum_size = Vector2(150, 56)
	rb.add_theme_font_size_override("font_size", 24)
	rb.pressed.connect(_on_button.bind("reset"))
	add_child(rb)

	show_actions(["sell", "drive"])
	set_drive_mode(false)

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

func set_auto_active(on: bool) -> void:
	drive_buttons["auto"].text = "Auto: Stop" if on else "Auto: Start"

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

func _process(_delta: float) -> void:
	var mem := OS.get_static_memory_usage() / 1048576.0
	stats.text = "FPS: %d   Mem: %.0f MB" % [Engine.get_frames_per_second(), mem]
	if msg.text != "" and Time.get_ticks_msec() > msg_until:
		msg.text = ""
