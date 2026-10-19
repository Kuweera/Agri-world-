extends Node3D

const CropModels := preload("res://scripts/crop_models.gd")
const CropStages := preload("res://scripts/crop_stages.gd")
const CropData := preload("res://scripts/crop_data.gd")

const COLS := 8
const ROWS := 8
const TILE_SIZE := 2.0

var tile_nodes: Array = []
var mesh_cache: Dictionary = {}

func _ready() -> void:
	print("Grid initialization started.")
	tile_nodes.clear()
	
	for row in ROWS:
		for col in COLS:
			var tm := MeshInstance3D.new()
			tm.position = Vector3(
				(col - COLS / 2.0) * TILE_SIZE + TILE_SIZE / 2.0,
				0.0,
				(row - ROWS / 2.0) * TILE_SIZE + TILE_SIZE / 2.0
			)
			add_child(tm)
			tile_nodes.append(tm)
	print("Grid nodes successfully generated.")

func world_to_tile(world_pos: Vector3) -> int:
	var cx := floori((world_pos.x + (COLS * TILE_SIZE) / 2.0) / TILE_SIZE)
	var cz := floori((world_pos.z + (ROWS * TILE_SIZE) / 2.0) / TILE_SIZE)
	if cx < 0 or cx >= COLS or cz < 0 or cz >= ROWS:
		return -1
	return cz * COLS + cx

func refresh_tile(i: int, tile_data: Dictionary, progress: float, is_selected: bool) -> void:
	if i < 0 or i >= tile_nodes.size():
		return
		
	var mi: MeshInstance3D = tile_nodes[i]
	var state: String = tile_data["state"]
	var crop_id: String = tile_data["crop"]
	
	var stage_idx := CropStages.get_stage_index(crop_id, progress)
	var cache_key := "%s_%s_%d_%s" % [state, crop_id, stage_idx, "sel" if is_selected else "nor"]
	
	if mesh_cache.has(cache_key):
		mi.mesh = mesh_cache[cache_key]
		return
		
	var combined_mesh := ArrayMesh.new()
	var st_mesh := _generate_base_ground_mesh(state, is_selected)
	
	if st_mesh and st_mesh.get_surface_count() > 0:
		combined_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, 
			st_mesh.surface_get_arrays(0)
		)
		
	if state == "growing" and crop_id != "":
		var crop_mesh := CropModels.generate_crop_mesh(crop_id, stage_idx)
		if crop_mesh and crop_mesh.get_surface_count() > 0:
			var crop_arrays = crop_mesh.surface_get_arrays(0)
			var p_count: int = CropData.CROPS[crop_id]["visual"]["plants_per_tile"]
			var verts: PackedVector3Array = crop_arrays[Mesh.ARRAY_VERTEX]
			var shifted_verts := PackedVector3Array()
			var shifted_indices := PackedInt32Array()
			var combined_indices: PackedInt32Array = crop_arrays[Mesh.ARRAY_INDEX]
			
			for p in p_count:
				var offset_idx := shifted_verts.size()
				var ox := -0.5 + (p % 2) * 1.0 + (randf() - 0.5) * 0.2
				var oz := -0.5 + floorf(p / 2.0) * 1.0 + (randf() - 0.5) * 0.2
				
				for v_idx in verts.size():
					shifted_verts.append(verts[v_idx] + Vector3(ox, 0.0, oz))
					
				for ind in combined_indices:
					shifted_indices.append(ind + offset_idx)
					
			crop_arrays[Mesh.ARRAY_VERTEX] = shifted_verts
			crop_arrays[Mesh.ARRAY_INDEX] = shifted_indices
			combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, crop_arrays)
			
	mesh_cache[cache_key] = combined_mesh
	mi.mesh = combined_mesh

func _generate_base_ground_mesh(state: String, selected: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	
	var h := TILE_SIZE / 2.0
	verts.append(Vector3(-h, 0.0, -h))
	verts.append(Vector3(h, 0.0, -h))
	verts.append(Vector3(h, 0.0, h))
	verts.append(Vector3(-h, 0.0, h))
	
	# ABSOLUTE FIX: Hardcoded layout indexing vectors to map the 3D surface plane correctly
	indices.append(0)
	indices.append(1)
	indices.append(2)
	indices.append(0)
	indices.append(2)
	indices.append(3)
	
	var col := Color(0.22, 0.45, 0.15) 
	match state:
		"ploughed":
			col = Color(0.28, 0.20, 0.14) 
		"growing":
			col = Color(0.24, 0.18, 0.12) 
		"stubble":
			col = Color(0.35, 0.30, 0.18) 
			
	if selected:
		col = col.lerp(Color(0.95, 0.85, 0.1), 0.35) 
		
	for i in 4:
		colors.append(col)
		
	return preload("res://scripts/mesh_builder.gd").build_mesh(verts, indices, colors)
