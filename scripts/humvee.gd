class_name Humvee
extends GroundVehicle
## Humvee with a crew of 5: driver, gunner, truck commander (TC) and two rear passengers.
## Only the gunner is exposed (standing in the roof hatch with the .50 cal); everyone else
## is safe inside unless a tank round wrecks it. When a crewman dies the others move up a
## seat, so the TC takes over the gun, then the passengers. With no crew left it can't move.
## Right-click the Chinook with the Humvee selected to drive it up the ramp.
## Driving, armor and wrecks are in GroundVehicle.

const M2 := {"range": 40.0, "interval": 0.12, "damage": 2.5, "accuracy": 0.10, "mag": 100, "reload": 4.0}
const SEATS := [
	{"role": "Driver", "pos": Vector3(-0.5, 0.9, -0.4), "visible": false, "exposed": "never"},
	{"role": "Gunner", "pos": Vector3(0.0, 1.25, 0.25), "visible": true, "exposed": "always", "fires": true, "weapon": M2},
	{"role": "TC", "pos": Vector3(0.5, 0.9, -0.4), "visible": false, "exposed": "never"},
	{"role": "Passenger", "pos": Vector3(-0.5, 0.9, 0.6), "visible": false, "exposed": "never"},
	{"role": "Passenger", "pos": Vector3(0.5, 0.9, 0.6), "visible": false, "exposed": "never"},
]


func _init() -> void:
	display_name = "Humvee"
	long_name = "HUMVEE"
	gun_rounds_max = 1000         # .50 cal
	max_speed = 31.3              # 70 mph (M1151)
	accel = 2.6
	turn_rate = 1.8
	max_hp = 100.0
	seat_list = SEATS
	gunner_seat = 1
	body_size = Vector3(2.2, 1.9, 4.7)
	body_offset = Vector3(0, 0.95, 0)
	ring_radius = 3.0
	ring_color = Color(0.55, 0.95, 0.55)
	crew_color = Color(0.35, 0.75, 0.35)
	air_mobile = true


func _make_model() -> VehicleModel:
	return VehicleModel.humvee()
