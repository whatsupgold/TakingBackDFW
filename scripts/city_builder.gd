class_name CityBuilder
extends RefCounted
## Builds a compressed, simplified Dallas–Fort Worth: real places in roughly the right spots,
## squeezed into a 1.8 x 0.9 km playable map. North is -Z, east is +X.
## The origin (the holdout building) sits in an Arlington plaza between the ballparks.
##
## Everything is generated from the data below with a fixed seed, so the city is the same
## every run. Buildings, ground, roads and trees are drawn with a handful of MultiMeshes;
## buildings get one collision box each (grouped per block) so units collide with them and they block line of sight.

const GEN_HALF_X := 900.0          # the generated city's size
const GEN_HALF_Z := 450.0
static var HALF_X := GEN_HALF_X    # this map's size (a real-map sector can be bigger)
static var HALF_Z := GEN_HALF_Z
const GRID := 60.0                 # street spacing (blocks are GRID - STREET wide)
const STREET := 10.0
const PLAZA := Rect2(-60, -50, 120, 100)   # x, z, w, h: the open lot around the holdout
const SEED := 1975

# Highways: polylines in (x, z), drawn at grade with lane markings
const HIGHWAYS := [
	{"name": "I-30", "width": 26.0, "pts": [Vector2(-900, -60), Vector2(-650, -60), Vector2(-420, -100), Vector2(-120, -110), Vector2(300, -110), Vector2(540, -55), Vector2(900, -55)]},
	{"name": "I-20", "width": 26.0, "pts": [Vector2(-900, 330), Vector2(900, 330)]},
	{"name": "I-35W", "width": 24.0, "pts": [Vector2(-560, -450), Vector2(-560, 450)]},
	{"name": "I-35E", "width": 24.0, "pts": [Vector2(590, -450), Vector2(575, 0), Vector2(590, 450)]},
	{"name": "Loop 820", "width": 20.0, "pts": [Vector2(-860, -300), Vector2(-430, -300), Vector2(-430, 280), Vector2(-860, 280), Vector2(-860, -300)]},
	{"name": "I-635", "width": 22.0, "pts": [Vector2(250, -290), Vector2(900, -290)]},
	{"name": "SH-360", "width": 20.0, "pts": [Vector2(-260, -450), Vector2(-260, 450)]},
	{"name": "SH-161", "width": 20.0, "pts": [Vector2(250, -450), Vector2(250, 450)]},
]

# The Trinity River: north of downtown Fort Worth, east across the metroplex, west of downtown Dallas
const RIVER_WIDTH := 22.0
const RIVER := [Vector2(-900, -230), Vector2(-700, -215), Vector2(-600, -200), Vector2(-480, -160),
	Vector2(-300, -170), Vector2(-100, -185), Vector2(100, -180), Vector2(300, -150), Vector2(470, -120),
	Vector2(520, -60), Vector2(530, 40), Vector2(570, 180), Vector2(640, 450)]

# Districts, first match wins. Types: downtown, offices, commercial, residential, industrial,
# stockyards, airport, park
const DISTRICTS := [
	{"name": "Downtown Fort Worth", "type": "downtown", "rect": Rect2(-760, -190, 230, 130), "tall": Vector2(14, 55)},
	{"name": "Fort Worth Stockyards", "type": "stockyards", "rect": Rect2(-720, -420, 150, 150)},
	{"name": "DFW Airport", "type": "airport", "rect": Rect2(-60, -450, 300, 150)},
	{"name": "Las Colinas", "type": "offices", "rect": Rect2(260, -285, 260, 150)},
	{"name": "Downtown Dallas", "type": "downtown", "rect": Rect2(600, -180, 220, 220), "tall": Vector2(22, 90)},
	{"name": "Fair Park", "type": "park", "rect": Rect2(690, 60, 210, 180)},   # the Red Army's ground: room for its FOB to grow
	{"name": "Arlington", "type": "commercial", "rect": Rect2(-250, -160, 490, 330)},
	{"name": "South industrial", "type": "industrial", "rect": Rect2(-430, 250, 680, 200)},
	{"name": "Fort Worth", "type": "residential", "rect": Rect2(-900, -450, 470, 900)},
	{"name": "Grand Prairie", "type": "residential", "rect": Rect2(-430, -450, 680, 900)},
	{"name": "Dallas", "type": "residential", "rect": Rect2(250, -450, 650, 900)},
]

# Big landmarks: footprints kept clear of generated blocks
const AT_T := Rect2(-200, 60, 160, 110)
const GLOBE_LIFE := Rect2(-170, -85, 100, 100)
const REUNION := Vector2(565, -5)

# Palette
const C_GROUND := Color(0.42, 0.45, 0.33)
const C_GRASS := Color(0.36, 0.48, 0.28)
const C_GRASS2 := Color(0.40, 0.52, 0.30)
const C_CONCRETE := Color(0.55, 0.55, 0.53)
const C_ASPHALT := Color(0.27, 0.28, 0.30)
const C_HIGHWAY := Color(0.33, 0.34, 0.36)
const C_LANE := Color(0.85, 0.82, 0.62)
const C_EDGE := Color(0.78, 0.78, 0.74)
const C_WATER := Color(0.24, 0.42, 0.52)
const C_BANK := Color(0.47, 0.42, 0.31)
const C_TRUNK := Color(0.34, 0.25, 0.16)
const C_LEAF := [Color(0.22, 0.38, 0.18), Color(0.28, 0.44, 0.20), Color(0.19, 0.33, 0.17)]
const TOWER_COLORS := [Color(0.42, 0.50, 0.56), Color(0.55, 0.57, 0.58), Color(0.36, 0.42, 0.50),
	Color(0.62, 0.58, 0.50), Color(0.30, 0.38, 0.44), Color(0.50, 0.46, 0.42)]
const HOUSE_COLORS := [Color(0.78, 0.72, 0.60), Color(0.70, 0.62, 0.52), Color(0.82, 0.80, 0.74),
	Color(0.62, 0.55, 0.47), Color(0.72, 0.66, 0.62), Color(0.58, 0.60, 0.56)]
const ROOF_COLORS := [Color(0.35, 0.30, 0.27), Color(0.42, 0.33, 0.28), Color(0.30, 0.30, 0.32), Color(0.45, 0.40, 0.34)]
const CAR_COLORS := [Color(0.55, 0.18, 0.16), Color(0.20, 0.28, 0.45), Color(0.80, 0.80, 0.78),
	Color(0.15, 0.15, 0.16), Color(0.45, 0.46, 0.44), Color(0.62, 0.52, 0.30)]

# Flat surfaces are stacked at these heights (far enough apart not to flicker at a distance)
const Y_GROUND := 0.0
const Y_LOT := 0.03
const Y_ROAD_EDGE := 0.04
const Y_STREET := 0.05
const Y_HIGHWAY := 0.06
const Y_PAINT := 0.08
const Y_BANK := 0.09
const Y_WATER := 0.11
const Y_BRIDGE := 0.13

# Window styles passed to the building shader (INSTANCE_CUSTOM.r)
const STYLE_PLAIN := 0.0
const STYLE_OFFICE := 1.0
const STYLE_HOUSE := 2.0
const STYLE_GLASS := 3.0

var root: Node3D
var rng := RandomNumberGenerator.new()
var material: ShaderMaterial
var labels: Array[Label3D] = []
var building_count := 0
var footprints: Array = []  # [Rect2 (x, z), Color] for the minimap
var solids: Array = []      # [corners (PackedVector3Array), height]: solid volumes the navmesh must not enter

var _boxes: Array = []      # [Transform3D, Color, Color custom]  (cast shadows)
var _flats: Array = []      # ground, roads, water (no shadows)
var _paint: Array = []      # lane markings: their own layer, hidden when zoomed far out
var paint_layer: MultiMeshInstance3D
var _prisms: Array = []     # pitched roofs
var _block_bodies := {}     # Vector2i -> StaticBody3D
var real_map: OsmImport = null   # set when the city comes from a real map (data/real_map.json)
var _polys: Array = []      # [PackedVector2Array, y, Color]: ground shapes from the real map


func build(parent: Node3D) -> void:
	root = parent
	rng.seed = SEED
	material = ShaderMaterial.new()
	material.shader = _make_shader()

	# A real map, if one is set up; otherwise the generated city
	HALF_X = GEN_HALF_X
	HALF_Z = GEN_HALF_Z
	var cfg := OsmImport.load_config()
	if not cfg.is_empty():
		HALF_X = float(cfg.get("width_m", GEN_HALF_X * 2.0)) * 0.5
		HALF_Z = float(cfg.get("height_m", GEN_HALF_Z * 2.0)) * 0.5
	RedFob.anchor(HALF_X)      # the Red FOB sits on the east edge, wherever that is
	if not cfg.is_empty():
		var imp := OsmImport.new()
		if imp.run(cfg, HALF_X, HALF_Z):
			real_map = imp
			print("Real map: %s" % imp.stats)
			_place_red_fob(imp)
			_build_real(imp)
			_flush()
			_flush_polys()
			return
		HALF_X = GEN_HALF_X      # (the map file didn't load: back to the generated city)
		HALF_Z = GEN_HALF_Z
		RedFob.anchor(HALF_X)

	_ground()
	_streets()
	_highways()
	_river()
	_blocks()
	_landmarks()
	_cars()
	_flush()
	_labels()


# --- Queries ------------------------------------------------------------------

static func dist_to_polyline(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func near_highway(p: Vector2, margin: float) -> bool:
	for h in HIGHWAYS:
		if dist_to_polyline(p, h.pts) < h.width * 0.5 + margin:
			return true
	return false


static func near_river(p: Vector2, margin: float) -> bool:
	return dist_to_polyline(p, RIVER) < RIVER_WIDTH * 0.5 + margin


static func district_at(p: Vector2) -> Dictionary:
	for d in DISTRICTS:
		if (d.rect as Rect2).has_point(p):
			return d
	return DISTRICTS[-1]


# --- Ground, streets, highways, river ----------------------------------------

func _ground() -> void:
	# One solid slab for the whole map; the visible ground is drawn as flats on top
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_X * 2.0, 1.0, HALF_Z * 2.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	root.add_child(body)
	_flat(Rect2(-HALF_X, -HALF_Z, HALF_X * 2.0, HALF_Z * 2.0), Y_GROUND, C_GROUND)
	# The holdout plaza: a parking lot with painted bays
	_flat(PLAZA, Y_LOT, C_ASPHALT)
	for i in range(-5, 6):
		_flat(Rect2(i * 10.0 - 0.12, 14.0, 0.24, 4.0), Y_PAINT, C_LANE)
		_flat(Rect2(-14.0, i * 9.0, 0.24, 4.0), Y_PAINT, C_LANE)
	_flat(Rect2(-9, -9, 18, 18), Y_STREET, C_CONCRETE)


func _streets() -> void:
	# A regular grid; lines run through the gaps between blocks
	var x := -HALF_X + GRID * 0.5
	while x <= HALF_X:
		_street_line(Vector2(x, -HALF_Z), Vector2(x, HALF_Z), true)
		x += GRID
	var z := -HALF_Z + GRID * 0.5
	while z <= HALF_Z:
		_street_line(Vector2(-HALF_X, z), Vector2(HALF_X, z), false)
		z += GRID


func _street_line(a: Vector2, b: Vector2, vertical: bool) -> void:
	# Split into block-length pieces, skipping the plaza, the airport and the water
	var length := a.distance_to(b)
	var steps := int(length / GRID)
	for i in steps:
		var p0 := a.lerp(b, float(i) / steps)
		var p1 := a.lerp(b, float(i + 1) / steps)
		var mid := (p0 + p1) * 0.5
		if PLAZA.grow(4.0).has_point(mid) or AT_T.has_point(mid) or GLOBE_LIFE.has_point(mid):
			continue
		if district_at(mid).type == "airport" or near_river(mid, 2.0):
			continue
		var r := Rect2(p0, Vector2.ZERO).expand(p1).grow_individual(
			STREET * 0.5 if vertical else 0.0, 0.0 if vertical else STREET * 0.5,
			STREET * 0.5 if vertical else 0.0, 0.0 if vertical else STREET * 0.5)
		_flat(r, Y_STREET, C_ASPHALT)
		# Centre line dashes
		var dashes := 6
		for k in dashes:
			var c := p0.lerp(p1, (k + 0.5) / dashes)
			if near_highway(c, 1.0):
				continue
			if vertical:
				_flat(Rect2(c.x - 0.12, c.y - 2.0, 0.24, 4.0), Y_PAINT, C_LANE)
			else:
				_flat(Rect2(c.x - 2.0, c.y - 0.12, 4.0, 0.24), Y_PAINT, C_LANE)


func _highways() -> void:
	for h in HIGHWAYS:
		var pts: Array = h.pts
		var w: float = h.width
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			_strip(a, b, w + 4.0, Y_ROAD_EDGE, C_CONCRETE)  # shoulders
			_strip(a, b, w, Y_HIGHWAY, C_HIGHWAY)
			_strip(a, b, 0.6, Y_PAINT, C_EDGE)              # median line
			# Lane dashes on each side of the median
			var seg := a.distance_to(b)
			var dir := (b - a) / seg
			var side := Vector2(-dir.y, dir.x)
			var n := int(seg / 12.0)
			for k in n:
				var c := a + dir * (k + 0.5) * 12.0
				for off in [-w * 0.25, w * 0.25]:
					_strip(c + side * off - dir * 2.0, c + side * off + dir * 2.0, 0.3, Y_PAINT, C_LANE)


func _river() -> void:
	# Water with muddy banks, plus invisible walls so units can't wade across.
	# Highways cross on bridges: the wall has gaps there.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for i in range(1, RIVER.size()):
		var a: Vector2 = RIVER[i - 1]
		var b: Vector2 = RIVER[i]
		_strip(a, b, RIVER_WIDTH + 6.0, Y_BANK, C_BANK)
		_strip(a, b, RIVER_WIDTH, Y_WATER, C_WATER)
		var seg := a.distance_to(b)
		var steps := int(seg / 6.0) + 1
		for k in steps:
			var p := a.lerp(b, (k + 0.5) / steps)
			if near_highway(p, 4.0):
				continue
			var dir := (b - a).normalized()
			var shape := BoxShape3D.new()
			shape.size = Vector3(seg / steps + 0.5, 3.0, RIVER_WIDTH)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.transform = Transform3D(Basis(Vector3.UP, -dir.angle()), Vector3(p.x, 1.5, p.y))
			body.add_child(col)
			add_solid(p, Vector2(seg / steps + 0.5, RIVER_WIDTH), -dir.angle(), 3.0)
	# Bridge decks where highways cross the water
	for h in HIGHWAYS:
		var hp: Array = h.pts
		for j in range(1, hp.size()):
			for i in range(1, RIVER.size()):
				var c = Geometry2D.segment_intersects_segment(RIVER[i - 1], RIVER[i], hp[j - 1], hp[j])
				if c != null:
					var w: float = h.width + 4.0
					_flat(Rect2((c as Vector2) - Vector2(w, w) * 0.5, Vector2(w, w)), Y_BRIDGE, C_HIGHWAY)


# --- Blocks and buildings -----------------------------------------------------

func _blocks() -> void:
	var bx := -HALF_X + GRID
	while bx < HALF_X:
		var bz := -HALF_Z + GRID
		while bz < HALF_Z:
			_block(Vector2(bx, bz))
			bz += GRID
		bx += GRID


func _block(center: Vector2) -> void:
	var half := (GRID - STREET) * 0.5
	var r := Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)
	if r.intersects(PLAZA) or r.intersects(AT_T.grow(6.0)) or r.intersects(GLOBE_LIFE.grow(6.0)):
		return
	if near_highway(center, half + 2.0) or near_river(center, half + 3.0):
		# Next to a highway or the river: leave it as scrubby open ground with a few trees
		if not near_river(center, half - 6.0) and not near_highway(center, 4.0):
			for k in 3:
				_tree(center + Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
		return
	if Vector2(REUNION - center).length() < 40.0:
		return
	var d := district_at(center)
	match d.type:
		"downtown":
			_flat(r, Y_LOT, C_CONCRETE)
			_downtown_block(r, d.get("tall", Vector2(15, 50)))
		"offices":
			_flat(r, Y_LOT, C_CONCRETE)
			_office_block(r)
		"commercial":
			_flat(r, Y_LOT, C_ASPHALT.lerp(C_CONCRETE, 0.4))
			_commercial_block(r)
		"industrial":
			_flat(r, Y_LOT, Color(0.48, 0.46, 0.40))
			_industrial_block(r)
		"stockyards":
			_flat(r, Y_LOT, Color(0.55, 0.47, 0.35))
			_stockyard_block(r)
		"airport":
			pass   # built as a landmark
		"park":
			_flat(r, Y_LOT, C_GRASS2)
			for k in 10:
				_tree(r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y))
		_:
			if rng.randf() < 0.07:
				_flat(r, Y_LOT, C_GRASS2)   # a neighbourhood park
				for k in 8:
					_tree(r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y))
			else:
				_flat(r, Y_LOT, C_GRASS)
				_residential_block(r)


func _body_for(center: Vector2) -> StaticBody3D:
	var key := Vector2i(floori(center.x / GRID), floori(center.y / GRID))
	if not _block_bodies.has(key):
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		_block_bodies[key] = body
	return _block_bodies[key]


func _building(center: Vector2, size: Vector3, color: Color, style: float, floor_h := 3.5, yaw := 0.0) -> void:
	## A solid building: one visible box (with windows from the shader) and one collision box
	var t := Transform3D(_rot_scale(yaw, size), Vector3(center.x, size.y * 0.5, center.y))
	_boxes.append([t, color, Color(style, floor_h, rng.randf(), 0.0)])
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, size.y * 0.5, center.y))
	_body_for(center).add_child(col)
	add_solid(center, Vector2(size.x, size.z), yaw, size.y)
	building_count += 1
	var ext := Vector2(absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.z, absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.z)
	footprints.append([Rect2(center - ext * 0.5, ext), color])


func _roof_box(center: Vector2, y: float, size: Vector3, color: Color) -> void:
	# Rooftop details (AC units, stair housings): visual only
	_boxes.append([Transform3D(Basis.IDENTITY.scaled(size), Vector3(center.x, y + size.y * 0.5, center.y)), color, Color(0, 3.5, 0, 0)])


func _downtown_block(r: Rect2, tall: Vector2) -> void:
	# 1, 2 or 4 towers per block, with setbacks and rooftop clutter
	var split: int = [1, 2, 2, 4].pick_random() if rng.randf() < 0.9 else 1
	var lots: Array[Rect2] = []
	if split == 1:
		lots.append(r)
	elif split == 2:
		if rng.randf() < 0.5:
			lots.append(Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y)))
			lots.append(Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y)))
		else:
			lots.append(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)))
			lots.append(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5)))
	else:
		for ix in 2:
			for iz in 2:
				lots.append(Rect2(r.position + r.size * Vector2(ix, iz) * 0.5, r.size * 0.5))
	for lot in lots:
		var inset := rng.randf_range(2.0, 5.0)
		var foot := lot.grow(-inset)
		var h := rng.randf_range(tall.x, tall.y) * (1.0 if split < 4 else 0.7)
		var glass := rng.randf() < 0.45
		var col: Color = TOWER_COLORS.pick_random()
		var c := foot.get_center()
		_building(c, Vector3(foot.size.x, h, foot.size.y), col, STYLE_GLASS if glass else STYLE_OFFICE, 3.6)
		# Setback crown on some towers
		if h > 30.0 and rng.randf() < 0.5:
			var crown := Vector3(foot.size.x * 0.6, rng.randf_range(4.0, 10.0), foot.size.y * 0.6)
			_boxes.append([Transform3D(Basis.IDENTITY.scaled(crown), Vector3(c.x, h + crown.y * 0.5, c.y)), col.darkened(0.1), Color(STYLE_GLASS if glass else STYLE_OFFICE, 3.6, rng.randf(), 0)])
		else:
			_roof_box(c + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), h, Vector3(4, 2.5, 4), Color(0.45, 0.45, 0.44))


func _office_block(r: Rect2) -> void:
	var n := rng.randi_range(1, 2)
	for i in n:
		var w := rng.randf_range(18.0, 30.0)
		var dpt := rng.randf_range(14.0, 22.0)
		var c := r.get_center() + Vector2(0.0, (i - (n - 1) * 0.5) * 24.0) + Vector2(rng.randf_range(-6, 6), 0)
		var h := rng.randf_range(10.0, 32.0)
		_building(c, Vector3(w, h, dpt), TOWER_COLORS.pick_random(), STYLE_GLASS if rng.randf() < 0.6 else STYLE_OFFICE, 3.6)
	for k in 4:
		_tree(r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y))


func _commercial_block(r: Rect2) -> void:
	# Strip malls and big boxes set back behind parking
	var w := rng.randf_range(26.0, 44.0)
	var dpt := rng.randf_range(12.0, 20.0)
	var c := r.get_center() + Vector2(rng.randf_range(-4, 4), -r.size.y * 0.5 + dpt * 0.5 + 3.0)
	var col := Color(0.70, 0.64, 0.55).lerp(Color(0.60, 0.62, 0.64), rng.randf())
	_building(c, Vector3(w, rng.randf_range(5.0, 8.0), dpt), col, STYLE_OFFICE, 4.5)
	# Parking bay lines
	for k in 6:
		var x := r.position.x + 6.0 + k * 7.0
		_flat(Rect2(x, r.end.y - 14.0, 0.25, 5.0), Y_PAINT, C_LANE)
	if rng.randf() < 0.5:
		_tree(r.position + Vector2(3, 3))
		_tree(r.end - Vector2(3, 3))


func _industrial_block(r: Rect2) -> void:
	var n := rng.randi_range(1, 2)
	for i in n:
		var w := rng.randf_range(28.0, 44.0)
		var dpt := rng.randf_range(14.0, 20.0)
		var c := r.get_center() + Vector2(rng.randf_range(-3, 3), (i - (n - 1) * 0.5) * 23.0)
		_building(c, Vector3(w, rng.randf_range(7.0, 10.0), dpt), Color(0.62, 0.62, 0.60).lerp(Color(0.55, 0.50, 0.44), rng.randf()), STYLE_PLAIN)
		_roof_box(c, 9.0, Vector3(3, 1.5, 3), Color(0.5, 0.5, 0.5))


func _stockyard_block(r: Rect2) -> void:
	for i in rng.randi_range(2, 4):
		var c := r.position + Vector2(rng.randf_range(10, r.size.x - 10), rng.randf_range(8, r.size.y - 8))
		var size := Vector3(rng.randf_range(10, 16), rng.randf_range(4.0, 6.0), rng.randf_range(8, 12))
		_building(c, size, Color(0.55, 0.36, 0.24), STYLE_PLAIN)
		_prisms.append([Transform3D(Basis.IDENTITY.scaled(Vector3(size.x + 0.6, 2.2, size.z + 0.6)), Vector3(c.x, size.y + 1.1, c.y)), Color(0.40, 0.30, 0.22), Color(0, 0, 0, 0)])


func _residential_block(r: Rect2) -> void:
	# Houses on lots facing the streets, with yards and trees
	var cols := 4
	var rows := 2
	var lot := Vector2(r.size.x / cols, r.size.y / rows)
	for ix in cols:
		for iz in rows:
			var cell := Rect2(r.position + lot * Vector2(ix, iz), lot)
			if rng.randf() < 0.12:
				_tree(cell.get_center())
				continue
			var w := rng.randf_range(7.0, 9.5)
			var dpt := rng.randf_range(7.5, 10.0)
			var h := rng.randf_range(3.2, 4.2) if rng.randf() < 0.8 else rng.randf_range(5.5, 6.5)
			# Front of the house faces the street on its side of the block
			var c := cell.get_center() + Vector2(0, (-1.0 if iz == 0 else 1.0) * (lot.y * 0.5 - dpt * 0.5 - 3.0))
			_building(c, Vector3(w, h, dpt), HOUSE_COLORS.pick_random(), STYLE_HOUSE, 3.0)
			_prisms.append([Transform3D(Basis.IDENTITY.scaled(Vector3(w + 0.8, 1.8, dpt + 0.8)), Vector3(c.x, h + 0.9, c.y)), ROOF_COLORS.pick_random(), Color(0, 0, 0, 0)])
			# Back yard tree
			if rng.randf() < 0.6:
				_tree(cell.get_center() + Vector2(rng.randf_range(-3, 3), (1.0 if iz == 0 else -1.0) * lot.y * 0.25))


# --- Landmarks ----------------------------------------------------------------

func _landmarks() -> void:
	# AT&T Stadium: huge, silver, with a lighter arched roof and glass ends
	var att := AT_T.get_center()
	_flat(AT_T.grow(8.0), Y_LOT, C_ASPHALT)
	_building(att, Vector3(AT_T.size.x - 20.0, 24.0, AT_T.size.y - 20.0), Color(0.78, 0.79, 0.80), STYLE_GLASS, 6.0)
	_boxes.append([Transform3D(Basis.IDENTITY.scaled(Vector3(AT_T.size.x - 50.0, 7.0, AT_T.size.y - 26.0)), Vector3(att.x, 27.5, att.y)), Color(0.88, 0.89, 0.90), Color(0, 4, 0, 0)])
	# Globe Life Field: brick, with a retractable roof
	var glf := GLOBE_LIFE.get_center()
	_flat(GLOBE_LIFE.grow(6.0), Y_LOT, C_ASPHALT)
	_building(glf, Vector3(GLOBE_LIFE.size.x - 12.0, 20.0, GLOBE_LIFE.size.y - 12.0), Color(0.58, 0.36, 0.28), STYLE_OFFICE, 5.0)
	_boxes.append([Transform3D(Basis.IDENTITY.scaled(Vector3(GLOBE_LIFE.size.x - 26.0, 4.0, GLOBE_LIFE.size.y - 26.0)), Vector3(glf.x, 22.0, glf.y)), Color(0.66, 0.68, 0.70), Color(0, 4, 0, 0)])

	# Reunion Tower: a stalk and the lit ball on top
	var rt := REUNION
	_flat(Rect2(rt - Vector2(20, 20), Vector2(40, 40)), Y_LOT, C_CONCRETE)
	_building(rt, Vector3(6.0, 92.0, 6.0), Color(0.72, 0.72, 0.70), STYLE_PLAIN)
	var ball := SphereMesh.new()
	ball.radius = 11.0
	ball.height = 22.0
	ball.radial_segments = 12
	ball.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = ball
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.85, 0.80)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.95, 0.75)
	bm.emission_energy_multiplier = 0.35
	mi.material_override = bm
	mi.position = Vector3(rt.x, 100.0, rt.y)
	root.add_child(mi)

	# Bank of America Plaza: tallest in Dallas, green outline lights
	var boa := Vector2(660, -100)
	_building(boa, Vector3(26, 110, 22), Color(0.36, 0.42, 0.48), STYLE_GLASS, 3.6)
	for corner in [Vector2(-13, -11), Vector2(13, -11), Vector2(-13, 11), Vector2(13, 11)]:
		_boxes.append([Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 110, 0.6)), Vector3(boa.x + corner.x, 55.0, boa.y + corner.y)), Color(0.3, 1.0, 0.45), Color(0, 0, 0, 1)])

	# DFW Airport: two runways, a curved terminal row and a control tower
	var ap: Rect2 = DISTRICTS[2].rect
	_flat(ap, Y_LOT, Color(0.46, 0.50, 0.38))
	for z in [ap.position.y + 25.0, ap.position.y + 120.0]:
		_flat(Rect2(ap.position.x + 10, z - 8, ap.size.x - 20, 16), Y_STREET, C_HIGHWAY)
		var x := ap.position.x + 20.0
		while x < ap.end.x - 20.0:
			_flat(Rect2(x, z - 0.3, 8, 0.6), Y_PAINT, C_EDGE)
			x += 18.0
	for i in 5:
		var tc := Vector2(ap.position.x + 45.0 + i * 52.0, ap.position.y + 72.0 + (absf(i - 2.0) * 6.0))
		_building(tc, Vector3(36, 9, 22), Color(0.80, 0.80, 0.78), STYLE_GLASS, 4.5)
	var tower := Vector2(ap.get_center().x, ap.position.y + 95.0)
	_building(tower, Vector3(6, 34, 6), Color(0.80, 0.80, 0.78), STYLE_PLAIN)
	_boxes.append([Transform3D(Basis.IDENTITY.scaled(Vector3(10, 5, 10)), Vector3(tower.x, 36.5, tower.y)), Color(0.30, 0.40, 0.46), Color(STYLE_GLASS, 2.5, 0.8, 0)])


# --- Trees and cars -----------------------------------------------------------

func _tree(p: Vector2) -> void:
	var h := rng.randf_range(2.0, 3.0)
	var s := rng.randf_range(2.6, 4.2)
	if RedFob.ZONE.grow(4.0).has_point(p):
		rng.randf()      # (keep the random sequence, so the rest of the city doesn't change)
		return
	_boxes.append([Transform3D(Basis.IDENTITY.scaled(Vector3(0.45, h, 0.45)), Vector3(p.x, h * 0.5, p.y)), C_TRUNK, Color(0, 0, 0, 0)])
	_boxes.append([Transform3D(_rot_scale(rng.randf() * TAU, Vector3(s, s * 0.8, s)), Vector3(p.x, h + s * 0.35, p.y)), C_LEAF.pick_random(), Color(0, 0, 0, 0)])


func _cars() -> void:
	# Abandoned cars: thicker on the highways (everyone tried to leave at once)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for h in HIGHWAYS:
		var pts: Array = h.pts
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var seg := a.distance_to(b)
			var dir := (b - a) / seg
			var side := Vector2(-dir.y, dir.x)
			var t := rng.randf_range(5.0, 20.0)
			while t < seg:
				var lane: float = [-0.35, -0.15, 0.15, 0.35].pick_random() * (h.width as float)
				var p: Vector2 = a + dir * t + side * lane
				if not PLAZA.grow(10).has_point(p) and not near_river(p, 0.0):
					_car(p, dir.angle() + rng.randf_range(-0.4, 0.4), body)
				t += rng.randf_range(10.0, 34.0)
	# A few on the side streets
	for k in 220:
		var gx := (rng.randi_range(-14, 14)) * GRID + GRID * 0.5
		var z := rng.randf_range(-HALF_Z + 10, HALF_Z - 10)
		var p := Vector2(gx + rng.randf_range(-2.5, 2.5), z)
		if rng.randf() < 0.5:
			p = Vector2(z * 2.0, (rng.randi_range(-7, 7)) * GRID + GRID * 0.5 + rng.randf_range(-2.5, 2.5))
		if absf(p.x) > HALF_X - 5 or absf(p.y) > HALF_Z - 5:
			continue
		if PLAZA.grow(10).has_point(p) or near_river(p, 2.0) or district_at(p).type == "airport":
			continue
		var along := PI * 0.5 if absf(fmod(absf(p.x) - GRID * 0.5, GRID)) < 6.0 else 0.0
		_car(p, along + rng.randf_range(-0.3, 0.3), body)


func _car(p: Vector2, yaw: float, body: StaticBody3D) -> void:
	if RedFob.ZONE.grow(4.0).has_point(p):
		return      # the Red Army cleared its base
	var col: Color = CAR_COLORS.pick_random()
	var basis := Basis(Vector3.UP, -yaw)
	_boxes.append([Transform3D(_rot_scale(-yaw, Vector3(4.2, 0.9, 1.9)), Vector3(p.x, 0.55, p.y)), col, Color(0, 0, 0, 0)])
	_boxes.append([Transform3D(_rot_scale(-yaw, Vector3(2.2, 0.6, 1.7)), Vector3(p.x, 1.3, p.y) + basis * Vector3(-0.2, 0, 0)), col.darkened(0.25), Color(0, 0, 0, 0)])
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.2, 1.5, 1.9)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, Vector3(p.x, 0.75, p.y))
	body.add_child(cs)
	add_solid(p, Vector2(4.2, 1.9), -yaw, 1.5)


func add_solid(center: Vector2, size: Vector2, yaw: float, height: float) -> void:
	## Remember a solid box footprint. Recast (the navmesh baker) only sees surfaces, so it
	## treats the floor inside a closed box as a walkable room; these footprints are carved
	## out of the navmesh so nothing can be placed or path inside a building.
	var b := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var pts := PackedVector3Array()
	for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		pts.append(b * c + Vector3(center.x, 0.0, center.y))
	solids.append([pts, height])


# --- Labels -------------------------------------------------------------------

func _labels() -> void:
	var places := [
		["FORT WORTH", Vector2(-650, -125), 80.0], ["DALLAS", Vector2(700, -70), 120.0],
		["ARLINGTON", Vector2(40, 120), 40.0], ["DFW AIRPORT", Vector2(90, -380), 30.0],
		["IRVING", Vector2(390, -210), 50.0], ["STOCKYARDS", Vector2(-645, -345), 20.0],
		["GRAND PRAIRIE", Vector2(330, 160), 30.0], ["AT&T STADIUM", Vector2(-120, 115), 45.0],
		["GLOBE LIFE FIELD", Vector2(-120, -35), 40.0], ["REUNION TOWER", Vector2(565, -5), 125.0],
		["FAIR PARK", Vector2(820, 115), 20.0], ["TRINITY RIVER", Vector2(-300, -170), 10.0],
	]
	for pl in places:
		labels.append(_label(pl[0], Vector3(pl[1].x, pl[2], pl[1].y), 1.0))
	for h in HIGHWAYS:
		var pts: Array = h.pts
		var mid: Vector2 = (pts[0] as Vector2).lerp(pts[1], 0.35)
		labels.append(_label(h.name, Vector3(mid.x, 8.0, mid.y), 0.6))


func _label(text: String, at: Vector3, scale: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.25 * scale
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.modulate = Color(1, 1, 1, 0.92)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = at
	l.visible = false
	root.add_child(l)
	return l


# --- Drawing helpers ----------------------------------------------------------

static func _rot_scale(yaw: float, size: Vector3) -> Basis:
	## Turn around Y, with the size applied along the object's own axes
	return Basis(Vector3.UP, yaw) * Basis.from_scale(size)


func _flat(r: Rect2, y: float, color: Color) -> void:
	var c := r.get_center()
	var into := _paint if y == Y_PAINT else _flats
	into.append([Transform3D(Basis.IDENTITY.scaled(Vector3(r.size.x, 0.02, r.size.y)), Vector3(c.x, y, c.y)), color, Color(0, 0, 0, 0)])


func _strip(a: Vector2, b: Vector2, width: float, y: float, color: Color) -> void:
	var c := (a + b) * 0.5
	var length := a.distance_to(b) + width * 0.5
	var basis := _rot_scale(-(b - a).angle(), Vector3(length, 0.02, width))
	var into := _paint if y == Y_PAINT else _flats
	into.append([Transform3D(basis, Vector3(c.x, y, c.y)), color, Color(0, 0, 0, 0)])


func _flush() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var prism := PrismMesh.new()
	prism.size = Vector3.ONE
	_add_multimesh(cube, _boxes, true)
	_add_multimesh(cube, _flats, false)
	paint_layer = _add_multimesh(cube, _paint, false)
	_add_multimesh(prism, _prisms, true)


func _add_multimesh(mesh: Mesh, items: Array, shadows: bool) -> MultiMeshInstance3D:
	if items.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
		mm.set_instance_custom_data(i, items[i][2])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


static func _make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Windows are drawn from world position, so any box size gets a sensible facade.
// detail = 0 hides them when zoomed far out (they'd just shimmer).
uniform float detail = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cust;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cust = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 col = base;
	float style = cust.r;
	float emit = cust.a;
	if (wnrm.y > 0.6) {
		col = base * 0.86;   // roofs a little darker
	} else if (abs(wnrm.y) < 0.4 && style > 0.5 && detail > 0.5) {
		vec2 t = normalize(vec2(-wnrm.z, wnrm.x));
		float u = dot(wpos.xz, t);
		float v = wpos.y;
		float fh = max(cust.g, 2.5);
		if (style < 1.5) {
			// Office: punched windows on every floor
			float wu = fract(u / 2.6);
			float wv = fract(v / fh);
			if (wu > 0.2 && wu < 0.75 && wv > 0.32 && wv < 0.8 && v > 1.2) {
				col = mix(vec3(0.18, 0.23, 0.29), vec3(0.42, 0.50, 0.56), step(0.7, fract(cust.b * 7.0 + floor(u / 2.6) * 0.37 + floor(v / fh) * 0.61)));
			}
		} else if (style < 2.5) {
			// House: a couple of windows per wall
			float wu = fract(u / 4.2);
			if (wu > 0.3 && wu < 0.62 && v > 1.1 && v < 2.4) {
				col = vec3(0.20, 0.24, 0.28);
			}
		} else {
			// Glass curtain wall: tinted panes with mullions and floor lines
			float wu = fract(u / 1.8);
			float wv = fract(v / fh);
			col = base * (0.95 + 0.25 * step(0.5, cust.b));
			if (wu < 0.1 || wv < 0.12) {
				col = base * 0.55;
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = col * emit * 1.5;
}
"""
	return sh


# --- The real map (OpenStreetMap, see OsmImport) ------------------------------------------------

const HOUSE_KINDS := ["house", "detached", "semidetached_house", "terrace", "bungalow", "residential", "farm", "garage", "garages", "shed"]
const MAX_CARS := 350
const PARK_TREE_AREA := 650.0      # one tree per this many square metres of park


func _cleared(p: Vector2, margin: float) -> bool:
	## Ground the game keeps for itself: the plaza at the centre and the Red FOB's land
	return PLAZA.grow(margin).has_point(p) or RedFob.ZONE.grow(margin).has_point(p)


func _build_real(m: OsmImport) -> void:
	_ground()
	for pk in m.parks:
		_polys.append([pk.poly, Y_LOT, C_GRASS2 if pk.kind != "forest" and pk.kind != "wood" else C_GRASS.darkened(0.15)])
	for lot in m.lots:
		_polys.append([lot, Y_LOT, C_ASPHALT.lerp(C_CONCRETE, 0.25)])
	# Roads: small ones first, highways on top
	var sorted := m.roads.duplicate()
	sorted.sort_custom(func(a, b): return a.width < b.width)
	for r in sorted:
		_real_road(r)
	for rail in m.rails:
		for i in range(1, rail.size()):
			_strip(rail[i - 1], rail[i], 2.6, Y_ROAD_EDGE, Color(0.36, 0.33, 0.30))
			_strip(rail[i - 1], rail[i], 0.25, Y_PAINT, Color(0.55, 0.55, 0.55))
	_real_water(m)
	for b in m.buildings:
		_real_building(b)
	for t in m.trees:
		if not _cleared(t, 2.0) and not _in_water(t):
			_tree(t)
	for pk in m.parks:
		if pk.kind in ["pitch", "golf_course", "cemetery"]:
			continue
		var poly: PackedVector2Array = pk.poly
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		var n := mini(int(absf(OsmImport._signed_area(poly)) / PARK_TREE_AREA), 60)
		for k in n:
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			if Geometry2D.is_point_in_polygon(p, poly) and not _cleared(p, 2.0) and not _in_water(p):
				_tree(p)
	_real_cars(m)
	for pl in m.places:
		if not _cleared(pl.pos, 0.0):
			labels.append(_label(String(pl.name).to_upper(), Vector3(pl.pos.x, pl.size, pl.pos.y), 0.7))
	# One label per named motorway / trunk road
	var named := {}
	for r in m.roads:
		if r.kind in ["motorway", "trunk"] and r.name != "" and not named.has(r.name):
			var pts: PackedVector2Array = r.pts
			if pts.size() >= 2:
				named[r.name] = true
				var mid := pts[pts.size() / 2]
				labels.append(_label(r.name, Vector3(mid.x, 8.0, mid.y), 0.6))


func _real_road(r: Dictionary) -> void:
	var pts: PackedVector2Array = r.pts
	var w: float = r.width
	var big: bool = r.kind in ["motorway", "trunk", "motorway_link", "trunk_link"]
	var y := Y_BRIDGE if r.bridge else (Y_HIGHWAY if big else Y_STREET)
	var color := C_HIGHWAY if big else (C_ASPHALT if w >= 7.0 else C_ASPHALT.lerp(C_CONCRETE, 0.3))
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		if a.distance_to(b) < 0.05:
			continue
		if big:
			_strip(a, b, w + 3.0, Y_ROAD_EDGE, C_CONCRETE)
		_strip(a, b, w, y, color)
		# Round off the joint with the next piece
		if i < pts.size() - 1:
			_strip(b - (b - a).normalized() * 0.01, b + (b - a).normalized() * 0.01, w, y, color)
		# Centre-line dashes on the bigger roads
		if w >= 11.0:
			var seg := a.distance_to(b)
			var dir := (b - a) / seg
			var n := int(seg / 12.0)
			for k in n:
				var c := a + dir * (k + 0.5) * 12.0
				_strip(c - dir * 2.0, c + dir * 2.0, 0.3, Y_PAINT, C_LANE)


func _in_water(p: Vector2) -> bool:
	if real_map == null:
		return false
	for wp in real_map.water:
		if Geometry2D.is_point_in_polygon(p, wp):
			return true
	for ww in real_map.waterways:
		if ww.river and dist_to_polyline(p, Array(ww.pts)) < ww.width * 0.5:
			return true
	return false


func _real_water(m: OsmImport) -> void:
	## Water: drawn, and cut out of the navigation map (except where a bridge crosses it)
	var bridges: Array = []      # strips under bridge roads, as polygons
	for r in m.roads:
		if not r.bridge:
			continue
		var pts: PackedVector2Array = r.pts
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var d := b - a
			if d.length() < 0.05:
				continue
			var u := d.normalized()
			var v: Vector2 = Vector2(-u.y, u.x) * (float(r.width) * 0.5 + 2.0)
			var e := u * 3.0
			bridges.append(PackedVector2Array([a - e + v, b + e + v, b + e - v, a - e - v]))
	for wp in m.water:
		_polys.append([wp, Y_WATER, C_WATER])
		var pieces: Array = [wp]
		var cw := Geometry2D.is_polygon_clockwise(wp)
		for br in bridges:
			var next: Array = []
			for pc in pieces:
				for out in Geometry2D.clip_polygons(pc, br):
					if Geometry2D.is_polygon_clockwise(out) == cw:     # (holes come back the other way round)
						next.append(out)
			pieces = next
		for pc in pieces:
			var corners := PackedVector3Array()
			for q in pc:
				corners.append(Vector3(q.x, 0.0, q.y))
			solids.append([corners, 3.0])
	for ww in m.waterways:
		var pts: PackedVector2Array = ww.pts
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			if a.distance_to(b) < 0.05:
				continue
			if ww.river:
				_strip(a, b, ww.width + 6.0, Y_BANK, C_BANK)
			_strip(a, b, ww.width, Y_WATER, C_WATER)
			if not ww.river:
				continue
			# Rivers can't be waded: cut out of the map in short pieces, skipping bridges
			var seg := a.distance_to(b)
			var steps := int(seg / 6.0) + 1
			for k in steps:
				var p := a.lerp(b, (k + 0.5) / steps)
				var on_bridge := false
				for br in bridges:
					if Geometry2D.is_point_in_polygon(p, br):
						on_bridge = true
						break
				if not on_bridge:
					add_solid(p, Vector2(seg / steps + 0.5, ww.width), -(b - a).angle(), 3.0)


func _place_red_fob(m: OsmImport) -> void:
	## On a real map the Red FOB needs open ground: try spots along the east edge and take the
	## one with the least building and water in the area it can grow into
	var base_zone := RedFob.ZONE
	var best := Vector2.ZERO
	var best_score := INF
	var boxes: Array = []
	for b in m.buildings:
		var r := Rect2(b.poly[0], Vector2.ZERO)
		for q in b.poly:
			r = r.expand(q)
		boxes.append(r)
	var z_room := HALF_Z - base_zone.size.y * 0.5 - 30.0
	for dx in [0.0, -40.0, -80.0, -120.0, -160.0]:
		var dz := -z_room
		while dz <= z_room:
			# (dz is measured from the generated city's spot, z 76..196)
			var off := Vector2(dx, dz - base_zone.get_center().y)
			var zone := Rect2(base_zone.position + off, base_zone.size).grow(6.0)
			var score := 0.0
			for r in boxes:
				if r.intersects(zone):
					score += r.intersection(zone).get_area()
			var wet := 0
			for i in 6:
				for j in 4:
					if _in_water(zone.position + zone.size * Vector2((i + 0.5) / 6.0, (j + 0.5) / 4.0)):
						wet += 1
			score += wet * 4000.0
			score += absf(dz) * 0.5 + absf(dx) * 2.0     # all else equal: near the middle, at the edge
			if score < best_score:
				best_score = score
				best = off
			dz += 40.0
	RedFob.anchor(HALF_X, best)
	print("Red FOB placed at %s (score %.0f)" % [RedFob.RECT, best_score])


func _real_building(b: Dictionary) -> void:
	var poly: PackedVector2Array = b.poly
	var c := Vector2.ZERO
	var bb := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		c += q
		bb = bb.expand(q)
	c /= poly.size()
	if _cleared(c, 6.0) or bb.intersects(RedFob.ZONE.grow(6.0)):
		return
	var kind: String = b.kind
	var h: float = b.height
	var area := absf(OsmImport._signed_area(poly))
	var house := kind in HOUSE_KINDS and area < 400.0 and h < 8.0
	var color: Color
	var style := STYLE_PLAIN
	var floor_h := 3.5
	if house:
		color = HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()]
		style = STYLE_HOUSE
		floor_h = 3.0
	elif kind in ["office", "hotel", "hospital"] or h > 20.0:
		color = TOWER_COLORS[rng.randi() % TOWER_COLORS.size()]
		style = STYLE_GLASS if rng.randf() < 0.5 else STYLE_OFFICE
		floor_h = 3.6
	elif kind in ["industrial", "warehouse", "manufacture"]:
		color = Color(0.62, 0.62, 0.60).lerp(Color(0.55, 0.50, 0.44), rng.randf())
	elif kind in ["stadium", "grandstand"]:
		color = Color(0.80, 0.80, 0.80)
		style = STYLE_GLASS
		floor_h = 6.0
	elif kind in ["apartments", "dormitory"]:
		color = HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()].darkened(0.1)
		style = STYLE_OFFICE
		floor_h = 3.2
	else:
		color = Color(0.70, 0.64, 0.55).lerp(Color(0.60, 0.62, 0.64), rng.randf())
		style = STYLE_OFFICE if h > 5.0 else STYLE_PLAIN
		floor_h = 4.5
	for box in OsmImport.boxes_for(poly):
		var size: Vector2 = box.size
		if size.x < 1.5 or size.y < 1.5:
			continue
		var yaw := -float(box.angle)
		var bc: Vector2 = box.center
		_building(bc, Vector3(size.x, h, size.y), color, style, floor_h, yaw)
		if house:
			_prisms.append([Transform3D(_rot_scale(yaw, Vector3(size.x + 0.8, 1.8, size.y + 0.8)), Vector3(bc.x, h + 0.9, bc.y)), ROOF_COLORS[rng.randi() % ROOF_COLORS.size()], Color(0, 0, 0, 0)])


func _real_cars(m: OsmImport) -> void:
	## Abandoned cars along the streets
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var placed := 0
	for r in m.roads:
		if placed >= MAX_CARS:
			break
		if not (r.kind in ["residential", "primary", "secondary", "tertiary", "service", "motorway", "trunk", "unclassified"]) or r.bridge:
			continue
		var pts: PackedVector2Array = r.pts
		for i in range(1, pts.size()):
			if rng.randf() > (0.35 if r.kind in ["motorway", "trunk"] else 0.12):
				continue
			var a := pts[i - 1]
			var b := pts[i]
			if a.distance_to(b) < 8.0:
				continue
			var d := (b - a).normalized()
			var side: Vector2 = Vector2(-d.y, d.x) * rng.randf_range(-0.3, 0.3) * float(r.width)
			var p := a.lerp(b, rng.randf_range(0.2, 0.8)) + side
			if _cleared(p, 4.0) or _in_water(p):
				continue
			_car(p, d.angle() + rng.randf_range(-0.3, 0.3), body)
			placed += 1


func _flush_polys() -> void:
	## Ground shapes from the real map (parks, lots, water) as one mesh with vertex colours
	if _polys.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item in _polys:
		var poly: PackedVector2Array = item[0]
		var y: float = item[1]
		var col: Color = item[2]
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			continue
		for i in idx:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(poly[i].x, y + 0.005, poly[i].y))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
