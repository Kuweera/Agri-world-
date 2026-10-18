extends RefCounted

# Generates 3D meshes dynamically with full Vertex Color and UV Map texturing data
static func build_mesh(vertices: PackedVector3Array, indices: PackedInt32Array, colors: PackedColorArray, uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var am := ArrayMesh.new()
	if vertices.is_empty():
		return am
		
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
		
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	else:
		# Fallback blank UV map if none provided to keep shader materials safe
		var blank_uvs := PackedVector2Array()
		blank_uvs.resize(vertices.size())
		arrays[Mesh.ARRAY_TEX_UV] = blank_uvs
		
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
