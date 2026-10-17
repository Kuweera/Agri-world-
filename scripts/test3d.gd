extends Node3D
# Diagnostic B: minimal 3D. One unshaded cube, no lights, no UI.

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.5, 4)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.9, 0.4, 0.1)
	cube.material_override = m
	add_child(cube)
