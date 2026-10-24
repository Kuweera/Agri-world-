extends RefCounted
# The yard beside the farmhouse where a new machine appears. Pure maths, so the game and the
# tests agree. Machines are not tied to a slot: once bought they stay wherever they were left.
# Heading 0 faces +z; heading PI faces the field.

const VehicleData := preload("res://scripts/vehicle_data.gd")
const Hitbox := preload("res://scripts/hitbox.gd")

const FIELD_FACING := PI
const HOUSE_CENTRE := Vector2(0.0, 7.5)
# The yard: machine middles stay in here (the farmhouse is cut out by VehicleData.OBSTACLES).
const YARD_X := 10.3
const YARD_Z0 := 4.8
const YARD_Z1 := 10.4
# The ploughed field, with a little room round it (x, z, width, depth).
const FIELD_RECT := Rect2(-6.8, -10.8, 13.6, 13.4)
const GAP := 0.15      # clear space kept between parked machines

# A free pose in the yard for a new machine, as close to the house as it fits and facing the
# field if possible. `others` are the machine dictionaries already standing there.
# Returns {x, z, heading}, or an empty dictionary if nothing fits.
static func find_spot(id: String, others: Array) -> Dictionary:
	if not VehicleData.VEHICLES.has(id):
		return {}
	var best := _search(id, others, true)
	if best.is_empty():
		# The yard is full: use the strip of grass beside the field.
		best = _search(id, others, false)
	return best

static func _search(id: String, others: Array, yard_only: bool) -> Dictionary:
	var best := {}
	var best_score := 1.0e9
	var heads := [PI, 0.5 * PI, 1.5 * PI, 0.0]
	var z_from := int((YARD_Z0 if yard_only else -YARD_Z1) * 10.0)
	var xi := -103
	while xi <= 103:
		var zi := z_from
		while zi <= int(YARD_Z1 * 10.0):
			var x := float(xi) / 10.0
			var z := float(zi) / 10.0
			for h in heads:
				var score := Vector2(x, z).distance_to(HOUSE_CENTRE) + (0.0 if h == PI else 3.0)
				if score >= best_score:
					continue
				var probe := {"x": x, "z": z, "heading": h, "vehicle": id}
				if _fits(probe, others, yard_only):
					best = {"x": x, "z": z, "heading": h}
					best_score = score
			zi += 4
		xi += 4
	return best

static func _fits(probe: Dictionary, others: Array, yard_only: bool = true) -> bool:
	var mine: Array = Hitbox.of_machine(probe, true)
	for c in mine:
		if absf(c.x) + c.z > YARD_X + 1.6:
			return false
		if yard_only:
			if c.y - c.z < YARD_Z0 - 1.2 or c.y + c.z > YARD_Z1 + 1.2:
				return false
		else:
			# Outside the yard: stay off the field.
			if c.y + c.z > YARD_Z1 + 1.2 or c.y - c.z < -YARD_Z1 - 1.0:
				return false
			if Hitbox.circle_hits_rect(Vector3(c.x, c.y, c.z + 0.2), FIELD_RECT):
				return false
		for r in VehicleData.OBSTACLES:
			if Hitbox.circle_hits_rect(Vector3(c.x, c.y, c.z + 0.2), r):
				return false
	for o in others:
		if Hitbox.penetration(mine, Hitbox.of_machine(o, true)) > -GAP:
			return false
	return true
