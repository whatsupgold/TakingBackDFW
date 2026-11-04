class_name Artillery
extends Node3D
## M777 howitzer. Its crew is a real 4-man squad (section chief, gunner, loader, ammo bearer)
## that walks, rides in the Chinook and mans the gun when it's beside it. Idle crew within
## AUTO_MAN_RANGE walk over and man it on their own (unless you've ordered them elsewhere);
## right-click the gun with the crew selected to send them back.
## The Chinook can sling-load it, but only with its crew aboard (see Chinook).
##
## Calling for fire starts a fire mission: the crew lays the gun on the target and fires at
## it, one round per reload. In REPEAT mode (the default) it keeps firing until the mission is
## cancelled or replaced; in SINGLE mode it fires one round and stands down.
## Click the gun (or its card) to select it.
## Reload: 45 s with a full crew, 5 s faster per upgrade (5 upgrades, so 20 s at best).
## Each missing crewman slows the reload (3 crew = 3/4 speed); with no crew the gun is silent.
## Upgrades come from kills by its shells, same thresholds as squads (20, then +10 each).
## Its shells are one of the two things that can kill Red tanks (the A-10 is the other).
## The gun only covers a wedge in front of it; anything else gets "No available artillery".

signal message(text: String)
signal fired
signal impact(at: Vector3)
signal lifted(up: bool)           # hooked under a Chinook (true) or set down (false)

const BASE_TIME := 45.0
const MAX_SHELLS := 24            # rounds kept at the gun; refilled at the FOB or from a PLS
const TIME_STEP := 5.0
const MAX_LEVEL := 5
const FIRST_LEVEL_KILLS := 20
const LEVEL_KILL_STEP := 10

const ARC_HALF_DEG := 40.0        # field of fire: 80 degrees wide, centred on the barrel
const MIN_RANGE := 12.0
const MAX_RANGE := 450.0         # a real M777 reaches 24 km; this covers most of the compressed city
const BLAST_RADIUS := 6.0
const BLAST_DAMAGE := 220.0       # to soldiers (either side) at the centre; less further out
const BLAST_VEHICLE := 60.0       # to your own vehicles caught in it
const BLAST_TANK := 90.0          # to Red tanks (100 hp): a near miss takes two or three
const BLAST_STRUCTURE := 220.0    # to walls and gates (a Red FOB wall has 420: two hits)
const SPREAD := 3.0               # rounds land within this many metres of the target (one gun)
const SPREAD_PER_GUN := 5.0       # each extra gun on the same mission widens the circle this much
const TRAVERSE_SPEED := 0.5       # rad/s
const ELEVATE_SPEED := 0.35
const REST_ELEVATION := 12.0

# Where the crew stand (gun faces -Z) and where the load run goes
const RIFLE_CLOSE := {"range": 20.0}   # gun crews carry rifles for close defence
const SEATS := [
	{"role": "Section chief", "pos": Vector3(-2.3, 0.0, 0.2), "yaw": 0.35, "fires": true, "weapon": RIFLE_CLOSE},
	{"role": "Gunner", "pos": Vector3(-1.0, 0.0, 1.25), "yaw": -PI / 2.0, "fires": true, "weapon": RIFLE_CLOSE},
	{"role": "Loader", "pos": Vector3(1.0, 0.0, 1.35), "yaw": PI / 2.0},
	{"role": "Ammo bearer", "pos": Vector3(0.0, 0.0, 2.85), "yaw": 0.0},
]
const MAN_REACH := 3.2            # how close a crewman must get to take his place
const AUTO_MAN_RANGE := 16.0      # idle crew this close walk over and man the gun
const MAN_POINTS := [Vector3(-2.9, 0, 1.0), Vector3(2.9, 0, 1.0), Vector3(-2.6, 0, 3.4), Vector3(2.6, 0, 3.4)]
const CRATE_SPOT := Vector3(0.6, 0.0, 2.45)
const BREECH_SPOT := Vector3(0.6, 0.0, 1.6)

var enemy: RedArmy
var nav_map: RID
var display_name := "M777"
var model: VehicleModel
var crew_squad: Squad              # the gun crew (set by main before it's added)
var manned: Array[Soldier] = []    # crewmen at the gun, most important seat first
var slung_by: Node3D = null        # the Chinook carrying it
var _call_cd := 0.0
var _body: StaticBody3D

var level := 0
var kills := 0
var kills_into_level := 0
var next_level_at := FIRST_LEVEL_KILLS
var rounds_fired := 0

var has_mission := false
var mission_target := Vector3.ZERO
var repeat := true                # false: one round per fire mission
var mission_spread := SPREAD      # radius the rounds fall in (wider when several guns share a target)
var selected := false
var _ring: MeshInstance3D
var loaded := true
var shells := MAX_SHELLS
var reload_left := 0.0            # full-crew seconds until the next round is loaded

var _recoil := 0.0
var _shells: Array = []           # {node, from, to, t, dur, apex}
var _light: OmniLight3D
var _light_time := 0.0


func _ready() -> void:
	model = VehicleModel.m777(REST_ELEVATION)
	add_child(model)

	# Solid body so units path around the gun
	add_to_group("m777")
	var body := StaticBody3D.new()
	_body = body
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 1.4, 2.2)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.7, 0.2)
	body.add_child(col)
	add_child(body)

	_ring = GroundVehicle._make_ring(4.2, Color(0.95, 0.80, 0.45))
	_ring.visible = false
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	get_parent().add_child.call_deferred(_light)


# --- Orders -----------------------------------------------------------------

# --- As an obstacle on the navigation map (see Level.add_blocker) ------------------

func footprint_world() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in [Vector3(-1.7, 0, -1.5), Vector3(1.7, 0, -1.5), Vector3(1.7, 0, 4.5), Vector3(-1.7, 0, 4.5)]:
		out.append(global_transform * c)
	return out


func nav_part() -> Dictionary:
	return {"obs": [[footprint_world(), -1.0, 1.6]], "faces": PackedVector3Array()}


func cycle_time() -> float:
	return BASE_TIME - TIME_STEP * level


func reload_rate() -> float:
	return 0.0 if slung_by != null else manned.size() / float(SEATS.size())


func crew_count() -> int:
	return manned.size()


# --- Manning: the crew squad's soldiers take their seats ---------------------------

func in_reach(p: Vector3, _extra := 0.0) -> bool:
	if slung_by != null:
		return false
	for m in MAN_POINTS:
		var g := to_global(m)
		if Vector2(p.x - g.x, p.z - g.z).length() < MAN_REACH:
			return true
	return false


func door_point(from: Vector3) -> Vector3:
	var best := to_global(MAN_POINTS[0])
	for m in MAN_POINTS:
		var g := to_global(m)
		if from.distance_to(g) < from.distance_to(best):
			best = g
	return best


func board_soldier(s: Soldier) -> bool:
	## Called by a crewman walking to the gun once he's close enough
	if s.squad != crew_squad or slung_by != null or manned.size() >= SEATS.size():
		return false
	s.man_gun(self)
	manned.append(s)
	_assign()
	return true


func release(s: Soldier) -> void:
	## A crewman leaves the gun (a new order, or the gun is lifted)
	if not (s in manned):
		return
	manned.erase(s)
	s.leave_gun()
	_assign()


func release_all() -> void:
	for s in manned.duplicate():
		release(s)


func call_crew(nav_map: RID) -> int:
	## Send the gun crew to man the gun. Returns how many are on their way.
	if crew_squad == null or slung_by != null:
		return 0
	crew_squad.set_meta("stand_down", false)
	var n := 0
	for s in crew_squad.active_soldiers():
		if s.manning == self:
			continue
		s.order_move(NavigationServer3D.map_get_closest_point(nav_map, door_point(s.global_position)))
		s.board_target = self
		n += 1
	return n


func _assign() -> void:
	## Seats in order: the section chief and gunner carry rifles for close defence
	for i in manned.size():
		var s := manned[i]
		var seat: Dictionary = SEATS[i]
		s.can_fire = seat.get("fires", false)
		var w: Dictionary = seat.get("weapon", {})
		s.weapon_range = w.get("range", Soldier.RANGE)
		s.set_carry(false)
		s.anim_moving = false
		_put(s, seat.pos, seat.yaw)


func _put(s: Soldier, local_pos: Vector3, local_yaw: float) -> void:
	s.global_transform = Transform3D(global_basis * Basis(Vector3.UP, local_yaw), to_global(local_pos))


func _auto_man(nav_map: RID) -> void:
	## Idle crewmen near the gun go and man it
	if crew_squad == null or slung_by != null or crew_squad.get_meta("stand_down", false):
		return
	var coming := 0
	for s in crew_squad.soldiers:
		if s.board_target == self:
			coming += 1
	for s in crew_squad.active_soldiers():
		if manned.size() + coming >= SEATS.size():
			return
		if s.manning != null or s.board_target != null or s._has_order or s.chute or s.dead:
			continue
		if Vector2(s.global_position.x - global_position.x, s.global_position.z - global_position.z).length() > AUTO_MAN_RANGE:
			continue
		s.task_move(NavigationServer3D.map_get_closest_point(nav_map, door_point(s.global_position)))
		s.board_target = self
		coming += 1


# --- Sling load (the Chinook moves it) ------------------------------------------------

func hook(by: Node3D) -> void:
	release_all()
	has_mission = false
	slung_by = by
	_body.collision_layer = 0
	lifted.emit(true)


func set_down(at: Vector3, yaw: float) -> void:
	slung_by = null
	_body.collision_layer = 1
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	model.traverse.rotation.y = 0.0
	lifted.emit(false)


func seconds_to_ready() -> float:
	if loaded:
		return 0.0
	var rate := reload_rate()
	return INF if rate <= 0.0 else reload_left / rate


func in_field(target: Vector3) -> bool:
	var local := to_local(target)
	var dist := Vector2(local.x, local.z).length()
	var ang := absf(rad_to_deg(atan2(-local.x, -local.z)))
	return ang <= ARC_HALF_DEG and dist >= MIN_RANGE and dist <= MAX_RANGE


## Returns "" if the mission is accepted, otherwise the reason it isn't.
func call_fire(target: Vector3) -> String:
	if slung_by != null:
		return "No available artillery: the M777 is slung under the Chinook"
	if manned.is_empty():
		if crew_squad == null or crew_squad.soldiers.is_empty():
			return "No available artillery: the M777 crew is down"
		return "No available artillery: nobody is manning the M777"
	if shells <= 0:
		return "%s has no shells left: resupply it at the FOB or from a PLS" % display_name
	if not in_field(target):
		return "No available artillery"
	mission_target = target
	has_mission = true
	return ""


static func spread_for(guns: int) -> float:
	## Several guns on one target: each round lands somewhere random in a wider circle
	return SPREAD + SPREAD_PER_GUN * maxf(0.0, guns - 1)


func cancel() -> void:
	has_mission = false


func set_selected(value: bool) -> void:
	selected = value
	_ring.visible = value


# --- Every physics tick -----------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_shells(delta)
	if _light_time > 0.0:
		_light_time -= delta
		_light.light_energy = maxf(0.0, _light_time / 0.25) * 8.0
	if slung_by != null:
		return
	_call_cd -= delta
	if _call_cd <= 0.0:
		_call_cd = 0.5
		_auto_man(nav_map)
	var rate := reload_rate()
	if not loaded and rate > 0.0:
		reload_left -= delta * rate
		if reload_left <= 0.0:
			reload_left = 0.0
			loaded = true

	var laid := _lay_gun(delta)
	if has_mission and loaded and laid and not manned.is_empty():
		if shells <= 0:
			has_mission = false
			message.emit("%s is out of shells: bring it near the FOB, or a PLS with a shell pallet" % display_name)
		else:
			_fire()

	_recoil = move_toward(_recoil, 0.0, delta * 0.8)
	model.recoil.position.z = _recoil
	_animate_crew()


func _lay_gun(delta: float) -> bool:
	## Turn and elevate toward the target (or the rest position). True once on target.
	var want_yaw := 0.0
	var want_elev := deg_to_rad(REST_ELEVATION)
	if has_mission:
		var local := to_local(mission_target)
		var dist := Vector2(local.x, local.z).length()
		want_yaw = clampf(atan2(-local.x, -local.z), -deg_to_rad(ARC_HALF_DEG), deg_to_rad(ARC_HALF_DEG))
		want_elev = deg_to_rad(12.0 + clampf(dist / MAX_RANGE, 0.0, 1.0) * 48.0)
	if not manned.is_empty():
		model.traverse.rotation.y = move_toward(model.traverse.rotation.y, want_yaw, TRAVERSE_SPEED * delta)
		model.cradle.rotation.x = move_toward(model.cradle.rotation.x, want_elev, ELEVATE_SPEED * delta)
	return absf(model.traverse.rotation.y - want_yaw) < 0.01 and absf(model.cradle.rotation.x - want_elev) < 0.01


func _fire() -> void:
	loaded = false
	shells -= 1
	reload_left = cycle_time()
	rounds_fired += 1
	_recoil = 0.9
	if not repeat:
		has_mission = false        # single shot: the round's away, stand down

	var muzzle := model.recoil.to_global(Vector3(0, 0.02, -6.3))
	var dir := -model.recoil.global_basis.z.normalized()
	enemy.gibs.muzzle_blast(muzzle, dir)

	# Where this round will land: near the target, on whatever surface is there
	var ang := randf() * TAU
	var r := sqrt(randf()) * mission_spread
	var land := mission_target + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	var q := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 200.0, land + Vector3.DOWN * 20.0, 1 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		land = hit.position

	var shell := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.22, 0.22, 0.7)
	shell.mesh = m
	shell.material_override = Level.make_material(Color(0.25, 0.25, 0.22))
	get_parent().add_child(shell)
	shell.global_position = muzzle
	var dist := Vector2(land.x - muzzle.x, land.z - muzzle.z).length()
	_shells.append({"node": shell, "from": muzzle, "to": land, "t": 0.0,
		"dur": clampf(dist / 60.0, 1.8, 8.0), "apex": maxf(12.0, dist * 0.3)})
	fired.emit()


func _update_shells(delta: float) -> void:
	var i := 0
	while i < _shells.size():
		var s: Dictionary = _shells[i]
		s.t += delta
		var f := clampf(s.t / s.dur, 0.0, 1.0)
		var p: Vector3 = (s.from as Vector3).lerp(s.to, f) + Vector3.UP * s.apex * 4.0 * f * (1.0 - f)
		var node: MeshInstance3D = s.node
		var prev := node.global_position
		node.global_position = p
		if p.distance_to(prev) > 0.01:
			node.look_at(p + (p - prev), Vector3.UP)
		if f >= 1.0:
			node.queue_free()
			_shells.remove_at(i)
			_impact(s.to)
			continue
		i += 1


func is_targetable() -> bool:
	## Red tanks fire on the gun while it's manned (the blast is what hurts the crew)
	return slung_by == null and not manned.is_empty()


func take_vehicle_damage(_amount: float) -> void:
	pass


func _impact(at: Vector3) -> void:
	enemy.blast(at, BLAST_RADIUS, BLAST_DAMAGE, BLAST_VEHICLE, BLAST_TANK, self, false, BLAST_STRUCTURE)
	_light.global_position = at + Vector3.UP * 2.0
	_light_time = 0.25
	impact.emit(at)


func add_kill() -> void:
	kills += 1
	if level >= MAX_LEVEL:
		return
	kills_into_level += 1
	if kills_into_level < next_level_at:
		return
	kills_into_level = 0
	next_level_at += LEVEL_KILL_STEP
	level += 1
	message.emit("M777 upgraded: %d s per shot (level %d/%d)" % [int(cycle_time()), level, MAX_LEVEL])


# --- Crew animation: fetch a round, carry it to the breech, ram, step back ---

func _animate_crew() -> void:
	var n := manned.size()
	if n == 0:
		return
	# Everyone at his seat (the gun may have been turned)
	for i in n:
		_put(manned[i], SEATS[i].pos, SEATS[i].yaw)
	# The lowest seat still filled does the carrying (normally the ammo bearer)
	var carrier_seat := mini(3, n - 1)
	var carrier := manned[carrier_seat]
	var home: Vector3 = SEATS[carrier_seat].pos
	var rammer: Soldier = manned[2] if n > 2 and carrier_seat != 2 else null

	var r := 0.0 if loaded else reload_left   # full-crew seconds left; the run fits the last 8
	var pos := home
	var moving := false
	var carrying := false
	if not loaded:
		if r > 8.0:
			pos = home
		elif r > 6.5:
			pos = home.lerp(CRATE_SPOT, (8.0 - r) / 1.5)
			moving = true
		elif r > 5.5:
			pos = CRATE_SPOT
			carrying = r < 6.0
		elif r > 3.5:
			pos = CRATE_SPOT.lerp(BREECH_SPOT, (5.5 - r) / 2.0)
			moving = true
			carrying = true
		elif r > 2.5:
			pos = BREECH_SPOT
			carrying = r > 3.0
		elif r > 0.5:
			pos = BREECH_SPOT.lerp(home, (2.5 - r) / 2.0)
			moving = true
	var yaw: float = SEATS[carrier_seat].yaw
	var prev: Vector3 = carrier.get_meta("seat_pos", home)
	var step := pos - prev
	carrier.set_meta("seat_pos", pos)
	if moving and step.length() > 0.0001:
		yaw = atan2(-step.x, -step.z)
	elif not moving and pos != home:
		yaw = PI / 2.0    # at the crate or breech: facing the gun's centreline
	carrier.anim_moving = moving
	carrier.set_carry(carrying)
	_put(carrier, pos, yaw)

	# The loader rams the round home, then steps back
	if rammer != null and not loaded and r < 3.2 and r > 2.4:
		var push := sin((3.2 - r) / 0.8 * PI)
		_put(rammer, (SEATS[2].pos as Vector3).lerp(Vector3(0.35, 0.0, 1.3), push), SEATS[2].yaw)
