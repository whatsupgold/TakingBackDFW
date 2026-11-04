class_name A10
extends AnimatableBody3D
## A-10 Thunderbolt II, flying from a runway slot at the FOB.
##
## Gun run: press V, then drag a line across the target (or just click: a 70 m run toward the
## point). The jet takes off, lines up behind the start of the line and walks its 30 mm
## cannon down it. It's the main tank killer: rifles and machine guns can't touch tanks.
## It hurts anything on the line, yours included.
## Each sortie carries ammo for 2 gun runs and fuel for about 2.5 minutes in the air.
## Between runs it orbits nearby, ready for the next call. Out of ammo or low on fuel, it flies
## back, lands, taxis to its slot, and spends REARM_TIME refuelling and rearming.
##
## Orbit order: select it and right-click a spot. It flies there (taking off first if it's
## parked and ready) and circles that spot until it's out of ammo or needs fuel; after a gun
## run it comes back to the same spot.
## Force stay (X): it ignores bingo fuel and Winchester and keeps circling until it has only
## just enough fuel to get home (about 20 s more on station). Without a runway it never
## leaves anyway. Force stay switches off once it heads home.

signal message(text: String)
signal ejected(jet: A10, at: Vector3)     # out of fuel with nowhere to land: the pilot bails out

const CRUISE_ALT := 70.0
const RUN_ALT := 24.0
const CRUISE_SPEED := 187.8       # m/s: 420 mph (the maps are real size)
const RUN_SPEED := 154.0          # about 300 knots down the gun line
const TAKEOFF_SPEED := 38.0        # (short-field: the FOB runway is only 96 m)
const APPROACH_SPEED := 75.0
const ROLL_ACCEL := 14.0
const TURN_RATE := 1.1             # rad/s (only for turning on the ground)
const GRAVITY := 9.81
const MAX_G := 6.0                 # hard turns and pull-outs (the A-10 is rated to 7.33 g)
const ROLL_RATE := 1.8             # rad/s it rolls into and out of a bank
const CRUISE_BANK := 1.13          # 65 degrees: a normal working turn
const HARD_BANK := 1.40            # 80 degrees: as hard as it can turn (6 g)
const LOITER_SPEED := 100.0        # m/s circling on station (about 195 knots)
const DIVE_ANGLE := 0.35           # radians (20 degrees) down the gun line
const CLIMB_RATE := 14.0
const MAX_FUEL := 150.0            # seconds in the air
const RUNS_PER_SORTIE := 2
const REARM_TIME := 35.0
const RUN_LEAD := 1400.0          # the straight run-in it lines up on before the target            # metres behind the line where it lines up
const AIM_AHEAD := 55.0            # how far ahead of the jet the shells land
const ROUNDS_PER_RUN := 50
const SPREAD := 2.2
const IMPACT_RADIUS := 3.2
const DMG_SOLDIER := 120.0
const DMG_VEHICLE := 30.0
const DMG_TANK := 40.0             # per round, close up: a tank on the line dies to one run
const DMG_STRUCTURE := 22.0       # per round to walls and gates
const LOITER_RADIUS := 520.0       # at loiter speed that is a 65-degree bank
const MAX_HP := 120.0
var max_hp := MAX_HP
const SEATS := [{"role": "Pilot", "pos": Vector3(0, 2.6, -4.0), "visible": false, "exposed": "never"}]

var enemy: RedArmy
var model: VehicleModel
var crew: Crew
var selected := false
var display_name := "A-10"
var callsign := "Hog 1"
var stack := 0                     # 0 for Hog 1, 1 for Hog 2...: spreads orbits so jets don't stack up
var slot_index := 0                # which runway slot it parks in
var slot_key := ""                 # runway slot it owns ("" = none yet)
var has_slot := false
const START_FUEL := 300.0          # the sortie you start the mission with: 5 minutes to get a runway built
var _ferry := false                # flying in as a reinforcement: ready as soon as it parks
var state := "parked"              # parked, takeoff, transit, run, egress, loiter, rtb, final, rollout, taxi
var fuel := MAX_FUEL
var runs_left := RUNS_PER_SORTIE
var rearm_left := 0.0
var kills := 0
var hp := MAX_HP
var destroyed := false
var speed := 0.0

# Runway slot (set by assign_slot)
var slot_pos := Vector3.ZERO
var slot_yaw := 0.0
var runway_dir := Vector3.RIGHT     # takeoff direction from the slot
var runway_far := Vector3.ZERO      # far end of the runway from the slot

var _pos := Vector3.ZERO
var _yaw := 0.0
var _alt := 0.0
var _bank := 0.0                   # roll, + = left wing down (turning left)
var _pitch := 0.0                  # + = nose up
var _load := 1.0                   # g in the turn
var _reattack := false
var _land_from_far := true         # which end it lands from (picked away from Red anti-air)
var _landing_set := false
var _outbound := false             # flying back out to set up a longer final approach
var _run_start := Vector3.ZERO
var _run_end := Vector3.ZERO
var _has_run := false
var _fired := 0
var _egress_t := 0.0
var _loiter_center := Vector3.ZERO
var _ring: MeshInstance3D
var _smoke_t := 0.0
var _bingo_warned := false
var _supplied := false             # this rearm's ammo and fuel have come out of the FOB stock
var _supply_cd := 0.0
var _supply_warned := false
var station := Vector3.ZERO        # orbit point you ordered (see order_orbit)
var has_station := false
var force_stay := false
var _stay_warned := false
const STAY_MARGIN := 4.0           # seconds of spare fuel kept when forced to stay (normally 25)


func place_on_runway(slot: Vector3, dir: Vector3, far_end: Vector3) -> void:
	assign_slot(slot, dir, far_end, "test")
	_pos = slot
	_yaw = slot_yaw
	_alt = 0.0
	state = "parked"
	_apply_transform()


func assign_slot(slot: Vector3, dir: Vector3, far_end: Vector3, key: String) -> void:
	## A parking slot on a built runway: from now on it lands there to refuel and rearm
	slot_pos = slot
	runway_dir = dir.normalized()
	runway_far = far_end
	slot_yaw = atan2(-runway_dir.x, -runway_dir.z)
	slot_key = key
	has_slot = true


func start_airborne(over: Vector3, fuel_s: float) -> void:
	## Mission start: on station over your start area, with no runway to go home to yet
	# Each jet starts at its own point on the orbit (golden-angle spacing), at its own height
	var a := stack * 2.4
	_loiter_center = _in_map(Vector3(over.x, 0.0, over.z))
	_pos = _loiter_center + Vector3(cos(a), 0.0, sin(a)) * _orbit_radius()
	_alt = _orbit_alt()
	speed = LOITER_SPEED
	fuel = fuel_s
	runs_left = RUNS_PER_SORTIE
	_yaw = PI - a     # already flying along the orbit
	_bank = CRUISE_BANK
	state = "loiter"
	_apply_transform()


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 8
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 3.0, 15.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 2.0, 0)
	add_child(col)
	model = HeliModels.a10()
	add_child(model)
	_ring = GroundVehicle._make_ring(9.0, Color(0.75, 0.85, 1.0))
	add_child(_ring)
	crew = Crew.new(callsign, Color(0.55, 0.60, 0.68), SEATS)
	crew.squad.progression = false
	crew.squad.kind = "aircrew"
	crew.spawn(self, enemy)


func set_selected(value: bool) -> void:
	selected = value and not destroyed
	_ring.visible = selected


func order_orbit(p: Vector3) -> String:
	## Fly to p and circle it. Returns "" if accepted, otherwise why not.
	if destroyed or state == "crash":
		return "%s is down" % callsign
	if crew.count() == 0:
		return "%s has no pilot" % callsign
	match state:
		"parked":
			if rearm_left > 0.0:
				return "%s is refuelling and rearming (%d s)" % [callsign, ceili(rearm_left)]
		"rtb", "final", "rollout", "taxi":
			if _must_leave():
				return "%s is %s and has to land" % [callsign, "Winchester" if runs_left == 0 else "low on fuel"]
		"takeoff":
			pass
	station = _in_map(Vector3(p.x, 0.0, p.z))
	has_station = true
	_loiter_center = station
	match state:
		"parked":
			state = "takeoff"
			speed = 0.0
			_has_run = false
		"loiter", "egress", "rtb", "final":
			state = "loiter"
		"transit", "run":
			pass               # finishes the gun run, then comes back here
	return ""


func toggle_force_stay() -> bool:
	force_stay = not force_stay
	_stay_warned = false
	return force_stay


func on_station() -> bool:
	## Circling its orbit (not just flying toward it)
	return state == "loiter" and Vector2(_pos.x - _loiter_center.x, _pos.z - _loiter_center.z).length() < _orbit_radius() * 1.6


func stop() -> void:
	pass


func is_targetable() -> bool:
	return not destroyed and _alt < 1.0


func is_ready() -> bool:
	## Can take a new gun run right now
	if destroyed or crew.count() == 0:
		return false
	if state == "parked":
		return rearm_left <= 0.0
	return (state == "loiter" or state == "egress") and runs_left > 0 and not _must_leave()


func status_text() -> String:
	if destroyed:
		return "DESTROYED"
	match state:
		"parked":
			if rearm_left > 0.0 and not _supplied:
				return "waiting for ammo / fuel"
			return "READY" if rearm_left <= 0.0 else "rearming %ds" % ceili(rearm_left)
		"takeoff":
			return "taking off"
		"transit":
			return "inbound"
		"run":
			return "GUN RUN"
		"crash":
			return "CRASHING"
		"egress", "loiter":
			var where := "on station" if state == "egress" or on_station() else "en route"
			if force_stay:
				where += " (staying)"
			if not has_slot:
				return "%s, %ds fuel" % [where, ceili(fuel)]
			return where
		"rtb", "final":
			return "returning"
		"rollout", "taxi":
			return "landing"
	return state


func add_kill() -> void:
	kills += 1
	crew.squad.add_kill()


func arrive_from(p: Vector3, loiter_at: Vector3) -> void:
	## Reinforcement: appear in the air over `p`. With a runway slot it flies in and lands;
	## without one it goes on station over `loiter_at` and the fuel clock starts.
	_ferry = has_slot
	_pos = Vector3(p.x, 0.0, p.z)
	_alt = CRUISE_ALT
	speed = CRUISE_SPEED
	fuel = MAX_FUEL
	runs_left = RUNS_PER_SORTIE
	_loiter_center = _in_map(Vector3(loiter_at.x, 0.0, loiter_at.z))
	var to := (_approach_point() if has_slot else _loiter_center) - _pos
	_yaw = atan2(-to.x, -to.z)
	state = "rtb" if has_slot else "loiter"
	_apply_transform()


# --- Orders -------------------------------------------------------------------------

func call_run(from: Vector3, to: Vector3) -> String:
	## Returns "" if accepted, otherwise why not
	if not is_ready():
		return "%s not available" % display_name
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if dir.length() < 10.0:
		# A click, not a line: make a 70 m run toward the point, from where the jet is coming
		var approach := Vector3(from.x - _pos.x, 0.0, from.z - _pos.z)
		if approach.length() < 1.0:
			approach = runway_dir
		dir = approach.normalized() * 70.0
		from = from - dir * 0.5
		to = from + dir
	_run_start = Vector3(from.x, 0.0, from.z)
	_run_end = Vector3(to.x, 0.0, to.z)
	_has_run = true
	_fired = 0
	if state == "parked":
		state = "takeoff"
		speed = 0.0
		message.emit("%s rolling for a gun run" % callsign)
	else:
		state = "transit"
		message.emit("%s inbound for a gun run" % callsign)
	return ""


# --- Flight -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if destroyed:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.6
			enemy.gibs.smoke(global_position + Vector3.UP * 2.0)
		return
	if state != "parked" and state != "taxi" and _alt > 0.5:
		fuel -= delta
		if not has_slot:
			for mark in [60.0, 30.0]:
				if fuel <= mark and fuel + delta > mark:
					message.emit("%s: %d seconds of fuel left and no runway to land on!" % [callsign, int(mark)])
		if fuel <= 0.0 and state != "crash":
			_bail_out()
	var turn := 0.0
	match state:
		"parked":
			speed = 0.0
			if rearm_left > 0.0 and not _supplied:
				# Rearming takes a full load of 30 mm and fuel from the FOB's stock
				_supply_cd -= delta
				if _supply_cd <= 0.0:
					_supply_cd = 1.0
					var f := Fob.current
					if f == null or (f.stock.ammo >= Fob.A10_ROUNDS and f.stock.fuel >= Fob.A10_FUEL):
						if f != null:
							f.take_stock("ammo", Fob.A10_ROUNDS)
							f.take_stock("fuel", Fob.A10_FUEL)
						_supplied = true
						_supply_warned = false
					elif not _supply_warned:
						_supply_warned = true
						message.emit("%s can't rearm: the FOB needs %d rounds and %d gal of fuel (airdrop more)" % [callsign, Fob.A10_ROUNDS, Fob.A10_FUEL])
			elif rearm_left > 0.0:
				rearm_left -= delta
				if rearm_left <= 0.0:
					fuel = MAX_FUEL
					runs_left = RUNS_PER_SORTIE
					message.emit("%s refuelled and rearmed: ready" % callsign)
		"takeoff":
			speed = minf(speed + ROLL_ACCEL * delta, CRUISE_SPEED)
			_pos += runway_dir * speed * delta
			if speed > TAKEOFF_SPEED:
				_alt = minf(_alt + CLIMB_RATE * 0.8 * delta, CRUISE_ALT)
			if _alt > 30.0:
				state = "transit" if _has_run else "loiter"
				_loiter_center = station if has_station else _in_map(_pos)
		"transit":
			# Line up on the run-in: follow the line from RUN_LEAD out to the start of the run
			var entry := _run_start - _run_dir() * RUN_LEAD
			var u := _line_param(entry, _run_start)
			if u > 0.95 and _heading().dot(_run_dir()) < 0.95:
				_reattack = true          # overshot without lining up: go back out and come in again
			if _reattack and u < 0.15:
				_reattack = false
			var aim := entry if _reattack else _line_carrot(entry, _run_start, 450.0)
			turn = _steer_to(aim, delta, true)
			_fly(CRUISE_SPEED, CRUISE_ALT, delta)
			if not _reattack and u > 0.3 and u < 0.97 and _heading().dot(_run_dir()) > 0.97 and _line_offset(entry, _run_start) < 40.0:
				state = "run"
		"run":
			turn = _steer_to(_line_carrot(_run_start, _run_end + _run_dir() * 300.0, 200.0), delta, true)
			var along := _along(_pos)
			# Push over into a 20-degree dive so it reaches gun height as the shells reach the line
			var dive_from := -AIM_AHEAD - (CRUISE_ALT - RUN_ALT) / tan(DIVE_ANGLE)
			var want_alt := CRUISE_ALT if along < dive_from else lerpf(CRUISE_ALT, RUN_ALT, clampf((along - dive_from) / (-AIM_AHEAD - dive_from), 0.0, 1.0))
			_fly(RUN_SPEED, want_alt, delta, 4.0)
			_shoot()
			var length := _run_length()
			if along + AIM_AHEAD > length:
				_end_run()
		"egress":
			# Pull off the target in a climbing turn toward its orbit, away from anti-air
			turn = _steer_to(_loiter_center, delta, true)
			_fly(CRUISE_SPEED, CRUISE_ALT, delta, 2.0)
			_egress_t -= delta
			if _egress_t <= 0.0:
				state = "rtb" if _must_leave() else "loiter"
				if state == "rtb":
					message.emit("%s %s, returning to base" % [callsign, "Winchester (out of ammo)" if runs_left == 0 else "low on fuel"])
				elif not has_slot and runs_left == 0:
					message.emit("%s Winchester with no runway to land on: build one before its fuel runs out" % callsign)
		"crash":
			# Nose down into the ground, still moving forward
			speed = move_toward(speed, 60.0, 5.0 * delta)
			_pos += _heading() * speed * delta
			_alt = maxf(0.0, _alt - 22.0 * delta)
			_bank += delta * 1.5
			if _alt <= 0.0:
				_crash_land()
				return
		"loiter":
			var to_c := _pos - _loiter_center
			to_c.y = 0.0
			var tangent := Vector3(-to_c.z, 0.0, to_c.x).normalized()
			var aim := _loiter_center + to_c.normalized() * _orbit_radius() + tangent * 300.0
			turn = _steer_to(aim, delta)
			# Far from its orbit point: fly there at full speed, then circle at loiter speed
			_fly(CRUISE_SPEED if not on_station() else LOITER_SPEED, _orbit_alt(), delta)
			if force_stay and has_slot and not _stay_warned and (_bingo() or runs_left == 0):
				_stay_warned = true
				message.emit("%s %s, staying on station (force stay)" % [callsign, "past bingo fuel" if _bingo() else "Winchester"])
			if _must_leave():
				state = "rtb"
				var why := "low on fuel" if runs_left > 0 else "Winchester"
				if force_stay:
					why = "at emergency fuel"
				message.emit("%s %s, returning to base" % [callsign, why])
				force_stay = false
		"rtb":
			# Join the long final: follow the line from the approach point to the touchdown
			if not _landing_set:
				_choose_landing_end()
			var ends := _landing_ends()
			var ap: Vector3 = ends.ap
			var touch: Vector3 = ends.touch
			var u := _line_param(ap, touch)
			var to_ap := Vector2(ap.x - _pos.x, ap.z - _pos.z).length()
			var aligned := _heading().dot(ends.travel) > 0.93 and _line_offset(ap, touch) < 60.0
			# Too close in to line up: go back out to the start of the approach and come in again
			if u > 0.55 and not aligned:
				_outbound = true
			if _outbound and u < 0.1:
				_outbound = false
			turn = _steer_to(ap if u < 0.0 or u > 1.0 or _outbound else _line_carrot(ap, touch, 350.0), delta)
			# Slows to approach speed over the last stretch before lining up
			_fly(130.0 if _outbound else (CRUISE_SPEED if to_ap > 2500.0 else APPROACH_SPEED), 40.0, delta)
			if not _outbound and u > 0.0 and u < 0.9 and aligned:
				state = "final"
		"final":
			# Straight in toward the far end of the runway, landing toward the slot
			var ends := _landing_ends()
			var touch: Vector3 = ends.touch
			turn = _steer_to(touch, delta)
			var dist := Vector2(touch.x - _pos.x, touch.z - _pos.z).length()
			speed = move_toward(speed, TAKEOFF_SPEED, 10.0 * delta)
			_pos += _heading() * speed * delta
			# A 3-degree glide slope down to the runway, flaring at the end
			var before := _alt
			_alt = move_toward(_alt, clampf(dist * 0.055, 0.0, 40.0), 12.0 * delta)
			_pitch = lerpf(_pitch, 0.06 + atan2((_alt - before) / maxf(delta, 0.001), maxf(speed, 1.0)), 1.0 - exp(-4.0 * delta))
			if dist < 4.0 or _alt <= 0.05:
				_alt = 0.0
				var tr: Vector3 = ends.travel
				_yaw = atan2(-tr.x, -tr.z)                 # straight down the runway
				state = "rollout"
		"rollout":
			var stop_at: Vector3 = _landing_ends().stop
			var left := Vector2(stop_at.x - _pos.x, stop_at.z - _pos.z).length()
			var decel := speed * speed / maxf(2.0 * left, 1.0)
			speed = maxf(0.0, speed - maxf(decel, 2.0) * delta)
			_pos += _heading() * speed * delta
			if left < 1.0 or speed <= 0.05:
				speed = 0.0
				state = "taxi"
		"taxi":
			# Taxi back to its slot (if it landed the other way), then turn to face down the runway
			var to_slot := Vector3(slot_pos.x - _pos.x, 0.0, slot_pos.z - _pos.z)
			if to_slot.length() > 0.5:
				var face := atan2(-to_slot.x, -to_slot.z)
				var d := wrapf(face - _yaw, -PI, PI)
				_yaw += clampf(d, -1.0 * delta, 1.0 * delta)
				if absf(d) < 0.1:
					_pos += to_slot.normalized() * minf(to_slot.length(), 6.0 * delta)
				_apply_transform()
				return
			_pos = slot_pos
			_landing_set = false
			var diff := wrapf(slot_yaw - _yaw, -PI, PI)
			_yaw += clampf(diff, -1.0 * delta, 1.0 * delta)
			if absf(diff) < 0.02:
				_yaw = slot_yaw
				state = "parked"
				_has_run = false
				force_stay = false
				if _ferry:
					_ferry = false
					rearm_left = 0.0
					fuel = MAX_FUEL
					runs_left = RUNS_PER_SORTIE
					message.emit("%s has landed at the FOB: ready for gun runs" % callsign)
				else:
					rearm_left = REARM_TIME
					_supplied = false
					_supply_cd = 0.0
					message.emit("%s on the ground: refuelling and rearming (%d s)" % [callsign, int(REARM_TIME)])
	if state in ["parked", "takeoff", "rollout", "taxi"]:
		_bank = move_toward(_bank, 0.0, ROLL_RATE * delta)
		_load = 1.0
		_pitch = move_toward(_pitch, 0.12 if state == "takeoff" and _alt > 0.1 else 0.0, 0.5 * delta)
	model.gear.visible = _alt < 15.0
	_ring.visible = selected
	if fuel < 30.0 and not _bingo_warned and state != "parked":
		_bingo_warned = true
	if state == "parked":
		_bingo_warned = false
	_apply_transform()


func _apply_transform() -> void:
	# Heading, then pitch, then roll (+ roll = left wing down: a left turn dips the left wing)
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _bank)
	global_transform = Transform3D(b, Vector3(_pos.x, _alt, _pos.z))


func _heading() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _steer_to(p: Vector3, delta: float, hard := false) -> float:
	## Fly toward p like an aeroplane: roll into a bank toward it, and the bank turns it
	## (a coordinated turn: turn rate = g * tan(bank) / speed). Returns the bank.
	var to := Vector3(p.x - _pos.x, 0.0, p.z - _pos.z)
	var diff := 0.0
	if to.length() > 0.5:
		diff = wrapf(atan2(-to.x, -to.z) - _yaw, -PI, PI)
	var limit := minf(HARD_BANK if hard else CRUISE_BANK, acos(1.0 / MAX_G))
	var want := clampf(diff * 2.5, -limit, limit)
	_bank = move_toward(_bank, want, ROLL_RATE * delta)
	_yaw += GRAVITY * tan(_bank) / maxf(speed, 40.0) * delta
	_load = 1.0 / cos(_bank)
	return _bank


func _line_param(a: Vector3, b: Vector3) -> float:
	## How far along a -> b the jet is (0 at a, 1 at b)
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return Vector3(_pos.x - a.x, 0.0, _pos.z - a.z).dot(ab) / maxf(ab.length_squared(), 1.0)


func _line_offset(a: Vector3, b: Vector3) -> float:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var ap := Vector3(_pos.x - a.x, 0.0, _pos.z - a.z)
	return (ap - ab * ap.dot(ab)).length()


func _line_carrot(a: Vector3, b: Vector3, ahead: float) -> Vector3:
	## A point on the line a -> b a little ahead of the jet: chasing it brings the jet onto the
	## line smoothly instead of circling a single point
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := ab.length()
	var dir := ab / maxf(length, 1.0)
	var t := clampf(Vector3(_pos.x - a.x, 0.0, _pos.z - a.z).dot(dir) + ahead, 0.0, length)
	return a + dir * t


func _fly(target_speed: float, target_alt: float, delta: float, climb_mult := 1.0) -> void:
	# Engines are slow to spool (the A-10 is not quick to accelerate), it slows faster with
	# the speed brakes, and a hard turn bleeds speed
	speed = move_toward(speed, target_speed, (4.0 if target_speed > speed else 10.0) * delta)
	speed = maxf(speed - 2.0 * (_load - 1.0) * delta, 60.0)
	_pos += _heading() * speed * delta
	var before := _alt
	_alt = move_toward(_alt, target_alt, CLIMB_RATE * climb_mult * delta)
	var climb := (_alt - before) / maxf(delta, 0.001)
	_pitch = lerpf(_pitch, atan2(climb, maxf(speed, 1.0)), 1.0 - exp(-3.0 * delta))


func _run_dir() -> Vector3:
	return (_run_end - _run_start).normalized()


func _run_length() -> float:
	return (_run_end - _run_start).length()


func _along(p: Vector3) -> float:
	## How far p is along the run line from its start (negative = before it)
	return Vector3(p.x - _run_start.x, 0.0, p.z - _run_start.z).dot(_run_dir())


func _shoot() -> void:
	# Shells land AIM_AHEAD in front of the jet; fire only while that's on the line
	var aim_along := _along(_pos) + AIM_AHEAD
	var length := _run_length()
	if aim_along < 0.0 or aim_along > length:
		return
	var due := int(ceilf(ROUNDS_PER_RUN * aim_along / maxf(length, 1.0)))
	var muzzle := model.muzzle.global_position
	var side := Vector3(-_run_dir().z, 0.0, _run_dir().x)
	while _fired < mini(due, ROUNDS_PER_RUN):
		_fired += 1
		var t := clampf(aim_along - randf() * 2.0, 0.0, length)
		var p := _run_start + _run_dir() * t + side * randf_range(-SPREAD, SPREAD)
		p.y = _ground_y(p) + 0.1
		enemy.add_tracer(muzzle, p)
		enemy.blast(p, IMPACT_RADIUS, DMG_SOLDIER, DMG_VEHICLE, DMG_TANK, self, true, DMG_STRUCTURE)


func _end_run() -> void:
	runs_left -= 1
	_has_run = false
	state = "egress"
	_egress_t = 6.0
	# Back to the orbit you gave it, otherwise somewhere near the target out of anti-air reach
	_loiter_center = station if has_station else _in_map(_safe_from_aa(_run_end + _run_dir() * 150.0))
	message.emit("%s off target, %s" % [callsign, "%d run left" % runs_left if runs_left > 0 else "Winchester"])


func _bingo(margin := 25.0) -> bool:
	var home := Vector2(slot_pos.x - _pos.x, slot_pos.z - _pos.z).length()
	return fuel < home / CRUISE_SPEED + margin


func _must_leave() -> bool:
	## Time to head home: out of ammo or at bingo fuel. Forced to stay, only at emergency fuel.
	## No runway to go home to: it never leaves.
	if not has_slot:
		return false
	if force_stay:
		return _bingo(STAY_MARGIN)
	return _bingo() or runs_left == 0


const APPROACH_LEN := 1600.0


func _landing_ends() -> Dictionary:
	## Where it lines up, touches down and stops, for the end it's landing from
	if _land_from_far:
		return {"ap": runway_far + runway_dir * APPROACH_LEN, "touch": runway_far, "stop": slot_pos, "travel": -runway_dir}
	return {"ap": slot_pos - runway_dir * APPROACH_LEN, "touch": slot_pos, "stop": runway_far, "travel": runway_dir}


func _choose_landing_end() -> void:
	## Land from whichever end keeps the approach farther from Red anti-air
	var far_ap := runway_far + runway_dir * APPROACH_LEN
	var near_ap := slot_pos - runway_dir * APPROACH_LEN
	var far_ok := _on_map(far_ap)
	var near_ok := _on_map(near_ap)
	if far_ok != near_ok:
		_land_from_far = far_ok              # an approach that starts over the map wins
	else:
		_land_from_far = _aa_clearance(far_ap) >= _aa_clearance(near_ap)
	_landing_set = true


func _on_map(p: Vector3) -> bool:
	return absf(p.x) < CityBuilder.HALF_X - 40.0 and absf(p.z) < CityBuilder.HALF_Z - 40.0


func _aa_clearance(p: Vector3) -> float:
	var best := INF
	for t in enemy.tanks:
		if t is RedAA and t.alive:
			best = minf(best, Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length())
	return best


func _approach_point() -> Vector3:
	## Lined up behind the far end, so it lands back toward its slot
	return _landing_ends().ap


func _safe_from_aa(p: Vector3) -> Vector3:
	## Move an orbit point out of reach of any Red anti-air (orbit radius included)
	var keep := RedAA.AA_RANGE + LOITER_RADIUS + 40.0
	for k in 12:
		var near: Node3D = null
		for t in enemy.tanks:
			if t is RedAA and t.alive and Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() < keep:
				near = t
		if near == null:
			return p
		var away := Vector3(p.x - near.global_position.x, 0, p.z - near.global_position.z)
		if away.length() < 1.0:
			away = Vector3.LEFT
		p += (away.normalized() + Vector3(-0.8, 0, 0)).normalized() * 60.0   # (Red is to the east)
		p.x = clampf(p.x, -(CityBuilder.HALF_X - 50.0), CityBuilder.HALF_X - 50.0)
		p.z = clampf(p.z, -(CityBuilder.HALF_Z - 30.0), CityBuilder.HALF_Z - 30.0)
	return p


func _in_map(p: Vector3) -> Vector3:
	## An orbit centre that keeps the whole circle over the map (a pilot who ejects lands on it)
	var r := _orbit_radius() + 40.0
	var mx := maxf(CityBuilder.HALF_X - r, 0.0)
	var mz := maxf(CityBuilder.HALF_Z - r, 0.0)
	return Vector3(clampf(p.x, -mx, mx), 0.0, clampf(p.z, -mz, mz))


func _orbit_radius() -> float:
	return LOITER_RADIUS + (stack % 3) * 35.0


func _orbit_alt() -> float:
	return CRUISE_ALT + (stack % 4) * 12.0


func is_air_target() -> bool:
	## Red anti-air can shoot at it
	return not destroyed and state != "crash" and _alt > 3.0


func take_flak(amount: float) -> void:
	## Hit by Red anti-air. At half armor it warns you; at zero it's going down.
	if not is_air_target():
		return
	var before := hp
	hp -= amount
	if randf() < 0.15:
		enemy.gibs.smoke(global_position + Vector3.UP * 2.0)
	if hp <= max_hp * 0.5 and before > max_hp * 0.5 and hp > 0.0:
		message.emit("%s hit by anti-air: %d%% armor left" % [callsign, int(100.0 * hp / max_hp)])
	if hp <= 0.0:
		hp = 0.0
		_bail_out("has been shot down by anti-air")


func _bail_out(why := "is out of fuel") -> void:
	state = "crash"
	message.emit("%s %s: the pilot has ejected!" % [callsign, why])
	# (over the map: a pilot who came down off its edge would have nowhere to land)
	var at := Vector3(_pos.x, _alt, _pos.z) - _heading() * 6.0
	at.x = clampf(at.x, -(CityBuilder.HALF_X - 60.0), CityBuilder.HALF_X - 60.0)
	at.z = clampf(at.z, -(CityBuilder.HALF_Z - 60.0), CityBuilder.HALF_Z - 60.0)
	ejected.emit(self, at)


func _crash_land() -> void:
	destroyed = true
	set_selected(false)
	model.burn()
	model.gear.visible = false
	enemy.gibs.explosion(Vector3(_pos.x, 0.5, _pos.z))
	enemy.blast(Vector3(_pos.x, 0.5, _pos.z), 7.0, 120.0, 40.0, 0.0, null)
	for s in crew.squad.soldiers.duplicate():
		s.die()
	_bank = 0.25
	_alt = 0.0
	_apply_transform()
	message.emit("%s has crashed" % callsign)


func take_vehicle_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		destroyed = true
		set_selected(false)
		model.burn()
		enemy.gibs.explosion(global_position + Vector3.UP * 1.5)
		for s in crew.squad.soldiers.duplicate():
			s.die()
		message.emit("%s destroyed on the ground" % callsign)


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else hit.position.y
