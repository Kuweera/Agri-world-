extends RefCounted
# Player settings (graphics quality, debug readout). Kept in a separate file from
# the game save so resetting the farm never changes the settings.

const DEFAULT_PATH := "user://settings.json"

static func defaults() -> Dictionary:
	return {"quality": 0, "debug": true}   # quality: 0 Low, 1 Medium, 2 High

# Accepts anything (even null) and returns a valid settings dictionary.
static func sanitize(data: Variant) -> Dictionary:
	var out := defaults()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var q = data.get("quality", 0)
	if (typeof(q) == TYPE_INT or typeof(q) == TYPE_FLOAT) and q >= 0 and q <= 2:
		out["quality"] = int(q)
	var d = data.get("debug", true)
	if typeof(d) == TYPE_BOOL:
		out["debug"] = d
	return out

static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	return sanitize(JSON.parse_string(FileAccess.get_file_as_string(path)))

static func save_settings(d: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sanitize(d)))
	f.close()
	return true
