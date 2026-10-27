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

# Area of n tiles in hectares, and as text ("12.3 ha"). The game talks about areas, not tiles.
static func ha(n_tiles: float) -> float:
	return n_tiles * HA_PER_TILE

static func ha_text(n_tiles: float) -> String:
	return "%.1f ha" % ha(n_tiles)

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

# Where a machine joins a plot from the road: a point on the north-south road beside the plot,
# level with the plot's centre. side is "w" (west road) or "e" (east road).
static func access_of(id: String, side: String) -> Vector2:
	var r := rect_of(id)
	var x := r.position.x - SETBACK if side == "w" else r.end.x + SETBACK
	return Vector2(x, r.get_center().y)

# The middle of the side of the plot that faces the main road (used for signs).
static func gate_of(id: String) -> Vector2:
	var p := get_plot(id)
	var r := rect_of(id)
	if str(p["side"]) == "n":
		return Vector2(float(p["cx"]), r.position.y + r.size.y)
	return Vector2(float(p["cx"]), r.position.y)
