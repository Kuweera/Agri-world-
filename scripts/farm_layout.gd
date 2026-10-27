extends RefCounted
# Where the plots are. Pure maths, shared by game logic, autopilot and tests.
# farm_grid.gd draws tiles at the same positions (a test checks they agree).
# `owned` is the list of plot ids the player owns, in buying order (GameState.plots). Tile
# indices count through the owned plots in that order. Without `owned`, only the home field exists.

const PlotData := preload("res://scripts/plot_data.gd")

# The home field (the first plot). Older code and tests use these.
const COLS := 8
const ROWS := 8
const PITCH := 1.5
const FIELD_CENTER_X := 0.0
const FIELD_CENTER_Z := -9.4   # = PlotData home plot cz
const HOME_ONLY := ["farm"]

# Index of a plot's first tile, or -1 if it is not in `owned`.
static func tile_start(owned: Array, id: String) -> int:
	var start := 0
	for o in owned:
		if str(o) == id:
			return start
		start += PlotData.tile_count(str(o))
	return -1

# Tile index = start of its plot + row * cols + col, or -1 if (x, z) is on no owned plot.
static func world_to_tile(x: float, z: float, owned: Array = HOME_ONLY) -> int:
	var start := 0
	for o in owned:
		var id := str(o)
		var p := PlotData.get_plot(id)
		if p.is_empty():
			continue
		var cols := int(p["cols"])
		var rows := int(p["rows"])
		var lx := x - float(p["cx"]) + float(cols) * PITCH / 2.0
		var lz := z - float(p["cz"]) + float(rows) * PITCH / 2.0
		if lx >= 0.0 and lz >= 0.0:
			var col := int(lx / PITCH)
			var row := int(lz / PITCH)
			if col < cols and row < rows:
				return start + row * cols + col
		start += cols * rows
	return -1

# {"plot": id, "col": c, "row": r} for tile index i, or {} if i is out of range.
static func tile_info(i: int, owned: Array = HOME_ONLY) -> Dictionary:
	if i < 0:
		return {}
	var start := 0
	for o in owned:
		var id := str(o)
		var n := PlotData.tile_count(id)
		if i < start + n:
			var cols := int(PlotData.get_plot(id)["cols"])
			var local := i - start
			return {"plot": id, "col": local % cols, "row": floori(float(local) / float(cols))}
		start += n
	return {}

# The owned plot that contains (x, z), or "".
static func plot_at(x: float, z: float, owned: Array = HOME_ONLY) -> String:
	for o in owned:
		if PlotData.rect_of(str(o)).has_point(Vector2(x, z)):
			return str(o)
	return ""

# The owned plot whose centre is nearest to (x, z); the home field if `owned` is empty.
static func nearest_plot(x: float, z: float, owned: Array = HOME_ONLY) -> String:
	var best := PlotData.HOME
	var best_d := INF
	for o in owned:
		var p := PlotData.get_plot(str(o))
		if p.is_empty():
			continue
		var d := Vector2(x - float(p["cx"]), z - float(p["cz"])).length()
		if d < best_d:
			best_d = d
			best = str(o)
	return best

static func col_x(col: int, plot_id: String = PlotData.HOME) -> float:
	return PlotData.col_x(plot_id, col)

static func row_z(row: int, plot_id: String = PlotData.HOME) -> float:
	return PlotData.row_z(plot_id, row)
