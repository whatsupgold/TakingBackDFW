class_name Apache
extends Helicopter
## AH-64D Apache attack helicopter: crew of 2 (gunner in front on the 30 mm chain gun, pilot
## behind). It carries nobody. In the air it fires Hellfire missiles at any Red tank or
## anti-air vehicle in range until the rails are empty, then it has to land inside the FOB
## walls to rearm. Anti-air is still the thing that kills it.

const M230 := {"range": 60.0, "interval": 0.12, "damage": 6.0, "accuracy": 0.18, "mag": 300, "reload": 3.0}
const SEATS := [
	{"role": "Gunner", "pos": Vector3(0, 1.75, -2.75), "visible": false, "exposed": "never", "fires": true, "weapon": M230},
	{"role": "Pilot", "pos": Vector3(0, 2.00, -1.40), "visible": false, "exposed": "never"},
]
const HELLFIRE_MAX := 8
const HELLFIRE_RANGE := 130.0
const HELLFIRE_INTERVAL := 2.5

var hellfires := HELLFIRE_MAX
var _hf_cd := 0.0
var _rail := 0


func _init() -> void:
	display_name = "Apache"
	long_name = "AH-64D APACHE"
	max_speed = 81.4              # 182 mph (AH-64D)
	accel = 5.0
	climb_rate = 12.7
	turn_rate = 1.6
	squad_capacity = 0
	vehicle_capacity = 0
	seat_list = SEATS
	door_points = [Vector3(-1.8, 0.0, -1.5)]
	board_points = [Vector3.ZERO]
	gun_rounds_max = 1200         # 30 mm
	can_rounds_max = 0
	max_hp = 170.0
	body_size = Vector3(2.0, 2.6, 6.0)
	body_offset = Vector3(0, 1.4, -0.5)
	ring_radius = 4.0
	crew_color = Color(0.45, 0.50, 0.42)
	fuel_max = 370.0
	endurance = 420.0


func _make_model() -> VehicleModel:
	return HeliModels.apache()


func missiles_text() -> String:
	return "%d / %d Hellfire" % [hellfires, HELLFIRE_MAX]


func rearm_missiles() -> bool:
	if hellfires >= HELLFIRE_MAX or state != "landed":
		return false
	hellfires = HELLFIRE_MAX
	message.emit("Apache rearmed: %d Hellfires" % HELLFIRE_MAX)
	return true


func board_soldier(_s: Soldier) -> bool:
	return false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if destroyed or state == "landed":
		return
	_hf_cd -= delta
	if hellfires <= 0 or _hf_cd > 0.0 or crew.occupant(0) == null:
		return
	var best: Node3D = null
	var best_d := HELLFIRE_RANGE
	for t in enemy.tanks:
		if not is_instance_valid(t) or not t.alive:
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return
	_hf_cd = HELLFIRE_INTERVAL
	hellfires -= 1
	_rail += 1
	var side := -1.75 if _rail % 2 == 0 else 1.75
	Missile.launch(get_parent(), to_global(Vector3(side, 1.1, -0.6)), best, enemy, 120.0, Missile.HELLFIRE_SPEED)
	if hellfires == 0:
		message.emit("Apache: Hellfires gone, land inside the FOB to rearm")
	else:
		message.emit("Apache: Hellfire away (%d left)" % hellfires)
