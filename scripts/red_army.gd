class_name RedArmy
extends Node3D
## The enemy. The Red Army holds its FOB in Fair Park on the east edge (see RedFob): the one
## objective, which you have to breach and take. While it holds it:
## - every RED_UNIT_INTERVAL a new unit arrives there (squad, tank, squad, anti-air, ...),
## - every GROW_INTERVAL the base grows by another walled section (up to RedFob.STEPS),
## - every COUNTERATTACK_INTERVAL a counterattack (riflemen, every other time a tank) comes out
##   of its west gate toward your FOB.
## The longer you take, the bigger and better defended it gets. Take it and it all stops.
##
## Also the shared combat service for both sides: who can shoot whom, bullet tracers, tank
## shells, and blasts (artillery, A-10 cannon, tank rounds).
##
## Objectives: you take one back when no Red unit is left inside its circle and at least one
## of yours is standing in it for CAPTURE_TIME. Red takes it back the same way (slower).

signal message(text: String)
signal objective_changed(obj: Dictionary)

const AI_INTERVAL := 0.5
const OBJECTIVE_RADIUS := 32.0
const CAPTURE_TIME := 6.0
const RECAPTURE_TIME := 14.0
const FIRST_COUNTERATTACK := 240.0
const COUNTERATTACK_INTERVAL := 240.0
const RED_UNIT_INTERVAL := 120.0
const RED_UNITS := ["squad", "tank", "squad", "aa"]   # what arrives, in turn
const GROW_INTERVAL := 300.0
const GROW_RETRY := 15.0          # your units are standing where it wants to build: try again
const MAX_ALIVE := 120
const TRACER_LIFE := 0.06
const SHELL_SPEED := 850.0        # m/s, tank HE round
const SQUAD_SIZE := 6

# Where the Red Army is dug in (snapped to walkable ground when deployed). Each sits on the
# far side of its landmark from the FOB, so the stadiums block the line of fire at the start.
const OBJECTIVES := [
	{"name": "Red FOB", "pos": Vector3(816, 0, 116), "squads": 3, "tanks": 2, "aa": 1, "fob": true},
]
# The old Arlington garrisons: only placed for the self-test (legacy_objectives)
const LEGACY_OBJECTIVES := [
	{"name": "Globe Life Field", "pos": Vector3(-180, 0, -35), "squads": 1, "tanks": 1},
	{"name": "AT&T Stadium", "pos": Vector3(-120, 0, 172), "squads": 2, "tanks": 1},
	{"name": "Downtown Arlington", "pos": Vector3(205, 0, 40), "squads": 2, "tanks": 2},
]
const FOB_CATWALK := 8          # riflemen on the west catwalk
# Counterattacks come in from these directions (picked far from your units)
const STAGING := [Vector3(-260, 0, 60), Vector3(60, 0, 230), Vector3(260, 0, -40), Vector3(-60, 0, -200), Vector3(250, 0, 160)]

class RedSquad:
	var members: Array = []        # RedSoldier and RedTank
	var role := "garrison"         # garrison: hold the post; assault: move on the target
	var post := Vector3.ZERO
	var target := Vector3.ZERO
	var objective := {}

	func alive_members() -> Array:
		return members.filter(func(m): return is_instance_valid(m) and m.alive)


var soldiers: Array[Soldier] = []   # your soldiers the Red Army can see and shoot (exposed)
var alive: Array = []               # living Red riflemen
var tanks: Array = []               # living Red tanks
var squads: Array = []              # RedSquad
var objectives: Array = []          # {name, pos, owner ("red"/"blue"), progress, label}
var vehicles: Array = []            # your vehicles tanks can shoot at (set by main)
var anchors: Array[Vector3] = []    # where your units are (set by main)
var fob := Vector3.ZERO
var red_fob: RedFob
var legacy_objectives := false     # the self-test still fights over Arlington
var next_unit_in := RED_UNIT_INTERVAL
var grow_in := GROW_INTERVAL
var units_arrived := 0
var _new_towers: Array = []
var nav_map: RID
var level: Level
var gibs: Gibs
var spawning_enabled := true
var deployed := false
var kills := 0                     # Red riflemen killed
var tanks_destroyed := 0
var wave := 0
var next_wave_in := FIRST_COUNTERATTACK

var _ai_cd := 0.0
var _tracers: Array = []            # [from, to, time_left, red]
var _tracer_mesh: ImmediateMesh
var _shells: Array = []             # {node, from, to, t, dur}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026
	gibs = Gibs.new()
	add_child(gibs)
	_tracer_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Setup --------------------------------------------------------------------

func build_fob() -> void:
	## The Red FOB's walls go up with the city (before the navigation map is baked)
	red_fob = RedFob.new()
	red_fob.build(level)


func deploy() -> void:
	## Put the garrisons in place (called once the map around the FOB is built)
	if deployed:
		return
	deployed = true
	var defs: Array = []
	if legacy_objectives:
		defs.append_array(LEGACY_OBJECTIVES)
	defs.append_array(OBJECTIVES)
	for def in defs:
		var p := _snap(RedFob.center() if def.get("fob", false) else def.pos)
		var obj := {"name": def.name, "pos": p, "owner": "red", "progress": 0.0, "red": 0, "blue": 0}
		obj["label"] = _make_label(def.name, p)
		objectives.append(obj)
		for i in def.squads:
			var sq := _new_squad("garrison", p)
			sq.objective = obj
			for k in SQUAD_SIZE:
				var spot := _snap(p + _ring_offset(i * SQUAD_SIZE + k, def.squads * SQUAD_SIZE, 8.0, 22.0))
				sq.members.append(spawn_soldier(spot, sq))
		for i in def.tanks:
			var sq := _new_squad("garrison", p)
			sq.objective = obj
			var spot := _snap(p + _ring_offset(i, def.tanks, 10.0, 14.0))
			sq.members.append(spawn_tank(spot, _rng.randf_range(0, 360), sq))
		for i in def.get("aa", 0):
			var sq := _new_squad("garrison", p)
			sq.objective = obj
			sq.members.append(spawn_aa(_snap(p + Vector3(-14 + 28 * i, 0, 4)), 270.0, sq))
		if def.get("fob", false) and red_fob != null:
			obj["fob"] = true
			_man_fob_walls(obj)


func _man_fob_walls(obj: Dictionary) -> void:
	## Riflemen on the catwalk facing the city, a machine gunner on every tower
	var sq := _new_squad("garrison", obj.pos)
	sq.objective = obj
	for spot in red_fob.catwalk_posts(FOB_CATWALK):
		var s := spawn_soldier(spot, sq)
		s.rotation.y = PI * 0.5      # facing west
		sq.members.append(s)
	_man_towers(obj, red_fob.tower_tops())


func _man_towers(obj: Dictionary, tops: Array) -> void:
	var towers := _new_squad("garrison", obj.pos)
	towers.objective = obj
	for top in tops:
		var g := spawn_soldier(top, towers)
		g.fixed = true
		g.weapon_range = RedFob.TOWER_GUNNER.range
		g.fire_interval = RedFob.TOWER_GUNNER.interval
		g.damage = RedFob.TOWER_GUNNER.damage
		towers.members.append(g)


func fob_mapped() -> bool:
	## Is the inside of the Red FOB on the navigation map yet? (its garrison is placed on it)
	if red_fob == null:
		return true
	var c := RedFob.center()
	var p := NavigationServer3D.map_get_closest_point(nav_map, c)
	return Vector2(p.x - c.x, p.z - c.z).length() < 3.0


func fob_objective() -> Dictionary:
	for o in objectives:
		if o.get("fob", false):
			return o
	return {}


func fob_held() -> bool:
	## Does the Red Army still hold its FOB? (that's where its reinforcements come in)
	var o := fob_objective()
	return not o.is_empty() and o.owner == "red"


func _ring_offset(i: int, n: int, r_min: float, r_max: float) -> Vector3:
	var a := TAU * float(i) / maxf(1.0, n) + _rng.randf_range(-0.3, 0.3)
	var r := _rng.randf_range(r_min, r_max)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _new_squad(role: String, post: Vector3) -> RedSquad:
	var sq := RedSquad.new()
	sq.role = role
	sq.post = post
	sq.target = post
	squads.append(sq)
	return sq


func spawn_soldier(pos: Vector3, sq: RedSquad = null) -> RedSoldier:
	var s := RedSoldier.new()
	s.army = self
	s.squad = sq
	add_child(s)
	s.global_position = pos + Vector3.UP * 0.1
	s.post = pos
	alive.append(s)
	return s


func spawn_aa(pos: Vector3, yaw_deg: float, sq: RedSquad = null) -> RedAA:
	## Anti-air: shoots A-10s and helicopters in the air. Counts as a tank (heavy weapons only).
	var t := RedAA.new()
	t.army = self
	t.squad = sq
	t.nav_map = nav_map
	add_child(t)
	t.place(pos, yaw_deg)
	tanks.append(t)
	return t


func aa_count() -> int:
	var n := 0
	for t in tanks:
		if t is RedAA:
			n += 1
	return n


func spawn_tank(pos: Vector3, yaw_deg: float, sq: RedSquad = null) -> RedTank:
	var t := RedTank.new()
	t.army = self
	t.squad = sq
	t.nav_map = nav_map
	add_child(t)
	t.place(pos, yaw_deg)
	tanks.append(t)
	return t


func counterattack(with_tank: bool) -> void:
	## Out of the Red FOB's west gate: a squad (and maybe a tank) for the nearest point you hold,
	## or your FOB. Also tops the FOB garrison back up. Nothing once you've taken the Red FOB.
	if red_fob != null and not fob_held():
		return
	wave += 1
	var start := _snap(red_fob.sally_point()) if red_fob != null else _staging_point()
	var goal := fob
	var goal_obj := {}
	var best := INF
	for o in objectives:
		if o.owner == "blue" and start.distance_to(o.pos) < best:
			best = start.distance_to(o.pos)
			goal = o.pos
			goal_obj = o
	var sq := _new_squad("assault", goal)
	sq.objective = goal_obj
	for k in SQUAD_SIZE:
		sq.members.append(spawn_soldier(_snap(start + _ring_offset(k, SQUAD_SIZE, 2.0, 6.0)), sq))
	if with_tank:
		var yaw := rad_to_deg(atan2(-(goal.x - start.x), -(goal.z - start.z)))
		sq.members.append(spawn_tank(_snap(start + Vector3(0, 0, 8)), yaw, sq))
	var where: String = goal_obj.name if not goal_obj.is_empty() else "the FOB"
	message.emit("Red Army counterattack%s out of the Red FOB, heading for %s" % [" with armor" if with_tank else "", where])
	_order_squad(sq, goal)


func red_unit() -> void:
	## A new unit for the Red FOB garrison (from the edge of the map behind it)
	var o := fob_objective()
	if o.is_empty() or red_fob == null or alive.size() >= MAX_ALIVE:
		return
	var kind: String = RED_UNITS[units_arrived % RED_UNITS.size()]
	units_arrived += 1
	var spot := _snap(red_fob.random_inside(_rng))
	var sq := _new_squad("garrison", spot)
	sq.objective = o
	match kind:
		"squad":
			for k in SQUAD_SIZE:
				sq.members.append(spawn_soldier(_snap(spot + _ring_offset(k, SQUAD_SIZE, 2.0, 7.0)), sq))
			message.emit("Red Army reinforced: a rifle squad arrived at the Red FOB")
		"tank":
			sq.members.append(spawn_tank(spot, 270.0, sq))
			message.emit("Red Army reinforced: a tank arrived at the Red FOB")
		"aa":
			sq.members.append(spawn_aa(spot, 270.0, sq))
			message.emit("Red Army reinforced: an anti-air vehicle arrived at the Red FOB. Watch your A-10s and helicopters")


func grow_fob(blockers: Array) -> String:
	## Start the next section of the Red FOB. Returns "" or why it can't right now.
	if red_fob == null:
		return "none"
	var why := red_fob.can_grow(level, blockers)
	if why != "":
		return why
	_new_towers = red_fob.grow(level)
	message.emit("The Red FOB is expanding: new walls going up (%d of %d)" % [red_fob.steps_done, RedFob.STEPS.size()])
	return ""


func _section_up() -> void:
	## A new section of the Red FOB is finished: gunners up the new towers
	var o := fob_objective()
	if not o.is_empty():
		_man_towers(o, red_fob.tower_tops(_new_towers))
	_new_towers.clear()
	message.emit("The Red FOB has grown: another walled section and two more towers")


func _staging_point() -> Vector3:
	var picks: Array = []
	for p in STAGING:
		var far := true
		for a in anchors:
			if Vector2(a.x - p.x, a.z - p.z).length() < 140.0:
				far = false
		if far:
			picks.append(p)
	if picks.is_empty():
		picks = STAGING.duplicate()
	return _snap(picks[_rng.randi() % picks.size()])


func _snap(p: Vector3) -> Vector3:
	## Street level only: never on a roof or inside a building (see Level.ground_spot)
	if level != null:
		return level.ground_spot(p, 24.0)
	var s := NavigationServer3D.map_get_closest_point(nav_map, p)
	return p if s == Vector3.ZERO else s


func _make_label(text: String, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.05
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.45, 0.35)
	l.position = at + Vector3.UP * 9.0
	add_child(l)
	return l


# --- Brain ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_shells(delta)
	if not deployed:
		return
	if red_fob != null and red_fob.tick(delta):
		_section_up()
	_ai_cd -= delta
	if _ai_cd > 0.0:
		return
	_ai_cd = AI_INTERVAL
	_update_objectives(AI_INTERVAL)
	for sq in squads.duplicate():
		var live: Array = sq.alive_members()
		if live.is_empty():
			squads.erase(sq)
			continue
		if sq.role == "assault":
			var lead: Node3D = live[0]
			if Vector2(lead.global_position.x - sq.target.x, lead.global_position.z - sq.target.z).length() < 14.0:
				# Arrived: dig in here
				sq.role = "garrison"
				sq.post = sq.target
				for m in live:
					m.post = _snap(sq.post + _ring_offset(live.find(m), live.size(), 4.0, 14.0))
					m.order_move(m.post)
	if spawning_enabled and (red_fob == null or fob_held()):
		next_wave_in -= AI_INTERVAL
		if next_wave_in <= 0.0:
			next_wave_in = COUNTERATTACK_INTERVAL
			if alive.size() < MAX_ALIVE:
				counterattack(wave % 2 == 1)
		if red_fob != null:
			next_unit_in -= AI_INTERVAL
			if next_unit_in <= 0.0:
				next_unit_in = RED_UNIT_INTERVAL
				red_unit()
			if red_fob.steps_done < RedFob.STEPS.size():
				grow_in -= AI_INTERVAL
				if grow_in <= 0.0:
					var blockers: Array = []
					for sd in soldiers:
						if is_instance_valid(sd):
							blockers.append(sd.global_position)
					for v in vehicles:
						if is_instance_valid(v) and v.visible:
							blockers.append(v.global_position)
					grow_in = GROW_INTERVAL if grow_fob(blockers) == "" else GROW_RETRY


func _order_squad(sq: RedSquad, goal: Vector3) -> void:
	var n: int = sq.members.size()
	for i in n:
		var m = sq.members[i]
		m.order_move(_snap(goal + _ring_offset(i, n, 2.0, 8.0)))


func _update_objectives(dt: float) -> void:
	for o in objectives:
		var red := 0
		for s in alive:
			if _flat(s.global_position, o.pos) < OBJECTIVE_RADIUS:
				red += 1
		for t in tanks:
			if _flat(t.global_position, o.pos) < OBJECTIVE_RADIUS:
				red += 1
		var blue := 0
		for s in soldiers:
			if not s.mounted and _flat(s.global_position, o.pos) < OBJECTIVE_RADIUS:
				blue += 1
		for v in vehicles:
			if v is GroundVehicle and v.is_targetable() and _flat(v.global_position, o.pos) < OBJECTIVE_RADIUS:
				blue += 1
		o.red = red
		o.blue = blue
		var was: String = o.owner
		if o.owner == "red":
			if red == 0 and blue > 0:
				o.progress = minf(1.0, o.progress + dt / CAPTURE_TIME)
			else:
				o.progress = maxf(0.0, o.progress - dt / CAPTURE_TIME)
			if o.progress >= 1.0:
				o.owner = "blue"
				message.emit("%s taken back!" % o.name)
		else:
			if red > 0 and blue == 0:
				o.progress = maxf(0.0, o.progress - dt / RECAPTURE_TIME)
			else:
				o.progress = minf(1.0, o.progress + dt / RECAPTURE_TIME)
			if o.progress <= 0.0:
				o.owner = "red"
				message.emit("The Red Army retook %s" % o.name)
		(o.label as Label3D).modulate = Color(0.55, 0.8, 1.0) if o.owner == "blue" else Color(1.0, 0.45, 0.35)
		if o.owner != was:
			objective_changed.emit(o)


func objectives_held() -> int:
	var n := 0
	for o in objectives:
		if o.owner == "blue":
			n += 1
	return n


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Targeting -------------------------------------------------------------------

func clear_line(from: Vector3, to: Vector3) -> bool:
	## Nothing solid (buildings, walls, ground) between the two points
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func find_shot_target(eye: Vector3, max_range: float) -> RedSoldier:
	## For your soldiers and vehicle guns: the nearest Red rifleman in sight.
	## Tanks aren't on the list: small arms can't hurt them.
	var r2 := max_range * max_range
	var candidates: Array = []
	for s in alive:
		var d := eye.distance_squared_to(s.global_position)
		if d < r2:
			candidates.append([d, s])
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(4, candidates.size()):
		var s: RedSoldier = candidates[i][1]
		if clear_line(eye, s.global_position + Vector3.UP * 1.0):
			return s
	return null


func find_player_target(eye: Vector3, max_range: float) -> Soldier:
	## For Red riflemen and tank MGs: the nearest of your exposed soldiers in sight
	var r2 := max_range * max_range
	var candidates: Array = []
	for s in soldiers:
		if not is_instance_valid(s) or s.dead:
			continue
		var d := eye.distance_squared_to(s.global_position)
		if d < r2:
			candidates.append([d, s])
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(4, candidates.size()):
		var s: Soldier = candidates[i][1]
		if clear_line(eye, s.global_position + Vector3.UP * 1.1):
			return s
	return null


func find_vehicle_target(eye: Vector3, max_range: float) -> Node3D:
	## For tank guns: the nearest of your vehicles in sight
	var best: Node3D = null
	var best_d := max_range
	for v in vehicles:
		if not is_instance_valid(v) or not v.is_targetable():
			continue
		var d := eye.distance_to(v.global_position)
		if d < best_d and clear_line(eye, v.global_position + Vector3.UP * 1.2):
			best_d = d
			best = v
	return best


# --- Shots, shells and blasts ------------------------------------------------------

func add_tracer(from: Vector3, to: Vector3, red := false) -> void:
	_tracers.append([from, to, TRACER_LIFE, red])


func fire_shell(from: Vector3, to: Vector3) -> void:
	## A tank round: a fast streak, then a blast that wrecks vehicles and kills infantry
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.25, 1.2)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = Level.make_material(Color(1.0, 0.75, 0.35), true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = from
	gibs.muzzle_blast(from, (to - from).normalized())
	_shells.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": maxf(0.05, from.distance_to(to) / SHELL_SPEED)})


func _update_shells(delta: float) -> void:
	var i := 0
	while i < _shells.size():
		var s: Dictionary = _shells[i]
		s.t += delta
		var f := clampf(s.t / s.dur, 0.0, 1.0)
		var node: MeshInstance3D = s.node
		var p: Vector3 = (s.from as Vector3).lerp(s.to, f)
		node.global_position = p
		if (s.to as Vector3).distance_to(s.from) > 0.1:
			node.look_at(p + ((s.to as Vector3) - (s.from as Vector3)), Vector3.UP)
		if f >= 1.0:
			node.queue_free()
			_shells.remove_at(i)
			blast(s.to, 4.0, 160.0, 40.0, 0.0, null, false, 40.0)
			continue
		i += 1


func blast(at: Vector3, radius: float, dmg_soldier: float, dmg_vehicle: float, dmg_tank: float, credit, small := false, dmg_structure := 0.0) -> int:
	## Damage everything near `at` (both sides). Damage falls off to nothing at the edge.
	## `credit` (a Squad, an Artillery or an A10) gets the kills. Returns Red units killed.
	## `dmg_structure` wears down walls, gates and buildings (yours and the Red FOB's).
	var killed := 0
	if dmg_structure > 0.0 and level != null:
		level.damage_structures(at, radius * 0.6, dmg_structure)
	for s in alive.duplicate():
		var d: float = s.global_position.distance_to(at)
		if d < radius:
			if s.take_hit(dmg_soldier * (1.0 - d / radius), (s.global_position - at).normalized(), null):
				killed += 1
	if dmg_tank > 0.0:
		for t in tanks.duplicate():
			var d: float = maxf(0.0, t.global_position.distance_to(at) - 2.5)
			if d < radius:
				if t.take_damage(dmg_tank * (1.0 - d / radius)):
					killed += 1
	for s in soldiers.duplicate():
		if not is_instance_valid(s):
			continue
		var d: float = s.global_position.distance_to(at)
		if d < radius:
			s.take_damage(dmg_soldier * (1.0 - d / radius))
	if dmg_vehicle > 0.0:
		for v in vehicles:
			if not is_instance_valid(v) or not v.is_targetable():
				continue
			var d: float = maxf(0.0, v.global_position.distance_to(at) - 2.5)
			if d < radius:
				v.take_vehicle_damage(dmg_vehicle * (1.0 - d / radius))
	if small:
		gibs.impact(at)
	else:
		gibs.explosion(at)
	if credit != null and killed > 0 and credit.has_method("add_kill"):
		for k in killed:
			credit.add_kill()
	return killed


func on_soldier_died(s: RedSoldier) -> void:
	alive.erase(s)
	kills += 1


func on_tank_destroyed(t: RedTank) -> void:
	tanks.erase(t)
	tanks_destroyed += 1
	message.emit("Red anti-air destroyed" if t is RedAA else "Red tank destroyed")


func _process(delta: float) -> void:
	_tracer_mesh.clear_surfaces()
	var i := 0
	var any := false
	while i < _tracers.size():
		_tracers[i][2] -= delta
		if _tracers[i][2] <= 0.0:
			_tracers.remove_at(i)
		else:
			i += 1
	if _tracers.is_empty():
		return
	_tracer_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for t in _tracers:
		_tracer_mesh.surface_set_color(Color(1.0, 0.45, 0.30) if t[3] else Color(1.0, 0.92, 0.45))
		_tracer_mesh.surface_add_vertex(t[0])
		_tracer_mesh.surface_add_vertex(t[1])
		any = true
	if any:
		_tracer_mesh.surface_end()
