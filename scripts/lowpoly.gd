class_name LowPoly
extends RefCounted
## A small mesh builder for the vehicles' low-poly, flat-shaded look: shapes are made of
## cross-sections (chamfered rectangles, so an octagon when the chamfer is large) joined
## along their length, which gives tapered noses, rounded fuselages, sloped armour and
## bevelled edges instead of plain boxes. Every face is flat-shaded, colours are per shape
## (vertex colours, one material for a whole vehicle), and each vertex carries its outward
## direction for the 1-pixel outline (see UnitLook).
##
## Build a part, then commit() it to an ArrayMesh:
##   var lp := LowPoly.new()
##   lp.hull([[z, width, height, centre_y, chamfer], ...], colour)   # stations along Z
##   lp.box(size, pos, colour, bevel)
##   lp.cyl(radius, length, sides, transform, colour)
##   var mesh := lp.commit()
## Every shape takes an optional Transform3D to place or turn it.

var _tris: Array = []          # [a, b, c, color, prim]
var _prim := 0


# --- Shapes ---------------------------------------------------------------------------

func hull(stations: Array, color: Color, xf := Transform3D.IDENTITY, top := Color(0, 0, 0, 0), caps := true) -> void:
	## A shape made of cross-sections along Z. Each station: [z, width, height, centre_y,
	## chamfer] (chamfer 0 = square corners, 1 = an octagon as round as it gets), optionally
	## a 6th value: centre_x. `top`: a second colour for faces looking up (a roof tone).
	var rings: Array = []
	for st in stations:
		var cx: float = st[5] if st.size() > 5 else 0.0
		rings.append(_ring(st[1], st[2], st[4], Vector2(cx, st[3]), st[0]))
	loft(rings, color, xf, top, caps)


func loft(rings: Array, color: Color, xf := Transform3D.IDENTITY, top := Color(0, 0, 0, 0), caps := true) -> void:
	## Join rings of points (each the same count, in the same order) with quads, and cap the ends
	_prim += 1
	var centre := Vector3.ZERO
	var n := 0
	for r in rings:
		for p in r:
			centre += p
			n += 1
	centre /= maxf(1.0, n)
	var cw: Vector3 = xf * centre
	for i in range(1, rings.size()):
		var a: Array = rings[i - 1]
		var b: Array = rings[i]
		# Faces between two rings face away from the middle of those two rings
		var mid := Vector3.ZERO
		for p in a + b:
			mid += p
		mid = xf * (mid / float(a.size() + b.size()))
		for k in a.size():
			var k2 := (k + 1) % a.size()
			_quad(xf * a[k], xf * a[k2], xf * b[k2], xf * b[k], color, top, mid, cw)
	if caps:
		for r in [rings[0], rings[-1]]:
			var c := Vector3.ZERO
			for p in r:
				c += p
			c /= r.size()
			for k in r.size():
				_tri(xf * c, xf * r[k], xf * r[(k + 1) % r.size()], color, top, cw)


func box(size: Vector3, pos: Vector3, color: Color, bevel := 0.0, xf := Transform3D.IDENTITY, top := Color(0, 0, 0, 0)) -> void:
	## A box, its edges bevelled by `bevel` metres (0: a plain box), turned by xf about its centre
	## and then moved to pos
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var ch := b / maxf(0.001, minf(h.x, h.y))
	var st: Array = []
	if b > 0.0:
		st.append([-h.z, size.x - b * 2.0, size.y - b * 2.0, 0.0, ch * 0.5])
		st.append([-h.z + b, size.x, size.y, 0.0, ch])
		st.append([h.z - b, size.x, size.y, 0.0, ch])
		st.append([h.z, size.x - b * 2.0, size.y - b * 2.0, 0.0, ch * 0.5])
	else:
		st.append([-h.z, size.x, size.y, 0.0, 0.0])
		st.append([h.z, size.x, size.y, 0.0, 0.0])
	hull(st, color, Transform3D(Basis.IDENTITY, pos) * xf, top)


func cyl(radius: float, length: float, sides: int, xf: Transform3D, color: Color, radius2 := -1.0) -> void:
	## A prism with `sides` faces along Z (a wheel, a pipe, an engine), centred on xf's origin.
	## radius2: the far end's radius (a cone) if given.
	var r2 := radius if radius2 < 0.0 else radius2
	var rings := [_ngon(radius, sides, -length * 0.5), _ngon(r2, sides, length * 0.5)]
	loft(rings, color, xf)


func tyre(radius: float, width: float, sides: int, xf: Transform3D, color: Color) -> void:
	## A round tyre along Z: tread with rounded shoulders (sides: 16 or more reads as round)
	var w := width * 0.5
	var rings := [_ngon(radius * 0.80, sides, -w), _ngon(radius * 0.96, sides, -w * 0.7), _ngon(radius, sides, -w * 0.3),
		_ngon(radius, sides, w * 0.3), _ngon(radius * 0.96, sides, w * 0.7), _ngon(radius * 0.80, sides, w)]
	loft(rings, color, xf)


func wedge(size: Vector3, pos: Vector3, color: Color, front_h: float, xf := Transform3D.IDENTITY) -> void:
	## A box whose front (-Z) end is only front_h tall, sitting on the same bottom: a slope
	var h := size * 0.5
	var st := [[-h.z, size.x, front_h, -h.y + front_h * 0.5, 0.0], [h.z, size.x, size.y, 0.0, 0.0]]
	hull(st, color, Transform3D(Basis.IDENTITY, pos) * xf)


# --- Output -------------------------------------------------------------------------

func commit() -> ArrayMesh:
	## One flat-shaded mesh. Outline directions: per shape, each corner's faces' normals
	## averaged and stretched so every face moves out by the same amount.
	var normals := {}            # "prim|x|y|z" -> Array of face normals
	var face_n: Array = []
	for t in _tris:
		var n: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).normalized() * -1.0
		face_n.append(n)
		for v in [t[0], t[1], t[2]]:
			var key := _key(t[4], v)
			if not normals.has(key):
				normals[key] = []
			var list: Array = normals[key]
			var dup := false
			for m in list:
				if (m as Vector3).dot(n) > 0.995:
					dup = true
					break
			if not dup:
				list.append(n)
	var dirs := {}
	for key in normals:
		var list: Array = normals[key]
		var avg := Vector3.ZERO
		for m in list:
			avg += m
		if avg.length() < 0.001:
			dirs[key] = Vector3.ZERO
			continue
		avg = avg.normalized()
		var least := 1.0
		for m in list:
			least = minf(least, avg.dot(m))
		dirs[key] = avg / clampf(least, 0.5, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for i in _tris.size():
		var t: Array = _tris[i]
		var n: Vector3 = face_n[i]
		if n == Vector3.ZERO or ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).length() < 1e-6:
			continue
		for v in [t[0], t[1], t[2]]:
			var d: Vector3 = dirs[_key(t[4], v)]
			st.set_color(t[3])
			st.set_normal(n)
			st.set_custom(0, Color(d.x, d.y, d.z, 0.0))
			st.add_vertex(v)
	return st.commit()


func is_empty() -> bool:
	return _tris.is_empty()


# --- Internals ----------------------------------------------------------------------

static func _ring(w: float, h: float, chamfer: float, c: Vector2, z: float) -> Array:
	## 8 points round a w x h rectangle with its corners cut (chamfer 0..1 of the half-size)
	var hw := w * 0.5
	var hh := h * 0.5
	var cut := clampf(chamfer, 0.0, 1.0) * minf(hw, hh) * 0.999
	var pts := [Vector2(hw, -hh + cut), Vector2(hw, hh - cut), Vector2(hw - cut, hh), Vector2(-hw + cut, hh),
		Vector2(-hw, hh - cut), Vector2(-hw, -hh + cut), Vector2(-hw + cut, -hh), Vector2(hw - cut, -hh)]
	var out: Array = []
	for p in pts:
		out.append(Vector3(c.x + p.x, c.y + p.y, z))
	return out


static func _ngon(r: float, sides: int, z: float) -> Array:
	var out: Array = []
	for k in sides:
		var a := TAU * (k + 0.5) / sides
		out.append(Vector3(cos(a) * r, sin(a) * r, z))
	return out


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, top: Color, centre: Vector3, centre2 := Vector3.INF) -> void:
	_tri(a, b, c, color, top, centre, centre2)
	_tri(a, c, d, color, top, centre, centre2)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, top: Color, centre: Vector3, centre2 := Vector3.INF) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 1e-7:
		return
	# Godot's front faces wind so this cross product points inward: flip if it points out
	var mid := (a + b + c) / 3.0
	var out := mid - centre
	if absf(n.normalized().dot(out.normalized())) < 0.05 and centre2 != Vector3.INF:
		out = mid - centre2       # a face lying across the shape (a step): use the shape's middle
	if n.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var col := color
	if top.a > 0.0 and -n.normalized().y > 0.7:
		col = top
	_tris.append([a, b, c, col, _prim])


static func _key(prim: int, v: Vector3) -> String:
	return "%d|%.3f|%.3f|%.3f" % [prim, v.x, v.y, v.z]
