extends RefCounted
# Builds a 3D model node for a catalogue vehicle or implement (used by the shop preview now,
# and the field later). It uses the .glb from model_path when that loads. Otherwise it falls
# back to the built-in implement model, or the built-in tractor view for tractors. It returns
# null when there is nothing to show (for example a combine without its .glb).
# The .glb files are in metres with the front toward -Z. The game faces +Z and is smaller,
# so models are turned around and scaled by model_scale. An implement's origin is its hitch.

const ImplementData := preload("res://scripts/implement_data.gd")
const VehicleData := preload("res://scripts/vehicle_data.gd")
const ImplementModels := preload("res://scripts/implement_models.gd")
const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const TRACTOR_VIEW_PATH := "res://scripts/tractor_view.gd"   # loaded when needed: tractor_view.gd preloads this file

const TILE_PITCH := 1.5

# The scene in a .glb file, or null if the path is empty, missing or not a scene.
static func glb_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res
	return null

# The box around every mesh under a node, in the node's own space (its own transform not applied).
# A node with no meshes gives a small default box.
static func bounds_of(node: Node3D) -> AABB:
	var box := {"aabb": AABB(), "has": false}
	_collect_bounds(node, Transform3D.IDENTITY, box)
	if not bool(box["has"]):
		return AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2))
	return box["aabb"]

static func _collect_bounds(n: Node, xf: Transform3D, box: Dictionary) -> void:
	for child in n.get_children():
		if not (child is Node3D):
			continue
		var cxf: Transform3D = xf * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var a: AABB = cxf * (child as MeshInstance3D).mesh.get_aabb()
			if bool(box["has"]):
				box["aabb"] = (box["aabb"] as AABB).merge(a)
			else:
				box["aabb"] = a
				box["has"] = true
		_collect_bounds(child, cxf, box)

# A vehicle standing still in the yard (scenery): its middle on the node's origin, front toward
# +Z like a driven one. Null when its .glb is missing.
static func parked_vehicle(id: String) -> Node3D:
	if not VehicleData.VEHICLES.has(id):
		return null
	if glb_scene(str(VehicleData.VEHICLES[id]["model_path"])) == null:
		return null
	var node: Node3D = _vehicle(id)
	if node == null or node.get_child_count() == 0:
		return node
	var c: Vector3 = bounds_of(node).get_center()
	(node.get_child(0) as Node3D).position -= Vector3(c.x, 0.0, c.z)
	return node

# Node3D for a catalogue id, or null if the id is unknown or has nothing to show.
static func instance_for(id: String) -> Node3D:
	if ImplementData.ITEMS.has(id):
		return _implement(id)
	if VehicleData.VEHICLES.has(id):
		return _vehicle(id)
	return null

static func _implement(id: String) -> Node3D:
	var item: Dictionary = ImplementData.ITEMS[id]
	var root := Node3D.new()
	var scene := glb_scene(str(item["model_path"]))
	if scene == null:
		var mi := MeshInstance3D.new()
		mi.mesh = ImplementModels.build(id)
		mi.material_override = MeshBuilder.vc_material()
		root.add_child(mi)
		return root
	var gang := maxi(1, int(item["model_gang"]))
	var s := float(item["model_scale"])
	for g in gang:
		var inst: Node3D = scene.instantiate()
		inst.scale = Vector3(s, s, s)
		inst.rotation.y = PI
		inst.position.x = (float(g) - float(gang - 1) * 0.5) * TILE_PITCH
		root.add_child(inst)
	if gang > 1:
		var bar := MeshBuilder.new()
		bar.add_box(Vector3(0, 0.4, -0.35), Vector3(float(gang) * TILE_PITCH, 0.1, 0.12), Color(0.2, 0.2, 0.23))
		var bi := MeshInstance3D.new()
		bi.mesh = bar.build()
		bi.material_override = MeshBuilder.vc_material()
		root.add_child(bi)
	return root

static func _vehicle(id: String) -> Node3D:
	var veh: Dictionary = VehicleData.VEHICLES[id]
	var scene := glb_scene(str(veh["model_path"]))
	if scene != null:
		var root := Node3D.new()
		var inst: Node3D = scene.instantiate()
		var s := float(veh["model_scale"])
		inst.scale = Vector3(s, s, s)
		inst.rotation.y = PI
		root.add_child(inst)
		return root
	if veh["type"] == "tractor":
		var tv_script: GDScript = load(TRACTOR_VIEW_PATH)
		return tv_script.new()
	return null
