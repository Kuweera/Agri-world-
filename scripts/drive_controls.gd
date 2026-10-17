extends Control
# Multi-touch driving controls: a steering strip (bottom-left) and a throttle
# strip (bottom-right). Handled in _input() so each finger is tracked by index
# (Buttons only see one touch, so they cannot steer and accelerate together).

var steer := 0.0       # -1 (left) .. 1 (right)
var throttle := 0.0    # -1 (reverse) .. 1 (forward)
var steer_rect := Rect2()
var throttle_rect := Rect2()
var touch_steer := -1
var touch_throttle := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	steer_rect = Rect2(30, vp.y - 190, 520, 160)
	throttle_rect = Rect2(vp.x - 180, vp.y - 400, 150, 370)

func reset() -> void:
	touch_steer = -1
	touch_throttle = -1
	steer = 0.0
	throttle = 0.0
	queue_redraw()

func _dead(v: float, zone: float) -> float:
	if absf(v) < zone:
		return 0.0
	return v

func _apply_steer(pos: Vector2) -> void:
	var v := (pos.x - steer_rect.get_center().x) / (steer_rect.size.x * 0.5)
	steer = _dead(clampf(v, -1.0, 1.0), 0.08)
	queue_redraw()

func _apply_throttle(pos: Vector2) -> void:
	var v := (throttle_rect.get_center().y - pos.y) / (throttle_rect.size.y * 0.5)
	throttle = _dead(clampf(v, -1.0, 1.0), 0.1)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_steer == -1 and steer_rect.has_point(event.position):
				touch_steer = event.index
				_apply_steer(event.position)
				get_viewport().set_input_as_handled()
			elif touch_throttle == -1 and throttle_rect.has_point(event.position):
				touch_throttle = event.index
				_apply_throttle(event.position)
				get_viewport().set_input_as_handled()
		else:
			if event.index == touch_steer:
				touch_steer = -1
				steer = 0.0
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif event.index == touch_throttle:
				touch_throttle = -1
				throttle = 0.0
				queue_redraw()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == touch_steer:
			_apply_steer(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == touch_throttle:
			_apply_throttle(event.position)
			get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(steer_rect, Color(0, 0, 0, 0.3))
	draw_rect(throttle_rect, Color(0, 0, 0, 0.3))
	var sc := steer_rect.get_center()
	var tc := throttle_rect.get_center()
	var line := Color(1, 1, 1, 0.4)
	draw_line(Vector2(sc.x, steer_rect.position.y), Vector2(sc.x, steer_rect.end.y), line, 3.0)
	draw_line(Vector2(throttle_rect.position.x, tc.y), Vector2(throttle_rect.end.x, tc.y), line, 3.0)
	var thumb := Color(1, 0.9, 0.3, 0.9)
	draw_circle(Vector2(sc.x + steer * steer_rect.size.x * 0.5, sc.y), 32.0, thumb)
	draw_circle(Vector2(tc.x, tc.y - throttle * throttle_rect.size.y * 0.5), 32.0, thumb)
	var font := ThemeDB.fallback_font
	draw_string(font, steer_rect.position + Vector2(12, 30), "STEER", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	draw_string(font, throttle_rect.position + Vector2(12, 30), "GAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	draw_string(font, throttle_rect.position + Vector2(12, throttle_rect.size.y - 12), "REV", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
