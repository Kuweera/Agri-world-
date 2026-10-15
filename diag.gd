extends Node3D
# Diagnostic: finds which part of the full scene hangs on the PowerVR GE8322.
# mode "light"   = DirectionalLight3D + lit materials
# mode "nolight" = lit materials, no light
# mode "ui"      = unshaded materials + Button/Label + touch orbit

@export var mode := "light"

var yaw := 0.6
var pitch := 0.5
var dist := 8.0
var touches := {}
var last_pinch := 0.0
var cam := Camera3D.new()
var info := Label.new()
var taps := 0

func _mat(c: Color, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if not lit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _ready() -> void:
	var lit := mode == "light" or mode == "nolight"
	if mode == "light":
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -30, 0)
		add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.3, 0.55, 0.25), lit)
	add_child(ground)

	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position = Vector3(0, 0.5, 0)
	cube.material_override = _mat(Color(0.9, 0.35, 0.1), lit)
	add_child(cube)

	add_child(cam)
	_update_camera()

	if mode == "ui":
		var ui := CanvasLayer.new()
		add_child(ui)
		info.position = Vector2(20, 20)
		info.add_theme_font_size_override("font_size", 28)
		ui.add_child(info)
		var button := Button.new()
		button.text = "Tap me: 0"
		button.position = Vector2(20, 100)
		button.custom_minimum_size = Vector2(300, 110)
		button.add_theme_font_size_override("font_size", 36)
		button.pressed.connect(func():
			taps += 1
			button.text = "Tap me: %d" % taps)
		ui.add_child(button)

func _process(_delta: float) -> void:
	if mode == "ui":
		info.text = "FPS: %d" % Engine.get_frames_per_second()

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
