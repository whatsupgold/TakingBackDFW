class_name TexasFormation
extends RefCounted
## The fleet sails in formation. One ship guides (the carrier if it's there) and goes by the sea
## lanes at the pace of the slowest ship; the others keep station on it, each in its place
## relative to the guide's heading. Where the water is too narrow for a ship's place (a pass, a
## channel) it falls in astern and follows the guide's wake, and takes its place again once
## there's room. When the guide arrives, everyone goes to their place round it.

const LEAD_ORDER := ["carrier", "amphib", "cruiser", "destroyer0", "destroyer1"]
const GAP := 700.0                     # metres between ships in line
## (right, ahead) of each ship from the carrier, metres
const SHAPES := [
	{"name": "Cross", "key": "1",
		"tip": "Carrier in the middle, cruiser ahead, a destroyer either side, assault ship astern",
		"slots": {"cruiser": Vector2(0, 700), "destroyer0": Vector2(-650, 0), "carrier": Vector2.ZERO,
			"destroyer1": Vector2(650, 0), "amphib": Vector2(0, -700)}},
	{"name": "Screen", "key": "2",
		"tip": "Destroyers and cruiser in a line ahead, then the carrier, then the assault ship",
		"slots": {"destroyer0": Vector2(-600, 800), "cruiser": Vector2(0, 800), "destroyer1": Vector2(600, 800),
			"carrier": Vector2.ZERO, "amphib": Vector2(0, -700)}},
	{"name": "Column", "key": "3", "column": true,
		"tip": "Two destroyers leading, then the carrier, the assault ship and the cruiser astern (best in narrow water)",
		"slots": {"destroyer0": Vector2(-300, 700), "destroyer1": Vector2(300, 700), "carrier": Vector2.ZERO,
			"amphib": Vector2(0, -700), "cruiser": Vector2(0, -1400)}},
]
## Each ship's outline (length, beam), for the markers where they'll end up
const HULL := {"carrier": Vector2(333, 78), "amphib": Vector2(257, 32), "destroyer": Vector2(155, 20),
	"cruiser": Vector2(173, 17)}
const UPDATE := 2.0                    # game seconds between station-keeping corrections
const TRAIL_STEP := 120.0
const LEAD_PACE := 0.85                # the guide goes at this share of the slowest ship's speed
const LOOK_AHEAD := 2500.0             # the formation faces where the guide will be this far on
const COURSE_RATE := deg_to_rad(1.0)   # how fast the formation as a whole comes round (per second)

var sim: TexasSim
var camp                               # TexasCampaign
var shape := 0
var lead := -1
var dest := Vector2.ZERO
var members := {}                      # ship -> Vector2(right, ahead) from the guide
var trail := PackedVector2Array()      # where the guide has been (newest last)
var lead_cap := 0.0
var mode := {}                         # ship -> "station" / "wake" / "routed" (for the labs)
var _last_l := Vector2(INF, INF)
var _settled := {}                     # ships already in their places (others give way to them)
var forming := false                  # some ships are still getting to their places
var course := 0.0                     # the way the formation faces (smoothed; the guide wanders)
var _acc := 0.0
var _routed := {}                      # ship -> game time it was last sent by the sea lanes


func _init(s: TexasSim, c) -> void:
	sim = s
	camp = c


static func axes(h: float) -> Array:
	## [right, ahead] on the map for a heading
	return [Vector2(cos(h), -sin(h)), Vector2(-sin(h), -cos(h))]


func role_of(i: int) -> String:
	for r in camp.ships:
		if camp.ships[r] == i:
			return r
	return ""


func shape_name(k := -1) -> String:
	return SHAPES[shape if k < 0 else k].name


func _ships(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		if sim.alive[i] == 1 and sim.side[i] == 0 and sim.aboard[i] == -1 and TexasUnits.is_ship(sim.utype[i]):
			out.append(i)
	return out


func places(ids: Array, k := -1) -> Array:
	## [guide, {ship: Vector2(right, ahead) from the guide}] for these ships in formation k
	var sh: Dictionary = SHAPES[shape if k < 0 else k]
	var slots: Dictionary = sh.slots
	var by_role := {}
	var extra: Array = []
	for i in ids:
		var r := role_of(i)
		if slots.has(r):
			by_role[r] = i
		else:
			extra.append(i)
	var guide := -1
	for r in LEAD_ORDER:
		if by_role.has(r):
			guide = by_role[r]
			break
	if guide < 0:
		if extra.is_empty():
			return [-1, {}]
		guide = extra[0]
	var base: Vector2 = slots.get(role_of(guide), Vector2.ZERO)
	var off := {}
	for r in by_role:
		off[by_role[r]] = (slots[r] as Vector2) - base
	off[guide] = Vector2.ZERO
	# anything else (ships the plan doesn't know) goes astern
	var tail := 0.0
	for i in off:
		tail = minf(tail, (off[i] as Vector2).y)
	for i in extra:
		if i == guide:
			continue
		tail -= GAP
		off[i] = Vector2(0, tail)
	# In the column, ships missing from the line don't leave holes: close up
	if sh.get("column", false):
		for dir in [1.0, -1.0]:
			var line: Array = []
			for i in off:
				var o: Vector2 = off[i]
				if absf(o.x) < 1.0 and o.y * dir > 0.0:
					line.append(i)
			line.sort_custom(func(a, b): return absf(off[a].y) < absf(off[b].y))
			for n in line.size():
				off[line[n]] = Vector2(0, dir * GAP * (n + 1))
	return [guide, off]


func preview(ids: Array, to: Vector2) -> Array:
	## Where each ship will end up: [[position, heading, type id], ...]
	var s := _ships(ids)
	var pl := places(s)
	var guide: int = pl[0]
	if guide < 0:
		return []
	var from := Vector2(sim.x[guide], sim.z[guide])
	# facing along the last stretch of the guide's way there
	if camp.sea != null and from.distance_to(to) > 50.0:
		var lane: PackedVector2Array = camp.sea.route(from, to)
		if lane.size() >= 2:
			from = lane[lane.size() - 2]
		if not lane.is_empty():
			to = lane[lane.size() - 1]
	var d := to - from
	var h: float = sim.heading[guide] if d.length() < 50.0 else atan2(-d.x, -d.y)
	var ax := axes(h)
	var out: Array = []
	for i in pl[1]:
		var o: Vector2 = pl[1][i]
		out.append([to + ax[0] * o.x + ax[1] * o.y, h, TexasUnits.TYPES[sim.utype[i]].id])
	return out


func start(ids: Array, to: Vector2) -> bool:
	## Sail these ships to `to` in formation; false if the guide can't get there
	var s := _ships(ids)
	if s.size() < 2:
		return false
	release_all()
	var pl := places(s)
	var guide: int = pl[0]
	if not sim.order_move(guide, to):
		return false
	lead = guide
	dest = to
	members = (pl[1] as Dictionary).duplicate()
	members.erase(guide)
	var slowest := INF
	for i in s:
		slowest = minf(slowest, TexasUnits.speed[sim.utype[i]])
	lead_cap = slowest * LEAD_PACE
	sim.cap[lead] = lead_cap
	trail = PackedVector2Array([Vector2(sim.x[lead], sim.z[lead])])
	_routed.clear()
	mode.clear()
	course = _ahead_course()
	_last_l = Vector2(INF, INF)
	_acc = UPDATE
	update(0.0)
	return true


func reform(ids: Array) -> bool:
	## Take up the current formation where they are, round the guide
	var s := _ships(ids)
	if s.size() < 2:
		return false
	release_all()
	var pl := places(s)
	lead = pl[0]
	dest = Vector2(sim.x[lead], sim.z[lead])
	members = (pl[1] as Dictionary).duplicate()
	members.erase(lead)
	sim.stop(lead)
	course = sim.heading[lead]
	_arrive()
	return true


func set_shape(k: int, ids: Array) -> String:
	## Change the formation. A fleet under way changes places as it sails; selected ships (or,
	## with none selected, the whole fleet) take up the new formation where they are.
	## Returns what happened, for the message line.
	shape = clampi(k, 0, SHAPES.size() - 1)
	if active():
		var all: Array = [lead] + members.keys()
		var pl := places(all)
		if pl[0] == lead:
			members = (pl[1] as Dictionary).duplicate()
			members.erase(lead)
			return "The fleet takes up %s formation as it sails." % shape_name().to_lower()
		start(all, dest)
		return "The fleet takes up %s formation as it sails." % shape_name().to_lower()
	var s := _ships(ids)
	if s.size() < 2:
		s = _ships(camp.ships.values())
	if reform(s):
		return "The fleet forms up in %s formation." % shape_name().to_lower()
	return "%s formation: select two or more ships and right-click to sail them in it." % shape_name()


func release(ids: Array) -> void:
	## These ships leave the formation (they've been given their own orders)
	for i in ids:
		if members.has(i):
			members.erase(i)
			sim.cap[i] = 0.0
		if i == lead:
			release_all()
			return


func release_all() -> void:
	forming = false
	if lead >= 0:
		sim.cap[lead] = 0.0
	for i in members:
		sim.cap[i] = 0.0
	lead = -1
	members.clear()
	mode.clear()


func active() -> bool:
	return lead >= 0


func update(dt: float) -> void:
	if lead < 0:
		return
	_acc += dt
	if _acc < UPDATE:
		return
	_acc = 0.0
	for i in members.keys():
		if sim.alive[i] == 0 or sim.aboard[i] != -1:
			members.erase(i)
	if sim.alive[lead] == 0:
		# The guide is gone: the next ship in line takes over
		if members.is_empty():
			release_all()
			return
		var pl := places(members.keys())
		var old: Dictionary = members
		lead = pl[0]
		var shift: Vector2 = old[lead]
		members = {}
		for i in old:
			if i != lead:
				members[i] = (old[i] as Vector2) - shift
		if not sim.order_move(lead, dest):
			release_all()
			return
		sim.cap[lead] = lead_cap
	if members.is_empty():
		release_all()
		return
	var L := Vector2(sim.x[lead], sim.z[lead])
	if L.distance_to(trail[trail.size() - 1]) > TRAIL_STEP:
		trail.append(L)
		if trail.size() > 400:
			trail = trail.slice(trail.size() - 400)
	if not sim.is_moving(lead):
		_arrive()
		return
	# how fast the guide is really going (it slows for turns and to stop)
	var pace := lead_cap
	if _last_l.x != INF:
		pace = clampf(L.distance_to(_last_l) / maxf(dt, UPDATE), 0.0, lead_cap)
	_last_l = L
	var want := _ahead_course()
	var step := COURSE_RATE * maxf(dt, UPDATE)
	course = wrapf(course + clampf(wrapf(want - course, -PI, PI), -step, step), -PI, PI)
	var ax := axes(course)
	var right: Vector2 = ax[0]
	var ahead: Vector2 = ax[1]
	# In the wake: those placed furthest ahead follow closest behind the guide
	var order: Array = members.keys()
	order.sort_custom(func(a, b): return members[a].y > members[b].y)
	var straggling := false
	_settled.clear()
	for m in order:
		var st0: Vector2 = L + right * members[m].x + ahead * members[m].y
		if st0.distance_to(Vector2(sim.x[m], sim.z[m])) < 300.0:
			_settled[m] = true
	for k in order.size():
		var m: int = order[k]
		var o: Vector2 = members[m]
		var full: float = TexasUnits.speed[sim.utype[m]]
		var pos := Vector2(sim.x[m], sim.z[m])
		var st := L + right * o.x + ahead * o.y
		if TexasSea.is_sea(st) and _water(L, st) and _water(pos, st):
			# Keep station: steer for a point a little ahead of the place, faster if behind it
			var behind := (st - pos).dot(ahead)
			var dist := pos.distance_to(st)
			straggling = straggling or dist > 1500.0
			# (the point ahead shrinks as the guide slows, so nobody overshoots when it stops)
			# (going round any ship of the fleet in the way, as seen from the moving formation)
			var wp := _round_others(m, pos, st)
			if wp != st:
				behind = (wp - pos).dot(ahead)
				dist = pos.distance_to(wp)
			var reach := clampf(pace * 60.0, 60.0, 600.0)
			while reach > 30.0 and not _water(wp, wp + ahead * reach):
				reach *= 0.5
			var aim := wp + ahead * reach
			sim.order_direct(m, aim)
			sim.cap[m] = full if dist > 1500.0 else clampf(pace + behind * 0.02 + (dist - absf(behind)) * 0.01, 0.5, full)
			mode[m] = "station"
			continue
		# No room for its place here: follow the guide's wake
		var wp := _wake(GAP * (k + 1))
		if (wp - pos).dot(ahead) < -50.0 and pos.distance_to(wp) < 1500.0:
			# ahead of its place in the line: ease off and let it come up (never double back)
			var on := pos + ahead * 150.0
			if _water(pos, on):
				sim.order_direct(m, on)
			else:
				sim.stop(m)
			sim.cap[m] = 1.0
			mode[m] = "wake"
		elif _water(pos, wp):
			var d := pos.distance_to(wp)
			sim.order_direct(m, wp)
			sim.cap[m] = clampf(lead_cap + (d - 150.0) * 0.02, 1.0, full)
			mode[m] = "wake"
		elif sim.time - float(_routed.get(m, -1.0e9)) > 20.0 or not sim.is_moving(m):
			sim.order_move(m, wp)
			sim.cap[m] = full
			_routed[m] = sim.time
			mode[m] = "routed"
	_keep_apart()
	# The guide eases off while ships are still far from their places, so the fleet forms up
	sim.cap[lead] = lead_cap * (0.5 if straggling else 1.0)
	forming = straggling


func _round_others(m: int, pos: Vector2, st: Vector2) -> Vector2:
	## Where to head for on the way to place `st`: the place itself, or, if another ship of the
	## fleet is in the way, a point beside that ship. The ships keep their places relative to
	## each other, so this works as if they stood still.
	var seg := st - pos
	var L := seg.length()
	if L < 1.0:
		return st
	var dir := seg / L
	var block := -1
	var block_t := INF
	for o in [lead] + members.keys():
		if o == m or not (o == lead or _settled.has(o)):
			continue
		var op := Vector2(sim.x[o], sim.z[o])
		var t := (op - pos).dot(dir)
		if t <= 0.0 or t >= L:
			continue
		var clear := _half(m) + _half(o) + 160.0
		if (pos + dir * t).distance_to(op) < clear and t < block_t:
			block = o
			block_t = t
	if block < 0:
		return st
	var op := Vector2(sim.x[block], sim.z[block])
	var clear := _half(m) + _half(block) + 160.0
	var perp := Vector2(-dir.y, dir.x)
	var side := signf((pos - op).dot(perp))
	if side == 0.0:
		side = 1.0
	var p := op + perp * side * clear * 1.3
	if not TexasSea.is_sea(p):
		p = op - perp * side * clear * 1.3
	return p if TexasSea.is_sea(p) else st


func _keep_apart() -> void:
	## Ships under way never sail into each other: any two too close are eased apart
	var all: Array = [lead] + members.keys()
	for a in all.size():
		for b in range(a + 1, all.size()):
			var i: int = all[a]
			var j: int = all[b]
			var d := Vector2(sim.x[j] - sim.x[i], sim.z[j] - sim.z[i])
			var need := _half(i) + _half(j) + 120.0
			var L := d.length()
			if L >= need:
				continue
			var n := d / L if L > 0.01 else Vector2(1, 0)
			var move := minf((need - L) * 0.5, 40.0)
			for pair in [[i, -1.0], [j, 1.0]]:
				var u: int = pair[0]
				if u == lead:
					continue
				var from := Vector2(sim.x[u], sim.z[u])
				var q := from + n * move * (pair[1] as float) * (2.0 if i == lead or j == lead else 1.0)
				if TexasSea.is_sea(q + (q - from).normalized() * _half(u) * 0.5) and TexasSea.open_water(from, q, 10.0, TexasSea.CLEAR * 0.6):
					sim.x[u] = q.x
					sim.z[u] = q.y


func _half(i: int) -> float:
	var id: String = TexasUnits.TYPES[sim.utype[i]].id
	return float(HULL.get(id, Vector2(150, 20)).x) * 0.5


func _ahead_course() -> float:
	## Which way the guide is going overall: towards where it will be LOOK_AHEAD further on
	var L := Vector2(sim.x[lead], sim.z[lead])
	var pts: Array = []
	var way: PackedVector2Array = sim.wps[lead]
	for q in range(sim.leg[lead], way.size()):
		pts.append(way[q])
	pts.append(Vector2(sim.dest_x[lead], sim.dest_z[lead]))
	var at := L
	var left := LOOK_AHEAD
	var tgt := L
	for p in pts:
		var d := at.distance_to(p)
		tgt = p
		if d >= left:
			tgt = at.lerp(p, left / d)
			break
		left -= d
		at = p
	var v := tgt - L
	if v.length() < 100.0:
		return sim.heading[lead]
	return atan2(-v.x, -v.y)


func _wake(back: float) -> Vector2:
	## The point on the guide's track `back` metres behind it
	var n := trail.size()
	var at := Vector2(sim.x[lead], sim.z[lead])
	var left := back
	for k in range(n - 1, -1, -1):
		var p := trail[k]
		var d := at.distance_to(p)
		if d >= left:
			return at.lerp(p, left / d)
		left -= d
		at = p
	return at


func _water(a: Vector2, b: Vector2) -> bool:
	## Open water all the way from a to b, with room for the hull
	return TexasSea.open_water(a, b)


func _arrive() -> void:
	## The guide is there: everyone to their place round it, then the formation is done
	var L := Vector2(sim.x[lead], sim.z[lead])
	var ax := axes(course)
	for m in members:
		var o: Vector2 = members[m]
		var st: Vector2 = L + ax[0] * o.x + ax[1] * o.y
		if not TexasSea.is_sea(st) and camp.sea != null:
			var lane: PackedVector2Array = camp.sea.route(Vector2(sim.x[m], sim.z[m]), st)
			if lane.is_empty():
				continue
			st = lane[lane.size() - 1]
		sim.cap[m] = 0.0
		sim.order_move(m, st)
	sim.cap[lead] = 0.0
	lead = -1
	members.clear()


func to_dict() -> Dictionary:
	return {"shape": shape, "lead": lead, "dest": dest, "members": members, "trail": trail, "cap": lead_cap, "course": course}


func from_dict(d: Dictionary) -> void:
	shape = d.get("shape", 0)
	lead = d.get("lead", -1)
	dest = d.get("dest", Vector2.ZERO)
	members = d.get("members", {})
	trail = d.get("trail", PackedVector2Array())
	lead_cap = d.get("cap", 0.0)
	course = d.get("course", 0.0)
	_acc = 0.0
	if lead >= 0 and trail.is_empty():
		trail = PackedVector2Array([Vector2(sim.x[lead], sim.z[lead])])
