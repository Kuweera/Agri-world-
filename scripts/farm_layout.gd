extends RefCounted
# Where the field is. Pure maths, shared by game logic, autopilot and tests.
# farm_grid.gd draws tiles at the same positions (a test checks they agree).

const COLS := 8
const ROWS := 8
const PITCH := 1.5
const FIELD_CENTER_X := 0.0
const FIELD_CENTER_Z := -4.0

# Tile index = row * COLS + col, or -1 if (x, z) is outside the field.
static func world_to_tile(x: float, z: float) -> int:
	var lx := x - FIELD_CENTER_X + COLS * PITCH / 2.0
	var lz := z - FIELD_CENTER_Z + ROWS * PITCH / 2.0
	if lx < 0.0 or lz < 0.0:
		return -1
	var col := int(lx / PITCH)
	var row := int(lz / PITCH)
	if col >= COLS or row >= ROWS:
		return -1
	return row * COLS + col

static func col_x(col: int) -> float:
	return FIELD_CENTER_X + (col - (COLS - 1) / 2.0) * PITCH

static func row_z(row: int) -> float:
	return FIELD_CENTER_Z + (row - (ROWS - 1) / 2.0) * PITCH
