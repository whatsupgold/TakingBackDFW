class_name Helicopter
extends AnimatableBody3D
## Shared flight, boarding and hover logic for the Huey and the Chinook.
##
## Flight: right-click to fly somewhere. In LAND mode it sets down on arrival; in HOVER mode
## it stays in the air (toggle with L). Crew in "landed" seats (door gunners) can only be
## shot by Red riflemen while it's on the ground, and Red tanks only fire at it on the ground.
## If it's wrecked (tank rounds), everyone aboard is lost.
## Pickup: right-click a helicopter with infantry (or a Humvee, for the Chinook) selected and
## it lands where it is. Once everyone sent to it is aboard, it lifts off again if it's in
## hover mode. Unload (U) while hovering: it lands, unloads, and climbs back to a hover.
## Subclasses set the numbers in _init() and build the model in _make_model().

signal message(text: String)

const IDLE_ROTOR := 1.0
const FLIGHT_ROTOR := 9.0
const RELIFT_DELAY := 3.0         # seconds after unloading before climbing back to a hover
const PICKUP_GRACE := 1.0         # seconds on the ground before an empty pickup lifts again
const STATE_NAMES := {"landed": "landed", "takeoff": "lifting off", "cruise": "flying", "autorotate": "AUTOROTATING",
		"descend": "landing", "hover": "hovering"}

# --- Set by subclasses ---------------------------------------------------------
var display_name := "Helicopter"   # "Huey"
var long_name := "HELICOPTER"      # "UH-1 HUEY"
var max_speed := 99.2              # m/s: 222 mph (UH-60); the maps are real size
var accel := 4.5
var turn_rate := 1.2
var climb_rate := 8.4
var descent_rate := 5.0
var cruise_alt := 14.0            # (old: kept for the Chinook's set-down hop)
var nap_alt := 30.0               # flying: this high above whatever is below and just ahead
const GRAVITY := 9.81
const MAX_BANK := 0.79            # 45 degrees in a hard turn
const ROLL_RATE := 1.4            # rad/s rolling into and out of a bank
const PEDAL_SPEED := 12.0         # below this it turns on its pedals instead of banking
const AUTOROTATE_SINK := 9.0      # m/s coming down with no power (about 1,800 ft/min)
const FLARE_HEIGHT := 15.0        # metres up where the pilot flares to cushion the landing
var hover_alt := 7.0              # metres above the ground (or nearby roofs) when hovering
var squad_capacity := 2
var vehicle_capacity := 0         # Humvees
var body_size := Vector3(2.4, 2.4, 5.4)
var body_offset := Vector3(0, 1.3, -0.1)
var ring_radius := 4.0
var ring_color := Color(0.6, 0.8, 1.0)
var crew_color := Color(0.55, 0.58, 0.66)
var seat_list: Array = []
var board_points: Array = [Vector3.ZERO]     # local spots troops climb in at
var door_points: Array = [Vector3.ZERO]      # local spots troops walk to (outside the body)
var board_reach := 3.4
var fast_rope := false            # unloading while hovering: troops slide down ropes (Black Hawk)
var _rope_queue: Array = []
var _rope_t := 0.0
var _rope_hold := 0.0
var _fast_ropes: Array = []
var gun_rounds_max := 0           # mounted gun ammunition (refilled at the FOB)
var gun_rounds := -1
var can_rounds_max := 0           # troop carriers: two ammo cans for the squads riding in it
var can_rounds := -1
var max_hp := 120.0
var fuel_max := 360.0             # gallons
var endurance := 420.0            # seconds in the air on a full tank (game scale)
var fuel := -1.0
var face_yaw := NAN               # heading to turn to on arrival (NAN: keep the flight heading)
var _fuel_warned := false
var _dry := false                 # ran dry: forced down, can't lift until refuelled

# --- Runtime -----------------------------------------------------------------
var enemy: RedArmy
var nav_map: RID
var hp := 120.0
var destroyed := false
var model: VehicleModel
var crew: Crew
var selected := false
var state := "landed"             # landed, takeoff, cruise, descend, hover
var hover_mode := false
var passengers: Array[Soldier] = []
var cargo: Array = []             # Humvees aboard
var inbound: Array = []           # soldiers and Humvees on their way to board
var speed := 0.0

var _dest := Vector3.ZERO
var _yaw := 0.0
var _pos := Vector3.ZERO
var _cruise_y := 0.0
var _hover_y := 0.0
var _pickup := false              # landed to pick someone up
var _ground_t := 0.0              # time since touchdown
var _unload_on_land := false
var _relift_t := -1.0
var _force_hover := false         # stay in the air on arrival whatever the mode (sling load)
var _land_once := false           # land on arrival even in hover mode (dropping off the gun crew)
var _unload_only: Squad = null    # on touchdown, unload just this squad
var _ring: MeshInstance3D
var _smoke_t := 0.0
var _route: Array[Vector3] = []   # waypoints before _dest (shift + right-click)
var _bank := 0.0                  # + = left side down (turning left)
var _pitch := 0.0                 # + = nose up
var _vy := 0.0                    # vertical speed while autorotating
var _ceiling_t := 0.0
var _terrain_y := 0.0             # the height it's holding: obstacles ahead + nap_alt
var _climb_limit := 999.0         # slowed down to climb over something tall in time
var _crash_spot := Vector3.ZERO
var force_outcome := ""           # tests only: "hard" or "crash" instead of the crew's roll


func _make_model() -> VehicleModel:
	return VehicleModel.huey()


func place(at: Vector3, yaw_deg: float) -> void:
	_pos = at
	_yaw = deg_to_rad(yaw_deg)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)


func _ready() -> void:
	if gun_rounds < 0:
		gun_rounds = gun_rounds_max
	if can_rounds < 0:
		can_rounds = can_rounds_max
	if fuel < 0.0:
		fuel = fuel_max
	sync_to_physics = false     # we set the transform ourselves every tick
	add_to_group("refuelable")
	collision_layer = 8
	collision_mask = 0
	hp = max_hp
	var shape := BoxShape3D.new()
	shape.size = body_size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = body_offset
	add_child(col)

	model = _make_model()
	add_child(model)
	model.rotor_factor = IDLE_ROTOR
	_ring = GroundVehicle._make_ring(ring_radius, ring_color)
	add_child(_ring)

	crew = Crew.new(display_name, crew_color, seat_list)
	crew.spawn(self, enemy)


func set_selected(value: bool) -> void:
	selected = value and not destroyed
	_ring.visible = selected


func is_targetable() -> bool:
	## Red tanks only shoot at helicopters on (or just above) the ground
	return not destroyed and (state == "landed" or (state == "descend" and _pos.y - _dest.y < 2.0))


func is_air_target() -> bool:
	## Red anti-air can shoot at it (in the air, not on or just above the ground)
	return not destroyed and state != "landed" and _pos.y - _ground_y(_pos) > 2.0


func take_flak(amount: float) -> void:
	if not is_air_target():
		return
	var before := hp
	hp -= amount
	if hp <= max_hp * 0.5 and before > max_hp * 0.5:
		message.emit("%s hit by anti-air: %d%% armor left. Get it out of range!" % [display_name, int(100.0 * hp / max_hp)])
	if hp <= 0.0:
		hp = 0.0
		var ground := _ground_y(_pos)
		destroy()
		_dest = Vector3(_pos.x, ground, _pos.z)
		state = "crash"
		message.emit("%s shot down by anti-air" % display_name)


func take_vehicle_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		destroy()


func destroy() -> void:
	if destroyed:
		return
	destroyed = true
	set_selected(false)
	model.burn()
	enemy.gibs.explosion(global_position + Vector3.UP * 1.5)
	for s in crew.squad.soldiers.duplicate():
		s.die()
	for s in passengers.duplicate():
		if is_instance_valid(s) and not s.dead:
			s.die()
	passengers.clear()
	for v in cargo:
		v.carried_by = null
		v.visible = true
		v.destroy()
	cargo.clear()
	_abandon_inbound()
	# Falls out of the sky if it was flying
	_dest = Vector3(_pos.x, _ground_y(Vector3(_pos.x, _pos.y + 200.0, _pos.z)), _pos.z)
	state = "crash"
	message.emit("%s destroyed" % display_name)


func is_landed() -> bool:
	return state == "landed"


func is_airborne() -> bool:
	return state != "landed"


func state_name() -> String:
	return STATE_NAMES.get(state, state)


func stop() -> void:
	pass


# --- Orders -------------------------------------------------------------------

func order_fly(p: Vector3, face := NAN) -> void:
	if destroyed:
		return
	if crew.count() == 0:
		message.emit("The %s has no crew left to fly it" % display_name)
		return
	if not _has_fuel():
		return
	face_yaw = face
	_abandon_inbound()
	_pickup = false
	_unload_on_land = false
	_relift_t = -1.0
	_route.clear()
	_dest = p
	_ceiling_t = 0.0
	if state == "hover":
		state = "cruise"
	elif state != "cruise":
		state = "takeoff"
	crew.set_landed(false)


func queue_fly(p: Vector3) -> void:
	## Shift + right-click: one more waypoint after the ones it's already flying
	if state == "cruise" or state == "takeoff":
		if fuel <= 0.0 or destroyed:
			return
		_route.append(_dest)
		_dest = p
		face_yaw = NAN
	else:
		order_fly(p)


func _has_fuel() -> bool:
	if fuel > 0.0:
		return true
	message.emit("The %s is out of fuel: bring the fuel truck to it" % display_name)
	return false


func fuel_text() -> String:
	return "%d / %d gal" % [ceili(fuel), int(fuel_max)]


func needs_fuel() -> bool:
	return not destroyed and fuel < fuel_max - 0.5


func is_parked() -> bool:
	return not destroyed and state == "landed"


func add_fuel(amount: float) -> void:
	fuel = minf(fuel_max, fuel + amount)
	if fuel > 0.0:
		_dry = false
	if fuel > fuel_max * 0.2:
		_fuel_warned = false


func planned_path() -> PackedVector3Array:
	## Where it was told to fly (for the overlay)
	var out := PackedVector3Array()
	if destroyed or not (state == "cruise" or state == "takeoff"):
		return out
	out.append(_pos)
	for w in _route:
		out.append(w)
	out.append(_dest)
	return out


func goal() -> Vector3:
	return _dest if state == "cruise" or state == "takeoff" or state == "descend" else _pos


func toggle_hover() -> void:
	set_hover_mode(not hover_mode)


func set_hover_mode(value: bool) -> void:
	if destroyed:
		return
	hover_mode = value
	if hover_mode:
		if state == "landed":
			if _purge_inbound() > 0:
				_pickup = true
				message.emit("%s: hover mode — lifting once everyone is aboard" % display_name)
			elif crew.count() > 0 and _has_fuel():
				_lift()
				message.emit("%s: hovering" % display_name)
		else:
			message.emit("%s: hover mode" % display_name)
	else:
		if not can_land():
			hover_mode = true
			message.emit("%s can't land with the M777 slung under it: set the gun down first (right-drag)" % display_name)
			return
		if state == "hover":
			land_here()
			message.emit("%s: landing" % display_name)
		else:
			message.emit("%s: land mode" % display_name)


func can_land() -> bool:
	return true


func _hover_extra() -> float:
	## Extra height to keep (a slung load hangs below)
	return 0.0


func land_here() -> void:
	## Set down below where it is now (snapped to walkable ground so troops can reach it)
	if not can_land():
		_hover_y = _hover_height(_pos)
		state = "hover"
		return
	_dest = _landing_spot(_pos)
	state = "descend"


func request_pickup() -> void:
	if destroyed:
		return
	## Troops (or a Humvee) are coming: land now if airborne, and stay down until they're in
	if crew.count() == 0:
		return
	if not can_land():
		message.emit("%s can't land for a pickup with the M777 slung under it" % display_name)
		return
	_pickup = true
	_ground_t = 0.0
	if state == "hover" or state == "takeoff" or state == "cruise":
		land_here()
		message.emit("%s landing for pickup" % display_name)


func add_inbound(n: Node) -> void:
	if not (n in inbound):
		inbound.append(n)


# --- Boarding ------------------------------------------------------------------

func max_squads(vehicles: int) -> int:
	return squad_capacity if vehicles == 0 else 0


func passenger_squads() -> Array:
	var out: Array = []
	for s in passengers:
		if not (s.squad in out):
			out.append(s.squad)
	return out


func committed_squads() -> Array:
	## Squads aboard plus squads walking to it
	var out := passenger_squads()
	_purge_inbound()
	for n in inbound:
		if n is Soldier and not (n.squad in out):
			out.append(n.squad)
	return out


func committed_vehicles() -> int:
	_purge_inbound()
	var n := cargo.size()
	for v in inbound:
		if v is Humvee:
			n += 1
	return n


func capacity_text() -> String:
	if vehicle_capacity == 0:
		return "max %d squads" % squad_capacity
	return "%d squads / %d Humvees / 1 Humvee + %d squads" % [max_squads(0), vehicle_capacity, max_squads(1)]


func _landing_xform() -> Transform3D:
	var at := _dest if state == "descend" else _pos
	if state != "landed" and state != "descend":
		at = _landing_spot(_pos)
	return Transform3D(Basis(Vector3.UP, _yaw), at)


func door_point(from: Vector3) -> Vector3:
	var xf := _landing_xform()
	var best := xf * (door_points[0] as Vector3)
	for d in door_points:
		var p: Vector3 = xf * (d as Vector3)
		if from.distance_to(p) < from.distance_to(best):
			best = p
	return best


func in_reach(p: Vector3, extra := 0.0) -> bool:
	for b in board_points:
		var g := to_global(b as Vector3)
		if Vector2(p.x - g.x, p.z - g.z).length() < board_reach + extra:
			return true
	return false


func board_soldier(s: Soldier) -> bool:
	if state != "landed":
		return false
	var squads := passenger_squads()
	if not (s.squad in squads) and squads.size() >= max_squads(cargo.size()):
		return false
	s.board()
	passengers.append(s)
	inbound.erase(s)
	return true


func board_vehicle(h: Humvee) -> bool:
	if state != "landed" or cargo.size() >= vehicle_capacity:
		return false
	if passenger_squads().size() > max_squads(cargo.size() + 1):
		return false
	h.stow(self)
	cargo.append(h)
	inbound.erase(h)
	message.emit("Humvee loaded into the %s" % display_name)
	return true


func unload(only: Squad = null) -> void:
	if destroyed:
		return
	if passengers.is_empty() and cargo.is_empty():
		message.emit("The %s has nobody aboard" % display_name)
		return
	if state == "hover" and fast_rope and cargo.is_empty():
		_start_fast_rope(only)
		return
	if state != "landed":
		if not can_land():
			message.emit("%s can't land with the M777 slung under it: set the gun down first (right-drag)" % display_name)
			return
		_unload_on_land = true
		if state == "hover":
			land_here()
		message.emit("%s landing to unload" % display_name)
		return
	var n := 0
	var staying: Array[Soldier] = []
	for s in passengers:
		if not is_instance_valid(s) or s.dead:
			continue
		if only != null and s.squad != only:
			staying.append(s)
			continue
		var spot := _unload_spot(n, false)
		s.unboard(spot)
		s.order_move(NavigationServer3D.map_get_closest_point(nav_map, _unload_spot(n, true)))
		n += 1
	passengers = staying
	if only != null:
		message.emit("%s unloaded %s" % [display_name, only.squad_name])
		if hover_mode:
			_relift_t = RELIFT_DELAY
		return
	var k := 0
	for h in cargo:
		var spot := to_global(Vector3(0.0, 0.0, door_points[0].z + 1.2))
		spot = NavigationServer3D.map_get_closest_point(nav_map, spot)
		spot.y = _ground_y(spot)
		h.unstow(spot, _yaw + PI)
		var out := to_global(Vector3((k - 0.5) * 6.0 if cargo.size() > 1 else 0.0, 0.0, door_points[0].z + 12.0 + k * 7.0))
		h.order_move(NavigationServer3D.map_get_closest_point(nav_map, out))
		k += 1
	cargo.clear()
	var parts: PackedStringArray = []
	if n > 0:
		parts.append("%d troops" % n)
	if k > 0:
		parts.append("%d Humvee%s" % [k, "s" if k > 1 else ""])
	message.emit("%s unloaded: %s" % [display_name, ", ".join(parts)])
	if hover_mode:
		_relift_t = RELIFT_DELAY


func _unload_spot(i: int, walk_out: bool) -> Vector3:
	## Default: out the side doors, alternating left and right
	var side := -1.0 if i % 2 == 0 else 1.0
	var row := floori(i / 2.0) * 0.9
	var x := side * (5.0 if walk_out else 2.4)
	var p := to_global(Vector3(x, 0.0, -1.0 + row))
	if not walk_out:
		p.y = _ground_y(p) + 0.1
	return p


func _purge_inbound() -> int:
	for n in inbound.duplicate():
		var keep: bool = is_instance_valid(n) and n.board_target == self
		if keep and n is Soldier:
			keep = not n.dead and not n.boarded
		elif keep and n is Humvee:
			keep = n.carried_by == null and n.crew.count() > 0
		if not keep:
			inbound.erase(n)
	return inbound.size()


func _abandon_inbound() -> void:
	var left := 0
	_purge_inbound()
	for n in inbound:
		n.board_target = null
		left += 1
	inbound.clear()
	if left > 0 and state == "landed":
		message.emit("%s lifting off: %d still on their way were left behind" % [display_name, left])


# --- Flight -----------------------------------------------------------------

func _lift() -> void:
	if fuel <= 0.0:
		return
	_hover_y = _hover_height(_pos)
	state = "hover"
	crew.set_landed(false)


func _start_fast_rope(only: Squad) -> void:
	_rope_queue.clear()
	for s in passengers:
		if is_instance_valid(s) and not s.dead and (only == null or s.squad == only):
			_rope_queue.append(s)
	if _rope_queue.is_empty():
		return
	_rope_t = 0.8
	message.emit("%s fast-roping %d troops" % [display_name, _rope_queue.size()])


func _fast_rope_tick(delta: float) -> void:
	if _rope_queue.is_empty() and _rope_hold <= 0.0:
		for r in _fast_ropes:
			(r as Node3D).visible = false
		return
	var drop := _pos.y - _ground_y(_pos)
	if _fast_ropes.is_empty():
		for side in [-1.0, 1.0]:
			var m := BoxMesh.new()
			m.size = Vector3(0.06, 1.0, 0.06)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = VehicleModel._mat(Color(0.20, 0.17, 0.12))
			mi.set_meta("side", side)
			add_child(mi)
			_fast_ropes.append(mi)
	for r in _fast_ropes:
		(r as MeshInstance3D).visible = true
		(r as MeshInstance3D).scale = Vector3(1, maxf(0.5, drop), 1)
		(r as MeshInstance3D).position = Vector3(float(r.get_meta("side")) * 1.25, -drop * 0.5 + 1.0, 0.3)
	_rope_hold -= delta
	if _rope_queue.is_empty():
		return
	_rope_hold = 1.5
	_rope_t -= delta
	if _rope_t > 0.0:
		return
	_rope_t = 0.45
	var s: Soldier = _rope_queue.pop_front()
	if not is_instance_valid(s) or s.dead or not (s in passengers):
		return
	var side := 1.0 if _rope_queue.size() % 2 == 0 else -1.0
	var foot := to_global(Vector3(side * 1.25, 0.0, 0.3))
	foot.y = _ground_y(foot)
	passengers.erase(s)
	s.unboard(foot + Vector3.UP * 0.1)
	var out := to_global(Vector3(side * 5.0, 0.0, 0.3 + randf_range(-2.0, 2.0)))
	s.order_move(NavigationServer3D.map_get_closest_point(nav_map, out))
	if _rope_queue.is_empty():
		message.emit("%s: troops on the ground" % display_name)


func _physics_process(delta: float) -> void:
	_fast_rope_tick(delta)
	if destroyed:
		if state == "crash":
			_pos.y = move_toward(_pos.y, _dest.y, 12.0 * delta)
			global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
			if _pos.y <= _dest.y + 0.01:
				state = "wreck"
				enemy.gibs.explosion(_pos + Vector3.UP)
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.6
			enemy.gibs.smoke(global_position + Vector3.UP * 2.5)
		return
	var p := _pos
	if state != "landed":
		_burn(delta)
	if not is_nan(face_yaw) and (state == "hover" or state == "descend" or (state == "landed" and _ground_t < 4.0)):
		# Arrived: pedal-turn to the heading it was given
		var d := wrapf(face_yaw - _yaw, -PI, PI)
		_yaw += clampf(d, -turn_rate * delta, turn_rate * delta)
		if absf(d) < 0.02:
			face_yaw = NAN
	match state:
		"landed":
			speed = 0.0
			_ground_tick(delta)
		"takeoff":
			# Lift into a low hover, then nose over into forward flight
			var lift := _ground_y(Vector3(p.x, p.y + 1.0, p.z)) + 5.0 + _hover_extra()
			p.y = move_toward(p.y, lift, climb_rate * delta)
			if p.y >= lift - 0.3:
				state = "cruise"
				_ceiling_t = 0.0
		"cruise":
			p = _cruise(p, delta)
		"hover":
			speed = move_toward(speed, 0.0, accel * delta)
			p.y = move_toward(p.y, _hover_y, climb_rate * delta)
			# Station-keeping: creep the last metres onto the spot it was sent to
			var drift := Vector2(_dest.x - p.x, _dest.z - p.z)
			if drift.length() > 0.02 and drift.length() < 6.0:
				var step := minf(drift.length(), 2.0 * delta)
				p.x += drift.normalized().x * step
				p.z += drift.normalized().y * step
		"autorotate":
			p = _autorotate(p, delta)
		"descend":
			speed = move_toward(speed, 0.0, accel * delta)
			var flat := Vector2(_dest.x - p.x, _dest.z - p.z)
			if flat.length() > 0.01:
				var step := minf(flat.length(), 4.0 * delta)
				p.x += flat.normalized().x * step
				p.z += flat.normalized().y * step
			var above := p.y - _dest.y
			p.y = move_toward(p.y, _dest.y, clampf(above * 0.8, 1.0, descent_rate) * delta)
			if p.y <= _dest.y + 0.02 and flat.length() < 0.05:
				p = _dest
				state = "landed"
				_ground_t = 0.0
				crew.set_landed(true)
	_pos = p
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)

	# Banks into turns, the nose dips to speed up and flares back to slow down; level when
	# it's hovering or on the ground
	if state != "cruise" and state != "autorotate":
		_bank = move_toward(_bank, 0.0, ROLL_RATE * delta)
		_pitch = move_toward(_pitch, 0.0, 0.6 * delta)
	model.rotation = Vector3(_pitch, 0.0, _bank)
	var want_rotor := IDLE_ROTOR if state == "landed" else FLIGHT_ROTOR
	model.rotor_factor = move_toward(model.rotor_factor, want_rotor, delta * 3.0)
	if model.ramp:
		var open := state == "landed" or (state == "descend" and _pos.y - _dest.y < 1.5)
		var want_ramp := VehicleModel.RAMP_OPEN if open else VehicleModel.RAMP_CLOSED
		model.ramp.rotation.x = move_toward(model.ramp.rotation.x, want_ramp, delta * 1.6)


func _burn(delta: float) -> void:
	fuel = maxf(0.0, fuel - fuel_max / endurance * delta)
	if not _fuel_warned and fuel < fuel_max * 0.2:
		_fuel_warned = true
		message.emit("%s: low fuel (%d gal), head for the FOB or the fuel truck" % [display_name, ceili(fuel)])
	if fuel <= 0.0 and not _dry:
		# Engines out: autorotate down, gliding a little way ahead to a clear spot
		_dry = true
		hover_mode = false
		_force_hover = false
		_unload_on_land = false
		_route.clear()
		_on_engine_out()
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		_crash_spot = _landing_spot(_pos + fwd * clampf(speed * 3.0, 20.0, 200.0))
		_vy = 0.0
		state = "autorotate"
		message.emit("%s is out of fuel: autorotating down!" % display_name)


func _on_engine_out() -> void:
	## Something to drop before coming down (the Chinook cuts its sling load)
	pass


func _cruise(p: Vector3, delta: float) -> Vector3:
	## Forward flight: bank into turns, slow down for sharp ones, hold nap_alt over whatever is
	## ahead (rising before a building, dropping back after), and brake to stop over the spot
	var target: Vector3 = _route[0] if not _route.is_empty() else _dest
	var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
	var dist := to.length()
	if not _route.is_empty() and dist < maxf(25.0, speed * 1.5):
		_route.pop_front()                     # through a waypoint without stopping
		return p
	var remaining := dist
	if not _route.is_empty():
		var prev := target
		var rest: Array = []
		for i in range(1, _route.size()):
			rest.append(_route[i])
		rest.append(_dest)
		for w in rest:
			remaining += Vector2(w.x - prev.x, w.z - prev.z).length()
			prev = w
	var diff := wrapf(atan2(-to.x, -to.z) - _yaw, -PI, PI) if dist > 1.0 else 0.0
	# Speed: full ahead, slower into a sharp turn, braking to arrive, slower if it must climb
	var want := max_speed * clampf(1.0 - absf(diff) / 2.2, 0.3, 1.0)
	want = minf(want, maxf(1.5, sqrt(2.0 * accel * 0.8 * remaining)))
	# Slow enough that the turn onto the next point is tight enough to reach it (too fast and
	# it circles round it), and brake before a sharp corner at a waypoint
	var lateral := GRAVITY * tan(MAX_BANK)
	if absf(diff) > 0.15:
		var reach := dist * 0.5 / sin(absf(diff))
		want = minf(want, maxf(3.0, sqrt(lateral * reach)))
	if not _route.is_empty():
		var nxt: Vector3 = _route[1] if _route.size() > 1 else _dest
		var leg_in := Vector2(target.x - p.x, target.z - p.z)
		var leg_out := Vector2(nxt.x - target.x, nxt.z - target.z)
		if leg_in.length() > 1.0 and leg_out.length() > 1.0:
			var corner := absf(leg_in.angle_to(leg_out))
			var corner_v := sqrt(lateral * 25.0 / maxf(tan(corner * 0.5), 0.05))
			want = minf(want, sqrt(corner_v * corner_v + 2.0 * accel * maxf(dist - 25.0, 0.0)))

	want = minf(want, _climb_limit)
	var before := speed
	speed = move_toward(speed, want, accel * delta)
	# Turning: banked and coordinated at speed, on the pedals when slow
	var yaw_rate := 0.0
	if speed > PEDAL_SPEED:
		_bank = move_toward(_bank, clampf(diff * 1.6, -MAX_BANK, MAX_BANK), ROLL_RATE * delta)
		yaw_rate = GRAVITY * tan(_bank) / speed
	else:
		_bank = move_toward(_bank, 0.0, ROLL_RATE * delta)
		yaw_rate = clampf(diff * 2.0, -turn_rate, turn_rate)
	var step := yaw_rate * delta
	if absf(step) > absf(diff) and signf(step) == signf(diff):
		step = diff
	_yaw += step
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if _route.is_empty() and dist < 20.0:
		p += to.normalized() * minf(dist, speed * delta)       # settling onto the spot
	else:
		p += fwd * speed * delta
	# Terrain following: what's below and ahead sets the height
	_ceiling_t -= delta
	if _ceiling_t <= 0.0:
		_ceiling_t = 0.25
		var look := clampf(speed * 5.0, 40.0, 500.0)
		var ahead := p + fwd * look
		if _route.is_empty() and dist < look:
			ahead = Vector3(target.x, p.y, target.z)
		var top := _ahead_ceiling(p, ahead)
		_terrain_y = top + (nap_alt if remaining > 120.0 else 12.0) + _hover_extra()
		var need := _terrain_y - p.y
		_climb_limit = 999.0 if need < 5.0 else maxf(8.0, climb_rate * look / need)
	p.y = move_toward(p.y, _terrain_y, (climb_rate if _terrain_y > p.y else descent_rate) * delta)
	# Attitude: nose down with speed, back when braking (a flare)
	var acc := (speed - before) / maxf(delta, 0.001)
	_pitch = lerpf(_pitch, -0.14 * speed / max_speed - clampf(acc * 0.025, -0.25, 0.25), 1.0 - exp(-4.0 * delta))
	# Arrived over the spot
	if _route.is_empty() and dist < 1.5 and speed < 5.0:
		if (hover_mode or _force_hover) and not _unload_on_land and not _pickup and not _land_once:
			_hover_y = _hover_height(_dest)
			state = "hover"
		else:
			_dest = _landing_spot(_dest)
			state = "descend"
	return p


func _ahead_ceiling(a: Vector3, b: Vector3) -> float:
	## The tallest thing (ground or roof) along a -> b and a little to each side
	var space := get_world_3d().direct_space_state
	var top := -INF
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var side := Vector3(-flat.normalized().y, 0.0, flat.normalized().x) * 8.0 if flat.length() > 0.1 else Vector3.ZERO
	var steps := int(flat.length() / 12.0) + 1
	for i in steps + 1:
		var q := a.lerp(b, float(i) / steps)
		for off in [Vector3.ZERO, side, -side]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, 400.0, q.z) + off, Vector3(q.x, -50.0, q.z) + off, 1)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				top = maxf(top, hit.position.y)
	return top if top > -INF else a.y - nap_alt


func _autorotate(p: Vector3, delta: float) -> Vector3:
	## No power: glide down toward the spot it picked, flare near the ground to cushion it,
	## and the crew's skill decides how it ends
	var to := Vector3(_crash_spot.x - p.x, 0.0, _crash_spot.z - p.z)
	var dist := to.length()
	var below := _ground_y(Vector3(p.x, p.y + 0.5, p.z))
	var flare := p.y - below < FLARE_HEIGHT
	if dist > 2.0:
		var diff := wrapf(atan2(-to.x, -to.z) - _yaw, -PI, PI)
		_bank = move_toward(_bank, clampf(diff * 1.6, -0.6, 0.6), ROLL_RATE * delta)
		_yaw += (GRAVITY * tan(_bank) / speed if speed > PEDAL_SPEED else clampf(diff, -0.6, 0.6)) * delta
	speed = move_toward(speed, 2.0 if flare else minf(22.0, maxf(dist * 0.4, 6.0)), (8.0 if flare else 3.0) * delta)
	_vy = move_toward(_vy, -2.5 if flare else -AUTOROTATE_SINK, (12.0 if flare else 4.0) * delta)
	_pitch = lerpf(_pitch, 0.3 if flare else -0.05, 1.0 - exp(-3.0 * delta))
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	p += fwd * speed * delta
	p.y += _vy * delta
	var g := _ground_y(Vector3(p.x, p.y + 1.0, p.z))
	if p.y <= g:
		p.y = g
		_pos = p
		_autorotation_landing()
	return p


func _autorotation_landing() -> void:
	## Touchdown with no power. A good crew walks away from a hard landing; a green one, or
	## coming in too fast, crashes.
	var level: int = crew.squad.total_level()
	var chance := clampf(0.5 + 0.1 * level, 0.5, 0.95)
	if absf(_vy) > 5.0:
		chance -= 0.25
	if speed > 12.0:
		chance -= 0.15
	_bank = 0.0
	var survived := randf() < chance
	if force_outcome != "":
		survived = force_outcome == "hard"
	if survived:
		state = "landed"
		speed = 0.0
		_ground_t = 0.0
		crew.set_landed(true)
		take_vehicle_damage(max_hp * 0.3)
		var aboard: Array = []
		aboard.append_array(passengers)
		aboard.append_array(crew.squad.soldiers)
		for sd in aboard:
			if is_instance_valid(sd) and not sd.dead:
				sd.take_damage(randf_range(5.0, 30.0))
		message.emit("%s made a hard landing: damaged, everyone shaken up (crew level %d)" % [display_name, level])
	else:
		message.emit("%s crashed on landing (crew level %d)" % [display_name, level])
		destroy()


func _ground_tick(delta: float) -> void:
	_ground_t += delta
	_land_once = false
	if _unload_only != null:
		var only := _unload_only
		_unload_only = null
		_landed_for(only)
		return
	if _unload_on_land:
		_unload_on_land = false
		unload()
		return
	if _relift_t >= 0.0:
		_relift_t -= delta
		if _relift_t < 0.0 and hover_mode and _purge_inbound() == 0 and crew.count() > 0:
			_lift()
		return
	if _pickup and _ground_t > PICKUP_GRACE and _purge_inbound() == 0:
		_pickup = false
		if hover_mode and crew.count() > 0:
			message.emit("%s: everyone aboard, lifting off" % display_name)
			_lift()


func _landed_for(sq: Squad) -> void:
	unload(sq)


func _hover_height(at: Vector3) -> float:
	var ground := _ground_y(Vector3(at.x, at.y + 200.0, at.z))
	return maxf(ground + hover_alt, _route_ceiling(at, at) + 4.0) + _hover_extra()


func _landing_spot(at: Vector3) -> Vector3:
	var g := Vector3(at.x, _ground_y(Vector3(at.x, at.y + 200.0, at.z)), at.z)
	var snapped := NavigationServer3D.map_get_closest_point(nav_map, g)
	if snapped == Vector3.ZERO or Vector2(snapped.x - g.x, snapped.z - g.z).length() > 25.0:
		return g
	snapped.y = _ground_y(Vector3(snapped.x, snapped.y + 3.0, snapped.z))
	return snapped


func _route_ceiling(a: Vector3, b: Vector3) -> float:
	## The tallest thing under the flight path (so it doesn't fly through towers)
	var space := get_world_3d().direct_space_state
	var top := 0.0
	var steps := int(Vector2(b.x - a.x, b.z - a.z).length() / 8.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for off in [Vector3.ZERO, Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6), Vector3(0, 0, -6)]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 250.0, p.z) + off, Vector3(p.x, -5.0, p.z) + off, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				top = maxf(top, hit.position.y)
	return top


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 300.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p.y if hit.is_empty() else hit.position.y
