extends Node
# Diagnostic A: 2D only. If this shows text, the engine runs on the phone.

func _ready() -> void:
	var size := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.4, 0.2)
	bg.size = size
	add_child(bg)
	var l := Label.new()
	l.position = Vector2(30, 30)
	l.add_theme_font_size_override("font_size", 30)
	l.text = "2D OK\nGPU: %s\nVendor: %s\nOS: %s %s\nModel: %s\nCPU: %s" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
		OS.get_name(), OS.get_version(),
		OS.get_model_name(),
		OS.get_processor_name()]
	add_child(l)
