extends Node3D
# Stage 0: toolchain proof. Cube, orbit camera, one touch button, FPS/memory readout.

var yaw := 0.6
var pitch := 0.5
var dist := 8.0
var touches := {}
var last_pinch := 0.0
var taps := 0
var cube := MeshInstance3D.new()
var cube_mat := StandardMaterial3D.new()
var cam := Camera3D.new()
var info := Label.new()
var button := Button.new()
var colors := [Color(0.9, 0.35, 0.1), Color(0.15, 0.6, 0.35), Color(0.2, 0.5, 0.9)]

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.55, 0.25)
	ground.material_override = gm
	add_child(ground)

	cube.mesh = BoxMesh.new()
	cube.position = Vector3(0, 0.5, 0)
	cube_mat.albedo_color = colors[0]
	cube.material_override = cube_mat
	add_child(cube)

	add_child(cam)
	_update_camera()

	var ui := CanvasLayer.new()
	add_child(ui)
	info.position = Vector2(20, 20)
	info.add_theme_font_size_override("font_size", 28)
	ui.add_child(info)
	button.text = "Tap me: 0"
	button.position = Vector2(20, 100)
	button.custom_minimum_size = Vector2(300, 110)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(_on_button)
	ui.add_child(button)

func _on_button() -> void:
	taps += 1
	cube_mat.albedo_color = colors[taps % colors.size()]
	button.text = "Tap me: %d" % taps

func _process(_delta: float) -> void:
	var mem := OS.get_static_memory_usage() / 1048576.0
	info.text = "FPS: %d   Mem: %.0f MB" % [Engine.get_frames_per_second(), mem]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		last_pinch = 0.0
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 1:
			yaw -= event.relative.x * 0.005
			pitch = clampf(pitch + event.relative.y * 0.005, 0.15, 1.4)
		elif touches.size() >= 2:
			var pts: Array = touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if last_pinch > 0.0:
				dist = clampf(dist - (d - last_pinch) * 0.03, 3.0, 20.0)
			last_pinch = d
		_update_camera()

func _update_camera() -> void:
	cam.position = Vector3(
		dist * cos(pitch) * sin(yaw),
		dist * sin(pitch),
		dist * cos(pitch) * cos(yaw))
	cam.look_at(Vector3.ZERO, Vector3.UP)
