extends Node3D
# Stage 1 entry point: wires light, sky, farm, camera and HUD together.

const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FarmGridScript := preload("res://scripts/farm_grid.gd")
const HudScript := preload("res://scripts/hud.gd")

var rig
var grid
var hud

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = env
	add_child(we)

	grid = FarmGridScript.new()
	add_child(grid)

	rig = CameraRigScript.new()
	rig.position = Vector3(0, 0, -1)
	add_child(rig)

	hud = HudScript.new()
	add_child(hud)

	rig.tapped.connect(_on_tapped)
	grid.selection_changed.connect(_on_selection_changed)

func _on_tapped(pos: Vector2) -> void:
	var hit = rig.ray_to_ground(pos)
	var idx := -1
	if hit != null:
		idx = grid.world_to_tile(hit)
	grid.select_tile(idx)

func _on_selection_changed(idx: int) -> void:
	hud.set_tile_text(grid.tile_text(idx))
