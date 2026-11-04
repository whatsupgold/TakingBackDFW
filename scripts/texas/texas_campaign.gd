class_name TexasCampaign
extends RefCounted
## The first playable slice: Galveston to Houston.
##
## Your fleet starts off Galveston with the first landing force aboard. Landing craft carry the
## vehicles to the beach and helicopters fly the squads in, both shuttling back and forth until
## everything is ashore. Ports, airfields and towns are taken by holding them with ground units
## and no enemy ground units left in them. A captured port lets the ships unload straight onto
## the dock; a captured airfield takes A-10s and is a place for aircraft to refuel and rearm.
## New units reach the fleet in waves; you order them from each wave's points.
##
## Red holds the area with garrisons in every town, reserves around Houston that counterattack
## where you push, air defences, attack helicopters, and jets at the Houston airfields that go
## after your ships. Taking downtown Houston wins; losing the carrier loses.

const WAVE_EVERY := 1800.0             # game seconds between deliveries
const WAVE_POINTS := 60
const CAPTURE_TIME := 300.0            # seconds of holding a place alone to take it
const ZONE_CHECK := 20.0
const AI_EVERY := 60.0
const AIR_EVERY := 10.0
const BINGO_FUEL := 0.25               # aircraft head home below this
const FLEET_START := Vector2(29.12, -94.62)
# The slice: Galveston to north Houston (lat, lon of the corners)
const SLICE_NW := Vector2(30.12, -95.80)
const SLICE_SE := Vector2(28.80, -94.30)
const SHIP_NAMES := {"carrier": "USS Gerald R. Ford", "amphib": "USS Kearsarge", "destroyer": ["USS Mitscher", "USS Laboon"], "cruiser": "USS Normandy"}

var sim: TexasSim
var sea: TexasSea
var slice: Rect2
var ships := {}                        # role -> unit index (destroyers: "destroyer0", "destroyer1")
var zones: Array = []                  # see _zone()
var lz := Vector2(INF, INF)            # where landings go
var vehicle_queue := PackedInt32Array()
var troop_queue := PackedInt32Array()
var ferries := {}                      # unit -> {"stage", "ship", "t", "to"}
var returning := {}                    # aircraft -> base ("s<ship>" or "z<zone>")
var player_air := {}                   # aircraft the player is flying -> game time of the order
var orders: Array = []                 # unit types ordered for the next wave
var points := 40
var next_wave := WAVE_EVERY
var raids: Array = []                  # {"units", "target", "until", "base"}
var raid_timer := {}                   # airfield zone -> game time of its next sortie
var assigned := {}                     # Red unit -> game time it was sent somewhere
var result := ""                       # "won", "lost"
var messages: Array = []               # for the screen (taken by TexasMain)
var alerts: Array = []                 # things that should slow the clock
var _zone_acc := 0.0
var _ai_acc := 0.0
var _air_acc := 0.0
var _ship_hp := {}
var _sep_acc := 0.0
var formation: TexasFormation          # the fleet sailing together
var org: TexasOrg                      # your brigades, battalions and companies
var order_to: Array = []
var ashore_to := {}                    # unit waiting aboard -> where it's to go ashore (else the landing zone)
var _slots := {}                       # landing spot (rounded) -> how many have been put there               # which company each ordered unit joins (-1: let it decide)


func setup(s: TexasSim) -> void:
	sim = s
	var a := TexasGeo.to_xz(SLICE_NW.x, SLICE_NW.y)
	var b := TexasGeo.to_xz(SLICE_SE.x, SLICE_SE.y)
	slice = Rect2(a, b - a)
	var sa := TexasGeo.to_xz(29.95, -95.60)
	var sb := TexasGeo.to_xz(28.55, -94.25)
	sea = TexasSea.new(Rect2(sa, sb - sa))
	sim.sea = sea
	formation = TexasFormation.new(sim, self)
	org = TexasOrg.new(sim)
	_make_zones()
	_make_fleet()
	_starting_lineup()
	_make_red()
	# The rest of Texas: Red garrisons, holding where they are
	sim.seed_red_garrisons(0.6, slice)
	for z in zones.size():
		raid_timer[z] = randf_range(900.0, 1800.0)
	# The water round everyone in the area, worked out in the background
	var keys := {}
	var ts := TexasData.tile_size
	for i in sim.count:
		var p := Vector2(sim.x[i], sim.z[i])
		if slice.has_point(p):
			keys[Vector2i(floori(p.x / ts), floori(p.y / ts))] = true
	TexasWater.warm(keys.keys())
	_say("The fleet is off Galveston. Set a landing zone, then send the force ashore.")


func _zone(name: String, kind: String, p: Vector2, r: float) -> Dictionary:
	return {"name": name, "kind": kind, "x": p.x, "z": p.y, "r": r, "owner": 1, "progress": 0.0, "objective": false}


func _make_zones() -> void:
	if TexasGeo.built:
		for pt in TexasData.meta.ports:
			var p := Vector2(pt[1], pt[2])
			if slice.has_point(p):
				zones.append(_zone(pt[0], "port", p, 1000.0))
		for af in TexasData.meta.airfields:
			var p := Vector2(af.x, af.z)
			if slice.has_point(p) and af.longest_runway >= 1500:
				var z := _zone(af.name, "airfield", p, 1300.0)
				z.icao = af.icao
				z.jets = af.jets
				zones.append(z)
	else:
		for pt in [["Galveston", 29.31, -94.795], ["Texas City", 29.37, -94.895]]:
			zones.append(_zone(pt[0], "port", TexasGeo.to_xz(pt[1], pt[2]), 1000.0))
		var z := _zone("Scholes Field", "airfield", TexasGeo.to_xz(29.265, -94.86), 1300.0)
		z.jets = false
		zones.append(z)
	var radius := {1: 700.0, 2: 900.0, 3: 1200.0, 4: 1600.0, 5: 2200.0}
	for c in TexasGeo.cities:
		var p := TexasGeo.city_xz(c)
		if slice.has_point(p) and int(c[3]) >= 2:
			zones.append(_zone(c[0], "town", p, radius[int(c[3])]))
	if TexasGeo.city("Houston").size() > 0 and zone_named("Houston") < 0:
		zones.append(_zone("Houston", "town", TexasGeo.city_xz(TexasGeo.city("Houston")), 2200.0))
	# The objectives: the port and airfield at Galveston, then downtown Houston
	var gal := TexasGeo.city_xz(TexasGeo.city("Galveston"))
	var best_port := -1
	var best_field := -1
	for k in zones.size():
		var z: Dictionary = zones[k]
		var d := Vector2(z.x, z.z).distance_to(gal)
		if z.kind == "port" and (best_port < 0 or d < Vector2(zones[best_port].x, zones[best_port].z).distance_to(gal)):
			best_port = k
		if z.kind == "airfield" and (best_field < 0 or d < Vector2(zones[best_field].x, zones[best_field].z).distance_to(gal)):
			best_field = k
	for k in [best_port, best_field, zone_named("Houston")]:
		if k >= 0:
			zones[k].objective = true
	zones[zone_named("Houston")].main = true


func zone_named(n: String) -> int:
	for k in zones.size():
		if zones[k].name == n:
			return k
	return -1


func _add_ship(role: String, type_name: String, at: Vector2) -> int:
	var i := sim.add_typed(0, TexasUnits.id(type_name), at)
	sim.heading[i] = PI * 0.75
	ships[role] = i
	_ship_hp[i] = 1.0
	return i


func _make_fleet() -> void:
	var c := TexasGeo.to_xz(FLEET_START.x, FLEET_START.y)
	var carrier := _add_ship("carrier", "carrier", c)
	var amphib := _add_ship("amphib", "amphib", c + Vector2(-1800.0, -700.0))
	_add_ship("destroyer0", "destroyer", c + Vector2(-3500.0, -2600.0))
	_add_ship("destroyer1", "destroyer", c + Vector2(2600.0, -1800.0))
	_add_ship("cruiser", "cruiser", c + Vector2(500.0, 2200.0))
	# The first landing force
	for k in 4:
		sim.add_typed(0, TexasUnits.id("lcac"), c, amphib)
	for tn in ["bradley", "bradley", "bradley", "bradley", "stryker", "stryker", "stryker", "stryker",
			"humvee", "humvee", "humvee", "humvee", "lmtv", "lmtv"]:
		sim.add_typed(0, TexasUnits.id(tn), c, amphib)
	for k in 16:
		sim.add_typed(0, TexasUnits.id("rifle"), c, amphib)
	for tn in ["black_hawk", "black_hawk", "black_hawk", "black_hawk", "chinook", "chinook",
			"apache", "apache", "little_bird", "little_bird", "hornet", "hornet", "hornet", "hornet"]:
		sim.add_typed(0, TexasUnits.id(tn), c, carrier)


func _starting_lineup() -> void:
	## The landing force as a brigade: an infantry battalion of two rifle companies and a mechanised
	## one, and an aviation battalion. Rearrange it as you like.
	var by_type := {}
	for i in sim.count:
		if sim.side[i] == 0 and TexasOrg.group_of_type(sim.utype[i]) != "navy":
			var id: String = TexasUnits.TYPES[sim.utype[i]].id
			if not by_type.has(id):
				by_type[id] = []
			by_type[id].append(i)
	var take := func(id: String, n: int, company: int) -> void:
		var pool: Array = by_type.get(id, [])
		for k in mini(n, pool.size()):
			org.assign(pool.pop_front(), company)
	var bde := org.add_brigade()
	var inf := org.add_battalion(bde)
	var able := org.add_company(inf)
	var baker := org.add_company(inf)
	var charlie := org.add_company(inf)
	take.call("rifle", 8, able)
	take.call("humvee", 2, able)
	take.call("lmtv", 1, able)
	take.call("rifle", 8, baker)
	take.call("humvee", 2, baker)
	take.call("lmtv", 1, baker)
	take.call("bradley", 4, charlie)
	take.call("stryker", 4, charlie)
	var avn := org.add_battalion(bde)
	var lift := org.add_company(avn)
	var attack := org.add_company(avn)
	var jets := org.add_company(avn)
	take.call("black_hawk", 99, lift)
	take.call("chinook", 99, lift)
	take.call("apache", 99, attack)
	take.call("little_bird", 99, attack)
	take.call("hornet", 99, jets)
	# anything left over finds a company of its own kind
	for i in sim.count:
		org.settle(i)


func _make_red() -> void:
	## Red around Galveston and Houston: garrisons in every place, reserves round Houston,
	## air defence at the airfields and downtown, jets and attack helicopters on the airfields
	var mix := ["rifle", "rifle", "rifle", "rifle", "rifle", "stryker", "stryker", "humvee", "tank", "tank", "aa"]
	var per := {"port": 4, "airfield": 6}
	var tier_n := {2: 6, 3: 10, 4: 16, 5: 40}
	for k in zones.size():
		var z: Dictionary = zones[k]
		var n: int = per.get(z.kind, 0)
		if z.kind == "town":
			var c := TexasGeo.city(z.name)
			n = tier_n.get(int(c[3]) if c.size() > 3 else 2, 6)
		var centre := Vector2(z.x, z.z)
		for q in n:
			var i := _red(mix.pick_random(), centre, z.r * 0.8)
			sim.flags[i] |= TexasSim.Flag.GARRISON
		if z.kind == "airfield":
			for q in 2:
				_red("aa", centre, z.r * 0.6)
			if z.get("jets", false):
				for q in 4:
					_park(sim.add_typed(1, TexasUnits.id("hornet"), centre), k)
				for q in 2:
					_park(sim.add_typed(1, TexasUnits.id("apache"), centre), k)
	# Reserves around Houston: they move to wherever you push
	var hou := Vector2(zones[zone_named("Houston")].x, zones[zone_named("Houston")].z)
	for q in 36:
		var i := _red(["tank", "tank", "stryker", "stryker", "humvee", "rifle", "aa"].pick_random(), hou, 9000.0)
		sim.flags[i] |= TexasSim.Flag.RESERVE
	for q in 6:
		_red("aa", hou, 2500.0)


func _red(type_name: String, centre: Vector2, r: float) -> int:
	var a := randf() * TAU
	var d := sqrt(randf()) * r
	var p := centre + Vector2(cos(a), sin(a)) * d
	if TexasUnits.move[TexasUnits.id(type_name)] == TexasUnits.Move.GROUND:
		p = sim.roadside(p)
	return sim.add_typed(1, TexasUnits.id(type_name), p)


func _park(i: int, zone: int) -> void:
	var z: Dictionary = zones[zone]
	sim.aboard[i] = -2 - zone
	sim.flags[i] |= TexasSim.Flag.LANDED
	sim.x[i] = z.x + randf_range(-300.0, 300.0)
	sim.z[i] = z.z + randf_range(-300.0, 300.0)
	sim.stop(i)


func _say(t: String, alert := false) -> void:
	messages.append(t)
	if alert:
		alerts.append(t)


# --- What the player can do -----------------------------------------------------------------

func set_lz(p: Vector2) -> bool:
	if TexasSim.is_water(p):
		_say("The landing zone has to be on land.")
		return false
	lz = p
	_say("Landing zone set.")
	return true


func ship_alive(role: String) -> bool:
	return ships.has(role) and sim.alive[ships[role]] == 1


func send_vehicles_ashore() -> int:
	var n := 0
	for role in ["amphib", "carrier"]:
		if not ship_alive(role):
			continue
		for j in sim.cargo_of(ships[role]):
			if TexasUnits.is_ground(sim.utype[j]) and sim.kind[j] != TexasSim.Kind.INFANTRY and not (j in vehicle_queue):
				vehicle_queue.append(j)
				n += 1
	if n > 0 and lz.x == INF:
		_say("Set a landing zone first: the vehicles are waiting for one.")
	return n


func send_ashore(ids: Array, to := Vector2(INF, INF)) -> Array:
	## These units, still aboard a ship, go ashore: vehicles by landing craft, squads by
	## helicopter, to `to` (or the landing zone). [vehicles, squads] queued.
	var dest := to if to.x != INF else lz
	var nv := 0
	var ns := 0
	for j in ids:
		if sim.alive[j] == 0 or sim.side[j] != 0:
			continue
		var host := sim.aboard[j]
		if host < 0 or not TexasUnits.is_ship(sim.utype[host]) or not TexasUnits.is_ground(sim.utype[j]):
			continue
		if dest.x != INF:
			ashore_to[j] = dest
		if sim.kind[j] == TexasSim.Kind.INFANTRY:
			if not (j in troop_queue):
				troop_queue.append(j)
			ns += 1
		else:
			if not (j in vehicle_queue):
				vehicle_queue.append(j)
			nv += 1
	if nv + ns > 0 and dest.x == INF:
		_say("Set a landing zone (or right-click on land with them selected) and they'll go.")
	return [nv, ns]


func _dest_of(j: int) -> Vector2:
	return ashore_to.get(j, lz)


func landing_slot(dest: Vector2, vehicle: bool) -> Vector2:
	## The next tidy spot at a landing point: vehicles in rows 30 m apart, squads 16 m apart
	var key := Vector2i(roundi(dest.x / 50.0), roundi(dest.y / 50.0))
	var k: int = _slots.get(key, 0)
	_slots[key] = k + 1
	var gap := 30.0 if vehicle else 16.0
	var cols := 5
	var p := dest + Vector2((k % cols - (cols - 1) * 0.5) * gap, (k / cols) * gap)
	return TexasSim.nearest_land(p)


func send_troops_ashore() -> int:
	var n := 0
	for role in ships:
		if not ship_alive(role):
			continue
		for j in sim.cargo_of(ships[role]):
			if sim.kind[j] == TexasSim.Kind.INFANTRY and not (j in troop_queue):
				troop_queue.append(j)
				n += 1
	if n > 0 and lz.x == INF:
		_say("Set a landing zone first: the squads are waiting for one.")
	return n


func launch(t: int) -> int:
	## Put one aircraft of type t in the air from whichever ship (or airfield) has one ready
	for i in sim.count:
		if sim.alive[i] == 0 or sim.side[i] != 0 or sim.utype[i] != t or ferries.has(i):
			continue
		var at := sim.aboard[i]
		if at >= 0 and TexasUnits.is_ship(sim.utype[at]) or at <= -2:
			if sim.fuel[i] < 0.5:
				continue
			sim.aboard[i] = -1
			sim.flags[i] &= ~TexasSim.Flag.LANDED
			sim.x[i] += randf_range(-150.0, 150.0)
			sim.z[i] += randf_range(-150.0, 150.0)
			sim.stop(i)
			returning.erase(i)
			return i
	return -1


func aircraft_ready(t: int) -> int:
	var n := 0
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 0 and sim.utype[i] == t and not ferries.has(i):
			var at := sim.aboard[i]
			if (at >= 0 and TexasUnits.is_ship(sim.utype[at])) or at <= -2:
				n += 1
	return n


func command_move(ids: Array, to: Vector2) -> int:
	## Right-click: everyone selected goes there, spread out so they don't all stand on one spot
	var ok := 0
	var k := 0
	var ks := 0
	# Two or more ships sail together in the fleet's formation
	var fleet := formation._ships(ids)
	if fleet.size() >= 2:
		if formation.start(fleet, to):
			ok += fleet.size()
		else:
			_say("The fleet can't get there by sea.")
	else:
		formation.release(fleet)
	for i in ids:
		if fleet.size() >= 2 and fleet.has(i):
			continue
		if sim.alive[i] == 0 or sim.side[i] != 0:
			continue
		# Aircraft parked on a deck or at an airfield take off and go
		if sim.is_air(i) and (sim.aboard[i] <= -2 or (sim.aboard[i] >= 0 and TexasUnits.is_ship(sim.utype[sim.aboard[i]]))):
			if ferries.has(i):
				continue
			sim.aboard[i] = -1
			sim.flags[i] &= ~TexasSim.Flag.LANDED
			sim.stop(i)
		if sim.aboard[i] != -1:
			continue
		var t: int = sim.utype[i]
		# Spread out by how much room each takes: ships far apart, squads close
		var off := Vector2.ZERO
		if TexasUnits.is_ship(t):
			if ks > 0:
				off = Vector2(cos(ks * 2.1), sin(ks * 2.1)) * 650.0 * ceili(sqrt(ks))
			ks += 1
		elif k > 0:
			var gap := maxf(TexasUnits.foot[t] * 3.0, 18.0)
			off = Vector2(cos(k * 2.4), sin(k * 2.4)) * gap * sqrt(k) * 1.2
			k += 1
		else:
			k += 1
		var p := to + off
		if TexasUnits.is_ship(t) and ks > 1:
			# Find open water round the spot for each ship rather than piling onto the first
			p = to
			for tries in 12:
				var a := ks * 2.1 + tries * 0.9
				var r := 650.0 * ceili(sqrt(ks - 1)) + 300.0 * floorf(tries / 6.0)
				var q := to + Vector2(cos(a), sin(a)) * r
				if TexasSea.is_sea(q):
					p = q
					break
		if sim.order_move(i, p):
			ok += 1
		elif TexasUnits.is_ship(t):
			_say("%s can't get there by sea." % TexasUnits.label(t, 0))
		if sim.is_air(i):
			player_air[i] = sim.time
			returning.erase(i)
		ferries.erase(i)
	return ok


func command_line(ids: Array, pts: PackedVector2Array) -> Dictionary:
	## Right-drag: the selected units spread out evenly along the line drawn, in the order they
	## stand across it (so their paths don't cross). Ships go in formation to its middle; units
	## still aboard a ship go ashore to their spot on it.
	var ships_: Array = formation._ships(ids)
	var units: Array = []
	for i in ids:
		if sim.alive[i] == 0 or sim.side[i] != 0 or TexasUnits.is_ship(sim.utype[i]):
			continue
		var h := sim.aboard[i]
		var aboard_ship := h >= 0 and TexasUnits.is_ship(sim.utype[h])
		if h == -1 or aboard_ship or h <= -2:
			units.append(i)
	# the line's length and a point at any distance along it
	var lens := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		lens.append(lens[k - 1] + pts[k].distance_to(pts[k - 1]))
	var total := lens[lens.size() - 1]
	var at := func(dist: float) -> Vector2:
		for k in range(1, pts.size()):
			if lens[k] >= dist:
				var seg := lens[k] - lens[k - 1]
				return pts[k - 1].lerp(pts[k], (dist - lens[k - 1]) / maxf(seg, 0.001))
		return pts[pts.size() - 1]
	# who goes where: sorted along the line's direction
	var axis := (pts[pts.size() - 1] - pts[0]).normalized()
	units.sort_custom(func(a, b): return Vector2(sim.x[a], sim.z[a]).dot(axis) < Vector2(sim.x[b], sim.z[b]).dot(axis))
	var spots: Array = []
	var moved := 0
	var ashore := [0, 0]
	for k in units.size():
		var i: int = units[k]
		var p: Vector2 = at.call(total * (k + 0.5) / units.size())
		spots.append(p)
		var h := sim.aboard[i]
		if h >= 0 and TexasUnits.is_ship(sim.utype[h]):
			if not TexasSim.is_water(p):
				var r := send_ashore([i], p)
				ashore[0] += r[0]
				ashore[1] += r[1]
			continue
		moved += command_move([i], p)
	if not ships_.is_empty():
		var mid: Vector2 = at.call(total * 0.5)
		moved += command_move(ships_, mid)
	return {"spots": spots, "moved": moved, "ashore": ashore}


func board_nearest(ids: Array) -> int:
	## Squads climb into the nearest friendly transport with room (a vehicle, or a helicopter
	## that's landed or hovering low nearby)
	var n := 0
	for j in ids:
		if sim.alive[j] == 0 or sim.kind[j] != TexasSim.Kind.INFANTRY or sim.aboard[j] != -1:
			continue
		var best := -1
		var best_d := 250.0 * 250.0
		for i in sim.count:
			if i == j or sim.alive[i] == 0 or sim.side[i] != 0 or sim.aboard[i] != -1:
				continue
			var t: int = sim.utype[i]
			if TexasUnits.seats[t] <= 0 or TexasUnits.is_ship(t) or sim.state[i] == TexasSim.State.MOVING:
				continue
			var d := Vector2(sim.x[i] - sim.x[j], sim.z[i] - sim.z[j]).length_squared()
			if d < best_d and sim.can_carry(i, j):
				best_d = d
				best = i
		if best >= 0:
			sim.board(j, best)
			n += 1
	return n


func unload(ids: Array) -> int:
	var n := 0
	for i in ids:
		if sim.alive[i] == 0 or sim.aboard[i] != -1 or TexasUnits.is_ship(sim.utype[i]):
			continue
		if TexasSea.is_sea(Vector2(sim.x[i], sim.z[i])):
			continue
		if sim.is_air(i):
			sim.flags[i] |= TexasSim.Flag.LANDED
			sim.stop(i)
		n += sim.unload(i).size()
	return n


func return_to_base(ids: Array) -> int:
	var n := 0
	for i in ids:
		if sim.alive[i] == 1 and sim.side[i] == 0 and sim.airborne(i):
			if _rtb(i):
				n += 1
	return n


func add_order(t: int, to_company := -1) -> bool:
	## Order a unit for the next delivery, to join a company (or -1: wherever it fits)
	var cost: int = TexasUnits.TYPES[t].cost
	if cost <= 0 or points < cost:
		return false
	points -= cost
	orders.append(t)
	order_to.append(to_company)
	return true


func remove_order(t: int) -> bool:
	var k := orders.rfind(t)
	if k < 0:
		return false
	orders.remove_at(k)
	if k < order_to.size():
		order_to.remove_at(k)
	points += TexasUnits.TYPES[t].cost
	return true


# --- Running ----------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if result != "":
		return
	if sim.time >= next_wave:
		_delivery()
	_ferries(dt)
	formation.update(dt)
	_refits(dt)
	_ships_hit()
	_air_acc += dt
	if _air_acc >= AIR_EVERY:
		_air(_air_acc)
		_air_acc = 0.0
	_zone_acc += dt
	if _zone_acc >= ZONE_CHECK:
		_zones(_zone_acc)
		_zone_acc = 0.0
	_sep_acc += dt
	if _sep_acc >= 5.0:
		_separate()
		_sep_acc = 0.0
	_ai_acc += dt
	if _ai_acc >= AI_EVERY:
		_red_ai()
		_ai_acc = 0.0
	_check_end()


func _separate() -> void:
	## Units that have stopped don't stand inside each other: ships keep their distance, and
	## vehicles, squads and hovering helicopters nudge apart (never out onto the water)
	var ship_list: Array = []
	var cells := {}
	var cell := 40.0
	for i in sim.count:
		if sim.alive[i] == 0 or sim.aboard[i] != -1:
			continue
		var t: int = sim.utype[i]
		if TexasUnits.is_ship(t):
			ship_list.append(i)
			continue
		if sim.state[i] == TexasSim.State.MOVING or TexasUnits.foot[t] <= 0.0:
			continue
		var p := Vector2(sim.x[i], sim.z[i])
		if not slice.has_point(p):
			continue
		var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(i)
	for a in ship_list.size():
		for b in range(a + 1, ship_list.size()):
			_push(ship_list[a], ship_list[b], true)
	for c in cells:
		for dz in [0, 1]:
			for dx in [-1, 0, 1]:
				if dz == 0 and dx < 0:
					continue
				var other = cells.get(c + Vector2i(dx, dz))
				if other == null:
					continue
				var mine: Array = cells[c]
				for i in mine:
					for j in other:
						if (dx == 0 and dz == 0 and j <= i) or sim.is_air(i) != sim.is_air(j):
							continue
						_push(i, j, false)


func _push(i: int, j: int, ships_: bool) -> void:
	var need: float = TexasUnits.foot[sim.utype[i]] + TexasUnits.foot[sim.utype[j]] + (60.0 if ships_ else 3.0)
	var d := Vector2(sim.x[j] - sim.x[i], sim.z[j] - sim.z[i])
	var L := d.length()
	if L >= need:
		return
	if L < 0.01:
		d = Vector2(cos(i * 1.7), sin(i * 1.7))
		L = 1.0
	var n := d / L
	var move := (need - L) * 0.5
	for pair in [[i, -1.0], [j, 1.0]]:
		var u: int = pair[0]
		if ships_ and sim.state[u] == TexasSim.State.MOVING:
			continue
		var q: Vector2 = Vector2(sim.x[u], sim.z[u]) + n * move * pair[1]
		var mv: int = TexasUnits.move[sim.utype[u]]
		if mv == TexasUnits.Move.SEA and not TexasSea.open_water(Vector2(sim.x[u], sim.z[u]), q, 10.0, TexasSea.CLEAR * 0.6):
			continue
		if mv == TexasUnits.Move.GROUND and TexasSim.is_water(q):
			continue
		sim.x[u] = q.x
		sim.z[u] = q.y
		if sim.state[u] != TexasSim.State.MOVING:
			sim.dest_x[u] = q.x
			sim.dest_z[u] = q.y


func _delivery() -> void:
	next_wave += WAVE_EVERY
	points += WAVE_POINTS
	var arrived := {}
	var held: Array = []
	var field := _blue_airfield()
	var held_to: Array = []
	order_to.resize(orders.size())
	for k in orders.size():
		var t: int = orders[k]
		var to = order_to[k]
		var deck: int = TexasUnits.TYPES[t].deck
		var host := -1
		if deck == TexasUnits.Deck.AIRFIELD:
			if field < 0:
				held.append(t)
				held_to.append(to)
				continue
			var i := sim.add_typed(0, t, Vector2(zones[field].x, zones[field].z))
			_park(i, field)
			_join(i, to)
		else:
			host = ships.get("carrier" if deck == TexasUnits.Deck.CARRIER else "amphib", -1)
			if host < 0 or sim.alive[host] == 0:
				host = ships.get("amphib" if deck == TexasUnits.Deck.CARRIER else "carrier", -1)
			if host < 0 or sim.alive[host] == 0:
				held.append(t)
				held_to.append(to)
				continue
			_join(sim.add_typed(0, t, Vector2(sim.x[host], sim.z[host]), host), to)
		var nm := TexasUnits.label(t, 0)
		arrived[nm] = arrived.get(nm, 0) + 1
	orders = held
	order_to = held_to
	if arrived.is_empty():
		_say("Delivery wave: nothing was ordered. %d points to spend." % points)
	else:
		var parts: Array = []
		for nm in arrived:
			parts.append("%d %s" % [arrived[nm], nm])
		_say("Delivery wave arrived at the fleet: %s." % ", ".join(parts))
	if not held.is_empty():
		_say("%d A-10s are waiting for an airfield." % held.size())


func _join(i: int, company) -> void:
	## A new arrival joins the company it was ordered for, or finds one
	if company != null and company is int and company >= 0 and org.nodes.has(company):
		org.assign(i, company)
	else:
		org.settle(i)


func _blue_airfield() -> int:
	for k in zones.size():
		if zones[k].kind == "airfield" and zones[k].owner == 0:
			return k
	return -1


func _ferries(dt: float) -> void:
	## Landing craft and helicopters shuttling the landing force ashore
	var amphib: int = ships.get("amphib", -1)
	var docked := _docked_port()
	# Straight onto the dock when the assault ship is alongside a port you hold
	if docked >= 0 and not (vehicle_queue.is_empty() and troop_queue.is_empty()) and amphib >= 0 and sim.alive[amphib] == 1:
		var dock := Vector2(zones[docked].x, zones[docked].z)
		for j in troop_queue:
			if sim.alive[j] == 1 and sim.aboard[j] == amphib:
				sim.aboard[j] = -1
				var q: Vector2 = TexasSim.nearest_land(dock + Vector2(randf_range(-150.0, 150.0), randf_range(-150.0, 150.0)))
				sim.x[j] = q.x
				sim.z[j] = q.y
				sim.stop(j)
		for j in vehicle_queue:
			if sim.alive[j] == 1 and sim.aboard[j] == amphib:
				sim.aboard[j] = -1
				var q: Vector2 = TexasSim.nearest_land(dock + Vector2(randf_range(-120.0, 120.0), randf_range(-120.0, 120.0)))
				sim.x[j] = q.x
				sim.z[j] = q.y
				sim.stop(j)
				var dv := _dest_of(j)
				if dv.x != INF:
					sim.order_move(j, landing_slot(dv, true))
				ashore_to.erase(j)
		for j in troop_queue:
			ashore_to.erase(j)
		vehicle_queue = PackedInt32Array()
		_say("The assault ship unloaded at %s." % zones[docked].name)
	# Clear out units that are no longer waiting
	vehicle_queue = _still_waiting(vehicle_queue)
	troop_queue = _still_waiting(troop_queue)
	var vdest := _first_dest(vehicle_queue)
	var tdest := _first_dest(troop_queue)
	if vdest.x != INF or tdest.x != INF:
		for i in sim.count:
			if sim.alive[i] == 0 or sim.side[i] != 0 or ferries.has(i) or player_air.has(i):
				continue
			var host := sim.aboard[i]
			if host < 0 or not TexasUnits.is_ship(sim.utype[host]):
				continue
			var t: int = sim.utype[i]
			if TexasUnits.move[t] == TexasUnits.Move.HOVER and vdest.x != INF:
				_start_ferry(i, host, vehicle_queue, vdest)
				vdest = _first_dest(_still_waiting_unferried(vehicle_queue))
			elif TexasUnits.is_air(t) and TexasUnits.seats[t] > 0 and tdest.x != INF and sim.fuel[i] > 0.6:
				_start_ferry(i, host, troop_queue, tdest)
				tdest = _first_dest(_still_waiting_unferried(troop_queue))
	for i in ferries.keys():
		var f: Dictionary = ferries[i]
		if sim.alive[i] == 0:
			ferries.erase(i)
			continue
		match f.stage:
			"out":
				if sim.at_dest(i):
					if sim.is_air(i):
						sim.flags[i] |= TexasSim.Flag.LANDED
					var off := sim.unload(i, 40.0)
					var dest: Vector2 = f.get("to", lz)
					for j in off:
						ashore_to.erase(j)
						if dest.x == INF:
							continue
						# each to its own tidy spot at the landing point, and there it waits
						sim.order_move(j, landing_slot(dest, sim.kind[j] != TexasSim.Kind.INFANTRY))
					f.stage = "unloading"
					f.t = 45.0 if sim.is_air(i) else 90.0
			"unloading":
				f.t -= dt
				if f.t <= 0.0:
					var host: int = f.ship
					if host < 0 or sim.alive[host] == 0:
						host = _any_ship()
					if host < 0:
						ferries.erase(i)
						continue
					f.ship = host
					if TexasUnits.move[sim.utype[i]] == TexasUnits.Move.HOVER and TexasUnits.TYPES[sim.utype[host]].id == "amphib":
						sim.order_move(i, well_points(host)[2])
						f.t = 20.0
					else:
						sim.order_move(i, Vector2(sim.x[host], sim.z[host]))
					f.stage = "back"
			"back":
				var host: int = f.ship
				if sim.alive[host] == 0:
					host = _any_ship()
					if host < 0:
						ferries.erase(i)
						continue
					f.ship = host
				var into_well: bool = TexasUnits.move[sim.utype[i]] == TexasUnits.Move.HOVER and TexasUnits.TYPES[sim.utype[host]].id == "amphib"
				if into_well:
					# landing craft come back in through the stern gate
					var w := well_points(host)
					var dw := Vector2(sim.x[i], sim.z[i]).distance_to(w[0])
					if dw < 45.0:
						sim.board(i, host)
						ferries.erase(i)
					elif sim.at_dest(i) or f.t <= 0.0:
						f.t = 20.0
						if Vector2(sim.x[i], sim.z[i]).distance_to(w[2]) < 120.0 or Vector2(sim.x[i], sim.z[i]).distance_to(w[1]) < 220.0:
							# line up astern and drive in through the gate
							sim.order_direct(i, w[0])
							sim.wps[i] = PackedVector2Array([w[1]])
						else:
							sim.order_move(i, w[2])
					else:
						f.t -= dt
					continue
				var d := Vector2(sim.x[host] - sim.x[i], sim.z[host] - sim.z[i]).length()
				if d < 250.0:
					sim.board(i, host)
					sim.flags[i] &= ~TexasSim.Flag.LANDED
					ferries.erase(i)
				elif sim.at_dest(i):
					sim.order_move(i, Vector2(sim.x[host], sim.z[host]))


func _first_dest(q: PackedInt32Array) -> Vector2:
	## Where the first unit still waiting in this queue is going
	for j in q:
		if sim.alive[j] == 1 and sim.aboard[j] >= 0 and TexasUnits.is_ship(sim.utype[sim.aboard[j]]):
			var d := _dest_of(j)
			if d.x != INF:
				return d
	return Vector2(INF, INF)


func _still_waiting_unferried(q: PackedInt32Array) -> PackedInt32Array:
	return _still_waiting(q)


func _still_waiting(q: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j in q:
		if sim.alive[j] == 1 and sim.aboard[j] >= 0 and TexasUnits.is_ship(sim.utype[sim.aboard[j]]):
			out.append(j)
	return out


func _start_ferry(i: int, host: int, queue: PackedInt32Array, to: Vector2) -> void:
	## Load from its own ship, or (squads) from any ship close by: they cross-deck by boat
	var loaded := 0
	for j in queue:
		var on := sim.aboard[j]
		if on < 0 or sim.alive[on] == 0:
			continue
		if _dest_of(j).distance_to(to) > 400.0:
			continue
		var near := on == host or (sim.kind[j] == TexasSim.Kind.INFANTRY and Vector2(sim.x[on] - sim.x[host], sim.z[on] - sim.z[host]).length() < 4000.0)
		if near and sim.can_carry(i, j):
			sim.aboard[j] = i
			sim._has_riders[i] = true
			loaded += 1
	if loaded == 0:
		return
	sim.aboard[i] = -1
	sim.flags[i] &= ~TexasSim.Flag.LANDED
	var drop := to
	if TexasUnits.is_air(sim.utype[i]):
		# helicopters set down side by side round the spot, not on top of each other
		var n := 0
		for k in ferries:
			if sim.is_air(k) and ferries[k].get("to", Vector2(INF, INF)).distance_to(to) < 400.0:
				n += 1
		drop = TexasSim.nearest_land(to + Vector2.from_angle(n * 2.4) * (45.0 * sqrt(n + 1.0)))
	elif TexasUnits.move[sim.utype[i]] == TexasUnits.Move.HOVER:
		# Spread along the beach: each comes in on its own line, side by side
		# to the water nearest the spot and up the beach there (the route finds it); craft
		# landing at the same place come in side by side
		var from := Vector2(sim.x[host], sim.z[host])
		var n := 0
		for k in ferries:
			if not sim.is_air(k) and ferries[k].get("to", Vector2(INF, INF)).distance_to(to) < 400.0:
				n += 1
		var off := float(n / 2 + n % 2) * 45.0 * (1.0 if n % 2 == 0 else -1.0)
		drop = to + (to - from).normalized().orthogonal() * off
		if TexasUnits.TYPES[sim.utype[host]].id == "amphib":
			# out of the well deck through the stern gate, then away
			var w := well_points(host)
			sim.x[i] = w[0].x
			sim.z[i] = w[0].y
			sim.px[i] = sim.x[i]
			sim.pz[i] = sim.z[i]
			sim.heading[i] = wrapf(sim.heading[host] + PI, -PI, PI)
			sim.order_move(i, drop, PackedVector2Array([w[1], w[2]]))
			ferries[i] = {"stage": "out", "ship": host, "t": 0.0, "to": to}
			return
	sim.order_move(i, drop)
	ferries[i] = {"stage": "out", "ship": host, "t": 0.0, "to": to}


func well_points(host: int) -> Array:
	## The assault ship's well deck, in map metres: [inside the dock, the stern gate, clear astern]
	var h: float = sim.heading[host]
	var aft := Vector2(sin(h), cos(h))
	var c := Vector2(sim.x[host], sim.z[host])
	return [c + aft * 108.0, c + aft * 135.0, c + aft * 330.0]


func _any_ship() -> int:
	for role in ["amphib", "carrier", "cruiser", "destroyer0", "destroyer1"]:
		if ship_alive(role):
			return ships[role]
	return -1


func _docked_port() -> int:
	var amphib: int = ships.get("amphib", -1)
	if amphib < 0 or sim.alive[amphib] == 0:
		return -1
	for k in zones.size():
		var z: Dictionary = zones[k]
		if z.kind == "port" and z.owner == 0:
			if Vector2(z.x - sim.x[amphib], z.z - sim.z[amphib]).length() < 4000.0:
				return k
	return -1


func _refits(dt: float) -> void:
	## Aircraft refuel and rearm aboard ship or at an airfield you hold; vehicles top up and
	## patch up in a port or airfield you hold
	for i in sim.count:
		if sim.alive[i] == 0:
			continue
		var t: int = sim.utype[i]
		var at := sim.aboard[i]
		var base := false
		if at >= 0:
			base = TexasUnits.is_ship(sim.utype[at])
		elif at <= -2:
			base = zones[-2 - at].owner == sim.side[i]
		if base and TexasUnits.is_air(t):
			var rt: float = TexasUnits.refit[t]
			sim.fuel[i] = minf(1.0, sim.fuel[i] + dt / rt)
			sim.strength[i] = minf(1.0, sim.strength[i] + dt / (rt * 2.0))


func _ships_hit() -> void:
	for role in ships:
		var i: int = ships[role]
		var was: float = _ship_hp.get(i, 1.0)
		if sim.alive[i] == 0:
			if was > 0.0:
				_say("%s has been sunk!" % _ship_name(role), true)
				_ship_hp[i] = 0.0
			continue
		var s: float = sim.strength[i]
		if s < was - 0.08:
			_say("%s hit: %d%% left." % [_ship_name(role), int(s * 100.0)], true)
			_ship_hp[i] = s


func _ship_name(role: String) -> String:
	if role.begins_with("destroyer"):
		return SHIP_NAMES.destroyer[int(role.substr(9))]
	return SHIP_NAMES[role]


func ship_title(i: int) -> String:
	for role in ships:
		if ships[role] == i:
			return "%s (%s)" % [_ship_name(role), TexasUnits.label(sim.utype[i], 0)]
	return TexasUnits.label(sim.utype[i], sim.side[i])


func _rtb(i: int) -> bool:
	## Send an aircraft home: the nearest ship (or for jets the carrier) or an airfield its side holds
	var t: int = sim.utype[i]
	var p := Vector2(sim.x[i], sim.z[i])
	var best := ""
	var best_d := INF
	var best_p := Vector2.ZERO
	if sim.side[i] == 0:
		for role in ships:
			var s: int = ships[role]
			if sim.alive[s] == 0:
				continue
			if sim.kind[i] == TexasSim.Kind.JET and role != "carrier":
				continue
			if TexasUnits.TYPES[t].deck == TexasUnits.Deck.AIRFIELD:
				continue
			var d := p.distance_to(Vector2(sim.x[s], sim.z[s]))
			if d < best_d:
				best_d = d
				best = "s%d" % s
				best_p = Vector2(sim.x[s], sim.z[s])
	for k in zones.size():
		var z: Dictionary = zones[k]
		if z.kind != "airfield" or z.owner != sim.side[i]:
			continue
		var d := p.distance_to(Vector2(z.x, z.z))
		if d < best_d:
			best_d = d
			best = "z%d" % k
			best_p = Vector2(z.x, z.z)
	if best == "":
		return false
	returning[i] = best
	player_air.erase(i)
	sim.order_move(i, best_p)
	return true


func _air(dt: float) -> void:
	## Every few seconds: aircraft heading home, landing, combat air patrol over the fleet,
	## and Red's raids steering onto their targets
	var carrier: int = ships.get("carrier", -1)
	var red_jets: Array = []
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 1 and sim.kind[i] == TexasSim.Kind.JET and sim.aboard[i] == -1:
			red_jets.append(i)
	for i in sim.count:
		if sim.alive[i] == 0 or not sim.airborne(i):
			continue
		# Low on fuel: home
		if sim.fuel[i] < BINGO_FUEL and not returning.has(i) and not ferries.has(i):
			if _rtb(i) and sim.side[i] == 0:
				_say("%s is low on fuel and heading back to refuel." % TexasUnits.label(sim.utype[i], 0))
		if returning.has(i):
			var base: String = returning[i]
			var bp: Vector2
			if base.begins_with("s"):
				var s := int(base.substr(1))
				if sim.alive[s] == 0:
					returning.erase(i)
					_rtb(i)
					continue
				bp = Vector2(sim.x[s], sim.z[s])
				var dist := Vector2(sim.x[i], sim.z[i]).distance_to(bp)
				if dist < 300.0 or (sim.at_dest(i) and dist < 3000.0):
					sim.board(i, s)
					returning.erase(i)
					continue
				sim.dest_x[i] = bp.x
				sim.dest_z[i] = bp.y
				sim.state[i] = TexasSim.State.MOVING
			else:
				var k := int(base.substr(1))
				var z: Dictionary = zones[k]
				if z.owner != sim.side[i]:
					returning.erase(i)
					_rtb(i)
					continue
				if sim.at_dest(i):
					_park(i, k)
					returning.erase(i)
			continue
		# Your fighters guard the fleet unless you've sent them somewhere
		if sim.side[i] == 0 and sim.kind[i] == TexasSim.Kind.JET and sim.utype[i] == TexasUnits.id("hornet"):
			if player_air.has(i) and sim.time - player_air[i] < 600.0:
				continue
			player_air.erase(i)
			if carrier < 0 or sim.alive[carrier] == 0:
				continue
			var cp := Vector2(sim.x[carrier], sim.z[carrier])
			var threat := -1
			var td := 35000.0
			for j in red_jets:
				var d := cp.distance_to(Vector2(sim.x[j], sim.z[j]))
				if d < td:
					td = d
					threat = j
			if threat >= 0:
				sim.dest_x[i] = sim.x[threat]
				sim.dest_z[i] = sim.z[threat]
				sim.state[i] = TexasSim.State.MOVING
			elif sim.at_dest(i):
				var a := sim.time * 0.01 + i
				sim.order_move(i, cp + Vector2(cos(a), sin(a)) * 6000.0)
	# Red raids: keep steering onto the target, then go home
	for r in raids.duplicate():
		var live: Array = []
		for j in r.units:
			if sim.alive[j] == 1 and sim.aboard[j] == -1 and not returning.has(j):
				live.append(j)
		if live.is_empty() or sim.time > r.until:
			for j in live:
				_rtb(j)
			raids.erase(r)
			continue
		var tp := _raid_target_pos(r)
		if tp.x == INF:
			for j in live:
				_rtb(j)
			raids.erase(r)
			continue
		for j in live:
			sim.dest_x[j] = tp.x
			sim.dest_z[j] = tp.y
			sim.wps[j] = PackedVector2Array()
			sim.state[j] = TexasSim.State.MOVING


func _raid_target_pos(r: Dictionary) -> Vector2:
	var t = r.target
	if t is int:
		if sim.alive[t] == 0:
			# Their ship went down: the nearest other ship
			var best := -1
			var bd := INF
			for role in ships:
				var s: int = ships[role]
				if sim.alive[s] == 1:
					var d := Vector2(sim.x[s] - sim.x[r.units[0]], sim.z[s] - sim.z[r.units[0]]).length()
					if d < bd:
						bd = d
						best = s
			if best < 0:
				return Vector2(INF, INF)
			r.target = best
			t = best
		return Vector2(sim.x[t], sim.z[t])
	return t


func _zones(dt: float) -> void:
	## Who holds each place: a side takes it by having ground units there and the other side none
	var counts: Array = []
	for z in zones:
		counts.append([0, 0])
	for i in sim.count:
		if sim.alive[i] == 0 or sim.aboard[i] != -1 or TexasUnits.move[sim.utype[i]] != TexasUnits.Move.GROUND:
			continue
		var p := Vector2(sim.x[i], sim.z[i])
		if not slice.has_point(p):
			continue
		for k in zones.size():
			var z: Dictionary = zones[k]
			var dx: float = p.x - z.x
			var dz: float = p.y - z.z
			if dx * dx + dz * dz < z.r * z.r:
				counts[k][sim.side[i]] += 1
	for k in zones.size():
		var z: Dictionary = zones[k]
		var mine: int = counts[k][0]
		var theirs: int = counts[k][1]
		var attacker := 1 - int(z.owner)
		var att_n: int = counts[k][attacker]
		var def_n: int = counts[k][z.owner]
		if att_n > 0 and def_n == 0:
			z.progress += dt / CAPTURE_TIME
			if z.progress >= 1.0:
				z.owner = attacker
				z.progress = 0.0
				_captured(k)
		else:
			z.progress = maxf(0.0, z.progress - dt / CAPTURE_TIME)
		z.blue_here = mine
		z.red_here = theirs


func _captured(k: int) -> void:
	var z: Dictionary = zones[k]
	var who := "You have taken" if z.owner == 0 else "Red has retaken"
	var what: String = {"port": "the port of", "airfield": "the airfield", "town": ""}[z.kind]
	_say(("%s %s %s." % [who, what, z.name]).replace("  ", " "), z.owner == 1)
	# Enemy aircraft parked there are lost
	for i in sim.count:
		if sim.alive[i] == 1 and sim.aboard[i] == -2 - k and sim.side[i] != z.owner:
			sim._kill(i)
	if z.owner == 0 and z.kind == "airfield":
		_say("%s can now take A-10s, and your aircraft can refuel there." % z.name)
	if z.owner == 0 and z.kind == "port":
		_say("Bring the assault ship close to %s to unload straight onto the dock." % z.name)


func _auto_engage() -> void:
	## Ground units standing idle go after enemy ground units close by (1.5 km), on both sides,
	## so a place isn't held forever by a straggler just out of range. Red garrisons stay put
	## unless the enemy is inside their own town.
	var blue: Array = []
	var red: Array = []
	for i in sim.count:
		if sim.alive[i] == 0 or sim.aboard[i] != -1 or TexasUnits.move[sim.utype[i]] != TexasUnits.Move.GROUND:
			continue
		if not slice.has_point(Vector2(sim.x[i], sim.z[i])):
			continue
		(blue if sim.side[i] == 0 else red).append(i)
	# (only Red's: your units hold where you put them and shoot at what's in range)
	for pair in [[red, blue]]:
		for i in pair[0]:
			if sim.state[i] != TexasSim.State.IDLE or TexasUnits.max_range[sim.utype[i]] <= 0.0:
				continue
			var reach := 1500.0 if (sim.side[i] == 0 or not (sim.flags[i] & TexasSim.Flag.GARRISON)) else 900.0
			var best := -1
			var bd := reach * reach
			for j in pair[1]:
				var d := Vector2(sim.x[j] - sim.x[i], sim.z[j] - sim.z[i]).length_squared()
				if d < bd:
					bd = d
					best = j
			if best >= 0 and bd > pow(TexasUnits.rng[sim.utype[i] * 6 + sim.kind[best]] * 0.8, 2.0):
				sim.order_move(i, Vector2(sim.x[best], sim.z[best]))
	# Inside a place both sides are in, the attackers clear out every last defender
	for z in zones:
		var zc := Vector2(z.x, z.z)
		var r2: float = z.r * z.r
		var mine: Array = []
		var theirs: Array = []
		if z.owner == 1:
			continue                       # Red retaking its own places; yours wait for orders
		for i in red:
			if Vector2(sim.x[i], sim.z[i]).distance_squared_to(zc) < r2:
				mine.append(i)
		if mine.is_empty():
			continue
		for j in blue:
			if Vector2(sim.x[j], sim.z[j]).distance_squared_to(zc) < r2:
				theirs.append(j)
		if theirs.is_empty():
			continue
		for i in mine:
			if sim.state[i] != TexasSim.State.IDLE or TexasUnits.max_range[sim.utype[i]] <= 0.0:
				continue
			var best := -1
			var bd := INF
			for j in theirs:
				var d := Vector2(sim.x[j] - sim.x[i], sim.z[j] - sim.z[i]).length_squared()
				if d < bd:
					bd = d
					best = j
			if best >= 0 and bd > 150.0 * 150.0:
				sim.order_move(i, Vector2(sim.x[best], sim.z[best]))


func _red_ai() -> void:
	## Red's commander: send reserves at your strongest pushes, launch jets at the fleet and
	## attack helicopters at your troops
	_auto_engage()
	var cells := {}
	for i in sim.count:
		if sim.alive[i] == 0 or sim.side[i] != 0 or sim.aboard[i] != -1:
			continue
		if TexasUnits.move[sim.utype[i]] != TexasUnits.Move.GROUND:
			continue
		var p := Vector2(sim.x[i], sim.z[i])
		if not slice.has_point(p):
			continue
		var c := Vector2i(floori(p.x / 4000.0), floori(p.y / 4000.0))
		if not cells.has(c):
			cells[c] = [0.0, Vector2.ZERO, 0]
		cells[c][0] += TexasUnits.hp[sim.utype[i]] * sim.strength[i]
		cells[c][1] += p
		cells[c][2] += 1
	var threats: Array = []
	for c in cells:
		threats.append([cells[c][0], cells[c][1] / cells[c][2]])
	threats.sort_custom(func(a, b): return a[0] > b[0])
	var free: Array = []
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 1 and (sim.flags[i] & TexasSim.Flag.RESERVE) and sim.aboard[i] == -1:
			if not assigned.has(i) or sim.time - assigned[i] > 1200.0:
				free.append(i)
	for th in threats.slice(0, 3):
		var at: Vector2 = th[1]
		var need: float = th[0] * 1.3
		free.sort_custom(func(a, b): return Vector2(sim.x[a], sim.z[a]).distance_squared_to(at) < Vector2(sim.x[b], sim.z[b]).distance_squared_to(at))
		var sent := 0.0
		while sent < need and not free.is_empty():
			var i: int = free.pop_front()
			if Vector2(sim.x[i], sim.z[i]).distance_to(at) > 45000.0:
				break
			sim.order_move(i, at + Vector2(randf_range(-400, 400), randf_range(-400, 400)))
			assigned[i] = sim.time
			sent += TexasUnits.hp[sim.utype[i]]
	# Air: each Red airfield sends its ready jets after the fleet now and then, and its attack
	# helicopters after your troops
	for k in zones.size():
		var z: Dictionary = zones[k]
		if z.kind != "airfield" or z.owner != 1 or sim.time < raid_timer.get(k, 0.0):
			continue
		raid_timer[k] = sim.time + randf_range(1500.0, 2700.0)
		var jets: Array = []
		var helis: Array = []
		for i in sim.count:
			if sim.alive[i] == 1 and sim.side[i] == 1 and sim.aboard[i] == -2 - k and sim.fuel[i] > 0.9:
				if sim.kind[i] == TexasSim.Kind.JET:
					jets.append(i)
				elif sim.kind[i] == TexasSim.Kind.HELI:
					helis.append(i)
		var target = null
		var carrier: int = ships.get("carrier", -1)
		if jets.size() >= 2 and _any_ship() >= 0:
			target = carrier if carrier >= 0 and sim.alive[carrier] == 1 else _any_ship()
			var sortie := jets.slice(0, 2)
			_launch_raid(sortie, target, 420.0, k)
			_say("Red jets are taking off from %s, heading for the fleet!" % z.name, true)
		if helis.size() >= 1 and not threats.is_empty():
			var at: Vector2 = threats[0][1]
			if at.distance_to(Vector2(z.x, z.z)) < 40000.0:
				_launch_raid(helis.slice(0, 2), at, 600.0, k)
				_say("Red attack helicopters are heading for your troops.", true)


func _launch_raid(units: Array, target, stay: float, base: int) -> void:
	for i in units:
		sim.aboard[i] = -1
		sim.flags[i] &= ~TexasSim.Flag.LANDED
		sim.stop(i)
	var tp: Vector2 = Vector2(sim.x[target], sim.z[target]) if target is int else target
	var dist := Vector2(sim.x[units[0]], sim.z[units[0]]).distance_to(tp)
	var t := dist / TexasUnits.speed[sim.utype[units[0]]] + stay
	raids.append({"units": units, "target": target, "until": sim.time + t, "base": base})


func _check_end() -> void:
	var h := zone_named("Houston")
	if h >= 0 and zones[h].owner == 0:
		result = "won"
		_say("Downtown Houston is yours. The landing has broken through: Galveston to Houston, done.", true)
		return
	if not ship_alive("carrier"):
		result = "lost"
		_say("The carrier is lost. Without it the fleet can't support the landing: the operation has failed.", true)


# --- Status for the screen ------------------------------------------------------------------------

func objectives_text() -> String:
	var lines: Array = []
	for z in zones:
		if not z.objective:
			continue
		var state := "taken" if z.owner == 0 else ("taking %d%%" % int(z.progress * 100.0) if z.progress > 0.0 and z.owner == 1 else "Red")
		lines.append("%s %s: %s" % ["■" if z.owner == 0 else "□", z.name, state])
	return "\n".join(lines)


func next_wave_in() -> float:
	return next_wave - sim.time


func ship_cargo(role: String) -> Dictionary:
	## Counts by type label of what's aboard a ship (including inside its landing craft)
	var out := {}
	if not ship_alive(role):
		return out
	var s: int = ships[role]
	for j in sim.count:
		if sim.alive[j] == 0:
			continue
		var at := sim.aboard[j]
		if at == s or (at >= 0 and sim.aboard[at] == s and not ferries.has(at)):
			var nm := TexasUnits.label(sim.utype[j], 0)
			out[nm] = out.get(nm, 0) + 1
	return out


# --- Saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"ships": ships, "zones": zones, "lz": lz, "vq": vehicle_queue, "tq": troop_queue,
		"ferries": ferries, "returning": returning, "player_air": player_air, "orders": orders, "order_to": order_to, "ashore_to": ashore_to, "org": org.to_dict(),
		"points": points, "next_wave": next_wave, "raids": raids, "raid_timer": raid_timer,
		"assigned": assigned, "result": result, "ship_hp": _ship_hp, "slice": slice,
		"formation": formation.to_dict()}


func from_dict(d: Dictionary) -> void:
	ships = d.ships
	zones = d.zones
	lz = d.lz
	vehicle_queue = d.vq
	troop_queue = d.tq
	ferries = d.ferries
	returning = d.returning
	player_air = d.player_air
	orders = d.orders
	order_to = d.get("order_to", [])
	ashore_to = d.get("ashore_to", {})
	org.from_dict(d.get("org", {}))
	points = d.points
	next_wave = d.next_wave
	raids = d.raids
	raid_timer = d.raid_timer
	assigned = d.assigned
	result = d.result
	_ship_hp = d.ship_hp
	slice = d.slice
	formation.from_dict(d.get("formation", {}))
