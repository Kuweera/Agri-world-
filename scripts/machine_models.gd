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
const TractorViewScript := preload("res://scripts/tractor_view.gd")

const TILE_PITCH := 1.5

# The scene in a .glb file, or null if the path is empty, missing or not a scene.
static func glb_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res
	return null

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
		return TractorViewScript.new()
	return null
