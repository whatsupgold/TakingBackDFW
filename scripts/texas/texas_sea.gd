class_name TexasSea
extends RefCounted
## Sea lanes for the fleet: a grid over the water of one stretch of coast (from the map
## builder's sea mask), routed with the engine's A*. Ships go round islands and in through the
## passes (Bolivar Roads into Galveston Bay) instead of straight over the land.

const CELL := 200.0                    # game metres per grid cell
const UP_THE_BEACH := 10.0
const CLEAR := 45.0                    # room a ship needs either side of its track (game m)             # how far past the waterline a hovercraft runs ashore

var area: Rect2
var _grid: AStarGrid2D
var _w := 0
var _h := 0
var _comp := PackedInt32Array()       # which connected stretch of water each cell is in (-1: land)


func _init(region: Rect2) -> void:
	area = region
	_w = ceili(region.size.x / CELL)
	_h = ceili(region.size.y / CELL)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _w, _h)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	# Which cells are open water: a quick look at the coarse sea map first, then, for the cells
	# along a shore, a careful one at the water as drawn: the cell's middle and points round it
	# a ship's half-beam out must all be water (so lanes keep off the land, in narrow channels too)
	var coarse := PackedByteArray()
	coarse.resize(_w * _h)
	for j in _h:
		for i in _w:
			coarse[j * _w + i] = 1 if _coarse_sea(_centre(i, j)) else 0
	for j in _h:
		for i in _w:
			var mine := coarse[j * _w + i]
			var shore := false
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ii: int = clampi(i + di, 0, _w - 1)
					var jj: int = clampi(j + dj, 0, _h - 1)
					if coarse[jj * _w + ii] != mine:
						shore = true
			var open := mine == 1
			if shore:
				var c := _centre(i, j)
				open = is_sea(c)
				for o in [Vector2(CLEAR, 0), Vector2(-CLEAR, 0), Vector2(0, CLEAR), Vector2(0, -CLEAR)]:
					open = open and is_sea(c + o)
			if not open:
				_grid.set_point_solid(Vector2i(i, j), true)
	# Connected stretches of water, so a route always aims for water the ship can reach
	_comp.resize(_w * _h)
	_comp.fill(-1)
	var next := 0
	for j in _h:
		for i in _w:
			if _comp[j * _w + i] != -1 or _grid.is_point_solid(Vector2i(i, j)):
				continue
			var stack: Array[Vector2i] = [Vector2i(i, j)]
			_comp[j * _w + i] = next
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = c + d
					if q.x < 0 or q.y < 0 or q.x >= _w or q.y >= _h:
						continue
					if _comp[q.y * _w + q.x] != -1 or _grid.is_point_solid(q):
						continue
					_comp[q.y * _w + q.x] = next
					stack.append(q)
			next += 1


func _centre(i: int, j: int) -> Vector2:
	return area.position + Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x - area.position.x) / CELL), 0, _w - 1), clampi(int((p.y - area.position.y) / CELL), 0, _h - 1))


static func is_sea(p: Vector2) -> bool:
	## The sea as it's drawn (the shoreline you see)
	return TexasWater.sea(p)


static func _coarse_sea(p: Vector2) -> bool:
	if TexasGeo.built:
		return TexasData.flags(p.x, p.y) & 2 != 0
	return TexasGeo.is_gulf(p.x, p.y)


func nearest_sea(p: Vector2, max_cells := 40, comp := -1) -> Vector2i:
	## The nearest water cell (in stretch `comp` if given)
	var c := _cell(p)
	for r in max_cells:
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := c + Vector2i(di, dj)
				if q.x < 0 or q.y < 0 or q.x >= _w or q.y >= _h:
					continue
				if not _grid.is_point_solid(q) and (comp < 0 or _comp[q.y * _w + q.x] == comp):
					return q
	return Vector2i(-1, -1)


func _start_cell(p: Vector2) -> Vector2i:
	## The nearest lane cell a ship at p can get to over water (not one across a spit of land)
	var c := _cell(p)
	for r in 30:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := c + Vector2i(di, dj)
				if q.x < 0 or q.y < 0 or q.x >= _w or q.y >= _h or _grid.is_point_solid(q):
					continue
				var d := p.distance_squared_to(_centre(q.x, q.y))
				if d < best_d and open_water(p, _centre(q.x, q.y), 20.0, 0.0):
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return nearest_sea(p)


func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	## Waypoints from one point at sea to another (the last one is `to`, or the nearest water
	## to it); empty if there's no way by sea
	var a := _start_cell(from)
	if a.x < 0:
		return PackedVector2Array()
	var b := nearest_sea(to, 60, _comp[a.y * _w + a.x])
	var out := PackedVector2Array()
	if a.x < 0 or b.x < 0:
		return out
	var path := _grid.get_id_path(a, b)
	if path.is_empty():
		return out
	# Keep only the turns (and the start cell, which the ship can reach over water)
	out.append(_centre(a.x, a.y))
	var prev_dir := Vector2i.ZERO
	for k in path.size():
		if k == 0 or k == path.size() - 1:
			continue
		var d: Vector2i = path[k + 1] - path[k]
		if d != prev_dir:
			out.append(_centre(path[k].x, path[k].y))
			prev_dir = d
	var reach_to := is_sea(to) and _comp[_cell(to).y * _w + _cell(to).x] == _comp[a.y * _w + a.x]
	out.append(to if reach_to else _centre(b.x, b.y))
	return _straighten(from, out)


func _straighten(from: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	## Skip the grid's zig-zags: from each point, head straight for the furthest later one that
	## can be reached over open water
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	var at := from
	var n := pts.size()
	var k := 0                          # the next point not yet passed
	while k < n:
		var far := k
		for j in range(n - 1, k, -1):
			if pts[j].distance_to(at) < 8000.0 and open_water(at, pts[j]):
				far = j
				break
		out.append(pts[far])
		at = pts[far]
		k = far + 1
	return out


static func open_water(a: Vector2, b: Vector2, every := 30.0, side := CLEAR * 0.6) -> bool:
	## Water all the way from a to b, with room for a hull either side of the line
	var d := b - a
	var L := d.length()
	var n := maxi(1, int(L / every))
	var perp := Vector2(-d.y, d.x) / maxf(L, 0.001) * side
	for k in range(1, n + 1):
		var p := a + d * (float(k) / n)
		if not is_sea(p):
			return false
		if side > 0.0 and (not is_sea(p + perp) or not is_sea(p - perp)):
			return false
	return true


func landing_point(from: Vector2, to: Vector2) -> Vector2:
	## Where a hovercraft heading from `from` towards `to` comes ashore: just past the waterline
	## (it runs up the beach, no further). `to` itself if it's on the water.
	return beach(from, to)


static func hover_water(p: Vector2) -> bool:
	## Water a hovercraft can cross: the sea and lakes and rivers (bridges don't stop it)
	return TexasWater.sea(p) or TexasWater.inland(p)


static func nearest_hover_water(p: Vector2, max_r := 3000.0) -> Vector2:
	var r := 10.0
	while r <= max_r:
		for k in 24:
			var q := p + Vector2.from_angle(TAU * k / 24.0) * r
			if hover_water(q):
				return q
		r *= 1.35
	return p


static func beach(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	var L := d.length()
	if L < 1.0:
		return to
	var dir := d / L
	var n := maxi(1, int(L / 10.0))
	for k in range(1, n + 1):
		var p := from + d * (float(k) / n)
		if not hover_water(p):
			return p + dir * UP_THE_BEACH
	return to
