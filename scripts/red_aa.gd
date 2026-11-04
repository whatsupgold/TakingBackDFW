class_name RedAA
extends RedTank
## Red Army anti-air vehicle (ZSU-23-4 style): four cannons and a radar. It sits in the Red FOB
## and fires bursts at A-10s and at helicopters in the air within AA_RANGE. It doesn't shoot
## at ground targets. Like a tank, only heavy weapons hurt it: the A-10's cannon, M777 shells
## and breach charges. An A-10 shot down crashes and its pilot ejects; a helicopter shot down
## crashes with everyone aboard.

const AA_RANGE := 450.0            # horizontal distance it can reach
const AA_CEILING := 250.0
const AA_LOOK := 0.2
const AA_TRAVERSE := 3.0           # rad/s
const AA_ELEVATE := 2.0
const BURST_TIME := 2.5
const BURST_GAP := 0.4
const SHOT_INTERVAL := 0.05
const HIT_DAMAGE := 4.0            # per round: an A-10 has 120, a Huey or Chinook 120
const ACCURACY_NEAR := 0.65
const ACCURACY_FAR := 0.3

var _air: Node3D = null
var _burst := 0.0
var _gap := 0.0
var _shot_cd := 0.0
var _aa_look := 0.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	add_to_group("red_tanks")
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.3, 2.6, 6.4)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 1.3, 0)
	add_child(col)
	model = VehicleModel.red_aa()
	add_child(model)
	_aa_look = randf() * AA_LOOK


func _physics_process(delta: float) -> void:
	if not alive:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.6
			army.gibs.smoke(global_position + Vector3.UP * 2.2)
		return
	_aa_look -= delta
	if _aa_look <= 0.0:
		_aa_look = AA_LOOK
		_air = _find_air()
	if _air != null and not _valid_air(_air):
		_air = null
	_aim_and_shoot(delta)


func _valid_air(t: Node3D) -> bool:
	if not is_instance_valid(t) or not t.has_method("is_air_target") or not t.is_air_target():
		return false
	var d := t.global_position - global_position
	return Vector2(d.x, d.z).length() <= AA_RANGE and d.y <= AA_CEILING


func _find_air() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var eye := global_position + Vector3.UP * 2.6
	for v in army.vehicles:
		if not _valid_air(v):
			continue
		var d := eye.distance_to(v.global_position)
		if d < best_d and army.clear_line(eye, v.global_position + Vector3.UP * 1.5):
			best_d = d
			best = v
	return best


func _aim_and_shoot(delta: float) -> void:
	_shot_cd -= delta
	if _air == null:
		_burst = 0.0
		model.cradle.rotation.x = move_toward(model.cradle.rotation.x, 0.15, AA_ELEVATE * delta)
		return
	var aim := _air.global_position + Vector3.UP * 1.5
	var local := to_local(aim)
	var want_yaw := atan2(-local.x, -local.z)
	var diff := wrapf(want_yaw - model.turret.rotation.y, -PI, PI)
	model.turret.rotation.y += clampf(diff, -AA_TRAVERSE * delta, AA_TRAVERSE * delta)
	var flat := Vector2(local.x, local.z).length()
	var want_elev := atan2(local.y - 2.2, maxf(flat, 0.1))
	model.cradle.rotation.x = move_toward(model.cradle.rotation.x, want_elev, AA_ELEVATE * delta)
	if absf(diff) > 0.25:
		return
	# Bursts: fire for BURST_TIME, pause for BURST_GAP
	if _burst <= 0.0:
		_gap -= delta
		if _gap > 0.0:
			return
		_burst = BURST_TIME
	_burst -= delta
	if _burst <= 0.0:
		_gap = BURST_GAP
	if _shot_cd > 0.0:
		return
	_shot_cd = SHOT_INTERVAL
	var muzzle := model.muzzle.global_position
	var dist := muzzle.distance_to(aim)
	var chance := lerpf(ACCURACY_NEAR, ACCURACY_FAR, clampf(dist / AA_RANGE, 0.0, 1.0))
	if randf() < chance:
		army.add_tracer(muzzle, aim, true)
		_air.take_flak(HIT_DAMAGE)
	else:
		army.add_tracer(muzzle, aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 8.0), true)
