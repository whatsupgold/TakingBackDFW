class_name TexasRoads
extends RefCounted
## The highway network as a graph: a node at every city and border point along the highways,
## an edge for each stretch between them. Ground units in the simulation drive along it, and
## the tiles draw it.
##
## With the map builder's real Texas loaded, it's the real network instead: interstates, US and
## state highways and the main city roads from OpenStreetMap. Junctions are the graph's nodes
## (routed with the engine's A*), and a route comes back as every point along the roads, so
## units follow each curve. `nodes` then holds the junctions first, then the shape points.

var nodes := PackedVector2Array()      # game metres
var names: PackedStringArray = []
var edges: Array = []                  # per node: [[other node, length], ...]
var segments: Array = []               # [a, b, kind]: every stretch once, for drawing
var _by_name := {}
var built := false
var junctions := 0
var _astar: AStar2D
var _chain_of := {}                    # a * junctions + b -> chain (negative: run it backwards)
var _chains := PackedInt32Array()      # [a, b, class, first point, point count] per chain
var _lengths := PackedFloat32Array()
var _route_cache := {}
var _grid := {}                        # Vector2i (4 km cell) -> PackedInt32Array of junctions
const GRID_CELL := 4096.0


func _init() -> void:
	if TexasGeo.built and _load_built():
		return
	for hw in TexasGeo.HIGHWAYS:
		var prev := -1
		for i in range(1, hw.size()):
			var n := _node_for(hw[i])
			if n < 0:
				continue
			if prev >= 0 and prev != n:
				_link(prev, n, hw[0])
			prev = n


func _node_for(key: String) -> int:
	if _by_name.has(key):
		return _by_name[key]
	var p: Vector2
	if key.begins_with("@"):
		var parts := key.substr(1).split(",")
		p = TexasGeo.to_xz(float(parts[0]), float(parts[1]))
	else:
		var c := TexasGeo.city(key)
		if c.is_empty():
			push_warning("TexasRoads: no city called %s" % key)
			return -1
		p = TexasGeo.city_xz(c)
	nodes.append(p)
	names.append(key)
	edges.append([])
	_by_name[key] = nodes.size() - 1
	return nodes.size() - 1


func _link(a: int, b: int, kind: String) -> void:
	for e in edges[a]:
		if e[0] == b:
			return
	var d := nodes[a].distance_to(nodes[b])
	edges[a].append([b, d])
	edges[b].append([a, d])
	segments.append([a, b, kind])


func _load_built() -> bool:
	var d := TexasData.read_roads()
	if d.is_empty():
		return false
	built = true
	junctions = d.junctions
	var pts: PackedFloat64Array = d.points
	var n := pts.size() / 2
	nodes.resize(n)
	for i in n:
		nodes[i] = Vector2(pts[i * 2], pts[i * 2 + 1])
	_chains = d.chains
	_lengths = d.lengths
	_astar = AStar2D.new()
	_astar.reserve_space(junctions)
	for i in junctions:
		_astar.add_point(i, nodes[i])
		var cell := Vector2i(floori(nodes[i].x / GRID_CELL), floori(nodes[i].y / GRID_CELL))
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		(_grid[cell] as PackedInt32Array).append(i)
	edges.resize(junctions)
	for i in junctions:
		edges[i] = []
	var c := _chains.size() / 5
	for k in c:
		var a := _chains[k * 5]
		var b := _chains[k * 5 + 1]
		var L := _lengths[k]
		var ab := a * junctions + b
		if _chain_of.has(ab) and _lengths[absi(_chain_of[ab]) - 1] <= L:
			continue
		_chain_of[ab] = k + 1
		_chain_of[b * junctions + a] = -(k + 1)
		if not _astar.are_points_connected(a, b):
			_astar.connect_points(a, b)
			edges[a].append([b, L])
			edges[b].append([a, L])
	return true


func class_of_chain(k: int) -> int:
	return _chains[k * 5 + 2]


func node_of(name: String) -> int:
	return _by_name.get(name, -1)


func nearest_node(p: Vector2) -> int:
	if built:
		return _nearest_built(p)
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var d := nodes[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func find_route(from: int, to: int) -> PackedInt32Array:
	## Shortest route by road (A*), as the list of nodes to drive through
	var out := PackedInt32Array()
	if from < 0 or to < 0:
		return out
	if from == to:
		out.append(to)
		return out
	if built:
		return _built_route(from, to)
	var g := {from: 0.0}
	var came := {}
	var open := [from]
	var goal := nodes[to]
	while not open.is_empty():
		# The open set is small (a few hundred nodes at most): a linear scan is fine
		var bi := 0
		var bf := INF
		for i in open.size():
			var n: int = open[i]
			var f: float = g[n] + nodes[n].distance_to(goal)
			if f < bf:
				bf = f
				bi = i
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == to:
			var path: Array = [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			for n in path:
				out.append(n)
			return out
		for e in edges[cur]:
			var nb: int = e[0]
			var ng: float = g[cur] + e[1]
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				if not (nb in open):
					open.append(nb)
	return out


func route_length(route: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += nodes[route[i - 1]].distance_to(nodes[route[i]])
	return total


func _built_route(from: int, to: int) -> PackedInt32Array:
	## Junction to junction with the engine's A*, then out to every shape point on the way
	var key := from * junctions + to
	if _route_cache.has(key):
		return _route_cache[key]
	var path := _astar.get_id_path(from, to)
	var out := PackedInt32Array()
	if path.is_empty():
		_route_cache[key] = out
		return out
	out.append(path[0])
	for i in range(1, path.size()):
		var a: int = path[i - 1]
		var b: int = path[i]
		var ck: int = _chain_of.get(a * junctions + b, 0)
		if ck != 0:
			var k := absi(ck) - 1
			var first := _chains[k * 5 + 3]
			var count := _chains[k * 5 + 4]
			if ck > 0:
				for q in count:
					out.append(first + q)
			else:
				for q in count:
					out.append(first + count - 1 - q)
		out.append(b)
	if _route_cache.size() > 4000:
		_route_cache.clear()
	_route_cache[key] = out
	return out


func nearest_reachable(p: Vector2) -> int:
	## The nearest junction a ground unit at p can reach without crossing the sea
	if not built:
		return nearest_node(p)
	var c := Vector2i(floori(p.x / GRID_CELL), floori(p.y / GRID_CELL))
	var cand: Array = []
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for i in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
					cand.append([nodes[i].distance_squared_to(p), i])
		if cand.size() >= 24:
			break
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(cand.size(), 24):
		var i: int = cand[k][1]
		if not TexasSim.crosses_water(p, nodes[i]):
			return i
	return _nearest_built(p)


func _nearest_built(p: Vector2) -> int:
	## Search outwards ring by ring through the 4 km cells; stop once a ring can't beat the best
	var c := Vector2i(floori(p.x / GRID_CELL), floori(p.y / GRID_CELL))
	var best := -1
	var best_d := INF
	for r in 12:
		if best >= 0 and (r - 1) * GRID_CELL > sqrt(best_d):
			break
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var lst: PackedInt32Array = _grid.get(c + Vector2i(dx, dz), PackedInt32Array())
				for i in lst:
					var d := nodes[i].distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = i
	if best < 0:
		best = _astar.get_closest_point(p)
	return best
