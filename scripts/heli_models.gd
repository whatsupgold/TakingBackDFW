class_name HeliModels
extends RefCounted
## The helicopters in the smooth, realistic look (see SmoothMesh): curved bodies, tinted glass
## you can see the crew through, open doors, and the pilots in their seats. They keep the
## same size, rotor positions and pivots as the faceted versions in VehicleModel, so seats,
## doors, ropes and the Chinook's ramp all line up.

const I := Transform3D.IDENTITY


static func _mats(paint: Color) -> Dictionary:
	var glass := VehicleModel._pbr(Color(0.07, 0.10, 0.12, 0.45), 0.04, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inner := VehicleModel._pbr(Color(0.06, 0.06, 0.065), 0.95)
	inner.cull_mode = BaseMaterial3D.CULL_FRONT
	return {
		"paint": VehicleModel._pbr(paint, 0.55, 0.12),
		"glass": glass,
		"dark": VehicleModel._pbr(Color(0.035, 0.035, 0.04), 0.9),
		"inner": inner,
		"metal": VehicleModel._pbr(Color(0.38, 0.39, 0.40), 0.32, 0.8),
		"blade": VehicleModel._pbr(Color(0.08, 0.08, 0.085), 0.55, 0.2),
		"tire": VehicleModel._pbr(Color(0.06, 0.06, 0.06), 0.9),
		"hub": VehicleModel._pbr(Color(0.30, 0.31, 0.30), 0.5, 0.5),
		"screen": VehicleModel._screen_mat(),
		"star": VehicleModel._pbr(Color(0.62, 0.63, 0.58), 0.8),
		"missile": VehicleModel._pbr(Color(0.60, 0.60, 0.54), 0.6, 0.2),
	}


static func _surfs(sm: SmoothMesh, mats: Dictionary) -> Dictionary:
	var out := {}
	for k in mats:
		out[k] = sm.surface(mats[k])
	return out


static var _cache := {}


static func _part(parent: Node3D, key: String, mats: Dictionary, build: Callable, outline := true) -> MeshInstance3D:
	## A piece of a model, built the first time and shared after that (building takes a while)
	if not _cache.has(key):
		var sm := SmoothMesh.new()
		build.call(sm, _surfs(sm, mats))
		_cache[key] = sm.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _cache[key]
	parent.add_child(mi)
	if outline:
		UnitLook.add_outline(mi, false, false)
	else:
		mi.set_meta("no_outline", true)
	return mi


static func _commit(parent: Node3D, sm: SmoothMesh, outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = sm.commit()
	parent.add_child(mi)
	if outline:
		UnitLook.add_outline(mi, false, false)
	else:
		mi.set_meta("no_outline", true)
	return mi


static func _wheel(sm: SmoothMesh, s: Dictionary, c: Vector3, r: float, w: float) -> void:
	## A round tyre on a hub, its axle along X
	var h := w * 0.5
	sm.loft([[-h, 0.01, 0.01, 0.0], [-h, r * 0.78, r * 0.78, 0.0], [-h * 0.7, r, r, 0.0], [h * 0.7, r, r, 0.0],
		[h, r * 0.78, r * 0.78, 0.0], [h, 0.01, 0.01, 0.0]], 10, 22,
		func(p: Vector3, _n: Vector3) -> int:
			return s.hub if Vector2(p.y - c.y, p.z - c.z).length() < r * 0.55 else s.tire,
		Transform3D(Basis(Vector3.UP, PI * 0.5), c))


static func _box(sm: SmoothMesh, surf: int, centre: Vector3, size: Vector3, xf := I) -> void:
	## A small box with softly rounded edges
	sm.loft([[centre.z - size.z * 0.5, size.x * 0.5, size.y * 0.5, centre.y, centre.x],
		[centre.z + size.z * 0.5, size.x * 0.5, size.y * 0.5, centre.y, centre.x]], 1, 12,
		func(_p, _n): return surf, xf, 8.0)


static func _m240(sm: SmoothMesh, s: Dictionary, at: Vector3, side: float) -> void:
	## A door gun on its mount, pointing out to one side
	sm.limb([at, at + Vector3(side * 0.22, 0.0, 0.0)], [0.025, 0.025], 8, s.metal)
	_box(sm, s.dark, at + Vector3(side * 0.32, 0.03, 0.0), Vector3(0.24, 0.12, 0.09))
	sm.limb([at + Vector3(side * 0.42, 0.04, 0.0), at + Vector3(side * 0.95, 0.04, 0.0)], [0.02, 0.018], 8, s.dark)
	_box(sm, s.dark, at + Vector3(side * 0.28, -0.12, 0.08), Vector3(0.14, 0.14, 0.10))


static func _cockpit_glass(p: Vector3, s: Dictionary, post_y: float) -> int:
	return s.paint if absf(p.x) < 0.035 and p.y > post_y else s.glass


# --- UH-60 Black Hawk -----------------------------------------------------------------

static func black_hawk() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "BlackHawk"
	var mats := _mats(Color(0.13, 0.15, 0.12))
	_part(v, "bh_body", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		# Fuselage: sloping nose, the wide flat-sided cabin, the long boom up to the tail
		var body := [[-3.74, 0.10, 0.12, 1.22], [-3.60, 0.50, 0.42, 1.28], [-3.30, 0.82, 0.70, 1.40],
			[-2.85, 1.04, 0.90, 1.58], [-2.35, 1.15, 0.98, 1.74], [-1.80, 1.19, 1.00, 1.80],
			[1.70, 1.20, 1.00, 1.82], [2.35, 1.00, 0.86, 1.95], [2.95, 0.70, 0.62, 2.10],
			[4.00, 0.45, 0.45, 2.18], [6.00, 0.32, 0.34, 2.24], [7.60, 0.26, 0.28, 2.32], [7.85, 0.05, 0.05, 2.34]]
		sm.loft(body, 160, 48, func(p: Vector3, _n: Vector3) -> int:
			# Cabin doors slid open
			if absf(p.x) > 0.9 and p.z > -0.98 and p.z < 0.98 and p.y > 0.95 and p.y < 2.42:
				return -1
			if p.z < -1.95:
				if p.z < -2.55 and p.y > 1.62:
					return _cockpit_glass(p, s, 1.6)                   # windscreen
				if p.z < -3.0 and p.y > 1.0 and p.y < 1.45 and absf(p.x) > 0.1:
					return s.glass                                     # chin windows
				if absf(p.x) > 0.85 and p.y > 1.58 and p.y < 2.45:
					return s.glass                                     # cockpit door windows
			if absf(p.x) > 0.9 and p.z > -1.65 and p.z < -1.10 and p.y > 1.65 and p.y < 2.30:
				return s.glass                                         # crew chief windows
			if absf(p.x) > 0.95 and p.z > 1.15 and p.z < 1.55 and p.y > 1.85 and p.y < 2.30:
				return s.glass                                         # rear cabin windows
			if absf(p.x) > 1.1 and p.z > 1.85 and p.z < 2.05 and p.y > 2.0 and p.y < 2.3:
				return s.star
			return s.paint, I, 3.0)
		# Inside: walls, floor, a troop bench along the back wall
		sm.loft([[-3.10, 0.02, 0.02, 1.55], [-2.90, 0.85, 0.75, 1.60], [-1.80, 1.12, 0.94, 1.80],
			[1.60, 1.13, 0.94, 1.82], [2.30, 0.90, 0.76, 1.95], [2.50, 0.02, 0.02, 2.0]], 30, 28,
			func(_p, _n): return s.inner, I, 3.0)
		_box(sm, s.dark, Vector3(0, 0.90, -0.4), Vector3(2.1, 0.06, 4.2))
		_box(sm, s.dark, Vector3(0, 1.20, 1.45), Vector3(2.0, 0.10, 0.45))
		_box(sm, s.dark, Vector3(0, 1.55, 1.70), Vector3(2.0, 0.65, 0.08))
		# The doors, slid back along the sides
		for x in [-1.23, 1.23]:
			sm.loft([[0.98, 0.03, 0.74, 1.68, x], [1.96, 0.03, 0.74, 1.68, x]], 1, 12,
				func(p: Vector3, _n: Vector3) -> int: return s.glass if p.y > 1.95 and p.y < 2.3 and p.z > 1.2 and p.z < 1.7 else s.paint, I, 8.0)
		# Instrument panel and centre console
		sm.loft([[-3.05, 0.02, 0.02, 1.72], [-3.00, 0.85, 0.10, 1.74], [-2.80, 0.90, 0.12, 1.72], [-2.72, 0.02, 0.02, 1.70]], 8, 20,
			func(_p, _n): return s.dark, I, 4.0)
		for x in [-0.66, -0.22, 0.22, 0.66]:
			sm.loft([[-2.74, 0.12, 0.09, 1.72, x], [-2.73, 0.12, 0.09, 1.72, x]], 1, 4,
				func(_p, n: Vector3): return s.screen if n.z > 0.5 else s.dark, I, 8.0)
		sm.loft([[-2.75, 0.13, 0.25, 1.20], [-1.85, 0.13, 0.15, 1.10]], 4, 12, func(_p, _n): return s.dark, I, 5.0)
		# Engine nacelles either side of the roof, the gearbox hump between them, exhausts
		for x in [-0.62, 0.62]:
			sm.loft([[-0.78, 0.02, 0.02, 3.0, x], [-0.74, 0.30, 0.30, 3.0, x], [-0.45, 0.38, 0.38, 3.0, x],
				[1.90, 0.38, 0.38, 3.0, x], [2.30, 0.30, 0.30, 3.0, x], [2.45, 0.02, 0.02, 3.0, x]], 24, 20,
				func(_p, n: Vector3): return s.dark if absf(n.z) > 0.85 else s.paint)
			sm.limb([Vector3(x * 1.05, 3.0, 2.3), Vector3(x * 1.45, 3.05, 2.75)], [0.20, 0.17], 14, s.paint)
		sm.loft([[-1.95, 0.02, 0.02, 2.80], [-1.70, 0.45, 0.25, 2.86], [0.20, 0.55, 0.34, 2.95],
			[2.60, 0.40, 0.25, 2.85], [3.20, 0.05, 0.05, 2.60]], 24, 24, func(_p, _n): return s.paint, I, 2.5)
		sm.limb([Vector3(0, 3.20, 0.10), Vector3(0, 3.92, 0.10)], [0.15, 0.13], 14, s.metal)
		# Wire cutters over the cockpit and under the nose
		sm.blade(Vector3(0, 2.70, -2.55), Vector3(0, 3.05, -2.35), 0.10, 0.02, s.metal, I, 0.04, Vector3.BACK)
		sm.blade(Vector3(0, 0.80, -3.20), Vector3(0, 0.55, -3.05), 0.10, 0.02, s.metal, I, 0.04, Vector3.BACK)
		# Tail: fin, the big stabilator, tail wheel
		sm.blade(Vector3(0, 2.25, 7.00), Vector3(0, 4.05, 8.35), 1.20, 0.14, s.paint, I, 0.75, Vector3.BACK)
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(0, 2.20, 7.90), Vector3(x * 1.70, 2.20, 7.90), 0.80, 0.08, s.paint, I, 0.62, Vector3.BACK)
		sm.limb([Vector3(0, 2.08, 7.40), Vector3(0, 0.32, 7.55)], [0.06, 0.05], 10, s.metal)
		sm.limb([Vector3(0, 2.10, 6.70), Vector3(0, 0.80, 7.50)], [0.04, 0.035], 8, s.metal)
		_wheel(sm, s, Vector3(0, 0.22, 7.55), 0.22, 0.14)
		# Main gear: struts and drag beams out to the wheels
		for x in [-1.0, 1.0]:
			sm.limb([Vector3(x * 0.95, 0.95, -1.75), Vector3(x * 1.45, 0.40, -1.70)], [0.07, 0.06], 12, s.paint)
			sm.limb([Vector3(x * 1.00, 1.05, -1.15), Vector3(x * 1.45, 0.42, -1.66)], [0.05, 0.05], 10, s.metal)
			_wheel(sm, s, Vector3(x * 1.45, 0.36, -1.70), 0.36, 0.24)
			_m240(sm, s, Vector3(x * 1.05, 1.62, -0.55), x)
	)
	# Pilots side by side
	VehicleModel.add_pilot(v, Vector3(0.50, 1.22, -2.25), "skin_b", true)
	VehicleModel.add_pilot(v, Vector3(-0.50, 1.22, -2.25), "skin_a", false)
	# Main rotor: four blades
	var rotor := v._pivot(Vector3(0, 3.95, 0.10))
	_part(rotor, "bh_rotor", mats, func(rm: SmoothMesh, rs: Dictionary) -> void:
		for k in 4:
			var dir := Vector3(cos(TAU * k / 4.0), 0.0, sin(TAU * k / 4.0))
			rm.blade(dir * 0.50, dir * 8.20 + Vector3.DOWN * 0.15, 0.53, 0.07, rs.blade, I, 0.40)
			rm.limb([dir * 0.15, dir * 0.62], [0.09, 0.07], 10, rs.metal)
		rm.loft([[-0.12, 0.05, 0.05, 0.0], [-0.10, 0.36, 0.36, 0.0], [0.10, 0.36, 0.36, 0.0], [0.18, 0.12, 0.12, 0.0], [0.30, 0.02, 0.02, 0.0]], 10, 20,
			func(_p, _n): return rs.metal, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	)
	v.spinners.append([rotor, Vector3.UP, 3.2])
	# Tail rotor, canted on the right of the fin
	var tail := v._pivot(Vector3(0.22, 3.75, 8.20))
	_part(tail, "bh_tail", mats, func(tm: SmoothMesh, ts: Dictionary) -> void:
		for k in 4:
			var a := TAU * k / 4.0
			var dir := Vector3(0, cos(a), sin(a))
			tm.blade(dir * 0.12, dir * 1.35, 0.20, 0.03, ts.blade, I, 0.16, Vector3(0, -sin(a), cos(a)))
		tm.limb([Vector3(-0.10, 0, 0), Vector3(0.10, 0, 0)], [0.10, 0.08], 12, ts.metal)
	)
	v.spinners.append([tail, Vector3.RIGHT, 9.0])
	return v


# --- CH-47 Chinook ----------------------------------------------------------------------

static func chinook() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Chinook"
	var mats := _mats(Color(0.27, 0.29, 0.22))
	_part(v, "ch_body", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		# The long, round-cornered box of a fuselage, open at the back over the ramp
		var body := [[-8.30, 0.30, 0.30, 1.30], [-8.15, 0.80, 0.70, 1.40], [-7.85, 1.20, 1.05, 1.58],
			[-7.40, 1.42, 1.30, 1.80], [-6.80, 1.50, 1.42, 1.95], [-6.00, 1.52, 1.45, 2.02],
			[5.60, 1.52, 1.45, 2.02], [6.60, 1.48, 1.38, 2.10], [7.00, 1.45, 1.32, 2.14]]
		sm.loft(body, 160, 56, func(p: Vector3, _n: Vector3) -> int:
			if p.z < -6.25:
				if p.z < -6.95 and p.y > 2.15 + (p.z + 6.95) * 0.35:
					return _cockpit_glass(p, s, 2.2)                   # windscreen
				if p.z < -7.6 and p.y > 1.05 and p.y < 1.75 and absf(p.x) > 0.12:
					return s.glass                                     # chin windows
				if absf(p.x) > 1.2 and p.y > 2.2 and p.y < 3.05:
					return s.glass                                     # cockpit side windows
			if p.x > 1.35 and p.z > -5.55 and p.z < -4.50 and p.y > 0.75 and p.y < 2.6:
				return -1                                              # crew door, open
			if p.x < -1.35 and p.z > -5.40 and p.z < -4.60 and p.y > 1.80 and p.y < 2.5:
				return -1                                              # gun window, open
			if absf(p.x) > 1.38 and p.y > 2.25 and p.y < 2.62 and p.z > -3.2 and p.z < 5.0 and fposmod(p.z + 3.2, 1.5) < 0.42:
				return s.glass                                         # cabin windows
			if absf(p.x) > 1.4 and p.z > 1.9 and p.z < 2.4 and p.y > 1.45 and p.y < 1.95:
				return s.star
			return s.paint, I, 3.2)
		# Inside: walls (seen through the ramp, the door and the glass) and the floor
		sm.loft([[-7.85, 0.02, 0.02, 1.70], [-7.50, 1.10, 1.00, 1.75], [-6.80, 1.42, 1.34, 1.95],
			[5.60, 1.44, 1.38, 2.02], [6.98, 1.38, 1.26, 2.14]], 40, 28, func(_p, _n): return s.inner, I, 3.2)
		_box(sm, s.dark, Vector3(0, 0.78, 0.0), Vector3(2.6, 0.06, 13.6))
		# Troop seats down both walls
		for x in [-1.15, 1.15]:
			_box(sm, s.dark, Vector3(x, 1.20, 0.6), Vector3(0.45, 0.08, 9.5))
			_box(sm, s.dark, Vector3(x * 1.12, 1.62, 0.6), Vector3(0.06, 0.70, 9.5))
		# The wall over the ramp opening, at the top of the back
		sm.loft([[6.96, 1.36, 0.30, 3.12], [7.02, 1.36, 0.30, 3.12]], 1, 20, func(_p, _n): return s.paint, I, 4.0)
		# Instrument panel and console
		sm.loft([[-7.45, 0.02, 0.02, 2.20], [-7.40, 1.05, 0.11, 2.22], [-7.20, 1.10, 0.13, 2.20], [-7.12, 0.02, 0.02, 2.18]], 8, 20,
			func(_p, _n): return s.dark, I, 4.0)
		for x in [-0.85, -0.42, 0.42, 0.85]:
			sm.loft([[-7.14, 0.13, 0.10, 2.20, x], [-7.13, 0.13, 0.10, 2.20, x]], 1, 4,
				func(_p, n: Vector3): return s.screen if n.z > 0.5 else s.dark, I, 8.0)
		sm.loft([[-7.20, 0.15, 0.30, 1.40], [-6.10, 0.15, 0.18, 1.30]], 4, 12, func(_p, _n): return s.dark, I, 5.0)
		# Fuel sponsons down both sides
		for x in [-1.62, 1.62]:
			sm.loft([[-2.60, 0.05, 0.06, 1.0, x], [-2.20, 0.32, 0.48, 1.0, x], [4.20, 0.34, 0.50, 1.0, x], [4.80, 0.08, 0.10, 1.0, x]], 30, 20,
				func(_p, _n): return s.paint, I, 3.0)
		# Front pylon, the tunnel along the roof, the tall aft pylon, the engines on its sides
		sm.loft([[-7.30, 0.05, 0.05, 3.15], [-6.90, 0.55, 0.35, 3.35], [-6.20, 0.72, 0.62, 3.55], [-5.20, 0.70, 0.60, 3.55],
			[-4.30, 0.45, 0.35, 3.40], [-3.90, 0.05, 0.05, 3.30]], 30, 24, func(_p, _n): return s.paint, I, 2.5)
		sm.limb([Vector3(0, 4.00, -6.0), Vector3(0, 4.60, -6.0)], [0.22, 0.20], 14, s.metal)
		sm.loft([[-4.60, 0.05, 0.05, 3.42], [-4.20, 0.42, 0.22, 3.45], [3.80, 0.42, 0.22, 3.45], [4.10, 0.05, 0.05, 3.42]], 20, 16,
			func(_p, _n): return s.paint, I, 2.5)
		sm.loft([[3.20, 0.10, 0.10, 3.40], [3.80, 0.70, 0.55, 3.90], [4.80, 0.85, 1.05, 4.35], [6.20, 0.85, 1.25, 4.55],
			[7.00, 0.75, 1.15, 4.60], [7.20, 0.10, 0.10, 4.50]], 30, 24, func(_p, _n): return s.paint, I, 2.6)
		sm.limb([Vector3(0, 5.60, 5.6), Vector3(0, 6.20, 5.6)], [0.22, 0.20], 14, s.metal)
		for x in [-1.38, 1.38]:
			sm.loft([[3.55, 0.02, 0.02, 3.90, x], [3.60, 0.42, 0.42, 3.90, x], [3.90, 0.50, 0.50, 3.90, x], [6.40, 0.50, 0.50, 3.90, x],
				[6.90, 0.42, 0.42, 3.90, x], [7.00, 0.02, 0.02, 3.90, x]], 24, 22,
				func(_p, n: Vector3): return s.dark if absf(n.z) > 0.85 else s.paint)
			sm.limb([Vector3(x * 0.55, 3.95, 4.6), Vector3(x * 0.95, 3.92, 4.6)], [0.12, 0.12], 10, s.paint)
			sm.limb([Vector3(x * 0.55, 3.95, 6.0), Vector3(x * 0.95, 3.92, 6.0)], [0.12, 0.12], 10, s.paint)
		# Landing gear: two up front, two under the sponsons
		for x in [-1.0, 1.0]:
			sm.limb([Vector3(x * 1.05, 0.80, -4.6), Vector3(x * 1.20, 0.38, -4.6)], [0.08, 0.07], 12, s.metal)
			_wheel(sm, s, Vector3(x * 1.20, 0.35, -4.6), 0.35, 0.30)
			sm.limb([Vector3(x * 1.72, 0.70, 4.4), Vector3(x * 1.72, 0.38, 4.4)], [0.08, 0.07], 12, s.metal)
			_wheel(sm, s, Vector3(x * 1.72, 0.35, 4.4), 0.35, 0.34)
		_m240(sm, s, Vector3(1.40, 1.95, -5.0), 1.0)
		_m240(sm, s, Vector3(-1.40, 1.95, -5.0), -1.0)
	)
	VehicleModel.add_pilot(v, Vector3(0.62, 1.30, -6.55), "skin_a", true)
	VehicleModel.add_pilot(v, Vector3(-0.62, 1.30, -6.55), "skin_b", false)
	# Rear ramp, hinged at the cabin floor
	var r := v._pivot(Vector3(0, 0.75, 7.0))
	v.ramp = r
	r.rotation.x = VehicleModel.RAMP_OPEN
	_part(r, "ch_ramp", mats, func(ram: SmoothMesh, rps: Dictionary) -> void:
		ram.loft([[0.0, 1.30, 0.08, 0.0], [2.60, 1.30, 0.08, 0.0]], 2, 20, func(_p, n: Vector3): return rps.dark if n.y > 0.7 else rps.paint, I, 8.0)
		for z in [0.6, 1.3, 2.0]:
			ram.limb([Vector3(-1.2, 0.09, z), Vector3(1.2, 0.09, z)], [0.03, 0.03], 8, rps.metal)
	)
	# Tandem rotors, three blades each, turning opposite ways
	for hub in [[Vector3(0, 4.65, -6.0), 3.0], [Vector3(0, 6.25, 5.6), -3.0]]:
		var rotor := v._pivot(hub[0])
		_part(rotor, "ch_rotor", mats, func(rm: SmoothMesh, rs: Dictionary) -> void:
			for k in 3:
				var a := TAU * k / 3.0 + 0.3
				var dir := Vector3(cos(a), 0.0, sin(a))
				rm.blade(dir * 0.55, dir * 9.10 + Vector3.DOWN * 0.15, 0.64, 0.08, rs.blade, I, 0.5)
				rm.limb([dir * 0.15, dir * 0.70], [0.10, 0.08], 10, rs.metal)
			rm.loft([[-0.15, 0.05, 0.05, 0.0], [-0.12, 0.42, 0.42, 0.0], [0.15, 0.42, 0.42, 0.0], [0.30, 0.15, 0.15, 0.0], [0.40, 0.02, 0.02, 0.0]], 10, 20,
				func(_p, _n): return rs.metal, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
		)
		v.spinners.append([rotor, Vector3.UP, hub[1]])
	return v


# --- AH-64D Apache ----------------------------------------------------------------------

static func apache() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Apache"
	var mats := _mats(Color(0.17, 0.19, 0.16))
	_part(v, "ah_body", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		# Narrow, slab-sided fuselage; open on top under the canopy
		var body := [[-4.15, 0.12, 0.12, 1.30], [-4.00, 0.32, 0.36, 1.30], [-3.60, 0.48, 0.52, 1.38], [-2.80, 0.55, 0.62, 1.48],
			[-1.00, 0.60, 0.70, 1.58], [0.80, 0.62, 0.72, 1.65], [1.90, 0.55, 0.62, 1.72], [2.70, 0.38, 0.45, 1.85],
			[4.50, 0.26, 0.30, 1.90], [6.50, 0.20, 0.24, 1.92], [7.70, 0.18, 0.20, 1.96], [7.95, 0.03, 0.03, 1.97]]
		sm.loft(body, 120, 36, func(p: Vector3, n: Vector3) -> int:
			if p.z > -3.80 and p.z < -0.45 and n.y > 0.35:
				return -1
			if absf(p.x) > 0.5 and p.z > 1.3 and p.z < 1.7 and p.y > 1.4 and p.y < 1.8:
				return s.star
			return s.paint, I, 3.5)
		# Tandem canopy: gunner in front and low, pilot behind and higher
		sm.loft([[-3.85, 0.02, 0.02, 1.95], [-3.55, 0.38, 0.30, 2.00], [-2.60, 0.47, 0.42, 2.06], [-2.15, 0.47, 0.45, 2.10],
			[-1.95, 0.47, 0.62, 2.25], [-0.85, 0.45, 0.66, 2.32], [-0.45, 0.30, 0.40, 2.40], [-0.30, 0.03, 0.03, 2.45]], 50, 32,
			func(p: Vector3, n: Vector3) -> int:
				if n.y < -0.1:
					return -1
				if absf(p.x) < 0.03 or absf(p.z + 2.05) < 0.05:
					return s.paint                                     # frame
				return s.glass, I, 3.5)
		sm.loft([[-3.80, 0.02, 0.02, 1.40], [-3.50, 0.46, 0.45, 1.45], [-1.00, 0.55, 0.60, 1.58], [-0.50, 0.02, 0.02, 1.62]], 20, 24,
			func(_p, _n): return s.inner, I, 3.5)
		_box(sm, s.dark, Vector3(0, 1.95, -3.40), Vector3(0.6, 0.18, 0.18))      # gunner's sight console
		_box(sm, s.dark, Vector3(0, 2.25, -1.95), Vector3(0.7, 0.20, 0.14))      # pilot's panel
		for z in [-3.30, -1.87]:
			sm.loft([[z - 0.005, 0.18, 0.06, 1.97 if z < -2.0 else 2.27], [z + 0.005, 0.18, 0.06, 1.97 if z < -2.0 else 2.27]], 1, 4,
				func(_p, n: Vector3): return s.screen if n.z > 0.5 else s.dark, I, 8.0)
		# Sensor turret on the nose, 30 mm chain gun under the chin
		sm.blob(Vector3(0, 1.20, -4.18), Vector3(0.30, 0.28, 0.30), 20, func(_p: Vector3, n: Vector3) -> int:
			return s.glass if n.z < -0.75 and absf(n.x) > 0.12 else s.dark)
		sm.blob(Vector3(0, 0.88, -2.70), Vector3(0.22, 0.17, 0.24), 16, func(_p, _n): return s.dark)
		sm.limb([Vector3(0, 0.84, -2.85), Vector3(0, 0.80, -3.80)], [0.075, 0.045], 10, s.dark)
		# Engines, the spine between them, the exhaust deflectors
		for x in [-0.95, 0.95]:
			sm.loft([[-0.80, 0.02, 0.02, 2.35, x], [-0.72, 0.30, 0.32, 2.35, x], [-0.40, 0.38, 0.40, 2.35, x], [1.30, 0.38, 0.40, 2.35, x],
				[1.80, 0.30, 0.32, 2.38, x], [1.95, 0.02, 0.02, 2.40, x]], 24, 20,
				func(_p, n: Vector3): return s.dark if n.z < -0.85 else s.paint, I, 2.5)
			sm.limb([Vector3(x * 1.0, 2.42, 1.75), Vector3(x * 1.22, 2.48, 2.25)], [0.21, 0.18], 14, s.paint)
		sm.loft([[-0.70, 0.02, 0.02, 2.25], [-0.50, 0.42, 0.28, 2.30], [1.80, 0.45, 0.30, 2.32], [2.60, 0.05, 0.05, 2.15]], 24, 20,
			func(_p, _n): return s.paint, I, 2.5)
		sm.limb([Vector3(0, 2.50, 0.25), Vector3(0, 3.40, 0.25)], [0.14, 0.12], 14, s.metal)
		# Longbow radar dome over the rotor (it doesn't turn)
		sm.limb([Vector3(0, 3.40, 0.25), Vector3(0, 3.78, 0.25)], [0.09, 0.09], 10, s.metal)
		sm.blob(Vector3(0, 3.92, 0.25), Vector3(0.46, 0.20, 0.46), 24, func(_p, _n): return s.paint)
		# Stub wings: rocket pods inboard, four Hellfires each side outboard
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(x * 0.45, 1.68, 0.15), Vector3(x * 2.05, 1.64, 0.15), 0.70, 0.12, s.paint, I, 0.52, Vector3.BACK)
			sm.limb([Vector3(x * 1.05, 1.62, 0.10), Vector3(x * 1.05, 1.36, 0.10)], [0.05, 0.05], 8, s.paint)
			sm.loft([[-0.82, 0.02, 0.02, 1.18, x * 1.05], [-0.78, 0.21, 0.21, 1.18, x * 1.05], [0.72, 0.21, 0.21, 1.18, x * 1.05], [0.80, 0.12, 0.12, 1.18, x * 1.05]], 12, 18,
				func(_p, n: Vector3): return s.dark if n.z < -0.8 else s.paint)
			sm.limb([Vector3(x * 1.75, 1.62, 0.10), Vector3(x * 1.75, 1.38, 0.10)], [0.05, 0.05], 8, s.paint)
			_box(sm, s.dark, Vector3(x * 1.75, 1.13, 0.10), Vector3(0.40, 0.06, 1.15))
			for y in [1.25, 1.00]:
				for dx in [-0.12, 0.12]:
					var mx: float = x * 1.75 + dx
					sm.limb([Vector3(mx, y, 0.75), Vector3(mx, y, -0.45), Vector3(mx, y, -0.55)], [0.085, 0.085, 0.06], 12, s.missile)
		# Tail: fin, stabilator low at the back, tail wheel
		sm.blade(Vector3(0, 1.95, 6.90), Vector3(0, 3.35, 7.85), 1.00, 0.12, s.paint, I, 0.60, Vector3.BACK)
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(0, 1.88, 7.35), Vector3(x * 1.05, 1.88, 7.35), 0.60, 0.06, s.paint, I, 0.50, Vector3.BACK)
		sm.limb([Vector3(0, 1.78, 7.25), Vector3(0, 0.28, 7.32)], [0.06, 0.05], 10, s.metal)
		_wheel(sm, s, Vector3(0, 0.20, 7.32), 0.20, 0.12)
		# Main gear
		for x in [-1.0, 1.0]:
			sm.limb([Vector3(x * 0.50, 1.00, -1.30), Vector3(x * 1.10, 0.38, -1.30)], [0.07, 0.06], 12, s.paint)
			_wheel(sm, s, Vector3(x * 1.10, 0.34, -1.30), 0.34, 0.20)
	)
	VehicleModel.add_pilot(v, Vector3(0, 1.30, -2.80), "skin_a", false)      # gunner
	VehicleModel.add_pilot(v, Vector3(0, 1.62, -1.45), "skin_b", true)       # pilot
	# Main rotor: four blades
	var rotor := v._pivot(Vector3(0, 3.40, 0.25))
	_part(rotor, "ah_rotor", mats, func(rm: SmoothMesh, rs: Dictionary) -> void:
		for k in 4:
			var dir := Vector3(cos(TAU * k / 4.0 + 0.3), 0.0, sin(TAU * k / 4.0 + 0.3))
			rm.blade(dir * 0.42, dir * 7.30 + Vector3.DOWN * 0.12, 0.53, 0.07, rs.blade, I, 0.40)
			rm.limb([dir * 0.12, dir * 0.55], [0.08, 0.06], 10, rs.metal)
		rm.loft([[-0.10, 0.05, 0.05, 0.0], [-0.08, 0.32, 0.32, 0.0], [0.10, 0.32, 0.32, 0.0], [0.16, 0.10, 0.10, 0.0]], 8, 20,
			func(_p, _n): return rs.metal, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	)
	v.spinners.append([rotor, Vector3.UP, 3.2])
	# Tail rotor on the left: four blades set as a scissor
	var tail := v._pivot(Vector3(-0.22, 3.10, 7.65))
	_part(tail, "ah_tail", mats, func(tm: SmoothMesh, ts: Dictionary) -> void:
		for a in [0.0, 0.96, PI, PI + 0.96]:
			var dir := Vector3(0, cos(a), sin(a))
			tm.blade(dir * 0.10, dir * 1.40, 0.22, 0.03, ts.blade, I, 0.18, Vector3(0, -sin(a), cos(a)))
		tm.limb([Vector3(-0.10, 0, 0), Vector3(0.10, 0, 0)], [0.09, 0.07], 12, ts.metal)
	)
	v.spinners.append([tail, Vector3.RIGHT, 9.0])
	return v


# --- A-10 Thunderbolt II -----------------------------------------------------------------

static func a10() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "A10"
	var mats := _mats(Color(0.30, 0.32, 0.34))         # "gunship gray"
	_part(v, "a10_body", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		# Fuselage: blunt gun nose, the cockpit, tapering to the tail; open under the canopy
		var body := [[-8.05, 0.05, 0.05, 1.62], [-7.70, 0.32, 0.35, 1.70], [-7.00, 0.55, 0.62, 1.85], [-5.60, 0.70, 0.78, 2.00],
			[-3.50, 0.72, 0.80, 2.05], [1.00, 0.72, 0.80, 2.05], [3.50, 0.60, 0.65, 2.15], [5.80, 0.42, 0.45, 2.30],
			[7.30, 0.28, 0.30, 2.42], [7.75, 0.05, 0.05, 2.45]]
		sm.loft(body, 110, 36, func(p: Vector3, n: Vector3) -> int:
			if p.z > -5.45 and p.z < -3.45 and n.y > 0.45:
				return -1
			if absf(p.x) > 0.6 and p.z > 1.6 and p.z < 2.1 and p.y > 1.8 and p.y < 2.3:
				return s.star
			return s.paint, I, 2.6)
		# Bubble canopy, the windscreen bow across it
		sm.loft([[-5.65, 0.02, 0.02, 2.62], [-5.30, 0.38, 0.32, 2.66], [-4.40, 0.43, 0.44, 2.72], [-3.60, 0.36, 0.32, 2.72], [-3.30, 0.02, 0.02, 2.66]], 30, 28,
			func(p: Vector3, n: Vector3) -> int:
				if n.y < -0.2:
					return -1
				if absf(p.z + 5.15) < 0.05:
					return s.paint
				return s.glass, I, 2.4)
		sm.loft([[-5.5, 0.02, 0.02, 2.3], [-5.3, 0.55, 0.45, 2.3], [-3.6, 0.55, 0.45, 2.35], [-3.4, 0.02, 0.02, 2.35]], 12, 16,
			func(_p, _n): return s.inner, I, 2.5)
		_box(sm, s.dark, Vector3(0, 2.62, -5.05), Vector3(0.5, 0.12, 0.25))        # gunsight and panel
		# The GAU-8 barrel out of the nose
		sm.limb([Vector3(0, 1.62, -7.70), Vector3(0, 1.60, -8.45)], [0.07, 0.06], 12, s.dark)
		# Straight wings, drooped tips, landing gear pods
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(x * 0.55, 1.50, 0.30), Vector3(x * 8.30, 1.62, 0.55), 2.7, 0.34, s.paint, I, 1.8, Vector3.BACK)
			sm.blade(Vector3(x * 8.20, 1.62, 0.55), Vector3(x * 8.85, 1.42, 0.65), 1.8, 0.16, s.paint, I, 1.2, Vector3.BACK)
			sm.loft([[-1.20, 0.05, 0.05, 1.25, x * 1.90], [-0.90, 0.32, 0.30, 1.25, x * 1.90], [1.30, 0.32, 0.30, 1.28, x * 1.90], [1.70, 0.05, 0.05, 1.32, x * 1.90]], 14, 16,
				func(_p, _n): return s.paint)
			# Engines high on the back, on pylons
			sm.loft([[1.80, 0.02, 0.02, 3.10, x * 1.35], [1.86, 0.52, 0.52, 3.10, x * 1.35], [2.20, 0.58, 0.58, 3.10, x * 1.35], [4.40, 0.55, 0.55, 3.10, x * 1.35],
				[4.95, 0.42, 0.42, 3.10, x * 1.35], [5.05, 0.02, 0.02, 3.10, x * 1.35]], 24, 22,
				func(_p, n: Vector3): return s.dark if absf(n.z) > 0.85 else s.paint)
			sm.blade(Vector3(x * 0.50, 2.60, 3.30), Vector3(x * 0.95, 2.95, 3.40), 1.30, 0.12, s.paint, I, 1.10, Vector3.BACK)
			# Stores: Mavericks inboard, bombs outboard
			for px in [3.6, 5.6]:
				sm.limb([Vector3(x * px, 1.48, 0.4), Vector3(x * px, 1.32, 0.4)], [0.05, 0.05], 8, s.paint)
				sm.limb([Vector3(x * px, 1.18, 1.10), Vector3(x * px, 1.18, -0.70), Vector3(x * px, 1.18, -0.95)], [0.15, 0.15, 0.08], 14, s.missile if px < 5.0 else s.paint)
		# Tailplane and the twin fins at its tips
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(0, 2.45, 6.95), Vector3(x * 2.95, 2.45, 6.95), 1.55, 0.16, s.paint, I, 1.15, Vector3.BACK)
			sm.blade(Vector3(x * 2.88, 1.75, 6.95), Vector3(x * 2.88, 3.80, 7.30), 1.60, 0.14, s.paint, I, 1.05, Vector3.BACK)
	)
	VehicleModel.add_pilot(v, Vector3(0, 2.05, -4.25), "skin_a", false)
	# Landing gear (hidden in flight): nose gear and two mains
	var g := Node3D.new()
	v.add_child(g)
	v.gear = g
	_part(g, "a10_gear", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		for at in [Vector3(0.0, 0.0, -4.6), Vector3(-1.9, 0.0, 0.5), Vector3(1.9, 0.0, 0.5)]:
			sm.limb([at + Vector3(0, 1.25, 0), at + Vector3(0, 0.34, 0)], [0.07, 0.06], 10, s.metal)
			_wheel(sm, s, at + Vector3(0, 0.32, 0), 0.32, 0.22)
	)
	var m := Node3D.new()
	m.position = Vector3(0, 1.60, -8.1)
	v.add_child(m)
	v.muzzle = m
	return v


# --- C-130 Hercules ------------------------------------------------------------------------

static func c130(parent: Node3D) -> Array:
	## Builds the C-130 under parent; returns its four propellers (they spin around Z)
	var mats := _mats(Color(0.30, 0.33, 0.27))
	_part(parent, "c130_body", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
		# Round nose with the cockpit glass, the long box of a cabin, the upswept tail
		var body := [[-14.20, 0.10, 0.10, -0.05], [-13.80, 1.10, 1.10, 0.05], [-13.00, 1.75, 1.80, 0.20], [-11.50, 2.10, 2.05, 0.35],
			[6.00, 2.15, 2.10, 0.40], [9.50, 1.60, 1.40, 1.20], [12.50, 0.90, 0.85, 2.00], [15.00, 0.30, 0.40, 2.50], [15.40, 0.05, 0.05, 2.55]]
		sm.loft(body, 110, 36, func(p: Vector3, n: Vector3) -> int:
			if p.z < -12.2 and p.y > 0.9 and p.y < 1.85 and n.z < -0.2:
				return _cockpit_glass(p, s, 0.9)
			if p.z > -12.6 and p.z < -11.6 and absf(p.x) > 1.4 and p.y > 0.9 and p.y < 1.6:
				return s.glass
			return s.paint, I, 2.4)
		sm.loft([[-13.6, 0.02, 0.02, 0.5], [-13.2, 1.4, 1.2, 0.5], [-11.5, 1.8, 1.6, 0.5], [-11.0, 0.02, 0.02, 0.5]], 12, 16,
			func(_p, _n): return s.inner, I, 2.4)
		# High wing across the top, four engine nacelles under it
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(x * 0.4, 2.70, -2.0), Vector3(x * 20.2, 2.80, -1.4), 4.4, 0.62, s.paint, I, 2.6, Vector3.BACK)
			for nx in [5.5, 10.0]:
				sm.loft([[-4.70, 0.02, 0.02, 2.35, x * nx], [-4.55, 0.45, 0.50, 2.35, x * nx], [-4.00, 0.62, 0.72, 2.30, x * nx], [-0.40, 0.55, 0.65, 2.40, x * nx], [0.60, 0.08, 0.08, 2.55, x * nx]], 20, 18,
					func(_p, _n): return s.paint)
			sm.loft([[-3.0, 0.05, 0.05, -1.55, x * 2.25], [-2.6, 0.45, 0.55, -1.40, x * 2.25], [2.6, 0.45, 0.55, -1.40, x * 2.25], [3.0, 0.05, 0.05, -1.45, x * 2.25]], 20, 16,
				func(_p, _n): return s.paint)            # main gear blisters
			sm.blade(Vector3(0, 3.0, 13.5), Vector3(x * 7.0, 3.0, 13.5), 4.0, 0.30, s.paint, I, 2.4, Vector3.BACK)
		sm.blade(Vector3(0, 2.6, 12.0), Vector3(0, 6.6, 15.4), 4.6, 0.32, s.paint, I, 2.6, Vector3.BACK)
	)
	VehicleModel.add_pilot(parent, Vector3(0.55, 0.70, -12.2), "skin_b", true)
	VehicleModel.add_pilot(parent, Vector3(-0.55, 0.70, -12.2), "skin_a", false)
	var props: Array = []
	for x in [-10.0, -5.5, 5.5, 10.0]:
		var hub := Node3D.new()
		hub.position = Vector3(x, 2.35, -4.80)
		parent.add_child(hub)
		_part(hub, "c130_prop", mats, func(sm: SmoothMesh, s: Dictionary) -> void:
			for k in 4:
				var a := TAU * k / 4.0 + 0.4
				var dir := Vector3(cos(a), sin(a), 0.0)
				sm.blade(dir * 0.25, dir * 2.05, 0.32, 0.05, s.blade, I, 0.22, Vector3.FORWARD.cross(dir))
			sm.loft([[-0.55, 0.02, 0.02, 0.0], [-0.40, 0.25, 0.25, 0.0], [0.10, 0.32, 0.32, 0.0]], 6, 16, func(_p, _n): return s.dark)
		)
		props.append(hub)
	return props
