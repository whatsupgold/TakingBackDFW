class_name Lmtv
extends Stryker
## M1078 LMTV: the 2½-ton cargo truck with a canvas-covered bed. Crew of 2 (driver, TC),
## unarmed, carries 2 squads and 2 ammo cans. Faster to come by than a Stryker, but soft:
## tank rounds and blasts go straight through it.

const LMTV_SEATS := [
	{"role": "Driver", "pos": Vector3(-0.55, 1.6, -2.4), "visible": false, "exposed": "never"},
	{"role": "TC", "pos": Vector3(0.55, 1.6, -2.4), "visible": false, "exposed": "never"},
]


func _init() -> void:
	display_name = "LMTV"
	long_name = "M1078 LMTV"
	gun_rounds_max = 0
	can_rounds_max = 2 * Fob.CAN_ROUNDS
	max_speed = 25.9              # 58 mph
	accel = 1.8
	turn_rate = 1.4
	max_hp = 80.0
	squad_capacity = 4               # 16 troop seats in the back
	seat_list = LMTV_SEATS
	gunner_seat = -1
	body_size = Vector3(2.5, 3.0, 7.2)
	body_offset = Vector3(0, 1.5, 0)
	ring_radius = 4.4
	crew_color = Color(0.42, 0.62, 0.40)
	fuel_max = 56.0
	fuel_range = 12000.0


func _make_model() -> VehicleModel:
	return VehicleModel.lmtv()
