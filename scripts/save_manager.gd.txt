extends RefCounted
# Reads and writes the save file safely:
# write a temp file, keep the previous save as a backup, then swap.

const DEFAULT_PATH := "user://save.json"

static func save_state(state, path: String = DEFAULT_PATH) -> bool:
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(state.to_dict()))
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path) == OK

# Loads the save into `state`. Returns "" on success, "none" if there is no
# save file, or "corrupt" if no readable valid save was found.
static func load_into(state, path: String = DEFAULT_PATH) -> String:
	var tried := false
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		tried = true
		var data = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var err: String = state.from_dict(data)
		if err == "":
			return ""
	if tried:
		return "corrupt"
	return "none"
