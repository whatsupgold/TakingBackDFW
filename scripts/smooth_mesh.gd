class_name SmoothMesh
extends RefCounted
## A mesh builder for smooth, rounded models (the "realistic" look, as opposed to LowPoly's
## faceted one): shapes are rings of points joined into a skin, with smooth shading (each
## vertex's normal is the average of the faces around it) and a material per surface, so one
## shape can be part paint, part glass. Every vertex also carries its normal in CUSTOM0 for
## the 1-pixel outline (see UnitLook).
##
##   var sm := SmoothMesh.new()
##   var paint := sm.surface(material)
##   sm.loft([[z, half_width, half_height, centre_y], ...], 64, 32, func(p, n): return paint)
##   sm.sweep([p0, p1, p2...], radius, 10, paint)
##   var mesh := sm.commit()

var _verts := PackedVector3Array()
var _faces: Array = []         # [i0, i1, i2, surface]
var _mats: Array = []


func surface(mat: Material) -> int:
	_mats.append(mat)
	return _mats.size() - 1


# --- Shapes ---------------------------------------------------------------------------

func loft(stations: Array, slices: int, segs: int, pick: Callable, xf := Transform3D.IDENTITY, power := 2.0) -> void:
	## A smooth body along Z through cross-sections [z, half_width, half_height, centre_y,
	## (centre_x)], curved through the stations (Catmull-Rom), each one a superellipse
	## (power 2 = an ellipse, higher = squarer). `pick(point, outward)` returns the surface for
	## each face, so a body can have its windows in it.
	var rings: Array = []
	var centres: Array = []
	var n := stations.size()
	for i in slices + 1:
		var t := float(i) / slices * (n - 1)
		var k := mini(floori(t), n - 2)
		var f := t - k
		var s := []
		for c in 5:
			var p0: float = _st(stations, k - 1, c)
			var p1: float = _st(stations, k, c)
			var p2: float = _st(stations, k + 1, c)
			var p3: float = _st(stations, k + 2, c)
			s.append(_catmull(p0, p1, p2, p3, f))
		var z: float = s[0]
		var hw := maxf(s[1], 0.001)
		var hh := maxf(s[2], 0.001)
		var ring := PackedVector3Array()
		for j in segs:
			var a := TAU * j / segs
			var ca := cos(a)
			var sa := sin(a)
			var x := signf(ca) * pow(absf(ca), 2.0 / power) * hw
			var y := signf(sa) * pow(absf(sa), 2.0 / power) * hh
			ring.append(xf * Vector3(s[4] + x, s[3] + y, z))
		rings.append(ring)
		centres.append(xf * Vector3(s[4], s[3], z))
	_skin(rings, centres, pick)


func sweep(points: Array, radius: float, segs: int, surf: int, xf := Transform3D.IDENTITY, flat := 1.0) -> void:
	## A round tube along a path (skids, struts), with rounded ends. `flat` < 1 squashes it
	## (an airfoil-ish blade).
	var pts: Array = []
	for p in points:
		pts.append(xf * (p as Vector3))
	var rings: Array = []
	var centres: Array = []
	var up_ref := Vector3.UP
	var count := pts.size()
	# Rounded ends: a short taper before the first and after the last point
	for i in count:
		var p: Vector3 = pts[i]
		var tan: Vector3 = ((pts[mini(i + 1, count - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		if absf(tan.dot(up_ref)) > 0.95:
			up_ref = Vector3.FORWARD
		var right := tan.cross(up_ref).normalized()
		var up := right.cross(tan).normalized()
		var radii := [radius]
		var offs := [0.0]
		if i == 0:
			radii = [radius * 0.05, radius * 0.7, radius]
			offs = [-radius, -radius * 0.7, 0.0]
		elif i == count - 1:
			radii = [radius, radius * 0.7, radius * 0.05]
			offs = [0.0, radius * 0.7, radius]
		for q in radii.size():
			var ring := PackedVector3Array()
			var c: Vector3 = p + tan * (offs[q] as float)
			for j in segs:
				var a := TAU * j / segs
				ring.append(c + right * cos(a) * (radii[q] as float) + up * sin(a) * (radii[q] as float) * flat)
			rings.append(ring)
			centres.append(c)
	_skin(rings, centres, func(_p, _n): return surf)


func limb(points: Array, radii: Array, segs: int, surf: int, xf := Transform3D.IDENTITY, sub := 4) -> void:
	## A body part along a bent path (an arm, a leg): the radius changes point to point, the
	## path is curved through the points, and the ends are rounded off
	var pts: Array = []
	var rs: Array = []
	var n := points.size()
	for i in n - 1:
		for k in sub:
			var t := float(k) / sub
			var p0: Vector3 = points[maxi(i - 1, 0)]
			var p1: Vector3 = points[i]
			var p2: Vector3 = points[i + 1]
			var p3: Vector3 = points[mini(i + 2, n - 1)]
			pts.append(xf * Vector3(_catmull(p0.x, p1.x, p2.x, p3.x, t), _catmull(p0.y, p1.y, p2.y, p3.y, t), _catmull(p0.z, p1.z, p2.z, p3.z, t)))
			rs.append(lerpf(radii[i], radii[i + 1], t))
	pts.append(xf * (points[-1] as Vector3))
	rs.append(radii[-1])
	var rings: Array = []
	var centres: Array = []
	var up_ref := Vector3.UP
	var count := pts.size()
	var prev_right := Vector3.ZERO
	for i in count:
		var p: Vector3 = pts[i]
		var tan: Vector3 = ((pts[mini(i + 1, count - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var right := tan.cross(up_ref)
		if right.length() < 0.2:
			right = tan.cross(Vector3.FORWARD)
		right = right.normalized()
		if prev_right != Vector3.ZERO and right.dot(prev_right) < 0.0:
			right = -right
		prev_right = right
		var up := right.cross(tan).normalized()
		var r: float = rs[i]
		var steps := [[0.0, r]]
		if i == 0:
			steps = [[-r * 0.95, r * 0.15], [-r * 0.7, r * 0.72], [0.0, r]]
		elif i == count - 1:
			steps = [[0.0, r], [r * 0.7, r * 0.72], [r * 0.95, r * 0.15]]
		for st in steps:
			var c: Vector3 = p + tan * (st[0] as float)
			var ring := PackedVector3Array()
			for j in segs:
				var a := TAU * j / segs
				ring.append(c + (right * cos(a) + up * sin(a)) * (st[1] as float))
			rings.append(ring)
			centres.append(c)
	_skin(rings, centres, func(_p, _n): return surf)


func blob(centre: Vector3, radii: Vector3, segs: int, pick: Callable, xf := Transform3D.IDENTITY) -> void:
	## An egg / ellipsoid (a head, a helmet, a hand) with its long axis up. `pick` may return
	## -1 to leave a face out (the face opening of a helmet).
	var st: Array = []
	var rows := 10
	for k in rows + 1:
		var a := PI * float(k) / rows          # 0 at the bottom .. PI at the top
		var r := sin(a)
		st.append([-cos(a) * radii.y, maxf(r * radii.x, 0.002), maxf(r * radii.z, 0.002), 0.0])
	# Built along Z (up), then stood upright: local Z -> up, local Y -> forward (-Z)
	var b := Basis(Vector3.RIGHT, -PI * 0.5)
	loft(st, rows * 2, segs, pick, xf * Transform3D(b, centre))


func blade(root: Vector3, tip: Vector3, chord: float, thick: float, surf: int, xf := Transform3D.IDENTITY, tip_chord := -1.0, chord_dir := Vector3.ZERO) -> void:
	## A rotor blade or a fin: a thin airfoil from root to tip. The chord lies along
	## `chord_dir` (default: level, across the blade)
	var along := (tip - root)
	var stations: Array = []
	var tc := chord if tip_chord < 0.0 else tip_chord
	var length := along.length()
	# Built along Z, then turned to point root -> tip
	stations = [[0.0, chord * 0.5, thick * 0.5, 0.0], [length * 0.04, chord * 0.5, thick * 0.5, 0.0],
		[length * 0.96, tc * 0.5, thick * 0.4, 0.0], [length, tc * 0.25, thick * 0.2, 0.0]]
	var dir := along.normalized()
	var side := Vector3.UP.cross(dir)
	if chord_dir != Vector3.ZERO:
		side = chord_dir - dir * chord_dir.dot(dir)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := dir.cross(side).normalized()
	var b := Basis(side, up, dir)
	loft(stations, 6, 12, func(_p, _n): return surf, xf * Transform3D(b, root), 2.0)


# --- Build ----------------------------------------------------------------------------

func commit() -> ArrayMesh:
	# Smooth normals: each vertex averages the (area-weighted) faces around it
	var normals := PackedVector3Array()
	normals.resize(_verts.size())
	for f in _faces:
		var a: Vector3 = _verts[f[0]]
		var b: Vector3 = _verts[f[1]]
		var c: Vector3 = _verts[f[2]]
		var fn := -(b - a).cross(c - a)        # faces wind inward (Godot), so this points out
		for k in 3:
			normals[f[k]] += fn
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length() > 1e-9 else Vector3.UP
	var mesh := ArrayMesh.new()
	for s in _mats.size():
		var remap := {}
		var v := PackedVector3Array()
		var nrm := PackedVector3Array()
		var custom := PackedFloat32Array()
		var idx := PackedInt32Array()
		for f in _faces:
			if f[3] != s:
				continue
			for k in 3:
				var gi: int = f[k]
				if not remap.has(gi):
					remap[gi] = v.size()
					v.append(_verts[gi])
					nrm.append(normals[gi])
					custom.append_array([normals[gi].x, normals[gi].y, normals[gi].z])
				idx.append(remap[gi])
		if idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[s])
	return mesh


# --- Internals ------------------------------------------------------------------------

func _skin(rings: Array, centres: Array, pick: Callable) -> void:
	var base := _verts.size()
	var segs: int = (rings[0] as PackedVector3Array).size()
	for r in rings:
		_verts.append_array(r)
	for i in rings.size() - 1:
		for j in segs:
			var a := base + i * segs + j
			var b := base + i * segs + (j + 1) % segs
			var c := base + (i + 1) * segs + (j + 1) % segs
			var d := base + (i + 1) * segs + j
			var centre: Vector3 = ((centres[i] as Vector3) + (centres[i + 1] as Vector3)) * 0.5
			var mid := (_verts[a] + _verts[b] + _verts[c] + _verts[d]) * 0.25
			var surf: int = pick.call(mid, (mid - centre).normalized())
			if surf < 0:
				continue
			_tri(a, b, c, centre, surf)
			_tri(a, c, d, centre, surf)


func _tri(a: int, b: int, c: int, centre: Vector3, surf: int) -> void:
	var pa := _verts[a]
	var pb := _verts[b]
	var pc := _verts[c]
	var n := (pb - pa).cross(pc - pa)
	if n.length() < 1e-10:
		return
	if n.dot((pa + pb + pc) / 3.0 - centre) > 0.0:
		_faces.append([a, c, b, surf])
	else:
		_faces.append([a, b, c, surf])


static func _st(stations: Array, i: int, c: int) -> float:
	var row: Array = stations[clampi(i, 0, stations.size() - 1)]
	if c == 4:
		return row[4] if row.size() > 4 else 0.0
	# Past the ends: carry the slope on, so the curve doesn't flatten out there
	if i < 0 and c == 0:
		return 2.0 * float(stations[0][0]) - float(stations[1][0])
	if i >= stations.size() and c == 0:
		return 2.0 * float(stations[-1][0]) - float(stations[-2][0])
	return row[c]


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
