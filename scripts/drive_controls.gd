extends Control
# Multi-touch driving cockpit. Handled in _input() so every finger is tracked by its index
# (a Button only sees one touch, so it could not steer and accelerate together).
#
#  Bottom-left : big steering wheel. Turn it with a finger; it springs back to centre.
#                Tap the hub (the horn button) to sound the horn.
#  Far right   : throttle lever with a speed readout on top. Slide it up to go forward,
#                down below the notch to reverse. It STAYS where you leave it (like a
#                hand throttle); the brake pedal or the notch brings it back to zero.
#  Next to it  : three round buttons -
#                  gear      lower / raise the tool (plough, cultivator, spreader, combine header)
#                  implement choose the next attachment (plough, cultivator, seeder ...)
#                  tractor   take the wheel of the next machine
#  Left of those: brake pedal (analog: press lower = brake harder) and the P handbrake.
#  Bottom centre: name of the machine being driven.
#
# Outputs (read by hud.gd): steer -1..1, throttle -1..1 (negative = reverse),
# brake 0..1 (pedal, or 1 while the handbrake is on), handbrake.
# Signal `action` carries "lift", "implement_next", "machine_next" to the hud.

signal action(name: String)

const WHEEL_MAX := 2.4          # radians the wheel turns from the middle to full lock (about 137 degrees)
const WHEEL_RETURN := 7.0       # radians per second it springs back
const PEDAL_MIN := 0.35         # a light touch at the top of the brake pedal
const DEAD := 0.04
const ZERO_FRAC := 0.74         # where the notch sits on the lever, from the top (forward above, reverse below)
const SNAP := 0.07              # the lever clicks to zero this close to the notch
const HORN_R := 40.0            # radius of the horn button in the wheel's hub

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := false

# Shown on the cockpit (set by the hud).
var speed_kmh := 0.0
var raised := false
var header_mode := false
var tool_name := "None"
var machine_name := ""
var machine_index := 0
var machine_total := 1

var s := 1.0                    # layout scale (720 px tall is 1.0)
var wheel_c := Vector2.ZERO
var wheel_r := 150.0
var wheel_angle := 0.0
var lever_rect := Rect2()       # the track
var read_rect := Rect2()
var brake_rect := Rect2()
var hand_rect := Rect2()
var btn_rects := {}             # action -> Rect2

var lever := 0.0                # -1..1
var touch_wheel := -1
var touch_lever := -1
var touch_brake := -1
var wheel_last := 0.0
var brake_v := 0.0
var flash := {}                 # action -> seconds of highlight left
var horn_t := 0.0
var horn: AudioStreamPlayer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	s = clampf(vp.y / 720.0, 0.6, 1.6)
	wheel_c = Vector2(60.0 * s + 150.0 * s, vp.y - 190.0 * s)
	wheel_r = 150.0 * s
	var rx := vp.x - 20.0 * s
	lever_rect = Rect2(rx - 86.0 * s, 200.0 * s, 86.0 * s, vp.y - 270.0 * s)
	read_rect = Rect2(rx - 130.0 * s, 132.0 * s, 130.0 * s, 62.0 * s)
	var bx := rx - 86.0 * s - 28.0 * s - 100.0 * s       # left edge of the round-button column
	var by := 230.0 * s
	for a in ["lift", "implement_next", "machine_next"]:
		btn_rects[a] = Rect2(bx, by, 100.0 * s, 104.0 * s)
		by += 118.0 * s
	var px := bx - 24.0 * s - 120.0 * s
	brake_rect = Rect2(px, vp.y - 230.0 * s, 120.0 * s, 190.0 * s)
	hand_rect = Rect2(px, vp.y - 306.0 * s, 120.0 * s, 64.0 * s)
	horn = AudioStreamPlayer.new()
	horn.stream = _make_horn()
	add_child(horn)
	set_process(true)

# A two-tone car-style horn, made in code (no audio files in the project).
func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := minf(1.0, t * 60.0) * minf(1.0, (0.5 - t) * 25.0)
		var v := (sin(TAU * 349.0 * t) + sin(TAU * 440.0 * t)) * 0.5
		v = clampf(v * 1.8, -1.0, 1.0) * env * 0.6
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func sound_horn() -> void:
	horn_t = 0.25
	if horn != null:
		horn.play()
	queue_redraw()

func reset() -> void:
	touch_wheel = -1
	touch_lever = -1
	touch_brake = -1
	wheel_angle = 0.0
	brake_v = 0.0
	lever = 0.0
	handbrake = false
	_update_outputs()
	queue_redraw()

# Throttle back to zero (autopilot start, changing machine).
func lever_zero() -> void:
	lever = 0.0
	touch_lever = -1
	_update_outputs()
	queue_redraw()

func _update_outputs() -> void:
	var st := wheel_angle / WHEEL_MAX
	steer = 0.0 if absf(st) < DEAD else clampf(st, -1.0, 1.0)
	throttle = 0.0 if handbrake else lever
	brake = 1.0 if handbrake else brake_v

# Lever value for a finger at pos: above the notch forward 0..1, below it reverse 0..-1.
func _lever_value(pos: Vector2) -> float:
	var zero_y := lever_rect.position.y + lever_rect.size.y * ZERO_FRAC
	var v := 0.0
	if pos.y <= zero_y:
		v = (zero_y - pos.y) / (zero_y - lever_rect.position.y)
	else:
		v = -(pos.y - zero_y) / (lever_rect.end.y - zero_y)
	v = clampf(v, -1.0, 1.0)
	return 0.0 if absf(v) < SNAP else v

func _lever_y(v: float) -> float:
	var zero_y := lever_rect.position.y + lever_rect.size.y * ZERO_FRAC
	if v >= 0.0:
		return zero_y - v * (zero_y - lever_rect.position.y)
	return zero_y - v * (lever_rect.end.y - zero_y)

func _pedal_value(rect: Rect2, pos: Vector2) -> float:
	var f := clampf((pos.y - rect.position.y) / rect.size.y, 0.0, 1.0)
	return PEDAL_MIN + (1.0 - PEDAL_MIN) * f

func _angle_of(pos: Vector2) -> float:
	return (pos - wheel_c).angle()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var redraw := false
	if touch_wheel == -1 and wheel_angle != 0.0:
		wheel_angle = move_toward(wheel_angle, 0.0, WHEEL_RETURN * delta)
		_update_outputs()
		redraw = true
	for k in flash.keys():
		flash[k] = float(flash[k]) - delta
		if float(flash[k]) <= 0.0:
			flash.erase(k)
		redraw = true
	if horn_t > 0.0:
		horn_t -= delta
		redraw = true
	if redraw or absf(speed_kmh - _shown_speed) > 0.05:
		queue_redraw()

var _shown_speed := 0.0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			var hit_btn := ""
			for a in btn_rects:
				if (btn_rects[a] as Rect2).grow(6.0 * s).has_point(pos):
					hit_btn = a
			if hit_btn != "":
				flash[hit_btn] = 0.18
				action.emit(hit_btn)
				_handled()
			elif touch_wheel == -1 and pos.distance_to(wheel_c) <= wheel_r + 25.0 * s:
				touch_wheel = event.index
				wheel_last = _angle_of(pos)
				if pos.distance_to(wheel_c) <= HORN_R * s:
					sound_horn()
				_handled()
			elif touch_lever == -1 and lever_rect.grow(34.0 * s).has_point(pos):
				touch_lever = event.index
				lever = _lever_value(pos)
				_handled()
			elif touch_brake == -1 and brake_rect.grow(10.0 * s).has_point(pos):
				touch_brake = event.index
				brake_v = _pedal_value(brake_rect, pos)
				lever = 0.0        # off the throttle as soon as the brake goes on
				_handled()
			elif hand_rect.has_point(pos):
				handbrake = not handbrake
				if handbrake:
					lever = 0.0
				_handled()
		else:
			if event.index == touch_wheel:
				touch_wheel = -1
				_handled()
			elif event.index == touch_lever:
				touch_lever = -1          # the lever stays where it was left
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
		elif event.index == touch_lever:
			lever = _lever_value(dpos)
			if handbrake and lever != 0.0:
				handbrake = false
			_handled()
		elif event.index == touch_brake:
			brake_v = _pedal_value(brake_rect, dpos)
			lever = 0.0
			_handled()
		else:
			return
		_update_outputs()
		queue_redraw()

func _handled() -> void:
	get_viewport().set_input_as_handled()

# ---- drawing ----

func _box(rect: Rect2, fill: Color, border: Color, radius: float, bw := 3.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)

func _text(pos: Vector2, text: String, w: float, fs: int, col := Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, int(fs * s), col)

# A curved arrow: arc from a0 to a1 (radians) with a head at a1.
func _arc_arrow(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	draw_arc(c, r, a0, a1, 16, col, w, true)
	var dir := 1.0 if a1 > a0 else -1.0
	var tip := c + Vector2(cos(a1), sin(a1)) * r
	var tang := Vector2(-sin(a1), cos(a1)) * dir
	var nrm := Vector2(cos(a1), sin(a1))
	var hs := w * 2.2
	draw_colored_polygon(PackedVector2Array([tip + tang * hs, tip + nrm * hs * 0.8, tip - nrm * hs * 0.8]), col)

func _icon_gear(c: Vector2, r: float, col: Color) -> void:
	for k in 8:
		var a := TAU * float(k) / 8.0
		draw_line(c + Vector2(cos(a), sin(a)) * r * 0.7, c + Vector2(cos(a), sin(a)) * r * 1.02, col, r * 0.36)
	draw_circle(c, r * 0.82, col)
	draw_circle(c, r * 0.34, Color(0.1, 0.12, 0.1, 0.95))

# A plough glyph (beam and three share blades) with a pair of cycle arrows round it.
func _icon_implement(c: Vector2, r: float, col: Color) -> void:
	draw_line(c + Vector2(-r * 0.5, -r * 0.3), c + Vector2(r * 0.55, r * 0.3), col, r * 0.14)
	for k in 3:
		var p := c + Vector2(-r * 0.3 + float(k) * r * 0.3, -r * 0.16 + float(k) * r * 0.17)
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(-r * 0.05, r * 0.42), p + Vector2(r * 0.24, r * 0.34)]), col)
	_arc_arrow(c, r * 0.98, -2.7, -0.55, col, r * 0.1)
	_arc_arrow(c, r * 0.98, 0.45, 2.6, col, r * 0.1)

func _icon_tractor(c: Vector2, r: float, col: Color) -> void:
	var hole := Color(0.1, 0.12, 0.1, 0.95)
	draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 0.9, r * 0.22)), col)             # bonnet and body
	draw_rect(Rect2(c + Vector2(r * 0.02, -r * 0.46), Vector2(r * 0.36, r * 0.42)), col)            # cab
	draw_rect(Rect2(c + Vector2(-r * 0.46, -r * 0.34), Vector2(r * 0.07, r * 0.26)), col)           # exhaust
	draw_circle(c + Vector2(r * 0.28, r * 0.2), r * 0.27, col)                                        # big rear wheel
	draw_circle(c + Vector2(r * 0.28, r * 0.2), r * 0.1, hole)
	draw_circle(c + Vector2(-r * 0.38, r * 0.27), r * 0.16, col)                                      # front wheel
	_arc_arrow(c, r * 0.98, 3.5, 5.7, col, r * 0.1)
	_arc_arrow(c, r * 0.98, 0.35, 2.55, col, r * 0.1)

func _round_button(a: String, title: String, ok: Color) -> void:
	var rc: Rect2 = btn_rects[a]
	var down := flash.has(a)
	var fill := Color(0.16, 0.2, 0.16, 0.85) if not down else Color(0.3, 0.45, 0.25, 0.95)
	_box(rc, fill, Color(1, 1, 1, 0.55), 22.0 * s)
	var c := rc.position + Vector2(rc.size.x * 0.5, rc.size.y * 0.4)
	var r := rc.size.x * 0.3
	match a:
		"lift":
			_icon_gear(c, r, ok)
			# What a tap will do: an arrow down (lower) or up (raise) beside the gear.
			var ax := rc.end.x - 18.0 * s
			var ay := rc.position.y + 22.0 * s
			var up := raised
			var d := -1.0 if up else 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(ax, ay + 10.0 * s * d), Vector2(ax - 9.0 * s, ay - 6.0 * s * d), Vector2(ax + 9.0 * s, ay - 6.0 * s * d)]), Color(1, 0.9, 0.4))
		"implement_next":
			_icon_implement(c, r * 1.1, ok)
		"machine_next":
			_icon_tractor(c, r * 1.15, ok)
	_text(rc.position + Vector2(0, rc.size.y - 12.0 * s), title, rc.size.x, 16, Color(1, 1, 1, 0.92))

func _draw() -> void:
	var col_ok := Color(0.55, 0.92, 0.45)
	var amber := Color(1.0, 0.72, 0.25)
	var vp := size

	# ---- machine name, bottom centre ----
	if machine_name != "":
		var nw := 520.0 * s
		var nx := (brake_rect.position.x + wheel_c.x + wheel_r) * 0.5 - nw * 0.5
		var rc := Rect2(nx, vp.y - 62.0 * s, nw, 46.0 * s)
		_box(rc, Color(0.05, 0.07, 0.05, 0.6), Color(1, 1, 1, 0.35), 14.0 * s, 2.0)
		_text(rc.position + Vector2(0, 33.0 * s), "%s   (%d/%d)" % [machine_name, machine_index + 1, machine_total], rc.size.x, 26)

	# ---- steering wheel ----
	var wr := wheel_r
	draw_circle(wheel_c, wr + 8.0 * s, Color(0, 0, 0, 0.28))
	draw_set_transform(wheel_c, wheel_angle, Vector2.ONE)
	var rim := wr - 12.0 * s
	draw_arc(Vector2.ZERO, rim, 0.0, TAU, 64, Color(0.1, 0.1, 0.12, 0.92), 26.0 * s, true)
	draw_arc(Vector2.ZERO, rim + 11.0 * s, 0.0, TAU, 64, Color(1, 1, 1, 0.3), 2.5 * s, true)
	draw_arc(Vector2.ZERO, rim - 11.0 * s, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 2.0 * s, true)
	for a in [PI / 2.0, 7.0 * PI / 6.0, 11.0 * PI / 6.0]:
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (rim - 6.0 * s), Color(0.1, 0.1, 0.12, 0.95), 20.0 * s)
	draw_line(Vector2(0, -rim - 12.0 * s), Vector2(0, -rim + 12.0 * s), Color(1, 0.85, 0.2), 8.0 * s)   # top mark
	# Horn button in the hub.
	var hub := HORN_R * s
	var pressed := horn_t > 0.0
	draw_circle(Vector2.ZERO, hub + 8.0 * s, Color(0.22, 0.22, 0.26, 0.97))
	draw_circle(Vector2.ZERO, hub, Color(0.95, 0.75, 0.15) if pressed else Color(0.78, 0.2, 0.18, 0.97))
	draw_arc(Vector2.ZERO, hub * 0.5, -0.9, 0.9, 10, Color.WHITE, 3.0 * s, true)             # little speaker waves
	draw_arc(Vector2.ZERO, hub * 0.75, -0.7, 0.7, 10, Color.WHITE, 3.0 * s, true)
	draw_rect(Rect2(Vector2(-hub * 0.55, -hub * 0.2), Vector2(hub * 0.3, hub * 0.4)), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ---- three round buttons ----
	var lift_title := ("Lower " if raised else "Raise ") + ("header" if header_mode else "tool")
	_round_button("lift", lift_title, amber if raised else col_ok)
	_round_button("implement_next", "Combine" if header_mode else tool_name, col_ok)
	_round_button("machine_next", "Machines", col_ok)

	# ---- brake pedal and handbrake ----
	_box(brake_rect, Color(0.08, 0.08, 0.1, 0.6), Color(1, 1, 1, 0.5), 14.0 * s)
	if brake_v > 0.0:
		var h := brake_rect.size.y * brake_v
		_box(Rect2(brake_rect.position.x + 4.0 * s, brake_rect.end.y - h, brake_rect.size.x - 8.0 * s, h - 4.0 * s), Color(0.9, 0.3, 0.25, 0.6), Color(0, 0, 0, 0), 10.0 * s, 0.0)
	var k := 0
	while float(k) * 22.0 * s < brake_rect.size.y - 40.0 * s:
		var y := brake_rect.position.y + 16.0 * s + float(k) * 22.0 * s
		draw_line(Vector2(brake_rect.position.x + 16.0 * s, y), Vector2(brake_rect.end.x - 16.0 * s, y), Color(1, 1, 1, 0.3), 3.0 * s)
		k += 1
	_text(brake_rect.position + Vector2(0, brake_rect.size.y - 10.0 * s), "BRAKE", brake_rect.size.x, 22)
	_box(hand_rect, Color(0.85, 0.15, 0.15, 0.85) if handbrake else Color(0.08, 0.08, 0.1, 0.6), Color(1, 1, 1, 0.5), 14.0 * s)
	_text(hand_rect.position + Vector2(0, hand_rect.size.y * 0.5 + 9.0 * s), "P  Handbrake" if not handbrake else "P  ON", hand_rect.size.x, 17)

	# ---- speed readout and throttle lever ----
	_shown_speed = speed_kmh
	_box(read_rect, Color(0.05, 0.07, 0.05, 0.75), Color(1, 1, 1, 0.5), 12.0 * s)
	var rev := throttle < -0.01 or (lever < 0.0)
	_text(read_rect.position + Vector2(0, 38.0 * s), "%d" % int(round(absf(speed_kmh))), read_rect.size.x * 0.72, 38, Color(1, 0.55, 0.45) if rev else Color.WHITE)
	_text(read_rect.position + Vector2(read_rect.size.x * 0.5, 22.0 * s), "km/h", read_rect.size.x * 0.5, 15, Color(1, 1, 1, 0.75))
	_text(read_rect.position + Vector2(read_rect.size.x * 0.5, 46.0 * s), "R" if rev else "F", read_rect.size.x * 0.5, 22, Color(1, 0.55, 0.45) if rev else col_ok)

	var track := Rect2(lever_rect.position.x + lever_rect.size.x * 0.5 - 26.0 * s, lever_rect.position.y, 52.0 * s, lever_rect.size.y)
	_box(track, Color(0.05, 0.07, 0.05, 0.7), Color(1, 1, 1, 0.45), 14.0 * s)
	var zero_y := lever_rect.position.y + lever_rect.size.y * ZERO_FRAC
	# Segmented bars: green going forward, red for reverse.
	var seg := 22.0 * s
	var gap := 6.0 * s
	var ky := _lever_y(lever)
	var y := zero_y - seg - gap
	while y > track.position.y + 6.0 * s:
		var on := lever > 0.0 and y + seg * 0.5 >= ky
		_box(Rect2(track.position.x + 8.0 * s, y, track.size.x - 16.0 * s, seg), col_ok if on else Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 5.0 * s, 0.0)
		y -= seg + gap
	y = zero_y + gap + 2.0 * s
	while y + seg < track.end.y - 6.0 * s:
		var on2 := lever < 0.0 and y + seg * 0.5 <= ky
		_box(Rect2(track.position.x + 8.0 * s, y, track.size.x - 16.0 * s, seg), Color(0.95, 0.3, 0.25) if on2 else Color(0.95, 0.3, 0.25, 0.14), Color(0, 0, 0, 0), 5.0 * s, 0.0)
		y += seg + gap
	# The notch (neutral).
	draw_line(Vector2(track.position.x - 10.0 * s, zero_y), Vector2(track.end.x + 10.0 * s, zero_y), Color(1, 0.9, 0.4), 3.0 * s)
	_text(Vector2(track.position.x - 60.0 * s, zero_y + 6.0 * s), "0", 40.0 * s, 16, Color(1, 0.9, 0.4))
	# Knob.
	var kw := 82.0 * s
	var kh := 46.0 * s
	var knob := Rect2(track.position.x + track.size.x * 0.5 - kw * 0.5, ky - kh * 0.5, kw, kh)
	_box(knob, Color(0.85, 0.87, 0.85, 0.97), Color(0.15, 0.15, 0.15), 12.0 * s, 3.0)
	for g in 3:
		var gy := knob.position.y + kh * (0.3 + 0.2 * float(g))
		draw_line(Vector2(knob.position.x + 12.0 * s, gy), Vector2(knob.end.x - 12.0 * s, gy), Color(0.3, 0.3, 0.3), 2.5 * s)
