class_name TexasData
extends RefCounted
## Reads the map builder's output (tools/texas_build.py → data/texas/build/): the real heights,
## the sea and the state border, and per 2 km tile the roads, buildings, water, railways and
## runways. Regions (32 km) are read from disk the first time anything asks about them and kept;
## every call here is safe from the tile threads.

const DIR := "res://data/texas/build/"
const RT := 16

static var available := false
static var meta: Dictionary = {}
static var tile_size := 2048.0
static var region_size := 32768.0
static var step := 64.0
static var samples := 513
static var _regions := {}                 # Vector2i -> Dictionary
static var _mutex := Mutex.new()


static func load_meta() -> bool:
	## Call on the main thread before anything else; false if there's no build
	if available:
		return true
	if not FileAccess.file_exists(DIR + "meta.json"):
		return false
	var txt := FileAccess.get_file_as_string(DIR + "meta.json")
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("TexasData: meta.json didn't parse")
		return false
	meta = d
	tile_size = meta.tile
	region_size = meta.region
	step = meta.height_step
	samples = int(meta.height_samples)
	available = true
	return true


static func region(rx: int, rz: int) -> Dictionary:
	var key := Vector2i(rx, rz)
	_mutex.lock()
	var r: Dictionary = _regions.get(key, {})
	_mutex.unlock()
	if not r.is_empty():
		return r
	r = _read_region(rx, rz)
	_mutex.lock()
	if _regions.has(key):
		r = _regions[key]
	else:
		_regions[key] = r
	_mutex.unlock()
	return r


static func _read_region(rx: int, rz: int) -> Dictionary:
	var path := DIR + "regions/r_%d_%d.bin" % [rx, rz]
	var out := {"ok": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var bytes := f.get_buffer(f.get_length())
	if bytes.size() < 24 or bytes.slice(0, 4).get_string_from_ascii() != "TXR1":
		return out
	var at := 20
	var hraw := bytes.decode_u32(at)
	var hz := bytes.decode_u32(at + 4)
	out.heights = bytes.slice(at + 8, at + 8 + hz).decompress(hraw, FileAccess.COMPRESSION_DEFLATE)
	at += 8 + hz
	var fraw := bytes.decode_u32(at)
	var fz := bytes.decode_u32(at + 4)
	out.flags = bytes.slice(at + 8, at + 8 + fz).decompress(fraw, FileAccess.COMPRESSION_DEFLATE)
	at += 8 + fz
	out.table_at = at
	out.bytes = bytes
	out.ok = true
	return out


static func _sample(x: float, z: float) -> Array:
	## [region, column, row, fraction x, fraction z] for a point
	var rx := floori(x / region_size)
	var rz := floori(z / region_size)
	var r := region(rx, rz)
	var fx := (x - rx * region_size) / step
	var fz := (z - rz * region_size) / step
	return [r, fx, fz]


static func height_real(x: float, z: float) -> float:
	## Ground (or sea floor) in real metres, bilinear between the 64 m samples
	var s := _sample(x, z)
	var r: Dictionary = s[0]
	if not r.ok:
		return 0.0
	var fx: float = s[1]
	var fz: float = s[2]
	var i := clampi(floori(fx), 0, samples - 2)
	var j := clampi(floori(fz), 0, samples - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var h: PackedByteArray = r.heights
	var a := (j * samples + i) * 2
	var h00 := h.decode_s16(a)
	var h10 := h.decode_s16(a + 2)
	var h01 := h.decode_s16(a + samples * 2)
	var h11 := h.decode_s16(a + samples * 2 + 2)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz) * 0.25


static func height_at_sample(rx: int, rz: int, i: int, j: int) -> float:
	## Real metres at one sample of a region (no blending)
	var r := region(rx, rz)
	if not r.ok:
		return 0.0
	return (r.heights as PackedByteArray).decode_s16((j * samples + i) * 2) * 0.25


static func flags(x: float, z: float) -> int:
	## bit 0: in Texas, bit 1: sea, bit 2: built-up
	var s := _sample(x, z)
	var r: Dictionary = s[0]
	if not r.ok:
		return 0
	var i := clampi(roundi(s[1]), 0, samples - 1)
	var j := clampi(roundi(s[2]), 0, samples - 1)
	return (r.flags as PackedByteArray)[j * samples + i]


static func tile(key: Vector2i) -> Dictionary:
	## The map data of one 2 km tile: section tag -> PackedFloat32Array
	##   1 buildings: [x, z, width, depth, angle, height, kind, shade] each (tile-local, metres)
	##   2 roads: [points, class, width, bridge, x0, z0, x1, z1, ...] per line
	##   3 water: [triangles, level (real m, -9999 = follows the ground), x, z × 3 per triangle] per piece
	##   4 rivers: [points, width, x, z ...] per line
	##   5 railways: [points, x, z ...] per line
	##   6 runways: [x, z, length, width, angle, paved, airfield] each
	var out := {}
	var rx := floori(key.x * tile_size / region_size)
	var rz := floori(key.y * tile_size / region_size)
	var r := region(rx, rz)
	if not r.ok:
		return out
	var ti := key.x - rx * RT
	var tj := key.y - rz * RT
	var bytes: PackedByteArray = r.bytes
	var e: int = r.table_at + (tj * RT + ti) * 12
	var at := bytes.decode_u32(e)
	if at == 0:
		return out
	var comp := bytes.decode_u32(e + 4)
	var raw := bytes.decode_u32(e + 8)
	var body := bytes.slice(at, at + comp).decompress(raw, FileAccess.COMPRESSION_DEFLATE)
	var p := 0
	while p + 8 <= body.size():
		var tag := body.decode_u32(p)
		var n := body.decode_u32(p + 4)
		out[tag] = body.slice(p + 8, p + 8 + n * 4).to_float32_array()
		p += 8 + n * 4
	return out


static func read_roads() -> Dictionary:
	## The road network for units: junction and shape points, and the stretches between junctions
	var f := FileAccess.open(DIR + "roads.bin", FileAccess.READ)
	if f == null:
		return {}
	var bytes := f.get_buffer(f.get_length())
	if bytes.slice(0, 4).get_string_from_ascii() != "TXN1":
		return {}
	var j := bytes.decode_s32(4)
	var p := bytes.decode_s32(8)
	var c := bytes.decode_s32(12)
	if j == 0:
		return {}
	var raw := bytes.decode_u32(16)
	var comp := bytes.decode_u32(20)
	var body := bytes.slice(24, 24 + comp).decompress(raw, FileAccess.COMPRESSION_DEFLATE)
	var pts := body.slice(0, p * 16).to_float64_array()
	var rec := body.slice(p * 16, p * 16 + c * 20).to_int32_array()
	var lengths := body.slice(p * 16 + c * 20, p * 16 + c * 24).to_float32_array()
	return {"junctions": j, "points": pts, "chains": rec, "lengths": lengths}
