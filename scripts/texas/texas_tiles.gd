class_name TexasTiles
extends Node3D
## Streams the ground around the camera in 2 km tiles: terrain, the highways draped over it,
## and (until the map builder brings in real buildings) stand-in city blocks, thinned for the
## 1:3 scale. Each tile is built on a background thread; the main thread only turns the
## finished arrays into meshes, a couple a frame, so the camera never waits for the ground.
##
## Tiles are placed relative to the world origin (see TexasMain): when the origin shifts, they
## all move together, so everything near the camera keeps small, precise coordinates.

const TILE := 2048.0
const GRID := 32                       # terrain cells a side (64 m each)
const MAX_BUILDING := 6                # tiles being built at once
const PER_FRAME := 2                   # finished tiles turned into meshes per frame

var roads: TexasRoads
var origin_x := 0.0
var origin_z := 0.0
var tiles := {}                        # Vector2i -> Node3D
var built_count := 0
var build_ms_total := 0.0
var _pending := {}                     # Vector2i -> task id while a thread builds it
var _done: Array = []                  # finished build results, filled by the threads
var _mutex := Mutex.new()
var _want := {}                        # the tiles the camera needs right now
var _terrain_mat: StandardMaterial3D
var _road_mat: StandardMaterial3D
var _building_mat: StandardMaterial3D
var _box: BoxMesh


func _init(road_net: TexasRoads) -> void:
	roads = road_net
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 1.0
	_road_mat = StandardMaterial3D.new()
	_road_mat.vertex_color_use_as_albedo = true
	_road_mat.roughness = 0.9
	_building_mat = StandardMaterial3D.new()
	_building_mat.vertex_color_use_as_albedo = true
	_building_mat.roughness = 0.9
	TexasWaterLook.setup()
	_box = BoxMesh.new()
	_box.size = Vector3.ONE


func pending_count() -> int:
	return _pending.size()


func wanted(world_x: float, world_z: float, radius: float) -> void:
	## Ask for every tile within radius of a point (world metres); drop the ones far outside
	_want.clear()
	var r := ceili(radius / TILE)
	var cx := floori(world_x / TILE)
	var cz := floori(world_z / TILE)
	var order: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(cx + dx, cz + dz)
			var centre := Vector2((key.x + 0.5) * TILE, (key.y + 0.5) * TILE)
			var d := centre.distance_to(Vector2(world_x, world_z))
			if d <= radius + TILE * 0.75:
				_want[key] = true
				if not tiles.has(key) and not _pending.has(key):
					order.append([d, key])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for o in order:
		if _pending.size() >= MAX_BUILDING:
			break
		var key: Vector2i = o[1]
		_pending[key] = WorkerThreadPool.add_task(_build.bind(key))
	# Unload what's well out of range
	for key in tiles.keys():
		var centre := Vector2((key.x + 0.5) * TILE, (key.y + 0.5) * TILE)
		if centre.distance_to(Vector2(world_x, world_z)) > radius + TILE * 2.5:
			(tiles[key] as Node3D).queue_free()
			tiles.erase(key)


func finish() -> void:
	## Wait for the tiles still being built (before the game closes)
	for key in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[key])
	_pending.clear()


func set_origin(ox: float, oz: float) -> void:
	origin_x = ox
	origin_z = oz
	for key in tiles:
		(tiles[key] as Node3D).position = Vector3(key.x * TILE - origin_x, 0.0, key.y * TILE - origin_z)


func _process(_delta: float) -> void:
	var batch: Array = []
	_mutex.lock()
	while not _done.is_empty() and batch.size() < PER_FRAME:
		batch.append(_done.pop_front())
	_mutex.unlock()
	for r in batch:
		if _pending.has(r.key):
			WorkerThreadPool.wait_for_task_completion(_pending[r.key])
			_pending.erase(r.key)
		if not _want.has(r.key) or tiles.has(r.key):
			continue
		tiles[r.key] = _make_tile(r)
		built_count += 1
		build_ms_total += r.ms


# --- Building (on a worker thread: no scene access here) -----------------------------------

func _build(key: Vector2i) -> void:
	if TexasGeo.built:
		_build_real(key)
		return
	var t0 := Time.get_ticks_usec()
	var cache := {}
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	var n := GRID + 1
	var step := TILE / GRID
	# Terrain: a grid of heights, coloured by where it is
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	verts.resize(n * n)
	cols.resize(n * n)
	hs.resize(n * n)
	for j in n:
		for i in n:
			var wx := x0 + i * step
			var wz := z0 + j * step
			var h := TexasGeo.height_cached(wx, wz, cache)
			hs[j * n + i] = h
			verts[j * n + i] = Vector3(i * step, h, j * step)
			var c := TexasGeo.ground_color(wx, wz, h / TexasGeo.VERTICAL)
			if h < 0.0:
				c = Color(0.55, 0.52, 0.42)
			cols[j * n + i] = c
	var idx := PackedInt32Array()
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for j in n:
		for i in n:
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, GRID)]
			var hu := hs[maxi(j - 1, 0) * n + i]
			var hd := hs[mini(j + 1, GRID) * n + i]
			norms[j * n + i] = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
	# Highways crossing the tile: a strip draped over the ground
	var rv := PackedVector3Array()
	var rc := PackedColorArray()
	var rn := PackedVector3Array()
	var rect := Rect2(x0, z0, TILE, TILE)
	for seg in roads.segments:
		var a: Vector2 = roads.nodes[seg[0]]
		var b: Vector2 = roads.nodes[seg[1]]
		var clip := _clip(a, b, rect.grow(20.0))
		if clip.is_empty():
			continue
		var interstate: bool = (seg[2] as String).begins_with("I-")
		var half := 9.0 if interstate else 6.0
		var col := Color(0.20, 0.20, 0.21) if interstate else Color(0.27, 0.27, 0.27)
		var p0: Vector2 = clip[0]
		var p1: Vector2 = clip[1]
		var dir := (p1 - p0)
		var length := dir.length()
		if length < 1.0:
			continue
		dir /= length
		var side := Vector2(-dir.y, dir.x) * half
		var pieces := maxi(1, ceili(length / 48.0))
		for k in pieces:
			var q0 := p0 + dir * (length * k / pieces)
			var q1 := p0 + dir * (length * (k + 1) / pieces)
			var corners := [q0 - side, q0 + side, q1 + side, q1 - side]
			var cv: Array = []
			for c in corners:
				var cc: Vector2 = c
				cv.append(Vector3(cc.x - x0, TexasGeo.height_cached(cc.x, cc.y, cache) + 0.35, cc.y - z0))
			for t in [0, 2, 1, 0, 3, 2]:
				rv.append(cv[t])
				rc.append(col)
				rn.append(Vector3.UP)
	# Stand-in city blocks, thinned for 1:3: dense and tall downtown, sparse and low outside
	var bt := PackedFloat32Array()
	for c in TexasGeo.CITIES:
		var centre := TexasGeo.city_xz(c)
		var cr := TexasGeo.city_radius(c[3])
		if not rect.grow(cr).has_point(centre):
			continue
		var spacing := 110.0
		var gx0 := floori(x0 / spacing)
		var gz0 := floori(z0 / spacing)
		for bj in range(gz0, gz0 + int(TILE / spacing) + 1):
			for bi in range(gx0, gx0 + int(TILE / spacing) + 1):
				var bx := (bi + 0.5) * spacing
				var bz := (bj + 0.5) * spacing
				if not rect.has_point(Vector2(bx, bz)):
					continue
				var d := Vector2(bx, bz).distance_to(centre) / cr
				if d > 1.0:
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(Vector3i(bi, bj, 1836))
				if rng.randf() > pow(1.0 - d, 0.6) * 0.9:
					continue
				if TexasGeo.is_gulf(bx, bz):
					continue
				var w := rng.randf_range(18.0, 46.0)
				var dpt := rng.randf_range(18.0, 46.0)
				var tall: float = rng.randf_range(6.0, 14.0)
				if d < 0.12 and c[3] >= 3:
					tall = rng.randf_range(40.0, 70.0 * c[3] / 2.0)
				elif d < 0.3:
					tall = rng.randf_range(10.0, 30.0)
				var gy := TexasGeo.height_cached(bx, bz, cache)
				var shade := rng.randf_range(0.55, 0.80)
				# Transform (3 x 4, row major) then colour, as MultiMesh wants it
				bt.append_array([w, 0.0, 0.0, bx - x0, 0.0, tall, 0.0, gy + tall * 0.5, 0.0, 0.0, dpt, bz - z0,
					shade, shade * 0.97, shade * 0.92, 1.0])
	var result := {"key": key, "verts": verts, "cols": cols, "norms": norms, "idx": idx,
		"rv": rv, "rc": rc, "rn": rn, "bt": bt, "ms": (Time.get_ticks_usec() - t0) / 1000.0}
	_mutex.lock()
	_done.append(result)
	_mutex.unlock()


static func _clip(a: Vector2, b: Vector2, r: Rect2) -> Array:
	## The part of segment a-b inside rectangle r (Liang-Barsky), or [] if none
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if absf(p[i]) < 1e-9:
			if q[i] < 0.0:
				return []
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]


# --- The real Texas, from the map builder (worker thread) -----------------------------------

const ROAD_COLORS := [Color(0.19, 0.19, 0.20), Color(0.21, 0.21, 0.22), Color(0.24, 0.24, 0.24),
	Color(0.27, 0.27, 0.27), Color(0.30, 0.30, 0.29), Color(0.21, 0.21, 0.22), Color(0.22, 0.22, 0.22),
	Color(0.25, 0.25, 0.25), Color(0.27, 0.27, 0.27)]
const BUILDING_COLORS := [Color(0.74, 0.72, 0.68), Color(0.80, 0.74, 0.62), Color(0.70, 0.52, 0.42),
	Color(0.62, 0.66, 0.70), Color(0.76, 0.77, 0.76), Color(0.58, 0.36, 0.30), Color(0.82, 0.76, 0.62),
	Color(0.48, 0.50, 0.40)]
const WATER := Color(0.20, 0.38, 0.52)


static func _th(hs: PackedFloat32Array, lx: float, lz: float) -> float:
	## The tile's ground height (game metres) at a tile-local point, from its own 64 m grid
	var fx := clampf(lx / (TILE / GRID), 0.0, GRID - 0.0001)
	var fz := clampf(lz / (TILE / GRID), 0.0, GRID - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var n := GRID + 1
	var a := j * n + i
	return lerpf(lerpf(hs[a], hs[a + 1], tx), lerpf(hs[a + n], hs[a + n + 1], tx), tz)


static func _strip(pts: PackedVector2Array, half: float, col: Color, lift: float, hs: PackedFloat32Array,
		v: PackedVector3Array, c: PackedColorArray, nm: PackedVector3Array, bridge := false, dry := false) -> void:
	## A ribbon along a line, draped over the ground (or held level across a bridge), with
	## mitred corners so it doesn't crack at bends. Long pieces are split to follow the ground.
	var fine := PackedVector2Array()
	for k in pts.size():
		if k > 0:
			var a := pts[k - 1]
			var b := pts[k]
			var pieces := int(a.distance_to(b) / 32.0)
			for q in range(1, pieces + 1):
				fine.append(a.lerp(b, float(q) / (pieces + 1)))
		fine.append(pts[k])
	var n := fine.size()
	if n < 2:
		return
	var h0 := _th(hs, fine[0].x, fine[0].y)
	var h1 := _th(hs, fine[n - 1].x, fine[n - 1].y)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(n)
	right.resize(n)
	for k in n:
		var d_in := (fine[k] - fine[maxi(k - 1, 0)])
		var d_out := (fine[mini(k + 1, n - 1)] - fine[k])
		if d_in.length_squared() < 1e-6:
			d_in = d_out
		if d_out.length_squared() < 1e-6:
			d_out = d_in
		var t := (d_in.normalized() + d_out.normalized())
		if t.length_squared() < 1e-6:
			t = d_out
		t = t.normalized()
		var side := Vector2(-t.y, t.x)
		var miter := half / maxf(side.dot(Vector2(-d_out.normalized().y, d_out.normalized().x)), 0.5)
		var y := _th(hs, fine[k].x, fine[k].y)
		if bridge:
			y = maxf(y, lerpf(h0, h1, float(k) / (n - 1)))
			y = maxf(y, 0.6)
		elif dry:
			# a road across low water (a causeway, a wharf) stays above it
			y = maxf(y, 0.3)
		var l := fine[k] + side * miter
		var r := fine[k] - side * miter
		left[k] = Vector3(l.x, y + lift, l.y)
		right[k] = Vector3(r.x, y + lift, r.y)
	for k in n - 1:
		for p in [left[k], right[k], left[k + 1], right[k], right[k + 1], left[k + 1]]:
			v.append(p)
			c.append(col)
			nm.append(Vector3.UP)


static func _near_sea(x: float, z: float, step: float) -> bool:
	for d in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
		if TexasData.flags(x + d.x, z + d.y) & 2 != 0:
			return true
	return false


func _build_real(key: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	TexasWater.warm_tile(key)              # the tile's water for the units, while we're here
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	var n := GRID + 1
	var step := TILE / GRID
	var rs := TexasData.region_size
	var rx := floori(x0 / rs)
	var rz := floori(z0 / rs)
	var si := int(roundf((x0 - rx * rs) / TexasData.step))
	var sj := int(roundf((z0 - rz * rs) / TexasData.step))
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	verts.resize(n * n)
	cols.resize(n * n)
	hs.resize(n * n)
	for j in n:
		for i in n:
			var hr := TexasData.height_at_sample(rx, rz, si + i, sj + j)
			var h := hr * TexasGeo.VERTICAL
			hs[j * n + i] = h
			verts[j * n + i] = Vector3(i * step, h, j * step)
			var c := TexasGeo.ground_color(x0 + i * step, z0 + j * step, hr)
			if hr < 0.0:
				c = Color(0.55, 0.52, 0.42)
			elif hr < 5.0 and _near_sea(x0 + i * step, z0 + j * step, step):
				c = Color(0.80, 0.74, 0.56)                   # beach: low ground next to the sea
			cols[j * n + i] = c
	var idx := PackedInt32Array()
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for j in n:
		for i in n:
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr2 := hs[j * n + mini(i + 1, GRID)]
			var hu := hs[maxi(j - 1, 0) * n + i]
			var hd := hs[mini(j + 1, GRID) * n + i]
			norms[j * n + i] = Vector3(hl - hr2, 2.0 * step, hu - hd).normalized()
	var data := TexasData.tile(key)
	var rv := PackedVector3Array()
	var rc := PackedColorArray()
	var rn := PackedVector3Array()
	var wv := PackedVector3Array()
	var wc := PackedColorArray()
	var wn := PackedVector3Array()
	# Water: lakes level, rivers following the ground
	var w: PackedFloat32Array = data.get(3, PackedFloat32Array())
	var p := 0
	while p < w.size():
		var tris := int(w[p])
		var level := w[p + 1]
		p += 2
		for q in tris * 3:
			var lx := w[p]
			var lz := w[p + 1]
			p += 2
			var y := level * TexasGeo.VERTICAL + 0.05 if level > -9000.0 else _th(hs, lx, lz) + 0.3
			wv.append(Vector3(lx, y, lz))
			wc.append(WATER)
			wn.append(Vector3.UP)
	# fix the winding: earcut's triangles may face down
	for t in range(0, wv.size(), 3):
		var e1 := wv[t + 1] - wv[t]
		var e2 := wv[t + 2] - wv[t]
		if e1.cross(e2).y > 0.0:
			var tmp := wv[t + 1]
			wv[t + 1] = wv[t + 2]
			wv[t + 2] = tmp
	var rivers: PackedFloat32Array = data.get(4, PackedFloat32Array())
	p = 0
	while p < rivers.size():
		var cnt := int(rivers[p])
		var width := rivers[p + 1]
		var line := PackedVector2Array()
		for q in cnt:
			line.append(Vector2(rivers[p + 2 + q * 2], rivers[p + 3 + q * 2]))
		p += 2 + cnt * 2
		_strip(line, width * 0.5, WATER, 0.22, hs, wv, wc, wn)
	# Railways, then roads (smaller roads first so the big ones draw on top where they meet)
	var rail: PackedFloat32Array = data.get(5, PackedFloat32Array())
	p = 0
	while p < rail.size():
		var cnt := int(rail[p])
		var line := PackedVector2Array()
		for q in cnt:
			line.append(Vector2(rail[p + 1 + q * 2], rail[p + 2 + q * 2]))
		p += 1 + cnt * 2
		_strip(line, 2.2, Color(0.34, 0.30, 0.27), 0.28, hs, rv, rc, rn)
	var roads: PackedFloat32Array = data.get(2, PackedFloat32Array())
	var lines: Array = []
	p = 0
	while p < roads.size():
		var cnt := int(roads[p])
		lines.append([int(roads[p + 1]), roads[p + 2], roads[p + 3] > 0.5, p + 4, cnt])
		p += 4 + cnt * 2
	lines.sort_custom(func(a, b): return a[0] > b[0])
	for L in lines:
		var line := PackedVector2Array()
		var at: int = L[3]
		for q in L[4]:
			line.append(Vector2(roads[at + q * 2], roads[at + 1 + q * 2]))
		var cls: int = L[0]
		_strip(line, L[1] * 0.5, ROAD_COLORS[clampi(cls, 0, 8)], 0.35 + (8 - cls) * 0.01, hs, rv, rc, rn, L[2], true)
	# Runways: the strip and a centre line
	var rw: PackedFloat32Array = data.get(6, PackedFloat32Array())
	for k in range(0, rw.size(), 7):
		var c := Vector2(rw[k], rw[k + 1])
		var dir := Vector2(cos(rw[k + 4]), sin(rw[k + 4]))
		var half_len := rw[k + 2] * 0.5
		var line := PackedVector2Array([c - dir * half_len, c + dir * half_len])
		var paved := rw[k + 5] > 0.5
		_strip(line, rw[k + 3] * 0.5, Color(0.25, 0.25, 0.26) if paved else Color(0.55, 0.50, 0.40), 0.45, hs, rv, rc, rn)
		_strip(line, 0.6, Color(0.85, 0.85, 0.80), 0.5, hs, rv, rc, rn)
	# Buildings: real size and shape, turned to their real heading
	var bt := PackedFloat32Array()
	var b: PackedFloat32Array = data.get(1, PackedFloat32Array())
	for k in range(0, b.size(), 8):
		var bx := b[k]
		var bz := b[k + 1]
		var bw := b[k + 2]
		var bd := b[k + 3]
		var ang := b[k + 4]
		var bh := b[k + 5]
		var kind := clampi(int(b[k + 6]), 0, 7)
		var shade := 0.85 + b[k + 7] * 0.3
		var ca := cos(ang)
		var sa := sin(ang)
		var gy := _th(hs, bx, bz)
		var tall := bh + 1.5
		var col: Color = BUILDING_COLORS[kind] * shade
		col.a = 1.0
		bt.append_array([bw * ca, 0.0, -bd * sa, bx, 0.0, tall, 0.0, gy - 1.5 + tall * 0.5, bw * sa, 0.0, bd * ca, bz,
			col.r, col.g, col.b, 1.0])
	var result := {"key": key, "verts": verts, "cols": cols, "norms": norms, "idx": idx,
		"rv": rv, "rc": rc, "rn": rn, "wv": wv, "wc": wc, "wn": wn, "bt": bt,
		"ms": (Time.get_ticks_usec() - t0) / 1000.0}
	_mutex.lock()
	_done.append(result)
	_mutex.unlock()


# --- Making the scene nodes (main thread) ---------------------------------------------------

func _make_tile(r: Dictionary) -> Node3D:
	var key: Vector2i = r.key
	var node := Node3D.new()
	node.name = "Tile_%d_%d" % [key.x, key.y]
	node.position = Vector3(key.x * TILE - origin_x, 0.0, key.y * TILE - origin_z)
	add_child(node)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r.verts
	arrays[Mesh.ARRAY_NORMAL] = r.norms
	arrays[Mesh.ARRAY_COLOR] = r.cols
	arrays[Mesh.ARRAY_INDEX] = r.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _terrain_mat
	node.add_child(mi)
	if r.has("wv") and not (r.wv as PackedVector3Array).is_empty():
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = r.wv
		wa[Mesh.ARRAY_NORMAL] = r.wn
		wa[Mesh.ARRAY_COLOR] = r.wc
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wm
		wmi.material_override = TexasWaterLook.inland
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wmi)
	if not (r.rv as PackedVector3Array).is_empty():
		var ra := []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = r.rv
		ra[Mesh.ARRAY_NORMAL] = r.rn
		ra[Mesh.ARRAY_COLOR] = r.rc
		var rm := ArrayMesh.new()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rm
		rmi.material_override = _road_mat
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rmi)
	var bt: PackedFloat32Array = r.bt
	if not bt.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _box
		mm.instance_count = bt.size() / 16
		mm.buffer = bt
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _building_mat
		node.add_child(mmi)
	return node
