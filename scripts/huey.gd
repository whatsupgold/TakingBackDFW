class_name Huey
extends Helicopter
## UH-60 Black Hawk (it took the Huey's place; the class keeps its old name) with a crew of 4:
## pilot, co-pilot and two crew chiefs on M240 door guns. Carries up to 2 squads (no vehicles).
## Troops board through the side doors. It can FAST-ROPE: unload (U) while it's hovering and
## the troops slide down ropes without it landing. Flight, hover mode and pickups are in
## Helicopter.

const CAPACITY := 2               # squads
const M240 := {"range": 36.0, "interval": 0.12, "damage": 1.6, "accuracy": 0.05, "mag": 100, "reload": 4.0}
const SEATS := [
	{"role": "Pilot", "pos": Vector3(0.5, 0.75, -2.4), "visible": false, "exposed": "never"},
	{"role": "Co-pilot", "pos": Vector3(-0.5, 0.75, -2.4), "visible": false, "exposed": "never"},
	{"role": "Crew chief", "pos": Vector3(-0.95, 0.68, -0.55), "yaw": PI / 2.0, "visible": true, "exposed": "landed", "fires": true, "weapon": M240},
	{"role": "Crew chief", "pos": Vector3(0.95, 0.68, -0.55), "yaw": -PI / 2.0, "visible": true, "exposed": "landed", "fires": true, "weapon": M240},
]


func _init() -> void:
	display_name = "Black Hawk"
	long_name = "UH-60 BLACK HAWK"
	squad_capacity = CAPACITY
	vehicle_capacity = 0
	seat_list = SEATS
	door_points = [Vector3(-2.3, 0.0, 0.3), Vector3(2.3, 0.0, 0.3)]
	board_points = [Vector3.ZERO]
	board_reach = 3.4
	fast_rope = true
	gun_rounds_max = 1800         # two M240 door guns
	can_rounds_max = 2 * Fob.CAN_ROUNDS


func _make_model() -> VehicleModel:
	return HeliModels.black_hawk()
