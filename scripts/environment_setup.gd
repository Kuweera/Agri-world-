extends Node3D

var sun: DirectionalLight3D
var env_instance: WorldEnvironment

func _ready() -> void:
	# Initialize a single, optimized master directional light source
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	# Configure the master 3D environmental container profile
	env_instance = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95) # Default atmospheric fallback tint
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env_instance.environment = env
	add_child(env_instance)

# Configures visual performance tiers based on local settings menu
func apply_quality_profile(profile_name: String) -> void:
	if sun == null or env_instance == null:
		return
		
	var env = env_instance.environment
	match profile_name.lower():
		"low":
			# Maximum performance baseline for mobile hardware
			sun.shadow_enabled = false
			env.background_mode = Environment.BG_COLOR
		"medium", "high":
			# Adds deep shadow fields and depth mapping
			sun.shadow_enabled = true
			sun.shadow_blur = 1.2
			
			# Enable real-world procedural atmospheric gradient maps
			env.background_mode = Environment.BG_SKY
			var sky_obj := Sky.new()
			sky_obj.sky_material = ProceduralSkyMaterial.new()
			env.sky = sky_obj
