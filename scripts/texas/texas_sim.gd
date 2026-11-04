class_name TexasSim
extends RefCounted
## The light layer of the two-layer simulation: every unit in Texas as a row of numbers
## (side, type, position, heading, strength, fuel, route), with no 3D model. It runs everywhere
## at any time speed: ground units drive the road network, ships follow sea lanes, aircraft and
## hovercraft go straight, fuel burns, and when enemies meet the fight is resolved with simple
## strength-against-strength maths (weapons, range, toughness) instead of every bullet.
##
## Units can be aboard others (squads in a Stryker, vehicles on a landing craft, aircraft on a
## carrier): they ride along, out of the fight, until they get off. Losing the carrier loses
## everything aboard.
##
## Near the camera TexasMain shows these units as 3D models, with the shots and explosions.

enum Kind {INFANTRY, WHEELED, ARMOR, HELI, JET, SHIP}       # = TexasUnits.Cat
const KIND_NAMES := ["infantry squad", "wheeled vehicle", "armour", "helicopter", "jet", "ship"]
const COMBAT_STEP := 5.0          # seconds of game time between fight resolutions
const CELL := 3000.0              # spatial grid for finding enemies nearby (>= the longest land range)

enum State {IDLE, MOVING, ENGAGED}
enum Flag {RESERVE = 1, GARRISON = 2, LANDED = 4, BUSY = 8}

var roads: TexasRoads
var sea: TexasSea                      # sea lanes, when there's a fleet
var count := 0
var side := PackedByteArray()          # 0 = you, 1 = Red
var kind := PackedByteArray()          # category (Kind / TexasUnits.Cat)
var utype := PackedByteArray()         # TexasUnits type
var alive := PackedByteArray()
var state := PackedByteArray()
var x := PackedFloat64Array()
var z := PackedFloat64Array()
var px := PackedFloat64Array()         # position at the previous tick (for smooth drawing)
var pz := PackedFloat64Array()
var heading := PackedFloat32Array()
var bank := PackedFloat32Array()       # how far an aircraft is leaning into its turn (for drawing)
var cap := PackedFloat32Array()        # speed limit (m/s) while keeping station in a formation; 0: none
var strength := PackedFloat32Array()
var fuel := PackedFloat32Array()
var dest_x := PackedFloat64Array()
var dest_z := PackedFloat64Array()
var leg := PackedInt32Array()
var target := PackedInt32Array()       # who it's shooting at (kept while still in range)
var aboard := PackedInt32Array()       # the unit it rides in, -1 if none, <= -2: parked at airfield (-2 - zone)
var flags := PackedByteArray()
var routes: Array = []                 # PackedInt32Array of road nodes per unit
var wps: Array = []                    # PackedVector2Array of waypoints (sea lanes, flight paths)
var time := 0.0                        # game seconds since the campaign started
var kills := [0, 0]                    # units each side has destroyed
var tick_ms := 0.0                     # cost of the last tick (for the stats line)
var killed_recent := PackedInt32Array() # units lost since the last time someone looked (effects, messages)
var shots := PackedInt32Array()        # [attacker, target] pairs from the last fight round
var crashed_recent := PackedInt32Array()
var _round := 0
var threaded := true                   # fight rounds on a worker thread
var _job_running := false
var _job_id := -1
var _job_result := {}
var _job_mutex := Mutex.new()
var _combat_acc := 0.0
var _has_riders := {}                  # units with someone aboard (rebuilt every tick)
var _grid_bounds: Rect2
var _grid_w := 0
var _grid_h := 0


func _init(road_net: TexasRoads) -> void:
	TexasUnits.setup()
	roads = road_net
	_grid_bounds = TexasGeo.bounds().grow(CELL * 4.0)
	_grid_w = ceili(_grid_bounds.size.x / CELL)
	_grid_h = ceili(_grid_bounds.size.y / CELL)


func add_unit(s: int, k: int, at: Vector2) -> int:
	## A unit by category, as the Phase 2 test world places them
	return add_typed(s, TexasUnits.default_type(k, s), at)


func add_typed(s: int, t: int, at: Vector2, on := -1) -> int:
	side.append(s)
	utype.append(t)
	kind.append(TexasUnits.cat[t])
	alive.append(1)
	state.append(State.IDLE)
	x.append(at.x)
	z.append(at.y)
	px.append(at.x)
	pz.append(at.y)
	heading.append(randf() * TAU)
	bank.append(0.0)
	cap.append(0.0)
	strength.append(1.0)
	fuel.append(1.0)
	dest_x.append(at.x)
	dest_z.append(at.y)
	leg.append(0)
	target.append(-1)
	aboard.append(on)
	if on >= 0:
		_has_riders[on] = true
	flags.append(0)
	routes.append(PackedInt32Array())
	wps.append(PackedVector2Array())
	count += 1
	return count - 1


func is_air(i: int) -> bool:
	return TexasUnits.move[utype[i]] == TexasUnits.Move.AIR


func airborne(i: int) -> bool:
	return is_air(i) and aboard[i] == -1 and not (flags[i] & Flag.LANDED)


static func is_water(p: Vector2) -> bool:
	## Water a vehicle can't drive into: the sea as drawn, lakes and rivers (not bridges)
	return TexasWater.any(p)


static func crosses_water(a: Vector2, b: Vector2) -> bool:
	## Whether the straight line from a to b goes over water (checked every 10 m)
	var n := int(a.distance_to(b) / 10.0)
	for k in range(1, n + 1):
		if is_water(a.lerp(b, float(k) / (n + 1))):
			return true
	return false


func roadside(p: Vector2) -> Vector2:
	## A spot on the nearest road junction (roads are always dry): for putting units down in towns
	var n := roads.nearest_node(p)
	if n < 0:
		return nearest_land(p)
	# (within the road's own width, which is dry even where it crosses water)
	return roads.nodes[n] + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 3.0)


static func nearest_land(p: Vector2, max_r := 4000.0) -> Vector2:
	if not is_water(p):
		return p
	var r := 15.0
	while r <= max_r:
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector2(cos(a), sin(a)) * r
			if not is_water(q):
				return q
		r *= 1.4
	return p


func order_move(i: int, to: Vector2, via := PackedVector2Array()) -> bool:
	## Send a unit somewhere: ground units by road (never across the water: they stop on the
	## shore), ships along sea lanes, aircraft and hovercraft straight there (through `via`
	## first). False if it can't get there.
	if alive[i] == 0 or aboard[i] != -1:
		return false
	var mv: int = TexasUnits.move[utype[i]]
	routes[i] = PackedInt32Array()
	wps[i] = via.duplicate()
	if mv == TexasUnits.Move.GROUND:
		var here := Vector2(x[i], z[i])
		to = nearest_land(to)
		var a := roads.nearest_reachable(here)
		var b := roads.nearest_reachable(to)
		var route := roads.find_route(a, b)
		if route.is_empty():
			if crosses_water(here, to):
				return false
		else:
			var last: Vector2 = roads.nodes[route[route.size() - 1]]
			if crosses_water(last, to):
				to = last
		routes[i] = route
	elif mv == TexasUnits.Move.HOVER:
		# Hovercraft: back into the water if ashore, round by the sea lanes, and up onto the
		# beach at the far end (no further inland)
		var start := Vector2(x[i], z[i]) if via.is_empty() else via[via.size() - 1]
		var path := PackedVector2Array(via)
		if not TexasSea.hover_water(start):
			start = TexasSea.nearest_hover_water(start)
			path.append(start)
		if sea != null:
			var lane := sea.route(start, to)
			if not lane.is_empty():
				path.append_array(lane)
				start = lane[lane.size() - 1]
		if not TexasSea.hover_water(to):
			to = TexasSea.beach(start, to)
		wps[i] = path
	elif mv == TexasUnits.Move.SEA:
		if sea == null:
			return false
		var lane := sea.route(Vector2(x[i], z[i]), to)
		if lane.is_empty():
			return false
		wps[i] = lane
		# a spot on land (a port, a beach): stop at the water nearest it, not drive on up to it
		to = lane[lane.size() - 1]
	dest_x[i] = to.x
	dest_z[i] = to.y
	leg[i] = 0
	state[i] = State.MOVING
	flags[i] &= ~Flag.LANDED
	return true


func order_direct(i: int, to: Vector2) -> void:
	## Straight there, no route (a ship keeping station when the water between is clear)
	routes[i] = PackedInt32Array()
	wps[i] = PackedVector2Array()
	dest_x[i] = to.x
	dest_z[i] = to.y
	leg[i] = 0
	state[i] = State.MOVING


func stop(i: int) -> void:
	routes[i] = PackedInt32Array()
	wps[i] = PackedVector2Array()
	dest_x[i] = x[i]
	dest_z[i] = z[i]
	state[i] = State.IDLE


func is_moving(i: int) -> bool:
	return alive[i] == 1 and state[i] == State.MOVING


func at_dest(i: int) -> bool:
	return state[i] != State.MOVING


func live_count(s: int) -> int:
	var n := 0
	for i in count:
		if alive[i] == 1 and side[i] == s:
			n += 1
	return n


func moving_count() -> int:
	var n := 0
	for i in count:
		if alive[i] == 1 and state[i] == State.MOVING:
			n += 1
	return n


# --- Riding in transports --------------------------------------------------------------------

func cargo_of(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j in count:
		if alive[j] == 1 and aboard[j] == i:
			out.append(j)
	return out


func seats_used(i: int) -> int:
	var n := 0
	for j in count:
		if alive[j] == 1 and aboard[j] == i and kind[j] == Kind.INFANTRY:
			n += 1
	return n


func slots_used(i: int) -> int:
	var n := 0
	for j in count:
		if alive[j] == 1 and aboard[j] == i and kind[j] != Kind.INFANTRY:
			n += TexasUnits.size[utype[j]]
	return n


func can_carry(carrier: int, j: int) -> bool:
	## Room for unit j aboard `carrier` (ships hold anything)
	var ct: int = utype[carrier]
	if TexasUnits.is_ship(ct):
		return true
	if kind[j] == Kind.INFANTRY:
		return seats_used(carrier) < TexasUnits.seats[ct]
	var need: int = TexasUnits.size[utype[j]]
	return need > 0 and TexasUnits.slots[ct] > 0 and slots_used(carrier) + need <= TexasUnits.slots[ct]


func board(j: int, carrier: int) -> void:
	stop(j)
	aboard[j] = carrier
	_has_riders[carrier] = true
	target[j] = -1
	x[j] = x[carrier]
	z[j] = z[carrier]


func unload(i: int, spread := 30.0) -> PackedInt32Array:
	## Everyone aboard gets off around the transport
	var out := cargo_of(i)
	var k := 0
	for j in out:
		var a := k * 2.4
		var r := spread * (1.0 + k * 0.25)
		aboard[j] = -1
		var p := Vector2(x[i] + cos(a) * r, z[i] + sin(a) * r)
		if is_water(p):
			p = nearest_land(Vector2(x[i], z[i]))
		x[j] = p.x
		z[j] = p.y
		px[j] = x[j]
		pz[j] = z[j]
		stop(j)
		k += 1
	return out


# --- Running ----------------------------------------------------------------------------

func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_collect_combat()
	time += dt
	var nodes := roads.nodes
	var MOVE := TexasUnits.move
	var SPEED := TexasUnits.speed
	var ENDURE := TexasUnits.endurance
	var riders := false
	for i in count:
		px[i] = x[i]
		pz[i] = z[i]
		if alive[i] == 0:
			continue
		if aboard[i] != -1:
			riders = riders or aboard[i] >= 0
			continue
		var moving: bool = state[i] == State.MOVING
		var t: int = utype[i]
		var flying: bool = MOVE[t] == TexasUnits.Move.AIR and not (flags[i] & Flag.LANDED)
		if not moving and not flying:
			continue
		# Aircraft burn fuel the whole time they're up; everything else only when moving
		fuel[i] = maxf(0.0, fuel[i] - dt / ENDURE[t])
		if fuel[i] <= 0.0:
			if flying:
				_out_of_fuel(i)
			else:
				state[i] = State.IDLE
			continue
		if TexasUnits.turn[t] > 0.0:
			# Aircraft and ships steer: they can only turn so fast
			if moving or (flying and kind[i] == Kind.JET):
				_steer(i, t, dt, SPEED[t] if cap[i] <= 0.0 else minf(SPEED[t], cap[i]), nodes)
			else:
				bank[i] = 0.0
			continue
		if not moving:
			continue
		var step: float = SPEED[t] * dt
		# Along the road, node by node, then the waypoints, then to the exact spot
		var route: PackedInt32Array = routes[i]
		var way: PackedVector2Array = wps[i]
		while step > 0.0:
			var tx: float
			var tz: float
			var phase := 0
			if leg[i] < route.size():
				var nd := nodes[route[leg[i]]]
				tx = nd.x
				tz = nd.y
			elif leg[i] - route.size() < way.size():
				var wp := way[leg[i] - route.size()]
				tx = wp.x
				tz = wp.y
				phase = 1
			else:
				tx = dest_x[i]
				tz = dest_z[i]
				phase = 2
			var dx := tx - x[i]
			var dz := tz - z[i]
			var d := sqrt(dx * dx + dz * dz)
			if d > 0.001:
				heading[i] = atan2(-dx, -dz)
			if d <= step:
				x[i] = tx
				z[i] = tz
				step -= d
				if phase < 2:
					leg[i] += 1
				else:
					state[i] = State.IDLE
					break
			else:
				x[i] += dx / d * step
				z[i] += dz / d * step
				step = 0.0
	if riders or not _has_riders.is_empty():
		_ride_along()
	_combat_acc += dt
	if _combat_acc >= maxf(COMBAT_STEP, dt) and not _job_running:
		_combat(_combat_acc)
		_combat_acc = 0.0
	tick_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _target_of(i: int, nodes: PackedVector2Array) -> Array:
	## Where unit i is heading now: [x, z, phase] (0 road node, 1 waypoint, 2 the destination)
	var route: PackedInt32Array = routes[i]
	var way: PackedVector2Array = wps[i]
	if leg[i] < route.size():
		var nd := nodes[route[leg[i]]]
		return [nd.x, nd.y, 0]
	if leg[i] - route.size() < way.size():
		var wp := way[leg[i] - route.size()]
		return [wp.x, wp.y, 1]
	return [dest_x[i], dest_z[i], 2]


func _steer(i: int, t: int, dt: float, speed: float, nodes: PackedVector2Array) -> void:
	## Fly or sail like the real thing: turn towards the target no faster than the type can
	## (jets lean into wide arcs; a target too close to turn onto, they fly past and come back
	## round), helicopters slow down for sharp turns, ships come about slowly. Jets with
	## nowhere to go circle the spot, 2 km round. Worked in short slices so fast time stays smooth.
	var rate: float = TexasUnits.turn[t]
	var jet: bool = kind[i] == Kind.JET
	var ship: bool = kind[i] == Kind.SHIP or TexasUnits.move[t] == TexasUnits.Move.HOVER
	var arrive: float = 300.0 if jet else (60.0 if ship else 25.0)
	var radius := speed / rate
	var left := dt
	var turned := 0.0
	while left > 0.0:
		var h := minf(left, 1.0)
		left -= h
		var tg := _target_of(i, nodes)
		var tx: float = tg[0]
		var tz: float = tg[1]
		var circling := state[i] != State.MOVING
		if circling:
			# Aim at a point a little ahead on a 2 km circle round the spot
			var a := atan2(z[i] - dest_z[i], x[i] - dest_x[i]) + 0.5
			tx = dest_x[i] + cos(a) * 2000.0
			tz = dest_z[i] + sin(a) * 2000.0
		var dx := tx - x[i]
		var dz := tz - z[i]
		var d := sqrt(dx * dx + dz * dz)
		if not circling and d <= maxf(arrive, speed * h * (0.6 if not jet else 0.0)):
			if tg[2] < 2:
				leg[i] += 1
				left += h
				if left > dt:
					left = dt
				continue
			# (onto the exact spot, unless it's a ship and the spot isn't open water)
			if not jet and not (kind[i] == Kind.SHIP and not TexasSea.open_water(Vector2(x[i], z[i]), Vector2(tx, tz), 15.0, 0.0)):
				x[i] = tx
				z[i] = tz
			state[i] = State.IDLE
			bank[i] = 0.0
			if not jet:
				return
			continue
		var want := atan2(-dx, -dz)
		var err := wrapf(want - heading[i], -PI, PI)
		var step_turn := rate * h
		var turn_by := clampf(err, -step_turn, step_turn)
		# A jet that would have to turn round inside its own turning circle flies on to get room
		if jet and not circling and d < radius * 1.6 and absf(err) > 1.2:
			turn_by = 0.0
		heading[i] = wrapf(heading[i] + turn_by, -PI, PI)
		turned += turn_by
		var v := speed
		if not jet:
			# Slow down for a sharp turn (ships and helicopters can nearly stop to come round)
			v *= clampf(cos(err) * 1.1, 0.15 if not ship else 0.3, 1.0)
			# Close to the spot and still facing away: ease right down so the turning circle
			# shrinks to fit (otherwise a ship orbits a spot inside its own turn for ever)
			# (a spot at distance d and bearing err off the bow is reachable on a circle of
			# radius d / (2 sin err), so only slow when the spot is inside that)
			if not circling and absf(err) > 0.05:
				v = minf(v, rate * d * 0.9 / (2.0 * sin(minf(absf(err), PI * 0.5))) + 0.3)
			v = minf(v, d / h)
			# Ships in confined water: land close ahead (inside the room it needs to turn)
			# means slow right down, which tightens the turn, rather than sweep over it
			if kind[i] == Kind.SHIP:
				var fwd := Vector2(-sin(heading[i]), -cos(heading[i]))
				var bow: float = TexasUnits.foot[t]
				var room := clampf(v / rate * 1.2, 80.0, 500.0)
				var here := Vector2(x[i], z[i])
				if not TexasSea.is_sea(here + fwd * (bow + 30.0)):
					# right up against it: come round almost on the spot
					v = minf(v, 0.6)
				elif v > speed * 0.25 and (not TexasSea.is_sea(here + fwd * (bow + room)) or not TexasSea.is_sea(here + fwd * (bow + room * 0.5))):
					v = speed * 0.25
		elif circling:
			v *= 0.75
		x[i] += -sin(heading[i]) * v * h
		z[i] += -cos(heading[i]) * v * h
	var lean := TexasUnits.max_bank[t]
	bank[i] = clampf(turned / maxf(rate * dt, 1e-4), -1.0, 1.0) * lean


func _ride_along() -> void:
	## Everyone aboard something sits where it is (through transports aboard ships too)
	_has_riders.clear()
	for i in count:
		var c := aboard[i]
		if c < 0 or alive[i] == 0:
			continue
		_has_riders[c] = true
		var depth := 0
		while aboard[c] >= 0 and depth < 4:
			c = aboard[c]
			depth += 1
		x[i] = x[c]
		z[i] = z[c]
		heading[i] = heading[c]


func _out_of_fuel(i: int) -> void:
	## Helicopters autorotate down: a good crew lands it hard, otherwise it crashes. Jets are lost.
	crashed_recent.append(i)
	if kind[i] == Kind.HELI and randf() < 0.6:
		flags[i] |= Flag.LANDED
		strength[i] = minf(strength[i], 0.5)
		stop(i)
		return
	_kill(i)


func _kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	strength[i] = 0.0
	killed_recent.append(i)
	# Whatever it carried goes with it
	if _has_riders.has(i):
		for j in count:
			if alive[j] == 1 and aboard[j] == i:
				_kill(j)



func _combat(dt: float) -> void:
	## Start a round of fighting. On a worker thread when `threaded` (the main thread only
	## copies the arrays and later applies the result); otherwise right here.
	_round += 1
	var snap := {"count": count, "x": x.duplicate(), "z": z.duplicate(), "side": side.duplicate(),
		"kind": kind.duplicate(), "utype": utype.duplicate(), "alive": alive.duplicate(),
		"aboard": aboard.duplicate(), "strength": strength.duplicate(),
		"target": target.duplicate(), "flags": flags.duplicate(), "dt": dt, "round": _round, "bounds": _grid_bounds, "gw": _grid_w, "gh": _grid_h}
	if not threaded:
		_apply_combat(_resolve(snap))
		return
	_job_running = true
	_job_id = WorkerThreadPool.add_task(func():
		var res := TexasSim._resolve(snap)
		_job_mutex.lock()
		_job_result = res
		_job_mutex.unlock())


func finish() -> void:
	## Wait for a fight round still being worked out (before the game closes)
	if _job_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_job_id)
		_job_id = -1
	_job_running = false


func _collect_combat() -> void:
	if not _job_running:
		return
	_job_mutex.lock()
	var res := _job_result
	_job_result = {}
	_job_mutex.unlock()
	if not res.is_empty():
		_job_running = false
		if _job_id >= 0:
			WorkerThreadPool.wait_for_task_completion(_job_id)
			_job_id = -1
		_apply_combat(res)


static func _resolve(snap: Dictionary) -> Dictionary:
	## One round of fighting, worked out on a snapshot (so it can run on a worker thread):
	## who shoots whom, and how much damage each unit takes
	var count: int = snap.count
	var x: PackedFloat64Array = snap.x
	var z: PackedFloat64Array = snap.z
	var side: PackedByteArray = snap.side
	var kind: PackedByteArray = snap.kind
	var utype: PackedByteArray = snap.utype
	var alive: PackedByteArray = snap.alive
	var aboard: PackedInt32Array = snap.aboard
	var strength: PackedFloat32Array = snap.strength
	var target: PackedInt32Array = snap.target
	var dt: float = snap.dt
	var _round: int = snap.round
	var b: Rect2 = snap.bounds
	var gw: int = snap.gw
	var gh: int = snap.gh
	var DPS := TexasUnits.dps
	var RNG := TexasUnits.rng
	var HP := TexasUnits.hp
	var MAXR := TexasUnits.max_range
	var flg: PackedByteArray = snap.flags
	var sight: bool = snap.get("sight", true)
	# Sort the units in the fight by (cell, side) with one native sort; only occupied cells are touched
	var keys := PackedInt64Array()
	keys.resize(count)
	var n := 0
	var bucket_of := PackedInt32Array()
	bucket_of.resize(count)
	var mask := {}
	var ships := PackedInt32Array()
	for i in count:
		if alive[i] == 0 or aboard[i] != -1:
			bucket_of[i] = -1
			continue
		if kind[i] == Kind.SHIP:
			ships.append(i)
		var cx := clampi(int((x[i] - b.position.x) / CELL), 0, gw - 1)
		var cz := clampi(int((z[i] - b.position.y) / CELL), 0, gh - 1)
		var c := cz * gw + cx
		var bk := c * 2 + side[i]
		bucket_of[i] = bk
		keys[n] = (bk << 20) | i
		n += 1
		mask[c] = mask.get(c, 0) | (1 << side[i])
	keys.resize(n)
	keys.sort()
	var items := PackedInt32Array()
	items.resize(n)
	var ranges := {}                     # bucket -> Vector2i(first, end) in items
	var prev := -1
	var first := 0
	for t in n:
		var bk := keys[t] >> 20
		items[t] = keys[t] & 0xFFFFF
		if bk != prev:
			if prev >= 0:
				ranges[prev] = Vector2i(first, t)
			prev = bk
			first = t
	if prev >= 0:
		ranges[prev] = Vector2i(first, n)
	# Which sides are in each occupied cell's neighbourhood (worked out once per cell)
	var near := {}
	for c in mask:
		var cx: int = c % gw
		var cz: int = c / gw
		var m := 0
		for gz in range(cz - 1, cz + 2):
			for gx in range(cx - 1, cx + 2):
				m |= mask.get(gz * gw + gx, 0)
		near[c] = m
	# How high each unit looks from (and is seen at), for line of sight past buildings and hills
	var eye := PackedFloat32Array()
	eye.resize(count)
	for i in count:
		if bucket_of[i] >= 0:
			var air := TexasUnits.move[utype[i]] == TexasUnits.Move.AIR and not (flg[i] & Flag.LANDED)
			eye[i] = TexasSight.eye(kind[i], air)
	var damage := PackedFloat32Array()
	damage.resize(count)
	var engaged := PackedByteArray()
	engaged.resize(count)
	var shots := PackedInt32Array()
	for i in count:
		var bk := bucket_of[i]
		if bk < 0 or kind[i] == Kind.SHIP:
			continue
		var t: int = utype[i]
		if MAXR[t] <= 0.0:
			target[i] = -1
			continue
		var c := bk >> 1
		var enemy := 1 - side[i]
		if not (near[c] & (1 << enemy)):
			target[i] = -1
			continue
		var row := t * 6
		# Keep shooting the same target while it's alive and in range; look again every third round
		var tg := target[i]
		if tg >= 0 and alive[tg] == 1 and aboard[tg] == -1 and (_round + i) % 3 != 0:
			var tdx: float = x[tg] - x[i]
			var tdz: float = z[tg] - z[i]
			var rr: float = RNG[row + kind[tg]]
			if rr > 0.0 and tdx * tdx + tdz * tdz < rr * rr and (not sight or TexasSight.clear(x[i], z[i], eye[i], x[tg], z[tg], eye[tg])):
				damage[tg] += DPS[row + kind[tg]] * strength[i] * dt / HP[utype[tg]]
				engaged[i] = 1
				engaged[tg] = 1
				shots.append(i)
				shots.append(tg)
				continue
		var cx := c % gw
		var cz := c / gw
		var cand := PackedInt32Array()
		var cand_d := PackedFloat64Array()
		var xi: float = x[i]
		var zi: float = z[i]
		for gz in range(cz - 1, cz + 2):
			for gx in range(cx - 1, cx + 2):
				var rg = ranges.get((gz * gw + gx) * 2 + enemy)
				if rg == null:
					continue
				for q in range(rg.x, rg.y):
					var j := items[q]
					var rr: float = RNG[row + kind[j]]
					if rr <= 0.0:
						continue
					var dx: float = x[j] - xi
					var dz: float = z[j] - zi
					var d2 := dx * dx + dz * dz
					if d2 < rr * rr:
						cand.append(j)
						cand_d.append(d2)
		var best := _first_seen(cand, cand_d, i, x, z, eye, sight)
		target[i] = best
		if best >= 0:
			damage[best] += DPS[row + kind[best]] * strength[i] * dt / HP[utype[best]]
			engaged[i] = 1
			engaged[best] = 1
			shots.append(i)
			shots.append(best)
	# Ships: guns and missiles reach further than anything on land, so they look further
	if not ships.is_empty():
		var fleet := Rect2(Vector2(x[ships[0]], z[ships[0]]), Vector2.ZERO)
		for s in ships:
			fleet = fleet.expand(Vector2(x[s], z[s]))
		fleet = fleet.grow(8500.0)
		var cand := PackedInt32Array()
		for j in count:
			if bucket_of[j] >= 0 and fleet.has_point(Vector2(x[j], z[j])):
				cand.append(j)
		for s in ships:
			var row: int = utype[s] * 6
			var sc := PackedInt32Array()
			var sd := PackedFloat64Array()
			for j in cand:
				if side[j] == side[s]:
					continue
				var rr: float = RNG[row + kind[j]]
				if rr <= 0.0:
					continue
				var dx: float = x[j] - x[s]
				var dz: float = z[j] - z[s]
				var d2 := dx * dx + dz * dz
				# air threats first: anything in the air inside range beats a ground target
				if kind[j] == Kind.HELI or kind[j] == Kind.JET:
					d2 *= 0.01
				if d2 < rr * rr:
					sc.append(j)
					sd.append(d2)
			var best := _first_seen(sc, sd, s, x, z, eye, sight)
			target[s] = best
			if best >= 0:
				damage[best] += DPS[row + kind[best]] * strength[s] * dt / HP[utype[best]]
				engaged[s] = 1
				engaged[best] = 1
				shots.append(s)
				shots.append(best)
	return {"damage": damage, "engaged": engaged, "target": target, "shots": shots}


static func _first_seen(cand: PackedInt32Array, d2: PackedFloat64Array, i: int, x: PackedFloat64Array,
		z: PackedFloat64Array, eye: PackedFloat32Array, sight: bool) -> int:
	## The nearest of the enemies in range that `i` can actually see (the closest few are tried)
	var tried := 0
	while tried < 4:
		var best := -1
		var bd := INF
		for k in cand.size():
			if d2[k] < bd:
				bd = d2[k]
				best = k
		if best < 0:
			return -1
		var j := cand[best]
		if not sight or TexasSight.clear(x[i], z[i], eye[i], x[j], z[j], eye[j]):
			return j
		d2[best] = INF
		tried += 1
	return -1


func _apply_combat(res: Dictionary) -> void:
	## Apply a finished round: damage, kills, and who stops to fight
	var damage: PackedFloat32Array = res.damage
	var engaged: PackedByteArray = res.engaged
	var new_target: PackedInt32Array = res.target
	shots = res.shots
	for i in mini(count, new_target.size()):
		target[i] = new_target[i]
	for i in mini(count, damage.size()):
		if alive[i] == 0:
			continue
		if damage[i] > 0.0:
			strength[i] -= damage[i]
			if strength[i] <= 0.0:
				kills[1 - side[i]] += 1
				_kill(i)
				continue
		if engaged[i] == 1 and TexasUnits.move[utype[i]] == TexasUnits.Move.GROUND:
			if state[i] == State.MOVING:
				state[i] = State.ENGAGED
		elif state[i] == State.ENGAGED:
			var more := leg[i] < (routes[i] as PackedInt32Array).size() + (wps[i] as PackedVector2Array).size()
			state[i] = State.MOVING if more or Vector2(dest_x[i] - x[i], dest_z[i] - z[i]).length() > 1.0 else State.IDLE


# --- Saving -------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"version": 2, "time": time, "kills": kills, "side": side, "kind": kind, "utype": utype,
		"alive": alive, "state": state, "x": x, "z": z, "heading": heading, "strength": strength,
		"fuel": fuel, "dest_x": dest_x, "dest_z": dest_z, "leg": leg, "routes": routes, "wps": wps,
		"target": target, "aboard": aboard, "flags": flags, "cap": cap}


func from_dict(d: Dictionary) -> void:
	finish()
	time = d.time
	kills = d.kills
	side = d.side
	kind = d.kind
	alive = d.alive
	state = d.state
	x = d.x
	z = d.z
	px = x.duplicate()
	pz = z.duplicate()
	heading = d.heading
	bank = PackedFloat32Array()
	bank.resize(d.heading.size())
	cap = d.get("cap", PackedFloat32Array())
	cap.resize(d.heading.size())
	strength = d.strength
	fuel = d.fuel
	dest_x = d.dest_x
	dest_z = d.dest_z
	leg = d.leg
	routes = d.routes
	count = side.size()
	target = d.get("target", PackedInt32Array())
	target.resize(count)
	if d.has("utype"):
		utype = d.utype
		wps = d.wps
		aboard = d.aboard
		flags = d.flags
	else:
		utype = PackedByteArray()
		wps = []
		aboard = PackedInt32Array()
		flags = PackedByteArray()
		for i in count:
			utype.append(TexasUnits.default_type(kind[i], side[i]))
			wps.append(PackedVector2Array())
			aboard.append(-1)
			flags.append(0)
	killed_recent = PackedInt32Array()
	shots = PackedInt32Array()
	_job_running = false
	_job_result = {}


func checksum() -> float:
	## A number that changes if any unit's position or strength does (to check a load)
	var s := 0.0
	for i in count:
		s += x[i] * 0.001 + z[i] * 0.0007 + strength[i] * 13.0 + alive[i] * 7.0
	return s


# --- A stand-in war for testing: Red garrisons every city, your forces push inland --------

func seed_demo(red_scale := 1.0, blue_count := 900, rng_seed := 7) -> void:
	seed(rng_seed)
	seed_red_garrisons(red_scale)
	# Red patrols and reserves on the move between cities
	for k in int(250 * red_scale):
		var c1: Array = TexasGeo.cities.pick_random()
		var c2: Array = TexasGeo.cities.pick_random()
		var i := add_unit(1, [Kind.WHEELED, Kind.ARMOR, Kind.INFANTRY].pick_random(), TexasGeo.city_xz(c1))
		order_move(i, TexasGeo.city_xz(c2))
	# Your forces: ashore at Galveston and Corpus Christi, driving inland; helicopters overhead
	var beaches := ["Galveston", "Freeport", "Corpus Christi", "Port Lavaca"]
	var goals := ["Houston", "San Antonio", "Austin", "Dallas", "Victoria", "College Station", "Waco", "Beaumont", "Laredo"]
	for k in blue_count:
		var start := TexasGeo.city_xz(TexasGeo.city(beaches.pick_random())) + Vector2(randf_range(-150, 150), randf_range(-150, 150))
		var kk: int = [Kind.INFANTRY, Kind.WHEELED, Kind.WHEELED, Kind.ARMOR, Kind.HELI].pick_random()
		var i := add_unit(0, kk, start)
		var goal := TexasGeo.city_xz(TexasGeo.city(goals.pick_random()))
		order_move(i, goal)


func seed_red_garrisons(red_scale := 1.0, skip: Rect2 = Rect2()) -> void:
	## Red in every town and city, more in the big ones (outside `skip`, if given)
	var per_tier := [0, 8, 20, 45, 90, 160]
	var mix := [Kind.INFANTRY, Kind.INFANTRY, Kind.INFANTRY, Kind.INFANTRY, Kind.INFANTRY, Kind.INFANTRY,
		Kind.WHEELED, Kind.WHEELED, Kind.ARMOR, Kind.ARMOR, Kind.ARMOR]
	for c in TexasGeo.cities:
		var centre := TexasGeo.city_xz(c)
		if skip.has_area() and skip.has_point(centre):
			continue
		var r := TexasGeo.city_radius(c[3])
		var n := int(per_tier[c[3]] * red_scale)
		for k in n:
			var a := randf() * TAU
			var d := sqrt(randf()) * r
			var kk: int = mix.pick_random()
			if randf() < 0.03:
				kk = Kind.HELI
			var at := centre + Vector2(cos(a), sin(a)) * d
			if kk != Kind.HELI:
				at = roadside(at)
			var i := add_unit(1, kk, at)
			flags[i] |= Flag.GARRISON
			if kk == Kind.HELI:
				flags[i] |= Flag.LANDED            # waiting on the ground, not burning fuel
