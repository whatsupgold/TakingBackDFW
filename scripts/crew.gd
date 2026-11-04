class_name Crew
extends RefCounted
## The crew of a vehicle or gun: real soldiers sitting in fixed seats.
## Seats are listed most important first. When a crewman dies, everyone in a lower seat
## moves up one, so the key jobs (driver, pilot, gunner) stay filled as long as anyone lives.
##
## Seat fields: role (String), pos (Vector3, local to the vehicle), yaw (radians),
## visible (bool, or "landed": only while on the ground), exposed ("always", "landed" or "never": can Red riflemen shoot him),
## fires (bool), weapon (Dictionary: range, interval, damage, accuracy, mag, reload).

signal changed

var squad: Squad
var seats: Array = []
var parent: Node3D
var enemy: RedArmy
var _order: Array[Soldier] = []
var _landed := true
var stowed := false        # vehicle is inside a Chinook: nobody can shoot or be hit


func _init(crew_name: String, color: Color, seat_list: Array) -> void:
	squad = Squad.new(crew_name, color)
	squad.progression = false
	seats = seat_list
	squad.soldier_removed.connect(_on_removed)


func spawn(p: Node3D, h: RedArmy) -> void:
	parent = p
	enemy = h
	for i in seats.size():
		var s := Soldier.new()
		s.squad = squad
		s.enemy = enemy
		s.mounted = true
		parent.add_child(s)
		squad.soldiers.append(s)
		_order.append(s)
	assign()


func add_member() -> bool:
	## A replacement crewman (from the barracks). Returns false if every seat is filled.
	if _order.size() >= seats.size() or parent == null:
		return false
	var s := Soldier.new()
	s.squad = squad
	s.enemy = enemy
	s.mounted = true
	parent.add_child(s)
	squad.soldiers.append(s)
	_order.append(s)
	assign()
	return true


func count() -> int:
	return _order.size()


func occupant(i: int) -> Soldier:
	return _order[i] if i >= 0 and i < _order.size() else null


func has_seat(i: int) -> bool:
	return i < _order.size()


func role(i: int) -> String:
	return seats[i].get("role", "")


func set_landed(value: bool) -> void:
	if _landed == value:
		return
	_landed = value
	assign()


func assign() -> void:
	for i in _order.size():
		var s := _order[i]
		var seat: Dictionary = seats[i]
		s.position = seat.get("pos", Vector3.ZERO)
		s.rotation = Vector3(0.0, seat.get("yaw", 0.0), 0.0)
		var vis = seat.get("visible", true)
		s.visible = _landed if vis is String and vis == "landed" else bool(vis)
		var exposure: String = seat.get("exposed", "always")
		s.set_exposed(not stowed and (exposure == "always" or (exposure == "landed" and _landed)))
		s.can_fire = seat.get("fires", false) and not stowed
		var w: Dictionary = seat.get("weapon", {})
		s.weapon_range = w.get("range", Soldier.RANGE)
		s.fire_interval = w.get("interval", Soldier.FIRE_INTERVAL)
		s.damage_mult = w.get("damage", 1.0)
		s.accuracy_bonus = w.get("accuracy", 0.0)
		s.mag_override = w.get("mag", 0)
		# A mounted gun fires the vehicle's own rounds (gun_rounds), not the crewman's
		var mounted_gun: bool = seat.get("fires", false) and not w.is_empty() and parent != null and parent.get("gun_rounds") != null
		s.gun_source = parent if mounted_gun else null
		s.reload_time = w.get("reload", Soldier.RELOAD_TIME)
		s.set_carry(false)
		s.anim_moving = false
	changed.emit()


func _on_removed(s: Soldier) -> void:
	_order.erase(s)
	assign()
