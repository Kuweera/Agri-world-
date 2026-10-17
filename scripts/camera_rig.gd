extends Node3D
# Orbit/zoom camera rig for touch screens.
# One finger drag = rotate. Two finger pinch = zoom.
# Emits `tapped` for a short, still, single-finger tap.

signal tapped(screen_pos: Vector2)

const TAP_MAX_MOVE := 20.0
const TAP_MAX_MS := 400

@export var min_dist := 6.0
@export var max_dist := 30.0

var yaw := 0.5
var pitch := 0.9
var dist := 18.0
var cam := Camera3D.new()
var touches := {}
var last_pinch := 0.0
var press_ms := 0
var moved := 0.0
var was_multi := false

func _ready() -> void:
	cam.far = 200.0
	add_child(cam)
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				press_ms = Time.get_ticks_msec()
				moved = 0.0
				was_multi = false
			else:
				was_multi = true
			last_pinch = 0.0
		else:
			if touches.size() == 1 and not was_multi and moved < TAP_MAX_MOVE \
					and Time.get_ticks_msec() - press_ms < TAP_MAX_MS:
				tapped.emit(event.position)
			touches.erase(event.index)
			last_pinch = 0.0
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		moved += event.relative.length()
		if touches.size() == 1:
			yaw -= event.relative.x * 0.005
			pitch = clampf(pitch + event.relative.y * 0.005, 0.35, 1.35)
		elif touches.size() >= 2:
			var pts: Array = touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if last_pinch > 0.0:
				dist = clampf(dist - (d - last_pinch) * 0.03, min_dist, max_dist)
			last_pinch = d
		_apply()

func _apply() -> void:
	cam.position = Vector3(
		dist * cos(pitch) * sin(yaw),
		dist * sin(pitch),
		dist * cos(pitch) * cos(yaw))
	cam.look_at(global_position, Vector3.UP)

# Where a screen point hits the ground plane (y = 0). Returns null if it misses.
func ray_to_ground(screen_pos: Vector2) -> Variant:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	return from + dir * t
