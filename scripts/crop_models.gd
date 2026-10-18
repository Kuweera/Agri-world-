extends RefCounted

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const CropStages := preload("res://scripts/crop_stages.gd")

# Generates procedural 3D model meshes with UVs and Vertex Colors for each visual growth stage
static func generate_crop_mesh(crop_id: String, stage_idx: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	
	match crop_id:
		"maize":
			_build_maize_geometry(stage_idx, verts, indices, colors, uvs)
		"beans":
			_build_bean_geometry(stage_idx, verts, indices, colors, uvs)
			
	return MeshBuilder.build_mesh(verts, indices, colors, uvs)

static func _build_maize_geometry(stage: int, v: PackedVector3Array, idx: PackedInt32Array, c: PackedColorArray, uv: PackedVector2Array) -> void:
	var h := 0.0
	match stage:
		0: h = 0.15 # Sprout: Small green spike
		1: h = 0.50 # Vegetative: Growing stalk
		2: h = 1.10 # Mature: Tall stalk with tassels forming
		3: h = 1.40 # Ripe: Golden mature stalk with cobs
		
	# Stalk Core Structure
	var base_idx := v.size()
	var stalk_color := Color(0.35, 0.65, 0.2) if stage < 3 else Color(0.65, 0.60, 0.25)
	
	v.append(Vector3(-0.03, 0.0, -0.03))
	v.append(Vector3(0.03, 0.0, -0.03))
	v.append(Vector3(0.03, h, 0.03))
	v.append(Vector3(-0.03, h, 0.03))
	
	for i in 4:
		c.append(stalk_color)
		uv.append(Vector2(0.0, 0.0))
		
	idx.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])
	
	# Drooping Leaf Cards (Stages 1-3)
	if stage >= 1:
		var lf_color := Color(0.25, 0.55, 0.15) if stage < 3 else Color(0.6, 0.55, 0.2)
		var leaf_idx := v.size()
		
		# Crossing leaf planes
		v.append(Vector3(-0.25, h*0.6, 0.0))
		v.append(Vector3(0.25, h*0.6, 0.0))
		v.append(Vector3(0.0, h*0.3, -0.25))
		v.append(Vector3(0.0, h*0.3, 0.25))
		
		for i in 4:
			c.append(lf_color)
			uv.append(Vector2(0.5, 0.5))
			
		idx.append_array([leaf_idx, leaf_idx+1, leaf_idx+2, leaf_idx, leaf_idx+2, leaf_idx+3])

	# Ripe Cobs (Stage 3 Only)
	if stage == 3:
		var cob_idx := v.size()
		v.append(Vector3(0.05, h*0.4, 0.05))
		v.append(Vector3(0.12, h*0.5, 0.12))
		v.append(Vector3(0.02, h*0.55, 0.02))
		
		c.append_array([Color(0.85, 0.75, 0.1), Color(0.85, 0.75, 0.1), Color(0.3, 0.5, 0.15)])
		uv.append_array([Vector2(0.9, 0.9), Vector2(0.9, 0.9), Vector2(0.9, 0.9)])
		idx.append_array([cob_idx, cob_idx+1, cob_idx+2])

static func _build_bean_geometry(stage: int, v: PackedVector3Array, idx: PackedInt32Array, c: PackedColorArray, uv: PackedVector2Array) -> void:
	var r := 0.05
	var h := 0.05
	match stage:
		0: # Sprout
			r = 0.08
			h = 0.1
		1: # Vegetative bush
			r = 0.22
			h = 0.3
		2: # Mature flower bush
			r = 0.35
			h = 0.45
		3: # Ripe seed pods
			r = 0.40
			h = 0.5
			
	var bush_color := Color(0.2, 0.5, 0.1) if stage < 3 else Color(0.45, 0.5, 0.2)
	var base_idx := v.size()
	
	# Low-poly cross cluster to create optimal dense foliage look on mobile budget
	v.append(Vector3(-r, 0.0, -r))
	v.append(Vector3(r, h, r))
	v.append(Vector3(r, 0.0, -r))
	v.append(Vector3(-r, h, r))
	
	for i in 4:
		c.append(bush_color)
		uv.append(Vector2(0.1, 0.8))
		
	idx.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+3, base_idx+1])

	# Flower buds or hanging bean pods
	if stage == 2: # Flowers
		var fl_idx := v.size()
		v.append(Vector3(0.0, h*0.8, r*0.5))
		c.append(Color(0.9, 0.9, 0.95)) # White/purple accent buds
		uv.append(Vector2(0.1, 0.1))
		idx.append_array([fl_idx, fl_idx, fl_idx])
	elif stage == 3: # Pods
		var pd_idx := v.size()
		v.append(Vector3(r*0.4, h*0.4, 0.0))
		v.append(Vector3(r*0.5, h*0.2, 0.0))
		c.append_array([Color(0.5, 0.6, 0.2), Color(0.5, 0.6, 0.2)])
		uv.append_array([Vector2(0.2, 0.2), Vector2(0.2, 0.2)])
		idx.append_array([pd_idx, pd_idx+1, pd_idx])
