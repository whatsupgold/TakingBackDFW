class_name LittleBird
extends Helicopter
## MH-6 Little Bird: the small, quick special-operations helicopter. Two pilots, no guns,
## and one squad riding on the outboard benches. It can fast-rope them in from a hover.

const SEATS := [
	{"role": "Pilot", "pos": Vector3(-0.35, 1.35, -0.9), "visible": false, "exposed": "never"},
	{"role": "Co-pilot", "pos": Vector3(0.35, 1.35, -0.9), "visible": false, "exposed": "never"},
]


func _init() -> void:
	display_name = "Little Bird"
	long_name = "MH-6 LITTLE BIRD"
	max_speed = 78.2              # 175 mph (MH-6M)
	accel = 6.0
	turn_rate = 2.0
	climb_rate = 10.0
	squad_capacity = 1
	vehicle_capacity = 0
	seat_list = SEATS
	door_points = [Vector3(-2.0, 0.0, -0.2), Vector3(2.0, 0.0, -0.2)]
	board_points = [Vector3.ZERO]
	board_reach = 2.8
	fast_rope = true
	max_hp = 70.0
	body_size = Vector3(1.6, 1.9, 3.4)
	body_offset = Vector3(0, 1.2, -0.2)
	ring_radius = 3.0
	crew_color = Color(0.40, 0.42, 0.40)
	fuel_max = 62.0
	endurance = 300.0


func _make_model() -> VehicleModel:
	return VehicleModel.mh6_smooth()      # test: the smooth, realistic look (VehicleModel.mh6() is the faceted one)
