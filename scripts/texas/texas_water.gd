class_name TexasWater
extends RefCounted
## Where the water is, the way it's drawn: the sea wherever the ground dips below sea level
## (exactly where the shoreline shows), and lakes, reservoirs and rivers from the map data,
## turned into a grid (8 m cells) per 2 km tile the first time anything asks. Safe from any thread.

const RES := 8.0
const N := 256
const MIN_RIVER := 6.0                 # narrower streams than this (game m) don't stop anyone

static var _tiles := {}                # Vector2i -> PackedByteArray (empty: no inland water)
static var _mutex := Mutex.new()
static var _warm_task := -1


static func warm(keys: Array) -> void:
	## Work out these tiles' water on a background thread, before anyone needs it
	finish()
	var todo: Array = []
	_mutex.lock()
	for k in keys:
		if not _tiles.has(k):
			todo.append(k)
	_mutex.unlock()
	if todo.is_empty() or not TexasData.available:
		return
	_warm_task = WorkerThreadPool.add_task(func():
		for k in todo:
			_grid(k))


static func finish() -> void:
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1


static func warm_tile(key: Vector2i) -> void:
	_grid(key)


static func sea(p: Vector2) -> bool:
	if TexasGeo.built:
		return TexasData.height_real(p.x, p.y) < 0.0
	return TexasGeo.is_gulf(p.x, p.y)


static func _cell(p: Vector2) -> int:
	## 0 dry, 1 lake or river, 2 a bridge (or causeway) deck
	if not TexasData.available:
		return 0
	var tile := TexasData.tile_size
	var key := Vector2i(floori(p.x / tile), floori(p.y / tile))
	var g := _grid(key)
	if g.is_empty():
		return 0
	var i := clampi(floori((p.x - key.x * tile) / RES), 0, N - 1)
	var j := clampi(floori((p.y - key.y * tile) / RES), 0, N - 1)
	return g[j * N + i]


static func inland(p: Vector2) -> bool:
	return _cell(p) == 1


static func bridge(p: Vector2) -> bool:
	return _cell(p) == 2


static func any(p: Vector2) -> bool:
	## Water a vehicle can't drive on (a bridge over it is fine)
	var c := _cell(p)
	if c == 2:
		return false
	return c == 1 or sea(p)


static func _grid(key: Vector2i) -> PackedByteArray:
	_mutex.lock()
	var r = _tiles.get(key)
	_mutex.unlock()
	if r != null:
		return r
	var out := _build(key)
	_mutex.lock()
	if _tiles.has(key):
		out = _tiles[key]
	else:
		_tiles[key] = out
	_mutex.unlock()
	return out


static func _build(key: Vector2i) -> PackedByteArray:
	var data := TexasData.tile(key)
	var w: PackedFloat32Array = data.get(3, PackedFloat32Array())
	var rivers: PackedFloat32Array = data.get(4, PackedFloat32Array())
	var roads: PackedFloat32Array = data.get(2, PackedFloat32Array())
	if w.is_empty() and rivers.is_empty() and roads.is_empty():
		return PackedByteArray()
	var g := PackedByteArray()
	g.resize(N * N)
	var any_set := false
	# Lakes: fill each triangle
	var p := 0
	while p < w.size():
		var tris := int(w[p])
		p += 2
		for t in tris:
			var a := Vector2(w[p], w[p + 1])
			var b := Vector2(w[p + 2], w[p + 3])
			var c := Vector2(w[p + 4], w[p + 5])
			p += 6
			any_set = _fill_tri(g, a, b, c) or any_set
	# Rivers: a strip each side of the line
	p = 0
	while p < rivers.size():
		var cnt := int(rivers[p])
		var width := rivers[p + 1]
		var line := PackedVector2Array()
		for q in cnt:
			line.append(Vector2(rivers[p + 2 + q * 2], rivers[p + 3 + q * 2]))
		p += 2 + cnt * 2
		if width < MIN_RIVER:
			continue
		for q in cnt - 1:
			any_set = _fill_seg(g, line[q], line[q + 1], width * 0.5) or any_set
	# Roads on top: a bridge, a causeway or a wharf is dry whatever is under it. Every road is
	# drawn above the water, so wherever one crosses water its deck counts as dry ground.
	var ox := key.x * TexasData.tile_size
	var oz := key.y * TexasData.tile_size
	p = 0
	while p < roads.size():
		var cnt := int(roads[p])
		var width := roads[p + 2]
		var is_bridge := roads[p + 3] > 0.5
		var at := p + 4
		p += 4 + cnt * 2
		var r := maxf(width * 0.5, 4.0) + 5.0
		for q in cnt - 1:
			var a := Vector2(roads[at + q * 2], roads[at + 1 + q * 2])
			var b := Vector2(roads[at + 2 + q * 2], roads[at + 3 + q * 2])
			if is_bridge:
				any_set = _fill_seg(g, a, b, r, 2) or any_set
				continue
			# only the stretches that are over water
			var n := maxi(1, int(a.distance_to(b) / 12.0))
			var run_a := Vector2(INF, INF)
			for k in range(0, n + 1):
				var c := a.lerp(b, float(k) / n)
				var ci := clampi(floori(c.x / RES), 0, N - 1)
				var cj := clampi(floori(c.y / RES), 0, N - 1)
				var wet := g[cj * N + ci] == 1 or sea(Vector2(ox + c.x, oz + c.y))
				if wet and run_a.x == INF:
					run_a = a.lerp(b, maxf(0.0, float(k) - 1.0) / n)
				if (not wet or k == n) and run_a.x != INF:
					var run_b := a.lerp(b, minf(float(n), float(k) + (0.0 if wet else 0.0)) / n)
					any_set = _fill_seg(g, run_a, run_b, r, 2) or any_set
					run_a = Vector2(INF, INF)
	return g if any_set else PackedByteArray()


static func _fill_tri(g: PackedByteArray, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var lo := a.min(b).min(c)
	var hi := a.max(b).max(c)
	var i0 := clampi(floori(lo.x / RES), 0, N - 1)
	var i1 := clampi(floori(hi.x / RES), 0, N - 1)
	var j0 := clampi(floori(lo.y / RES), 0, N - 1)
	var j1 := clampi(floori(hi.y / RES), 0, N - 1)
	var hit := false
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var q := Vector2((i + 0.5) * RES, (j + 0.5) * RES)
			var d1 := (b - a).cross(q - a)
			var d2 := (c - b).cross(q - b)
			var d3 := (a - c).cross(q - c)
			if (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0):
				g[j * N + i] = 1
				hit = true
	return hit


static func _fill_seg(g: PackedByteArray, a: Vector2, b: Vector2, r: float, v := 1) -> bool:
	var lo := a.min(b) - Vector2(r, r)
	var hi := a.max(b) + Vector2(r, r)
	var i0 := clampi(floori(lo.x / RES), 0, N - 1)
	var i1 := clampi(floori(hi.x / RES), 0, N - 1)
	var j0 := clampi(floori(lo.y / RES), 0, N - 1)
	var j1 := clampi(floori(hi.y / RES), 0, N - 1)
	var ab := b - a
	var L2 := maxf(ab.length_squared(), 1e-6)
	var hit := false
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var q := Vector2((i + 0.5) * RES, (j + 0.5) * RES)
			var t := clampf((q - a).dot(ab) / L2, 0.0, 1.0)
			if (a + ab * t).distance_to(q) <= r:
				g[j * N + i] = v
				hit = true
	return hit
