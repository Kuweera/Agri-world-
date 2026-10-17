extends CanvasLayer
# On-screen info: FPS/memory (top-left) and selected-tile panel (bottom-left).

var stats := Label.new()
var tile_label := Label.new()

func _ready() -> void:
	stats.position = Vector2(20, 16)
	stats.add_theme_font_size_override("font_size", 26)
	add_child(stats)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 120)
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(20, vp.y - 140)
	add_child(panel)

	tile_label.add_theme_font_size_override("font_size", 28)
	tile_label.text = "Tap a tile"
	panel.add_child(tile_label)

func set_tile_text(t: String) -> void:
	tile_label.text = t

func _process(_delta: float) -> void:
	var mem := OS.get_static_memory_usage() / 1048576.0
	stats.text = "FPS: %d   Mem: %.0f MB" % [Engine.get_frames_per_second(), mem]
