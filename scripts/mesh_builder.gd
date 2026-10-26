extends RefCounted
# Tiny mesh builder for flat-shaded, vertex-coloured low-poly meshes.
# Use the mesh with vc_material(): vertex colours become the albedo and the
# material is double-sided, so triangle winding order does not matter.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var use_uv := false   # set by add_card; then build() includes the UVs

static func vc_material(unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# Ground material: vertex colours tint a tiled detail texture (soil grain, grass blades).
# The texture is projected from world space, so the meshes need no UV coordinates.
# gain brightens the grey texture so the vertex colours keep their strength.
# If the texture file is missing or unreadable this returns the plain vertex-colour material.
static func textured_material(path: String, uv_scale: float, gain: float) -> StandardMaterial3D:
	var m := vc_material()
	if not ResourceLoader.exists(path):
		return m
	var src: Resource = load(path)
	if src == null or not (src is Texture2D):
		return m
	var img: Image = (src as Texture2D).get_image()
	if img == null or img.is_empty() or img.is_compressed():
		return m
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.albedo_color = Color(gain, gain, gain)
	return m

# Crop cards: a grey leaf/pod/cob atlas (alpha = shape) tinted by vertex colours.
# Alpha scissor is cheap on weak GPUs. If the atlas is missing the cards are plain coloured quads.
static func card_material(path: String) -> StandardMaterial3D:
	var m := vc_material()
	if not ResourceLoader.exists(path):
		return m
	var src: Resource = load(path)
	if src == null or not (src is Texture2D):
		return m
	var img: Image = (src as Texture2D).get_image()
	if img == null or img.is_empty() or img.is_compressed():
		return m
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # cards are seen from both sides
	return m

# UV rectangle of atlas cell i (4 x 4 grid, index = row * 4 + col), inset a little.
static func cell_uv(i: int) -> Rect2:
	var cx := float(i % 4) * 0.25
	var cy := floorf(float(i) / 4.0) * 0.25
	return Rect2(cx + 0.004, cy + 0.004, 0.242, 0.242)

static func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

func triangle_count() -> int:
	return floori(float(verts.size()) / 3.0)

func add_tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color,
		ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.ZERO, uc: Vector2 = Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.00000001:
		return
	n = n.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(ca)
	cols.append(cb)
	cols.append(cc)
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)

func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color,
		ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.ZERO, uc: Vector2 = Vector2.ZERO, ud: Vector2 = Vector2.ZERO) -> void:
	add_tri(a, b, c, ca, cb, cc, ua, ub, uc)
	add_tri(a, c, d, ca, cc, cd, ua, uc, ud)

func add_flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	add_quad(a, b, c, d, col, col, col, col)

# Box with a transform; the bottom corners are darkened (fake ambient occlusion).
func add_box_xf(xf: Transform3D, size: Vector3, color: Color, ao: float = 0.7) -> void:
	var h := size / 2.0
	var p: Array = []
	var c: Array = []
	for i in 8:
		var sx := 1.0 if (i & 4) != 0 else -1.0
		var sy := 1.0 if (i & 2) != 0 else -1.0
		var sz := 1.0 if (i & 1) != 0 else -1.0
		p.append(xf * Vector3(sx * h.x, sy * h.y, sz * h.z))
		c.append(shade(color, ao) if sy < 0.0 else color)
	var faces := [[4, 5, 7, 6], [0, 1, 3, 2], [2, 3, 7, 6], [0, 1, 5, 4], [1, 3, 7, 5], [0, 2, 6, 4]]
	for f in faces:
		add_quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], c[f[0]], c[f[1]], c[f[2]], c[f[3]])

func add_box(center: Vector3, size: Vector3, color: Color, yaw: float = 0.0, ao: float = 0.7) -> void:
	add_box_xf(Transform3D(Basis(Vector3.UP, yaw), center), size, color, ao)

# Tapered prism / cylinder from base to top (any direction).
func add_prism(base: Vector3, top: Vector3, r0: float, r1: float, sides: int,
		c0: Color, c1: Color, cap_top: bool = false, cap_base: bool = false) -> void:
	var axis := top - base
	if axis.length() < 0.0001:
		return
	axis = axis.normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		add_quad(base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1, c0, c0, c1, c1)
		if cap_top:
			add_tri(top, top + d0 * r1, top + d1 * r1, c1, c1, c1)
		if cap_base:
			add_tri(base, base + d0 * r0, base + d1 * r0, c0, c0, c0)

# A flat strip along a list of points (leaf blades, grass, straw).
# `side` is the direction the strip is wide in; widths has one entry per point.
func add_ribbon(points: Array, widths: Array, side: Vector3, c0: Color, c1: Color) -> void:
	var n := points.size()
	if n < 2:
		return
	for i in n - 1:
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var w0: float = widths[i]
		var w1: float = widths[i + 1]
		var col0 := c0.lerp(c1, t0)
		var col1 := c0.lerp(c1, t1)
		add_quad(p0 - side * (w0 * 0.5), p0 + side * (w0 * 0.5),
			p1 + side * (w1 * 0.5), p1 - side * (w1 * 0.5), col0, col0, col1, col1)

# Rhombus leaflet: base at -u, tip at +u, width along v.
func add_diamond(center: Vector3, u: Vector3, v: Vector3, c_base: Color, c_tip: Color) -> void:
	var mid := c_base.lerp(c_tip, 0.5)
	add_quad(center - u, center + v, center + u, center - v, c_base, mid, c_tip, mid)

# A textured leaf/pod card along a list of points (base first), like add_ribbon but with UVs.
# `rect` is the UV rectangle of the picture. It runs from its bottom (first point) to its top (last point).
# `side` is the direction the card is wide in; widths has one entry per point.
func add_card(points: Array, widths: Array, side: Vector3, rect: Rect2, c0: Color, c1: Color) -> void:
	var n := points.size()
	if n < 2:
		return
	use_uv = true
	var r := rect
	for i in n - 1:
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var hw0: float = float(widths[i]) * 0.5
		var hw1: float = float(widths[i + 1]) * 0.5
		var col0 := c0.lerp(c1, t0)
		var col1 := c0.lerp(c1, t1)
		var y0 := r.position.y + r.size.y * (1.0 - t0)
		var y1 := r.position.y + r.size.y * (1.0 - t1)
		var xl := r.position.x
		var xr := r.position.x + r.size.x
		add_quad(p0 - side * hw0, p0 + side * hw0, p1 + side * hw1, p1 - side * hw1,
			col0, col0, col1, col1, Vector2(xl, y0), Vector2(xr, y0), Vector2(xr, y1), Vector2(xl, y1))

func build() -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.size() == 0:
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	if use_uv and uvs.size() == verts.size():
		arr[Mesh.ARRAY_TEX_UV] = uvs
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
