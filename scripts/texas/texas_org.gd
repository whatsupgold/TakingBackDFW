class_name TexasOrg
extends RefCounted
## Your forces' organisation: brigades, their battalions, and the battalions' companies, with
## every ground unit and aircraft you have in a company. It's for finding and picking units (the
## dock at the bottom of the screen); every unit is still commanded on its own. Ships aren't in
## it: they're the fleet. Red's organisation is never shown.

const COMPANY_NAMES := ["Able", "Baker", "Charlie", "Dog", "Easy", "Fox", "George", "How", "Item", "King",
	"Love", "Mike", "Nan", "Oboe", "Peter", "Queen", "Roger", "Sugar", "Tare", "Uncle", "Victor",
	"William", "X-ray", "Yoke", "Zebra"]
enum Level {ROOT, BRIGADE, BATTALION, COMPANY}
## How many units a company takes before deliveries start a new one
const FULL := {"ground": 12, "mech": 14, "air": 8}

var sim: TexasSim
var nodes := {}                        # id -> {"level", "parent", "num", "name"}
var unit_of := {}                      # unit -> company id
var _next := 1


func _init(s: TexasSim) -> void:
	sim = s
	nodes[0] = {"level": Level.ROOT, "parent": -1, "num": 0, "name": "All forces"}


# --- What's in it -------------------------------------------------------------------------------

static func group_of_type(t: int) -> String:
	## Which tab a kind of unit shows under: ground (infantry), mech (vehicles), air, navy
	var mv: int = TexasUnits.move[t]
	if mv == TexasUnits.Move.SEA or mv == TexasUnits.Move.HOVER:
		return "navy"
	if mv == TexasUnits.Move.AIR:
		return "air"
	return "ground" if TexasUnits.cat[t] == TexasUnits.Cat.INFANTRY else "mech"


func group_of(i: int) -> String:
	return group_of_type(sim.utype[i])


func children(id: int) -> Array:
	var out: Array = []
	for k in nodes:
		if nodes[k].parent == id:
			out.append(k)
	out.sort_custom(func(a, b): return nodes[a].num < nodes[b].num)
	return out


func units_in(id: int, group := "all") -> Array:
	## Your living units in this part of the organisation (everything under it), in order
	var out: Array = []
	for i in unit_of:
		if sim.alive[i] == 0:
			continue
		if group != "all" and group_of(i) != group:
			continue
		if id == 0 or _under(unit_of[i], id):
			out.append(i)
	out.sort_custom(func(a, b): return a < b if sim.utype[a] == sim.utype[b] else sim.utype[a] < sim.utype[b])
	return out


func _under(node: int, id: int) -> bool:
	var n := node
	while n >= 0:
		if n == id:
			return true
		n = nodes[n].parent if nodes.has(n) else -1
	return false


func path(id: int) -> Array:
	## From the top down to this one: [0, brigade, battalion, company]
	var out: Array = []
	var n := id
	while n >= 0 and nodes.has(n):
		out.push_front(n)
		n = nodes[n].parent
	return out


func name_of(id: int) -> String:
	return nodes[id].name if nodes.has(id) else "?"


func short_name(id: int) -> String:
	var nd: Dictionary = nodes[id]
	match nd.level:
		Level.BRIGADE:
			return "%s Bde" % _ordinal(nd.num)
		Level.BATTALION:
			return "%s Bn" % _ordinal(nd.num)
		Level.COMPANY:
			return "%s Co" % COMPANY_NAMES[(nd.num - 1) % COMPANY_NAMES.size()]
	return nd.name


func full_name(id: int) -> String:
	## "1st Bde ▸ 3rd Bn ▸ Easy Co"
	var parts: Array = []
	for n in path(id):
		if n != 0:
			parts.append(short_name(n))
	return " ▸ ".join(parts)


func companies() -> Array:
	var out: Array = []
	for b in children(0):
		for bn in children(b):
			out.append_array(children(bn))
	return out


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


# --- Making and changing it ---------------------------------------------------------------------

func _add(level: int, parent: int) -> int:
	var num := 1
	for k in children(parent):
		num = maxi(num, nodes[k].num + 1)
	var id := _next
	_next += 1
	var nm: String
	match level:
		Level.BRIGADE:
			nm = "%s Brigade" % _ordinal(num)
		Level.BATTALION:
			nm = "%s Battalion" % _ordinal(num)
		_:
			nm = "%s Company" % COMPANY_NAMES[(num - 1) % COMPANY_NAMES.size()]
	nodes[id] = {"level": level, "parent": parent, "num": num, "name": nm}
	return id


func add_brigade() -> int:
	return _add(Level.BRIGADE, 0)


func add_battalion(brigade: int) -> int:
	return _add(Level.BATTALION, brigade)


func add_company(battalion: int) -> int:
	return _add(Level.COMPANY, battalion)


func assign(i: int, company: int) -> void:
	## Put a unit in a company (ships stay with the fleet)
	if group_of(i) == "navy" or not nodes.has(company) or nodes[company].level != Level.COMPANY:
		return
	unit_of[i] = company


func disband(id: int) -> bool:
	## Remove an empty company, battalion or brigade
	if id == 0 or not nodes.has(id) or not units_in(id).is_empty():
		return false
	for k in children(id):
		disband(k)
	for i in unit_of.keys():
		if unit_of[i] == id:
			unit_of.erase(i)
	nodes.erase(id)
	return true


func auto_company(t: int) -> int:
	## Where a new unit goes when you leave it to the organisation: a company of the same kind
	## with room, or a new company in the battalion that has most of that kind
	var g := group_of_type(t)
	if g == "navy":
		return -1
	var best := -1
	var best_n := 999
	for c in companies():
		var mine := units_in(c, g).size()
		var all := units_in(c).size()
		if mine * 2 >= all and all > 0 and all < FULL[g] and all < best_n:
			best = c
			best_n = all
	if best >= 0:
		return best
	# a new company: in the battalion with most of this kind, or a new battalion
	var bn := -1
	var most := 0
	for b in children(0):
		for x in children(b):
			var n := units_in(x, g).size()
			if n > most:
				most = n
				bn = x
	if bn < 0:
		var brig: int = children(0)[0] if not children(0).is_empty() else add_brigade()
		bn = add_battalion(brig)
	return add_company(bn)


func settle(i: int) -> void:
	## A new unit of yours with no company yet: put it in one
	if sim.side[i] == 0 and not unit_of.has(i) and group_of(i) != "navy":
		assign(i, auto_company(sim.utype[i]))


func to_dict() -> Dictionary:
	return {"nodes": nodes, "unit_of": unit_of, "next": _next}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	nodes = d.nodes
	unit_of = d.unit_of
	_next = d.next
