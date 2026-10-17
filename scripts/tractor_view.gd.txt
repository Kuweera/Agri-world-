extends Node3D
# Presentation only: a low-poly tractor built from primitives, plus implement visuals.
# The tractor faces +z in local space, so rotation.y = heading.

var impl_nodes := {}

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add_mesh(parent, m, pos, color)

func _wheel(parent: Node3D, radius: float, width: float, pos: Vector3) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = width
	m.radial_segments = 12
	_add_mesh(parent, m, pos, Color(0.1, 0.1, 0.1), Vector3(0, 0, PI / 2.0))

func _ready() -> void:
	var green := Color(0.2, 0.6, 0.25)
	_box(self, Vector3(0.9, 0.25, 2.0), Vector3(0, 0.45, 0.1), Color(0.25, 0.25, 0.28))
	_box(self, Vector3(0.8, 0.55, 1.0), Vector3(0, 0.8, 0.8), green)
	_box(self, Vector3(0.95, 0.9, 0.9), Vector3(0, 1.2, -0.25), Color(0.15, 0.5, 0.2))
	_box(self, Vector3(1.1, 0.08, 1.1), Vector3(0, 1.7, -0.25), Color(0.9, 0.9, 0.9))
	_wheel(self, 0.6, 0.35, Vector3(0.75, 0.6, -0.5))
	_wheel(self, 0.6, 0.35, Vector3(-0.75, 0.6, -0.5))
	_wheel(self, 0.38, 0.28, Vector3(0.65, 0.38, 1.0))
	_wheel(self, 0.38, 0.28, Vector3(-0.65, 0.38, 1.0))
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.05
	pipe.bottom_radius = 0.05
	pipe.height = 0.5
	_add_mesh(self, pipe, Vector3(0.25, 1.3, 1.0), Color(0.15, 0.15, 0.15))

	# Implements trail behind the tractor (negative z)
	var plough := Node3D.new()
	_box(plough, Vector3(1.3, 0.12, 0.8), Vector3(0, 0.3, -1.8), Color(0.45, 0.45, 0.5))
	_box(plough, Vector3(0.12, 0.35, 0.5), Vector3(-0.4, 0.15, -2.1), Color(0.3, 0.3, 0.33))
	_box(plough, Vector3(0.12, 0.35, 0.5), Vector3(0.4, 0.15, -2.1), Color(0.3, 0.3, 0.33))
	add_child(plough)
	impl_nodes["plough"] = plough

	var seeder := Node3D.new()
	_box(seeder, Vector3(1.1, 0.5, 0.7), Vector3(0, 0.75, -1.8), Color(0.9, 0.5, 0.15))
	_box(seeder, Vector3(1.2, 0.1, 0.5), Vector3(0, 0.3, -1.9), Color(0.35, 0.35, 0.4))
	add_child(seeder)
	impl_nodes["seeder"] = seeder

	var harvester := Node3D.new()
	_box(harvester, Vector3(1.9, 0.45, 0.9), Vector3(0, 0.5, -1.9), Color(0.9, 0.8, 0.15))
	_box(harvester, Vector3(1.9, 0.12, 0.3), Vector3(0, 0.85, -2.3), Color(0.7, 0.2, 0.15))
	add_child(harvester)
	impl_nodes["harvester"] = harvester

func update_from(v: Dictionary) -> void:
	position = Vector3(v["x"], 0.0, v["z"])
	rotation.y = v["heading"]
	for k in impl_nodes:
		impl_nodes[k].visible = (k == v["implement"])
