extends Node3D

var sun: DirectionalLight3D
var env_instance: WorldEnvironment

func _ready() -> void:
	print("[DEBUG 1.5] Initializing Environment Setup Node")
	
	# Create a clean, safe directional sun light source
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	print("[DEBUG 1.6] Sun Light Node Attached")

	# Safe baseline environment wrapper with ZERO risky sky shaders
	env_instance = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95) # Sky blue fallback
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env_instance.environment = env
	add_child(env_instance)
	print("[DEBUG 1.7] WorldEnvironment Setup Completed cleanly")

func apply_quality_profile(profile_name: String) -> void:
	if sun == null or env_instance == null:
		return
		
	# Force mobile-friendly baseline rendering to protect the PowerVR GPU
	sun.shadow_enabled = false
	if env_instance.environment:
		env_instance.environment.background_mode = Environment.BG_COLOR
