class_name RedTank
extends AnimatableBody3D
## A Red Army tank. Its main gun goes after your vehicles first (Humvee, Stryker, landed
## helicopters, the M777, a parked A-10), then groups of soldiers; its coaxial machine gun
## shoots soldiers. Rifles and vehicle machine guns can't hurt it: it takes the A-10's
## cannon or M777 shells. A destroyed tank stays where it died as a burnt-out wreck.

const MAX_HP := 100.0
const SPEED := 16.7                # 60 km/h (T-72), real size maps
const ACCEL := 2.0
const BRAKE := 5.0
const TURN_RATE := 0.9
const TURRET_SPEED := 1.1          # rad/s
const GUN_RANGE := 85.0
const GUN_RELOAD := 7.0
const GUN_SPREAD := 2.0             # metres off at full range
const MG_RANGE := 45.0
const MG_INTERVAL := 0.2
const MG_DAMAGE := 8.0
const MG_ACCURACY := 0.25
const LOOK_INTERVAL := 0.5

var army: RedArmy
var squad                           # RedArmy.RedSquad
var nav_map: RID
var post := Vector3.ZERO
var hp := MAX_HP
var alive := true
var model: VehicleModel
var speed := 0.0
var driving := false

var _path := PackedVector3Array()
var _path_i := 0
var _yaw := 0.0
var _pos := Vector3.ZERO
var _gun_target: Node3D            # vehicle or soldier
var _mg_target: Soldier
var _look_cd := 0.0
var _reload := 0.0
var _mg_cd := 0.0
var _smoke_t := 0.0


func place(at: Vector3, yaw_deg: float) -> void:
	_pos = at
	post = at
	_yaw = deg_to_rad(yaw_deg)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	add_to_group("red_tanks")
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 2.2, 6.9)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	add_child(col)
	model = VehicleModel.red_tank()
	add_child(model)
	_reload = randf_range(1.0, GUN_RELOAD)
	_look_cd = randf() * LOOK_INTERVAL


func order_move(p: Vector3) -> void:
	if not alive:
		return
	_path = Level.find_path(nav_map, _pos, p)
	_path_i = 1
	driving = _path.size() > 1


func _physics_process(delta: float) -> void:
	if not alive:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.6
			army.gibs.smoke(global_position + Vector3.UP * 2.2)
		return
	_look_cd -= delta
	if _look_cd <= 0.0:
		_look_cd = LOOK_INTERVAL
		var eye := global_position + Vector3.UP * 2.2
		_gun_target = army.find_vehicle_target(eye, GUN_RANGE)
		_mg_target = army.find_player_target(eye, MG_RANGE)
		if _gun_target == null:
			_gun_target = army.find_player_target(eye, GUN_RANGE)
	if _gun_target != null and not _valid_target(_gun_target):
		_gun_target = null
	if _mg_target != null and (not is_instance_valid(_mg_target) or _mg_target.dead or not _mg_target.exposed):
		_mg_target = null

	# Drive (stops to fight when it has something to shoot at)
	var target_speed := 0.0
	if driving and _gun_target == null and _path_i < _path.size():
		var w := _path[_path_i]
		var to := Vector3(w.x - _pos.x, 0.0, w.z - _pos.z)
		var last := _path_i == _path.size() - 1
		if to.length() < (1.0 if last else 2.5):
			if last:
				driving = false
			else:
				_path_i += 1
		else:
			var want := atan2(-to.x, -to.z)
			var diff := wrapf(want - _yaw, -PI, PI)
			_yaw += clampf(diff, -TURN_RATE * delta, TURN_RATE * delta)
			target_speed = SPEED * (1.0 - minf(absf(diff) / 1.0, 0.85))
			target_speed = minf(target_speed, GroundVehicle.turn_limit(absf(diff), to.length(), TURN_RATE))
			target_speed = minf(target_speed, GroundVehicle.corner_limit(_pos, _path, _path_i, SPEED, BRAKE))
	speed = move_toward(speed, target_speed, (ACCEL if target_speed > speed else BRAKE) * delta)
	if speed > 0.01:
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var p := _pos + fwd * speed * delta
		p.y = _ground_y(p)
		_pos = p
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)

	_aim_and_fire(delta)


func _valid_target(t: Node3D) -> bool:
	if not is_instance_valid(t):
		return false
	if t is Soldier:
		return not t.dead and t.exposed
	return t.is_targetable()


func _aim_and_fire(delta: float) -> void:
	_reload -= delta
	_mg_cd -= delta
	var turret := model.turret
	var aim_at: Node3D = _gun_target if _gun_target != null else _mg_target
	if aim_at != null:
		var local := to_local(aim_at.global_position)
		var want := atan2(-local.x, -local.z)
		var diff := wrapf(want - turret.rotation.y, -PI, PI)
		turret.rotation.y += clampf(diff, -TURRET_SPEED * delta, TURRET_SPEED * delta)
		var on_target := absf(diff) < 0.06
		# Main gun
		if _gun_target != null and on_target and _reload <= 0.0:
			_reload = GUN_RELOAD * randf_range(0.9, 1.15)
			var muzzle := model.muzzle.global_position
			var aim := _gun_target.global_position + Vector3.UP * 0.8
			var miss := GUN_SPREAD * muzzle.distance_to(aim) / GUN_RANGE
			aim += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * miss
			aim.y = maxf(aim.y, _ground_y(aim) + 0.3)
			army.fire_shell(muzzle, aim)
		# Coaxial MG at soldiers
		if _mg_target != null and _mg_cd <= 0.0 and on_target:
			_mg_cd = MG_INTERVAL * randf_range(0.8, 1.3)
			var from := model.muzzle.global_position
			var to := _mg_target.global_position + Vector3.UP * 1.0
			if randf() < MG_ACCURACY:
				army.add_tracer(from, to, true)
				_mg_target.take_damage(MG_DAMAGE)
			else:
				army.add_tracer(from, to + Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)) * 1.5, true)


func take_damage(amount: float) -> bool:
	## Only heavy weapons call this (artillery, A-10 cannon). Returns true if it was destroyed.
	if not alive:
		return false
	hp -= amount
	if hp > 0.0:
		return false
	alive = false
	driving = false
	model.burn()
	army.gibs.explosion(global_position + Vector3.UP * 1.0)
	army.on_tank_destroyed(self)
	return true


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p.y if hit.is_empty() else hit.position.y
