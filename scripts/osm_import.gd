class_name OsmImport
extends RefCounted
## Reads a real map from an OpenStreetMap file (.osm, XML) and turns it into the shapes the city
## builder draws: building footprints with heights, roads by class, railways, water, parks,
## parking lots, trees and place names. Coordinates are projected to metres around a centre
## point (x = east, z = south, like the rest of the game) and scaled.
##
## Turned on by data/real_map.json (see README "Real map"):
##   {"osm_file": "res://data/dfw.osm", "center_lat": 32.748, "center_lon": -97.09,
##    "scale": 1.0, "rotation_deg": 0}
## With no config, or no .osm file, the game uses its own generated city.
##
## Building footprints are kept as polygons here; the city builder turns each into one or more
## boxes (see CityBuilder._real_building), which is what the pixel-art look, collision and
## pathfinding all need.

const CONFIG_PATH := "res://data/real_map.json"
const M_PER_DEG_LAT := 110574.0
const M_PER_DEG_LON_EQ := 111320.0

const ROAD_WIDTHS := {
	"motorway": 24.0, "trunk": 20.0, "primary": 15.0, "secondary": 13.0, "tertiary": 11.0,
	"motorway_link": 9.0, "trunk_link": 9.0, "primary_link": 8.0, "secondary_link": 8.0, "tertiary_link": 8.0,
	"residential": 8.0, "unclassified": 8.0, "living_street": 7.0, "road": 8.0, "service": 5.0,
	"pedestrian": 5.0,
}
const WATER_AREA := ["water", "reservoir", "basin", "riverbank"]
const PARK_LEISURE := ["park", "pitch", "golf_course", "garden", "playground", "dog_park", "nature_reserve", "recreation_ground"]
const PARK_LANDUSE := ["grass", "recreation_ground", "cemetery", "meadow", "forest", "village_green", "greenfield"]
const PLACE_KINDS := ["suburb", "neighbourhood", "quarter", "locality", "city", "town"]

var config := {}
var buildings: Array = []   # {poly: PackedVector2Array, height: float, kind: String, name: String, levels: float}
var roads: Array = []       # {pts: PackedVector2Array, width: float, kind: String, bridge: bool, name: String}
var rails: Array = []       # PackedVector2Array
var water: Array = []       # PackedVector2Array (areas)
var waterways: Array = []   # {pts: PackedVector2Array, width: float, river: bool}
var parks: Array = []       # {poly: PackedVector2Array, kind: String}
var lots: Array = []        # PackedVector2Array (parking)
var trees: Array = []       # Vector2
var places: Array = []      # {name: String, pos: Vector2, size: float}
var stats := {}
var bounds := Rect2()       # the playable area in map metres

var _lat0 := 0.0
var _lon0 := 0.0
var _scale := 1.0
var _rot := 0.0
var _m_lon := 1.0
var _nodes := {}            # id -> Vector2 (map metres)
var _node_tags := {}        # id -> tags (only nodes that have any)
var _ways := {}             # id -> {refs: PackedInt64Array, tags: Dictionary}
var _relations: Array = []  # {members: Array of [type, ref, role], tags}


const SECTORS_PATH := "res://data/sectors.json"
const SECTOR_DIR := "res://data/sectors/"


static func sectors() -> Array:
	## The DFW sectors (real-size maps, one per mission), in order, each with "ready" = its
	## map file has been downloaded
	if not FileAccess.file_exists(SECTORS_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SECTORS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for sec in parsed.get("sectors", []):
		var d: Dictionary = sec.duplicate()
		d["osm_file"] = SECTOR_DIR + String(d.id) + ".osm"
		d["ready"] = FileAccess.file_exists(d.osm_file)
		out.append(d)
	return out


static func load_config() -> Dictionary:
	## The map to build, from what was picked under New game (Settings.sector): a sector,
	## "custom" = data/real_map.json, or "" = {} (the generated city)
	var picked: String = Settings.sector
	if picked == "":
		return {}
	if picked != "custom":
		for sec in sectors():
			if sec.id == picked:
				if sec.ready:
					return sec
				print("Real map: sector %s isn't downloaded (%s), using the generated city" % [picked, sec.osm_file])
				return {}
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.get("enabled", true):
		return {}
	var path: String = parsed.get("osm_file", "")
	if path == "" or not FileAccess.file_exists(path):
		print("Real map: %s not found, using the generated city" % path)
		return {}
	return parsed


func run(cfg: Dictionary, half_x: float, half_z: float) -> bool:
	config = cfg
	_lat0 = float(cfg.get("center_lat", 32.748))
	_lon0 = float(cfg.get("center_lon", -97.09))
	_scale = float(cfg.get("scale", 1.0))
	_rot = deg_to_rad(float(cfg.get("rotation_deg", 0.0)))
	_m_lon = M_PER_DEG_LON_EQ * cos(deg_to_rad(_lat0))
	bounds = Rect2(-half_x, -half_z, half_x * 2.0, half_z * 2.0)
	var t0 := Time.get_ticks_msec()
	if not _parse(cfg.osm_file):
		return false
	var t1 := Time.get_ticks_msec()
	_classify()
	stats = {"nodes": _nodes.size(), "ways": _ways.size(), "relations": _relations.size(),
		"buildings": buildings.size(), "roads": roads.size(), "water": water.size() + waterways.size(),
		"parks": parks.size(), "lots": lots.size(), "trees": trees.size(), "places": places.size(),
		"parse_ms": t1 - t0, "build_ms": Time.get_ticks_msec() - t1}
	_nodes.clear()
	_node_tags.clear()
	_ways.clear()
	_relations.clear()
	return true


func project(lat: float, lon: float) -> Vector2:
	var p := Vector2((lon - _lon0) * _m_lon, -(lat - _lat0) * M_PER_DEG_LAT) * _scale
	return p.rotated(_rot) if _rot != 0.0 else p


# --- Reading the XML ---------------------------------------------------------------------

func _parse(path: String) -> bool:
	var x := XMLParser.new()
	if x.open(path) != OK:
		push_error("Real map: can't open %s" % path)
		return false
	var cur_kind := ""         # node, way, relation
	var cur_id := 0
	var cur_tags := {}
	var cur_refs := PackedInt64Array()
	var cur_members: Array = []
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var name := x.get_node_name()
			match name:
				"node":
					var id := x.get_named_attribute_value_safe("id").to_int()
					var lat := x.get_named_attribute_value_safe("lat").to_float()
					var lon := x.get_named_attribute_value_safe("lon").to_float()
					_nodes[id] = project(lat, lon)
					if not x.is_empty():
						cur_kind = "node"
						cur_id = id
						cur_tags = {}
				"way":
					cur_kind = "way"
					cur_id = x.get_named_attribute_value_safe("id").to_int()
					cur_tags = {}
					cur_refs = PackedInt64Array()
					if x.is_empty():
						cur_kind = ""
				"relation":
					cur_kind = "relation"
					cur_id = x.get_named_attribute_value_safe("id").to_int()
					cur_tags = {}
					cur_members = []
					if x.is_empty():
						cur_kind = ""
				"nd":
					if cur_kind == "way":
						cur_refs.append(x.get_named_attribute_value_safe("ref").to_int())
				"member":
					if cur_kind == "relation":
						cur_members.append([x.get_named_attribute_value_safe("type"), x.get_named_attribute_value_safe("ref").to_int(), x.get_named_attribute_value_safe("role")])
				"tag":
					if cur_kind != "":
						cur_tags[x.get_named_attribute_value_safe("k")] = x.get_named_attribute_value_safe("v")
		elif t == XMLParser.NODE_ELEMENT_END:
			match x.get_node_name():
				"node":
					if cur_kind == "node" and not cur_tags.is_empty():
						_node_tags[cur_id] = cur_tags
					cur_kind = ""
				"way":
					_ways[cur_id] = {"refs": cur_refs, "tags": cur_tags}
					cur_kind = ""
				"relation":
					_relations.append({"members": cur_members, "tags": cur_tags})
					cur_kind = ""
	return true


# --- Sorting it into game shapes -------------------------------------------------------------

func _classify() -> void:
	var used_ways := {}
	# Multipolygons: buildings, water and parks made of several ways (outer rings only)
	for r in _relations:
		var tags: Dictionary = r.tags
		if tags.get("type", "") != "multipolygon":
			continue
		var outer: Array = []
		for m in r.members:
			if m[0] == "way" and (m[2] == "outer" or m[2] == "") and _ways.has(m[1]):
				outer.append(m[1])
		for ring in _rings(outer):
			var poly := _poly(ring)
			if poly.size() >= 3:
				_area(poly, tags)
		# Outer ways that carry no tags of their own were only there for this relation
		for wid in outer:
			if (_ways[wid].tags as Dictionary).is_empty():
				used_ways[wid] = true
	for wid in _ways:
		if used_ways.has(wid):
			continue
		var w: Dictionary = _ways[wid]
		var tags: Dictionary = w.tags
		if tags.is_empty():
			continue
		var refs: PackedInt64Array = w.refs
		var closed := refs.size() >= 4 and refs[0] == refs[refs.size() - 1]
		if closed and _is_area(tags):
			_area(_poly(refs), tags)
			continue
		var pts := _line(refs)
		if pts.size() < 2:
			continue
		if tags.has("highway") and ROAD_WIDTHS.has(tags.highway) and tags.get("area", "no") != "yes":
			var width: float = ROAD_WIDTHS[tags.highway] * clampf(_scale, 0.6, 1.0)
			for piece in _clip_line(pts):
				roads.append({"pts": piece, "width": width, "kind": tags.highway,
					"bridge": tags.get("bridge", "no") != "no", "name": tags.get("name", tags.get("ref", ""))})
		elif tags.get("railway", "") in ["rail", "light_rail"]:
			for piece in _clip_line(pts):
				rails.append(piece)
		elif tags.get("waterway", "") in ["river", "canal", "stream", "ditch", "drain"]:
			var river: bool = tags.waterway in ["river", "canal"]
			var width: float = String(tags.get("width", "")).to_float()
			if width <= 0.0:
				width = 18.0 if river else 3.0
			for piece in _clip_line(pts):
				waterways.append({"pts": piece, "width": width * _scale, "river": river})
	for nid in _node_tags:
		var tags: Dictionary = _node_tags[nid]
		var p: Vector2 = _nodes[nid]
		if not bounds.has_point(p):
			continue
		if tags.get("natural", "") == "tree":
			trees.append(p)
		elif tags.get("place", "") in PLACE_KINDS and tags.has("name"):
			places.append({"name": tags.name, "pos": p, "size": 40.0 if tags.place in ["city", "town", "suburb"] else 25.0})


func _is_area(tags: Dictionary) -> bool:
	return tags.has("building") or tags.get("natural", "") in ["water", "wood"] or tags.get("landuse", "") in WATER_AREA + PARK_LANDUSE \
		or tags.get("waterway", "") == "riverbank" or tags.get("leisure", "") in PARK_LEISURE + ["stadium"] \
		or tags.get("amenity", "") == "parking" or tags.get("area", "") == "yes"


func _area(poly: PackedVector2Array, tags: Dictionary) -> void:
	## A closed shape: a building, water, a park or a parking lot
	if poly.size() < 3:
		return
	var b: String = tags.get("building", "no")
	var clipped := _clip_poly(poly)
	if clipped.is_empty():
		return
	if b != "no" and b != "":
		var h := _height(tags, b, absf(_signed_area(poly)))
		for c in clipped:
			buildings.append({"poly": c, "height": h, "kind": b, "name": tags.get("name", "")})
		_maybe_place(poly, tags)
		return
	if tags.get("natural", "") == "water" or tags.get("landuse", "") in WATER_AREA or tags.get("waterway", "") == "riverbank":
		water.append_array(clipped)
		return
	if tags.get("amenity", "") == "parking":
		lots.append_array(clipped)
		return
	if tags.get("leisure", "") in PARK_LEISURE + ["stadium"] or tags.get("landuse", "") in PARK_LANDUSE or tags.get("natural", "") == "wood":
		var kind: String = tags.get("leisure", tags.get("landuse", tags.get("natural", "park")))
		for c in clipped:
			parks.append({"poly": c, "kind": kind})
		_maybe_place(poly, tags)


func _maybe_place(poly: PackedVector2Array, tags: Dictionary) -> void:
	## Big named things (stadiums, parks) get a label
	if not tags.has("name"):
		return
	var a := absf(_signed_area(poly))
	if a < 6000.0 * _scale * _scale:
		return
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	if bounds.has_point(c):
		places.append({"name": tags.name, "pos": c, "size": clampf(sqrt(a) * 0.25, 18.0, 45.0)})


func _height(tags: Dictionary, kind: String, area: float) -> float:
	var h := _metres(tags.get("height", ""))
	if h <= 0.0:
		var levels: float = String(tags.get("building:levels", "")).to_float()
		if levels > 0.0:
			h = levels * 3.3 + (1.0 if levels <= 2.0 else 0.0)
	if h <= 0.0:
		match kind:
			"house", "detached", "semidetached_house", "terrace", "bungalow", "residential", "farm":
				h = 4.5 if area < 220.0 else 6.5
			"garage", "garages", "shed", "carport", "roof", "hut":
				h = 3.0
			"apartments", "dormitory":
				h = 11.0
			"commercial", "retail", "supermarket", "kiosk", "restaurant":
				h = 6.5
			"industrial", "warehouse", "manufacture":
				h = 9.0
			"office":
				h = 18.0
			"hotel", "hospital":
				h = 24.0
			"school", "church", "university", "civic", "public":
				h = 9.0
			"stadium", "grandstand":
				h = 30.0
			"parking":
				h = 10.0
			_:
				h = 4.5 if area < 200.0 else (7.0 if area < 1500.0 else 10.0)
	return clampf(h, 2.5, 320.0)


static func _metres(v: String) -> float:
	v = v.strip_edges().to_lower()
	if v == "":
		return 0.0
	if v.ends_with("ft") or v.ends_with("'"):
		return v.trim_suffix("ft").trim_suffix("'").strip_edges().to_float() * 0.3048
	return v.trim_suffix("m").strip_edges().to_float()


# --- Geometry helpers ------------------------------------------------------------------------

func _poly(refs: PackedInt64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in refs.size():
		if i == refs.size() - 1 and refs[i] == refs[0]:
			break
		if _nodes.has(refs[i]):
			out.append(_nodes[refs[i]])
	return out


func _line(refs: PackedInt64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in refs:
		if _nodes.has(r):
			out.append(_nodes[r])
	return out


func _rings(way_ids: Array) -> Array:
	## Join a multipolygon's outer ways end to end into closed rings
	var segs: Array = []
	for wid in way_ids:
		var refs: PackedInt64Array = _ways[wid].refs
		if refs.size() >= 2:
			segs.append(refs.duplicate())
	var rings: Array = []
	while not segs.is_empty():
		var cur: PackedInt64Array = segs.pop_back()
		var guard := 0
		while cur[0] != cur[cur.size() - 1] and guard < 500:
			guard += 1
			var joined := false
			for i in segs.size():
				var s: PackedInt64Array = segs[i]
				if s[0] == cur[cur.size() - 1]:
					cur.append_array(s.slice(1))
				elif s[s.size() - 1] == cur[cur.size() - 1]:
					var r := s.duplicate()
					r.reverse()
					cur.append_array(r.slice(1))
				else:
					continue
				segs.remove_at(i)
				joined = true
				break
			if not joined:
				break
		if cur.size() >= 4 and cur[0] == cur[cur.size() - 1]:
			rings.append(cur)
	return rings


func _bounds_poly() -> PackedVector2Array:
	var r := bounds
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _clip_poly(poly: PackedVector2Array) -> Array:
	## The parts of a shape inside the map (most are entirely inside or outside)
	var inside := 0
	for p in poly:
		if bounds.has_point(p):
			inside += 1
	if inside == poly.size():
		return [poly]
	var box := bounds
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	if not r.intersects(box):
		return []
	var out: Array = []
	for c in Geometry2D.intersect_polygons(poly, _bounds_poly()):
		if (c as PackedVector2Array).size() >= 3:
			out.append(c)
	return out


func _clip_line(pts: PackedVector2Array) -> Array:
	var inside := true
	for p in pts:
		if not bounds.has_point(p):
			inside = false
			break
	if inside:
		return [pts]
	var out: Array = []
	for piece in Geometry2D.intersect_polyline_with_polygon(pts, _bounds_poly()):
		if (piece as PackedVector2Array).size() >= 2:
			out.append(piece)
	return out


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func obb(poly: PackedVector2Array) -> Dictionary:
	## The smallest rectangle around a shape: {center, size (along, across), angle (radians)}
	var hull := Geometry2D.convex_hull(poly)
	var best := {"area": INF}
	for i in range(hull.size() - 1):
		var d := hull[i + 1] - hull[i]
		if d.length() < 0.01:
			continue
		var u := d.normalized()
		var v := Vector2(-u.y, u.x)
		var u0 := INF
		var u1 := -INF
		var v0 := INF
		var v1 := -INF
		for p in hull:
			var a := p.dot(u)
			var b := p.dot(v)
			u0 = minf(u0, a)
			u1 = maxf(u1, a)
			v0 = minf(v0, b)
			v1 = maxf(v1, b)
		var area := (u1 - u0) * (v1 - v0)
		if area < best.area:
			best = {"area": area, "center": u * (u0 + u1) * 0.5 + v * (v0 + v1) * 0.5,
				"size": Vector2(u1 - u0, v1 - v0), "angle": u.angle()}
	if not best.has("center"):
		var c := poly[0]
		return {"area": 0.0, "center": c, "size": Vector2(1, 1), "angle": 0.0}
	return best


static func boxes_for(poly: PackedVector2Array) -> Array:
	## A footprint as boxes: one if it's roughly rectangular, otherwise one per convex piece
	var area := absf(_signed_area(poly))
	var whole := obb(poly)
	if area < 150.0 or whole.area <= 0.0 or area / whole.area > 0.8:
		return [whole]
	var out: Array = []
	var pieces := Geometry2D.decompose_polygon_in_convex(poly)
	if pieces.is_empty() or pieces.size() > 12:
		return [whole]
	for piece in pieces:
		var pa := absf(_signed_area(piece))
		if pa < 6.0:
			continue
		out.append(obb(piece))
	return out if not out.is_empty() else [whole]
