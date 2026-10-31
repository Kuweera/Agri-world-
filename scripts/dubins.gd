extends RefCounted
# Shortest forward-only path between two poses for a machine with a minimum turning radius:
# arcs (L = turn left, R = turn right) joined by a straight piece (S). Pure maths, no nodes.
#
# Planar frame used here: X = game x, Y = game z, theta = PI/2 - heading (so the game's heading 0,
# which faces +z, is theta PI/2). L increases theta, which is the game's STEER > 0 (heading goes down).
#
# Classic Dubins words: LSL, RSR, LSR, RSL, RLR, LRL (Shkel and Lumelsky). RLR/LRL are the three-arc
# "bulb" turns that fit when two parallel lanes are closer together than two turning radii.

const L := 1
const S := 0
const R := -1
const WORDS := [[L, S, L], [R, S, R], [L, S, R], [R, S, L], [R, L, R], [L, R, L]]

static func _mod2pi(x: float) -> float:
	var v := fposmod(x, TAU)
	if v > TAU - 0.000000001:
		return 0.0
	return v

# One word: returns [t, p, q] in units of rho, or an empty array when it does not exist.
static func _word(w: int, alpha: float, beta: float, d: float) -> Array:
	var sa := sin(alpha)
	var sb := sin(beta)
	var ca := cos(alpha)
	var cb := cos(beta)
	var c_ab := cos(alpha - beta)
	match w:
		0:  # LSL
			var p2 := 2.0 + d * d - 2.0 * c_ab + 2.0 * d * (sa - sb)
			if p2 < 0.0:
				return []
			var tmp1 := atan2(cb - ca, d + sa - sb)
			return [_mod2pi(-alpha + tmp1), sqrt(p2), _mod2pi(beta - tmp1)]
		1:  # RSR
			var p2 := 2.0 + d * d - 2.0 * c_ab + 2.0 * d * (sb - sa)
			if p2 < 0.0:
				return []
			var tmp1 := atan2(ca - cb, d - sa + sb)
			return [_mod2pi(alpha - tmp1), sqrt(p2), _mod2pi(-beta + tmp1)]
		2:  # LSR
			var p2 := -2.0 + d * d + 2.0 * c_ab + 2.0 * d * (sa + sb)
			if p2 < 0.0:
				return []
			var p := sqrt(p2)
			var tmp0 := atan2(-ca - cb, d + sa + sb) - atan2(-2.0, p)
			return [_mod2pi(-alpha + tmp0), p, _mod2pi(-_mod2pi(beta) + tmp0)]
		3:  # RSL
			var p2 := d * d - 2.0 + 2.0 * c_ab - 2.0 * d * (sa + sb)
			if p2 < 0.0:
				return []
			var p := sqrt(p2)
			var tmp0 := atan2(ca + cb, d - sa - sb) - atan2(2.0, p)
			return [_mod2pi(alpha - tmp0), p, _mod2pi(beta - tmp0)]
		4:  # RLR
			var tmp0 := (6.0 - d * d + 2.0 * c_ab + 2.0 * d * (sa - sb)) / 8.0
			if absf(tmp0) > 1.0:
				return []
			var p := _mod2pi(TAU - acos(tmp0))
			var t := _mod2pi(alpha - atan2(ca - cb, d - sa + sb) + _mod2pi(p / 2.0))
			return [t, p, _mod2pi(alpha - beta - t + _mod2pi(p))]
		5:  # LRL is RLR mirrored (angles negated), with the same segment lengths
			return _word(4, _mod2pi(-alpha), _mod2pi(-beta), d)
	return []

# Shortest path from (x0, y0, th0) to (x1, y1, th1) with turning radius rho.
# Returns {"word": index, "types": [..3], "lens": [t, p, q] (in rho), "length": metres} or {}.
static func shortest(x0: float, y0: float, th0: float, x1: float, y1: float, th1: float, rho: float) -> Dictionary:
	var dx := x1 - x0
	var dy := y1 - y0
	var dist := sqrt(dx * dx + dy * dy)
	var d := dist / rho
	var th := 0.0
	if dist > 0.0:
		th = _mod2pi(atan2(dy, dx))
	var alpha := _mod2pi(th0 - th)
	var beta := _mod2pi(th1 - th)
	var best := {}
	var best_len := INF
	for w in 6:
		var r: Array = _word(w, alpha, beta, d)
		if r.is_empty():
			continue
		var total: float = float(r[0]) + float(r[1]) + float(r[2])
		if total < best_len:
			best_len = total
			best = {"word": w, "types": WORDS[w], "lens": r, "length": total * rho}
	return best

# Points along the path every `ds` metres (the first is the start, the last the end).
# Returns {"pts": PackedVector2Array, "turn": PackedFloat32Array (+1 left arc, -1 right arc, 0 straight),
#          "th": PackedFloat32Array (theta at each point)}.
static func sample(x0: float, y0: float, th0: float, rho: float, path: Dictionary, ds: float = 0.25) -> Dictionary:
	var pts := PackedVector2Array()
	var turn := PackedFloat32Array()
	var ths := PackedFloat32Array()
	var x := x0
	var y := y0
	var th := th0
	pts.append(Vector2(x, y))
	turn.append(0.0)
	ths.append(th)
	for k in 3:
		var ty: int = path["types"][k]
		var seg_len: float = float(path["lens"][k])   # in rho
		var n := maxi(1, int(ceil(seg_len * rho / ds)))
		if seg_len <= 0.0000001:
			continue
		var u := seg_len / float(n)
		for i in n:
			if ty == L:
				x += rho * (sin(th + u) - sin(th))
				y += rho * (-cos(th + u) + cos(th))
				th += u
			elif ty == R:
				x += rho * (-sin(th - u) + sin(th))
				y += rho * (cos(th - u) - cos(th))
				th -= u
			else:
				x += rho * u * cos(th)
				y += rho * u * sin(th)
			pts.append(Vector2(x, y))
			turn.append(float(ty))
			ths.append(th)
	return {"pts": pts, "turn": turn, "th": ths}

# Shortest path to a POINT (final heading free): an arc to the tangent, then straight on to the point.
# Same result format as shortest(). Returns {} when the point lies inside both turning circles.
static func to_point(x0: float, y0: float, th0: float, xp: float, yp: float, rho: float) -> Dictionary:
	var best := {}
	var best_len := INF
	for dir in [L, R]:
		var s_dir: float = float(dir)
		# Centre of the turning circle: to the left (L) or right (R) of the start.
		var cx := x0 + s_dir * rho * (-sin(th0))
		var cy := y0 + s_dir * rho * cos(th0)
		var dxp := xp - cx
		var dyp := yp - cy
		var dd := sqrt(dxp * dxp + dyp * dyp)
		if dd < rho:
			continue
		var phi := atan2(dyp, dxp)
		var beta := acos(rho / dd)
		var arc := 0.0
		if dir == L:
			arc = _mod2pi((phi - beta) - (th0 - PI / 2.0))
		else:
			arc = _mod2pi((th0 + PI / 2.0) - (phi + beta))
		var line := sqrt(dd * dd - rho * rho)
		var total := arc * rho + line
		if total < best_len:
			best_len = total
			best = {"word": -1, "types": [dir, S, S], "lens": [arc, line / rho, 0.0], "length": total}
	return best
