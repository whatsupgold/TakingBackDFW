class_name GroundVehicle
extends AnimatableBody3D
## Shared driving, crew, armor and wreck logic for the Humvee and the Stryker.
## Right-click to drive (it follows the navmesh). Driving into Red riflemen at speed runs
## them over. Rifles can only hit exposed crew; tank rounds and blasts damage the hull,
## and at 0 hit points it's destroyed with everyone inside.
## Subclasses set the numbers in _init() and build the model in _make_model().

signal message(text: String)

# --- Set by subclasses -----------------------------------------------------------
var display_name := "Vehicle"
var long_name := "VEHICLE"
var max_speed := 9.0              # m/s, real top speed (the maps are real size)
var accel := 6.0
var brake := 6.0                  # m/s² when slowing (for corners and stopping)
var turn_rate := 1.8              # rad/s at speed
var runover_speed := 3.0
var gun_rounds_max := 0           # mounted gun ammunition (refilled at the FOB)
var gun_rounds := -1
var can_rounds_max := 0           # troop carriers: two ammo cans for the squads riding in it
var can_rounds := -1
var max_hp := 100.0
var seat_list: Array = []
var gunner_seat := 1              # whose target the turret follows
var body_size := Vector3(2.2, 1.9, 4.7)
var body_offset := Vector3(0, 0.95, 0)
var ring_radius := 3.0
var ring_color := Color(0.55, 0.95, 0.55)
var crew_color := Color(0.35, 0.75, 0.35)
var air_mobile := true            # fits in a Chinook
var fuel_max := 25.0              # gallons in the tank
var fuel_range := 12000.0         # metres it can drive on a full tank (game scale)
var fuel := -1.0

# --- Runtime -----------------------------------------------------------------------
var enemy: RedArmy
var nav_map: RID
var model: VehicleModel
var crew: Crew
var selected := false
var speed := 0.0
var driving := false
var hp := 100.0
var destroyed := false
var board_target: Node3D = null   # Chinook it's driving to
var carried_by: Node3D = null     # Chinook it's inside

var _path := PackedVector3Array()
var _path_i := 0
var _ring: MeshInstance3D
var _yaw := 0.0
var _pos := Vector3.ZERO
var _col: CollisionShape3D
var _smoke_t := 0.0
var face_yaw := NAN               # turn to this heading on arrival (NAN: keep the last heading)
var _turning := false
var _queue: Array[Vector3] = []   # waypoints after this one (shift + right-click)
var _fuel_warned := false


func _make_model() -> VehicleModel:
	return VehicleModel.humvee()


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
	add_to_group("blue_vehicles")
	hp = max_hp
	var shape := BoxShape3D.new()
	shape.size = body_size
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position = body_offset
	add_child(_col)

	model = _make_model()
	add_child(model)
	_ring = _make_ring(ring_radius, ring_color)
	add_child(_ring)

	crew = Crew.new(display_name, crew_color, seat_list)
	crew.spawn(self, enemy)


func set_selected(value: bool) -> void:
	selected = value and not destroyed
	_ring.visible = selected


func is_targetable() -> bool:
	## Can Red tanks see and shoot it
	return not destroyed and carried_by == null and visible


func order_move(p: Vector3, face := NAN) -> void:
	if destroyed:
		return
	if fuel <= 0.0:
		message.emit("The %s is out of fuel: send the fuel truck, or tow it in" % display_name)
		return
	if carried_by != null:
		message.emit("The %s is inside the Chinook: unload it first (U)" % display_name)
		return
	if crew.count() == 0:
		message.emit("The %s has no crew left to drive it" % display_name)
		return
	board_target = null
	_queue.clear()
	_path = Level.find_path(nav_map, _pos, p)
	_path_i = 1
	driving = _path.size() > 1
	face_yaw = face
	_turning = not driving and not is_nan(face)


func queue_move(p: Vector3) -> void:
	## Shift + right-click: drive here after the current destination
	if driving:
		_queue.append(p)
	else:
		order_move(p)


func planned_path() -> PackedVector3Array:
	## What's left of the route it was told to drive (for the overlay)
	var out := PackedVector3Array()
	if destroyed or carried_by != null:
		return out
	if driving and _path_i < _path.size():
		out.append(_pos)
		for i in range(_path_i, _path.size()):
			out.append(_path[i])
		for q in _queue:
			out.append(q)
	return out


func goal() -> Vector3:
	return _path[-1] if driving and _path.size() > 0 else _pos


func fuel_text() -> String:
	return "%d / %d gal" % [ceili(fuel), int(fuel_max)]


func needs_fuel() -> bool:
	return not destroyed and fuel < fuel_max - 0.5


func is_parked() -> bool:
	## Stopped where a fuel truck or the FOB can top it up
	return not destroyed and carried_by == null and speed < 0.5


func add_fuel(amount: float) -> void:
	fuel = minf(fuel_max, fuel + amount)
	if fuel > fuel_max * 0.2:
		_fuel_warned = false


func stop() -> void:
	driving = false
	_turning = false
	_queue.clear()
	board_target = null


func stow(heli: Node3D) -> void:
	## Driven into a Chinook: hidden and riding along until unloaded
	carried_by = heli
	board_target = null
	driving = false
	speed = 0.0
	visible = false
	_col.disabled = true
	crew.stowed = true
	crew.assign()


func unstow(at: Vector3, yaw: float) -> void:
	carried_by = null
	_pos = at
	_yaw = yaw
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
	visible = true
	_col.disabled = false
	crew.stowed = false
	crew.assign()


# --- Damage -------------------------------------------------------------------------

func take_vehicle_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		destroy()


func destroy() -> void:
	## Burnt-out wreck: everyone inside is lost
	if destroyed:
		return
	destroyed = true
	driving = false
	speed = 0.0
	set_selected(false)
	model.burn()
	enemy.gibs.explosion(global_position + Vector3.UP * 1.0)
	for s in crew.squad.soldiers.duplicate():
		s.die()
	_on_destroyed()
	message.emit("%s destroyed" % display_name)


func _on_destroyed() -> void:
	pass


# --- Driving ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if destroyed:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.6
			enemy.gibs.smoke(global_position + Vector3.UP * 1.8)
		return
	if carried_by != null:
		_pos = carried_by.global_position
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
		return
	if board_target != null:
		if not is_instance_valid(board_target):
			board_target = null
		elif board_target.in_reach(_pos, 1.5) and board_target.board_vehicle(self):
			return
	var target_speed := 0.0
	if fuel <= 0.0 and (driving or _turning):
		driving = false
		_turning = false
		message.emit("%s is out of fuel" % display_name)
	if _turning and crew.count() > 0:
		# Arrived: turn to face the way it was told (a slow pivot / three-point turn)
		var d := wrapf(face_yaw - _yaw, -PI, PI)
		var step := turn_rate * 0.5 * delta
		_yaw += clampf(d, -step, step)
		_burn(0.4 * delta)
		if absf(d) < 0.02:
			_turning = false
	if driving and crew.count() > 0 and _path_i < _path.size():
		var w := _path[_path_i]
		var to := Vector3(w.x - _pos.x, 0.0, w.z - _pos.z)
		var last := _path_i == _path.size() - 1
		if to.length() < (0.8 if last else 2.0):
			if last and not _queue.is_empty():
				# On to the next waypoint
				var rest := _queue.duplicate()
				var nxt: Vector3 = rest.pop_front()
				order_move(nxt, face_yaw)
				_queue = rest
			elif last:
				driving = false
				_turning = not is_nan(face_yaw)
			else:
				_path_i += 1
		else:
			var want := atan2(-to.x, -to.z)
			var diff := wrapf(want - _yaw, -PI, PI)
			# Vehicles steer harder the faster they go (but can creep round tight corners)
			var steer := turn_rate * delta * clampf(speed / 3.0, 0.35, 1.0)
			_yaw += clampf(diff, -steer, steer)
			target_speed = max_speed * (1.0 - minf(absf(diff) / 1.2, 0.75))
			# Pointing well off the next waypoint: slow enough to turn onto it (too fast and it
			# circles round it for ever), and stop to pivot if it's behind
			target_speed = minf(target_speed, turn_limit(absf(diff), to.length(), turn_rate))
			# Slow down in time for the next corners and for the stop at the end
			target_speed = minf(target_speed, corner_limit(_pos, _path, _path_i, max_speed, brake))
	speed = move_toward(speed, target_speed, (accel if target_speed > speed else brake) * delta)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if speed > 0.01:
		var p := _pos + fwd * speed * delta
		p.y = _ground_y(p)
		_pos = p
		_burn(speed * delta)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
	if speed > runover_speed:
		_run_over(fwd)
	_aim_turret(delta)


const LATERAL_GRIP := 4.0         # m/s² of sideways acceleration it will take round a corner
const CORNER_CUT := 6.0           # metres before a corner it starts turning


static func turn_limit(off: float, dist: float, rate: float) -> float:
	## Fastest it can go and still turn onto a waypoint `dist` away that's `off` radians off
	## its nose (0 = stop and pivot first)
	if off > 1.3:
		return 0.0
	if off < 0.2:
		return INF
	var radius := dist * 0.5 / sin(off)          # the turn that just reaches it
	if radius < 3.2 / rate:                      # tighter than it can steer at a crawl: pivot
		return 0.0
	return maxf(1.5, rate * radius)


static func corner_speed(turn: float, top: float) -> float:
	## How fast it can take a corner that turns by `turn` radians
	if turn < 0.08:
		return top
	var radius := CORNER_CUT / tan(minf(turn, 2.8) * 0.5)
	return minf(top, sqrt(LATERAL_GRIP * radius))


static func corner_limit(from: Vector3, path: PackedVector3Array, i: int, top: float, decel: float) -> float:
	## The speed it can be doing now and still brake in time for the next few corners and
	## the end of the path
	var limit := top
	var dist := Vector2(path[i].x - from.x, path[i].z - from.z).length()
	var prev := from
	for k in range(i, mini(i + 5, path.size())):
		if k > i:
			dist += Vector2(path[k].x - path[k - 1].x, path[k].z - path[k - 1].z).length()
		var v_here := 1.5 if k == path.size() - 1 else top
		if k < path.size() - 1:
			var a := Vector2(path[k].x - prev.x, path[k].z - prev.z)
			var b := Vector2(path[k + 1].x - path[k].x, path[k + 1].z - path[k].z)
			if a.length() > 0.1 and b.length() > 0.1:
				v_here = corner_speed(absf(a.angle_to(b)), top)
		limit = minf(limit, sqrt(v_here * v_here + 2.0 * decel * maxf(0.0, dist - 1.0)))
		prev = path[k]
		if limit < 2.0:
			break
	return maxf(limit, 1.5)


func _burn(metres: float) -> void:
	fuel = maxf(0.0, fuel - metres / fuel_range * fuel_max)
	if not _fuel_warned and fuel < fuel_max * 0.2:
		_fuel_warned = true
		message.emit("%s is low on fuel (%d gal)" % [display_name, ceili(fuel)])


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p.y if hit.is_empty() else hit.position.y


func _run_over(fwd: Vector3) -> void:
	var half_w := body_size.x * 0.5 + 0.25
	var nose := body_size.z * 0.5
	var front := global_position + fwd * (nose + 0.2)
	for s in enemy.alive.duplicate():
		if not is_instance_valid(s) or not s.alive:
			continue
		if s.global_position.distance_squared_to(front) > 9.0:
			continue
		var local := to_local(s.global_position)
		if absf(local.x) < half_w and local.z < -nose + 0.6 and local.z > -nose - 1.0 and local.y < 2.2:
			s.take_hit(999.0, fwd, crew.squad)


func _aim_turret(delta: float) -> void:
	var gunner := crew.occupant(gunner_seat)
	if gunner == null or gunner.target_time <= 0.0 or model.turret == null:
		return
	var local := to_local(gunner.last_target)
	var want := atan2(-local.x, -local.z)
	model.turret.rotation.y = lerp_angle(model.turret.rotation.y, want, 1.0 - exp(-10.0 * delta))


static func _make_ring(radius: float, color: Color) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = radius - 0.15
	m.outer_radius = radius
	m.rings = 24
	m.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position.y = 0.06
	mi.material_override = Level.make_material(color, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi
