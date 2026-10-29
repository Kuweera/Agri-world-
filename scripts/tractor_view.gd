extends Node3D
# Presentation only: one machine (tractor or combine) and the tool it carries.
# It shows the real .glb model; a simple built-in tractor stands in if the file is missing.
# The machine faces +z in local space, so rotation.y = heading.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const ImplementData := preload("res://scripts/implement_data.gd")
const ImplementModels := preload("res://scripts/implement_models.gd")
const Suspension := preload("res://scripts/suspension.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const MachineModels := preload("res://scripts/machine_models.gd")

# Where implements hang on the built-in tractor. A real tractor model sets its own.
const BUILTIN_HITCH := Vector3(0, 0.35, -1.25)
# Lifting the tool (3-point hitch / combine header): seconds to move, and how far it goes up.
const LIFT_TIME := 0.45
const LIFT_Y := 0.28
const LIFT_PITCH := 0.38
const HEADER_LIFT := 0.5      # metres in the model's own size
# Track animation (model Tractor_Heavy_Tracked.glb): five shifted cleat rings per pod.
const TRACK_TAGS := ["FL", "FR", "RL", "RR"]
const TRACK_VARIANTS := 5
const TRACK_PITCH := 0.23622  # metres between cleats, as built
const TRACK_VISUAL := 0.3     # how fast the tread runs compared with the ground (looks only)
const TRACK_PARTS := [["Track_Sprocket_", 0.6], ["Track_Idler_F_", 0.39], ["Track_Idler_R_", 0.39],
	["Track_Roller_0_", 0.14], ["Track_Roller_1_", 0.14], ["Track_Roller_2_", 0.14]]

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
var raised := true            # where the driver wants the tool: up (travel) or down (work)
var lift := 1.0               # 1 = fully up, 0 = fully down on the ground
var hitch_pos := BUILTIN_HITCH
var is_combine := false
var rear_steer := false
var reel_node: Node3D
var header_node: Node3D
var header_base_y := 0.0
var reel_angle := 0.0
# Tracked tractors: sprocket, idlers and rollers spin; the cleat ring steps round the belt.
var track_spin: Array = []     # [{"node", "radius", "angle"}]
var track_cleats: Array = []   # one array of shifted cleat rings per track pod
var track_dist := 0.0
var track_pitch := TRACK_PITCH
var track_vi := -1
var blob: MeshInstance3D
var attach: Node3D                       # AttachmentPoint: implements built from the catalogue hang here
var susp := Suspension.new_state()       # springs for lean (looks only); the tyres stay on the ground
var foot_half_len := 1.15                # half the machine's length and width (model size), limits the lean
var foot_half_wid := 0.7
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
		_build_base()

# The hitch point and the blob shadow. The built-in tractor is only built when it is needed.
func _build_base() -> void:
	mat_vc = MeshBuilder.vc_material()
	# Hitch at the rear of the machine. Implements are built from the catalogue and attached
	# here the first time they are used.
	attach = Node3D.new()
	attach.name = "AttachmentPoint"
	attach.position = BUILTIN_HITCH
	add_child(attach)

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

# The simple built-in tractor: a stand-in when a model file is missing.
func _build_builtin_tractor() -> void:
	if body_mi != null:
		return
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

# Shows the real model for a catalogue vehicle (tractor or combine) when its .glb loads,
# otherwise the built-in tractor. The real model's middle is put on the vehicle position, so
# work stays put.
func _apply_vehicle(vid: String) -> void:
	cur_vehicle = vid
	if glb_vehicle != null:
		remove_child(glb_vehicle)
		glb_vehicle.free()
		glb_vehicle = null
	steer_pivots = []
	reel_node = null
	header_node = null
	is_combine = false
	rear_steer = false
	track_spin = []
	track_cleats = []
	track_vi = -1
	wheels = builtin_wheels
	var veh: Dictionary = VehicleData.get_vehicle(vid)
	foot_half_len = float(veh.get("hit_len", 2.3)) * 0.5
	foot_half_wid = float(veh.get("hit_wid", 1.4)) * 0.5
	var scene: PackedScene = null
	if not veh.is_empty():
		scene = MachineModels.glb_scene(str(veh["model_path"]))
	if scene == null:
		_build_builtin_tractor()
		wheels = builtin_wheels
	if body_mi != null:
		body_mi.visible = scene == null
		for bw in builtin_wheels:
			bw["node"].visible = scene == null
	hitch_pos = BUILTIN_HITCH
	if scene == null:
		return
	is_combine = str(veh["type"]) == "harvester"
	rear_steer = bool(veh.get("rear_steer", false))
	var tracked := bool(veh.get("tracked", false))
	var sc := float(veh["model_scale"])
	var inst: Node3D = scene.instantiate()
	inst.scale = Vector3(sc, sc, sc)
	inst.rotation.y = PI
	var mb := MachineModels.bounds_of(inst)
	inst.position.z = mb.get_center().z * sc
	# Stand the model on the ground: some models were built with their tyres a few cm below
	# (sinking) or above y = 0.
	inst.position.y = -mb.position.y * sc
	# The lean is limited by the model's real extent (a combine's header sticks out wide).
	foot_half_len = mb.size.z * sc * 0.5
	foot_half_wid = mb.size.x * sc * 0.5
	add_child(inst)
	glb_vehicle = inst
	var hitch = inst.find_child("Hitch_Rear", true, false)
	if hitch is Node3D and not is_combine:
		var hp: Vector3 = _pos_in_root(inst, hitch as Node3D)
		hitch_pos = Vector3(-hp.x * sc, hp.y * sc + inst.position.y, -hp.z * sc + inst.position.z)
	var real_wheels: Array = []
	if not tracked:
		for nm in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			var wn = inst.find_child(nm, true, false)
			if wn is MeshInstance3D:
				var r := maxf(0.15, (wn as MeshInstance3D).get_aabb().size.y * 0.5 * sc)
				real_wheels.append({"node": wn, "radius": r, "angle": 0.0, "sign": -1.0})
		for nm in ["SteerPivot_L", "SteerPivot_R", "SteerPivot_RL", "SteerPivot_RR"]:
			var pn = inst.find_child(nm, true, false)
			if pn is Node3D:
				steer_pivots.append(pn)
	wheels = real_wheels
	if tracked:
		_setup_tracks(inst, sc)
	if is_combine:
		var rn = inst.find_child("Reel", true, false)
		if rn is Node3D:
			reel_node = rn
		var hn = inst.find_child("Header", true, false)
		if hn is Node3D:
			header_node = hn
			header_base_y = (hn as Node3D).position.y

# Finds the parts of the four track pods that move: sprocket, idlers, rollers and the cleat rings.
func _setup_tracks(inst: Node3D, sc: float) -> void:
	track_pitch = TRACK_PITCH * sc
	for tag in TRACK_TAGS:
		var ring: Array = []
		for j in TRACK_VARIANTS:
			var cn = inst.find_child("Track_Cleats_%s_%d" % [tag, j], true, false)
			if cn is Node3D:
				ring.append(cn)
		if not ring.is_empty():
			track_cleats.append(ring)
		for part in TRACK_PARTS:
			var pn = inst.find_child(str(part[0]) + tag, true, false)
			if pn is Node3D:
				track_spin.append({"node": pn, "radius": float(part[1]) * sc, "angle": 0.0})
	_show_cleat_ring(0)

# Shows one of the shifted cleat rings on every pod and hides the others.
func _show_cleat_ring(vi: int) -> void:
	if vi == track_vi:
		return
	track_vi = vi
	for ring in track_cleats:
		for k in ring.size():
			(ring[k] as Node3D).visible = (k == vi)

# Raise or lower the tool (a combine's header). It moves smoothly in update_from().
func set_raised(on: bool) -> void:
	raised = on

# True once the tool is all the way down on the ground.
func is_down() -> bool:
	return lift < 0.15

func update_from(v: Dictionary, dt: float = 0.0) -> void:
	if attach == null:
		_build_base()
	var vid := str(v.get("vehicle", "tractor"))
	if vid != cur_vehicle:
		_apply_vehicle(vid)
	var id: String = "none" if is_combine else str(v["implement"])
	_ensure_implement(id)
	var heading: float = v["heading"]
	var sp: float = v["speed"]
	if dt > 0.0:
		if motion_ready:
			var acc: float = (sp - prev_speed) / dt
			var yaw_rate: float = wrapf(heading - prev_heading, -PI, PI) / dt
			yaw_vis = yaw_rate
			Suspension.step(susp, acc, sp, yaw_rate, dt, foot_half_len, foot_half_wid)
		prev_speed = sp
		prev_heading = heading
		motion_ready = true
	else:
		motion_ready = false
	position = Vector3(v["x"], Suspension.body_y(susp, foot_half_len, foot_half_wid), v["z"])
	rotation = Vector3(float(susp["pitch"]), heading, float(susp["roll"]))
	if dt > 0.0:
		lift = move_toward(lift, 1.0 if raised else 0.0, dt / LIFT_TIME)
	attach.position = hitch_pos + Vector3(0.0, lift * LIFT_Y, 0.0)
	attach.rotation.x = float(susp["impl_pitch"]) + lift * LIFT_PITCH
	if header_node != null:
		header_node.position.y = header_base_y + lift * HEADER_LIFT / maxf(0.01, glb_vehicle.scale.y)
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
			p.rotation.y = -steer_vis if rear_steer else steer_vis
		if not track_spin.is_empty():
			for ts in track_spin:
				ts["angle"] = fposmod(float(ts["angle"]) + sp * dt / float(ts["radius"]), TAU)
				ts["node"].rotation.x = -float(ts["angle"])
			track_dist += sp * dt * TRACK_VISUAL
			var phase := fposmod(track_dist / track_pitch, 1.0)
			_show_cleat_ring(int(phase * float(TRACK_VARIANTS)) % TRACK_VARIANTS)
		# The reel turns while the header is down and the machine is moving.
		if reel_node != null and lift < 0.5 and absf(sp) > 0.05:
			reel_angle = fposmod(reel_angle + 4.0 * dt, TAU)
			reel_node.rotation.x = reel_angle
