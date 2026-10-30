extends Control
# Multi-touch driving controls: a steering wheel (bottom-left) and, bottom-right, an accelerator
# pedal, a brake pedal, a forward/reverse selector and a handbrake. Handled in _input() so each
# finger is tracked by index (Buttons only see one touch, so they cannot steer and accelerate together).
#
# Wheel: put a finger on it and turn it round; it follows your finger and springs back to the middle
# when you let go. Pedals: press anywhere on them; the lower you press, the harder (analog), and you can
# slide the finger to change it. F/R chooses the direction the accelerator drives. P is the handbrake.
#
# Outputs (read by hud.gd): steer -1..1, throttle -1..1 (accelerator, negative in reverse),
# brake 0..1 (brake pedal, or 1 while the handbrake is on), handbrake.

const WHEEL_MAX := 2.4          # radians the wheel turns from the middle to full lock (about 137 degrees)
const WHEEL_RETURN := 7.0       # radians per second it springs back
const PEDAL_MIN := 0.35         # a light touch at the top of a pedal
const DEAD := 0.04

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := false
var reverse := false

var wheel_c := Vector2.ZERO
var wheel_r := 115.0
var wheel_angle := 0.0
var accel_rect := Rect2()
var brake_rect := Rect2()
var gear_rect := Rect2()
var hand_rect := Rect2()

var touch_wheel := -1
var touch_accel := -1
var touch_brake := -1
var wheel_last := 0.0
var accel_v := 0.0
var brake_v := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	# The wheel sits right of the button column on the left (x 20..340).
	wheel_c = Vector2(480.0, vp.y - 140.0)
	accel_rect = Rect2(vp.x - 150.0, vp.y - 300.0, 120.0, 270.0)
	brake_rect = Rect2(vp.x - 290.0, vp.y - 190.0, 120.0, 160.0)
	gear_rect = Rect2(vp.x - 290.0, vp.y - 280.0, 120.0, 70.0)
	hand_rect = Rect2(vp.x - 150.0, vp.y - 380.0, 120.0, 70.0)
	set_process(true)

func reset() -> void:
	touch_wheel = -1
	touch_accel = -1
	touch_brake = -1
	wheel_angle = 0.0
	accel_v = 0.0
	brake_v = 0.0
	reverse = false
	handbrake = false
	_update_outputs()
	queue_redraw()

func _update_outputs() -> void:
	var s := wheel_angle / WHEEL_MAX
	steer = 0.0 if absf(s) < DEAD else clampf(s, -1.0, 1.0)
	throttle = (-accel_v if reverse else accel_v)
	if handbrake:
		throttle = 0.0
	brake = 1.0 if handbrake else brake_v

func _pedal_value(rect: Rect2, pos: Vector2) -> float:
	var f := clampf((pos.y - rect.position.y) / rect.size.y, 0.0, 1.0)
	return PEDAL_MIN + (1.0 - PEDAL_MIN) * f

func _angle_of(pos: Vector2) -> float:
	return (pos - wheel_c).angle()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if touch_wheel == -1 and wheel_angle != 0.0:
		wheel_angle = move_toward(wheel_angle, 0.0, WHEEL_RETURN * delta)
		_update_outputs()
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if touch_wheel == -1 and pos.distance_to(wheel_c) <= wheel_r + 25.0:
				touch_wheel = event.index
				wheel_last = _angle_of(pos)
				_handled()
			elif touch_accel == -1 and accel_rect.grow(10.0).has_point(pos):
				touch_accel = event.index
				accel_v = _pedal_value(accel_rect, pos)
				_handled()
			elif touch_brake == -1 and brake_rect.grow(10.0).has_point(pos):
				touch_brake = event.index
				brake_v = _pedal_value(brake_rect, pos)
				_handled()
			elif gear_rect.has_point(pos):
				reverse = not reverse
				_handled()
			elif hand_rect.has_point(pos):
				handbrake = not handbrake
				_handled()
		else:
			if event.index == touch_wheel:
				touch_wheel = -1
				_handled()
			elif event.index == touch_accel:
				touch_accel = -1
				accel_v = 0.0
				_handled()
			elif event.index == touch_brake:
				touch_brake = -1
				brake_v = 0.0
				_handled()
		_update_outputs()
		queue_redraw()
	elif event is InputEventScreenDrag:
		var dpos: Vector2 = event.position
		if event.index == touch_wheel:
			var a := _angle_of(dpos)
			wheel_angle = clampf(wheel_angle + wrapf(a - wheel_last, -PI, PI), -WHEEL_MAX, WHEEL_MAX)
			wheel_last = a
			_handled()
		elif event.index == touch_accel:
			accel_v = _pedal_value(accel_rect, dpos)
			_handled()
		elif event.index == touch_brake:
			brake_v = _pedal_value(brake_rect, dpos)
			_handled()
		else:
			return
		_update_outputs()
		queue_redraw()

func _handled() -> void:
	get_viewport().set_input_as_handled()

func _pedal(rect: Rect2, value: float, label: String, color: Color) -> void:
	draw_rect(rect, Color(0.08, 0.08, 0.1, 0.55))
	if value > 0.0:
		var h := rect.size.y * value
		draw_rect(Rect2(rect.position.x, rect.end.y - h, rect.size.x, h), Color(color.r, color.g, color.b, 0.55))
	var k := 0
	while float(k) * 22.0 < rect.size.y - 12.0:
		var y := rect.position.y + 14.0 + float(k) * 22.0
		draw_line(Vector2(rect.position.x + 12.0, y), Vector2(rect.end.x - 12.0, y), Color(1, 1, 1, 0.3), 3.0)
		k += 1
	draw_rect(rect, Color(1, 1, 1, 0.5), false, 3.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, rect.size.y - 10.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color.WHITE)

func _button(rect: Rect2, text: String, on: bool, on_color: Color) -> void:
	draw_rect(rect, on_color if on else Color(0.08, 0.08, 0.1, 0.55))
	draw_rect(rect, Color(1, 1, 1, 0.5), false, 3.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, rect.size.y * 0.5 + 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 32, Color.WHITE)

func _draw() -> void:
	# Steering wheel: ring, three spokes and a hub, turned by wheel_angle. The yellow mark is the top.
	draw_circle(wheel_c, wheel_r + 6.0, Color(0, 0, 0, 0.25))
	draw_set_transform(wheel_c, wheel_angle, Vector2.ONE)
	draw_arc(Vector2.ZERO, wheel_r - 8.0, 0.0, TAU, 48, Color(0.12, 0.12, 0.14, 0.85), 20.0)
	draw_arc(Vector2.ZERO, wheel_r - 8.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	for a in [PI / 2.0, 7.0 * PI / 6.0, 11.0 * PI / 6.0]:
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (wheel_r - 18.0), Color(0.12, 0.12, 0.14, 0.9), 14.0)
	draw_circle(Vector2.ZERO, 24.0, Color(0.2, 0.2, 0.24, 0.95))
	draw_line(Vector2(0, -wheel_r + 20.0), Vector2(0, -wheel_r + 0.0), Color(1, 0.85, 0.2), 8.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_pedal(accel_rect, accel_v, "GAS", Color(0.3, 0.85, 0.35))
	_pedal(brake_rect, brake_v, "BRAKE", Color(0.9, 0.3, 0.25))
	_button(gear_rect, "R" if reverse else "F", reverse, Color(0.85, 0.5, 0.1, 0.8))
	_button(hand_rect, "P", handbrake, Color(0.85, 0.15, 0.15, 0.85))
