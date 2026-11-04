class_name RedFob
extends RefCounted
## The Red Army's base in Fair Park, on the east edge of the map: where its reinforcements
## come in, and the one objective you have to take. Concrete walls with a catwalk (Red
## riflemen on it face the city), a guard tower in each corner with a machine gunner on top,
## and steel gates that only open for the Red Army, so you have to breach the walls:
## M777 shells and A-10 runs wear walls and gates down, and an engineer squad can blow a hole
## with a breach charge (right-click a wall or gate with engineers selected).
## Inside: barracks, a vehicle shed, rifle squads, tanks and anti-air.
##
## It grows: every few minutes (see RedArmy) a new walled section goes up against it (STEPS,
## in order), with two more towers. The new walls rise first; then the walls between the old
## base and the new section come down. A section waits while any of your units stand there.

# Laid out for the generated city's east edge (x = 900); anchor() moves it to this map's east edge
const BASE_RECT := Rect2(772, 76, 88, 80)    # the base you see at the start: x 772-860, z 76-156
const BASE_STEPS := [                        # the sections it grows by, in order
	Rect2(732, 76, 40, 80),              # west, toward the city
	Rect2(772, 156, 88, 40),             # south
	Rect2(732, 156, 40, 40),             # south-west corner
	Rect2(692, 76, 40, 120),             # further west
]
const BASE_ZONE := Rect2(692, 76, 168, 120)  # everything it can grow into (kept clear of buildings)
static var RECT := BASE_RECT
static var STEPS: Array = BASE_STEPS.duplicate()
static var ZONE := BASE_ZONE


static func anchor(half_x: float, offset := Vector2.ZERO) -> void:
	## Put the Red FOB against the east edge of a map half_x metres from centre to edge
	## (offset: moved west / north-south from there, to keep it off buildings and water)
	var shift := Vector2(half_x - 900.0, 0.0) + offset
	RECT = Rect2(BASE_RECT.position + shift, BASE_RECT.size)
	ZONE = Rect2(BASE_ZONE.position + shift, BASE_ZONE.size)
	STEPS = []
	for r in BASE_STEPS:
		STEPS.append(Rect2((r as Rect2).position + shift, (r as Rect2).size))


const TOWER_INSET := 10.0
const TOWER_TOP := 6.2
const TOWER_GUNNER := {"range": 48.0, "interval": 0.22, "damage": 6.0}
const RISE_TIME := 10.0                  # seconds for a new section's walls to go up

var rects: Array[Rect2] = [RECT]
var pieces: Array = []                    # every Structure
var towers: Array = []                    # the tower Structures
var gates: Array = []
var steps_done := 0
var _rising: Array = []                   # pieces of the section going up
var _to_remove: Array = []                # walls that come down once it's up


static func center() -> Vector3:
	var c := RECT.get_center()
	return Vector3(c.x, 0, c.y)


static func contains(p: Vector3) -> bool:
	## Inside the original base (the objective)
	return RECT.grow(-0.5).has_point(Vector2(p.x, p.z))


func inside(p: Vector3) -> bool:
	## Inside any part of the base, as it stands now
	for r in rects:
		if r.grow(-0.5).has_point(Vector2(p.x, p.z)):
			return true
	return false


func sally_point() -> Vector3:
	## Just outside the westernmost gate: where counterattacks come out
	var best: Structure = null
	for g in gates:
		if is_instance_valid(g) and (best == null or g.position.x < best.position.x):
			best = g
	if best == null:
		return Vector3(RECT.position.x - 12.0, 0, RECT.get_center().y)
	return best.position + Vector3(-12.0, 0, 0)


func build(level: Level) -> void:
	## The starting base: walls (already standing), towers, buildings
	for st in _walls_for(RECT):
		_add(level, st)
	_towers_for(level, RECT, 4)
	var mid := center()
	_add(level, Structure.make("red_barracks", mid + Vector3(-22, 0, 22), 0.0, "red"))
	_add(level, Structure.make("red_barracks", mid + Vector3(22, 0, 22), 0.0, "red"))
	_add(level, Structure.make("red_shed", mid + Vector3(0, 0, -26), PI, "red"))


func _walls_for(r: Rect2) -> Array:
	## Wall pieces for a section: gates only on the west and east sides (north and south are
	## solid), and nothing where the section meets the base that's already there
	var helper := Fob.new()
	helper.rects = rects.duplicate()
	if r in helper.rects:
		helper.rects.erase(r)
	var lay: Array = helper.wall_layout(r)
	helper.free()
	var out: Array = []
	for e in lay:
		var k: String = e[0]
		var at: Vector3 = e[1]
		var yaw: float = e[2]
		var seg: float = e[3]
		var west_or_east := absf(absf(yaw) - PI * 0.5) < 0.01
		if k == "gate" and not west_or_east:
			var along := Basis(Vector3.UP, yaw) * Vector3.RIGHT
			for d in [-1.0, 1.0]:
				out.append(Structure.make("red_wall", at + along * d * Structure.WALL_LEN * 0.5, yaw, "red"))
			continue
		out.append(Structure.make("red_" + k, at, yaw, "red", seg))
	return out


func _towers_for(level: Level, r: Rect2, n: int, built := true) -> Array:
	## A tower in the n corners of the section furthest from the original base
	var corners := [Vector3(r.position.x + TOWER_INSET, 0, r.position.y + TOWER_INSET), Vector3(r.end.x - TOWER_INSET, 0, r.position.y + TOWER_INSET),
			Vector3(r.position.x + TOWER_INSET, 0, r.end.y - TOWER_INSET), Vector3(r.end.x - TOWER_INSET, 0, r.end.y - TOWER_INSET)]
	var mid := center()
	corners.sort_custom(func(a, b): return a.distance_to(mid) > b.distance_to(mid))
	var out: Array = []
	for i in mini(n, corners.size()):
		var t := Structure.make("red_tower", corners[i], 0.0, "red")
		out.append(t)
		towers.append(t)
		_add(level, t, built)
	return out


func _add(level: Level, st: Structure, built := true) -> Structure:
	if built:
		st.state = "built"
		st.work = st.work_needed
	else:
		st.state = "building"
		st.work = 0.0
	level.add_structure(st)
	pieces.append(st)
	if st.kind == "red_gate":
		gates.append(st)
	return st


# --- Growing --------------------------------------------------------------------------

func next_step() -> Rect2:
	return STEPS[steps_done] if steps_done < STEPS.size() else Rect2()


func can_grow(level: Level, blockers: Array) -> String:
	## "" if the next section can go up now, otherwise why not
	if steps_done >= STEPS.size():
		return "full"
	if not _rising.is_empty():
		return "rising"
	var r: Rect2 = STEPS[steps_done].grow(4.0)
	for p in blockers:
		if r.has_point(Vector2(p.x, p.z)):
			return "occupied"
	for st in level.structures:
		if is_instance_valid(st) and st.side == "blue" and st.state != "removed":
			for c in st.footprint_world():
				if r.has_point(Vector2(c.x, c.z)):
					return "occupied"
	return ""


func grow(level: Level) -> Array:
	## Start the next section: its walls and two towers rise over RISE_TIME. Returns the new
	## towers (the army puts gunners on them once they're up).
	var r: Rect2 = STEPS[steps_done]
	steps_done += 1
	# Walls of the old base that will end up inside
	_to_remove.clear()
	for st in pieces:
		if not is_instance_valid(st) or not (st.kind in ["red_wall", "red_ramp", "red_gate"]):
			continue
		var inward := Basis(Vector3.UP, st.yaw) * Vector3.BACK
		var probe: Vector3 = st.position - inward * (Structure.WALL_T * 0.5 + 1.0)
		if r.grow(-0.1).has_point(Vector2(probe.x, probe.z)):
			_to_remove.append(st)
	var walls := _walls_for(r)
	rects.append(r)
	for st in walls:
		_rising.append(_add(level, st, false))
	var new_towers := _towers_for(level, r, 2, false)
	_rising.append_array(new_towers)
	return new_towers


func tick(delta: float) -> bool:
	## Raise the walls going up. Returns true on the frame the section is finished.
	if _rising.is_empty():
		return false
	var done := true
	for st in _rising:
		if not is_instance_valid(st) or st.state != "building":
			continue
		st.add_work(st.work_needed * delta / RISE_TIME)
		if st.state == "building":
			done = false
	if not done:
		return false
	_rising.clear()
	for st in _to_remove:
		if is_instance_valid(st):
			pieces.erase(st)
			gates.erase(st)
			st.cancel()
	_to_remove.clear()
	return true


func catwalk_posts(n: int) -> Array:
	## Spots on the west catwalk (facing the city), spread along the wall
	var out: Array = []
	var x := RECT.position.x + Structure.WALL_T + Structure.DECK_W * 0.5
	for i in n:
		var z := RECT.position.y + 14.0 + (RECT.size.y - 28.0) * (float(i) / maxf(1.0, n - 1))
		if absf(z - RECT.get_center().y) < 6.0:
			z += 7.0 * signf(z - RECT.get_center().y + 0.01)
		out.append(Vector3(x, Structure.DECK_Y + 0.1, z))
	return out


func tower_tops(list: Array = []) -> Array:
	var out: Array = []
	for t in (list if not list.is_empty() else towers):
		if is_instance_valid(t) and t.is_built():
			out.append(t.position + Vector3.UP * (TOWER_TOP + 0.1))
	return out


func random_inside(rng: RandomNumberGenerator) -> Vector3:
	## A random spot in one of the base's sections (away from the walls)
	var r: Rect2 = rects[rng.randi() % rects.size()].grow(-8.0)
	return Vector3(rng.randf_range(r.position.x, r.end.x), 0, rng.randf_range(r.position.y, r.end.y))


func breached() -> bool:
	## Is there a way in? (a wall or gate on the outline is down)
	for st in pieces:
		if is_instance_valid(st) and st.state == "destroyed" and st.kind in ["red_wall", "red_ramp", "red_gate"]:
			return true
	return false
