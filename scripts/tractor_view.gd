extends Node3D
# Presentation only: a low-poly tractor with cab, fenders, lugged wheels that spin,
# and tool visuals (plough, seeder, harvester) that trail behind.
# The tractor faces +z in local space, so rotation.y = heading.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const ImplementModels := preload("res://scripts/implement_models.gd")
const Suspension := preload("res://scripts/suspension.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const MachineModels := preload("res://scripts/machine_models.gd")

# Where implements hang on the built-in tractor. A real tractor model sets its own.
const BUILTIN_HITCH := Vector3(0, 0.35, -1.25)

var impl_nodes := {}                     # built-in implement models, by catalogue id
var glb_impl := {}                       # real (.glb) implement models on the hitch, by catalogue id
var builtin_wheels: Array = []
var wheels: Array = []                   # the wheels now shown: [{"node", "radius", "angle", "sign"}]
var body_mi: MeshInstance3D              # the built-in tractor body
var glb_vehicle: Node3D                  # the real tractor model, or null while the built-in one shows
var cur_vehicle := ""
var steer_pivots: Array = []
var steer_vis := 0.0
var yaw_vis := 0.0
var blob: MeshInstance3D
var attach: Node3D                       # AttachmentPoint: implements built from the catalogue hang here
var susp := Suspension.new_state()       # springs for lean and bounce (looks only)
var prev_speed := 0.0
var prev_heading := 0.0
var motion_ready := false
var mat_vc: StandardMaterial3D

func _mesh_node(parent: Node3D, mesh: ArrayMesh, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat_vc
	mi.position = pos
	parent.add_child(mi)
	return mi

func _wheel_mesh(radius: float, width: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var tire := Color(0.07, 0.07, 0.08)
	var rim := Color(0.85, 0.78, 0.2)
	var hw := width / 2.0
	mb.add_prism(Vector3(-hw, 0, 0), Vector3(hw, 0, 0), radius * 0.92, radius * 0.92, 12, tire, tire, true, true)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var xf := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, cos(a) * radius * 0.96, sin(a) * radius * 0.96))
		mb.add_box_xf(xf, Vector3(width * 1.02, 0.08, 0.11), Color(0.12, 0.12, 0.13), 1.0)
	mb.add_prism(Vector3(-hw * 1.08, 0, 0), Vector3(hw * 1.08, 0, 0), radius * 0.5, radius * 0.5, 10, rim, rim, true, true)
	return mb.build()

func _add_wheel(pos: Vector3, radius: float, width: float, mesh: ArrayMesh) -> void:
	var mi := _mesh_node(self, mesh, pos)
	builtin_wheels.append({"node": mi, "radius": radius, "angle": 0.0, "sign": 1.0})

func _ready() -> void:
	if attach == null:
		_build_builtin()

# The built-in tractor and implements. They stay as the fallback when a .glb is missing.
func _build_builtin() -> void:
	mat_vc = MeshBuilder.vc_material()
	var mb := MeshBuilder.new()
	var green := Color(0.2, 0.6, 0.25)
	var dark := Color(0.22, 0.22, 0.25)
	var glass := Color(0.12, 0.18, 0.26)
	mb.add_box(Vector3(0, 0.5, 0.35), Vector3(0.9, 0.3, 2.3), dark)
	mb.add_box(Vector3(0, 0.88, 0.78), Vector3(0.85, 0.55, 1.05), green)
	mb.add_box(Vector3(0, 0.82, 1.33), Vector3(0.7, 0.4, 0.04), dark)
	mb.add_box(Vector3(0.3, 0.92, 1.35), Vector3(0.14, 0.12, 0.05), Color(1.0, 0.95, 0.7), 0.0, 1.0)
	mb.add_box(Vector3(-0.3, 0.92, 1.35), Vector3(0.14, 0.12, 0.05), Color(1.0, 0.95, 0.7), 0.0, 1.0)
	mb.add_box(Vector3(0, 1.45, -0.28), Vector3(1.0, 1.1, 0.95), Color(0.15, 0.5, 0.2))
	mb.add_box(Vector3(0, 1.62, 0.2), Vector3(0.8, 0.5, 0.03), glass, 0.0, 1.0)
	mb.add_box(Vector3(0, 1.62, -0.76), Vector3(0.8, 0.5, 0.03), glass, 0.0, 1.0)
	mb.add_box(Vector3(0.51, 1.62, -0.28), Vector3(0.03, 0.5, 0.7), glass, 0.0, 1.0)
	mb.add_box(Vector3(-0.51, 1.62, -0.28), Vector3(0.03, 0.5, 0.7), glass, 0.0, 1.0)
	mb.add_box(Vector3(0, 2.03, -0.28), Vector3(1.12, 0.07, 1.15), Color(0.92, 0.92, 0.9), 0.0, 1.0)
	mb.add_box(Vector3(0.82, 1.3, -0.55), Vector3(0.45, 0.08, 1.2), green)
	mb.add_box(Vector3(-0.82, 1.3, -0.55), Vector3(0.45, 0.08, 1.2), green)
	mb.add_box(Vector3(0, 0.4, 1.0), Vector3(1.3, 0.1, 0.1), dark)
	mb.add_box(Vector3(0, 0.62, -0.55), Vector3(1.6, 0.1, 0.1), dark)
	mb.add_box(Vector3(0, 0.35, -1.25), Vector3(0.2, 0.15, 0.2), dark)
	mb.add_prism(Vector3(0.3, 1.1, 0.9), Vector3(0.3, 1.75, 0.9), 0.04, 0.035, 6, dark, dark, true)
	body_mi = _mesh_node(self, mb.build())

	var rear := _wheel_mesh(0.62, 0.42)
	var front := _wheel_mesh(0.4, 0.28)
	_add_wheel(Vector3(0.8, 0.62, -0.55), 0.62, 0.42, rear)
	_add_wheel(Vector3(-0.8, 0.62, -0.55), 0.62, 0.42, rear)
	_add_wheel(Vector3(0.7, 0.4, 1.0), 0.4, 0.28, front)
	_add_wheel(Vector3(-0.7, 0.4, 1.0), 0.4, 0.28, front)

	var steel := Color(0.58, 0.6, 0.65)
	var plough := Node3D.new()
	var pb := MeshBuilder.new()
	pb.add_box(Vector3(0, 0.55, -1.5), Vector3(1.3, 0.1, 0.12), dark)
	for x in [-0.4, 0.0, 0.4]:
		pb.add_box_xf(Transform3D(Basis(Vector3.UP, 0.5), Vector3(x, 0.28, -1.95)), Vector3(0.08, 0.45, 0.6), steel, 0.6)
		pb.add_box(Vector3(x, 0.45, -1.65), Vector3(0.06, 0.2, 0.06), dark)
	_mesh_node(plough, pb.build())
	add_child(plough)
	impl_nodes["plough"] = plough

	var seeder := Node3D.new()
	var sb := MeshBuilder.new()
	sb.add_box(Vector3(0, 0.95, -1.7), Vector3(1.2, 0.5, 0.6), Color(0.92, 0.5, 0.15))
	sb.add_box(Vector3(0, 0.55, -1.5), Vector3(1.4, 0.08, 0.1), dark)
	for x in [-0.45, -0.15, 0.15, 0.45]:
		sb.add_prism(Vector3(x, 0.7, -1.75), Vector3(x, 0.1, -2.0), 0.03, 0.02, 5, steel, dark)
	_mesh_node(seeder, sb.build())
	add_child(seeder)
	impl_nodes["seeder"] = seeder

	var harvester := Node3D.new()
	var hb := MeshBuilder.new()
	hb.add_box(Vector3(0, 0.5, -1.95), Vector3(1.9, 0.4, 0.8), Color(0.92, 0.8, 0.15))
	hb.add_box(Vector3(0, 0.3, -2.4), Vector3(1.9, 0.05, 0.12), Color(0.75, 0.2, 0.15), 0.0, 1.0)
	hb.add_box(Vector3(0.95, 0.6, -2.0), Vector3(0.06, 0.5, 0.9), Color(0.92, 0.8, 0.15))
	hb.add_box(Vector3(-0.95, 0.6, -2.0), Vector3(0.06, 0.5, 0.9), Color(0.92, 0.8, 0.15))
	hb.add_prism(Vector3(-0.9, 0.95, -2.15), Vector3(0.9, 0.95, -2.15), 0.26, 0.26, 8, Color(0.75, 0.25, 0.15), Color(0.75, 0.25, 0.15), true, true)
	_mesh_node(harvester, hb.build())
	add_child(harvester)
	impl_nodes["harvester"] = harvester

	var blue := Color(0.2, 0.45, 0.75)
	var spreader := Node3D.new()
	var fb := MeshBuilder.new()
	fb.add_box(Vector3(0, 0.55, -1.5), Vector3(1.4, 0.08, 0.1), dark)
	fb.add_prism(Vector3(0, 1.3, -1.85), Vector3(0, 0.75, -1.85), 0.55, 0.15, 10, blue, blue, true)
	fb.add_prism(Vector3(0, 0.62, -2.25), Vector3(0, 0.58, -2.25), 0.45, 0.45, 10, steel, steel, true, true)
	_mesh_node(spreader, fb.build())
	add_child(spreader)
	impl_nodes["spreader"] = spreader

	# Hitch at the rear of the tractor. Wide and extra implements are built from the catalogue
	# and attached here the first time they are used.
	attach = Node3D.new()
	attach.name = "AttachmentPoint"
	attach.position = BUILTIN_HITCH
	add_child(attach)
	wheels = builtin_wheels

	# Cheap blob shadow (visible when real shadows are off)
	var bb := MeshBuilder.new()
	bb.add_flat_quad(Vector3(-0.95, 0.03, -1.4), Vector3(1.25, 0.03, -1.4), Vector3(1.25, 0.03, 1.7), Vector3(-0.95, 0.03, 1.7), Color(0, 0, 0, 1))
	var blob_mat := StandardMaterial3D.new()
	blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_mat.albedo_color = Color(0, 0, 0, 0.3)
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	blob = MeshInstance3D.new()
	blob.mesh = bb.build()
	blob.material_override = blob_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)

func set_blob_visible(on: bool) -> void:
	if blob != null:
		blob.visible = on

# Builds the model for a catalogue implement the first time it is shown: the real .glb on the
# hitch when it loads, otherwise the built-in model.
func _ensure_implement(id: String) -> void:
	if id == "none" or glb_impl.has(id) or not ImplementData.ITEMS.has(id):
		return
	if MachineModels.glb_scene(str(ImplementData.ITEMS[id]["model_path"])) != null:
		var node: Node3D = MachineModels.instance_for(id)
		if node != null:
			attach.add_child(node)
			glb_impl[id] = node
			return
	if not impl_nodes.has(id):
		impl_nodes[id] = _mesh_node(attach, ImplementModels.build(id))

# Where a node sits in the model's own space, through any parent nodes (articulated tractors).
func _pos_in_root(root: Node3D, n: Node3D) -> Vector3:
	var p := Vector3.ZERO
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			p = (cur as Node3D).transform * p
		cur = cur.get_parent()
	return p

# Shows the real tractor model for a catalogue vehicle id when its .glb loads, otherwise the
# built-in tractor. The real model's middle is put on the tractor position, so work stays put.
func _apply_vehicle(vid: String) -> void:
	cur_vehicle = vid
	if glb_vehicle != null:
		remove_child(glb_vehicle)
		glb_vehicle.free()
		glb_vehicle = null
	steer_pivots = []
	wheels = builtin_wheels
	var veh: Dictionary = VehicleData.get_vehicle(vid)
	var scene: PackedScene = null
	if not veh.is_empty() and str(veh["type"]) == "tractor":
		scene = MachineModels.glb_scene(str(veh["model_path"]))
	body_mi.visible = scene == null
	for bw in builtin_wheels:
		bw["node"].visible = scene == null
	attach.position = BUILTIN_HITCH
	if scene == null:
		return
	var sc := float(veh["model_scale"])
	var inst: Node3D = scene.instantiate()
	inst.scale = Vector3(sc, sc, sc)
	inst.rotation.y = PI
	inst.position.z = MachineModels.bounds_of(inst).get_center().z * sc
	add_child(inst)
	glb_vehicle = inst
	var hitch = inst.find_child("Hitch_Rear", true, false)
	if hitch is Node3D:
		var hp: Vector3 = _pos_in_root(inst, hitch as Node3D)
		attach.position = Vector3(-hp.x * sc, hp.y * sc, -hp.z * sc + inst.position.z)
	var real_wheels: Array = []
	for nm in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wn = inst.find_child(nm, true, false)
		if wn is MeshInstance3D:
			var r := maxf(0.15, (wn as MeshInstance3D).get_aabb().size.y * 0.5 * sc)
			real_wheels.append({"node": wn, "radius": r, "angle": 0.0, "sign": -1.0})
	for nm in ["SteerPivot_L", "SteerPivot_R"]:
		var pn = inst.find_child(nm, true, false)
		if pn is Node3D:
			steer_pivots.append(pn)
	if not real_wheels.is_empty():
		wheels = real_wheels
	for bw in builtin_wheels:
		bw["node"].visible = false

func update_from(v: Dictionary, dt: float = 0.0) -> void:
	if attach == null:
		_build_builtin()
	var vid := str(v.get("vehicle", "tractor"))
	if vid != cur_vehicle:
		_apply_vehicle(vid)
	var id: String = v["implement"]
	_ensure_implement(id)
	var heading: float = v["heading"]
	var sp: float = v["speed"]
	if dt > 0.0:
		if motion_ready:
			var acc: float = (sp - prev_speed) / dt
			var yaw_rate: float = wrapf(heading - prev_heading, -PI, PI) / dt
			yaw_vis = yaw_rate
			Suspension.step(susp, acc, sp, yaw_rate, dt)
		prev_speed = sp
		prev_heading = heading
		motion_ready = true
	else:
		motion_ready = false
	position = Vector3(v["x"], float(susp["bounce"]), v["z"])
	rotation = Vector3(float(susp["pitch"]), heading, float(susp["roll"]))
	attach.rotation.x = float(susp["impl_pitch"])
	for k in impl_nodes:
		impl_nodes[k].visible = (k == id) and not glb_impl.has(k)
	for k in glb_impl:
		glb_impl[k].visible = (k == id)
	if dt > 0.0:
		for w in wheels:
			w["angle"] = fposmod(float(w["angle"]) + sp * dt / float(w["radius"]), TAU)
			w["node"].rotation.x = float(w["sign"]) * float(w["angle"])
		# Real front wheels turn into the bend (looks only).
		var want := clampf(yaw_vis * 0.35 * (1.0 if sp >= 0.0 else -1.0), -0.5, 0.5)
		steer_vis = lerpf(steer_vis, want, minf(1.0, dt * 8.0))
		for p in steer_pivots:
			p.rotation.y = steer_vis
