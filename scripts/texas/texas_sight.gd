class_name TexasSight
extends RefCounted
## Line of sight: can one unit see (and so shoot) another, or is a building or a hill in the way?
## Each 2 km tile's buildings are turned into a grid of rooftop heights (8 m cells) the first
## time a shot crosses it; the ground comes from the height data. Safe from the fight thread.

const RES := 8.0                      # game metres per cell of the rooftop grid
const N := 256                        # cells across a tile (2048 / 8)
const END_GAP := 14.0                 # the bit next to the shooter and the target doesn't count
const GROUND_STEP := 64.0             # how often the ground is looked at along the line

static var _tiles := {}               # Vector2i -> PackedByteArray (empty: no buildings)
static var _mutex := Mutex.new()
static var tests := 0                 # how many sight lines were worked out (for the labs)
static var blocked := 0


static func eye(kind: int, airborne: bool) -> float:
	## How high above the ground a unit looks from (and is seen at), game metres
	match kind:
		TexasSim.Kind.JET:
			return 160.0 if airborne else 1.5
		TexasSim.Kind.HELI:
			return 45.0 if airborne else 1.5
		TexasSim.Kind.SHIP:
			return 12.0
		TexasSim.Kind.INFANTRY:
			return 0.7
	return 1.2


static func roofs(key: Vector2i) -> PackedByteArray:
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
	if not TexasData.available:
		return PackedByteArray()
	var data := TexasData.tile(key)
	var b: PackedFloat32Array = data.get(1, PackedFloat32Array())
	if b.is_empty():
		return PackedByteArray()
	var g := PackedByteArray()
	g.resize(N * N)
	for k in range(0, b.size(), 8):
		var bx := b[k]
		var bz := b[k + 1]
		var bw := b[k + 2]
		var bd := b[k + 3]
		var ang := b[k + 4]
		var top := clampi(roundi(b[k + 5]), 1, 255)
		var ca := cos(ang)
		var sa := sin(ang)
		var ex := absf(bw * 0.5 * ca) + absf(bd * 0.5 * sa)
		var ez := absf(bw * 0.5 * sa) + absf(bd * 0.5 * ca)
		var i0 := clampi(floori((bx - ex) / RES), 0, N - 1)
		var i1 := clampi(floori((bx + ex) / RES), 0, N - 1)
		var j0 := clampi(floori((bz - ez) / RES), 0, N - 1)
		var j1 := clampi(floori((bz + ez) / RES), 0, N - 1)
		for j in range(j0, j1 + 1):
			var pz := (j + 0.5) * RES - bz
			for i in range(i0, i1 + 1):
				var px := (i + 0.5) * RES - bx
				var u := px * ca + pz * sa
				var w := -px * sa + pz * ca
				if absf(u) <= bw * 0.5 and absf(w) <= bd * 0.5:
					if g[j * N + i] < top:
						g[j * N + i] = top
		# a building smaller than a cell still blocks the cell it stands in
		var ci := clampi(floori(bx / RES), 0, N - 1)
		var cj := clampi(floori(bz / RES), 0, N - 1)
		if g[cj * N + ci] < top:
			g[cj * N + ci] = top
	return g


static func clear(ax: float, az: float, ah: float, bx: float, bz: float, bh: float) -> bool:
	## True if nothing stands between a point `ah` above the ground at (ax, az) and one `bh`
	## above the ground at (bx, bz)
	tests += 1
	var dx := bx - ax
	var dz := bz - az
	var L := sqrt(dx * dx + dz * dz)
	if L <= END_GAP * 2.0:
		return true
	var ga := maxf(TexasGeo.height(ax, az), 0.0)
	var gb := maxf(TexasGeo.height(bx, bz), 0.0)
	var ya := ga + ah
	var yb := gb + bh
	var tile := TexasData.tile_size
	var steps := ceili(L / RES)
	var gstride := maxi(1, int(GROUND_STEP / RES))
	var cur_key := Vector2i(1 << 30, 0)
	var cur := PackedByteArray()
	var ground := ga
	for s in range(1, steps):
		var f := float(s) / steps
		var d := f * L
		if d < END_GAP or d > L - END_GAP:
			continue
		var px := ax + dx * f
		var pz := az + dz * f
		var line_y := lerpf(ya, yb, f)
		if s % gstride == 0:
			ground = maxf(TexasGeo.height(px, pz), 0.0)
			# hills (more than a little over the line) block
			if ground > line_y + 0.5:
				blocked += 1
				return false
		if line_y - ground > 255.0:
			continue
		var key := Vector2i(floori(px / tile), floori(pz / tile))
		if key != cur_key:
			cur_key = key
			cur = roofs(key)
		if cur.is_empty():
			continue
		var i := clampi(floori((px - key.x * tile) / RES), 0, N - 1)
		var j := clampi(floori((pz - key.y * tile) / RES), 0, N - 1)
		var top := cur[j * N + i]
		if top > 0 and ground + top > line_y:
			blocked += 1
			return false
	return true
