extends RefCounted
# Routes along the farm roads (PlotData.ROADS_H / ROADS_V). Pure maths, no nodes.
# route() finds the shortest way along the roads, so machines drive on roads between plots and
# never cut across other people's fields.

const PlotData := preload("res://scripts/plot_data.gd")

# Shortest path from `from` (any point: it drives straight to the nearest road first) to `to`
# (a point that lies on a road). Returns the points to drive through, starting with the point where
# `from` joins the road and ending with `to`. Empty if there is no way.
static func route(from: Vector2, to: Vector2) -> Array:
	var roads: Array = []   # {"h": bool, "c": coordinate across, "a": from, "b": to, "ids": [node ids]}
	for r in PlotData.ROADS_H:
		roads.append({"h": true, "c": float(r[0]), "a": float(r[1]), "b": float(r[2]), "ids": []})
	for r in PlotData.ROADS_V:
		roads.append({"h": false, "c": float(r[0]), "a": float(r[1]), "b": float(r[2]), "ids": []})
	var nodes: Array = []
	# Junctions
	for h in roads:
		if not h["h"]:
			continue
		for v in roads:
			if v["h"]:
				continue
			if float(v["c"]) >= float(h["a"]) - 0.01 and float(v["c"]) <= float(h["b"]) + 0.01 \
					and float(h["c"]) >= float(v["a"]) - 0.01 and float(h["c"]) <= float(v["b"]) + 0.01:
				_node(nodes, roads, Vector2(float(v["c"]), float(h["c"])))
	# Where `from` joins the nearest road
	var best := INF
	var snap := from
	for r in roads:
		var p: Vector2
		if r["h"]:
			p = Vector2(clampf(from.x, float(r["a"]), float(r["b"])), float(r["c"]))
		else:
			p = Vector2(float(r["c"]), clampf(from.y, float(r["a"]), float(r["b"])))
		var d := p.distance_to(from)
		if d < best:
			best = d
			snap = p
	var s := _node(nodes, roads, snap)
	var g := _node(nodes, roads, to)
	if not _on_any_road(roads, to):
		return []
	# Edges: neighbours along each road
	var adj: Array = []
	for i in nodes.size():
		adj.append([])
	for r in roads:
		var ids: Array = r["ids"].duplicate()
		var horizontal: bool = r["h"]
		ids.sort_custom(func(a, b): return (nodes[a].x < nodes[b].x) if horizontal else (nodes[a].y < nodes[b].y))
		for k in ids.size() - 1:
			var a: int = ids[k]
			var b: int = ids[k + 1]
			var w: float = (nodes[a] as Vector2).distance_to(nodes[b])
			adj[a].append([b, w])
			adj[b].append([a, w])
	# Dijkstra
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in nodes.size():
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[s] = 0.0
	for _step in nodes.size():
		var u := -1
		var ud := INF
		for i in nodes.size():
			if not done[i] and float(dist[i]) < ud:
				ud = float(dist[i])
				u = i
		if u < 0 or u == g:
			break
		done[u] = true
		for e in adj[u]:
			var nd := ud + float(e[1])
			if nd < float(dist[int(e[0])]):
				dist[int(e[0])] = nd
				prev[int(e[0])] = u
	if float(dist[g]) == INF:
		return []
	var path: Array = []
	var cur := g
	while cur >= 0:
		path.push_front(nodes[cur])
		cur = int(prev[cur])
	return path

# Length of the way from `from` along `path` (a route() result).
static func path_length(from: Vector2, path: Array) -> float:
	if path.is_empty():
		return INF
	var total := 0.0
	var p := from
	for q in path:
		total += p.distance_to(q)
		p = q
	return total

static func _on_road(r: Dictionary, p: Vector2) -> bool:
	if r["h"]:
		return absf(p.y - float(r["c"])) < 0.02 and p.x >= float(r["a"]) - 0.02 and p.x <= float(r["b"]) + 0.02
	return absf(p.x - float(r["c"])) < 0.02 and p.y >= float(r["a"]) - 0.02 and p.y <= float(r["b"]) + 0.02

static func _on_any_road(roads: Array, p: Vector2) -> bool:
	for r in roads:
		if _on_road(r, p):
			return true
	return false

# Index of the node at p (added if new) and registered on every road that passes through it.
static func _node(nodes: Array, roads: Array, p: Vector2) -> int:
	var id := -1
	for i in nodes.size():
		if (nodes[i] as Vector2).distance_to(p) < 0.02:
			id = i
			break
	if id < 0:
		nodes.append(p)
		id = nodes.size() - 1
	for r in roads:
		if _on_road(r, p) and not (r["ids"] as Array).has(id):
			(r["ids"] as Array).append(id)
	return id
