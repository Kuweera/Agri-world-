extends Control
# The farm map: every plot (owned and for sale), the main road, the farmhouse and the machines.
# Owned plots show their tiles: gold = ripe and ready, green = still growing, brown = soil.
# Tap a plot to see its details. From there: buy it, look at it, or send the machine you are
# using to it on autopilot. Built in code (no scene file). Call open(state, machine_name).
# Signals: plot_bought(id), go_requested(id), send_requested(id), closed.

signal plot_bought(id: String)
signal go_requested(id: String)
signal send_requested(id: String)
signal closed

const PlotData := preload("res://scripts/plot_data.gd")
const CropData := preload("res://scripts/crop_data.gd")

const FONT := 24

var state
var machine_name := ""
var selected := ""
var canvas: MapCanvas
var machine_id := ""
var title_label: Label
var info_label: Label
var money_label: Label
var message_label: Label
var buy_button: Button
var go_button: Button
var send_button: Button

# The map canvas draws everything and reports taps.
class MapCanvas extends Control:
	signal plot_tapped(id: String)
	const PlotData := preload("res://scripts/plot_data.gd")
	const X0 := -92.0
	const X1 := 92.0
	const Z0 := -28.0
	const Z1 := 27.0
	var state
	var selected := ""
	var active_id := ""
	var now := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _map_scale() -> float:
		return minf(size.x / (X1 - X0), size.y / (Z1 - Z0))

	func _origin() -> Vector2:
		var s := _map_scale()
		return (size - Vector2((X1 - X0) * s, (Z1 - Z0) * s)) / 2.0

	func _to_screen(x: float, z: float) -> Vector2:
		return _origin() + Vector2((x - X0), (z - Z0)) * _map_scale()

	func _to_world(p: Vector2) -> Vector2:
		var w := (p - _origin()) / _map_scale()
		return Vector2(w.x + X0, w.y + Z0)

	func _rect_on_screen(r: Rect2) -> Rect2:
		return Rect2(_to_screen(r.position.x, r.position.y), r.size * _map_scale())

	func _gui_input(event: InputEvent) -> void:
		var pos := Vector2.ZERO
		var hit := false
		var mb := event as InputEventMouseButton
		var st := event as InputEventScreenTouch
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.position
			hit = true
		elif st != null and st.pressed:
			pos = st.position
			hit = true
		if not hit:
			return
		var w := _to_world(pos)
		for p in PlotData.PLOTS:
			if PlotData.rect_of(str(p["id"])).grow(0.6).has_point(w):
				plot_tapped.emit(str(p["id"]))
				return

	func _tile_color(i: int) -> Color:
		var t: Dictionary = state.tiles[i]
		match str(t["state"]):
			"ploughed":
				return Color(0.3, 0.2, 0.12)
			"stubble":
				return Color(0.62, 0.56, 0.34)
			"growing":
				if state.is_ripe(i, now):
					return Color(1.0, 0.84, 0.18)
				return Color(0.28, 0.62, 0.26).lerp(Color(0.6, 0.78, 0.25), state.progress(i, now))
		return Color(0.46, 0.37, 0.25)

	func _text(pos: Vector2, text: String, size_px: int, col: Color) -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.7))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)

	func _draw() -> void:
		if state == null:
			return
		var s := _map_scale()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.3, 0.16))
		draw_rect(_rect_on_screen(Rect2(X0, Z0, X1 - X0, Z1 - Z0)), Color(0.3, 0.46, 0.22))
		# Road, yard and farmhouse
		var road := Rect2(X0, PlotData.ROAD_Z - PlotData.ROAD_HALF, X1 - X0, PlotData.ROAD_HALF * 2.0)
		draw_rect(_rect_on_screen(road), Color(0.28, 0.28, 0.3))
		draw_rect(_rect_on_screen(Rect2(-17.0, 5.0, 34.0, 12.0)), Color(0.52, 0.42, 0.28))
		draw_rect(_rect_on_screen(Rect2(-2.6, 5.4, 5.2, 4.2)), Color(0.7, 0.3, 0.22))
		_text(_to_screen(-4.0, 13.5), "Yard", 18, Color(1, 1, 1, 0.8))
		_text(_to_screen(X0 + 1.0, PlotData.ROAD_Z + 0.5), "Main road", 16, Color(1, 1, 1, 0.85))
		# Plots
		for p in PlotData.PLOTS:
			var id := str(p["id"])
			var r := PlotData.rect_of(id)
			var sr := _rect_on_screen(r)
			var owned: bool = state.owns_plot(id)
			if owned:
				draw_rect(sr, Color(0.25, 0.17, 0.1))
				var start: int = state.plot_start(id)
				var cols := int(p["cols"])
				var rows := int(p["rows"])
				var cell := PlotData.PITCH * s
				for row in rows:
					for col in cols:
						var c := _tile_color(start + row * cols + col)
						draw_rect(Rect2(sr.position + Vector2(col, row) * cell, Vector2(cell - 0.6, cell - 0.6)), c)
				var st: Dictionary = state.plot_status(id, now)
				var label := str(p["name"])
				if bool(st["ready"]):
					label += "  READY %d" % int(st["ripe"])
				_text(sr.position + Vector2(5, 20), label, 18, Color(1, 1, 1) if not bool(st["ready"]) else Color(1.0, 0.9, 0.3))
			else:
				draw_rect(sr, Color(0.42, 0.52, 0.34))
				_text(sr.position + Vector2(5, 20), str(p["name"]), 18, Color(1, 1, 1))
				_text(sr.position + Vector2(5, 42), "For sale  %d" % PlotData.price_of(id), 18, Color(1.0, 0.9, 0.5))
			var edge := Color(1, 1, 1, 0.9) if id == selected else (Color(0.95, 0.85, 0.3) if not owned else Color(0.2, 0.2, 0.15))
			draw_rect(sr, edge, false, 4.0 if id == selected else 2.0)
		# Machines
		for mid in state.fleet:
			var m: Dictionary = state.fleet[mid]
			var pt := _to_screen(float(m["x"]), float(m["z"]))
			draw_circle(pt, 7.0 if str(mid) == active_id else 5.0, Color(0.1, 0.1, 0.1))
			draw_circle(pt, 5.0 if str(mid) == active_id else 3.5, Color(0.95, 0.9, 0.2) if str(mid) == active_id else Color(0.5, 0.75, 1.0))
		# Legend
		var items := [[Color(1.0, 0.84, 0.18), "Ripe: ready"], [Color(0.28, 0.62, 0.26), "Growing"], [Color(0.3, 0.2, 0.12), "Ploughed"],
			[Color(0.46, 0.37, 0.25), "Not ploughed"], [Color(0.42, 0.52, 0.34), "For sale"], [Color(0.95, 0.9, 0.2), "Your machine"]]
		var lx := 8.0
		var ly := size.y - 14.0
		for it in items:
			draw_rect(Rect2(lx, ly - 12.0, 14.0, 14.0), it[0])
			_text(Vector2(lx + 18.0, ly), str(it[1]), 16, Color(1, 1, 1))
			lx += 28.0 + 9.0 * float(str(it[1]).length())

func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.06, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := _label("Farm Map", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	money_label = _label("", FONT)
	head.add_child(money_label)
	var close_btn := _button("Close")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	canvas = MapCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_stretch_ratio = 2.6
	canvas.custom_minimum_size = Vector2(300, 200)
	canvas.plot_tapped.connect(_on_plot_tapped)
	body.add_child(canvas)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	title_label = _label("Tap a plot", 28)
	right.add_child(title_label)
	info_label = _label("", 22)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(info_label)
	message_label = _label("", 22)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(message_label)
	buy_button = _button("Buy")
	buy_button.pressed.connect(_on_buy)
	right.add_child(buy_button)
	go_button = _button("Look at plot")
	go_button.pressed.connect(_on_go)
	right.add_child(go_button)
	send_button = _button("Send machine here")
	send_button.pressed.connect(_on_send)
	right.add_child(send_button)
	set_process(false)

func _label(text: String, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONT)
	b.custom_minimum_size = Vector2(0, 52)
	return b

func open(game_state, active_machine_id: String = "", active_machine_name: String = "", select_plot: String = "") -> void:
	state = game_state
	machine_id = active_machine_id
	machine_name = active_machine_name
	if select_plot != "":
		selected = select_plot
	message_label.text = ""
	visible = true
	refresh()

func close() -> void:
	visible = false
	closed.emit()

# Redraws the map and the details of the selected plot.
func refresh() -> void:
	if state == null:
		return
	canvas.state = state
	canvas.selected = selected
	canvas.now = Time.get_unix_time_from_system()
	canvas.active_id = machine_id
	money_label.text = "Money: %d" % state.money
	_update_info()
	canvas.queue_redraw()

func _update_info() -> void:
	buy_button.visible = false
	go_button.visible = false
	send_button.visible = false
	if selected == "" or not PlotData.has_plot(selected):
		title_label.text = "Tap a plot"
		info_label.text = "Gold tiles are ripe and ready to harvest.\nGreen tiles are still growing.\nPlots with a price are for sale."
		return
	var p := PlotData.get_plot(selected)
	title_label.text = str(p["name"])
	var size_text := "%s plot: %d x %d tiles (%d)" % [str(p["size"]), int(p["cols"]), int(p["rows"]), PlotData.tile_count(selected)]
	if state.owns_plot(selected):
		var st: Dictionary = state.plot_status(selected, Time.get_unix_time_from_system())
		info_label.text = "%s\nRipe, ready to harvest: %d\nGrowing, not ready: %d\nPloughed, ready to plant: %d\nNot ploughed or stubble: %d" % [
			size_text, int(st["ripe"]), int(st["growing"]), int(st["ploughed"]), int(st["empty"])]
		go_button.visible = true
		send_button.visible = true
		send_button.text = "Send %s here" % (machine_name if machine_name != "" else "machine")
	else:
		var price := PlotData.price_of(selected)
		info_label.text = "%s\nPrice: %d\nYou have: %d" % [size_text, price, state.money]
		buy_button.visible = true
		buy_button.text = "Buy for %d" % price
		buy_button.disabled = state.money < price
		go_button.visible = true

func _on_plot_tapped(id: String) -> void:
	selected = id
	message_label.text = ""
	refresh()

func _on_buy() -> void:
	var err: String = state.buy_plot(selected)
	if err != "":
		message_label.text = err
		refresh()
		return
	message_label.text = "You bought %s!" % str(PlotData.get_plot(selected)["name"])
	plot_bought.emit(selected)
	refresh()

func _on_go() -> void:
	if selected == "":
		return
	visible = false
	go_requested.emit(selected)
	closed.emit()

func _on_send() -> void:
	if selected == "" or not state.owns_plot(selected):
		return
	visible = false
	send_requested.emit(selected)
	closed.emit()
