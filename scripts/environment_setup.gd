extends Node3D
# Sun, sky and ambient light, plus the settings for each graphics quality level.
# The numbers live in PROFILES so they are easy to tune. Quality is 0 Low, 1 Medium, 2 High.

const PROFILES := [
	{"name": "Low", "shadows": false, "shadow_distance": 0.0, "atlas": 0, "sky": false},
	{"name": "Medium", "shadows": true, "shadow_distance": 30.0, "atlas": 1024, "sky": true},
	{"name": "High", "shadows": true, "shadow_distance": 45.0, "atlas": 2048, "sky": true},
]

var sun: DirectionalLight3D
var env: Environment
var sky_obj: Sky

# Pure logic (no 3D), so the tests can check it: settings for one quality level.
static func profile(q: int) -> Dictionary:
	return PROFILES[clampi(q, 0, PROFILES.size() - 1)]

func _init() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.48, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
	sky_mat.ground_horizon_color = Color(0.72, 0.84, 0.95)
	sky_mat.ground_bottom_color = Color(0.3, 0.4, 0.25)
	sky_obj = Sky.new()
	sky_obj.sky_material = sky_mat
	sky_obj.radiance_size = Sky.RADIANCE_SIZE_32

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.54, 0.62)
	we.environment = env
	add_child(we)

func apply_quality(q: int) -> void:
	var p: Dictionary = profile(q)
	sun.shadow_enabled = bool(p["shadows"])
	if bool(p["shadows"]):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = float(p["shadow_distance"])
		sun.shadow_bias = 0.08
		RenderingServer.directional_shadow_atlas_set_size(int(p["atlas"]), true)
	if bool(p["sky"]):
		env.background_mode = Environment.BG_SKY
		env.sky = sky_obj
	else:
		env.background_mode = Environment.BG_COLOR
