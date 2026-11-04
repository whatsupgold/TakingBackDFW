class_name Soldier
extends CharacterBody3D
## One soldier. Moves on the navmesh, auto-fires at the nearest Red rifleman he can see.
## Rifles can't hurt tanks, so soldiers don't waste ammo on them.
## A "mounted" soldier is vehicle crew: he sits in a seat the vehicle controls (see Crew),
## doesn't walk or collide, and may or may not fire or be shot at.

const SPEED := 4.5
const GRAVITY := 20.0
const RANGE := 32.0
const FIRE_INTERVAL := 0.22
const RELOAD_TIME := 2.0
const MAX_HEALTH := 100.0
const EYE_HEIGHT := 1.45
const MISS_SPREAD := 1.4
const ARRIVE_DISTANCE := 0.25
const RIFLE_DAMAGE := 25.0       # per hit at squad weapons level 0 (Red riflemen have 100 hp)
const BODY_LIFE := 25.0
const CARRY := 280                # rounds each soldier carries (magazines included)

var squad: Squad
var enemy: RedArmy
var health := MAX_HEALTH
var ammo := 0                     # rounds in the magazine
var rounds := CARRY               # rounds he has left in all (the magazine included)
var gun_source: Node = null       # vehicle crew on a mounted gun: they fire the vehicle's rounds
var dead := false

var _agent: NavigationAgent3D
var _has_order := false
var _face := Vector3.ZERO     # direction to face on arrival (from a line formation)
var _fire_cd := 0.0
var _reload := 0.0
var _ring: MeshInstance3D
var _model: SoldierModel
var _col: CollisionShape3D

# Crew and transport
var mounted := false          # vehicle crew: no walking, no collision
var can_fire := true
var exposed := true           # in enemy.soldiers: the Red Army can shoot him
var anim_moving := false      # set by a vehicle that walks this crewman around
var boarded := false          # riding in a helicopter or Stryker: hidden and inactive
var board_target: Node3D = null   # transport this soldier is walking to
var manual := false               # following an order you gave (engineers pause building)
var manning: Node3D = null       # the M777 he's crewing (it places him at his seat)
var chute := false                # coming down under a parachute (an ejected pilot)
var _canopy: MeshInstance3D
var last_target := Vector3.ZERO   # where he last fired (vehicles aim turrets with it)
var target_time := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _sidestep := Vector3.ZERO
var _sidestep_t := 0.0
var _repath_cd := 0.0
var _goal_retry := 0.0        # seconds left to keep asking for a path that reaches the goal
const GOAL_RETRY := 20.0      # (a wall just blown or a gate just built changes the map)

# Weapon (crew seats override these with mounted guns)
var weapon_range := RANGE
var fire_interval := FIRE_INTERVAL
var damage_mult := 1.0
var accuracy_bonus := 0.0
var mag_override := 0
var reload_time := RELOAD_TIME


func _ready() -> void:
	collision_layer = 0 if mounted else 2
	collision_mask = 1 | 4 | 8 | 16    # 16: Red gate leaves
	floor_max_angle = deg_to_rad(40.0)
	add_to_group("soldiers")

	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.85
	col.disabled = mounted
	add_child(col)
	_col = col

	_model = SoldierModel.new()
	add_child(_model)
	var leader := squad.soldiers.is_empty() or squad.soldiers[0] == self
	_model.build(squad.color, false, squad.kind, leader and squad.kind == "rifle")
	_model.allow_kneel = not mounted

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.65
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 4
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.position.y = 0.06
	_ring.material_override = Level.make_material(squad.color.lightened(0.4), true)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	_agent = NavigationAgent3D.new()
	_agent.path_search_max_polygons = Level.PATH_POLYS
	# Navmesh polygons sit a little above the floor, so these are measured generously
	_agent.path_desired_distance = 0.65
	_agent.target_desired_distance = 0.3
	_agent.radius = 0.45
	_agent.height = 1.8
	add_child(_agent)

	ammo = mini(_mag(), rounds)
	_fire_cd = randf() * FIRE_INTERVAL


func set_selected(value: bool) -> void:
	if _ring:
		_ring.visible = value


func order_move(p: Vector3, face := Vector3.ZERO) -> void:
	if manning != null:
		manning.release(self)
	if boarded or mounted:
		return
	_agent.target_position = p
	_face = face
	_has_order = true
	board_target = null
	manual = true
	_goal_retry = GOAL_RETRY


func task_move(p: Vector3, face := Vector3.ZERO) -> void:
	## A move the game gives (engineers walking to their work), not one you gave
	order_move(p, face)
	manual = false


func man_gun(g: Node3D) -> void:
	## Take a seat at the M777: the gun places and animates him from now on
	manning = g
	board_target = null
	_has_order = false
	manual = false
	velocity = Vector3.ZERO
	_col.disabled = true
	collision_layer = 0


func leave_gun() -> void:
	manning = null
	_col.disabled = false
	collision_layer = 2
	can_fire = true
	weapon_range = RANGE
	anim_moving = false
	set_carry(false)
	_agent.target_position = global_position


func open_chute() -> void:
	chute = true
	var m := BoxMesh.new()
	m.size = Vector3(3.2, 0.5, 2.4)
	_canopy = MeshInstance3D.new()
	_canopy.mesh = m
	_canopy.material_override = Level.make_material(Color(0.86, 0.84, 0.74))
	_canopy.position = Vector3(0, 4.2, 0)
	add_child(_canopy)
	for x in [-1.4, 1.4]:
		var line := BoxMesh.new()
		line.size = Vector3(0.04, 2.6, 0.04)
		var li := MeshInstance3D.new()
		li.mesh = line
		li.material_override = Level.make_material(Color(0.2, 0.2, 0.2))
		li.position = Vector3(x * 0.5, 2.8, 0)
		li.rotation.z = -x * 0.35
		add_child(li)
		li.set_meta("chute", true)

func stop() -> void:
	_has_order = false
	_agent.target_position = global_position


func on_squad_upgrade() -> void:
	# New magazine size applies right away
	ammo = mini(_mag(), rounds) if gun_source == null else _mag()


func out_of_ammo() -> bool:
	if gun_source != null:
		return gun_source.gun_rounds <= 0
	return rounds <= 0


func top_up(available: int) -> int:
	## Refill his rounds from a supply (ammo cans, the FOB). Returns how many he took.
	var take := mini(CARRY - rounds, maxi(0, available))
	if take <= 0:
		return 0
	var was_empty := rounds <= 0
	rounds += take
	if was_empty or ammo <= 0:
		ammo = mini(_mag(), rounds)
		_reload = 0.0
	return take


func _mag() -> int:
	return mag_override if mag_override > 0 else squad.mag_size()


func set_exposed(value: bool) -> void:
	exposed = value
	if enemy == null:
		return
	if value and not (self in enemy.soldiers):
		enemy.soldiers.append(self)
	elif not value:
		enemy.soldiers.erase(self)


func set_carry(value: bool) -> void:
	if _model:
		_model.set_carry(value)


func board() -> void:
	## Climb into a helicopter or Stryker: hidden, safe, inactive until unloaded
	if manning != null:
		manning.release(self)
	boarded = true
	board_target = null
	_has_order = false
	velocity = Vector3.ZERO
	visible = false
	set_exposed(false)
	_col.disabled = true
	collision_layer = 0


func unboard(at: Vector3) -> void:
	boarded = false
	visible = true
	_col.disabled = false
	collision_layer = 2
	global_position = at
	set_exposed(true)


func _physics_process(delta: float) -> void:
	if dead or boarded:
		return
	target_time -= delta
	if mounted or manning != null:
		_model.animate(delta, anim_moving)
		if can_fire:
			_combat(delta)
		return
	if is_on_floor():
		velocity.y = -0.5
		if chute:
			chute = false
			for c in get_children():
				if c == _canopy or c.has_meta("chute"):
					c.queue_free()
	elif chute:
		velocity.y = -4.0       # drifting down under the canopy
	else:
		velocity.y -= GRAVITY * delta

	var h := Vector3.ZERO
	if _has_order:
		# No path yet (the map was still being built when the order came): ask again
		_repath_cd -= delta
		if _repath_cd <= 0.0 and _agent.get_current_navigation_path().is_empty():
			_repath_cd = 0.5
			_agent.target_position = _agent.target_position
		var next := _agent.get_next_path_position()
		# Arrival is checked on the ground plane: the navmesh floats a little above the floor
		var to_goal := _agent.target_position - global_position
		to_goal.y = 0.0
		var short := _agent.is_navigation_finished() and to_goal.length() > 2.5 and _goal_retry > 0.0
		if short:
			# The path stopped short of where he was sent (the map is still being updated,
			# or there's no way in yet): wait and ask again for a while
			_goal_retry -= delta
			if _repath_cd <= 0.0:
				_repath_cd = 1.0
				_agent.target_position = _agent.target_position
		elif to_goal.length() < ARRIVE_DISTANCE or _agent.is_navigation_finished():
			_has_order = false
			manual = false
			if _face != Vector3.ZERO:
				look_at(global_position + _face, Vector3.UP)
		else:
			var d := next - global_position
			d.y = 0.0
			if d.length() < 0.3:
				d = to_goal    # last waypoint reached: close the remaining gap directly
			if _sidestep_t > 0.0:
				_sidestep_t -= delta
				d = _sidestep
			_check_stuck(delta, d)
			if d.length() > 0.05:
				h = d.normalized() * minf(SPEED, d.length() * 6.0)
				look_at(global_position + d, Vector3.UP)
	velocity.x = h.x
	velocity.z = h.z
	move_and_slide()
	_model.allow_kneel = not mounted and manning == null
	_model.animate(delta, h != Vector3.ZERO)

	_combat(delta)

	# Walking to a helicopter: climb in once at its door (it may still be landing)
	if board_target != null:
		if not is_instance_valid(board_target):
			board_target = null
		elif board_target.in_reach(global_position) and board_target.board_soldier(self):
			return

	if global_position.y < -20.0:
		die()


func _check_stuck(delta: float, heading: Vector3) -> void:
	## Wedged on a corner: step sideways for a moment, then ask for a fresh path
	_stuck_check -= delta
	if _stuck_check > 0.0:
		return
	_stuck_check = 0.6
	var moved := Vector2(global_position.x - _stuck_from.x, global_position.z - _stuck_from.z).length()
	_stuck_from = global_position
	if moved < 0.15 and heading.length() > 0.05:
		_sidestep = heading.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		_sidestep_t = 0.4
		_agent.target_position = _agent.target_position


func _combat(delta: float) -> void:
	_fire_cd -= delta
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			ammo = _mag() if gun_source != null else mini(_mag(), rounds)
		return
	if _fire_cd > 0.0:
		return
	if out_of_ammo() or ammo <= 0:
		_fire_cd = 0.5
		return
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var target := enemy.find_shot_target(eye, weapon_range)
	if target == null:
		_fire_cd = 0.15
		return
	_fire_cd = fire_interval * randf_range(0.85, 1.15)
	ammo -= 1
	if gun_source != null:
		gun_source.gun_rounds -= 1
	else:
		rounds -= 1
	_model.muzzle_flash()
	var aim := target.global_position + Vector3.UP * 1.0
	last_target = aim
	target_time = 0.6
	if not _has_order:
		var face := aim - global_position
		face.y = 0.0
		if face.length() > 0.1:
			look_at(global_position + face, Vector3.UP)
	if randf() < minf(0.95, squad.accuracy() + accuracy_bonus):
		enemy.add_tracer(eye, aim)
		target.take_hit(squad.damage() * damage_mult * RIFLE_DAMAGE, (aim - eye).normalized(), squad)
	else:
		var miss := aim + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized() * MISS_SPREAD
		enemy.add_tracer(eye, miss)
	if ammo <= 0 and not out_of_ammo():
		_reload = reload_time


func take_damage(amount: float) -> void:
	if dead:
		return
	health -= amount
	_model.set_damage(1.0 - health / MAX_HEALTH)
	if health <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	if manning != null:
		manning.release(self)
		_col.disabled = true
		collision_layer = 0
	enemy.soldiers.erase(self)
	board_target = null
	squad.remove_soldier(self)
	if mounted or boarded or not is_visible_in_tree():
		queue_free()
		return
	# Falls where he stood; the body stays for a while
	_col.disabled = true
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	_ring.visible = false
	enemy.gibs.blood(global_position + Vector3.UP * 0.9, 6)
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", PI * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "position:y", 0.18, 0.35)
	tw.tween_interval(BODY_LIFE)
	tw.tween_callback(queue_free)
