class_name FuelTruck
extends GroundVehicle
## M978A4 HEMTT fuel truck: crew of 2, unarmed, a 2,500 gallon tanker. Park it and it tops up
## every vehicle or landed helicopter within REACH from its tank. Right-click a vehicle or a
## helicopter with the fuel truck selected and it drives over to refuel it. Park it inside the
## FOB walls and it fills its tanker from the FOB's fuel stock.

const CARGO := 2500                # gallons in the tanker
const REACH := 25.0                # hose reach
const RATE := 120.0                # gallons a second through the hoses
const SEATS := [
	{"role": "Driver", "pos": Vector3(-0.5, 1.5, -3.5), "visible": false, "exposed": "never"},
	{"role": "TC", "pos": Vector3(0.5, 1.5, -3.5), "visible": false, "exposed": "never"},
]

var cargo_fuel := float(CARGO)
var refuel_target: Node3D = null


func _init() -> void:
	display_name = "Fuel truck"
	long_name = "M978A4 HEMTT FUEL"
	max_speed = 27.7              # 62 mph (M978A4)
	accel = 1.5
	turn_rate = 1.2
	max_hp = 110.0
	seat_list = SEATS
	gunner_seat = -1
	body_size = Vector3(2.6, 3.0, 10.2)
	body_offset = Vector3(0, 1.5, 0)
	ring_radius = 5.5
	ring_color = Color(0.55, 0.95, 0.55)
	crew_color = Color(0.45, 0.62, 0.40)
	air_mobile = false
	fuel_max = 155.0
	fuel_range = 10000.0


func _make_model() -> VehicleModel:
	return VehicleModel.fuel_truck()


func go_refuel(v: Node3D) -> String:
	## Drive over to a vehicle (or landed helicopter) and fill it up. Returns "" or why not.
	if v == self:
		return ""
	if not v.needs_fuel():
		return "The %s's tank is already full" % v.display_name
	if cargo_fuel < 1.0:
		return "The fuel truck is empty: park it inside the FOB walls to fill up"
	refuel_target = v
	var stand: Vector3 = v.global_position + (global_position - v.global_position).normalized() * 8.0
	order_move(NavigationServer3D.map_get_closest_point(nav_map, stand))
	message.emit("Fuel truck heading to the %s" % v.display_name)
	return ""


func cargo_text() -> String:
	return "%d / %d gal" % [int(cargo_fuel), CARGO]


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if destroyed or carried_by != null or speed > 0.5 or driving:
		return
	if refuel_target != null and (not is_instance_valid(refuel_target) or refuel_target.destroyed):
		refuel_target = null
	if cargo_fuel < 1.0:
		return
	for v in get_tree().get_nodes_in_group("refuelable"):
		if v == self or not v.needs_fuel() or not v.is_parked():
			continue
		if Vector2(v.global_position.x - _pos.x, v.global_position.z - _pos.z).length() > REACH:
			continue
		var n := minf(minf(RATE * delta, v.fuel_max - v.fuel), cargo_fuel)
		v.add_fuel(n)
		cargo_fuel -= n
		if not v.needs_fuel():
			message.emit("Fuel truck: %s full (%d gal left in the tanker)" % [v.display_name, int(cargo_fuel)])
			if v == refuel_target:
				refuel_target = null
	# Its own tank comes out of the tanker too
	if fuel < fuel_max - 0.5:
		var own := minf(fuel_max - fuel, cargo_fuel)
		add_fuel(own)
		cargo_fuel -= own
	# Got as close as the roads allow but not in reach: try again from here
	if refuel_target != null and refuel_target.needs_fuel():
		var d := Vector2(refuel_target.global_position.x - _pos.x, refuel_target.global_position.z - _pos.z).length()
		if d > REACH:
			var t := refuel_target
			refuel_target = null
			message.emit("Fuel truck can't get within %d m of the %s" % [int(REACH), t.display_name])
