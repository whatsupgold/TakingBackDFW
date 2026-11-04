class_name Stryker
extends GroundVehicle
## M1126 Stryker troop carrier: crew of 2 (driver and vehicle commander on the remote .50 cal
## on top, fired from inside, so rifles can't reach either of them) and room for 2 squads.
## Right-click it with infantry selected: it stops and they climb in over the rear ramp.
## Press U (with it selected) to drop them off behind it. If a tank wrecks it, everyone
## inside is lost. Too heavy for the Chinook.

const M2_RWS := {"range": 42.0, "interval": 0.12, "damage": 2.5, "accuracy": 0.15, "mag": 200, "reload": 5.0}
const SEATS := [
	{"role": "Driver", "pos": Vector3(-0.6, 1.1, -2.3), "visible": false, "exposed": "never"},
	{"role": "Vehicle commander", "pos": Vector3(0.35, 1.1, -0.4), "visible": false, "exposed": "never", "fires": true, "weapon": M2_RWS},
]
const CAPACITY := 2

var passengers: Array[Soldier] = []
var inbound: Array = []
var squad_capacity := CAPACITY
var vehicle_capacity := 0


func _init() -> void:
	display_name = "Stryker"
	long_name = "M1126 STRYKER"
	gun_rounds_max = 2000         # .50 cal on the remote weapon station
	can_rounds_max = 2 * Fob.CAN_ROUNDS   # two ammo cans for the squads it carries
	max_speed = 26.8              # 60 mph
	accel = 2.0
	turn_rate = 1.4
	max_hp = 160.0
	seat_list = SEATS
	gunner_seat = 1
	body_size = Vector3(2.7, 2.6, 6.9)
	body_offset = Vector3(0, 1.3, 0)
	ring_radius = 4.2
	ring_color = Color(0.55, 0.95, 0.55)
	crew_color = Color(0.40, 0.70, 0.45)
	air_mobile = false
	fuel_max = 53.0
	fuel_range = 12000.0


func _make_model() -> VehicleModel:
	return VehicleModel.stryker()


# --- Carrying troops (same calls as a helicopter, so boarding code treats them alike) ---

func is_landed() -> bool:
	return not driving


func max_squads(_vehicles: int) -> int:
	return squad_capacity


func capacity_text() -> String:
	return "max %d squads" % squad_capacity


func passenger_squads() -> Array:
	var out: Array = []
	for s in passengers:
		if not (s.squad in out):
			out.append(s.squad)
	return out


func committed_squads() -> Array:
	var out := passenger_squads()
	_purge_inbound()
	for n in inbound:
		if not (n.squad in out):
			out.append(n.squad)
	return out


func committed_vehicles() -> int:
	return 0


func request_pickup() -> void:
	## Troops are coming: stop where it is
	driving = false


func add_inbound(n: Node) -> void:
	if not (n in inbound):
		inbound.append(n)


func door_point(_from: Vector3) -> Vector3:
	return to_global(Vector3(0.0, 0.0, 5.0))


func in_reach(p: Vector3, extra := 0.0) -> bool:
	var g := to_global(Vector3(0.0, 0.0, 3.8))
	return Vector2(p.x - g.x, p.z - g.z).length() < 2.6 + extra


func board_soldier(s: Soldier) -> bool:
	if destroyed or driving or speed > 0.5:
		return false
	var squads := passenger_squads()
	if not (s.squad in squads) and squads.size() >= squad_capacity:
		return false
	s.board()
	passengers.append(s)
	inbound.erase(s)
	return true


func board_vehicle(_v) -> bool:
	return false


func unload() -> void:
	if passengers.is_empty():
		message.emit("The %s has nobody aboard" % display_name)
		return
	driving = false
	var n := 0
	for s in passengers:
		if not is_instance_valid(s) or s.dead:
			continue
		var x := (n % 5 - 2) * 1.1
		var z := 4.6 + floori(n / 5.0) * 1.0
		var spot := to_global(Vector3(x, 0.0, z))
		spot.y = _ground_y(spot) + 0.1
		s.unboard(spot)
		s.order_move(NavigationServer3D.map_get_closest_point(nav_map, to_global(Vector3(x, 0.0, z + 4.0))))
		n += 1
	passengers.clear()
	message.emit("%s unloaded: %d troops" % [display_name, n])


func order_move(p: Vector3, face := NAN) -> void:
	_abandon_inbound()
	super.order_move(p, face)


func _purge_inbound() -> int:
	for n in inbound.duplicate():
		if not is_instance_valid(n) or n.board_target != self or n.dead or n.boarded:
			inbound.erase(n)
	return inbound.size()


func _abandon_inbound() -> void:
	var left := _purge_inbound()
	for n in inbound:
		n.board_target = null
	inbound.clear()
	if left > 0:
		message.emit("%s moving: %d troops still on their way were left behind" % [display_name, left])


func _on_destroyed() -> void:
	for s in passengers.duplicate():
		if is_instance_valid(s) and not s.dead:
			s.die()
	passengers.clear()
