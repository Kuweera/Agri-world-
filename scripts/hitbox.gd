extends RefCounted
# Footprints of machines, so they cannot drive through each other. Pure maths, no nodes.
# A machine is covered by a row of circles along its length; two machines touch when any
# two of their circles overlap. Heading 0 faces +z (forward = (sin h, cos h)).

const VehicleData := preload("res://scripts/vehicle_data.gd")

# Circles (x, z, radius) for a body half_len long and half_wid wide.
static func circles(x: float, z: float, heading: float, half_len: float, half_wid: float) -> Array:
	var r := maxf(0.2, half_wid)
	var span := maxf(0.0, half_len - r)
	var out: Array = []
	if span <= 0.01:
		out.append(Vector3(x, z, r))
		return out
	var fx := sin(heading)
	var fz := cos(heading)
	var k := maxi(2, int(ceil(2.0 * span / r)) + 1)
	for i in k:
		var t := -span + 2.0 * span * float(i) / float(k - 1)
		out.append(Vector3(x + fx * t, z + fz * t, r))
	return out

# Footprint of a machine dictionary (x, z, heading, vehicle). wide = use the room it needs
# when parked (a combine's header sticks out) instead of the body width.
static func of_machine(m: Dictionary, wide: bool = false) -> Array:
	var veh: Dictionary = VehicleData.get_vehicle(str(m.get("vehicle", "tractor")))
	var hl := float(veh.get("hit_len", 2.0)) * 0.5
	var hw := float(veh.get("hit_wid", 1.4)) * 0.5
	if wide:
		hw = float(veh.get("park_wid", veh.get("hit_wid", 1.4))) * 0.5
		hw = maxf(hw, float(veh.get("hit_wid", 1.4)) * 0.5)
	return circles(float(m["x"]), float(m["z"]), float(m["heading"]), hl, hw)

# How deep the two footprints overlap: positive means they touch, zero or less means clear.
static func penetration(a: Array, b: Array) -> float:
	var worst := -1000.0
	for ca in a:
		for cb in b:
			var d := Vector2(ca.x - cb.x, ca.y - cb.y).length()
			worst = maxf(worst, ca.z + cb.z - d)
	return worst

# Does a circle (x, z, radius) touch a solid rectangle Rect2(x, z, width, depth)?
static func circle_hits_rect(c: Vector3, rect: Rect2) -> bool:
	var cx := clampf(c.x, rect.position.x, rect.position.x + rect.size.x)
	var cz := clampf(c.y, rect.position.y, rect.position.y + rect.size.y)
	return Vector2(c.x - cx, c.y - cz).length() < c.z

# The deepest touch between two footprints: Vector3(nx, nz, depth). (nx, nz) is the unit
# direction pointing from footprint b towards footprint a. depth <= 0 means clear.
static func contact(a: Array, b: Array) -> Vector3:
	var worst := -1000.0
	var best := Vector2(0.0, 1.0)
	for ca in a:
		for cb in b:
			var d := Vector2(ca.x - cb.x, ca.y - cb.y)
			var depth: float = ca.z + cb.z - d.length()
			if depth > worst:
				worst = depth
				if d.length() > 0.0001:
					best = d.normalized()
	return Vector3(best.x, best.y, worst)
