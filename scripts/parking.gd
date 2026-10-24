extends RefCounted
# Where owned machines wait when they are not being driven: a yard beside the farmhouse.
# Pure data, so the game, the tests and the autopilot agree. Parked machines are scenery:
# nothing collides with them. Heading 0 faces +z; heading PI faces the field.

const FIELD_FACING := PI

# id: {"x", "z", "heading"}. Right of the house: three tractors and the small combine.
# Left of the house: the large combine.
const SLOTS := {
	"tractor": {"x": 9.3, "z": 5.6, "heading": 1.5 * PI},
	"tractor_heavy": {"x": 9.3, "z": 7.7, "heading": 1.5 * PI},
	"tractor_tracked": {"x": 9.3, "z": 9.8, "heading": 1.5 * PI},
	"combine_small": {"x": 5.0, "z": 7.6, "heading": PI},
	"combine_large": {"x": -7.1, "z": 7.7, "heading": 0.5 * PI},
}

static func has_slot(id: String) -> bool:
	return SLOTS.has(id)

# The slot as a pose a driver starts from: same place, but facing the field.
static func start_pose(id: String) -> Dictionary:
	if not SLOTS.has(id):
		return {}
	var s: Dictionary = SLOTS[id]
	return {"x": float(s["x"]), "z": float(s["z"]), "heading": FIELD_FACING}
