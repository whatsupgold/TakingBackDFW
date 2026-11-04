class_name ShipModels
extends RefCounted
## The fleet at real size, in detail: a Ford-class carrier (CVN-78), a Wasp-class amphibious
## assault ship (LHD-3 Kearsarge) with its well deck, Arleigh Burke destroyers (DDG-57 Mitscher,
## DDG-58 Laboon), a Ticonderoga cruiser (CG-60 Normandy) and the LCAC hovercraft.
## Bow towards -Z, starboard +X, the waterline at y = 0, metres.
##
## Each ship is one mesh for the hull and everything fixed (shared between copies), plus its
## weapons and radars as separate parts that turn: the 5-inch guns, Phalanx CIWS, RAM and Sea
## Sparrow launchers, rotating radars, and the stern gate of the well deck. The model's root
## carries where they are as meta, for the naval effects (TexasNavalFx):
##   "guns", "ciws", "ram", "essm": the mounts' turning nodes (each has a "Pitch" child, which
##       has a "Muzzle" marker at the business end)
##   "vls": PackedVector3Array, the top of every Mk 41 launch cell
##   "radars": nodes that spin;  "gate": the stern gate's hinge (amphib);  "well": the well deck
##   mouth (amphib)

const HULL := Color(0.47, 0.50, 0.53)
const HULL_DARK := Color(0.40, 0.43, 0.46)
const SUPER := Color(0.57, 0.60, 0.63)
const SUPER_DARK := Color(0.50, 0.53, 0.56)
const DECK := Color(0.26, 0.27, 0.29)
const DECK_SHIP := Color(0.33, 0.35, 0.36)      # the non-skid of the escorts' weather decks
const BOOT := Color(0.08, 0.08, 0.09)
const WHITE := Color(0.90, 0.90, 0.88)
const YELLOW := Color(0.88, 0.74, 0.20)
const RED := Color(0.70, 0.16, 0.12)
const GLASS := Color(0.10, 0.16, 0.22)
const SPY := Color(0.42, 0.45, 0.48)
const HATCH := Color(0.30, 0.32, 0.34)
const DARK := Color(0.13, 0.14, 0.15)
const MOUNT := Color(0.60, 0.63, 0.66)
const RADOME := Color(0.92, 0.92, 0.90)
const STACK_TOP := Color(0.10, 0.10, 0.10)

static var _cache := {}
static var _mat: StandardMaterial3D


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.75
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


# --- Drawing helpers ----------------------------------------------------------------------------

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := -(b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	## A quad facing towards `out`, whichever way its corners go round
	if (-(b - a).cross(c - a)).dot(out) < 0.0:
		_quad(st, a, d, c, b, col)
	else:
		_quad(st, a, b, c, d, col)


static func _flat(st: SurfaceTool, c: Vector3, sx: float, sz: float, col: Color, ang := 0.0) -> void:
	## A flat marking on a deck (facing up), turned by `ang` about Y
	var ax := Vector3(cos(ang), 0, -sin(ang)) * sx * 0.5
	var az := Vector3(sin(ang), 0, cos(ang)) * sz * 0.5
	_quad_out(st, c - ax - az, c + ax - az, c + ax + az, c - ax + az, col, Vector3.UP)


static func _prism(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, side_col: Color, top_col: Color) -> void:
	## A solid from an outline (x, z) between two heights: walls and a top
	var n := poly.size()
	var area := 0.0
	for k in n:
		area += poly[k].x * poly[(k + 1) % n].y - poly[(k + 1) % n].x * poly[k].y
	var cx := Vector2.ZERO
	for p in poly:
		cx += p
	cx /= n
	for k in n:
		var p := poly[k]
		var q := poly[(k + 1) % n]
		var mid := (p + q) * 0.5
		var out := Vector3(mid.x - cx.x, 0, mid.y - cx.y)
		var e := q - p
		var nrm := Vector3(e.y, 0, -e.x) * (1.0 if area > 0.0 else -1.0)
		if nrm.dot(out) < 0.0:
			nrm = -nrm
		_quad_out(st, Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y), side_col, nrm)
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		var va := Vector3(a.x, y1, a.y)
		var vb := Vector3(b.x, y1, b.y)
		var vc := Vector3(c.x, y1, c.y)
		if -(vb - va).cross(vc - va).y < 0.0:
			_tri(st, va, vc, vb, top_col)
		else:
			_tri(st, va, vb, vc, top_col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, top := Color(0, 0, 0, 0)) -> void:
	var h := s * 0.5
	var poly := PackedVector2Array([Vector2(c.x - h.x, c.z - h.z), Vector2(c.x + h.x, c.z - h.z),
		Vector2(c.x + h.x, c.z + h.z), Vector2(c.x - h.x, c.z + h.z)])
	_prism(st, poly, c.y - h.y, c.y + h.y, col, col if top.a == 0.0 else top)


static func _taper(st: SurfaceTool, c: Vector3, bottom: Vector2, top: Vector2, h: float, col: Color, top_col := Color(0, 0, 0, 0)) -> void:
	## A block narrower at the top (sloped sides, like a modern deckhouse): sizes are (x, z)
	var b0 := [Vector3(c.x - bottom.x * 0.5, c.y, c.z - bottom.y * 0.5), Vector3(c.x + bottom.x * 0.5, c.y, c.z - bottom.y * 0.5),
		Vector3(c.x + bottom.x * 0.5, c.y, c.z + bottom.y * 0.5), Vector3(c.x - bottom.x * 0.5, c.y, c.z + bottom.y * 0.5)]
	var t0 := [Vector3(c.x - top.x * 0.5, c.y + h, c.z - top.y * 0.5), Vector3(c.x + top.x * 0.5, c.y + h, c.z - top.y * 0.5),
		Vector3(c.x + top.x * 0.5, c.y + h, c.z + top.y * 0.5), Vector3(c.x - top.x * 0.5, c.y + h, c.z + top.y * 0.5)]
	var centre := c + Vector3(0, h * 0.5, 0)
	for k in 4:
		var a: Vector3 = b0[k]
		var b: Vector3 = b0[(k + 1) % 4]
		var tb: Vector3 = t0[(k + 1) % 4]
		var ta: Vector3 = t0[k]
		_quad_out(st, a, b, tb, ta, col, ((a + b) * 0.5 - centre) * Vector3(1, 0, 1))
	_quad_out(st, t0[0], t0[1], t0[2], t0[3], col if top_col.a == 0.0 else top_col, Vector3.UP)


static func _cyl(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, sides := 12, top_col := Color(0, 0, 0, 0)) -> void:
	var poly := PackedVector2Array()
	for k in sides:
		var a := TAU * k / sides
		poly.append(Vector2(c.x + cos(a) * r, c.z + sin(a) * r))
	_prism(st, poly, c.y, c.y + h, col, col if top_col.a == 0.0 else top_col)


static func _cone(st: SurfaceTool, base: Vector3, r: float, h: float, col: Color, sides := 12) -> void:
	var tip := base + Vector3(0, h, 0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var q := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var out := ((p + q) * 0.5 - base)
		if (-(q - p).cross(tip - p)).dot(out) < 0.0:
			_tri(st, p, tip, q, col)
		else:
			_tri(st, p, q, tip, col)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, sides := 8) -> void:
	## A round bar from a to b (masts, barrels, booms)
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := d.cross(u).normalized()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var o0 := (u * cos(a0) + v * sin(a0)) * r
		var o1 := (u * cos(a1) + v * sin(a1)) * r
		_quad_out(st, a + o0, a + o1, b + o1, b + o0, col, (o0 + o1))
	# end caps
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		_tri(st, b, b + (u * cos(a0) + v * sin(a0)) * r, b + (u * cos(a1) + v * sin(a1)) * r, col)
		_tri(st, a, a + (u * cos(a1) + v * sin(a1)) * r, a + (u * cos(a0) + v * sin(a0)) * r, col)


static func _panel(st: SurfaceTool, c: Vector3, w: float, h: float, facing: Vector3, col: Color, octagon := false) -> void:
	## A flat panel standing on a wall, facing out (radar faces, windows, doors, numbers)
	var f := facing.normalized()
	var right := Vector3.UP.cross(f).normalized() * w * 0.5
	var up := f.cross(right).normalized() * h * 0.5
	var p := c + f * 0.08
	if octagon:
		var pts: Array = []
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			pts.append(p + right * cos(a) * 1.08 + up * sin(a) * 1.08)
		for k in 8:
			if (-(pts[k] - p).cross(pts[(k + 1) % 8] - p)).dot(f) < 0.0:
				_tri(st, p, pts[(k + 1) % 8], pts[k], col)
			else:
				_tri(st, p, pts[k], pts[(k + 1) % 8], col)
		return
	_quad_out(st, p - right - up, p + right - up, p + right + up, p - right + up, col, f)


const _SEG := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
	"7": "abc", "8": "abcdefg", "9": "abcfgd"}


static func _digits(st: SurfaceTool, text: String, c: Vector3, right: Vector3, up: Vector3, h: float, col: Color, facing: Vector3) -> void:
	## Painted numbers (hull numbers, the carrier's deck number): seven-segment shapes
	var w := h * 0.55
	var t := h * 0.13
	var r := right.normalized()
	var u := up.normalized()
	var start := c - r * (text.length() * (w + t * 2.0)) * 0.5
	for k in text.length():
		var o := start + r * (k * (w + t * 2.0) + w * 0.5)
		var segs: String = _SEG.get(text[k], "")
		for s in segs:
			var a: Vector3
			var b: Vector3
			match s:
				"a": a = o + u * h * 0.5 - r * w * 0.5; b = o + u * h * 0.5 + r * w * 0.5
				"b": a = o + r * w * 0.5 + u * h * 0.5; b = o + r * w * 0.5
				"c": a = o + r * w * 0.5; b = o + r * w * 0.5 - u * h * 0.5
				"d": a = o - u * h * 0.5 - r * w * 0.5; b = o - u * h * 0.5 + r * w * 0.5
				"e": a = o - r * w * 0.5; b = o - r * w * 0.5 - u * h * 0.5
				"f": a = o - r * w * 0.5 + u * h * 0.5; b = o - r * w * 0.5
				"g": a = o - r * w * 0.5; b = o + r * w * 0.5
			var along := (b - a).normalized()
			var across := facing.normalized().cross(along).normalized() * t * 0.5
			var ext := along * t * 0.5
			_quad_out(st, a - ext - across, b + ext - across, b + ext + across, a - ext + across, col, facing)


static func _loft(st: SurfaceTool, stations: Array, side_col: Color, deck_col: Color, transom := true) -> void:
	## A hull from cross-sections bow to stern: [z, half-beam at the waterline, half-beam at the
	## deck edge, deck height]. Sides flare from the waterline up to the deck edge; the boot
	## topping is the black band along the waterline. A pointed bow has a half-beam of 0.
	for k in stations.size() - 1:
		var s0: Array = stations[k]
		var s1: Array = stations[k + 1]
		for sx in [-1.0, 1.0]:
			var w0 := Vector3(sx * s0[1], 0.0, s0[0])
			var w1 := Vector3(sx * s1[1], 0.0, s1[0])
			var b0 := Vector3(sx * lerpf(s0[1], s0[2], 1.4 / s0[3]), 1.4, s0[0])
			var b1 := Vector3(sx * lerpf(s1[1], s1[2], 1.4 / s1[3]), 1.4, s1[0])
			var d0 := Vector3(sx * s0[2], s0[3], s0[0])
			var d1 := Vector3(sx * s1[2], s1[3], s1[0])
			var out := Vector3(sx, 0, 0)
			_quad_out(st, Vector3(w0.x, -1.0, w0.z), Vector3(w1.x, -1.0, w1.z), b1, b0, BOOT, out)
			_quad_out(st, b0, b1, d1, d0, side_col, out)
		# deck
		var p0 := Vector3(-s0[2], s0[3], s0[0])
		var q0 := Vector3(s0[2], s0[3], s0[0])
		var p1 := Vector3(-s1[2], s1[3], s1[0])
		var q1 := Vector3(s1[2], s1[3], s1[0])
		_quad_out(st, p0, q0, q1, p1, deck_col, Vector3.UP)
	if transom:
		var s: Array = stations[stations.size() - 1]
		_quad_out(st, Vector3(-s[1], -1.0, s[0]), Vector3(s[1], -1.0, s[0]), Vector3(s[2], s[3], s[0]), Vector3(-s[2], s[3], s[0]), side_col, Vector3(0, 0, 1))


static func _rails(st: SurfaceTool, stations: Array, col: Color) -> void:
	## Thin lifelines along the deck edges
	for k in stations.size() - 1:
		var s0: Array = stations[k]
		var s1: Array = stations[k + 1]
		for sx in [-1.0, 1.0]:
			var a := Vector3(sx * s0[2], s0[3] + 1.0, s0[0])
			var b := Vector3(sx * s1[2], s1[3] + 1.0, s1[0])
			_quad_out(st, a, b, b + Vector3(0, 0.08, 0), a + Vector3(0, 0.08, 0), col, Vector3(sx, 0, 0))


static func _start() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _mesh_node(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material()
	return mi


static func _cached(key: String, build: Callable) -> Mesh:
	if not _cache.has(key):
		var st := _start()
		build.call(st)
		_cache[key] = st.commit()
	return _cache[key]


# --- Weapons and radars that turn ---------------------------------------------------------------
# Each mount is a node that turns (yaw) with a "Pitch" node that elevates and, on the pitch node,
# a "Muzzle" marker where rounds and missiles leave. Facing -Z when trained fore and aft.

static func _mount(root: Node3D, kind: String, at: Vector3, facing := 0.0) -> Node3D:
	var yaw := Node3D.new()
	yaw.name = "%s%d" % [kind, root.get_child_count()]
	yaw.position = at
	yaw.rotation.y = facing
	yaw.set_meta("rest", facing)
	root.add_child(yaw)
	var pitch := Node3D.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	pitch.add_child(muzzle)
	match kind:
		"gun":
			yaw.add_child(_mesh_node(_cached("mk45_turret", _b_mk45_turret)))
			pitch.position = Vector3(0, 1.9, -2.0)
			var barrel := MeshInstance3D.new()
			barrel.name = "Barrel"
			barrel.mesh = _cached("mk45_barrel", _b_mk45_barrel)
			barrel.material_override = _material()
			pitch.add_child(barrel)
			muzzle.position = Vector3(0, 0, -8.1)
		"ciws":
			yaw.add_child(_mesh_node(_cached("ciws_mount", _b_ciws_mount)))
			pitch.position = Vector3(0, 1.75, -0.6)
			var gun := MeshInstance3D.new()
			gun.mesh = _cached("ciws_gun", _b_ciws_gun)
			gun.material_override = _material()
			pitch.add_child(gun)
			muzzle.position = Vector3(0, 0, -2.3)
		"ram":
			yaw.add_child(_mesh_node(_cached("ram_base", _b_ram_base)))
			pitch.position = Vector3(0, 2.6, 0)
			var box := MeshInstance3D.new()
			box.mesh = _cached("ram_box", _b_ram_box)
			box.material_override = _material()
			pitch.add_child(box)
			muzzle.position = Vector3(0, 0, -2.3)
		"essm":
			yaw.add_child(_mesh_node(_cached("essm_base", _b_essm_base)))
			pitch.position = Vector3(0, 2.8, 0)
			var box := MeshInstance3D.new()
			box.mesh = _cached("essm_box", _b_essm_box)
			box.material_override = _material()
			pitch.add_child(box)
			muzzle.position = Vector3(0, 0, -2.0)
	return yaw


static func _radar(root: Node3D, kind: String, at: Vector3) -> Node3D:
	## A radar that spins
	var n := Node3D.new()
	n.name = "Radar%d" % root.get_child_count()
	n.position = at
	root.add_child(n)
	match kind:
		"sps48":
			n.add_child(_mesh_node(_cached("sps48", _b_sps48)))
			n.set_meta("spin", 2.1)
		"sps49":
			n.add_child(_mesh_node(_cached("sps49", _b_sps49)))
			n.set_meta("spin", 1.3)
		"small":
			n.add_child(_mesh_node(_cached("radar_small", _b_radar_small)))
			n.set_meta("spin", 4.0)
	var spins: Array = root.get_meta("radars", [])
	spins.append(n)
	root.set_meta("radars", spins)
	return n


static func _add(root: Node3D, list: String, node: Node3D) -> void:
	var a: Array = root.get_meta(list, [])
	a.append(node)
	root.set_meta(list, a)


static func _vls(st: SurfaceTool, root: Node3D, centre: Vector3, cols: int, rows: int, skip := 0) -> void:
	## A Mk 41 vertical launcher: modules of 8 cells (2 across, 4 along), hatches flush with the
	## deck. Their tops are recorded as launch points; `skip` leaves out cells (the strike-down crane)
	var pitch := 0.85
	var gap := 0.3
	var w := cols * pitch + (cols / 2 - 1) * gap
	var l := rows * pitch + (rows / 4 - 1) * gap
	_box(st, centre + Vector3(0, -0.1, 0), Vector3(w + 0.8, 0.4, l + 0.8), HULL_DARK, DECK_SHIP)
	var cells: PackedVector3Array = root.get_meta("vls", PackedVector3Array())
	var n := 0
	for r in rows:
		for c in cols:
			n += 1
			if n <= skip:
				continue
			var x := -w * 0.5 + c * pitch + pitch * 0.5 + (c / 2) * gap
			var z := -l * 0.5 + r * pitch + pitch * 0.5 + (r / 4) * gap
			var p := centre + Vector3(x, 0.12, z)
			_flat(st, p, pitch * 0.8, pitch * 0.8, HATCH)
			cells.append(p)
	root.set_meta("vls", cells)


static func _lifeboats(st: SurfaceTool, x: float, y: float, z0: float, n: int, step := 4.0) -> void:
	for k in n:
		_box(st, Vector3(x, y, z0 + k * step), Vector3(1.5, 1.2, 3.2), WHITE)


# --- The ships ----------------------------------------------------------------------------------

static func _ship_root(key: String, build: Callable, mounts: Callable) -> Node3D:
	## One shared hull mesh plus this copy's own turning parts
	var root := Node3D.new()
	root.name = key
	var holder := Node3D.new()                   # collects the launch cells while building
	var mesh: Mesh
	if _cache.has(key):
		mesh = _cache[key]
		root.set_meta("vls", _cache[key + "_vls"])
	else:
		var st := _start()
		build.call(st, holder)
		mesh = st.commit()
		_cache[key] = mesh
		_cache[key + "_vls"] = holder.get_meta("vls", PackedVector3Array())
		root.set_meta("vls", _cache[key + "_vls"])
	holder.free()
	var mi := _mesh_node(mesh)
	mi.name = "Hull"
	root.add_child(mi)
	mounts.call(root)
	return root


static func carrier() -> Node3D:
	## Ford class (CVN-78): 333 m long, 41 m at the waterline, a flight deck 78 m wide with the
	## angled landing deck to port, a small island well aft on the starboard side, four catapults,
	## three deck-edge elevators. Two RAM, two Sea Sparrow and three Phalanx on sponsons.
	return _ship_root("carrier", _carrier_hull, _carrier_mounts)


static func _carrier_hull(st: SurfaceTool, _h: Node3D) -> void:
	var hull := [[-166.0, 0.0, 1.5, 17.0], [-160.0, 3.0, 8.0, 16.6], [-145.0, 8.0, 14.0, 16.3], [-115.0, 14.0, 18.5, 16.0],
		[-70.0, 19.0, 21.0, 16.0], [-10.0, 20.5, 22.0, 16.0], [100.0, 20.5, 22.0, 16.0], [140.0, 19.0, 21.5, 16.0],
		[156.0, 16.0, 20.0, 16.0], [161.0, 14.0, 18.5, 16.0]]
	_loft(st, hull, HULL, HULL_DARK)
	# The flight deck, overhanging the hull
	var deck := PackedVector2Array([Vector2(3, -168), Vector2(14, -156), Vector2(22, -122), Vector2(28, -72),
		Vector2(31, -22), Vector2(33, 40), Vector2(33, 140), Vector2(28, 164), Vector2(20, 167), Vector2(-22, 167),
		Vector2(-30, 152), Vector2(-38, 112), Vector2(-41, 62), Vector2(-40, 22), Vector2(-33, -12),
		Vector2(-25, -62), Vector2(-19, -112), Vector2(-11, -150), Vector2(-4, -166)])
	_prism(st, deck, 16.3, 19.5, HULL_DARK, DECK)
	var dy := 19.56
	# Angled landing deck: centre line, edges, the arresting wires, the foul line
	var a0 := Vector3(-7, dy, 166)
	var a1 := Vector3(-36, dy, -14)
	var ax := (a1 - a0).normalized()
	var side := Vector3(-ax.z, 0, ax.x)
	var ang := atan2(ax.x, ax.z) + PI
	for k in 18:
		_flat(st, a0 + (a1 - a0) * ((k + 0.25) / 18.0), 0.5, 5.5, WHITE, ang)
	for off in [-12.5, 12.5]:
		for k in 24:
			_flat(st, a0 + side * off + (a1 - a0) * ((k + 0.25) / 24.0), 0.35, 3.5, WHITE, ang)
	for k in 3:
		var p := a0 + ax * (38.0 + k * 12.0)
		_flat(st, p, 26.0, 0.35, Color(0.55, 0.55, 0.55), ang)
	for k in 30:
		_flat(st, a0 + side * 15.0 + (a1 - a0) * ((k + 0.5) / 30.0), 0.6, 2.8, RED if k % 2 == 0 else WHITE, ang)
	# Catapults: two on the bow, two in the waist; shuttle tracks and the jet blast deflectors
	for c in [[Vector3(-3, dy, -166), Vector3(-3, dy, -66)], [Vector3(12, dy, -164), Vector3(13, dy, -64)],
			[Vector3(-14, dy, -110), Vector3(-30, dy, 2)], [Vector3(-22, dy, -102), Vector3(-37, dy, 6)]]:
		var p: Vector3 = c[0]
		var q: Vector3 = c[1]
		var d := (q - p)
		var a2 := atan2(d.x, d.z)
		_flat(st, (p + q) * 0.5, 0.5, d.length(), Color(0.42, 0.42, 0.42), a2)
		_flat(st, (p + q) * 0.5 + Vector3(d.normalized().z, 0, -d.normalized().x) * 2.2, 0.25, d.length(), YELLOW, a2)
		var jbd := q + d.normalized() * 6.0
		var b := Basis(Vector3.UP, a2)
		var hx := b * Vector3(5.0, 0, 0)
		_quad_out(st, jbd - hx, jbd + hx, jbd + hx + Vector3(0, 2.6, 0) + b * Vector3(0, 0, 1.4), jbd - hx + Vector3(0, 2.6, 0) + b * Vector3(0, 0, 1.4), Color(0.36, 0.37, 0.38), -d)
	# Elevators at the deck edge: two to starboard ahead of the island, one to port aft
	for e in [[34.5, -18.0, 1.0], [34.5, 18.0, 1.0], [-44.0, 128.0, -1.0]]:
		var x: float = e[0]
		var z: float = e[1]
		_box(st, Vector3(x, 19.0, z), Vector3(16, 0.9, 20), HULL_DARK, Color(0.29, 0.30, 0.32))
		_flat(st, Vector3(x, 19.48, z), 15.6, 0.3, YELLOW)
		_panel(st, Vector3(x - e[2] * 13.0, 9.5, z), 18.0, 9.0, Vector3(e[2], 0, 0), DARK)
	# Taxi line and the deck number at the bow
	for k in 40:
		_flat(st, Vector3(22, dy, -150 + k * 7.6), 0.35, 3.8, YELLOW)
	_digits(st, "78", Vector3(4, dy + 0.02, -138), Vector3(1, 0, 0), Vector3(0, 0, -1), 13.0, WHITE, Vector3.UP)
	# The island: small and far aft, with the flat faces of the dual-band radar
	var ix := 29.0
	var iz := 66.0
	_taper(st, Vector3(ix, dy, iz), Vector2(10, 30), Vector2(9, 27), 12.0, SUPER)
	_taper(st, Vector3(ix, dy + 12.0, iz - 2.0), Vector2(11, 22), Vector2(10.5, 20), 5.0, SUPER)
	for k in 6:
		_panel(st, Vector3(ix, dy + 14.6, iz - 12.2), 1.5, 1.4, Vector3(0, 0, -1), GLASS)
		_panel(st, Vector3(ix - 4.0 + k * 1.6, dy + 14.6, iz - 13.0), 1.3, 1.4, Vector3(0, 0, -1), GLASS)
	for k in 8:
		_panel(st, Vector3(ix + 5.4, dy + 14.6, iz - 10.0 + k * 2.4), 1.8, 1.4, Vector3(1, 0, 0), GLASS)
		_panel(st, Vector3(ix - 5.4, dy + 14.6, iz - 10.0 + k * 2.4), 1.8, 1.4, Vector3(-1, 0, 0), GLASS)
	_taper(st, Vector3(ix, dy + 17.0, iz - 1.0), Vector2(10, 16), Vector2(8, 13), 7.0, SUPER_DARK)
	for f in [[Vector3(0, 0, -1), Vector3(0, 0, -7.6)], [Vector3(0, 0, 1), Vector3(0, 0, 5.6)], [Vector3(1, 0, 0), Vector3(4.6, 0, 0)], [Vector3(-1, 0, 0), Vector3(-4.6, 0, 0)]]:
		_panel(st, Vector3(ix, dy + 20.4, iz - 1.0) + f[1], 4.6, 4.6, f[0], SPY, true)
	_digits(st, "78", Vector3(ix + 5.15, dy + 7.0, iz), Vector3(0, 0, -1), Vector3(0, 1, 0), 6.5, WHITE, Vector3(1, 0, 0))
	_digits(st, "78", Vector3(ix - 5.15, dy + 7.0, iz), Vector3(0, 0, 1), Vector3(0, 1, 0), 6.5, WHITE, Vector3(-1, 0, 0))
	_tube(st, Vector3(ix, dy + 24.0, iz), Vector3(ix, dy + 40.0, iz), 0.9, SUPER_DARK, 8)
	_box(st, Vector3(ix, dy + 33.0, iz), Vector3(9, 0.4, 0.4), SUPER_DARK)
	_box(st, Vector3(ix, dy + 37.5, iz), Vector3(6, 0.3, 0.3), SUPER_DARK)
	_cyl(st, Vector3(ix, dy + 40.0, iz), 0.5, 3.0, RADOME, 8)
	# Sponsons for the weapons, the anchors, the antennas along the port edge
	for p in [Vector3(35.5, 15.5, -98), Vector3(-37.5, 15.5, 142), Vector3(-26.0, 15.5, -122), Vector3(34.5, 15.5, 152),
			Vector3(-30.5, 15.5, -137), Vector3(36.5, 15.5, 118), Vector3(-43.5, 15.5, 78)]:
		_box(st, p, Vector3(8, 3.0, 8), HULL_DARK, HULL)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 9.5, 13.0, -150), Vector3(0.6, 2.2, 1.6), DARK)
	for k in 5:
		_tube(st, Vector3(-38.0 + k * 0.2, 19.5, 30.0 + k * 22.0), Vector3(-39.0 + k * 0.2, 27.0, 30.0 + k * 22.0), 0.12, DARK, 5)


static func _carrier_mounts(root: Node3D) -> void:
	_add(root, "ram", _mount(root, "ram", Vector3(35.5, 17.0, -98), -PI * 0.5))
	_add(root, "ram", _mount(root, "ram", Vector3(-37.5, 17.0, 142), PI * 0.7))
	_add(root, "essm", _mount(root, "essm", Vector3(-26.0, 17.0, -122), PI * 0.4))
	_add(root, "essm", _mount(root, "essm", Vector3(34.5, 17.0, 152), -PI * 0.7))
	_add(root, "ciws", _mount(root, "ciws", Vector3(-30.5, 17.0, -137), PI * 0.3))
	_add(root, "ciws", _mount(root, "ciws", Vector3(36.5, 17.0, 118), -PI * 0.6))
	_add(root, "ciws", _mount(root, "ciws", Vector3(-43.5, 17.0, 78), PI * 0.5))
	_radar(root, "small", Vector3(29.0, 19.56 + 33.4, 66.0))



static func amphib() -> Node3D:
	## Wasp class (LHD-3 Kearsarge): 257 m, a full-length flight deck, the island to starboard
	## with its rotating SPS-48 and SPS-49 radars, two deck-edge elevators, and the well deck in
	## the stern: a floodable dock 81 m long behind a gate that drops into the water, where the
	## landing craft come and go. Two RAM, two Sea Sparrow, three Phalanx.
	return _ship_root("amphib", _amphib_hull, _amphib_mounts)


const WELL_FROM := 47.0                # the well deck runs from here to the stern
const WELL_HALF := 7.6                 # half its width
const WELL_TOP := 9.0                  # the deck over it
const AMPHIB_STERN := 128.4


static func _amphib_hull(st: SurfaceTool, _h: Node3D) -> void:
	var hull := [[-128.0, 0.0, 1.5, 17.5], [-121.0, 3.5, 8.5, 17.0], [-104.0, 9.0, 14.0, 16.6], [-75.0, 14.5, 16.4, 16.3],
		[-30.0, 16.0, 16.8, 16.3], [90.0, 16.0, 16.8, 16.3], [AMPHIB_STERN, 15.6, 16.5, 16.3]]
	_loft(st, hull, HULL, HULL_DARK, false)
	# The stern: walls either side of the well deck's mouth and over it
	var hb := 15.6
	_quad_out(st, Vector3(-hb, -1, AMPHIB_STERN), Vector3(-WELL_HALF, -1, AMPHIB_STERN), Vector3(-WELL_HALF, 16.3, AMPHIB_STERN), Vector3(-16.5, 16.3, AMPHIB_STERN), HULL, Vector3(0, 0, 1))
	_quad_out(st, Vector3(WELL_HALF, -1, AMPHIB_STERN), Vector3(hb, -1, AMPHIB_STERN), Vector3(16.5, 16.3, AMPHIB_STERN), Vector3(WELL_HALF, 16.3, AMPHIB_STERN), HULL, Vector3(0, 0, 1))
	_quad_out(st, Vector3(-WELL_HALF, WELL_TOP, AMPHIB_STERN), Vector3(WELL_HALF, WELL_TOP, AMPHIB_STERN), Vector3(WELL_HALF, 16.3, AMPHIB_STERN), Vector3(-WELL_HALF, 16.3, AMPHIB_STERN), HULL, Vector3(0, 0, 1))
	# Inside the well deck: the dock floor (flooded), its walls and the deck overhead
	var wall := Color(0.30, 0.31, 0.33)
	_quad_out(st, Vector3(-WELL_HALF, 0.15, WELL_FROM), Vector3(WELL_HALF, 0.15, WELL_FROM), Vector3(WELL_HALF, 0.15, AMPHIB_STERN), Vector3(-WELL_HALF, 0.15, AMPHIB_STERN), Color(0.12, 0.20, 0.24), Vector3.UP)
	for sx in [-1.0, 1.0]:
		_quad_out(st, Vector3(sx * WELL_HALF, -1, WELL_FROM), Vector3(sx * WELL_HALF, -1, AMPHIB_STERN), Vector3(sx * WELL_HALF, WELL_TOP, AMPHIB_STERN), Vector3(sx * WELL_HALF, WELL_TOP, WELL_FROM), wall, Vector3(-sx, 0, 0))
		for k in 10:
			_panel(st, Vector3(sx * (WELL_HALF - 0.02), 6.5, WELL_FROM + 6.0 + k * 8.0), 0.6, 0.4, Vector3(-sx, 0, 0), Color(1.0, 0.9, 0.6))
	_quad_out(st, Vector3(-WELL_HALF, WELL_TOP, WELL_FROM), Vector3(WELL_HALF, WELL_TOP, WELL_FROM), Vector3(WELL_HALF, WELL_TOP, AMPHIB_STERN), Vector3(-WELL_HALF, WELL_TOP, AMPHIB_STERN), DARK, Vector3.DOWN)
	_quad_out(st, Vector3(-WELL_HALF, -1, WELL_FROM), Vector3(WELL_HALF, -1, WELL_FROM), Vector3(WELL_HALF, WELL_TOP, WELL_FROM), Vector3(-WELL_HALF, WELL_TOP, WELL_FROM), wall, Vector3(0, 0, 1))
	# The flight deck
	var deck := _mirror([[0, -129], [11, -122], [17, -102], [20, -62], [20, 125], [18, 128.6]])
	_prism(st, deck, 16.3, 18.2, HULL_DARK, DECK)
	var dy := 18.26
	for k in 30:
		_flat(st, Vector3(-2.0, dy, -118 + k * 8.2), 0.5, 4.0, YELLOW)
	for k in 9:
		var z := -100.0 + k * 25.0
		_flat(st, Vector3(-9, dy, z), 9.0, 0.5, WHITE)
		_flat(st, Vector3(-9, dy, z), 0.5, 9.0, WHITE)
		_digits(st, str(k + 1), Vector3(-15.5, dy + 0.01, z), Vector3(1, 0, 0), Vector3(0, 0, -1), 4.0, WHITE, Vector3.UP)
	for k in 26:
		_flat(st, Vector3(12.5, dy, -110 + k * 9.0), 0.4, 4.5, WHITE)
	# Elevators: to port amidships, to starboard aft of the island
	for e in [[-26.0, 4.0, -1.0], [26.0, 82.0, 1.0]]:
		_box(st, Vector3(e[0], 17.6, e[1]), Vector3(13, 0.9, 16), HULL_DARK, Color(0.29, 0.30, 0.32))
		_panel(st, Vector3(e[0] - e[2] * 9.9, 11.0, e[1]), 15.0, 8.0, Vector3(e[2], 0, 0), DARK)
	# The island: long and tall, the bridge and flight control, funnels, the masts
	var ix := 16.5
	_taper(st, Vector3(ix, dy, 12.0), Vector2(8, 58), Vector2(7.5, 54), 9.0, SUPER)
	_taper(st, Vector3(ix, dy + 9.0, 4.0), Vector2(7.5, 34), Vector2(7, 30), 6.0, SUPER)
	for k in 9:
		_panel(st, Vector3(ix - 2.8 + k * 0.7, dy + 12.6, -11.0), 0.6, 1.3, Vector3(0, 0, -1), GLASS)
	for k in 12:
		_panel(st, Vector3(ix - 3.6, dy + 12.6, -9.0 + k * 2.1), 1.6, 1.3, Vector3(-1, 0, 0), GLASS)
		_panel(st, Vector3(ix + 3.6, dy + 12.6, -9.0 + k * 2.1), 1.6, 1.3, Vector3(1, 0, 0), GLASS)
	for k in 6:
		_panel(st, Vector3(ix - 3.85, dy + 5.0, 6.0 + k * 2.2), 1.7, 1.2, Vector3(-1, 0, 0), GLASS)
	for zz in [16.0, 28.0]:
		_taper(st, Vector3(ix, dy + 9.0, zz), Vector2(6, 7), Vector2(5, 5.5), 7.5, SUPER_DARK, STACK_TOP)
	_taper(st, Vector3(ix, dy + 15.0, 2.0), Vector2(5, 12), Vector2(4, 9), 4.0, SUPER)
	_tube(st, Vector3(ix, dy + 19.0, 0.0), Vector3(ix, dy + 36.0, 1.5), 0.8, SUPER_DARK, 8)
	_box(st, Vector3(ix, dy + 26.0, 0.5), Vector3(10, 0.35, 0.35), SUPER_DARK)
	_box(st, Vector3(ix, dy + 31.0, 1.0), Vector3(7, 0.3, 0.3), SUPER_DARK)
	_box(st, Vector3(ix, dy + 21.6, 0.5), Vector3(3.2, 0.5, 3.2), SUPER_DARK)
	_tube(st, Vector3(ix, dy + 9.0, 36.0), Vector3(ix, dy + 22.0, 36.0), 0.7, SUPER_DARK, 8)
	_box(st, Vector3(ix, dy + 22.0, 36.0), Vector3(3.0, 0.5, 3.0), SUPER_DARK)
	# Sponsons, boats and the anchors
	for p in [Vector3(17.5, 14.5, -96), Vector3(-17.5, 14.5, 112), Vector3(-17.0, 14.5, -108), Vector3(17.5, 14.5, 118)]:
		_box(st, p, Vector3(7, 2.4, 7), HULL_DARK, HULL)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 7.5, 13.0, -116), Vector3(0.6, 2.2, 1.6), DARK)
		_lifeboats(st, sx * 17.0, 13.6, -60.0, 5, 5.0)


static func _amphib_mounts(root: Node3D) -> void:
	_add(root, "ram", _mount(root, "ram", Vector3(17.5, 15.7, -96), -PI * 0.4))
	_add(root, "ram", _mount(root, "ram", Vector3(-17.5, 15.7, 112), PI * 0.6))
	_add(root, "essm", _mount(root, "essm", Vector3(16.5, 18.26 + 15.0, -4.0), 0.0))
	_add(root, "essm", _mount(root, "essm", Vector3(17.5, 15.7, 118), -PI * 0.7))
	_add(root, "ciws", _mount(root, "ciws", Vector3(-17.0, 15.7, -108), PI * 0.3))
	_add(root, "ciws", _mount(root, "ciws", Vector3(16.5, 18.26 + 9.0, 40.0), PI))
	_radar(root, "sps48", Vector3(16.5, 18.26 + 22.0, 0.5))
	_radar(root, "sps49", Vector3(16.5, 18.26 + 22.5, 36.0))
	# The stern gate: hinged at the bottom, it drops back into the water to open the well deck
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 0.4, AMPHIB_STERN + 0.2)
	root.add_child(gate)
	gate.add_child(_mesh_node(_cached("lhd_gate", _b_lhd_gate)))
	root.set_meta("gate", gate)
	root.set_meta("well", Vector3(0, 0, AMPHIB_STERN - 18.0))


static func _mirror(half: Array) -> PackedVector2Array:
	## An outline from its starboard half, bow to stern ([x, z] pairs)
	var out := PackedVector2Array()
	for p in half:
		out.append(Vector2(p[0], p[1]))
	for k in range(half.size() - 1, -1, -1):
		var p: Array = half[k]
		if p[0] != 0.0:
			out.append(Vector2(-p[0], p[1]))
	return out


static func destroyer() -> Node3D:
	## Arleigh Burke class, Flight I (DDG-57 Mitscher, DDG-58 Laboon): 154 m, 20 m beam. A Mk 45
	## 5-inch gun on the bow, Mk 41 launchers fore (29 cells) and aft (61 cells), the four flat
	## faces of the SPY-1D radar on the forward deckhouse, a raked tripod mast, two funnels,
	## Phalanx fore and aft, Harpoon canisters amidships, the helicopter deck aft.
	return _ship_root("destroyer", _destroyer_hull, _destroyer_mounts)


static func _destroyer_hull(st: SurfaceTool, holder: Node3D) -> void:
	var hull := [[-77.0, 0.0, 0.8, 9.6], [-72.0, 1.6, 4.2, 9.3], [-60.0, 4.6, 7.3, 8.9], [-40.0, 7.6, 9.4, 8.4],
		[-15.0, 9.2, 10.0, 8.1], [25.0, 9.3, 10.0, 7.9], [50.0, 9.0, 9.8, 6.9], [77.0, 7.8, 8.6, 6.7]]
	_loft(st, hull, HULL, DECK_SHIP)
	_rails(st, hull, HULL_DARK)
	# Forward launcher behind the gun
	_vls(st, holder, Vector3(0, 8.45, -39.0), 4, 8, 3)
	# Forward deckhouse: the bridge and the four radar faces
	_taper(st, Vector3(0, 8.1, -16.0), Vector2(16.5, 30), Vector2(15.0, 27), 6.0, SUPER)
	_taper(st, Vector3(0, 14.1, -17.0), Vector2(14.6, 22), Vector2(12.4, 18), 5.6, SUPER)
	_taper(st, Vector3(0, 19.7, -18.0), Vector2(10.0, 11), Vector2(8.6, 9), 3.0, SUPER)
	for k in 9:
		_panel(st, Vector3(-4.0 + k * 1.0, 18.3, -27.9), 0.8, 1.2, Vector3(0, 0.15, -1), GLASS)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 8.6, 18.4, -26.0), Vector3(3.6, 1.6, 2.6), SUPER)
		_panel(st, Vector3(sx * 4.2, 16.6, -26.0), 4.2, 4.2, Vector3(sx, 0, -1.4), SPY, true)
		_panel(st, Vector3(sx * 5.4, 16.6, -9.6), 4.2, 4.2, Vector3(sx, 0, 1.2), SPY, true)
	# The mast, raked aft, with its yards and radar
	_tube(st, Vector3(0, 22.6, -16.0), Vector3(0, 40.0, -12.0), 0.7, SUPER_DARK, 8)
	for sx in [-1.0, 1.0]:
		_tube(st, Vector3(sx * 3.5, 22.6, -19.0), Vector3(0, 33.0, -13.5), 0.3, SUPER_DARK, 6)
	_box(st, Vector3(0, 33.0, -13.4), Vector3(9.0, 0.3, 0.3), SUPER_DARK)
	_box(st, Vector3(0, 37.0, -12.4), Vector3(5.0, 0.25, 0.25), SUPER_DARK)
	# Funnels: slab-sided, black-topped
	for zz in [4.0, 21.0]:
		_taper(st, Vector3(0, 8.0, zz), Vector2(6.5, 9.0), Vector2(5.0, 6.5), 11.5, SUPER, STACK_TOP)
		for sx in [-1.0, 1.0]:
			_cyl(st, Vector3(sx * 1.2, 19.5, zz), 0.7, 1.4, STACK_TOP, 8)
	_box(st, Vector3(0, 9.6, 12.5), Vector3(8.0, 3.0, 8.0), SUPER)
	# Harpoon canisters between the funnels, angled out to each side
	for sx in [-1.0, 1.0]:
		for k in 4:
			var c := Vector3(sx * 3.2, 11.6 + k * 0.6, 12.5)
			var b := Basis(Vector3.UP, sx * 0.6)
			var e := b * Vector3(0, 0, 2.2)
			_tube(st, c - e, c + e, 0.3, HULL_DARK, 6)
	# Aft deckhouse with the fire-control directors
	_taper(st, Vector3(0, 7.0, 36.0), Vector2(14, 18), Vector2(12.5, 16), 5.5, SUPER)
	for zz in [32.0, 40.0]:
		_cyl(st, Vector3(0, 12.5, zz), 0.8, 1.2, SUPER_DARK, 8)
		_cone(st, Vector3(0, 13.7, zz), 1.3, 0.8, SUPER_DARK, 10)
	# Aft launcher, the helicopter deck, the hull numbers' place and the boats
	_vls(st, holder, Vector3(0, 7.15, 51.0), 8, 8, 3)
	_box(st, Vector3(0, 6.77, 67.5), Vector3(16.5, 0.05, 17.0), DECK)
	_flat(st, Vector3(0, 6.82, 67.5), 0.4, 15.0, WHITE)
	_flat(st, Vector3(0, 6.82, 67.5), 10.0, 0.4, WHITE)
	_flat(st, Vector3(0, 6.83, 60.0), 14.0, 0.5, YELLOW)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 9.6, 9.5, 28.0), Vector3(1.6, 1.4, 6.0), WHITE)
		_box(st, Vector3(sx * 6.4, 8.6, 33.0), Vector3(1.0, 1.0, 2.0), HULL_DARK)
		_box(st, Vector3(sx * 3.6, 9.0, -70.0), Vector3(0.5, 1.4, 1.2), DARK)


static func _destroyer_mounts(root: Node3D) -> void:
	_add(root, "guns", _mount(root, "gun", Vector3(0, 8.7, -54.0), 0.0))
	_add(root, "ciws", _mount(root, "ciws", Vector3(0, 21.0, -10.5), 0.0))
	_add(root, "ciws", _mount(root, "ciws", Vector3(0, 12.6, 43.5), PI))
	_radar(root, "small", Vector3(0, 40.0, -12.0))


static func cruiser() -> Node3D:
	## Ticonderoga class (CG-60 Normandy): 173 m, 16.8 m beam. Mk 45 guns fore and aft, a Mk 41
	## launcher of 61 cells at each end, SPY-1 faces on both deckhouses, two masts with an SPS-49
	## that turns, two funnels, Phalanx on each deckhouse, a hangar and helicopter deck aft.
	return _ship_root("cruiser", _cruiser_hull, _cruiser_mounts)


static func _cruiser_hull(st: SurfaceTool, holder: Node3D) -> void:
	var hull := [[-86.5, 0.0, 0.8, 9.2], [-80.0, 1.8, 4.0, 8.9], [-65.0, 4.6, 6.8, 8.5], [-45.0, 7.0, 8.3, 8.1],
		[-20.0, 8.0, 8.4, 7.9], [30.0, 8.2, 8.4, 7.7], [70.0, 7.5, 8.0, 6.9], [86.5, 6.5, 7.2, 6.6]]
	_loft(st, hull, HULL, DECK_SHIP)
	_rails(st, hull, HULL_DARK)
	_vls(st, holder, Vector3(0, 8.4, -51.0), 8, 8, 3)
	# Forward deckhouse: tall and boxy, the bridge on top, two radar faces angled forward
	_taper(st, Vector3(0, 7.95, -20.0), Vector2(15.4, 36), Vector2(14.6, 34), 8.0, SUPER)
	_taper(st, Vector3(0, 15.95, -25.0), Vector2(12.6, 20), Vector2(11.2, 16), 4.5, SUPER)
	for k in 9:
		_panel(st, Vector3(-4.0 + k * 1.0, 18.8, -33.0), 0.8, 1.2, Vector3(0, 0.15, -1), GLASS)
	for sx in [-1.0, 1.0]:
		_panel(st, Vector3(sx * 5.6, 12.5, -36.6), 4.2, 4.2, Vector3(sx, 0, -1.2), SPY, true)
		_box(st, Vector3(sx * 7.6, 18.9, -31.0), Vector3(2.6, 1.4, 2.4), SUPER)
	_tube(st, Vector3(0, 20.4, -22.0), Vector3(0, 37.0, -20.0), 0.7, SUPER_DARK, 8)
	for sx in [-1.0, 1.0]:
		_tube(st, Vector3(sx * 3.4, 20.4, -25.0), Vector3(0, 30.0, -21.0), 0.3, SUPER_DARK, 6)
	_box(st, Vector3(0, 30.5, -20.8), Vector3(8.0, 0.3, 0.3), SUPER_DARK)
	# Funnels and the main mast between them
	for zz in [4.0, 22.0]:
		_taper(st, Vector3(0, 7.8, zz), Vector2(5.6, 8.0), Vector2(4.6, 6.0), 12.5, SUPER, STACK_TOP)
	_box(st, Vector3(0, 9.5, 13.0), Vector3(7.0, 3.4, 10.0), SUPER)
	_tube(st, Vector3(0, 11.2, 13.0), Vector3(0, 31.0, 14.0), 0.6, SUPER_DARK, 8)
	_box(st, Vector3(0, 26.0, 13.8), Vector3(7.0, 0.3, 0.3), SUPER_DARK)
	# Aft deckhouse: radar faces angled aft, the hangar doors
	_taper(st, Vector3(0, 7.75, 40.0), Vector2(15.0, 26), Vector2(14.2, 24), 7.0, SUPER)
	_taper(st, Vector3(0, 14.75, 36.0), Vector2(11.0, 12), Vector2(9.6, 9.5), 3.8, SUPER)
	for sx in [-1.0, 1.0]:
		_panel(st, Vector3(sx * 5.4, 12.0, 52.6), 4.2, 4.2, Vector3(sx, 0, 1.2), SPY, true)
		_panel(st, Vector3(sx * 3.4, 10.6, 53.1), 5.0, 5.2, Vector3(0, 0, 1), HULL_DARK)
	_box(st, Vector3(0, 7.72, 60.5), Vector3(15.0, 0.05, 14.0), DECK)
	_flat(st, Vector3(0, 7.76, 60.5), 0.4, 12.0, WHITE)
	_flat(st, Vector3(0, 7.76, 60.5), 9.0, 0.4, WHITE)
	_vls(st, holder, Vector3(0, 7.05, 73.0), 8, 8, 3)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 8.4, 10.0, 25.0), Vector3(1.5, 1.3, 6.0), WHITE)
		_box(st, Vector3(sx * 3.6, 9.0, -79.0), Vector3(0.5, 1.4, 1.2), DARK)
		for k in 4:
			var c := Vector3(sx * 6.6, 8.4 + k * 0.55, 66.5)
			var e := Basis(Vector3.UP, sx * 0.4) * Vector3(0, 0, 2.2)
			_tube(st, c - e, c + e, 0.28, HULL_DARK, 6)


static func _cruiser_mounts(root: Node3D) -> void:
	_add(root, "guns", _mount(root, "gun", Vector3(0, 8.6, -67.0), 0.0))
	_add(root, "guns", _mount(root, "gun", Vector3(0, 6.9, 81.5), PI))
	_add(root, "ciws", _mount(root, "ciws", Vector3(0, 20.5, -16.5), 0.0))
	_add(root, "ciws", _mount(root, "ciws", Vector3(0, 18.6, 38.0), PI))
	_radar(root, "sps49", Vector3(0, 31.0, 14.0))
	_radar(root, "small", Vector3(0, 37.0, -20.0))


static func lcac() -> Node3D:
	## Landing Craft, Air Cushion: 26.8 m by 14.3 m. A black skirt, the cargo deck open fore and
	## aft between two side structures (the pilots' cab forward on the starboard one), ramps at
	## both ends, two big ducted propellers at the back and swivelling thrusters forward.
	return _ship_root("lcac", _lcac_hull, _lcac_mounts)


static func _lcac_hull(st: SurfaceTool, _h: Node3D) -> void:
	var olive := Color(0.42, 0.45, 0.40)
	var olive_l := Color(0.50, 0.54, 0.48)
	var skirt := _mirror([[0, -13.4], [4.5, -13.0], [6.8, -11.0], [7.15, -8], [7.15, 11], [6.5, 13.2], [4.0, 13.4]])
	_prism(st, skirt, -0.3, 1.5, BOOT, Color(0.16, 0.16, 0.16))
	_box(st, Vector3(0, 1.7, 0), Vector3(8.4, 0.4, 26.0), olive, Color(0.36, 0.38, 0.35))
	for k in 6:
		_flat(st, Vector3(0, 1.92, -10.0 + k * 4.0), 7.6, 0.15, YELLOW)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 5.5, 3.6, 0.5), Vector3(2.6, 3.4, 23.0), olive_l)
		for k in 4:
			_panel(st, Vector3(sx * 6.82, 3.8, -7.0 + k * 4.0), 2.0, 1.6, Vector3(sx, 0, 0), Color(0.25, 0.27, 0.25))
		# thrusters forward on top of each side structure
		_cyl(st, Vector3(sx * 5.5, 5.3, -8.5), 0.9, 1.6, olive, 10)
	_box(st, Vector3(5.5, 6.3, -10.0), Vector3(2.8, 1.8, 3.4), olive_l)
	_panel(st, Vector3(5.5, 6.6, -11.75), 2.2, 0.9, Vector3(0, 0, -1), GLASS)
	_panel(st, Vector3(6.95, 6.6, -10.0), 2.4, 0.9, Vector3(1, 0, 0), GLASS)
	_box(st, Vector3(0, 2.2, -13.6), Vector3(7.6, 0.4, 1.2), olive)
	_box(st, Vector3(0, 2.2, 13.2), Vector3(7.6, 0.4, 1.0), olive)
	_box(st, Vector3(-5.5, 6.0, 4.0), Vector3(2.2, 1.2, 3.0), olive)
	_digits(st, "57", Vector3(6.85, 3.6, 2.0), Vector3(0, 0, -1), Vector3(0, 1, 0), 1.4, WHITE, Vector3(1, 0, 0))


static func _lcac_mounts(root: Node3D) -> void:
	# The two propellers in their ducts, which spin when it's under way
	for sx in [-1.0, 1.0]:
		var duct := MeshInstance3D.new()
		duct.mesh = _cached("lcac_duct", _b_lcac_duct)
		duct.material_override = _material()
		duct.position = Vector3(sx * 3.6, 4.9, 11.6)
		root.add_child(duct)
		var prop := Node3D.new()
		prop.name = "Prop"
		prop.position = duct.position
		prop.add_child(_mesh_node(_cached("lcac_prop", _b_lcac_prop)))
		root.add_child(prop)
		_add(root, "props", prop)


static func hull_number(root: Node3D, number: String) -> void:
	## Paint a ship's own number on it (the shared hull mesh has none)
	var old := root.get_node_or_null("Number")
	if old != null:
		if old.get_meta("n", "") == number:
			return
		old.free()
	var key := "%s_no_%s" % [root.name, number]
	var mesh := _cached(key, func(st: SurfaceTool) -> void:
		_paint_number(st, root.name, number))
	var mi := _mesh_node(mesh)
	mi.name = "Number"
	mi.set_meta("n", number)
	root.add_child(mi)


static func _paint_number(st: SurfaceTool, kind: String, number: String) -> void:
	match kind:
		"destroyer":
			for sx in [-1.0, 1.0]:
				var x: float = sx * 7.4 + sx * 0.25
				_digits(st, number, Vector3(x, 5.6, -58.0), Vector3(0, 0, -sx), Vector3(0, 1, 0), 3.4, WHITE, Vector3(sx, 0, 0))
		"cruiser":
			for sx in [-1.0, 1.0]:
				var x: float = sx * 6.9 + sx * 0.25
				_digits(st, number, Vector3(x, 5.5, -66.0), Vector3(0, 0, -sx), Vector3(0, 1, 0), 3.4, WHITE, Vector3(sx, 0, 0))
		"amphib":
			for sx in [-1.0, 1.0]:
				_digits(st, number, Vector3(16.5 + sx * 3.98, 18.26 + 3.5, 26.0), Vector3(0, 0, -sx), Vector3(0, 1, 0), 5.5, WHITE, Vector3(sx, 0, 0))
				_digits(st, number, Vector3(sx * 13.4, 11.0, -100.0), Vector3(0, 0, -sx), Vector3(0, 1, 0), 5.0, WHITE, Vector3(sx, 0, 0))


static func by_type(id: String) -> Node3D:
	match id:
		"carrier":
			return carrier()
		"amphib":
			return amphib()
		"destroyer":
			return destroyer()
		"cruiser":
			return cruiser()
		"lcac":
			return lcac()
	return null


static func deck_height(id: String) -> float:
	## The flight deck (or helicopter deck) aircraft sit on
	match id:
		"carrier":
			return 19.56
		"amphib":
			return 18.26
		"destroyer":
			return 6.8
		"cruiser":
			return 7.75
		"lcac":
			return 1.9
	return 0.0


# --- Builders for the shared mount meshes ---------------------------------------------------

static func _b_mk45_turret(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 2.4, 0.7, HULL_DARK, 16)
	_taper(st, Vector3(0, 0.7, 0.6), Vector2(4.4, 6.4), Vector2(3.0, 4.2), 2.5, MOUNT)
	_panel(st, Vector3(0, 1.9, -2.55), 1.0, 1.2, Vector3(0, 0.45, -1), DARK)
	_box(st, Vector3(0, 3.35, 1.6), Vector3(1.6, 0.4, 1.4), MOUNT)


static func _b_mk45_barrel(st: SurfaceTool) -> void:
	_tube(st, Vector3(0, 0, 0.5), Vector3(0, 0, -7.9), 0.17, MOUNT, 10)
	_tube(st, Vector3(0, 0, -7.4), Vector3(0, 0, -8.0), 0.22, MOUNT, 10)
	_tube(st, Vector3(0, 0, 0.4), Vector3(0, 0, -0.8), 0.32, MOUNT, 10)


static func _b_ciws_mount(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 0.95, 1.2, MOUNT, 12)
	_box(st, Vector3(0, 1.75, 0.1), Vector3(1.7, 1.1, 2.1), MOUNT)
	_cyl(st, Vector3(0, 2.3, 0.35), 0.78, 1.6, RADOME, 14)
	_cone(st, Vector3(0, 3.9, 0.35), 0.78, 0.7, RADOME, 14)
	_box(st, Vector3(0, 3.1, -0.45), Vector3(1.0, 0.7, 0.3), RADOME)


static func _b_ciws_gun(st: SurfaceTool) -> void:
	for k in 6:
		var a := TAU * k / 6.0
		var o := Vector3(cos(a) * 0.12, sin(a) * 0.12, 0)
		_tube(st, o, o + Vector3(0, 0, -2.2), 0.035, DARK, 6)
	_tube(st, Vector3(0, 0, 0.0), Vector3(0, 0, -0.5), 0.2, DARK, 10)
	_box(st, Vector3(0, -0.55, 0.5), Vector3(0.9, 0.7, 1.2), MOUNT)


static func _b_ram_base(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 0.9, 1.0, MOUNT, 12)
	_box(st, Vector3(0, 1.4, 0), Vector3(2.8, 0.8, 1.6), MOUNT)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 1.25, 2.2, 0), Vector3(0.3, 1.6, 1.0), MOUNT)


static func _b_ram_box(st: SurfaceTool) -> void:
	_box(st, Vector3(0, 0, 0.1), Vector3(2.1, 1.9, 4.4), MOUNT)
	for r in 3:
		for c in 7:
			_panel(st, Vector3(-0.78 + c * 0.26, -0.55 + r * 0.55, -2.1), 0.18, 0.18, Vector3(0, 0, -1), DARK)


static func _b_essm_base(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 1.0, 1.0, MOUNT, 12)
	_box(st, Vector3(0, 1.6, 0.3), Vector3(1.2, 1.2, 2.0), MOUNT)


static func _b_essm_box(st: SurfaceTool) -> void:
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.95, 0, 0.2), Vector3(1.35, 1.35, 4.2), MOUNT)
		for r in 2:
			for c in 2:
				_panel(st, Vector3(sx * 0.95 - 0.3 + c * 0.6, -0.3 + r * 0.6, -1.9), 0.45, 0.45, Vector3(0, 0, -1), DARK)


static func _b_sps48(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 0.5, 0.8, DARK, 8)
	var b := Basis(Vector3.RIGHT, deg_to_rad(-15))
	var c := Vector3(0, 3.0, 0.4)
	var hx := b * Vector3(2.7, 0, 0)
	var hy := b * Vector3(0, 2.5, 0)
	_quad_out(st, c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, SUPER_DARK, b * Vector3(0, 0, -1))
	_quad_out(st, c - hx - hy + b * Vector3(0, 0, 0.3), c + hx - hy + b * Vector3(0, 0, 0.3), c + hx + hy + b * Vector3(0, 0, 0.3), c - hx + hy + b * Vector3(0, 0, 0.3), DARK, b * Vector3(0, 0, 1))


static func _b_sps49(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, 0), 0.4, 0.6, DARK, 8)
	_box(st, Vector3(0, 1.6, 0), Vector3(7.3, 2.6, 0.25), SUPER_DARK)
	_box(st, Vector3(0, 0.9, -0.6), Vector3(0.6, 0.6, 1.2), DARK)


static func _b_radar_small(st: SurfaceTool) -> void:
	_box(st, Vector3(0, 0.3, 0), Vector3(3.0, 0.5, 0.4), DARK)



static func _b_lhd_gate(st: SurfaceTool) -> void:
	_box(st, Vector3(0, 4.3, 0), Vector3(WELL_HALF * 2.0 - 0.2, 8.6, 0.6), HULL_DARK)
	for k in 5:
		_box(st, Vector3(0, 0.9 + k * 1.7, 0.35), Vector3(WELL_HALF * 2.0 - 0.6, 0.25, 0.15), HULL)



static func _b_lcac_duct(st: SurfaceTool) -> void:
	var olive := Color(0.42, 0.45, 0.40)
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		var p0 := Vector3(cos(a0) * 2.4, sin(a0) * 2.4, 0)
		var p1 := Vector3(cos(a1) * 2.4, sin(a1) * 2.4, 0)
		_quad_out(st, p0 + Vector3(0, 0, -0.9), p1 + Vector3(0, 0, -0.9), p1 + Vector3(0, 0, 0.9), p0 + Vector3(0, 0, 0.9), olive, (p0 + p1))
	_box(st, Vector3(0, -2.6, 0), Vector3(0.6, 0.8, 1.4), olive)
	_tube(st, Vector3(0, 0, 0.9), Vector3(0, 2.2, 3.2), 0.12, olive, 5)


static func _b_lcac_prop(st: SurfaceTool) -> void:
	_cyl(st, Vector3(0, 0, -0.3), 0.35, 0.6, DARK, 8)
	for k in 4:
		var a := TAU * k / 4.0
		var d := Vector3(cos(a), sin(a), 0)
		var w := Vector3(-sin(a), cos(a), 0) * 0.28
		_quad_out(st, d * 0.3 - w, d * 0.3 + w, d * 2.2 + w * 0.6, d * 2.2 - w * 0.6, DARK, Vector3(0, 0, 1))
