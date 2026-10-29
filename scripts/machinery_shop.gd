extends Control
# Machinery shop screen: pick a category, see stats and a rotating 3D preview, buy machines
# and put them to use. Built in code (no scene file). Call open(state) to show it.
# Emits `changed` after a purchase or when a machine is put to use, and `closed` on close.

signal changed
signal closed

const ShopCatalog := preload("res://scripts/shop_catalog.gd")
const MachineModels := preload("res://scripts/machine_models.gd")
const ImplementData := preload("res://scripts/implement_data.gd")

const FONT := 26

var state
var category := "tractor"
var selected := ""
var ids: Array = []
var cat_buttons: Dictionary = {}
var list: ItemList
var money_label: Label
var name_label: Label
var stats_label: Label
var message_label: Label
var buy_button: Button
var use_button: Button
var preview_vp: SubViewport
var preview_pivot: Node3D
var preview_cam: Camera3D
var preview_for := ""

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
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := _label("Machinery Shop", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	money_label = _label("", FONT)
	head.add_child(money_label)
	# DEVELOPMENT TOOL: keep during development (master plan, section 3). A release build may hide it, not delete it.
	var cash_btn := _button("+5000 test")
	cash_btn.pressed.connect(_on_test_cash)
	head.add_child(cash_btn)
	var close_btn := _button("Close")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var cats := HBoxContainer.new()
	root.add_child(cats)
	for c in ShopCatalog.CATEGORIES:
		var b := _button(str(c["label"]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_category.bind(str(c["id"])))
		cats.add_child(b)
		cat_buttons[str(c["id"])] = b

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	list = ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_stretch_ratio = 1.0
	list.add_theme_font_size_override("font_size", FONT)
	list.item_selected.connect(_on_item)
	body.add_child(list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.5
	body.add_child(right)
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.custom_minimum_size = Vector2(0, 200)
	right.add_child(vpc)
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vpc.add_child(preview_vp)
	_build_preview_world()

	name_label = _label("", 30)
	right.add_child(name_label)
	stats_label = _label("", 24)
	right.add_child(stats_label)
	message_label = _label("", 24)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	right.add_child(message_label)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	buy_button = _button("Buy")
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_button.pressed.connect(_on_buy)
	buttons.add_child(buy_button)
	use_button = _button("Use")
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.pressed.connect(_on_use)
	buttons.add_child(use_button)
	set_process(false)

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", FONT)
	return b

# Own little 3D world for the preview: a light, an ambient colour, a camera, and a pivot that turns.
func _build_preview_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.2, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	preview_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	preview_vp.add_child(sun)
	preview_cam = Camera3D.new()
	preview_vp.add_child(preview_cam)
	preview_pivot = Node3D.new()
	preview_vp.add_child(preview_pivot)

func open(st) -> void:
	state = st
	visible = true
	set_process(true)
	if not ShopCatalog.ids_in(category).has(selected):
		selected = ""
	refresh()

func close() -> void:
	visible = false
	set_process(false)
	_clear_preview()
	closed.emit()

func _process(delta: float) -> void:
	preview_pivot.rotation.y += delta * 0.6

func refresh() -> void:
	if state == null:
		return
	money_label.text = "Money: %d   " % state.money
	for cid in cat_buttons:
		cat_buttons[cid].disabled = (cid == category)
	ids = ShopCatalog.ids_in(category)
	list.clear()
	for id in ids:
		var e := ShopCatalog.entry(id, state)
		list.add_item("%s    %s" % [e["name"], e["tag"]])
	if not ids.has(selected):
		selected = str(ids[0]) if not ids.is_empty() else ""
	if selected != "":
		list.select(ids.find(selected))
	_show_entry()

func _show_entry() -> void:
	if selected == "":
		return
	var e := ShopCatalog.entry(selected, state)
	name_label.text = str(e["name"])
	stats_label.text = str(e["stats"])
	buy_button.visible = not e["owned"]
	buy_button.text = "Buy for %d" % int(e["price"])
	buy_button.disabled = e["can_buy"] != ""
	use_button.visible = bool(e["owned"]) and bool(e["can_use"]) and not e["in_use"]
	use_button.text = "Use"
	if e["in_use"]:
		message_label.text = "In use"
	elif not e["owned"] and e["can_buy"] != "":
		message_label.text = str(e["can_buy"])
	else:
		message_label.text = ""
	_show_preview(selected)

func _on_category(cid: String) -> void:
	category = cid
	selected = ""
	refresh()

func _on_item(index: int) -> void:
	if index >= 0 and index < ids.size():
		selected = str(ids[index])
		_show_entry()

func _on_test_cash() -> void:
	state.money += 5000
	refresh()
	changed.emit()

func _on_buy() -> void:
	var err: String = state.buy(selected)
	refresh()
	if err != "":
		message_label.text = err
	else:
		message_label.text = "Bought!"
		changed.emit()

func _on_use() -> void:
	var err := ""
	if ShopCatalog.is_vehicle(selected):
		err = state.select_vehicle(selected)
	else:
		err = state.equip_implement(selected)
	refresh()
	if err != "":
		message_label.text = err
	else:
		changed.emit()

func _clear_preview() -> void:
	for child in preview_pivot.get_children():
		preview_pivot.remove_child(child)
		child.free()
	preview_for = ""

func _show_preview(id: String) -> void:
	if preview_for == id:
		return
	for child in preview_pivot.get_children():
		preview_pivot.remove_child(child)
		child.free()
	preview_pivot.rotation.y = 0.0
	preview_for = id
	var node: Node3D = MachineModels.instance_for(id)
	var center := Vector3(0, 0.9, 0)
	var dist := 6.0
	if node != null:
		# Frame from the model's own box: middle on the pivot, camera far enough to fit it.
		var box: AABB = MachineModels.bounds_of(node)
		var mid: Vector3 = box.get_center()
		node.position = Vector3(-mid.x, 0.0, -mid.z)
		center = Vector3(0, mid.y, 0)
		dist = maxf(1.2, box.size.length() * 0.5 * 1.1)
		preview_pivot.add_child(node)
	var pos := center + Vector3(0, dist * 0.3, dist)
	preview_cam.transform = Transform3D(Basis.looking_at(center - pos, Vector3.UP), pos)
