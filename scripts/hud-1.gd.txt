extends CanvasLayer
# On-screen UI: FPS (top-left), money and stock (top-right), messages (top-centre),
# selected-tile panel (bottom-left) and action buttons (bottom-right).

signal action_pressed(action: String)

const CropData := preload("res://scripts/crop_data.gd")

var stats := Label.new()
var status := Label.new()
var msg := Label.new()
var tile_label := Label.new()
var buttons := {}
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

	msg.position = Vector2(vp.x / 2.0 - 250, 70)
	msg.size = Vector2(500, 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 30)
	add_child(msg)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 120)
	panel.position = Vector2(20, vp.y - 140)
	add_child(panel)
	tile_label.add_theme_font_size_override("font_size", 28)
	tile_label.text = "Tap a tile"
	panel.add_child(tile_label)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	box.position = Vector2(vp.x - 360, 130)
	box.size = Vector2(340, vp.y - 150)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_add_button(box, "plough", "Plough")
	for id in CropData.CROPS:
		var c: Dictionary = CropData.CROPS[id]
		_add_button(box, "plant_" + id, "Plant %s (%d)" % [c["name"], c["seed_cost"]])
	_add_button(box, "harvest", "Harvest")
	_add_button(box, "sell", "Sell all")
	show_actions(["sell"])

	var rb := Button.new()
	rb.text = "Reset"
	rb.position = Vector2(20, 56)
	rb.custom_minimum_size = Vector2(150, 56)
	rb.add_theme_font_size_override("font_size", 24)
	rb.pressed.connect(_on_button.bind("reset"))
	add_child(rb)

func _add_button(parent: Control, action: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 84)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(_on_button.bind(action))
	parent.add_child(b)
	buttons[action] = b

func _on_button(action: String) -> void:
	action_pressed.emit(action)

func show_actions(names: Array) -> void:
	for key in buttons:
		buttons[key].visible = key in names

func set_tile_text(t: String) -> void:
	tile_label.text = t

func set_status(t: String) -> void:
	status.text = t

func set_message(t: String) -> void:
	msg.text = t
	msg_until = Time.get_ticks_msec() + 2500

func _process(_delta: float) -> void:
	var mem := OS.get_static_memory_usage() / 1048576.0
	stats.text = "FPS: %d   Mem: %.0f MB" % [Engine.get_frames_per_second(), mem]
	if msg.text != "" and Time.get_ticks_msec() > msg_until:
		msg.text = ""
