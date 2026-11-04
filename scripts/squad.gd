class_name Squad
extends RefCounted
## A squad of up to 4 soldiers (the Little Bird carries 4 on its benches). Levels belong to the squad, not to its soldiers.
## First level-up at 20 kills, each later one needs 10 more (20, 30, 40 ...).
## Each level-up raises one random skill that isn't maxed yet; every skill caps at 5.

signal leveled_up(squad: Squad, skill: String)
signal wiped_out(squad: Squad)
signal soldier_removed(soldier: Soldier)

const MAX_MEMBERS := 4
const SKILL_CAP := 5
const FIRST_LEVEL_KILLS := 20
const LEVEL_KILL_STEP := 10
const SKILLS: Array[String] = ["accuracy", "ammo", "weapons"]

var squad_name: String
var color: Color
var soldiers: Array[Soldier] = []
var selected := false
var kills := 0
var kills_into_level := 0
var next_level_at := FIRST_LEVEL_KILLS
var levels := {"accuracy": 0, "ammo": 0, "weapons": 0}
var progression := true        # vehicle crews count kills but don't level up
var kind := "rifle"            # rifle, engineer (builds the FOB), gun_crew (crews an M777), pilot
var max_members := MAX_MEMBERS


static func make(n: String, c: Color, k := "rifle") -> Squad:
	var sq := Squad.new(n, c)
	sq.kind = k
	sq.max_members = {"rifle": 4, "engineer": 4, "gun_crew": 4, "pilot": 1}.get(k, 4)
	return sq


func kind_label() -> String:
	return {"rifle": "SQUAD", "engineer": "ENGINEERS", "gun_crew": "GUN CREW", "pilot": "PILOT"}.get(kind, "SQUAD")


func _init(n: String, c: Color) -> void:
	squad_name = n
	color = c


# --- Stats driven by squad level ------------------------------------------

func accuracy() -> float:
	return 0.45 + 0.09 * levels["accuracy"]        # 45% -> 90%


func mag_size() -> int:
	return 24 + 8 * levels["ammo"]                  # 24 -> 64 rounds


func damage() -> float:
	return 1.0 + 0.35 * levels["weapons"]           # 1.0 -> 2.75 per hit


func total_level() -> int:
	return levels["accuracy"] + levels["ammo"] + levels["weapons"]


func is_maxed() -> bool:
	return total_level() >= SKILL_CAP * SKILLS.size()


# --- Progression ------------------------------------------------------------

func add_kill() -> void:
	kills += 1
	if not progression or is_maxed():
		return
	kills_into_level += 1
	if kills_into_level < next_level_at:
		return
	kills_into_level = 0
	next_level_at += LEVEL_KILL_STEP
	var open_skills: Array[String] = []
	for s in SKILLS:
		if levels[s] < SKILL_CAP:
			open_skills.append(s)
	var skill: String = open_skills.pick_random()
	levels[skill] += 1
	for s in soldiers:
		s.on_squad_upgrade()
	leveled_up.emit(self, skill)


# --- Orders -----------------------------------------------------------------

func set_selected(value: bool) -> void:
	selected = value
	for s in soldiers:
		s.set_selected(value)


func active_soldiers() -> Array[Soldier]:
	## Soldiers on the ground (not riding in a Huey)
	var out: Array[Soldier] = []
	for s in soldiers:
		if not s.boarded:
			out.append(s)
	return out


func order_move(point: Vector3, nav_map: RID) -> void:
	var active := active_soldiers()
	for i in active.size():
		var col := (i % 3) - 1
		var row := floori(i / 3.0)
		var offset := Vector3(col * 1.3, 0.0, row * 1.3 - 0.65)
		var p := NavigationServer3D.map_get_closest_point(nav_map, point + offset)
		active[i].order_move(p)


func stop() -> void:
	for s in soldiers:
		s.stop()


func remove_soldier(s: Soldier) -> void:
	soldiers.erase(s)
	soldier_removed.emit(s)
	if soldiers.is_empty():
		wiped_out.emit(self)
