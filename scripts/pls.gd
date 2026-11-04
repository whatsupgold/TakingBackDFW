class_name Pls
extends GroundVehicle
## M1074A1 PLS (Palletized Load System) truck: crew of 2 (driver, TC), unarmed. It fetches
## air-dropped supply pallets. Right-click a pallet with the PLS selected: it drives there and
## loads it onto its flatrack (it holds CAPACITY pallets). Drive it inside the FOB walls and
## stop: the pallets go into the FOB's stock. Park it next to an M777 with a shell pallet
## aboard and the gun takes shells straight off the truck. U drops its pallets behind it.

const CAPACITY := 2
const LOAD_REACH := 7.0
const LOAD_TIME := 3.0
const GUN_REACH := 16.0
const SEATS := [
	{"role": "Driver", "pos": Vector3(-0.5, 1.4, -3.3), "visible": false, "exposed": "never"},
	{"role": "TC", "pos": Vector3(0.5, 1.4, -3.3), "visible": false, "exposed": "never"},
]
const SLOTS := [Vector3(0, 1.62, 0.2), Vector3(0, 1.62, 2.6)]

var cargo: Array = []              # pallets on the flatrack
var load_target: SupplyPallet = null
var _load_t := 0.0
var _deliver_t := 0.0


func _init() -> void:
	display_name = "PLS"
	long_name = "M1074A1 PLS TRUCK"
	max_speed = 27.7              # 62 mph (M1074A1)
	accel = 1.5
	turn_rate = 1.2
	max_hp = 120.0
	seat_list = SEATS
	gunner_seat = -1
	body_size = Vector3(2.6, 3.0, 10.4)
	body_offset = Vector3(0, 1.5, 0)
	ring_radius = 5.5
	ring_color = Color(0.55, 0.95, 0.55)
	crew_color = Color(0.45, 0.62, 0.40)
	air_mobile = false
	fuel_max = 80.0
	fuel_range = 10000.0


func _make_model() -> VehicleModel:
	return VehicleModel.pls()


func go_load(p: SupplyPallet) -> String:
	## Drive to a pallet and load it. Returns "" or why not.
	if cargo.size() >= CAPACITY:
		return "The PLS is full (%d pallets): take them to the FOB first" % CAPACITY
	if not p.is_on_ground():
		return "That pallet isn't on the ground yet"
	load_target = p
	_load_t = LOAD_TIME
	var stand := p.global_position + (global_position - p.global_position).normalized() * 5.0
	order_move(NavigationServer3D.map_get_closest_point(nav_map, stand))
	message.emit("PLS going for the %s" % p.display_name.to_lower())
	return ""


func drop_all() -> void:
	## U: pallets down on the ground behind the truck
	if cargo.is_empty():
		message.emit("The PLS has nothing aboard")
		return
	var i := 0
	for p in cargo.duplicate():
		var at := to_global(Vector3((i - 0.5) * 2.0, 0, 7.0))
		at.y = _ground_y(at)
		(p as SupplyPallet).unload_to(get_parent(), at, rotation.y)
		i += 1
	cargo.clear()
	message.emit("PLS: pallets set down")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if destroyed or carried_by != null:
		return
	# Loading: once beside the pallet and stopped
	if load_target != null:
		if not is_instance_valid(load_target) or not load_target.is_on_ground():
			load_target = null
		elif Vector2(load_target.global_position.x - _pos.x, load_target.global_position.z - _pos.z).length() < LOAD_REACH:
			if speed < 0.5:
				_load_t -= delta
				if _load_t <= 0.0:
					_load(load_target)
					load_target = null
		elif not driving:
			# Got as close as the roads allow but not close enough: try again from here
			var stand := load_target.global_position + (_pos - load_target.global_position).normalized() * 4.0
			order_move(NavigationServer3D.map_get_closest_point(nav_map, stand))
	if cargo.is_empty():
		return
	# Inside the FOB walls and stopped: the pallets go into the stock
	var f := Fob.current
	if f != null and speed < 0.5 and f.contains(_pos):
		_deliver_t += delta
		if _deliver_t > 2.0:
			_deliver_t = 0.0
			for p in cargo.duplicate():
				(p as SupplyPallet).deliver()
			cargo.clear()
	else:
		_deliver_t = 0.0
	# Beside an M777 with a shell pallet: refill the gun
	for p in cargo.duplicate():
		if p.kind != "shells" or not is_instance_valid(p):
			continue
		for g in get_tree().get_nodes_in_group("m777"):
			if g.slung_by != null or g.shells >= Artillery.MAX_SHELLS:
				continue
			if Vector2(g.global_position.x - _pos.x, g.global_position.z - _pos.z).length() < GUN_REACH:
				var n := mini(Artillery.MAX_SHELLS - g.shells, p.amount)
				g.shells += n
				p.amount -= n
				message.emit("PLS: %d shells to the %s (%d left on the pallet)" % [n, g.display_name, p.amount])
		if p.amount <= 0:
			cargo.erase(p)
			p.queue_free()


func _load(p: SupplyPallet) -> void:
	var slot := Node3D.new()
	slot.position = SLOTS[cargo.size()]
	model.add_child(slot)
	p.load_on(self, slot)
	cargo.append(p)
	message.emit("PLS loaded the %s (%d/%d)" % [p.display_name.to_lower(), cargo.size(), CAPACITY])


func cargo_text() -> String:
	var names: PackedStringArray = []
	for p in cargo:
		names.append(p.display_name)
	return ", ".join(names) if not names.is_empty() else "empty"


func destroy() -> void:
	# The pallets burn with it
	for p in cargo:
		if is_instance_valid(p):
			p.queue_free()
	cargo.clear()
	super.destroy()
