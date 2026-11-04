class_name Fob
extends Node3D
## Your forward operating base: everything you plan, and your engineers build.
##
## Walls: drag out a rectangle (any size, in 4 m steps). It's planned as wall segments with a
## catwalk on the inside, a ramp up to the catwalk near one end of each side, and an 8 m gate in
## the middle of every side 16 m or longer. Engineers then build it one segment at a time,
## so a big base takes a long time. Drag a new rectangle that overlaps or touches the old
## one to extend the base: the walls between them come down.
## Buildings: barracks and maintenance shed go inside the walls; a runway goes anywhere open.
## - Barracks: squads (and vehicle crews) inside the walls get a replacement every 12 s
##   until they're back to full strength. A squad that's been wiped out is gone for good.
## - Maintenance shed: vehicles and helicopters inside the walls are repaired.
## - Runway: 2 parking slots for aircraft; A-10s land there to refuel and rearm.
## Engineers work on whatever is unfinished whenever you're not moving them yourself.
##
## Supplies: the FOB keeps a stock of AMMO (rounds: rifles, machine guns, the A-10's cannon),
## SHELLS (155 mm for the M777) and FUEL (gallons, for the A-10). Air-dropped pallets add to
## it once a PLS truck or a Chinook brings them inside the walls. From the stock:
## - soldiers inside the walls top their rounds back up to Soldier.CARRY
## - vehicles inside the walls refill their guns and their two ammo cans
## - an M777 inside (or right by) the walls refills its shells
## - an A-10 rearming on the runway takes A10_ROUNDS of ammo and A10_FUEL of fuel

signal message(text: String)
signal runway_built(r: Structure)

const GRID := Structure.WALL_LEN
const MIN_SIDE := 16.0
const MAX_SIDE := 160.0
const REFILL_INTERVAL := 12.0
const REPAIR_RATE := 4.0            # armor per second
const WORK_TICK := 0.25
const WORK_REACH := 2.6             # engineers this close to a piece are working on it
const RUNWAY_SLOT_OFFSET := 38.0
const CAN_ROUNDS := 840             # rounds of 5.56 in one ammo can (bandoliers in an M2A1 can)
const RESUPPLY_TICK := 1.0
const GUN_REACH := 30.0             # an M777 this close to the walls refills its shells
const START_STOCK := {"ammo": 8400, "shells": 24, "fuel": 6000}
const A10_ROUNDS := 1150            # one full load for the GAU-8
const A10_FUEL := 800               # gallons per refuel

static var current: Fob             # the one FOB (A-10s and pallets look it up)

var stock := START_STOCK.duplicate()
var _resupply_cd := RESUPPLY_TICK
var _label: Label3D

var game: Node                      # main.gd
var level: Level
var rects: Array[Rect2] = []        # the base outline(s)
var pieces: Array = []              # every Structure you've planned, in order
var work_speed := 1.0               # the self-test speeds building up
var _batch := 0                     # each wall rectangle or building you place is one job
var _work_cd := 0.0
var _refill_cd := REFILL_INTERVAL


# --- Queries ------------------------------------------------------------------------

func contains(p: Vector3) -> bool:
	for r in rects:
		if r.grow(-0.5).has_point(Vector2(p.x, p.z)):
			return true
	return false


func has_built(kind: String) -> bool:
	for s in pieces:
		if is_instance_valid(s) and s.kind == kind and s.is_built():
			return true
	return false


func count_built(kind: String) -> int:
	var n := 0
	for s in pieces:
		if is_instance_valid(s) and s.kind == kind and s.is_built():
			n += 1
	return n


func unfinished() -> Array:
	var out: Array = []
	for s in pieces:
		if is_instance_valid(s) and (s.state == "planned" or s.state == "building"):
			out.append(s)
	return out


func center() -> Vector3:
	if rects.is_empty():
		return Vector3.ZERO
	var c := rects[0].get_center()
	return Vector3(c.x, 0, c.y)


func runway_slots() -> Array:
	## {key, pos, dir, far} for both slots of every built runway
	var out: Array = []
	var n := 0
	for s in pieces:
		if not is_instance_valid(s) or s.kind != "runway" or not s.is_built():
			continue
		var along := Basis(Vector3.UP, s.yaw) * Vector3.RIGHT
		var half: float = s.size().x * 0.5
		out.append({"key": "rw%d_a" % n, "pos": s.position - along * RUNWAY_SLOT_OFFSET, "dir": along, "far": s.position + along * half})
		out.append({"key": "rw%d_b" % n, "pos": s.position + along * RUNWAY_SLOT_OFFSET, "dir": -along, "far": s.position - along * half})
		n += 1
	return out


# --- Planning walls -------------------------------------------------------------------

static func snap_rect(a: Vector3, b: Vector3) -> Rect2:
	var x0 := snappedf(minf(a.x, b.x), GRID)
	var z0 := snappedf(minf(a.z, b.z), GRID)
	var x1 := snappedf(maxf(a.x, b.x), GRID)
	var z1 := snappedf(maxf(a.z, b.z), GRID)
	x1 = clampf(x1, x0 + MIN_SIDE, x0 + MAX_SIDE)
	z1 = clampf(z1, z0 + MIN_SIDE, z0 + MAX_SIDE)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func wall_layout(r: Rect2) -> Array:
	## The segments a rectangle needs: [kind, position, yaw, length], skipping any that fall
	## inside the existing base (they'd be interior walls)
	var out: Array = []
	var sides := [
		[Vector3(r.position.x, 0, r.position.y), Vector3.RIGHT, r.size.x, 0.0],          # north, inward +Z
		[Vector3(r.end.x, 0, r.end.y), Vector3.LEFT, r.size.x, PI],                       # south, inward -Z
		[Vector3(r.position.x, 0, r.end.y), Vector3.FORWARD, r.size.y, PI * 0.5],         # west, inward +X
		[Vector3(r.end.x, 0, r.position.y), Vector3.BACK, r.size.y, -PI * 0.5],           # east, inward -X
	]
	for sd in sides:
		var start: Vector3 = sd[0]
		var dir: Vector3 = sd[1]
		var length: float = sd[2]
		var yaw: float = sd[3]
		var inward := Basis(Vector3.UP, yaw) * Vector3.BACK
		var n := int(round(length / GRID))
		var gate_at := -1
		if length >= 16.0:
			gate_at = maxi(1, n / 2 - 1)
		var ramp_at := 1 if n >= 4 else 0
		if ramp_at == gate_at or ramp_at == gate_at + 1:
			ramp_at = 0
		var i := 0
		while i < n:
			if i == gate_at:
				var gp := start + dir * (GRID * (i + 1)) + inward * Structure.WALL_T * 0.5
				if not _interior(gp, inward, rects):
					out.append(["gate", gp, yaw, Structure.GATE_LEN])
				i += 2
				continue
			var p := start + dir * (GRID * (i + 0.5)) + inward * Structure.WALL_T * 0.5
			if not _interior(p, inward, rects):
				out.append(["ramp" if i == ramp_at else "wall", p, yaw, GRID])
			i += 1
	return out


static func _interior(p: Vector3, inward: Vector3, outline: Array) -> bool:
	## A wall is only needed where the outside of it is outside the base. If the ground just
	## past its outer face is inside another rectangle of the base, it would be an inner wall.
	var outside := p - inward * (Structure.WALL_T * 0.5 + 1.0)
	for r in outline:
		if (r as Rect2).grow(-0.1).has_point(Vector2(outside.x, outside.z)):
			return true
	return false


func check_layout(layout: Array) -> Array:
	## Which planned pieces are blocked by buildings, cars, the river or other structures
	var bad: Array = []
	var space := get_world_3d().direct_space_state
	for item in layout:
		var probe := Structure.make(item[0], item[1], item[2], "blue", item[3])
		bad.append(not _clear(probe, space))
		probe.free()
	return bad


func _clear(probe: Structure, space: PhysicsDirectSpaceState3D) -> bool:
	var s := probe.size()
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(s.x - 0.4, 0.5), 1.8, maxf(s.z - 0.4, 0.5))
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, probe.yaw), probe.to_global_flat(probe.footprint_center_local()) + Vector3.UP * 1.25)
	q.collision_mask = 1
	# A watch tower may stand on your wall line: your own walls don't block it
	for h in space.intersect_shape(q, 8):
		var col = h.collider
		if probe.kind == "tower" and col is Structure and col.side == "blue" and col.kind in ["wall", "ramp", "gate"]:
			continue
		return false
	# Planned pieces aren't solid yet, so check those by footprint too
	var mine := _rect_of(probe)
	for p in pieces:
		if is_instance_valid(p) and p.state != "removed" and p.state != "destroyed" and _rect_of(p).grow(-0.3).intersects(mine.grow(-0.3)):
			if not (p.kind in ["wall", "ramp", "gate"] and probe.kind in ["wall", "ramp", "gate", "tower"]):
				return false
	return true


static func _rect_of(s: Structure) -> Rect2:
	var pts := s.footprint_world()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return Rect2(lo, hi - lo)


func plan_walls(r: Rect2) -> String:
	## Returns "" if planned, otherwise why not
	var layout := wall_layout(r)
	if layout.is_empty():
		return "That's already inside the base"
	var bad := check_layout(layout)
	if true in bad:
		return "Blocked: walls can't go through buildings, cars or the river"
	# Extending: walls of the old base that now have base on both sides come down
	_batch += 1
	for s in pieces.duplicate():
		if is_instance_valid(s) and s.kind in ["wall", "ramp", "gate"] and s.state != "removed":
			var inward := Basis(Vector3.UP, s.yaw) * Vector3.BACK
			if _interior(s.position, inward, [r]):
				pieces.erase(s)
				s.cancel()
	rects.append(r)
	for item in layout:
		_add_piece(Structure.make(item[0], item[1], item[2], "blue", item[3]))
	message.emit("FOB walls planned: %d pieces, %d x %d m. Engineers will build them one at a time" % [layout.size(), int(r.size.x), int(r.size.y)])
	return ""


func plan_building(kind: String, at: Vector3, yaw: float) -> String:
	var probe := Structure.make(kind, at, yaw)
	var why := building_blocked(probe)
	probe.free()
	if why != "":
		return why
	_batch += 1
	_add_piece(Structure.make(kind, at, yaw))
	message.emit("%s planned" % Structure.NAMES[kind])
	return ""


func building_blocked(probe: Structure) -> String:
	if probe.kind in ["barracks", "shed"]:
		var fr := _rect_of(probe)
		var inside := false
		var inset := Structure.WALL_T + Structure.DECK_W
		for r in rects:
			if r.grow(-inset).encloses(fr):
				inside = true
		if not inside:
			return "The %s has to go inside your FOB walls" % Structure.NAMES[probe.kind].to_lower()
	if not _clear(probe, get_world_3d().direct_space_state):
		return "Blocked: not enough clear ground there"
	return ""


func _add_piece(s: Structure) -> void:
	s.set_meta("batch", _batch)
	pieces.append(s)
	add_child(s)
	level.add_structure(s)
	s.state_changed.connect(_on_piece_changed)


func _on_piece_changed(s: Structure) -> void:
	if s.state == "built":
		_clear_footprint(s)
		if s.kind == "runway":
			runway_built.emit(s)
			message.emit("Runway built: 2 aircraft slots")
		elif s.kind in ["barracks", "shed"]:
			message.emit("%s built" % s.display_name())
	elif s.state == "destroyed":
		message.emit("Your %s was destroyed" % s.display_name().to_lower())


func _clear_footprint(s: Structure) -> void:
	## Anyone standing where a piece just went solid steps out to the inside
	for sq in game.squads:
		for sd in sq.active_soldiers():
			if s.flat_distance(sd.global_position) < 0.4:
				sd.global_position = s.work_spot(0, 1) + Vector3.UP * 0.2


# --- Work, refills, repairs -------------------------------------------------------------

func _enter_tree() -> void:
	current = self


func add_stock(kind: String, amount: int) -> void:
	stock[kind] = int(stock.get(kind, 0)) + amount


func take_stock(kind: String, amount: int) -> int:
	## Take up to `amount`; returns how much there was
	var n := mini(amount, int(stock.get(kind, 0)))
	stock[kind] = int(stock.get(kind, 0)) - n
	return n


static func stock_text(st: Dictionary) -> String:
	return "AMMO %s  ·  SHELLS %d  ·  FUEL %s gal" % [_thousands(st.ammo), st.shells, _thousands(st.fuel)]


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func near_walls(p: Vector3, margin: float) -> bool:
	for r in rects:
		if r.grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _resupply() -> void:
	## Ammo for soldiers riding in a troop carrier (from its cans), and for anything inside
	## the walls (from the stock)
	for t in game.transports:
		if t.destroyed or t.can_rounds <= 0:
			continue
		for sd in t.passengers:
			if is_instance_valid(sd) and not sd.dead:
				t.can_rounds -= sd.top_up(t.can_rounds)
	if rects.is_empty():
		return
	for sq in game.squads:
		for sd in sq.active_soldiers():
			if sd.rounds < Soldier.CARRY and contains(sd.global_position) and stock.ammo > 0:
				stock.ammo -= sd.top_up(stock.ammo)
	for v in game.vehicles:
		if v is A10 or v.destroyed or not v.visible or not contains(v.global_position):
			continue
		for k in ["gun_rounds", "can_rounds"]:
			var room: int = int(v.get(k + "_max")) - int(v.get(k))
			if room > 0 and stock.ammo > 0:
				v.set(k, int(v.get(k)) + take_stock("ammo", room))
		# Fuel: parked (or landed) inside the walls fills the tank, and a fuel truck's tanker too
		if v.has_method("needs_fuel") and v.needs_fuel() and v.is_parked() and stock.fuel > 0:
			v.add_fuel(take_stock("fuel", ceili(v.fuel_max - v.fuel)))
		if v.has_method("rearm_missiles") and v.is_parked():
			v.rearm_missiles()
		if v is FuelTruck and v.is_parked() and v.cargo_fuel < FuelTruck.CARGO and stock.fuel > 0:
			v.cargo_fuel += take_stock("fuel", FuelTruck.CARGO - int(v.cargo_fuel))
	for g in game.guns:
		if g.slung_by == null and g.shells < Artillery.MAX_SHELLS and stock.shells > 0 and near_walls(g.global_position, GUN_REACH):
			g.shells += take_stock("shells", Artillery.MAX_SHELLS - g.shells)


func _update_label() -> void:
	if rects.is_empty():
		if _label != null:
			_label.visible = false
		return
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0011
		_label.font_size = 26
		_label.outline_size = 8
		_label.modulate = Color(1.0, 0.86, 0.45)
		add_child(_label)
	_label.visible = true
	_label.position = center() + Vector3.UP * 9.0
	_label.text = "FOB\n" + stock_text(stock)


func _physics_process(delta: float) -> void:
	_resupply_cd -= delta
	if _resupply_cd <= 0.0:
		_resupply_cd = RESUPPLY_TICK
		_resupply()
		_update_label()
	_work_cd -= delta
	if _work_cd <= 0.0:
		_work_cd = WORK_TICK
		_engineers_work()
	_refill_cd -= delta
	if _refill_cd <= 0.0:
		_refill_cd = REFILL_INTERVAL
		if has_built("barracks"):
			_refill()
	if has_built("shed"):
		_repair(delta)


func _engineers_work() -> void:
	var todo := unfinished()
	for sq in game.squads:
		if sq.kind != "engineer" or sq.get_meta("breaching", false):
			continue
		var crew: Array = []
		for sd in sq.active_soldiers():
			if not sd.manual and sd.board_target == null and not sd.boarded:
				crew.append(sd)
		if crew.is_empty():
			continue
		var target: Structure = sq.get_meta("build_target") if sq.has_meta("build_target") else null
		# A job you told them to do first (right-click it, or shift-click when placing): that
		# piece, then the rest of the same job; after that, back to the jobs in order
		var pb: int = sq.get_meta("priority_batch", -1)
		if pb >= 0:
			var first: Structure = sq.get_meta("priority", null)
			if first != null and is_instance_valid(first) and first in todo:
				target = first
			else:
				sq.set_meta("priority", null)
				target = _nearest(todo, crew[0].global_position, pb)
				if target == null:
					sq.set_meta("priority_batch", -1)
					message.emit("%s: done with that, back to the earlier work" % sq.squad_name)
		if target == null or not is_instance_valid(target) or not (target in todo):
			target = _nearest(todo, crew[0].global_position)
		sq.set_meta("build_target", target)
		if target == null:
			continue
		var n := crew.size()
		var nav := level.get_navigation_map()
		for i in n:
			var sd: Soldier = crew[i]
			var d: float = target.flat_distance(sd.global_position)
			# Close enough and standing still: working (a bit further counts once he's arrived,
			# since his spot may have been nudged by walls already standing)
			if not sd._has_order and (d < WORK_REACH or (d < 8.0 and sd.get_meta("work_target", null) == target)):
				if target.add_work(WORK_TICK * work_speed):
					break
				continue
			var spot := _free_work_spot(target, i, n)
			var last: Vector3 = sd.get_meta("work_spot") if sd.has_meta("work_spot") else Vector3.INF
			if last.distance_to(spot) > 0.5 or not sd._has_order:
				sd.set_meta("work_spot", spot)
				sd.set_meta("work_target", target)
				sd.task_move(NavigationServer3D.map_get_closest_point(nav, spot), target.position - spot)


func _free_work_spot(target: Structure, i: int, n: int) -> Vector3:
	## The piece's work spot, or the nearest open ground around it if another piece is in the
	## way (at a corner one wall's spot can fall under the next wall's catwalk)
	var raw := target.work_spot(i, n)
	for r in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		var steps := 1 if r == 0.0 else 8
		for k in steps:
			var a := TAU * k / steps
			var c: Vector3 = raw + Vector3(cos(a), 0, sin(a)) * r
			if target.flat_distance(c) < 0.6:
				continue
			var blocked := false
			for p in pieces:
				if p != target and is_instance_valid(p) and p.state != "removed" and p.state != "destroyed" and p.flat_distance(c) < 0.7:
					blocked = true
					break
			if not blocked:
				return c
	return raw


func prioritize(target: Structure, squads: Array = []) -> int:
	## Engineers drop what they're doing and build this job first, then go back to the rest.
	## squads: the engineer squads to send (empty: all of them). Returns how many squads.
	var n := 0
	for sq in (squads if not squads.is_empty() else game.squads):
		if sq.kind != "engineer" or sq.soldiers.is_empty():
			continue
		sq.set_meta("priority", target)
		sq.set_meta("priority_batch", target.get_meta("batch", 0))
		sq.set_meta("breaching", false)
		for sd in sq.active_soldiers():
			sd.manual = false
		n += 1
	return n


func _nearest(todo: Array, from: Vector3, batch := -1) -> Structure:
	## Jobs in the order you placed them (a wall rectangle, then a building...); within a
	## wall job, the nearest unfinished segment, so they work their way round.
	## batch >= 0: only that job.
	var first := INF
	for s in todo:
		first = minf(first, s.get_meta("batch", 0))
	if batch >= 0:
		first = batch
	var best: Structure = null
	var best_d := INF
	for s in todo:
		if s.get_meta("batch", 0) != first:
			continue
		var d: float = s.flat_distance(from)
		if d < best_d:
			best_d = d
			best = s
	return best


func _refill() -> void:
	var door := Vector3.ZERO
	for s in pieces:
		if is_instance_valid(s) and s.kind == "barracks" and s.is_built():
			door = s.to_global_flat(Vector3(0, 0, s.size().z * 0.5 + 1.5))
			break
	for sq in game.squads:
		if sq.soldiers.is_empty() or sq.soldiers.size() >= sq.max_members:
			continue
		var home := false
		for sd in sq.active_soldiers():
			if contains(sd.global_position):
				home = true
				break
		if not home:
			continue
		var lead: Soldier = sq.active_soldiers()[0]
		var s: Soldier = game.add_recruit(sq, level.ground_spot(door, 8.0) + Vector3.UP * 0.1)
		if s != null:
			s.order_move(NavigationServer3D.map_get_closest_point(level.get_navigation_map(), lead.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))))
			message.emit("%s: a replacement from the barracks (%d/%d)" % [sq.squad_name, sq.soldiers.size(), sq.max_members])
	for v in game.vehicles:
		if v.destroyed or not v.visible or v is A10:
			continue
		if contains(v.global_position) and v.crew.count() > 0 and v.crew.count() < v.crew.seats.size():
			if v.crew.add_member():
				message.emit("%s: a replacement crewman (%d/%d)" % [v.display_name, v.crew.count(), v.crew.seats.size()])


func _repair(delta: float) -> void:
	for v in game.vehicles:
		if v.destroyed or not v.visible:
			continue
		var here: bool = contains(v.global_position) and (not (v is Helicopter) or v.is_landed())
		if v is A10:
			here = v.state == "parked"
		if here and v.hp < v.max_hp:
			v.hp = minf(v.max_hp, v.hp + REPAIR_RATE * delta * (v.max_hp / 100.0))
