extends RefCounted
# Pure logic (no 3D): turns growth progress (0.0 to 1.0) into a stage.
# Stage thresholds come from crop_data.gd. Unknown crops use DEFAULT_STAGES.

const CropData := preload("res://scripts/crop_data.gd")

const DEFAULT_STAGES := [
	{"name": "sprout", "from": 0.0},
	{"name": "growing", "from": 0.34},
	{"name": "ripe", "from": 1.0},
]

static func stages_for(crop_id: String) -> Array:
	if CropData.CROPS.has(crop_id):
		var crop: Dictionary = CropData.CROPS[crop_id]
		if crop.has("visual"):
			var vis: Dictionary = crop["visual"]
			if vis.has("stages"):
				return vis["stages"]
	return DEFAULT_STAGES

static func stage_count(crop_id: String) -> int:
	return stages_for(crop_id).size()

static func get_stage_index(crop_id: String, progress: float) -> int:
	var stages: Array = stages_for(crop_id)
	var idx := 0
	for i in stages.size():
		if progress >= float(stages[i]["from"]):
			idx = i
	return idx

static func get_stage_name(crop_id: String, progress: float) -> String:
	var stages: Array = stages_for(crop_id)
	return str(stages[get_stage_index(crop_id, progress)]["name"])
