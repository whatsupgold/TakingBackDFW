class_name Bradley
extends Stryker
## M2A3 Bradley fighting vehicle: crew of 3 (driver, gunner on the 25 mm Bushmaster,
## commander), carries 1 squad. It has just 2 TOW missiles: stopped, it fires them at any
## Red tank or anti-air vehicle in range, and then it has to go back inside the FOB walls
## to load more.

const M242 := {"range": 55.0, "interval": 0.25, "damage": 7.0, "accuracy": 0.12, "mag": 300, "reload": 4.0}
const BRADLEY_SEATS := [
	{"role": "Driver", "pos": Vector3(-0.95, 1.6, -1.9), "visible": false, "exposed": "never"},
	{"role": "Gunner", "pos": Vector3(0.0, 2.0, -0.3), "visible": false, "exposed": "never", "fires": true, "weapon": M242},
	{"role": "Commander", "pos": Vector3(0.55, 2.0, -0.1), "visible": false, "exposed": "never"},
]
const TOW_MAX := 2
const TOW_RANGE := 110.0
const TOW_INTERVAL := 6.0

var tows := TOW_MAX
var _tow_cd := 0.0


func _init() -> void:
	display_name = "Bradley"
	long_name = "M2A3 BRADLEY"
	squad_capacity = 1
	gun_rounds_max = 900           # 25 mm: 300 ready, 600 stowed
	can_rounds_max = 2 * Fob.CAN_ROUNDS
	max_speed = 18.3              # 41 mph (M2A3)
	accel = 2.0
	turn_rate = 1.5
	max_hp = 220.0
	seat_list = BRADLEY_SEATS
	gunner_seat = 1
	body_size = Vector3(3.4, 2.9, 6.6)
	body_offset = Vector3(0, 1.45, 0)
	ring_radius = 4.4
	crew_color = Color(0.40, 0.70, 0.45)
	fuel_max = 175.0
	fuel_range = 9000.0


func _make_model() -> VehicleModel:
	return VehicleModel.bradley()


func missiles_text() -> String:
	return "%d / %d TOW" % [tows, TOW_MAX]


func rearm_missiles() -> bool:
	if tows >= TOW_MAX:
		return false
	tows = TOW_MAX
	message.emit("Bradley: TOW launcher reloaded")
	return true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if destroyed or carried_by != null:
		return
	_tow_cd -= delta
	if tows <= 0 or _tow_cd > 0.0 or speed > 1.0 or crew.occupant(gunner_seat) == null:
		return
	var best: Node3D = null
	var best_d := TOW_RANGE
	for t in enemy.tanks:
		if not is_instance_valid(t) or not t.alive:
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return
	_tow_cd = TOW_INTERVAL
	tows -= 1
	var launcher := model.turret.to_global(Vector3(-1.40, 0.55, -0.70)) if model.turret != null else global_position + Vector3.UP * 2.6
	model.turret.rotation.y = atan2(-to_local(best.global_position).x, -to_local(best.global_position).z)
	Missile.launch(get_parent(), launcher, best, enemy, 120.0, Missile.TOW_SPEED)
	if tows == 0:
		message.emit("Bradley fired its last TOW: back to the FOB to reload")
	else:
		message.emit("Bradley: TOW away (%d left)" % tows)
