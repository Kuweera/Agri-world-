extends RefCounted

const CropData := preload("res://scripts/crop_data.gd")

# Calculates the precise visual stage index (0 to 3) for a given growth progress
static func get_stage_index(crop_id: String, progress: float) -> int:
	if not CropData.CROPS.has(crop_id):
		return 0
	
	var stages: Array = CropData.CROPS[crop_id]["visual"]["stages"]
	var target_idx := 0
	
	# Loop through thresholds to determine active visual stage
	for i in range(stages.size()):
		if progress >= float(stages[i]["from"]):
			target_idx = i
			
	return target_idx

# Returns string name of active stage
static func get_stage_name(crop_id: String, progress: float) -> String:
	if not CropData.CROPS.has(crop_id):
		return "unknown"
	var stages: Array = CropData.CROPS[crop_id]["visual"]["stages"]
	return stages[get_stage_index(crop_id, progress)]["name"]
  
