class_name Chinook
extends Helicopter
## CH-47 Chinook with a crew of 5: pilot, co-pilot, flight engineer on the ramp gun and two
## door gunners (M240s). Everyone loads and unloads over the rear ramp.
## Carries 5 squads, or 2 Humvees, or 1 Humvee and 3 squads.
## Flight, hover mode and pickups are in Helicopter.
##
## Sling load: it can carry a supply pallet on a hook (right-click the pallet; set it down
## inside the FOB walls and it goes into the stock), or the M777, but only with the gun's crew
## squad aboard
## (they take one squad's place). It hovers over the gun, drops to hook height, hooks it and
## climbs. While the gun is slung it can't land and flies slower. Right-drag to set it down:
## the press is where it goes, the drag is where the barrel points. It lowers the gun, turns
## it to face that way, unhooks, then lands beside it to drop off the crew, who man the gun.

const SLING_LEN := 8.0            # the gun hangs this far below the helicopter
const SLUNG_SPEED := 56.6         # about 110 knots with a load on the hook
const HOOK_TIME := 1.5
const GUN_TURN := 0.7              # rad/s the slung gun is turned to its drop heading
const CREW_DROP := Vector3(0.0, 0.0, 22.0)   # where it lands to drop the crew (behind the gun)

const MAX_SQUADS_BY_VEHICLES := [8, 4, 0]    # squads of 4 (33 seats) it can still take with 0, 1, 2 Humvees aboard
const M240 := {"range": 36.0, "interval": 0.11, "damage": 1.4, "accuracy": 0.05, "mag": 100, "reload": 4.0}
const SEATS := [
	{"role": "Pilot", "pos": Vector3(0.6, 1.0, -6.8), "visible": false, "exposed": "never"},
	{"role": "Co-pilot", "pos": Vector3(-0.6, 1.0, -6.8), "visible": false, "exposed": "never"},
	{"role": "Ramp gunner", "pos": Vector3(0.0, 0.62, 7.9), "yaw": PI, "visible": "landed", "exposed": "landed", "fires": true, "weapon": M240},
	{"role": "Door gunner", "pos": Vector3(1.55, 0.85, -5.0), "yaw": -PI / 2.0, "visible": true, "exposed": "landed", "fires": true, "weapon": M240},
	{"role": "Door gunner", "pos": Vector3(-1.55, 0.85, -5.0), "yaw": PI / 2.0, "visible": true, "exposed": "landed", "fires": true, "weapon": M240},
]


func _init() -> void:
	display_name = "Chinook"
	fuel_max = 1030.0
	endurance = 480.0
	long_name = "CH-47 CHINOOK"
	gun_rounds_max = 2700         # three M240s
	can_rounds_max = 2 * Fob.CAN_ROUNDS
	max_speed = 87.6
	accel = 3.5
	turn_rate = 0.9
	climb_rate = 7.7
	descent_rate = 4.5
	hover_alt = 9.0
	squad_capacity = 8
	vehicle_capacity = 2
	body_size = Vector3(3.4, 3.4, 16.4)
	body_offset = Vector3(0, 1.95, 0.4)
	ring_radius = 9.5
	ring_color = Color(0.85, 0.75, 0.45)
	crew_color = Color(0.62, 0.58, 0.45)
	seat_list = SEATS
	door_points = [Vector3(0.0, 0.0, 10.4)]
	board_points = [Vector3(0.0, 0.0, 8.8)]
	board_reach = 3.0


var sling_gun = null               # the M777 or a pallet (Node3D), hooked (or being hooked)
var sling_pending = null           # waiting for the gun crew to board before hooking
var sling_phase := ""               # to_hook, hooking, carry, to_drop, lowering
var _hook_t := 0.0
var _gun_rel_yaw := 0.0
var _drop_at := Vector3.ZERO
var _drop_yaw := 0.0
var _rope: MeshInstance3D


func _ready() -> void:
	super._ready()
	var m := BoxMesh.new()
	m.size = Vector3(0.07, 1.0, 0.07)
	_rope = MeshInstance3D.new()
	_rope.mesh = m
	_rope.material_override = Level.make_material(Color(0.15, 0.14, 0.12))
	_rope.visible = false
	add_child(_rope)


func _make_model() -> VehicleModel:
	return HeliModels.chinook()


func max_squads(vehicles: int) -> int:
	return MAX_SQUADS_BY_VEHICLES[clampi(vehicles, 0, 2)]


func _unload_spot(i: int, walk_out: bool) -> Vector3:
	## Out the back in rows of five, then a walk clear of the rotors
	var x := (i % 5 - 2) * 1.2
	var z: float = (door_points[0] as Vector3).z + floori(i / 5.0) * 1.1
	if walk_out:
		z += 8.0
	var p := to_global(Vector3(x, 0.0, z))
	if not walk_out:
		p.y = _ground_y(p) + 0.1
	return p


# --- Sling load ---------------------------------------------------------------------

func is_slung() -> bool:
	return sling_gun != null and sling_gun.slung_by == self


func can_land() -> bool:
	return sling_gun == null


func _hover_extra() -> float:
	return SLING_LEN if sling_gun != null else 0.0


func crew_aboard(gun) -> bool:
	## Is the gun's crew (whoever is left of it) riding in here?
	var sq = gun.crew_squad
	if sq == null or sq.soldiers.is_empty():
		return true
	for sd in sq.soldiers:
		if not (sd in passengers):
			return false
	return true


func start_sling(gun) -> void:
	## Fly to the gun and hook it (the crew must already be aboard)
	sling_pending = null
	sling_gun = gun
	sling_phase = "to_hook"
	_force_hover = true
	order_fly(gun.global_position)
	message.emit("%s going to hook the %s" % [display_name, gun.display_name])


func order_fly(p: Vector3, face := NAN) -> void:
	if sling_phase == "lowering" or sling_phase == "hooking":
		message.emit("%s is busy with its sling load: wait until it's done" % display_name)
		return
	if is_slung() and sling_phase == "to_drop":
		sling_phase = "carry"
	elif sling_phase == "to_hook" and p.distance_to(sling_gun.global_position) > 1.0:
		_cancel_sling("hook cancelled")
	super.order_fly(p, face)


func order_drop(at: Vector3, yaw: float) -> void:
	## Set the slung gun down at `at` with the barrel facing `yaw`
	if not is_slung():
		return
	if sling_phase == "lowering":
		return
	_drop_at = at
	_drop_yaw = yaw
	super.order_fly(at)
	sling_phase = "to_drop"
	message.emit("%s taking the %s down there" % [display_name, sling_gun.display_name])


func _cancel_sling(why: String) -> void:
	if sling_gun != null and not is_slung():
		sling_gun = null
		_force_hover = false
	sling_phase = "carry" if is_slung() else ""
	message.emit("%s: %s" % [display_name, why])


func destroy() -> void:
	if is_slung():
		# The gun falls where it is
		var g = sling_gun
		var at := Vector3(_pos.x, _ground_y(Vector3(_pos.x, _pos.y, _pos.z)), _pos.z)
		g.set_down(at, g.rotation.y)
		sling_gun = null
		_rope.visible = false
	sling_pending = null
	super.destroy()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if destroyed:
		return
	_sling_tick(delta)


func _sling_tick(delta: float) -> void:
	# Waiting for the crew to climb in before going for the gun
	if sling_pending != null:
		if not is_instance_valid(sling_pending) or sling_pending.slung_by != null:
			sling_pending = null
		elif crew_aboard(sling_pending) and state in ["landed", "hover"]:
			start_sling(sling_pending)
		elif state == "landed" and _purge_inbound() == 0 and not crew_aboard(sling_pending) and _ground_t > 3.0:
			sling_pending = null
			message.emit("%s: the gun crew didn't board, so no sling load" % display_name)
	if sling_gun == null:
		max_speed = 87.6
		return
	if not is_instance_valid(sling_gun):
		sling_gun = null
		sling_phase = ""
		_force_hover = false
		_rope.visible = false
		return
	var gun = sling_gun
	match sling_phase:
		"to_hook":
			if state == "hover" and Vector2(_pos.x - gun.global_position.x, _pos.z - gun.global_position.z).length() < 1.0:
				sling_phase = "hooking"
				_hook_t = HOOK_TIME
				_hover_y = gun.global_position.y + SLING_LEN
		"hooking":
			if absf(_pos.y - _hover_y) < 0.25:
				_hook_t -= delta
				_rope.visible = true
				_set_rope(SLING_LEN - 1.6)
				if _hook_t <= 0.0:
					_gun_rel_yaw = wrapf(gun.rotation.y - _yaw, -PI, PI)
					gun.hook(self)
					sling_phase = "carry"
					_hover_y = _hover_height(_pos)
					if gun is Artillery:
						message.emit("M777 hooked. Right-drag where it should go: the drag sets which way the barrel points")
					else:
						message.emit("%s hooked. Fly it inside the FOB walls and press U to set it down" % gun.display_name)
		"to_drop":
			if state == "hover" and Vector2(_pos.x - _drop_at.x, _pos.z - _drop_at.z).length() < 1.0:
				sling_phase = "lowering"
				_hover_y = _ground_y(Vector3(_drop_at.x, _pos.y, _drop_at.z)) + SLING_LEN
		"lowering":
			var want := wrapf(_drop_yaw - _yaw, -PI, PI)
			_gun_rel_yaw = move_toward(_gun_rel_yaw, want, GUN_TURN * delta)
			if absf(_pos.y - _hover_y) < 0.25 and absf(_gun_rel_yaw - want) < 0.01:
				_release_gun()
				return
	if is_slung():
		max_speed = SLUNG_SPEED
		_rope.visible = true
		_set_rope(SLING_LEN - 1.6)
		var sway := sin(Time.get_ticks_msec() * 0.0015) * 0.04 * minf(1.0, speed / 4.0)
		gun.global_transform = Transform3D(Basis(Vector3.UP, _yaw + _gun_rel_yaw + sway), _pos + Vector3.DOWN * SLING_LEN)


func _on_engine_out() -> void:
	## Engines out with a load on the hook: the crew cuts it loose to save the aircraft
	if sling_gun != null and is_slung():
		var gun = sling_gun
		gun.set_down(Vector3(_pos.x, _ground_y(_pos), _pos.z), _yaw + _gun_rel_yaw)
		sling_gun = null
		sling_phase = ""
		_rope.visible = false
		message.emit("%s cut its sling load loose" % display_name)
	elif sling_gun != null:
		_cancel_sling("engines out")


func _set_rope(length: float) -> void:
	_rope.scale = Vector3(1.0, length, 1.0)
	_rope.position = Vector3(0.0, -length * 0.5 + 0.2, 0.0)


func _release_gun() -> void:
	var gun = sling_gun
	var at := Vector3(_drop_at.x, _ground_y(Vector3(_drop_at.x, _pos.y, _drop_at.z)), _drop_at.z)
	gun.set_down(at, _drop_yaw)
	sling_gun = null
	sling_phase = ""
	_force_hover = false
	_rope.visible = false
	max_speed = 87.6
	_hover_y = _hover_height(_pos)
	var crew_sq = gun.crew_squad
	var have_crew: bool = crew_sq != null and not crew_sq.soldiers.is_empty() and crew_aboard(gun)
	if not have_crew:
		if gun.get("state") != "delivered":
			message.emit("%s set down" % gun.display_name)
		return
	# Land behind the gun and let the crew out
	var spot := _landing_spot(gun.to_global(CREW_DROP))
	_dest = spot
	_cruise_y = maxf(_pos.y, _route_ceiling(_pos, spot) + 6.0)
	_land_once = true
	_unload_only = crew_sq
	_pickup = false
	state = "cruise"
	crew.set_landed(false)
	message.emit("M777 set down. Landing to drop off the gun crew")


func _landed_for(sq: Squad) -> void:
	unload(sq)
	# The crew walks over and mans the gun
	for g in get_tree().get_nodes_in_group("m777"):
		if g.crew_squad == sq:
			g.call_crew(nav_map)
