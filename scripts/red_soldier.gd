class_name RedSoldier
extends CharacterBody3D
## A Red Army rifleman. Holds his post (or walks where his squad is sent), and shoots the
## nearest of your soldiers he can see. Stops to fight when he has a target.
## Dies after about 4 rifle hits at squad level 0. The body stays on the ground for a while.

const SPEED := 3.8
const GRAVITY := 20.0
const RANGE := 34.0
const FIRE_INTERVAL := 0.6
const DAMAGE := 9.0
const BASE_ACCURACY := 0.40         # at point-blank; falls off with range
const MAX_HEALTH := 100.0
const EYE_HEIGHT := 1.45
const LOOK_INTERVAL := 0.3
const BODY_LIFE := 25.0
const COLOR := Color(0.62, 0.14, 0.11)

var army: RedArmy
var squad                           # RedArmy.RedSquad
var post := Vector3.ZERO
var health := MAX_HEALTH
var alive := true
var weapon_range := RANGE
var fire_interval := FIRE_INTERVAL
var damage := DAMAGE
var fixed := false                  # tower gunner: never moves

var _agent: NavigationAgent3D
var _model: SoldierModel
var _col: CollisionShape3D
var _has_order := false
var _target: Soldier
var _look_cd := 0.0
var _fire_cd := 0.0
var _dead_t := 0.0
var _repath_cd := 0.0
var _repaths := 0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 32     # 32: your gates' leaves
	add_to_group("red_soldiers")
	floor_max_angle = deg_to_rad(40.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = 0.85
	add_child(_col)
	_model = SoldierModel.new()
	add_child(_model)
	_model.build(COLOR, true)
	_agent = NavigationAgent3D.new()
	_agent.path_search_max_polygons = Level.PATH_POLYS
	_agent.path_desired_distance = 0.65
	_agent.target_desired_distance = 0.4
	_agent.radius = 0.45
	_agent.height = 1.8
	add_child(_agent)
	_fire_cd = randf() * FIRE_INTERVAL * 2.0
	_look_cd = randf() * LOOK_INTERVAL
	rotation.y = randf() * TAU


func order_move(p: Vector3) -> void:
	if not alive or fixed:
		return
	_agent.target_position = p
	_has_order = true
	_repaths = 0


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		if _dead_t > BODY_LIFE:
			queue_free()
		return
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta

	_look_cd -= delta
	if _look_cd <= 0.0:
		_look_cd = LOOK_INTERVAL
		var t := army.find_player_target(global_position + Vector3.UP * EYE_HEIGHT, weapon_range)
		_target = t

	var h := Vector3.ZERO
	if _target != null and (not is_instance_valid(_target) or _target.dead or not _target.exposed):
		_target = null
	if _target == null and _has_order:
		var to_goal := _agent.target_position - global_position
		to_goal.y = 0.0
		if to_goal.length() < 0.6:
			_has_order = false
		elif _agent.is_navigation_finished():
			# No path yet (or it ended short): ask again a few times before giving up
			_repath_cd -= delta
			if _repath_cd <= 0.0:
				_repath_cd = 0.5
				_repaths += 1
				_agent.target_position = _agent.target_position
				if _repaths > 8 or to_goal.length() < 3.0:
					_has_order = false
		else:
			var d := _agent.get_next_path_position() - global_position
			d.y = 0.0
			if d.length() < 0.3:
				d = to_goal
			if d.length() > 0.05:
				h = d.normalized() * SPEED
				look_at(global_position + d, Vector3.UP)
	velocity.x = h.x
	velocity.z = h.z
	move_and_slide()
	_model.allow_kneel = not fixed
	_model.animate(delta, h != Vector3.ZERO)
	_combat(delta)
	if global_position.y < -20.0:
		take_hit(999.0, Vector3.UP, null)


func _combat(delta: float) -> void:
	_fire_cd -= delta
	if _target == null or _fire_cd > 0.0:
		return
	_fire_cd = fire_interval * randf_range(0.8, 1.3)
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var aim := _target.global_position + Vector3.UP * 1.0
	var face := aim - global_position
	face.y = 0.0
	if face.length() > 0.1:
		look_at(global_position + face, Vector3.UP)
	_model.muzzle_flash()
	var dist := eye.distance_to(aim)
	var chance := BASE_ACCURACY * (1.1 - 0.6 * dist / weapon_range)
	if randf() < chance:
		army.add_tracer(eye, aim, true)
		_target.take_damage(damage)
	else:
		army.add_tracer(eye, aim + Vector3(randf_range(-1, 1), randf_range(-0.4, 1), randf_range(-1, 1)).normalized() * 1.4, true)


func take_hit(dmg: float, _dir: Vector3, by) -> bool:
	## Returns true if this hit killed him
	if not alive:
		return false
	health -= dmg
	_model.set_damage(1.0 - health / MAX_HEALTH)
	if health > 0.0:
		return false
	_die()
	if by != null and by.has_method("add_kill"):
		by.add_kill()
	return true


func _die() -> void:
	alive = false
	army.on_soldier_died(self)
	collision_layer = 0
	collision_mask = 1
	_col.disabled = true
	velocity = Vector3.ZERO
	# Fall over backwards
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", PI * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "position:y", 0.18, 0.35)
	army.gibs.blood(global_position + Vector3.UP * 0.9, 6)
