class_name Gibs
extends Node3D
## Pixel effects: blood when a soldier is hit, explosions, muzzle blasts, cannon impacts and
## smoke from wrecks. Chunks fly, bounce off floors and walls, then shrink away.
## Blood chunks leave flat splats on whatever they land on, which fade after a while.
## Everything is drawn with two MultiMeshes, so hundreds of chunks cost very little.
## Purely visual: chunks have no physics bodies and don't affect gameplay.

const MAX_CHUNKS := 2500
const MAX_SPLATS := 800
const GRAVITY := 18.0
const CHUNK_LIFE := Vector2(1.6, 2.6)
const SPLAT_LIFE := 30.0
const FLOOR_CELL := 0.25          # metres per cached floor-height cell
const BLOOD := Color(0.50, 0.04, 0.03)
const BLOOD_DARK := Color(0.32, 0.03, 0.02)

var chunk_count := 0

# Chunk state, packed for speed (removal swaps with the last chunk)
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _angle := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _size := PackedFloat32Array()
var _life := PackedFloat32Array()
var _color := PackedColorArray()
var _blood := PackedByteArray()     # 1 = leaves a splat when it lands
var _grav := PackedFloat32Array()   # per-chunk gravity (smoke floats up)
var _n := 0

var _splat_pos := PackedVector3Array()
var _splat_size := PackedFloat32Array()
var _splat_rot := PackedFloat32Array()
var _splat_age := PackedFloat32Array()
var _splat_color := PackedColorArray()
var _splat_next := 0
var _splat_used := 0

var _chunks_mm: MultiMesh
var _splats_mm: MultiMesh
var _floor_cache := {}


func _ready() -> void:
	_pos.resize(MAX_CHUNKS)
	_vel.resize(MAX_CHUNKS)
	_axis.resize(MAX_CHUNKS)
	_angle.resize(MAX_CHUNKS)
	_spin.resize(MAX_CHUNKS)
	_size.resize(MAX_CHUNKS)
	_life.resize(MAX_CHUNKS)
	_grav.resize(MAX_CHUNKS)
	_color.resize(MAX_CHUNKS)
	_blood.resize(MAX_CHUNKS)
	_splat_pos.resize(MAX_SPLATS)
	_splat_size.resize(MAX_SPLATS)
	_splat_rot.resize(MAX_SPLATS)
	_splat_age.resize(MAX_SPLATS)
	_splat_color.resize(MAX_SPLATS)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0

	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_chunks_mm = _make_multimesh(cube, MAX_CHUNKS, mat, true)

	var flat := BoxMesh.new()
	flat.size = Vector3(1.0, 0.01, 1.0)
	_splats_mm = _make_multimesh(flat, MAX_SPLATS, mat, false)


func _make_multimesh(mesh: Mesh, count: int, mat: Material, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## Burst a body at `center` (its body centre). `dir` is the direction the killing shot travelled.
func burst(center: Vector3, dir: Vector3, skin: Color, shirt: Color, pants: Color, hair: Color) -> void:
	var push := Vector3(dir.x, 0.0, dir.z)
	if push.length() > 0.01:
		push = push.normalized() * 3.0
	# [color, count, size range, how high on the body]
	var parts := [
		[skin, 4, Vector2(0.10, 0.17), 0.55],    # head and hands
		[hair, 2, Vector2(0.07, 0.12), 0.75],
		[shirt, 5, Vector2(0.10, 0.19), 0.15],
		[pants, 4, Vector2(0.09, 0.16), -0.45],
		[BLOOD, 7, Vector2(0.05, 0.10), 0.10],
		[BLOOD_DARK, 3, Vector2(0.06, 0.12), 0.0],
	]
	for part in parts:
		var col: Color = part[0]
		var count: int = part[1]
		var size_range: Vector2 = part[2]
		var height: float = part[3]
		var is_blood: bool = col == BLOOD or col == BLOOD_DARK
		for k in count:
			var size := randf_range(size_range.x, size_range.y)
			var at := center + Vector3(randf_range(-0.2, 0.2), height + randf_range(-0.15, 0.15), randf_range(-0.2, 0.2))
			var spray := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0), randf_range(-1, 1)).normalized()
			var vel := push + spray * randf_range(2.5, 6.0) + Vector3.UP * randf_range(2.0, 4.5)
			_add_chunk(at, vel, size, col, is_blood)
	# A pool of blood where it stood
	var floor_y := _floor_at(center, center.y + 1.0)
	if floor_y > -50.0 and center.y - floor_y < 2.5:
		_add_splat(Vector3(center.x, floor_y, center.z), randf_range(0.5, 0.8), BLOOD_DARK)


## Artillery or tank-round impact: fireball, debris, rising smoke and a scorch mark.
func explosion(center: Vector3) -> void:
	var fire := [Color(1.0, 0.55, 0.10), Color(1.0, 0.82, 0.30), Color(0.95, 0.30, 0.05)]
	for k in 26:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		_add_chunk(center + Vector3.UP * 0.4, dir * randf_range(5.0, 12.0), randf_range(0.25, 0.55), fire.pick_random(), false, randf_range(0.25, 0.6), 6.0)
	for k in 22:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		var dirt := Color(0.30, 0.27, 0.22) if randf() < 0.6 else Color(0.18, 0.17, 0.16)
		_add_chunk(center + Vector3.UP * 0.3, dir * randf_range(4.0, 11.0), randf_range(0.10, 0.28), dirt, false)
	for k in 16:
		var drift := Vector3(randf_range(-1.2, 1.2), randf_range(1.0, 3.0), randf_range(-1.2, 1.2))
		var grey := Color(0.38, 0.37, 0.35).lerp(Color(0.62, 0.61, 0.58), randf())
		_add_chunk(center + Vector3(randf_range(-1.5, 1.5), randf_range(0.3, 1.8), randf_range(-1.5, 1.5)), drift, randf_range(0.7, 1.4), grey, false, randf_range(2.2, 3.8), -0.6)
	var floor_y := _floor_at(center, center.y + 1.0)
	if floor_y > -50.0:
		_add_splat(Vector3(center.x, floor_y, center.z), randf_range(4.0, 5.0), Color(0.11, 0.10, 0.09))


## A soldier going down: a spray of blood and a splat under him.
func blood(center: Vector3, count := 6) -> void:
	for k in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		_add_chunk(center, dir * randf_range(1.5, 4.0), randf_range(0.06, 0.12), BLOOD if randf() < 0.6 else BLOOD_DARK, true)
	var floor_y := _floor_at(center, center.y)
	if floor_y > -50.0 and center.y - floor_y < 2.5:
		_add_splat(Vector3(center.x, floor_y, center.z), randf_range(0.4, 0.7), BLOOD_DARK)


## A 30 mm cannon round hitting the ground: a small flash and a kick of dirt.
func impact(center: Vector3) -> void:
	for k in 4:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized()
		_add_chunk(center, dir * randf_range(4.0, 9.0), randf_range(0.2, 0.35), Color(1.0, 0.75, 0.30), false, randf_range(0.08, 0.2), 4.0)
	for k in 5:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized()
		_add_chunk(center, dir * randf_range(3.0, 7.0), randf_range(0.12, 0.25), Color(0.30, 0.27, 0.22), false)
	_add_chunk(center + Vector3.UP * 0.4, Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5)), randf_range(0.6, 1.0), Color(0.50, 0.48, 0.44), false, randf_range(1.0, 1.8), -0.5)


## A puff of black smoke drifting up from a burning wreck.
func smoke(at: Vector3) -> void:
	var grey := Color(0.12, 0.12, 0.12).lerp(Color(0.30, 0.29, 0.28), randf())
	_add_chunk(at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)), Vector3(randf_range(-0.4, 0.4), randf_range(1.5, 2.5), randf_range(-0.4, 0.4)), randf_range(0.7, 1.2), grey, false, randf_range(2.5, 3.5), -0.3)


## Cannon firing: a flash out of the muzzle and a puff of smoke.
func muzzle_blast(muzzle: Vector3, dir: Vector3) -> void:
	for k in 10:
		var v := (dir + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))) * randf_range(8.0, 16.0)
		_add_chunk(muzzle, v, randf_range(0.25, 0.45), Color(1.0, 0.75, 0.25), false, randf_range(0.1, 0.25), 0.0)
	for k in 10:
		var v := dir * randf_range(1.0, 4.0) + Vector3(randf_range(-1, 1), randf_range(0.3, 1.5), randf_range(-1, 1))
		_add_chunk(muzzle, v, randf_range(0.5, 1.0), Color(0.55, 0.54, 0.52), false, randf_range(1.5, 2.8), -0.4)


func _add_chunk(p: Vector3, v: Vector3, size: float, color: Color, bleeds: bool, life := -1.0, gravity := GRAVITY) -> void:
	if _n >= MAX_CHUNKS:
		return
	var i := _n
	_n += 1
	_pos[i] = p
	_vel[i] = v
	_axis[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_angle[i] = randf() * TAU
	_spin[i] = randf_range(6.0, 16.0)
	_size[i] = size
	_life[i] = life if life > 0.0 else randf_range(CHUNK_LIFE.x, CHUNK_LIFE.y)
	_color[i] = color
	_blood[i] = 1 if bleeds else 0
	_grav[i] = gravity


func _add_splat(p: Vector3, size: float, color: Color) -> void:
	var i := _splat_next
	_splat_next = (_splat_next + 1) % MAX_SPLATS
	_splat_used = mini(_splat_used + 1, MAX_SPLATS)
	_splat_pos[i] = p + Vector3.UP * (0.015 + randf() * 0.01)   # small offset so splats don't flicker
	_splat_size[i] = size
	_splat_rot[i] = randf() * TAU
	_splat_age[i] = 0.0
	_splat_color[i] = color
	_splats_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _splat_rot[i]).scaled(Vector3(size, 1, size)), _splat_pos[i]))
	_splats_mm.set_instance_color(i, color)
	_splats_mm.visible_instance_count = _splat_used


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var i := 0
	while i < _n:
		_life[i] -= dt
		if _life[i] <= 0.0:
			_remove(i)
			continue
		var p := _pos[i]
		var v := _vel[i]
		var half := _size[i] * 0.5
		if v != Vector3.ZERO:
			v.y -= _grav[i] * dt
			if _grav[i] < 0.0:
				v *= 1.0 - minf(dt * 1.2, 0.5)   # smoke slows as it drifts
			var next := p + v * dt
			var floor_y := _floor_at(next, p.y)
			if floor_y > p.y - half + 0.3:
				# Something taller than the chunk is in the way: a wall. Bounce off it.
				next = Vector3(p.x, next.y, p.z)
				v.x *= -0.4
				v.z *= -0.4
				floor_y = _floor_at(next, p.y)
			if next.y - half <= floor_y:
				next.y = floor_y + half
				if v.y < -1.5:
					v.y = -v.y * 0.3
					v.x *= 0.55
					v.z *= 0.55
					_spin[i] *= 0.5
				else:
					v = Vector3.ZERO
					_spin[i] = 0.0
				if _blood[i] == 1:
					_blood[i] = 0
					_add_splat(Vector3(next.x, floor_y, next.z), _size[i] * randf_range(2.0, 3.5), _color[i])
			_pos[i] = next
			_vel[i] = v
			_angle[i] += _spin[i] * dt
		i += 1

	chunk_count = _n
	_chunks_mm.visible_instance_count = _n
	for k in _n:
		var s := _size[k]
		if _life[k] < 0.5:
			s *= _life[k] / 0.5    # shrink away at the end
		var b := Basis(_axis[k], _angle[k]).scaled(Vector3(s, s, s))
		_chunks_mm.set_instance_transform(k, Transform3D(b, _pos[k]))
		_chunks_mm.set_instance_color(k, _color[k])

	# Old splats fade into the street, then disappear
	for k in _splat_used:
		_splat_age[k] += dt
		var age := _splat_age[k]
		if age > SPLAT_LIFE - 5.0:
			var f := clampf((SPLAT_LIFE - age) / 5.0, 0.0, 1.0)
			var sz := _splat_size[k] * f
			_splats_mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, _splat_rot[k]).scaled(Vector3(sz, 1, sz)), _splat_pos[k]))


func _remove(i: int) -> void:
	var last := _n - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_axis[i] = _axis[last]
		_angle[i] = _angle[last]
		_spin[i] = _spin[last]
		_size[i] = _size[last]
		_life[i] = _life[last]
		_color[i] = _color[last]
		_blood[i] = _blood[last]
		_grav[i] = _grav[last]
	_n -= 1


func _floor_at(p: Vector3, from_y: float) -> float:
	## Height of the static world under p (buildings, ramp, cars, street). Cached per cell,
	## since the level never moves. Returns the highest surface at or below from_y + 0.3.
	var key := Vector2i(floori(p.x / FLOOR_CELL), floori(p.z / FLOOR_CELL))
	var heights: Array = _floor_cache.get(key, [])
	if heights.is_empty():
		heights = _scan_cell(key)
		_floor_cache[key] = heights
	for h in heights:      # sorted high to low
		if h <= from_y + 0.3:
			return h
	return -100.0


func _scan_cell(key: Vector2i) -> Array:
	# Cast down through the cell from high up, collecting every surface top (most cells have one)
	var cx := (key.x + 0.5) * FLOOR_CELL
	var cz := (key.y + 0.5) * FLOOR_CELL
	var space := get_world_3d().direct_space_state
	var out: Array = []
	var from := Vector3(cx, 200.0, cz)
	var exclude: Array[RID] = []
	for attempt in 4:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(cx, -5.0, cz), 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		out.append(hit.position.y)
		exclude.append(hit.rid)
		from = hit.position + Vector3.DOWN * 0.01
	if out.is_empty():
		out.append(-100.0)
	return out
