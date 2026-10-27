extends RefCounted
# The farmland plots. Pure data and maths, shared by game logic, autopilot, map and tests.
# North is -z. The main road runs east-west at z = ROAD_Z, between the home field (north)
# and the farmhouse yard (south). Every plot touches that road:
#   north plots end at the road's north edge, south plots start at its south edge.
# Plots are made of tiles PITCH apart. Their tiles are stored after the home field's tiles,
# in the order the player bought the plots (see game_state.gd).

const PITCH := 1.5
const HOME := "farm"
const ROAD_Z := 3.6          # centre line of the main road
const ROAD_HALF := 1.2       # half its width
const NORTH_EDGE_Z := 2.0    # south edge of the north plots (road edge minus a 0.4 verge)
const SOUTH_EDGE_Z := 5.2    # north edge of the south plots
const PRICE_PER_TILE := 35
const WORLD_HALF := 90.0     # the farm land reaches this far from the centre

# id, name, size class, tiles across (cols) and down (rows), world centre (cx, cz), side.
const PLOTS := [
	{"id": "farm", "name": "Home Farm", "size": "Home", "cols": 8, "rows": 8, "cx": 0.0, "cz": -4.0, "side": "n"},
	{"id": "e1", "name": "East Meadow", "size": "Medium", "cols": 12, "rows": 10, "cx": 17.0, "cz": -5.5, "side": "n"},
	{"id": "w1", "name": "West Meadow", "size": "Medium", "cols": 10, "rows": 10, "cx": -15.5, "cz": -5.5, "side": "n"},
	{"id": "e2", "name": "Big East Field", "size": "Large", "cols": 16, "rows": 12, "cx": 40.0, "cz": -7.0, "side": "n"},
	{"id": "w2", "name": "Big West Field", "size": "Large", "cols": 14, "rows": 14, "cx": -35.5, "cz": -8.5, "side": "n"},
	{"id": "e3", "name": "Grand East Estate", "size": "Very large", "cols": 20, "rows": 16, "cx": 69.0, "cz": -10.0, "side": "n"},
	{"id": "w3", "name": "Grand West Estate", "size": "Very large", "cols": 24, "rows": 16, "cx": -66.0, "cz": -10.0, "side": "n"},
	{"id": "s1", "name": "Yard Side Plot", "size": "Medium", "cols": 10, "rows": 8, "cx": 28.5, "cz": 11.2, "side": "s"},
	{"id": "s2", "name": "South Prairie", "size": "Large", "cols": 16, "rows": 12, "cx": 51.0, "cz": 14.2, "side": "s"},
	{"id": "s3", "name": "South West Plot", "size": "Large", "cols": 12, "rows": 10, "cx": -30.0, "cz": 12.7, "side": "s"},
]

static func ids() -> Array:
	var out: Array = []
	for p in PLOTS:
		out.append(p["id"])
	return out

static func has_plot(id: String) -> bool:
	for p in PLOTS:
		if p["id"] == id:
			return true
	return false

# The plot dictionary for an id, or {} if there is none.
static func get_plot(id: String) -> Dictionary:
	for p in PLOTS:
		if p["id"] == id:
			return p
	return {}

static func tile_count(id: String) -> int:
	var p := get_plot(id)
	if p.is_empty():
		return 0
	return int(p["cols"]) * int(p["rows"])

# Price in money: 0 for the home field, otherwise tiles * PRICE_PER_TILE rounded to 50.
static func price_of(id: String) -> int:
	if id == HOME or not has_plot(id):
		return 0
	return int(round(float(tile_count(id)) * float(PRICE_PER_TILE) / 50.0)) * 50

# Area of the plot in world units.
static func rect_of(id: String) -> Rect2:
	var p := get_plot(id)
	if p.is_empty():
		return Rect2()
	var w: float = float(p["cols"]) * PITCH
	var h: float = float(p["rows"]) * PITCH
	return Rect2(float(p["cx"]) - w / 2.0, float(p["cz"]) - h / 2.0, w, h)

static func col_x(id: String, col: int) -> float:
	var p := get_plot(id)
	return float(p["cx"]) + (float(col) - (float(p["cols"]) - 1.0) / 2.0) * PITCH

static func row_z(id: String, row: int) -> float:
	var p := get_plot(id)
	return float(p["cz"]) + (float(row) - (float(p["rows"]) - 1.0) / 2.0) * PITCH

# Where a machine joins the plot from the road: centre of the plot's side that faces the road.
static func gate_of(id: String) -> Vector2:
	var p := get_plot(id)
	var r := rect_of(id)
	if str(p["side"]) == "n":
		return Vector2(float(p["cx"]), r.position.y + r.size.y)
	return Vector2(float(p["cx"]), r.position.y)
