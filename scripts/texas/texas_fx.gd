class_name TexasFx
extends Node3D
## What the fighting looks like near the camera: tracer fire between the units that are
## shooting at each other (from the simulation's fight rounds), explosions where units are
## lost, and their burnt-out wrecks. Everything is kept in world metres and drawn relative to
## the scene origin, like the rest of the Texas world.

const MAX_TRACERS := 900
const MAX_WRECKS := 240
const TRACER_LIFE := 0.22

var origin_x := 0.0
var origin_z := 0.0
var pos_of: Callable                   # unit -> Vector3 in world metres (y up), from TexasMain
var _mm: MultiMeshInstance3D
var _tracers: Array = []               # [from world, to world, age, colour]
var _pairs := PackedInt32Array()       # who is firing at whom this round
var _rates := {}                       # unit type -> tracers a second
var _acc := {}
var _blasts: Array = []                # {"node", "age", "life", "size", "smoke"}
var _wrecks: Array = []                # {"node", "x", "z", "y"}
var _flash_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _wreck_mat: StandardMaterial3D
var _sphere: SphereMesh
var _box: BoxMesh
var sim: TexasSim


func _init(s: TexasSim) -> void:
	sim = s
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bx := BoxMesh.new()
	bx.size = Vector3(1, 1, 1)
	mm.mesh = bx
	mm.instance_count = MAX_TRACERS
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	_mm.material_override = tm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.62, 0.20, 0.9)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_color = Color(0.16, 0.15, 0.14, 0.7)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.roughness = 1.0
	_wreck_mat = StandardMaterial3D.new()
	_wreck_mat.albedo_color = Color(0.09, 0.08, 0.08)
	_wreck_mat.roughness = 1.0
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	# How hard each type fires, in tracers a second while it's in a fight
	for t in TexasUnits.TYPES.size():
		var id: String = TexasUnits.TYPES[t].id
		_rates[t] = {"rifle": 4.0, "humvee": 5.0, "stryker": 5.0, "bradley": 3.0, "tank": 1.0, "aa": 9.0,
			"black_hawk": 4.0, "chinook": 3.0, "little_bird": 5.0, "apache": 3.0, "hornet": 2.0, "a10": 6.0,
			"carrier": 0.0, "amphib": 0.0, "destroyer": 0.0, "cruiser": 0.0}.get(id, 2.0)
	# (ships' guns and missiles are drawn by TexasNavalFx)


func set_origin(ox: float, oz: float) -> void:
	origin_x = ox
	origin_z = oz
	for w in _wrecks:
		(w.node as Node3D).position = Vector3(w.x - ox, w.y, w.z - oz)
	for b in _blasts:
		(b.node as Node3D).position = Vector3(b.x - ox, b.y + b.rise, b.z - oz)


func add_tracer(from: Vector3, to: Vector3, col: Color, width := 0.5) -> void:
	## One tracer round (map metres), for weapons drawn elsewhere (the ships' Phalanx)
	if _tracers.size() < MAX_TRACERS:
		_tracers.append([from, to, 0.0, col, width])


func set_pairs(p: PackedInt32Array) -> void:
	_pairs = p


func update(delta: float, focus: Vector2, radius: float, game_speed: float) -> void:
	## Spawn tracers for the fights near the camera, age everything, draw
	if game_speed > 0.0 and radius > 0.0:
		var r2 := radius * radius
		var budget := MAX_TRACERS - _tracers.size()
		for k in range(0, _pairs.size(), 2):
			if budget <= 0:
				break
			var a := _pairs[k]
			var b := _pairs[k + 1]
			if a >= sim.count or b >= sim.count or sim.alive[a] == 0 or sim.alive[b] == 0:
				continue
			var dx: float = sim.x[a] - focus.x
			var dz: float = sim.z[a] - focus.y
			if dx * dx + dz * dz > r2:
				continue
			var t: int = sim.utype[a]
			var acc: float = _acc.get(a, randf()) + delta * _rates[t] * minf(game_speed, 4.0)
			while acc >= 1.0 and budget > 0:
				acc -= 1.0
				var from: Vector3 = pos_of.call(a)
				var to: Vector3 = pos_of.call(b)
				to += Vector3(randf_range(-6, 6), randf_range(-1, 3), randf_range(-6, 6))
				var col := Color(1.0, 0.86, 0.45) if sim.side[a] == 0 else Color(1.0, 0.38, 0.25)
				_tracers.append([from, to, randf() * 0.05, col])
				budget -= 1
			_acc[a] = acc
	if _acc.size() > 4000:
		_acc.clear()
	_draw_tracers(delta)
	_age_blasts(delta)


func _draw_tracers(delta: float) -> void:
	var mm := _mm.multimesh
	var n := 0
	var buf := PackedFloat32Array()
	buf.resize(MAX_TRACERS * 16)
	var keep: Array = []
	for tr in _tracers:
		tr[2] += delta
		var f: float = tr[2] / TRACER_LIFE
		if f >= 1.0:
			continue
		keep.append(tr)
		var a: Vector3 = tr[0]
		var b: Vector3 = tr[1]
		var dir := b - a
		var L := dir.length()
		if L < 1.0:
			continue
		var seg := minf(L * 0.25, 40.0)
		var head := a + dir * f
		var tail := head - dir / L * seg
		var mid := (head + tail) * 0.5
		var zax := (head - tail).normalized()
		var xax := zax.cross(Vector3.UP)
		if xax.length_squared() < 1e-6:
			xax = Vector3.RIGHT
		xax = xax.normalized()
		var yax := xax.cross(zax).normalized()
		var w: float = tr[4] if tr.size() > 4 else 0.5
		var x0 := xax * w
		var y0 := yax * w
		var z0 := zax * seg
		var o := n * 16
		buf[o] = x0.x
		buf[o + 1] = y0.x
		buf[o + 2] = z0.x
		buf[o + 3] = mid.x - origin_x
		buf[o + 4] = x0.y
		buf[o + 5] = y0.y
		buf[o + 6] = z0.y
		buf[o + 7] = mid.y
		buf[o + 8] = x0.z
		buf[o + 9] = y0.z
		buf[o + 10] = z0.z
		buf[o + 11] = mid.z - origin_z
		var c: Color = tr[3]
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1.0
		n += 1
	_tracers = keep
	mm.buffer = buf
	mm.visible_instance_count = n


func explode(at: Vector3, size: float, wreck: Vector3 = Vector3.ZERO, heading := 0.0) -> void:
	## A fireball and smoke where a unit was lost, and its wreck if it leaves one
	for smoke in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = _sphere
		var mat: StandardMaterial3D = (_smoke_mat if smoke else _flash_mat).duplicate()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var b := {"node": mi, "mat": mat, "age": 0.0, "life": 6.0 if smoke else 0.9, "size": size * (1.6 if smoke else 1.0),
			"smoke": smoke, "x": at.x, "y": at.y, "z": at.z, "rise": 0.0}
		_blasts.append(b)
	if wreck != Vector3.ZERO:
		var w := MeshInstance3D.new()
		w.mesh = _box
		w.material_override = _wreck_mat
		w.scale = wreck
		w.rotation.y = heading
		add_child(w)
		_wrecks.append({"node": w, "x": at.x, "y": at.y + wreck.y * 0.5 - 0.3, "z": at.z})
		if _wrecks.size() > MAX_WRECKS:
			(_wrecks.pop_front().node as Node).queue_free()
	set_origin(origin_x, origin_z)


func _age_blasts(delta: float) -> void:
	var keep: Array = []
	for b in _blasts:
		b.age += delta
		var f: float = b.age / b.life
		var node: MeshInstance3D = b.node
		if f >= 1.0:
			node.queue_free()
			continue
		keep.append(b)
		var s: float = b.size * (0.4 + f * (1.6 if b.smoke else 1.2))
		node.scale = Vector3(s, s, s)
		if b.smoke:
			b.rise = f * b.size * 2.5
			(b.mat as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - f)
		else:
			(b.mat as StandardMaterial3D).albedo_color.a = 0.95 * (1.0 - f)
		node.position = Vector3(b.x - origin_x, b.y + b.rise, b.z - origin_z)
	_blasts = keep


func clear() -> void:
	for b in _blasts:
		(b.node as Node).queue_free()
	for w in _wrecks:
		(w.node as Node).queue_free()
	_blasts.clear()
	_wrecks.clear()
	_tracers.clear()
