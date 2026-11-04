class_name TexasNavalFx
extends Node3D
## The fleet's weapons, seen up close. When a ship near the camera is fighting (the simulation's
## fight rounds say who is shooting at whom), its weapons train on the target and fire:
##   - Mk 41 vertical launchers: a hatch pops open, the missile boosts straight up out of its
##     cell in a great white plume (with the exhaust venting beside the launcher), pitches over
##     and streaks off trailing smoke: Standard missiles at aircraft, Tomahawks at targets ashore
##   - RAM and Sea Sparrow launchers turn and elevate, and fire from the box in a cloud of smoke
##   - the 5-inch guns turn, elevate and fire: muzzle flash, a puff of smoke, the barrel recoils,
##     the shell flies its arc and bursts on the target
##   - Phalanx swings onto close aircraft and fires bursts of tracer
## Radars turn, the LCACs' propellers spin, and the assault ship's stern gate drops into the
## water to let the landing craft in and out of the well deck.
## Missiles and shells are kept in map metres (like the units) and placed relative to the scene
## origin each frame.

const CIWS_RANGE := 1500.0             # game m: closer aircraft get Phalanx
const RAM_RANGE := 3200.0
const STANDARD_SPEED := 650.0          # m/s, what the eye can follow
const TOMAHAWK_SPEED := 240.0
const BOX_SPEED := 560.0
const SHELL_SPEED := 760.0
const GRAVITY := 9.8

var sim: TexasSim
var main: Node                          # TexasMain: proxies, unit_pos, origin
var fx: TexasFx
var _timers := {}                      # ship -> {weapon: seconds until it may fire again}
var _shots: Array = []                 # missiles and shells in flight
var _bursts: Array = []                # Phalanx firing
var _recoil: Array = []                # [barrel node, age]
var _lids: Array = []                  # [node, age]
var _puffs: Array = []                 # one-shot smoke and flashes: [node, age, life]
var _aim := {}                         # mount node -> target unit
var _smoke_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _missile_mesh: Mesh
var _lid_mesh: Mesh
var _flash_mesh: SphereMesh
var _round := 0
var _ribbons: Array = []               # smoke trails: {"mi", "im", "pts": [[map pos, age]], "live"}
var _ribbon_mat: StandardMaterial3D
var launches := {}                     # (for the labs) weapon -> how many times it fired


func _init(s: TexasSim, m: Node, f: TexasFx) -> void:
	sim = s
	main = m
	fx = f
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = tex
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_smoke_mat.billboard_keep_scale = true
	_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.albedo_color = Color(1.0, 0.75, 0.35, 0.95)
	_flame_mat.albedo_texture = tex
	_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flame_mat.billboard_keep_scale = true
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.5
	_flash_mesh.height = 1.0
	_flash_mesh.radial_segments = 10
	_flash_mesh.rings = 5
	# A missile: white body, dark nose, fins (4.7 m long, about a third of a metre across)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ShipModels._tube(st, Vector3(0, 0, 2.35), Vector3(0, 0, -1.9), 0.18, Color(0.92, 0.92, 0.90), 8)
	ShipModels._tube(st, Vector3(0, 0, -1.9), Vector3(0, 0, -2.35), 0.11, Color(0.25, 0.25, 0.25), 8)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var d := Vector3(cos(a), sin(a), 0)
		ShipModels._quad_out(st, d * 0.15 + Vector3(0, 0, 1.4), d * 0.15 + Vector3(0, 0, 2.3), d * 0.55 + Vector3(0, 0, 2.3), d * 0.5 + Vector3(0, 0, 1.8), Color(0.85, 0.85, 0.83), Vector3(-sin(a), cos(a), 0))
	_missile_mesh = st.commit()
	var rt := GradientTexture2D.new()
	rt.fill_from = Vector2(0, 0)
	rt.fill_to = Vector2(1, 0)
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1, 0))
	rg.add_point(0.3, Color(1, 1, 1, 0.85))
	rg.add_point(0.5, Color(1, 1, 1, 1))
	rg.add_point(0.7, Color(1, 1, 1, 0.85))
	rg.set_color(rg.get_point_count() - 1, Color(1, 1, 1, 0))
	rt.gradient = rg
	rt.width = 64
	rt.height = 4
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_mat.vertex_color_use_as_albedo = true
	_ribbon_mat.albedo_texture = rt
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	ShipModels._box(ls, Vector3(0, 0.03, -0.34), Vector3(0.66, 0.06, 0.68), ShipModels.HATCH)
	_lid_mesh = ls.commit()


func _mat() -> StandardMaterial3D:
	return ShipModels._material()


# --- Every frame -------------------------------------------------------------------------------

func update(delta: float, game_speed: float) -> void:
	var gs := minf(game_speed, 4.0)        # effects run at most 4x, so they stay watchable
	var dt := delta * gs
	_animate_ships(delta, game_speed, dt)
	if game_speed > 0.0:
		_fire(dt)
	_fly(dt)
	_ribbons_update(dt)
	_age(dt)


func _ship_model(i: int) -> Node3D:
	var p = main._proxies.get(i)
	if p == null or not (p as Node3D).has_meta("ship"):
		return null
	return (p as Node3D).get_meta("ship")


func _animate_ships(delta: float, game_speed: float, dt: float) -> void:
	for i in main._proxies:
		var m := _ship_model(i)
		if m == null:
			continue
		# radars turn (in real time: they're just turning), propellers spin when under way
		for r in m.get_meta("radars", []):
			(r as Node3D).rotation.y += float(r.get_meta("spin", 2.0)) * delta
		if m.has_meta("props") and sim.is_moving(i) and game_speed > 0.0:
			for pr in m.get_meta("props"):
				(pr as Node3D).rotation.z += 30.0 * delta
		# the stern gate: down while a landing craft is coming or going
		if m.has_meta("gate"):
			var gate: Node3D = m.get_meta("gate")
			var want := deg_to_rad(96.0) if _lcac_near_stern(i) else 0.0
			gate.rotation.x = move_toward(gate.rotation.x, want, deg_to_rad(9.0) * maxf(dt, delta * 0.25))
		# weapons return to their rest positions when there's nothing to shoot at
		for list in ["guns", "ciws", "ram", "essm"]:
			for mount in m.get_meta(list, []):
				var tgt: int = _aim.get(mount, -1)
				var rate := deg_to_rad(120.0 if list == "ciws" else (40.0 if list == "guns" else 70.0)) * maxf(dt, delta)
				if tgt >= 0 and tgt < sim.count and sim.alive[tgt] == 1:
					var want := _bearing(mount, main.unit_pos(tgt), list == "guns")
					_slew(mount, want.x, want.y, rate)
				else:
					_slew(mount, float(mount.get_meta("rest", 0.0)), 0.0, rate * 0.5)


func _lcac_near_stern(i: int) -> bool:
	var h: float = sim.heading[i]
	var aft := Vector2(sin(h), cos(h))
	var stern := Vector2(sim.x[i], sim.z[i]) + aft * 125.0
	var lcac := TexasUnits.id("lcac")
	for j in sim.count:
		if sim.utype[j] == lcac and sim.alive[j] == 1 and sim.aboard[j] == -1:
			if Vector2(sim.x[j], sim.z[j]).distance_to(stern) < 360.0:
				return true
	return false


func _bearing(mount: Node3D, target_abs: Vector3, ballistic: bool) -> Vector2:
	## (yaw, pitch) for a mount to point at a target in map metres
	var parent := mount.get_parent() as Node3D
	var local := parent.to_local(_scene(target_abs)) - mount.position
	var yaw := atan2(-local.x, -local.z)
	var flat := Vector2(local.x, local.z).length()
	var pitch := atan2(local.y, flat)
	if ballistic:
		# loft the barrel for the shell's arc (flat-fire guns still come up a little)
		var t := flat / SHELL_SPEED
		pitch = atan2(local.y + 0.5 * GRAVITY * t * t, flat)
	return Vector2(yaw, clampf(pitch, deg_to_rad(-5.0), deg_to_rad(80.0)))


func _slew(mount: Node3D, yaw: float, pitch: float, rate: float) -> void:
	mount.rotation.y = mount.rotation.y + clampf(wrapf(yaw - mount.rotation.y, -PI, PI), -rate, rate)
	var p := mount.get_node("Pitch") as Node3D
	p.rotation.x = move_toward(p.rotation.x, pitch, rate)


func _scene(abs_pos: Vector3) -> Vector3:
	return Vector3(abs_pos.x - main.origin_x, abs_pos.y, abs_pos.z - main.origin_z)


func _abs(scene_pos: Vector3) -> Vector3:
	return Vector3(scene_pos.x + main.origin_x, scene_pos.y, scene_pos.z + main.origin_z)


# --- Choosing and firing weapons ----------------------------------------------------------------

func _fire(dt: float) -> void:
	var pairs: PackedInt32Array = sim.shots
	var seen := {}
	for k in range(0, pairs.size(), 2):
		var a := pairs[k]
		var b := pairs[k + 1]
		if a >= sim.count or b >= sim.count or seen.has(a) or not TexasUnits.is_ship(sim.utype[a]):
			continue
		if sim.alive[a] == 0 or sim.alive[b] == 0:
			continue
		var m := _ship_model(a)
		if m == null:
			continue
		seen[a] = true
		var t: Dictionary = _timers.get(a, {})
		for w in t.keys():
			t[w] -= dt
		_timers[a] = t
		var air: bool = sim.kind[b] == TexasSim.Kind.HELI or sim.kind[b] == TexasSim.Kind.JET
		var d := Vector2(sim.x[b] - sim.x[a], sim.z[b] - sim.z[a]).length()
		var id: String = TexasUnits.TYPES[sim.utype[a]].id
		var big_deck := id == "carrier" or id == "amphib"
		if air:
			if d < CIWS_RANGE and _can_fire(t, "ciws", 3.5):
				_ciws(m, a, b)
			elif big_deck:
				if d < RAM_RANGE and _can_fire(t, "ram", 6.0):
					_box_launch(m, "ram", a, b)
				elif _can_fire(t, "essm", 8.0):
					_box_launch(m, "essm", a, b)
			elif _can_fire(t, "standard", 7.0):
				_vls_launch(m, a, b, "standard")
		else:
			if not big_deck:
				if _can_fire(t, "gun", 5.0):
					_gun_salvo(m, a, b)
				if d > 2500.0 and _can_fire(t, "tomahawk", 26.0):
					_vls_launch(m, a, b, "tomahawk")
	# timers of ships no longer fighting still run down
	for a in _timers.keys():
		if not seen.has(a):
			var t: Dictionary = _timers[a]
			for w in t.keys():
				t[w] -= dt
			if a >= sim.count or sim.alive[a] == 0:
				_timers.erase(a)


func _can_fire(t: Dictionary, weapon: String, every: float) -> bool:
	if t.get(weapon, 0.0) > 0.0:
		return false
	t[weapon] = every * randf_range(0.85, 1.15)
	return true


func _pick_mount(m: Node3D, list: String, target_abs: Vector3) -> Node3D:
	## The mount of this kind facing nearest the target (so the forward gun takes targets ahead)
	var best: Node3D = null
	var best_a := INF
	for mount in m.get_meta(list, []):
		var want := _bearing(mount, target_abs, false).x
		var off := absf(wrapf(want - float(mount.get_meta("rest", 0.0)), -PI, PI))
		if off < best_a:
			best_a = off
			best = mount
	return best


func _count(w: String) -> void:
	launches[w] = launches.get(w, 0) + 1


func _vls_launch(m: Node3D, a: int, b: int, kind: String) -> void:
	var cells: PackedVector3Array = m.get_meta("vls", PackedVector3Array())
	if cells.is_empty():
		return
	var cell := cells[randi() % cells.size()]
	var top := m.to_global(cell)
	_count(kind)
	# the hatch flips open
	var lid := MeshInstance3D.new()
	lid.mesh = _lid_mesh
	lid.material_override = _mat()
	m.add_child(lid)
	lid.position = cell + Vector3(0, 0.05, 0.34)
	_lids.append([lid, 0.0])
	# the plume: white smoke boiling up out of the cell, and the exhaust venting beside it
	_puff(_abs(top), Color(0.97, 0.97, 0.96), 150, 7.0, 9.0, 20.0, Vector3(0, 30, 0), 8.0, 2.8)
	_puff(_abs(top + m.global_basis * Vector3(2.2, 0, 0)), Color(0.86, 0.86, 0.85), 80, 6.0, 7.0, 15.0, Vector3(0, 24, 0), 6.0, 2.4)
	_puff(_abs(top), Color(0.98, 0.95, 0.88), 40, 2.5, 6.0, 12.0, Vector3(0, 6, 0), 18.0, 2.0)
	_flash(_abs(top + Vector3(0, 3, 0)), 18.0, 0.3)
	_launch_missile(_abs(top + Vector3(0, 0.5, 0)), Vector3.UP, b, kind, true)


func _box_launch(m: Node3D, list: String, a: int, b: int) -> void:
	var tgt: Vector3 = main.unit_pos(b)
	var mount := _pick_mount(m, list, tgt)
	if mount == null:
		return
	_aim[mount] = b
	_count(list)
	var muzzle := mount.get_node("Pitch/Muzzle") as Node3D
	var side := Vector3(randf_range(-0.6, 0.6), randf_range(-0.5, 0.5), 0)
	var from := muzzle.to_global(side)
	var dir := -muzzle.global_basis.z
	# if the launcher hasn't come round yet, the missile still leaves upwards and turns
	if dir.y < 0.2:
		dir = (dir + Vector3(0, 0.6, 0)).normalized()
	_puff(_abs(from), Color(0.95, 0.95, 0.94), 90, 6.0, 6.0, 14.0, dir * 22.0 + Vector3(0, 4, 0), 10.0, 2.8)
	_flash(_abs(from), 10.0, 0.25)
	_launch_missile(_abs(from), dir, b, list, false)


func _launch_missile(from_abs: Vector3, dir: Vector3, target: int, kind: String, vertical: bool) -> void:
	var node := Node3D.new()
	add_child(node)
	var body := MeshInstance3D.new()
	body.mesh = _missile_mesh
	body.material_override = _mat()
	if kind == "tomahawk":
		body.scale = Vector3(1.4, 1.4, 1.35)
	node.add_child(body)
	var flame := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 9.0)
	flame.mesh = q
	flame.material_override = _flame_mat
	flame.position = Vector3(0, 0, 3.4)
	node.add_child(flame)
	var trail := _ribbon(from_abs, kind == "tomahawk")
	var speed := STANDARD_SPEED
	match kind:
		"tomahawk":
			speed = TOMAHAWK_SPEED
		"ram", "essm":
			speed = BOX_SPEED
	_shots.append({"kind": kind, "node": node, "trail": trail, "pos": from_abs, "vel": dir.normalized() * (25.0 if vertical else 60.0),
		"target": target, "aim": main.unit_pos(target), "age": 0.0, "speed": speed, "vertical": vertical, "missile": true})


func _gun_salvo(m: Node3D, a: int, b: int) -> void:
	var tgt: Vector3 = main.unit_pos(b)
	var mount := _pick_mount(m, "guns", tgt)
	if mount == null:
		return
	_aim[mount] = b
	# three rounds, about two seconds apart (once the gun is on the bearing)
	for k in 3:
		_shots.append({"kind": "round_pending", "mount": mount, "target": b, "age": -1.2 - k * 1.9, "missile": false})


func _gun_fire(mount: Node3D, b: int) -> void:
	var muzzle := mount.get_node("Pitch/Muzzle") as Node3D
	var from := _abs(muzzle.global_position)
	var to: Vector3 = main.unit_pos(b) + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var t := maxf(flat.length() / SHELL_SPEED, 0.2)
	var v := Vector3(flat.x / t, (to.y - from.y + 0.5 * GRAVITY * t * t) / t, flat.y / t)
	var dir := -muzzle.global_basis.z
	_flash(from + dir * 3.0, 9.0, 0.2)
	_puff(from + dir * 5.0, Color(0.82, 0.81, 0.78), 50, 5.0, 5.0, 12.0, dir * 30.0 + Vector3(0, 3, 0), 8.0, 3.0)
	var barrel := mount.get_node_or_null("Pitch/Barrel") as Node3D
	if barrel != null:
		_recoil.append([barrel, 0.0])
	var tracer := MeshInstance3D.new()
	tracer.mesh = _flash_mesh
	tracer.scale = Vector3.ONE * 1.6
	tracer.material_override = _flame_mat
	add_child(tracer)
	_count("gun")
	_shots.append({"kind": "shell", "node": tracer, "pos": from, "vel": v, "target": b, "age": 0.0, "life": t, "missile": false})


func _ciws(m: Node3D, a: int, b: int) -> void:
	var tgt: Vector3 = main.unit_pos(b)
	var mount := _pick_mount(m, "ciws", tgt)
	if mount == null:
		return
	_aim[mount] = b
	_count("ciws")
	_bursts.append({"mount": mount, "target": b, "age": -0.4, "life": 1.6})


# --- In flight ----------------------------------------------------------------------------------

func _fly(dt: float) -> void:
	var keep: Array = []
	for s in _shots:
		s.age += dt
		match s.kind:
			"round_pending":
				if s.age >= 0.0:
					if is_instance_valid(s.mount) and (s.mount as Node3D).is_visible_in_tree() and s.target < sim.count and sim.alive[s.target] == 1:
						_gun_fire(s.mount, s.target)
					continue
				keep.append(s)
				continue
			"shell":
				s.vel += Vector3(0, -GRAVITY, 0) * dt
				s.pos += s.vel * dt
				(s.node as Node3D).position = _scene(s.pos)
				if s.age >= s.life:
					fx.explode(s.pos, 7.0)
					(s.node as Node).queue_free()
					continue
				keep.append(s)
				continue
		# missiles
		var tgt: Vector3 = s.aim
		if s.target < sim.count and sim.alive[s.target] == 1:
			tgt = main.unit_pos(s.target)
			s.aim = tgt
		var to: Vector3 = tgt - s.pos
		var dist := to.length()
		var v: Vector3 = s.vel
		var speed := v.length()
		if s.vertical and s.age < 1.1:
			# straight up out of the cell, picking up speed
			v = Vector3.UP * minf(speed + 160.0 * dt, 140.0)
		else:
			var target_speed: float = s.speed
			speed = move_toward(speed, target_speed, 420.0 * dt)
			var want := to.normalized()
			if s.kind == "tomahawk" and dist > 600.0:
				# cruise missiles fly low: aim along the ground, a little above it
				want = Vector3(to.x, (60.0 - s.pos.y) * 2.0, to.z).normalized()
			var turn := (1.6 if s.age < 3.0 else 4.0) * dt
			var cur := v.normalized()
			var nd := cur.slerp(want, clampf(turn, 0.0, 1.0)) if cur.dot(want) > -0.999 else want
			v = nd * speed
		s.vel = v
		s.pos += v * dt
		_ribbon_extend(s.trail, s.pos - v.normalized() * 3.0)
		var node: Node3D = s.node
		node.position = _scene(s.pos)
		if v.length_squared() > 1.0:
			node.look_at(node.position + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
		if dist < maxf(20.0, speed * dt * 1.5) or s.age > 45.0:
			fx.explode(s.pos, 11.0 if s.kind == "tomahawk" else 7.0)
			_leave_trail(s)
			node.queue_free()
			continue
		keep.append(s)
	_shots = keep
	# Phalanx bursts: a stream of tracer and muzzle flashes
	var bk: Array = []
	for b in _bursts:
		b.age += dt
		if b.age > b.life or not is_instance_valid(b.mount) or b.target >= sim.count or sim.alive[b.target] == 0:
			if b.age <= b.life and is_instance_valid(b.mount):
				pass
			continue
		bk.append(b)
		if b.age < 0.0:
			continue
		var muzzle := (b.mount as Node3D).get_node("Pitch/Muzzle") as Node3D
		var from := _abs(muzzle.global_position)
		var to: Vector3 = main.unit_pos(b.target)
		for k in 3:
			fx.add_tracer(from, to + Vector3(randf_range(-8, 8), randf_range(-6, 6), randf_range(-8, 8)), Color(1.0, 0.85, 0.45), 1.6)
		if randf() < 0.5:
			_flash(from + (to - from).normalized() * 1.5, 1.6, 0.05)
		if randf() < 0.25:
			_puff(from, Color(0.75, 0.74, 0.72), 4, 2.0, 1.0, 3.0, Vector3(0, 2, 0), 1.0, 1.5)
	_bursts = bk


func _leave_trail(s: Dictionary) -> void:
	## The smoke trail stays in the air and fades after the missile has gone
	(s.trail as Dictionary).live = false


func _ribbon(start_abs: Vector3, thin: bool) -> Dictionary:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _ribbon_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	var r := {"mi": mi, "im": im, "pts": [[start_abs, 0.0]], "live": true, "w0": 2.5 if thin else 4.0, "life": 9.0 if thin else 11.0}
	_ribbons.append(r)
	return r


func _ribbons_update(dt: float) -> void:
	## Lay smoke along each missile's path, widen and fade it with age, and draw it facing the camera
	var cam := get_viewport().get_camera_3d()
	var view := -cam.global_basis.z if cam != null else Vector3.DOWN
	var keep: Array = []
	for r in _ribbons:
		var pts: Array = r.pts
		for p in pts:
			p[1] += dt
		while pts.size() > 1 and pts[0][1] > r.life:
			pts.pop_front()
		var im: ImmediateMesh = r.im
		im.clear_surfaces()
		if not r.live and (pts.size() < 2 or pts[pts.size() - 1][1] > r.life):
			(r.mi as Node).queue_free()
			continue
		keep.append(r)
		if pts.size() < 2:
			continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in pts.size():
			var p: Vector3 = _scene(pts[k][0])
			var a: float = pts[k][1]
			var nb: Vector3 = _scene(pts[mini(k + 1, pts.size() - 1)][0]) - _scene(pts[maxi(k - 1, 0)][0])
			var side := nb.cross(view)
			if side.length_squared() < 1e-6:
				side = Vector3.RIGHT
			side = side.normalized()
			var w: float = r.w0 + a * 3.2
			var f := clampf(a / r.life, 0.0, 1.0)
			var fresh := clampf(a * 3.0, 0.0, 1.0)
			var col := Color(1.0, 0.98, 0.95).lerp(Color(0.82, 0.82, 0.82), f)
			col.a = 0.85 * (1.0 - f) * (1.0 - f) * fresh
			im.surface_set_color(col)
			im.surface_set_uv(Vector2(0, 0))
			im.surface_add_vertex(p - side * w * 0.5)
			im.surface_set_color(col)
			im.surface_set_uv(Vector2(1, 0))
			im.surface_add_vertex(p + side * w * 0.5)
		im.surface_end()
	_ribbons = keep


func _ribbon_extend(r: Dictionary, at_abs: Vector3) -> void:
	var pts: Array = r.pts
	var last: Vector3 = pts[pts.size() - 1][0]
	var d := at_abs.distance_to(last)
	if d >= 6.0:
		# fill in evenly however far it went this frame
		var n := mini(int(d / 6.0), 60)
		for k in range(1, n + 1):
			pts.append([last.lerp(at_abs, float(k) / n), 0.0])


func _age(dt: float) -> void:
	var keep: Array = []
	for r in _recoil:
		r[1] += dt
		var barrel: Node3D = r[0]
		if not is_instance_valid(barrel):
			continue
		var f: float = r[1]
		barrel.position.z = 1.0 * (1.0 - smoothstep(0.05, 0.6, f)) if f > 0.0 else 0.0
		if f < 0.7:
			keep.append(r)
		else:
			barrel.position.z = 0.0
	_recoil = keep
	keep = []
	for l in _lids:
		l[1] += dt
		var lid: Node3D = l[0]
		if not is_instance_valid(lid):
			continue
		var f: float = l[1]
		lid.rotation.x = -deg_to_rad(100.0) * clampf(f * 5.0, 0.0, 1.0) * (1.0 - clampf((f - 2.5) * 2.0, 0.0, 1.0))
		if f < 3.2:
			keep.append(l)
		else:
			lid.queue_free()
	_lids = keep
	keep = []
	for p in _puffs:
		p[1] += dt
		var n: Node3D = p[0]
		if not is_instance_valid(n):
			continue
		if n is CPUParticles3D:
			(n as CPUParticles3D).speed_scale = 1.0
		elif n.has_meta("flash"):
			var f: float = p[1] / p[2]
			n.scale = Vector3.ONE * float(n.get_meta("flash")) * (1.0 + f * 0.6)
			var mat := (n as MeshInstance3D).material_override as StandardMaterial3D
			mat.albedo_color.a = 1.0 - f
		if p[1] < p[2]:
			keep.append(p)
		else:
			n.queue_free()
	_puffs = keep


# --- Smoke and fire -----------------------------------------------------------------------------

func _trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 220
	p.lifetime = 7.0
	p.emitting = true
	# the trail is drawn as one thing with the missile at its head: don't cull it when the
	# missile itself is out of view
	p.extra_cull_margin = 16384.0
	p.direction = Vector3(0, 0, 1)
	p.spread = 12.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 8.0
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, 4.0))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.85))
	g.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _smoke_mat
	p.mesh = q
	return p


func _puff(at_abs: Vector3, col: Color, amount: int, life: float, size_min: float, size_max: float,
		vel: Vector3, spread_v: float, grow: float) -> void:
	## A one-off cloud of smoke
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 0.75
	p.extra_cull_margin = 400.0
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = vel.normalized() if vel.length() > 0.01 else Vector3.UP
	p.spread = 24.0
	p.initial_velocity_min = vel.length() * 0.4
	p.initial_velocity_max = vel.length() * 1.1 + spread_v
	p.gravity = Vector3(0, 0.8, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.95))
	g.set_color(1, Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _smoke_mat
	p.mesh = q
	add_child(p)
	p.position = _scene(at_abs)
	p.emitting = true
	_puffs.append([p, 0.0, life + 0.5])


func _flash(at_abs: Vector3, size: float, life: float) -> void:
	## A burst of light: a glowing disc that always faces the camera, quickly gone
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var mat: StandardMaterial3D = _flame_mat.duplicate()
	mat.albedo_color = Color(1.0, 0.9, 0.6, 1.0)
	mat.render_priority = 2
	mi.material_override = mat
	mi.set_meta("flash", size)
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = _scene(at_abs)
	_puffs.append([mi, 0.0, life])


func set_origin(dx: float, dz: float) -> void:
	## The scene origin moved by (dx, dz): move what's drawn relative to it
	for s in _shots:
		if s.has("node") and is_instance_valid(s.node):
			(s.node as Node3D).position = _scene(s.pos)
	for p in _puffs:
		if is_instance_valid(p[0]):
			(p[0] as Node3D).position -= Vector3(dx, 0, dz)
