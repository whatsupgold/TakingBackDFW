extends Node
## Taking back DFW — M1 prototype: push in and clear.
## Sets up the pixel-art pipeline (3D rendered at 1/3 resolution, scaled up with nearest
## filtering), the level and FOB, your squads and support units (M777, Humvee, Stryker, Huey,
## Chinook, A-10), the Red Army, the HUD and RTS input.
## You win by taking back all three objectives in Arlington; you lose if every unit dies.

var pixel_scale := 3                   # from Settings (2, 3 or 4 screen pixels per game pixel)
const DRAG_THRESHOLD := 6.0
const PICK_RADIUS := 24.0

var container: SubViewportContainer
var viewport: SubViewport
var camera: RtsCamera
var level: Level
var enemy: RedArmy
var hud: Hud
var units: Node3D
var squads: Array[Squad] = []          # infantry (rifle squads, engineers, gun crews, pilots)
var guns: Array = []                   # every M777 you have
var artillery: Artillery:              # the first M777 (null if none): the self-tests use it
	get:
		return guns[0] if not guns.is_empty() else null
var _fire_guns: Array = []             # the guns a G + click goes to (empty: every manned gun)
var fob: Fob
var humvee: Humvee
var stryker: Stryker
var huey: Huey
var chinook: Chinook
var airdrops: Array = []               # [aim point, C-130] for drops on their way
var a10s: Array = []                   # A-10s on the runway (one for now; the runway holds two)
var helis: Array = []                  # Huey and Chinook
var transports: Array = []             # everything troops can ride in: helicopters and the Stryker
var vehicles: Array = []               # selectable vehicles
var _targeting := false                # waiting for a click to call artillery
var _a10_targeting := false            # waiting for a click or drag to call an A-10 run
var _airdrop_kind := ""                 # waiting for a click to call an airdrop of this pallet

# Reinforcements: one more unit every REINFORCE_INTERVAL. Pick it from the HUD (B); it shows up
# at a corner of the map and you bring it to the fight yourself.
const REINFORCE_INTERVAL := 120.0
const REINFORCEMENTS := [
	{"id": "squad", "name": "Rifle squad", "desc": "4 riflemen. A long walk: pick them up with a helicopter or the Stryker"},
	{"id": "engineer", "name": "Engineer squad", "desc": "4 engineers: they build your FOB"},
	{"id": "humvee", "name": "Humvee", "desc": "Crew of 5, .50 cal. Fits in the Chinook"},
	{"id": "stryker", "name": "Stryker", "desc": "Crew of 2, remote .50, carries 2 squads"},
	{"id": "huey", "name": "Black Hawk", "desc": "Crew of 4, 2 door guns, carries 2 squads, fast-ropes them in"},
	{"id": "chinook", "name": "Chinook", "desc": "Crew of 5, carries 8 squads or 2 Humvees"},
	{"id": "a10", "name": "A-10", "desc": "Flies in and lands in a free runway slot"},
	{"id": "m777", "name": "M777 + gun crew", "desc": "Arrives set up with its crew: fetch it with a Chinook"},
	{"id": "pls", "name": "PLS truck", "desc": "Fetches air-dropped supply pallets, 2 at a time"},
	{"id": "fuel", "name": "Fuel truck", "desc": "M978A4 HEMTT: 2,500 gal, refuels vehicles and landed helicopters"},
	{"id": "lmtv", "name": "LMTV", "desc": "Cargo truck: crew of 2, carries 4 squads, unarmored"},
	{"id": "bradley", "name": "Bradley", "desc": "Crew of 3, 25 mm, 2 TOW missiles, carries 1 squad"},
	{"id": "apache", "name": "Apache", "desc": "Attack helicopter: 30 mm and 8 Hellfires, rearms at the FOB"},
	{"id": "mh6", "name": "Little Bird", "desc": "MH-6: fast, carries 1 squad, fast-ropes them in"},
]
const SQUADS_PER_BARRACKS := 5        # rifle and engineer squads each barracks supports
const VEHICLES_PER_SHED := 5          # Humvees, Strykers, Hueys, Chinooks each shed supports
const SQUAD_IDS := ["squad", "engineer"]
var limit_bonus := 0                  # (the self-test lifts the limits)
const VEHICLE_IDS := ["humvee", "stryker", "huey", "chinook", "pls", "fuel", "lmtv", "bradley", "apache", "mh6"]
# What you can bring at the start of a mission (START_PICKS in total)
const START_PICKS := 7
const LOADOUT := [
	{"id": "squad", "name": "Rifle squad", "desc": "4 riflemen"},
	{"id": "engineer", "name": "Engineer squad", "desc": "Builds your FOB: walls, barracks, shed, runway"},
	{"id": "m777", "name": "M777 + gun crew", "desc": "Howitzer and its 4-man crew squad"},
	{"id": "humvee", "name": "Humvee", "desc": "Crew of 5, .50 cal"},
	{"id": "stryker", "name": "Stryker", "desc": "Carries 2 squads, remote .50"},
	{"id": "huey", "name": "Black Hawk", "desc": "Carries 2 squads; fast-ropes them in"},
	{"id": "chinook", "name": "Chinook", "desc": "8 squads or 2 Humvees; sling-loads the M777"},
	{"id": "a10", "name": "A-10", "desc": "Starts in the air with 5 minutes of fuel: build a runway before it runs out"},
	{"id": "pls", "name": "PLS truck", "desc": "Fetches air-dropped supply pallets"},
	{"id": "fuel", "name": "Fuel truck", "desc": "M978A4: refuels vehicles and helicopters in the field"},
	{"id": "lmtv", "name": "LMTV", "desc": "Truck: carries 4 squads, unarmored"},
	{"id": "bradley", "name": "Bradley", "desc": "25 mm, 2 TOWs, carries 1 squad"},
	{"id": "apache", "name": "Apache", "desc": "Attack helicopter with Hellfires"},
	{"id": "mh6", "name": "Little Bird", "desc": "Fast, carries 1 squad"},
]
# Where you can come in: along the west, north and south edges (the Red Army holds the east)
const START_ZONES := [
	{"name": "West — Fort Worth north", "pos": Vector3(-850, 0, -280)},
	{"name": "West — Fort Worth", "pos": Vector3(-850, 0, 0)},
	{"name": "West — Benbrook", "pos": Vector3(-850, 0, 280)},
	{"name": "North — Stockyards", "pos": Vector3(-560, 0, -425)},
	{"name": "North — DFW Airport", "pos": Vector3(-130, 0, -425)},
	{"name": "North — Las Colinas", "pos": Vector3(300, 0, -425)},
	{"name": "South — I-20 west", "pos": Vector3(-560, 0, 425)},
	{"name": "South — I-20", "pos": Vector3(-120, 0, 425)},
	{"name": "South — Grand Prairie", "pos": Vector3(300, 0, 425)},
]
const RIFLE_NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima", "Mike", "November"]
const ENGINEER_COLOR := Color(0.98, 0.86, 0.20)
const GUN_CREW_COLOR := Color(0.85, 0.35, 0.30)
const PILOT_COLOR := Color(0.75, 0.88, 1.0)
var start_zone := -1
# Build mode: placing FOB walls or a building (see Fob)
var build_mode := ""                  # "", walls, barracks, shed, runway
var _build_from := Vector3.ZERO
var _build_dragging := false
var _build_cursor := Vector3.ZERO
var _build_yaw := 0.0
var _build_preview_key := ""
var _build_preview: Array = []        # [[footprint points, blocked]]
const RIFLE_COLOR := Color(0.25, 0.55, 1.0)   # every rifle squad wears the same color (names tell them apart)
# Map corners where reinforcements arrive (north is -Z)
const CORNERS := [    # the east corners are the Red Army's side of the map
	{"name": "northwest", "pos": Vector3(-830, 0, -400)},
	{"name": "southwest", "pos": Vector3(-830, 0, 400)},
]
var reinforcements := 0               # units waiting to be picked
var reinforce_in := REINFORCE_INTERVAL
var arrivals: Array = []              # [position, seconds left]: pings on the minimap
var _type_count := {}                 # how many of each unit type exist (for names like "Humvee 2")
var _corner_uses := {}
var _rng := RandomNumberGenerator.new()
var _a10_dragging := false
var _a10_from := Vector3.ZERO
var _a10_to := Vector3.ZERO
const OVERLAY_RANGE := Artillery.MAX_RANGE   # how far the field-of-fire wedge is drawn
const LABEL_ZOOM := 70.0               # district names show when zoomed out past this
var _anchor_cd := 0.0

var battle_time := 0.0
var state := "setup"                # setup (choosing the loadout), playing, won, lost
var world_ready := false            # the battle starts once the map around the FOB is built

var _drag_start := Vector2.ZERO
var _dragging := false
# Right-drag line formation
var _line_start := Vector2.ZERO
var _line_dragging := false
var _line_moved := false
var _line_points: Array[Vector3] = []   # the shape being drawn, in world space
const MIN_LINE_SPACING := 0.9
const LINE_SAMPLE := 0.35               # metres between recorded points
var _hud_cd := 0.0

# Headless self-test: godot --headless --fixed-fps 60 -- --autotest
var _autotest := false
var _test_clock := 0.0
var _test_report := 0.0
var _test_peak_phys := 0.0
var _shot_path := ""
var _shot_times: Array[float] = []
var _line_test_pending := false
var _support_shots := false
var _city_shots := false
var _chinook_shots := false
var _reinforce_shots := false
var _fob_lab := false
var _breaches: Array = []            # engineer breach charges: {squad, target, state, t, at, node}
const BREACH_PLANT := 6.0             # seconds at the wall to set the charge
const BREACH_FUSE := 5.0
var _redfob_lab := false
var _growth_lab := false
var _soldier_lab := false
var _orders_lab := false
var _base_lab := false
var _vehicle_lab := false
var _supply_lab := false
var _move_lab := false
var _flight_lab := false
var _gl := {}
var _rf := {}
var _sling_lab := false
var _deploy_test := ""               # --deploy-test=a10:7,squad:1 : deploy that loadout through the setup screen
var _dt := 0.0
var _sling_shot := ""                # path prefix for sling-lab screenshots ("" = none)
var _sl := {}                        # sling-lab progress
var _setup_shot := ""
var _setup_clock := 0.0
var _shot_queue: Array = []    # {t, name, focus (Vector3 or Node3D), size, framed}
const TEST_LENGTH := 150.0


func _ready() -> void:
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	# Tests run on the generated city unless they ask for a map (--sector=<id> or --sector=custom)
	var test_run := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			test_run = true
		if a.begins_with("--sector="):
			Settings.sector = a.trim_prefix("--sector=")
	if test_run and not ("--sector=" in " ".join(OS.get_cmdline_user_args())):
		Settings.sector = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
			_autotest = true
			_shot_times = [12.0, 40.0, 75.0]
		if a == "--city-shots":
			_city_shots = true
			_shot_times = []
		if a == "--support-shots":
			_support_shots = true
			_shot_times = []
		if a == "--fob-lab":
			_fob_lab = true
		if a.begins_with("--supply-lab"):
			_supply_lab = true
			_sling_shot = a.trim_prefix("--supply-lab").trim_prefix("=")
		if a.begins_with("--flight-lab"):
			_flight_lab = true
			_sling_shot = a.trim_prefix("--flight-lab").trim_prefix("=")
		if a.begins_with("--move-lab"):
			_move_lab = true
			_sling_shot = a.trim_prefix("--move-lab").trim_prefix("=")
		if a.begins_with("--vehicle-lab"):
			_vehicle_lab = true
			_sling_shot = a.trim_prefix("--vehicle-lab").trim_prefix("=")
		if a.begins_with("--base-lab"):
			_base_lab = true
			_sling_shot = a.trim_prefix("--base-lab").trim_prefix("=")
		if a.begins_with("--orders-lab"):
			_orders_lab = true
			_sling_shot = a.trim_prefix("--orders-lab").trim_prefix("=")
		if a.begins_with("--soldier-lab"):
			_soldier_lab = true
			_sling_shot = a.trim_prefix("--soldier-lab").trim_prefix("=")
		if a.begins_with("--growth-lab"):
			_growth_lab = true
			_sling_shot = a.trim_prefix("--growth-lab").trim_prefix("=")
		if a.begins_with("--redfob-lab"):
			_redfob_lab = true
			_sling_shot = a.trim_prefix("--redfob-lab").trim_prefix("=")
		if a.begins_with("--deploy-test="):
			_deploy_test = a.trim_prefix("--deploy-test=")
		if a.begins_with("--sling-lab"):
			_sling_lab = true
			_sling_shot = a.trim_prefix("--sling-lab").trim_prefix("=")
		if a.begins_with("--setup-shot="):
			_setup_shot = a.trim_prefix("--setup-shot=")
		if a == "--reinforce-shots":
			_support_shots = true
			_reinforce_shots = true
			_shot_times = []
		if a == "--chinook-shots":
			_support_shots = true
			_chinook_shots = true
			_shot_times = []

	container = SubViewportContainer.new()
	container.stretch = true
	pixel_scale = Settings.pixel_scale
	container.stretch_shrink = pixel_scale
	Settings.changed.connect(func():
		pixel_scale = Settings.pixel_scale
		container.stretch_shrink = pixel_scale)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.audio_listener_enable_3d = true
	container.add_child(viewport)

	level = Level.new()
	viewport.add_child(level)
	enemy = RedArmy.new()
	viewport.add_child(enemy)

	level.build()
	enemy.nav_map = level.get_navigation_map()
	enemy.level = level
	enemy.build_fob()
	enemy.fob = Vector3.ZERO

	units = Node3D.new()
	units.name = "Units"
	viewport.add_child(units)

	camera = RtsCamera.new()
	camera.allow_edge_scroll = not _autotest
	viewport.add_child(camera)
	camera.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)

	fob = Fob.new()
	fob.game = self
	fob.level = level
	viewport.add_child(fob)
	fob.message.connect(hud.push_message)
	fob.runway_built.connect(func(_r): _assign_runway_slots())
	level.nav_progress.connect(func(done: int, total: int):
		if done == total:
			print("Map ready: %d navigation tiles in %.1f s" % [total, Time.get_ticks_msec() / 1000.0])
			hud.push_message("The whole city is mapped: units can path anywhere"))
	enemy.message.connect(hud.push_message)
	enemy.objective_changed.connect(_on_objective_changed)

	if _autotest:
		_legacy_start()
		_start_autotest()
	else:
		# Choose your force and where you come in
		enemy.spawning_enabled = false
		hud.show_setup()
	if _support_shots:
		enemy.spawning_enabled = false


func _legacy_start() -> void:
	## Tests and screenshots: a fixed force around the Arlington plaza, the A-10 on station overhead
	state = "playing"
	enemy.legacy_objectives = true      # the self-test still fights over Arlington
	var alpha := _new_squad("rifle")
	for i in 4:
		_spawn_soldier(alpha, Vector3(-2.0 + (i % 3) * 1.3, Level.ROOF_HEIGHT + 0.1, -1.0 + floori(i / 3.0) * 1.3))
	var bravo := _new_squad("rifle")
	for i in 4:
		_spawn_soldier(bravo, Vector3(8.0 + (i % 2) * 1.2, 0.1, 11.0 + floori(i / 2.0) * 1.3))
	var eng := _new_squad("engineer")
	for i in 4:
		_spawn_soldier(eng, Vector3(46.0 + (i % 3) * 1.3, 0.1, 24.0 + floori(i / 3.0) * 1.3))
	humvee = spawn_unit("humvee", Vector3(13.0, 0.0, 16.5), -150.0)
	stryker = spawn_unit("stryker", Vector3(-42.0, 0.0, 33.0), 180.0)
	huey = spawn_unit("huey", Vector3(30.0, 0.0, 6.0), -20.0)
	chinook = spawn_unit("chinook", Vector3(44.0, 0.0, -8.0), -10.0)
	spawn_unit("m777", Vector3(-15.5, 0.0, 3.0), 112.5)
	spawn_unit("a10", Vector3(0, 0, 0), 0.0)
	alpha.set_selected(true)


func zone_pos(i: int) -> Vector3:
	## Where start point i is on this map (the same spots on the edges, whatever the map size)
	var hx := CityBuilder.HALF_X
	var hz := CityBuilder.HALF_Z
	var base: Vector3 = START_ZONES[i].pos
	if base.x <= -849.0:
		return Vector3(-(hx - 50.0), 0, base.z / 450.0 * hz)
	return Vector3(base.x / 900.0 * hx, 0, signf(base.z) * (hz - 25.0))


func corner_pos(i: int) -> Vector3:
	var c: Vector3 = CORNERS[i].pos
	return Vector3(signf(c.x) * (CityBuilder.HALF_X - 70.0), 0, signf(c.z) * (CityBuilder.HALF_Z - 50.0))


func zone_name(i: int) -> String:
	## A start point's name (the generated city's place names don't apply to a real map)
	if level.city.real_map != null:
		return ["West edge, north", "West edge, middle", "West edge, south", "North edge, west", "North edge, middle",
			"North edge, east", "South edge, west", "South edge, middle", "South edge, east"][i]
	return START_ZONES[i].name


func start_mission(loadout: Dictionary, zone: int) -> void:
	## From the setup screen: bring in the chosen units at the chosen part of the map edge
	start_zone = zone
	var center: Vector3 = zone_pos(zone)
	var inward := Vector3(-signf(center.x) if absf(center.x) > CityBuilder.HALF_X - 100.0 else 0.0, 0.0, -signf(center.z) if absf(center.z) > CityBuilder.HALF_Z - 50.0 else 0.0).normalized()
	var used: Array = []
	var first: Variant = null
	for opt in LOADOUT:
		for k in loadout.get(opt.id, 0):
			var spot := _free_spot(center, inward, used, 16.0 if opt.id in ["chinook", "huey", "m777"] else 12.0)
			var face := Vector3(-spot.x, 0, -spot.z)
			var u = spawn_unit(opt.id, spot, rad_to_deg(atan2(-face.x, -face.z)))
			if first == null and u is Squad:
				first = u
	state = "playing"
	enemy.spawning_enabled = true
	camera.focus = level.ground_spot(center + inward * 30.0, 40.0)
	camera.size = 70.0
	camera._target_size = 70.0
	if first != null:
		_select_only([first])
	hud.push_message("Deployed at %s. Get the engineers building: press F" % zone_name(zone))


func _free_spot(center: Vector3, inward: Vector3, used: Array, gap: float) -> Vector3:
	## A street-level spot near `center` at least `gap` metres from the others in `used`
	var side := Vector3(-inward.z, 0, inward.x)
	var spot := level.ground_spot(center, 60.0)
	for k in 40:
		var c := level.ground_spot(center + inward * (8.0 + 12.0 * floori(k / 5.0)) + side * 14.0 * ((k % 5) - 2), 30.0)
		var clear := true
		for u in used:
			if Vector2(c.x - u.x, c.z - u.z).length() < gap:
				clear = false
		if clear:
			spot = c
			break
	used.append(spot)
	spot.y = level.floor_y(spot)
	return spot


func _new_squad(kind: String, squad_name := "") -> Squad:
	var n := squad_name
	var color := PILOT_COLOR
	match kind:
		"rifle":
			var i: int = _type_count.get("rifle", 0)
			_type_count["rifle"] = i + 1
			n = RIFLE_NAMES[i % RIFLE_NAMES.size()] + ("" if i < RIFLE_NAMES.size() else " %d" % (i / RIFLE_NAMES.size() + 1))
			color = RIFLE_COLOR
		"engineer":
			n = _next_name("engineer", "Engineers")
			color = ENGINEER_COLOR
		"gun_crew":
			n = _next_name("gun_crew", "Gun crew")
			color = GUN_CREW_COLOR
	var sq := Squad.make(n, color, kind)
	squads.append(sq)
	sq.leveled_up.connect(_on_level_up)
	sq.wiped_out.connect(_on_wiped_out)
	hud.add_unit_card(sq)
	return sq


func spawn_unit(id: String, at: Vector3, yaw_deg: float, arriving := false):
	## Make one unit of a kind and put it in the battle (mission start or reinforcement).
	## Returns the Squad or the vehicle.
	var nav := level.get_navigation_map()
	match id:
		"squad", "rifle", "engineer":
			var sq := _new_squad("engineer" if id == "engineer" else "rifle")
			for k in sq.max_members:
				var off := Vector3((k % 3 - 1) * 1.4, 0.0, floori(k / 3.0) * 1.4)
				_spawn_soldier(sq, level.ground_spot(at + off, 10.0) + Vector3.UP * 0.1)
			return sq
		"humvee", "stryker", "pls", "fuel", "lmtv", "bradley":
			var v: GroundVehicle
			match id:
				"humvee": v = Humvee.new()
				"stryker": v = Stryker.new()
				"pls": v = Pls.new()
				"fuel": v = FuelTruck.new()
				"lmtv": v = Lmtv.new()
				_: v = Bradley.new()
			v.enemy = enemy
			v.nav_map = nav
			v.display_name = _next_name(id, v.display_name)
			units.add_child(v)
			v.place(at, yaw_deg)
			_register_vehicle(v)
			return v
		"huey", "chinook", "apache", "mh6":
			var h: Helicopter
			match id:
				"huey": h = Huey.new()
				"chinook": h = Chinook.new()
				"apache": h = Apache.new()
				_: h = LittleBird.new()
			h.enemy = enemy
			h.nav_map = nav
			h.display_name = _next_name(id, h.display_name)
			units.add_child(h)
			h.place(at, yaw_deg)
			_register_vehicle(h)
			return h
		"m777":
			var gun := Artillery.new()
			gun.enemy = enemy
			gun.nav_map = nav
			gun.display_name = _next_name("m777", "M777")
			var crew_sq := _new_squad("gun_crew")
			gun.crew_squad = crew_sq
			guns.append(gun)
			level.add_child(gun)
			gun.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at)
			level.add_blocker(gun)
			enemy.vehicles.append(gun)
			gun.lifted.connect(_on_gun_lifted.bind(gun))
			gun.message.connect(hud.push_message)
			gun.impact.connect(_on_artillery_impact)
			if _autotest:
				gun.fired.connect(func(): print("AUTOTEST: M777 fired at t=%.1f" % _test_clock))
			hud.add_unit_card(gun)
			# The crew starts at the gun, manning it
			for i in Artillery.SEATS.size():
				var spot := level.ground_spot(gun.to_global(Artillery.MAN_POINTS[i]), 6.0)
				var s := _spawn_soldier(crew_sq, spot + Vector3.UP * 0.1)
				gun.board_soldier(s)
			return gun
		"a10":
			var jet := A10.new()
			jet.enemy = enemy
			_type_count["a10"] = _type_count.get("a10", 0) + 1
			jet.callsign = "Hog %d" % _type_count["a10"]
			jet.stack = _type_count["a10"] - 1
			# A pilot who ejected and made it back inside the FOB takes the new jet: it keeps his
			# callsign and his kills
			var pilot := _rescued_pilot()
			if pilot != null:
				jet.callsign = pilot.get_meta("callsign", jet.callsign)
				jet.kills = pilot.get_meta("jet_kills", 0)
				_retire_pilot(pilot)
				hud.push_message("%s's pilot is back in the air in a new A-10" % jet.callsign)
			units.add_child(jet)
			jet.ejected.connect(_on_ejected)
			_register_vehicle(jet)
			_assign_runway_slots()
			if arriving:
				jet.arrive_from(at, fob.center() if not fob.rects.is_empty() else at)
			else:
				jet.start_airborne(at, A10.START_FUEL)
			return jet
	return null


func _on_gun_lifted(up: bool, gun: Artillery) -> void:
	if up:
		level.remove_blocker(gun)
	else:
		level.add_blocker(gun)


func gun_of(sq: Squad) -> Artillery:
	## The M777 a gun crew belongs to
	for g in guns:
		if g.crew_squad == sq:
			return g
	return null


func fire_guns() -> Array:
	## The guns a fire mission goes to: the ones you picked (their crew selected, or their card
	## clicked), otherwise every gun that's manned and on the ground
	var out: Array = []
	for g in (_fire_guns if not _fire_guns.is_empty() else guns):
		if is_instance_valid(g) and g.slung_by == null and g.crew_count() > 0:
			out.append(g)
	return out


func begin_fire(picked: Array = []) -> void:
	## Start a call for fire (G): click a target next
	_a10_targeting = false
	if guns.is_empty():
		hud.push_message("No M777 in this mission")
		return
	_fire_guns = picked.duplicate()
	if _fire_guns.is_empty():
		_fire_guns.append_array(_selected_guns())
		for sq in _selected():
			var g := gun_of(sq)
			if g != null:
				_fire_guns.append(g)
	_targeting = true
	var n := fire_guns().size()
	if n == 0:
		hud.push_message("No M777 can fire right now: nobody's manning it, or it's slung")
		_targeting = false
		return
	hud.push_message("Call for fire (%d gun%s): click a target inside the field of fire" % [n, "s" if n > 1 else ""])


func add_recruit(sq: Squad, at: Vector3) -> Soldier:
	## A replacement soldier from the barracks: joins at the squad's current level
	if sq.soldiers.is_empty() or sq.soldiers.size() >= sq.max_members:
		return null
	return _spawn_soldier(sq, at)


func _assign_runway_slots() -> void:
	## Give every A-10 without a parking slot a free one on a built runway
	var taken := {}
	for a in a10s:
		if not a.destroyed and a.has_slot:
			taken[a.slot_key] = true
	for slot in fob.runway_slots():
		if taken.has(slot.key):
			continue
		for a in a10s:
			if not a.destroyed and not a.has_slot:
				a.assign_slot(slot.pos, slot.dir, slot.far, slot.key)
				taken[slot.key] = true
				hud.push_message("%s has a runway slot: it will land there to refuel and rearm" % a.callsign)
				break


func free_runway_slots() -> int:
	var n := fob.runway_slots().size()
	for a in a10s:
		if not a.destroyed and a.has_slot:
			n -= 1
	return maxi(0, n)


func _on_ejected(jet: A10, at: Vector3) -> void:
	var pilot := _new_squad("pilot", "%s pilot" % jet.callsign)
	pilot.set_meta("callsign", jet.callsign)
	pilot.set_meta("jet_kills", jet.kills)
	var s := _spawn_soldier(pilot, at)
	s.open_chute()
	arrivals.append([Vector3(at.x, 0, at.z), 25.0])
	hud.push_message("%s's pilot is coming down by parachute: get him back to the FOB" % jet.callsign)


func _rescued_pilot() -> Squad:
	## An ejected pilot standing inside your FOB walls, ready for a new jet
	for sq in squads:
		if sq.kind != "pilot" or sq.soldiers.is_empty():
			continue
		for s in sq.soldiers:
			if not s.chute and fob.contains(s.global_position):
				return sq
	return null


func _retire_pilot(sq: Squad) -> void:
	## The pilot climbs into his new jet: his ground squad goes away (no "wiped out")
	if sq.wiped_out.is_connected(_on_wiped_out):
		sq.wiped_out.disconnect(_on_wiped_out)
	sq.set_selected(false)
	for s in sq.soldiers.duplicate():
		s.visible = false       # (an unseen soldier is removed at once, no body)
		s.die()


func has_engineers() -> bool:
	for sq in squads:
		if sq.kind == "engineer" and not sq.soldiers.is_empty():
			return true
	return false


func _on_artillery_impact(at: Vector3) -> void:
	var near := clampf(1.0 - at.distance_to(camera.focus) / 70.0, 0.25, 1.0)
	camera.shake(0.8 * near)


func _spawn_soldier(sq: Squad, pos: Vector3) -> Soldier:
	var s := Soldier.new()
	s.squad = sq
	s.enemy = enemy
	units.add_child(s)
	s.global_position = pos
	sq.soldiers.append(s)
	enemy.soldiers.append(s)
	return s


# --- Game flow --------------------------------------------------------------

func _process(delta: float) -> void:
	if not world_ready:
		# The whole map first: the Red FOB's garrison is placed on it at the far east edge
		world_ready = level.nav_ready() and level.map_settled() and enemy.fob_mapped()
		if world_ready:
			print("Map settled: %.1f s" % (Time.get_ticks_msec() / 1000.0))
		enemy.process_mode = Node.PROCESS_MODE_INHERIT if world_ready else Node.PROCESS_MODE_DISABLED
		if world_ready:
			enemy.deploy()
		elif state != "setup" and Engine.get_process_frames() % 600 == 1:
			hud.push_message("Preparing the city...")
	if state == "playing" and world_ready:
		battle_time += delta
		reinforce_in -= delta
		if reinforce_in <= 0.0:
			reinforce_in += REINFORCE_INTERVAL
			reinforcements += 1
			hud.push_message("Reinforcements available: %d  (press B to pick a unit)" % reinforcements)
	for i in range(arrivals.size() - 1, -1, -1):
		arrivals[i][1] -= delta
		if arrivals[i][1] <= 0.0:
			arrivals.remove_at(i)
	if _deploy_test != "":
		_deploy_test_tick(delta)
	if _setup_shot != "":
		_setup_shot_tick(delta)
	_hud_cd -= delta
	if _hud_cd <= 0.0:
		_hud_cd = 0.1
		_update_hud()
	_update_overlay()
	_update_world_view(delta)


func _update_world_view(delta: float) -> void:
	# Labels for districts and highways when zoomed out; window detail when zoomed in
	var far := camera.size > LABEL_ZOOM
	for l in level.city.labels:
		l.visible = far
	level.city.material.set_shader_parameter("detail", 0.0 if camera.size > 110.0 else 1.0)
	if level.city.paint_layer:
		level.city.paint_layer.visible = camera.size < 90.0
	# Place names hide when you zoom right in, so they don't cover the fight
	var names := camera.size > 28.0
	for o in enemy.objectives:
		(o.label as Label3D).visible = names
	# Tell the Red Army where your units are (counterattacks come in away from them)
	_anchor_cd -= delta
	if _anchor_cd <= 0.0:
		_anchor_cd = 0.5
		var pts: Array[Vector3] = []
		for sq in squads:
			var active := sq.active_soldiers()
			if not active.is_empty():
				pts.append(active[0].global_position)
		for u in vehicles:
			if not (u is A10) and u.crew.count() > 0 and u.visible:
				pts.append(u.global_position)
		enemy.anchors = pts
		# Counterattacks go for your FOB once you have one, otherwise for your force
		if not fob.rects.is_empty():
			enemy.fob = fob.center()
		elif not pts.is_empty():
			enemy.fob = pts[0]


func _on_objective_changed(obj: Dictionary) -> void:
	if obj.get("fob", false) and obj.owner == "blue":
		hud.push_message("The Red FOB is yours: no more Red reinforcements")
	if enemy.objectives_held() == enemy.objectives.size():
		_end("won")


func _update_overlay() -> void:
	## Call-for-fire overlays: the M777's field-of-fire wedge and crosshair, the A-10 run line
	var items: Array = []
	_build_overlay(items)
	if _targeting:
		for g in fire_guns():
			var fwd: Vector3 = -g.global_basis.z
			fwd.y = 0.0
			_wedge(items, g.global_position, fwd.normalized(), Color(1, 1, 1, 0.7), OVERLAY_RANGE)
		var hit := _ray(get_viewport().get_mouse_position(), 1 | 8)
		if not hit.is_empty():
			var reach := 0
			for g in fire_guns():
				if g.in_field(hit.position):
					reach += 1
			var c := Color(0.4, 1.0, 0.4) if reach > 0 else Color(1.0, 0.3, 0.25)
			# Where the rounds can land (wider with more guns) plus the blast around them
			var spread := Artillery.spread_for(maxi(reach, 1))
			items.append([_ring_screen(hit.position, spread + Artillery.BLAST_RADIUS), c, true, 2.0])
			if reach > 1:
				items.append([_ring_screen(hit.position, spread), Color(c, 0.6), true, 1.0])
	for g in guns:
		if g.has_mission:
			items.append([_ring_screen(g.mission_target, g.mission_spread + 1.0), Color(1.0, 0.35, 0.2), true, 2.0])
			items.append([_ring_screen(g.mission_target, 0.6), Color(1.0, 0.35, 0.2), true, 2.0])
	# Setting the slung M777 down: where it goes and its field of fire
	if _line_dragging and _line_moved and not _slung_selected().is_empty():
		var plan := _drop_plan()
		if not plan.is_empty():
			items.append([_ring_screen(plan.at, 2.5), UiTheme.ACCENT, true, 2.0])
			_wedge(items, plan.at, plan.fwd, Color(UiTheme.ACCENT, 0.8), 80.0)
	for h in helis:
		if h is Chinook and h.sling_phase in ["to_drop", "lowering"]:
			var f := Vector3(-sin(h._drop_yaw), 0.0, -cos(h._drop_yaw))
			items.append([_ring_screen(h._drop_at, 2.5), Color(UiTheme.ACCENT, 0.8), true, 2.0])
			_wedge(items, h._drop_at, f, Color(UiTheme.ACCENT, 0.45), 40.0)
	if _a10_targeting:
		var c := Color(0.55, 0.85, 1.0)
		if _a10_dragging:
			items.append([_strip_screen(_a10_from, _a10_to, A10.SPREAD + 1.0), c, true, 2.0])
		else:
			var hit := _ray(get_viewport().get_mouse_position(), 1)
			if not hit.is_empty():
				items.append([_ring_screen(hit.position, 3.0), c, true, 2.0])
	# Airdrops: the aim point while picking it, then a ring under each pallet coming down
	if _airdrop_kind != "":
		var ah := _ray(get_viewport().get_mouse_position(), 1)
		if not ah.is_empty():
			items.append([_ring_screen(ah.position, 6.0), Color(1.0, 0.85, 0.35), true, 2.0])
	for n in get_tree().get_nodes_in_group("pallets"):
		var pl := n as SupplyPallet
		if pl != null and pl.state == "falling":
			items.append([_ring_screen(Vector3(pl.global_position.x, 0.0, pl.global_position.z), 3.0), Color(1.0, 0.85, 0.35, 0.8), true, 1.5])
	# Selected vehicles and helicopters: the route they were told to take, where it ends, and
	# the way they'll face when they get there
	for v in vehicles:
		if not v.selected or v.destroyed or not v.has_method("planned_path"):
			continue
		var route: PackedVector3Array = v.planned_path()
		var col := Color(0.55, 0.85, 1.0, 0.9) if v is Helicopter else Color(0.6, 1.0, 0.55, 0.9)
		var turning: bool = v is GroundVehicle and v._turning
		if route.size() >= 2:
			var pts := PackedVector2Array()
			for p in route:
				pts.append(_to_screen(p))
			items.append([pts, col, false, 1.5])
			items.append([_ring_screen(route[-1], 2.0), col, true, 1.5])
		if (route.size() >= 2 or turning) and not is_nan(v.face_yaw):
			var at: Vector3 = route[-1] if route.size() >= 2 else v.global_position
			items.append([_arrow_screen(at, v.face_yaw, 7.0), col, false, 2.0])
	# Selected A-10s: the orbit they're flying (dashed look: two thin rings)
	for a in a10s:
		if a.selected and not a.destroyed and a.state in ["loiter", "egress", "transit", "run", "takeoff"]:
			var oc := Color(0.55, 0.85, 1.0, 0.85) if not a.force_stay else Color(UiTheme.ACCENT, 0.95)
			items.append([_ring_screen(a._loiter_center, a._orbit_radius()), oc, true, 1.5])
			items.append([_ring_screen(a._loiter_center, 4.0), oc, true, 2.0])
	# Objective circles: red while the Red Army holds them, blue once taken back
	for o in enemy.objectives:
		var col := Color(0.45, 0.75, 1.0, 0.8) if o.owner == "blue" else Color(1.0, 0.35, 0.3, 0.8)
		items.append([_ring_screen(o.pos, RedArmy.OBJECTIVE_RADIUS), col, true, 2.0])
	hud.set_overlay(items)


func _arrow_screen(at: Vector3, yaw: float, length: float) -> PackedVector2Array:
	## An arrow on the ground from `at` pointing along `yaw` (as an open polyline)
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var r := Vector3(-f.z, 0.0, f.x)
	var tip := at + f * length
	var head := length * 0.35
	return PackedVector2Array([_to_screen(at), _to_screen(tip), _to_screen(tip - f * head + r * head * 0.6),
		_to_screen(tip), _to_screen(tip - f * head - r * head * 0.6)])


func _strip_screen(a: Vector3, b: Vector3, half_width: float) -> PackedVector2Array:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 0.1:
		return _ring_screen(a, half_width)
	var side := Vector3(-d.z, 0.0, d.x).normalized() * half_width
	return PackedVector2Array([_to_screen(a + side), _to_screen(b + side), _to_screen(b - side), _to_screen(a - side), _to_screen(a + side)])


func _physics_process(delta: float) -> void:
	if not _breaches.is_empty():
		_breach_tick(delta)
	if _autotest and world_ready:
		_autotest_tick(delta)


# --- Breaching the Red FOB (engineers) ----------------------------------------------

func _red_wall_at(hit: Dictionary) -> Structure:
	## A standing Red FOB wall, ramp or gate under the cursor
	var st: Structure = hit.collider if hit.collider is Structure else null
	if st == null:
		st = level.structure_at(hit.position, 2.0)
	if st != null and st.side == "red" and st.kind in ["red_wall", "red_ramp", "red_gate"] and st.is_built():
		return st
	return null


func order_breach(sq: Squad, st: Structure) -> void:
	## The engineers go to the outside of the wall, set a charge, step back, and it blows
	for b in _breaches.duplicate():
		if b.squad == sq and b.state != "fuse":
			_breaches.erase(b)
	var nav := level.get_navigation_map()
	var out := st.to_global_flat(Vector3(0, 0, -(Structure.WALL_T * 0.5 + 1.3)))
	sq.order_move(NavigationServer3D.map_get_closest_point(nav, out), nav)
	sq.set_meta("breaching", true)
	_breaches.append({"squad": sq, "target": st, "state": "moving", "t": BREACH_PLANT, "at": out, "node": null})
	hud.push_message("%s: moving up to blow a breach in the Red FOB %s" % [sq.squad_name, st.display_name().to_lower()])


func _end_breach(b: Dictionary) -> void:
	_breaches.erase(b)
	if b.node != null and is_instance_valid(b.node):
		b.node.queue_free()
	var sq: Squad = b.squad
	var busy := false
	for o in _breaches:
		busy = busy or o.squad == sq
	if not busy:
		sq.set_meta("breaching", false)


func _breach_tick(delta: float) -> void:
	for b in _breaches.duplicate():
		var st: Structure = b.target
		var sq: Squad = b.squad
		var standing := is_instance_valid(st) and st.is_built()
		if b.state != "fuse":
			if not standing or sq.soldiers.is_empty() or not sq.get_meta("breaching", false):
				_end_breach(b)
				continue
			var near := false
			for sd in sq.active_soldiers():
				if not sd._has_order and st.flat_distance(sd.global_position) < 3.2:
					near = true
			if not near:
				continue
			if b.state == "moving":
				b.state = "planting"
				hud.push_message("%s setting a breach charge" % sq.squad_name)
			b.t -= delta
			if b.t > 0.0:
				continue
			# Charge set: a satchel on the wall, and everyone back
			b.state = "fuse"
			b.t = BREACH_FUSE
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.6, 0.4)
			m.mesh = bm
			m.material_override = Level.make_material(Color(0.32, 0.36, 0.22))
			level.add_child(m)
			m.global_position = st.to_global_flat(Vector3(0, 0, -(Structure.WALL_T * 0.5 + 0.2))) + Vector3.UP * 0.9
			m.rotation.y = st.yaw
			b.node = m
			var away := ((b.at as Vector3) - st.position)
			away.y = 0.0
			away = away.normalized()
			var nav := level.get_navigation_map()
			sq.order_move(NavigationServer3D.map_get_closest_point(nav, (b.at as Vector3) + away * 16.0), nav)
			hud.push_message("Breach charge set: %d seconds, get clear!" % int(BREACH_FUSE))
		else:
			b.t -= delta
			if b.node != null and is_instance_valid(b.node):
				b.node.visible = fmod(b.t, 0.5) > 0.2 or b.t > 3.0
			if b.t > 0.0:
				continue
			var at: Vector3 = b.node.global_position if b.node != null and is_instance_valid(b.node) else b.at
			enemy.blast(at, 7.0, 220.0, 60.0, 90.0, sq, false)
			if standing:
				st.take_damage(99999.0)
			level.damage_structures(at, 2.5, 300.0, ["red"])
			camera.shake(0.8)
			hud.push_message("Breach! The Red FOB wall is open")
			_end_breach(b)


func _end(result: String) -> void:
	if state != "playing":
		return
	state = result
	enemy.spawning_enabled = false
	var alive := 0
	for u in _all_units():
		alive += u.soldiers.size()
	var stats := "Time: %d:%02d\nObjectives taken back: %d / %d\nRed riflemen killed: %d\nRed tanks destroyed: %d\nSoldiers still standing: %d" % [
		floori(battle_time / 60.0), floori(fmod(battle_time, 60.0)), enemy.objectives_held(), enemy.objectives.size(),
		enemy.kills, enemy.tanks_destroyed, alive]
	hud.show_end(result == "won", stats)


func _on_level_up(sq: Squad, skill: String) -> void:
	var names := {"accuracy": "Accuracy", "ammo": "Ammo capacity", "weapons": "Weapons"}
	hud.push_message("%s leveled up: %s %d/5" % [sq.squad_name, names[skill], sq.levels[skill]])


func _on_wiped_out(sq: Squad) -> void:
	if sq.kind != "aircrew":
		hud.push_message("%s has been wiped out" % sq.squad_name)
	for other in _all_units():
		if not other.soldiers.is_empty():
			return
	_end("lost")


func _all_units() -> Array:
	## Every squad that counts toward "if you all die, you lose": infantry and crews
	var out: Array = []
	out.append_array(squads)
	for v in vehicles:
		out.append(v.crew.squad)
	return out


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == "setup":
		return
	if build_mode != "" and _build_input(event):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _a10_targeting and mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _ray(mb.position, 1)
			if mb.pressed and not hit.is_empty():
				_a10_from = hit.position
				_a10_to = hit.position
				_a10_dragging = true
			elif not mb.pressed and _a10_dragging:
				if not hit.is_empty():
					_a10_to = hit.position
				_call_a10(_a10_from, _a10_to)
			return
		if _airdrop_kind != "" and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_calls()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var dhit := _ray(mb.position, 1)
				if not dhit.is_empty():
					call_airdrop(dhit.position, _airdrop_kind)
					if not mb.shift_pressed:
						_cancel_calls()
				return
		if (_targeting or _a10_targeting) and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_calls()
			return
		if _targeting and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_call_artillery(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = mb.position
				_dragging = true
			else:
				if _dragging:
					_finish_select(mb.position, mb.shift_pressed)
				_dragging = false
				hud.set_drag(Rect2(), false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_begin_line(mb.position)
			else:
				_end_line(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(1.1)
	elif event is InputEventMouseMotion and _a10_dragging:
		var hit := _ray((event as InputEventMouseMotion).position, 1)
		if not hit.is_empty():
			_a10_to = hit.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		hud.set_drag(Rect2(_drag_start, mm.position - _drag_start), mm.position.distance_to(_drag_start) > DRAG_THRESHOLD)
	elif event is InputEventMouseMotion and _line_dragging:
		_preview_line((event as InputEventMouseMotion).position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key((event as InputEventKey).keycode)


func begin_airdrop(kind: String) -> void:
	## Pick a pallet in the airdrop menu, then click where it should land
	_cancel_calls()
	_airdrop_kind = kind
	hud.set_hint("Airdrop (%s): click where it should land (shift-click to drop more).  Right-click or Esc to stop" % SupplyPallet.KINDS[kind].name.to_lower())


func call_airdrop(at: Vector3, kind: String) -> void:
	var plane := Airlifter.fly(at, kind, level)
	plane.dropped.connect(func(p: SupplyPallet): hud.push_message("%s out of the C-130, coming down on its parachute" % p.display_name))
	airdrops.append([Vector3(at.x, at.y, at.z), plane])
	hud.push_message("C-130 inbound: %s" % SupplyPallet.KINDS[kind].name.to_lower())


func _pallet_at(p: Vector3) -> SupplyPallet:
	var best: SupplyPallet = null
	var best_d := 3.5
	for n in get_tree().get_nodes_in_group("pallets"):
		var pl := n as SupplyPallet
		if pl == null or pl.state != "ground":
			continue
		var d := Vector2(pl.global_position.x - p.x, pl.global_position.z - p.z).length()
		if d < best_d:
			best_d = d
			best = pl
	return best


func _cancel_calls() -> void:
	if _airdrop_kind != "":
		_airdrop_kind = ""
		hud.set_hint("")
	if _targeting:
		hud.push_message("Artillery call cancelled")
	_fire_guns = []
	if _a10_targeting:
		hud.push_message("A-10 call cancelled")
	_targeting = false
	_a10_targeting = false
	_a10_dragging = false


func _on_key(key: Key) -> void:
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
			var list := hotkey_units()
			var i: int = 9 if key == KEY_0 else key - KEY_1
			if i < list.size():
				_select_only([list[i]])
		KEY_F:
			hud.toggle_build_menu()
		KEY_G:
			if _targeting:
				_cancel_calls()
			else:
				begin_fire()
		KEY_V:
			_targeting = false
			_a10_dragging = false
			if _ready_a10() == null:
				hud.push_message(_a10_unavailable())
				_a10_targeting = false
			else:
				_a10_targeting = not _a10_targeting
				if _a10_targeting:
					hud.push_message("A-10 gun run: drag a line across the target (or click a spot)")
		KEY_T:
			# Single shot / repeat for the selected guns (or all of them)
			var tg: Array = _selected_guns()
			for sq in _selected():
				var cg := gun_of(sq)
				if cg != null and not cg in tg:
					tg.append(cg)
			if tg.is_empty():
				tg = guns.duplicate()
			if tg.is_empty():
				hud.push_message("No M777 in this mission")
			else:
				var rep: bool = not tg[0].repeat
				for g in tg:
					g.repeat = rep
				hud.push_message("%s: %s" % [tg[0].display_name if tg.size() == 1 else "%d guns" % tg.size(), "REPEAT fire (keeps firing until you cease fire)" if rep else "SINGLE shot (one round per fire mission)"])
		KEY_X:
			var jets: Array = []
			for a in a10s:
				if a.selected and not a.destroyed:
					jets.append(a)
			if jets.is_empty():
				hud.push_message("Select an A-10 to make it stay on station (X)")
			else:
				var on: bool = not jets[0].force_stay
				for a in jets:
					if a.force_stay != on:
						a.toggle_force_stay()
				hud.push_message("%s: %s" % [jets[0].callsign if jets.size() == 1 else "%d A-10s" % jets.size(),
					"FORCE STAY — keeps circling past bingo fuel, until it only just has enough to get home" if on else "force stay off: returns at bingo fuel or Winchester"])
		KEY_C:
			# The selected guns and crews' guns, otherwise every gun
			var pick: Array = _selected_guns()
			for sq in _selected():
				var g := gun_of(sq)
				if g != null:
					pick.append(g)
			var n := 0
			for g in (pick if not pick.is_empty() else guns):
				if g.has_mission:
					g.cancel()
					n += 1
			if n > 0:
				hud.push_message("Fire mission cancelled (%d gun%s)" % [n, "s" if n > 1 else ""])
		KEY_L:
			var picked := _selected_helis()
			if picked.is_empty():
				hud.push_message("Select a Black Hawk or Chinook to switch land / hover")
			for h in picked:
				h.toggle_hover()
		KEY_U:
			var picked: Array = []
			for t in transports:
				if t.selected:
					picked.append(t)
			for v in _selected_vehicles():
				if v is Pls:
					v.drop_all()
					picked.append(v)
			if picked.is_empty():
				hud.push_message("Select a Black Hawk, Chinook, Stryker or PLS to unload")
			for t in picked:
				if t is Pls:
					continue
				if t is Chinook and t.is_slung():
					# Set the gun down right below, facing the way the Chinook is heading
					t.order_drop(level.ground_spot(t.global_position, 20.0), t.global_rotation.y)
				else:
					t.unload()
		KEY_K:
			var chs: Array = []
			for h in _selected_helis():
				if h is Chinook:
					chs.append(h)
			if chs.is_empty():
				hud.push_message("Select a Chinook to sling-load the M777")
			else:
				# The nearest gun that's on the ground
				var best: Artillery = null
				for g in guns:
					if g.slung_by == null and (best == null or g.global_position.distance_to(chs[0].global_position) < best.global_position.distance_to(chs[0].global_position)):
						best = g
				if best == null:
					hud.push_message("No M777 on the ground to sling")
				else:
					_order_sling(chs[0], best)
		KEY_B:
			hud.toggle_reinforcements()
		KEY_ESCAPE:
			if hud.build_menu_open():
				hud.toggle_build_menu()
			elif hud.reinforcements_open():
				hud.toggle_reinforcements()
			elif _targeting or _a10_targeting or _airdrop_kind != "":
				_cancel_calls()
			else:
				hud.toggle_pause()
		KEY_F1:
			hud.toggle_help()
		KEY_F4:
			hud.toggle_debug()
		KEY_H:
			for sq in _selected():
				sq.stop()
			for v in _selected_vehicles():
				v.stop()
		KEY_Q:
			camera.rotate_step(-1)
		KEY_E:
			camera.rotate_step(1)
		KEY_SPACE:
			enemy.counterattack(true)
		KEY_F2:
			for sq in _selected():
				for i in 10:
					sq.add_kill()
		KEY_R:
			get_tree().reload_current_scene()


# --- Building the FOB (engineers) -----------------------------------------------------

func hotkey_units() -> Array:
	## What 1-9 select: squads, then vehicles, in the order of the unit cards
	var out: Array = []
	for sq in squads:
		if not sq.soldiers.is_empty() and sq.kind != "gun_crew":
			out.append(sq)
	for v in vehicles:
		if not v.destroyed:
			out.append(v)
	out.append_array(guns)
	return out


func begin_build(kind: String) -> void:
	if not has_engineers():
		hud.push_message("You need an engineer squad to build (call one in with B)")
		return
	_cancel_calls()
	build_mode = kind
	_build_dragging = false
	_build_preview_key = ""
	if kind == "walls":
		hud.set_hint("FOB walls: drag out a rectangle on open ground (4 m grid).  Right-click or Esc to cancel")
	else:
		var where := " inside your walls" if kind in ["barracks", "shed"] else (" anywhere, on your wall line too" if kind == "tower" else "")
		hud.set_hint("%s: click to place it%s (shift-click: build it first).  R rotates.  Right-click or Esc to cancel" % [Structure.NAMES[kind], where])


func end_build() -> void:
	build_mode = ""
	_build_dragging = false
	_build_preview = []
	hud.set_hint("")


func _build_input(event: InputEvent) -> bool:
	## Mouse and keys while placing walls or a building. Returns true if it used the event.
	if event is InputEventMouseMotion:
		var hit := _ray((event as InputEventMouseMotion).position, 1)
		if not hit.is_empty():
			_build_cursor = hit.position
		return false     # let the camera edge-scroll etc. keep working
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			end_build()
			hud.push_message("Building cancelled")
			return true
		if k == KEY_R:
			_build_yaw = 0.0 if _build_yaw != 0.0 else PI * 0.5
			_build_preview_key = ""
			return true
		return false
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		end_build()
		hud.push_message("Building cancelled")
		return true
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	var hit := _ray(mb.position, 1)
	if hit.is_empty():
		return true
	_build_cursor = hit.position
	if build_mode == "walls":
		if mb.pressed:
			_build_from = hit.position
			_build_dragging = true
		elif _build_dragging:
			_build_dragging = false
			var why := fob.plan_walls(Fob.snap_rect(_build_from, hit.position))
			if why != "":
				hud.push_message(why)
			else:
				end_build()
		return true
	if mb.pressed:
		var at := _snap_building(hit.position)
		var why := fob.plan_building(build_mode, at, _build_yaw)
		if why != "":
			hud.push_message(why)
		else:
			if mb.shift_pressed and not fob.pieces.is_empty():
				if fob.prioritize(fob.pieces[-1]) > 0:
					hud.push_message("Engineers: building the %s first, then back to the rest" % Structure.NAMES[build_mode].to_lower())
			end_build()
	return true


func _snap_building(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, 1.0), 0.0, snappedf(p.z, 1.0))


func _build_overlay(items: Array) -> void:
	## Outlines of what you're about to place: green if it fits, red where it's blocked
	if build_mode == "":
		return
	var key := ""
	if build_mode == "walls":
		if _build_dragging:
			var r := Fob.snap_rect(_build_from, _build_cursor)
			key = str(r)
			if key != _build_preview_key:
				_build_preview_key = key
				_build_preview = []
				var layout := fob.wall_layout(r)
				var bad := fob.check_layout(layout)
				for i in layout.size():
					var probe := Structure.make(layout[i][0], layout[i][1], layout[i][2], "blue", layout[i][3])
					_build_preview.append([probe.footprint_world(), bad[i]])
					probe.free()
				var outline := PackedVector3Array([Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)])
				_build_preview.append([outline, false])
		else:
			var c := Vector3(snappedf(_build_cursor.x, Fob.GRID), 0, snappedf(_build_cursor.z, Fob.GRID))
			_build_preview = [[PackedVector3Array([c + Vector3(-2, 0, -2), c + Vector3(2, 0, -2), c + Vector3(2, 0, 2), c + Vector3(-2, 0, 2)]), false]]
	else:
		var at := _snap_building(_build_cursor)
		key = "%s %s" % [at, _build_yaw]
		if key != _build_preview_key:
			_build_preview_key = key
			var probe := Structure.make(build_mode, at, _build_yaw)
			_build_preview = [[probe.footprint_world(), fob.building_blocked(probe) != ""]]
			probe.free()
	for item in _build_preview:
		var pts := PackedVector2Array()
		for p in item[0]:
			pts.append(_to_screen(p))
		items.append([pts, Color(1.0, 0.35, 0.3) if item[1] else Color(0.55, 1.0, 0.55), true, 2.0])


# --- Units joining the battle ------------------------------------------------------

func _register_vehicle(v: Node3D) -> void:
	## Add a vehicle to every list that needs it (selection, Red targeting, transports, HUD)
	vehicles.append(v)
	enemy.vehicles.append(v)
	if v is Helicopter:
		helis.append(v)
		if v.squad_capacity > 0:
			transports.append(v)
	elif v is Stryker:
		transports.append(v)
	elif v is A10:
		a10s.append(v)
	v.crew.squad.wiped_out.connect(_on_wiped_out)
	v.message.connect(hud.push_message)
	hud.add_unit_card(v)


func _next_name(kind: String, base: String) -> String:
	_type_count[kind] = _type_count.get(kind, 0) + 1
	var n: int = _type_count[kind]
	return base if n == 1 else "%s %d" % [base, n]


func squad_count() -> int:
	## Rifle and engineer squads still alive (gun crews and pilots don't count)
	var n := 0
	for sq in squads:
		if sq.kind in ["rifle", "engineer"] and not sq.soldiers.is_empty():
			n += 1
	return n


func vehicle_count() -> int:
	var n := 0
	for v in vehicles:
		if not v.destroyed and not (v is A10):
			n += 1
	return n


func squad_limit() -> int:
	return fob.count_built("barracks") * SQUADS_PER_BARRACKS + limit_bonus


func vehicle_limit() -> int:
	return fob.count_built("shed") * VEHICLES_PER_SHED + limit_bonus


func reinforcement_blocked(id: String) -> String:
	## Why a unit can't be picked right now ("" = it can)
	if reinforcements <= 0:
		return "none available"
	# No unit limits: barracks refill squads and sheds repair vehicles, but neither caps them
	return ""


func limits_text() -> String:
	return "Squads %d · vehicles %d (no limits)" % [squad_count(), vehicle_count()]


func arrival_spot(big: bool) -> Vector3:
	## Where reinforcements turn up: at the start point you picked (spaced out from whatever
	## is already standing there). The self-test, with no start point, uses a west corner.
	var center: Vector3 = zone_pos(start_zone) if start_zone >= 0 else corner_pos(_rng.randi() % CORNERS.size())
	var inward := Vector3(-signf(center.x) if absf(center.x) > CityBuilder.HALF_X - 100.0 else 0.0, 0.0, -signf(center.z) if absf(center.z) > CityBuilder.HALF_Z - 50.0 else 0.0).normalized()
	var used: Array = []
	for sq in squads:
		for sd in sq.active_soldiers():
			if sd.global_position.distance_to(center) < 120.0:
				used.append(sd.global_position)
	for v in vehicles:
		if v.visible and not (v is A10) and v.global_position.distance_to(center) < 120.0:
			used.append(v.global_position)
	for g in guns:
		if g.global_position.distance_to(center) < 120.0:
			used.append(g.global_position)
	return _free_spot(center, inward, used, 16.0 if big else 12.0)


func reinforcement_note(id: String) -> String:
	## A warning to show next to an option that can be picked but has a catch
	if id == "a10" and free_runway_slots() == 0:
		return "no free runway slot: it crashes when its fuel runs out"
	if id == "engineer" and has_engineers():
		return ""
	return ""


func call_reinforcement(id: String) -> bool:
	var why := reinforcement_blocked(id)
	if why != "":
		hud.push_message("Can't call that in: %s" % why)
		return false
	reinforcements -= 1
	var spot := arrival_spot(id in ["chinook", "huey", "m777", "stryker", "apache", "mh6", "pls", "fuel", "lmtv", "bradley"])
	var where: String = zone_name(start_zone) if start_zone >= 0 else "a corner of the map"
	var to_fob := Vector3(-spot.x, 0.0, -spot.z)
	if not fob.rects.is_empty():
		to_fob = fob.center() - spot
	var yaw := rad_to_deg(atan2(-to_fob.x, -to_fob.z))
	var u = spawn_unit(id, spot, yaw, true)
	var label := ""
	if u is Squad:
		label = u.squad_name if u.kind != "rifle" else "%s squad" % u.squad_name
	elif u is A10:
		label = "A-10 %s" % u.callsign
	elif u != null:
		label = u.display_name
	arrivals.append([spot, 20.0])
	if id == "a10":
		hud.push_message("%s inbound from %s: %s" % [label, where, "it will land at the FOB" if u.has_slot else "no runway slot, so it goes on station and its fuel clock starts"])
	elif id == "m777":
		hud.push_message("M777 and its crew arrived at %s: send a Chinook to sling it forward" % where)
	else:
		hud.push_message("%s arrived at %s: bring them in" % [label, where])
	return true


func _selected() -> Array[Squad]:
	## Selected infantry squads that have soldiers on the ground
	var out: Array[Squad] = []
	for sq in squads:
		if sq.selected and not sq.active_soldiers().is_empty():
			out.append(sq)
	return out


func _selected_vehicles() -> Array:
	var out: Array = []
	for v in vehicles:
		if v.selected and v.visible and not v.destroyed:
			out.append(v)
	return out


func _selected_helis() -> Array:
	var out: Array = []
	for h in helis:
		if h.selected and not h.destroyed:
			out.append(h)
	return out


func carrier_of(sq: Squad) -> Node3D:
	## The helicopter or Stryker a squad (or the Humvee's crew) is riding in, or null
	for t in transports:
		if sq in t.passenger_squads():
			return t
		if t is Helicopter:
			for v in t.cargo:
				if v.crew.squad == sq:
					return t
	return null


func _select_only(typed_list: Array) -> void:
	var list: Array = []
	list.append_array(typed_list)    # plain array: it may hold squads and vehicles
	for sq in squads:
		sq.set_selected(sq in list)
	for v in vehicles:
		v.set_selected(v in list)
	for g in guns:
		g.set_selected(g in list)


func _selected_guns() -> Array:
	var out: Array = []
	for g in guns:
		if g.selected:
			out.append(g)
	return out


func _vehicle_screen_pos(v: Node3D) -> Vector2:
	return camera.unproject_position(v.global_position + Vector3.UP * 1.2) * pixel_scale


func _screen_pos(s: Soldier) -> Vector2:
	return camera.unproject_position(s.global_position + Vector3.UP * 0.9) * pixel_scale


func _finish_select(pos: Vector2, additive: bool) -> void:
	var picked: Array = []
	var rect := Rect2(_drag_start, pos - _drag_start).abs()
	if rect.size.length() < DRAG_THRESHOLD:
		# A vehicle under the cursor wins; otherwise the nearest soldier
		var vhit := _ray(pos, 8)
		if not vhit.is_empty() and vhit.collider in vehicles and not vhit.collider.destroyed:
			picked.append(vhit.collider)
		var best: Soldier = null
		var best_d := PICK_RADIUS
		for sq in squads:
			if not picked.is_empty():
				break
			if sq.kind == "gun_crew":
				continue          # gun crews go with their M777: you select the gun
			for s in sq.active_soldiers():
				var d := _screen_pos(s).distance_to(pos)
				if d < best_d:
					best_d = d
					best = s
		if best != null:
			picked.append(best.squad)
		# Nothing else there: the M777 under the cursor
		if picked.is_empty():
			var ghit := _ray(pos, 1)
			if not ghit.is_empty():
				var g := _gun_at(ghit)
				if g != null:
					picked.append(g)
	else:
		for sq in squads:
			if sq.kind == "gun_crew":
				continue
			for s in sq.active_soldiers():
				if rect.has_point(_screen_pos(s)):
					picked.append(sq)
					break
		for v in vehicles:
			if v.visible and not v.destroyed and rect.has_point(_vehicle_screen_pos(v)):
				picked.append(v)
		for g in guns:
			if g.slung_by == null and rect.has_point(camera.unproject_position(g.global_position + Vector3.UP) * pixel_scale):
				picked.append(g)
	var clicked := rect.size.length() < DRAG_THRESHOLD
	if clicked and picked.size() == 1 and picked[0].selected:
		# Clicking a unit that's already selected drops it from the selection
		picked[0].set_selected(false)
	elif additive:
		for u in picked:
			u.set_selected(true)
	else:
		_select_only(picked)


func _ray(screen_pos: Vector2, mask: int) -> Dictionary:
	var vp := screen_pos / float(pixel_scale)
	var from := camera.project_ray_origin(vp)
	var to := from + camera.project_ray_normal(vp) * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return level.get_world_3d().direct_space_state.intersect_ray(q)


func _order_move(screen_pos: Vector2) -> void:
	var sel := _selected()
	var vsel := _selected_vehicles()
	if sel.is_empty() and vsel.is_empty():
		return
	# Right-clicking a transport with infantry (or a Humvee) selected: they climb aboard.
	# A hovering helicopter lands for them; the Stryker stops.
	var vhit := _ray(screen_pos, 8)
	# Right-clicking a vehicle or helicopter with the fuel truck selected: go and fill it up
	if not vhit.is_empty() and vhit.collider in vehicles and vhit.collider.has_method("needs_fuel") and not vhit.collider.destroyed:
		var trucks: Array = []
		for v in vsel:
			if v is FuelTruck and v != vhit.collider:
				trucks.append(v)
		for t in trucks:
			var why: String = t.go_refuel(vhit.collider)
			if why != "":
				hud.push_message(why)
			vsel.erase(t)
		if not trucks.is_empty() and sel.is_empty() and vsel.is_empty():
			return
	if not vhit.is_empty() and vhit.collider in transports and not vhit.collider.destroyed:
		var riders: Array = []
		for v in vsel:
			if v is GroundVehicle and v.air_mobile and v != vhit.collider:
				riders.append(v)
		if not sel.is_empty() or not riders.is_empty():
			_order_board(sel, vhit.collider, riders)
			return
	var hit := _ray(screen_pos, 1)
	if hit.is_empty():
		return
	var point: Vector3 = hit.position
	# Right-clicking a supply pallet: a PLS goes to load it, a Chinook to hook it
	var pallet := _pallet_at(point)
	if pallet != null:
		var used := false
		for v in vsel.duplicate():
			if v is Pls:
				var why: String = v.go_load(pallet)
				if why != "":
					hud.push_message(why)
				vsel.erase(v)
				used = true
			elif v is Chinook:
				if v.sling_gun != null:
					hud.push_message("The %s already has a sling load" % v.display_name)
				else:
					v.start_sling(pallet)
				vsel.erase(v)
				used = true
		if used and sel.is_empty() and vsel.is_empty():
			return
	# Right-clicking one of your own pieces: engineers build that first; infantry climb a tower
	var mine := _own_piece_at(hit)
	if mine != null:
		if mine.state in ["planned", "building"]:
			var engs: Array = []
			for sq in sel:
				if sq.kind == "engineer":
					engs.append(sq)
			if not engs.is_empty():
				fob.prioritize(mine, engs)
				for sq in engs:
					sel.erase(sq)
				hud.push_message("Engineers: building the %s now, then back to the rest" % mine.display_name().to_lower())
				if sel.is_empty() and vsel.is_empty():
					return
		elif mine.kind == "tower" and mine.state == "built" and not sel.is_empty():
			var free: int = mine.tower_free()
			var sent := 0
			for sq in sel:
				for sd in sq.active_soldiers():
					if sent >= free:
						break
					sd.order_move(NavigationServer3D.map_get_closest_point(level.get_navigation_map(), mine.door_point(sd.global_position)))
					sd.board_target = mine
					sent += 1
			hud.push_message("%d soldier%s climbing the watch tower" % [sent, "" if sent == 1 else "s"] if sent > 0 else "The watch tower is full")
			if vsel.is_empty():
				return
	# Right-clicking a Red FOB wall or gate with engineers: blow a breach in it
	var red_wall := _red_wall_at(hit)
	if red_wall != null:
		var any := false
		for sq in sel.duplicate():
			if sq.kind == "engineer":
				order_breach(sq, red_wall)
				sel.erase(sq)
				any = true
				break
		if any and sel.is_empty() and vsel.is_empty():
			return
	for sq in sel:
		if sq.kind == "engineer":
			sq.set_meta("breaching", false)
	# Right-clicking the M777: a Chinook goes to sling it, its crew goes to man it
	var clicked := _gun_at(hit)
	if clicked != null:
		var used := false
		for v in vsel:
			if v is Chinook:
				_order_sling(v, clicked)
				vsel.erase(v)
				used = true
				break
		for sq in sel.duplicate():
			if sq.kind == "gun_crew":
				var own := gun_of(sq)
				if own != clicked:
					continue      # each crew mans its own gun
				var n := clicked.call_crew(level.get_navigation_map())
				hud.push_message("%s manning the %s" % [sq.squad_name, clicked.display_name] if n > 0 else "%s is already on the gun" % sq.squad_name)
				sel.erase(sq)
				used = true
		if used and sel.is_empty() and vsel.is_empty():
			return
	_stand_down(sel)
	_order_vehicles(vsel, point)
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	for i in sel.size():
		var offset := right * (i - (sel.size() - 1) * 0.5) * 4.0
		sel[i].order_move(point + offset, level.get_navigation_map())


func _own_piece_at(hit: Dictionary) -> Structure:
	## One of your FOB pieces under a click (planned ones aren't solid, so by footprint)
	if hit.collider is Structure and hit.collider.side == "blue" and hit.collider.state != "removed":
		return hit.collider
	for st in fob.pieces:
		if is_instance_valid(st) and st.state in ["planned", "building"] and st.kind != "runway" and st.flat_distance(hit.position) < 0.5:
			return st
	return null


func _gun_at(hit: Dictionary) -> Artillery:
	## The M777 (on the ground) under a click, or null
	for g in guns:
		if g.slung_by != null:
			continue
		if hit.collider == g._body:
			return g
		var p: Vector3 = hit.position
		if Vector2(p.x - g.global_position.x, p.z - g.global_position.z).length() < 3.0:
			return g
	return null


func _stand_down(sel: Array) -> void:
	## You moved the gun crew somewhere: they stay there instead of drifting back to the gun
	for sq in sel:
		if sq.kind == "gun_crew":
			sq.set_meta("stand_down", true)


func _order_sling(ch: Chinook, gun: Artillery) -> void:
	## Hook the M777 under the Chinook. Its crew has to be aboard (they take a squad's place).
	if ch.destroyed or ch.crew.count() == 0:
		return
	if ch.sling_gun != null:
		hud.push_message("The %s already has the M777" % ch.display_name)
		return
	var crew_sq := gun.crew_squad
	if ch.crew_aboard(gun):
		ch.start_sling(gun)
		return
	var ride := carrier_of(crew_sq)
	if ride != null and ride != ch:
		hud.push_message("The gun crew is in the %s: unload them first, the crew has to fly with the gun" % ride.display_name)
		return
	if not (crew_sq in ch.committed_squads()) and ch.committed_squads().size() >= ch.max_squads(ch.committed_vehicles()):
		hud.push_message("No room for the gun crew in the %s: they take one squad's place (%s)" % [ch.display_name, ch.capacity_text()])
		return
	_order_board([crew_sq], ch)
	ch.sling_pending = gun
	hud.push_message("The gun crew has to fly with the gun: they're boarding the %s, then it hooks the M777" % ch.display_name)


func _slung_selected() -> Array:
	var out: Array = []
	for h in _selected_helis():
		if h is Chinook and h.is_slung():
			out.append(h)
	return out


func _drop_plan() -> Dictionary:
	## Right-drag with a slung Chinook selected: where the gun goes and which way it faces
	if _line_points.size() < 2:
		return {}
	var a: Vector3 = _line_points[0]
	var b: Vector3 = _line_points[-1]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 2.0:
		return {}
	var at := level.ground_spot(a, 20.0)
	return {"at": at, "yaw": atan2(-d.x, -d.z), "fwd": d.normalized()}


func _wedge(items: Array, origin: Vector3, fwd: Vector3, color: Color, reach: float) -> void:
	var arc := deg_to_rad(Artillery.ARC_HALF_DEG)
	var wedge := PackedVector2Array()
	for k in 13:
		var dir := fwd.rotated(Vector3.UP, lerpf(-arc, arc, k / 12.0))
		wedge.append(_to_screen(origin + dir * Artillery.MIN_RANGE))
	for k in 13:
		var dir := fwd.rotated(Vector3.UP, lerpf(arc, -arc, k / 12.0))
		wedge.append(_to_screen(origin + dir * reach))
	items.append([wedge, color, true, 2.0])


func _vehicle_slots(vsel: Array, point: Vector3, face := NAN) -> Array:
	## Where each selected vehicle and helicopter goes for a move order: side by side across
	## the facing (or across the screen with no facing), nearest ones to the nearest slots.
	## Returns [[unit, spot], ...]; the A-10 isn't in it.
	var out: Array = []
	var fwd := Vector3(-sin(face), 0.0, -cos(face))
	if is_nan(face):
		fwd = -camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var nav := level.get_navigation_map()
	for group in [true, false]:
		var list: Array = []
		var spacing := 0.0
		for v in vsel:
			if (v is GroundVehicle) == group and (v is GroundVehicle or v is Helicopter):
				list.append(v)
				spacing = maxf(spacing, v.ring_radius * (2.2 if group else 2.6))
		if list.is_empty():
			continue
		list.sort_custom(func(a, b): return right.dot(a.global_position - point) < right.dot(b.global_position - point))
		# Helicopters line up behind the vehicles when both are sent
		var back := 0.0 if group or out.is_empty() else -spacing
		for i in list.size():
			var spot: Vector3 = point + right * (i - (list.size() - 1) * 0.5) * spacing + fwd * back
			if group and list.size() > 1:
				spot = NavigationServer3D.map_get_closest_point(nav, spot)
			out.append([list[i], spot])
	return out


func _queue_move(screen_pos: Vector2) -> bool:
	## Add a waypoint to every selected vehicle and helicopter's route. False if none selected.
	var vsel: Array = []
	for v in _selected_vehicles():
		if v.has_method("queue_fly") or v.has_method("queue_move"):
			vsel.append(v)
	if vsel.is_empty():
		return false
	var hit := _ray(screen_pos, 1)
	if hit.is_empty():
		return true
	var point: Vector3 = hit.position
	for v in vsel:
		if v.has_method("queue_fly"):
			v.queue_fly(point)
		else:
			v.queue_move(NavigationServer3D.map_get_closest_point(level.get_navigation_map(), point))
	return true


func _move_plan() -> Dictionary:
	## Right-drag with vehicles or helicopters selected: they go where the drag started and
	## face the way it was dragged
	if _line_points.size() < 2:
		return {}
	var a: Vector3 = _line_points[0]
	var b: Vector3 = _line_points[-1]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 2.0:
		return {}
	return {"at": a, "yaw": atan2(-d.x, -d.z), "end": b}


func _order_vehicles(vsel: Array, point: Vector3, face := NAN) -> void:
	for pair in _vehicle_slots(vsel, point, face):
		var v = pair[0]
		if v is GroundVehicle:
			v.order_move(pair[1], face)
		else:
			v.order_fly(pair[1], face)
	for v in vsel:
		if v is A10:
			var why: String = v.order_orbit(point)
			if why != "":
				hud.push_message(why)
			else:
				var aa := false
				for t in enemy.tanks:
					if t is RedAA and t.alive and Vector2(t.global_position.x - point.x, t.global_position.z - point.z).length() < RedAA.AA_RANGE + A10.LOITER_RADIUS:
						aa = true
				hud.push_message("%s: orbiting there until it needs fuel or ammo%s" % [v.callsign, "  —  WARNING: inside Red anti-air reach" if aa else ""])


func _nearest_transport(from: Vector3, want_vehicles := false) -> Node3D:
	var best: Node3D = null
	for t in transports:
		if t.destroyed or t.crew.count() == 0 or (want_vehicles and t.vehicle_capacity == 0):
			continue
		if best == null or t.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = t
	return best


func _order_board(sel: Array, carrier: Node3D = null, riders: Array = []) -> void:
	## Send infantry squads (and Humvees, for the Chinook) to a transport
	if carrier == null:
		for t in transports:
			if t.selected and not t.destroyed:
				carrier = t
				break
		if carrier == null:
			var from: Vector3 = sel[0].active_soldiers()[0].global_position if not sel.is_empty() else riders[0].global_position
			carrier = _nearest_transport(from, not riders.is_empty() and sel.is_empty())
	if carrier == null:
		hud.push_message("Nothing left to ride in")
		return
	if carrier.crew.count() == 0:
		hud.push_message("The %s has no crew left" % carrier.display_name)
		return
	if carrier is Chinook and carrier.sling_gun != null:
		hud.push_message("The %s can't land with the M777 slung under it: set the gun down first" % carrier.display_name)
		return
	var nav := level.get_navigation_map()
	var vehicles_n: int = carrier.committed_vehicles()
	var aboard: Array = carrier.committed_squads()
	var accepted_v: Array = []
	for v in riders:
		if carrier.vehicle_capacity == 0:
			hud.push_message("The %s can't carry vehicles: use the Chinook" % carrier.display_name)
			break
		if v.carried_by != null or v.board_target == carrier:
			continue
		if vehicles_n + 1 > carrier.vehicle_capacity or aboard.size() > carrier.max_squads(vehicles_n + 1):
			hud.push_message("No room for the Humvee in the %s (%s)" % [carrier.display_name, carrier.capacity_text()])
			continue
		vehicles_n += 1
		accepted_v.append(v)
	var accepted_s: Array = []
	for sq in sel:
		if not (sq in aboard) and aboard.size() >= carrier.max_squads(vehicles_n):
			hud.push_message("The %s is full (%s)" % [carrier.display_name, carrier.capacity_text()])
			continue
		if not (sq in aboard):
			aboard.append(sq)
		accepted_s.append(sq)
	if accepted_s.is_empty() and accepted_v.is_empty():
		return
	carrier.request_pickup()
	var names: PackedStringArray = []
	for sq in accepted_s:
		for s in sq.active_soldiers():
			var door: Vector3 = carrier.door_point(s.global_position)
			s.order_move(NavigationServer3D.map_get_closest_point(nav, door))
			s.board_target = carrier
			carrier.add_inbound(s)
		names.append(sq.squad_name)
	for v in accepted_v:
		var door: Vector3 = carrier.door_point(v.global_position)
		v.order_move(NavigationServer3D.map_get_closest_point(nav, door))
		v.board_target = carrier
		carrier.add_inbound(v)
		names.append("Humvee")
	hud.push_message("%s boarding the %s" % [", ".join(names), carrier.display_name])


func _call_artillery(screen_pos: Vector2) -> void:
	_targeting = false
	var hit := _ray(screen_pos, 1 | 8)
	if hit.is_empty():
		return
	var accepted: Array = []
	var reason := "No available artillery"
	for g in fire_guns():
		var why: String = g.call_fire(hit.position)
		if why == "":
			accepted.append(g)
		else:
			reason = why
	_fire_guns = []
	if accepted.is_empty():
		hud.push_message(reason)
		return
	# Several guns: the rounds fall at random inside a circle that grows with the number of guns
	var spread := Artillery.spread_for(accepted.size())
	for g in accepted:
		g.mission_spread = spread
	var close := false
	for s in enemy.soldiers:
		if s.global_position.distance_to(hit.position) < Artillery.BLAST_RADIUS + spread:
			close = true
	var wait := INF
	for g in accepted:
		wait = minf(wait, g.seconds_to_ready())
	var when := "on the way" if wait < 1.0 else "first round in %d s" % ceili(wait)
	var who: String = accepted[0].display_name if accepted.size() == 1 else "%d guns" % accepted.size()
	hud.push_message("Fire mission (%s): %s%s" % [who, when, "  —  DANGER CLOSE" if close else ""])


func _ready_a10() -> A10:
	## Prefer a selected one, then one already overhead with ammo, then one ready on the runway
	for a in a10s:
		if a.selected and a.is_ready():
			return a
	for a in a10s:
		if a.is_ready() and a.state == "loiter":
			return a
	for a in a10s:
		if a.is_ready():
			return a
	return null


func _a10_unavailable() -> String:
	var parts: PackedStringArray = []
	for a in a10s:
		parts.append("%s %s" % [a.callsign, a.status_text()])
	return "No A-10 available (%s)" % ", ".join(parts)


func _call_a10(from: Vector3, to: Vector3) -> void:
	_a10_targeting = false
	_a10_dragging = false
	var jet := _ready_a10()
	if jet == null:
		hud.push_message(_a10_unavailable())
		return
	var reason := jet.call_run(from, to)
	if reason != "":
		hud.push_message(reason)
		return
	var close := false
	for s in enemy.soldiers:
		if _dist_to_segment(s.global_position, from, to) < A10.SPREAD + 4.0:
			close = true
	if close:
		hud.push_message("Gun run DANGER CLOSE: your troops are on the line")


func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := 0.0 if ab.length_squared() < 0.01 else clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (ap - ab * t).length()


func _to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) * pixel_scale


func _ring_screen(center: Vector3, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(_to_screen(center + Vector3(cos(a) * radius, 0.05, sin(a) * radius)))
	return pts


# --- Drawn formations (right-click + drag any shape) ------------------------

func _begin_line(screen_pos: Vector2) -> void:
	_line_dragging = false
	_line_moved = false
	_line_points.clear()
	if _selected().is_empty() and _selected_vehicles().is_empty():
		return
	var hit := _ray(screen_pos, 1)
	if hit.is_empty():
		return
	_line_start = screen_pos
	_line_points.append(hit.position)
	_line_dragging = true


func _end_line(screen_pos: Vector2) -> void:
	if not _line_dragging:
		return
	_line_dragging = false
	hud.set_formation([], PackedVector2Array())
	if not _line_moved:
		if Input.is_key_pressed(KEY_SHIFT) and _queue_move(_line_start):
			return                  # shift + right-click: one more waypoint for vehicles and helicopters
		_order_move(_line_start)    # plain right-click: move as squads
		return
	_record_point(screen_pos)
	if not _selected().is_empty():
		_stand_down(_selected())
		order_path(_line_points)
	# A slung M777 is set down where the drag started, facing along it
	var vsel := _selected_vehicles()
	var slung := _slung_selected()
	if not slung.is_empty():
		var plan := _drop_plan()
		if not plan.is_empty():
			slung[0].order_drop(plan.at, plan.yaw)
			vsel.erase(slung[0])
	# Vehicles and helicopters go where the drag started and face the way it was dragged
	var plan := _move_plan()
	if plan.is_empty():
		_order_vehicles(vsel, _line_points[0])
	else:
		_order_vehicles(vsel, plan.at, plan.yaw)


func _preview_line(screen_pos: Vector2) -> void:
	if not _line_moved and screen_pos.distance_to(_line_start) < DRAG_THRESHOLD:
		return
	_line_moved = true
	_record_point(screen_pos)
	if _line_points.size() < 2:
		return
	if _selected().is_empty():
		_preview_vehicle_move()
		return
	var plan := plan_path(_line_points)
	var marks: Array = []
	for i in plan.soldiers.size():
		var sd: Soldier = plan.soldiers[i]
		marks.append([camera.unproject_position(plan.slots[i]) * pixel_scale, sd.squad.color])
	var trail := PackedVector2Array()
	for p in _line_points:
		trail.append(camera.unproject_position(p) * pixel_scale)
	if plan.closed:
		trail.append(trail[0])
	hud.set_formation(marks, trail)


func _preview_vehicle_move() -> void:
	## While right-dragging vehicles: a dot where each one will park and an arrow for the facing
	var vsel := _selected_vehicles()
	for g in _slung_selected():
		vsel.erase(g)
	var plan := _move_plan()
	if vsel.is_empty() or plan.is_empty():
		hud.set_formation([], PackedVector2Array())
		return
	var marks: Array = []
	for pair in _vehicle_slots(vsel, plan.at, plan.yaw):
		var c := Color(0.55, 0.85, 1.0) if pair[0] is Helicopter else Color(0.6, 1.0, 0.55)
		marks.append([_to_screen(pair[1]), c])
	var length := maxf(6.0, Vector2(plan.end.x - plan.at.x, plan.end.z - plan.at.z).length())
	hud.set_formation(marks, _arrow_screen(plan.at, plan.yaw, length))


func _record_point(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, 1)
	if hit.is_empty():
		return
	var p: Vector3 = hit.position
	var last: Vector3 = _line_points[_line_points.size() - 1]
	if Vector2(p.x - last.x, p.z - last.z).length() >= LINE_SAMPLE:
		_line_points.append(p)


func order_path(points: Array[Vector3]) -> void:
	## Spread every selected soldier evenly along the drawn shape.
	var plan := plan_path(points)
	for i in plan.soldiers.size():
		(plan.soldiers[i] as Soldier).order_move(plan.slots[i], plan.facing[i])


func plan_path(points: Array[Vector3]) -> Dictionary:
	var soldiers: Array = []
	for sq in _selected():
		soldiers.append_array(sq.active_soldiers())
	var n := soldiers.size()
	var pts: Array[Vector3] = points.duplicate()
	if pts.size() == 1:
		pts.append(pts[0] + Vector3(0.01, 0, 0))

	var length := _path_length(pts, false)
	var gap := Vector2(pts[-1].x - pts[0].x, pts[-1].z - pts[0].z).length()
	# A shape that ends back near where it started is a loop (circle, square, ...)
	var closed := n > 2 and length > 4.0 and gap < maxf(1.5, length * 0.2)

	var centroid := Vector3.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()

	if closed:
		# Loop too small for everyone: grow it around its centre
		var perimeter := _path_length(pts, true)
		var need := MIN_LINE_SPACING * n
		if perimeter < need:
			var k := need / perimeter
			for i in pts.size():
				var off := pts[i] - centroid
				pts[i] = centroid + Vector3(off.x * k, off.y, off.z * k)
	elif n > 1 and length < MIN_LINE_SPACING * (n - 1):
		# Line too short: extend it past the end in the direction it was heading
		var tail := Vector3(pts[-1].x - pts[-2].x, 0.0, pts[-1].z - pts[-2].z)
		if tail.length() < 0.01:
			tail = camera.global_transform.basis.x
			tail.y = 0.0
		pts.append(pts[-1] + tail.normalized() * (MIN_LINE_SPACING * (n - 1) - length))

	# Evenly spaced positions along the shape (a loop has no repeated end point)
	var total := _path_length(pts, closed)
	var slots: Array[Vector3] = []
	var tangents: Array[Vector3] = []
	for i in n:
		var t: float
		if closed:
			t = total * float(i) / n
		elif n == 1:
			t = total * 0.5
		else:
			t = total * float(i) / (n - 1)
		var sample := _point_at(pts, closed, t)
		slots.append(sample[0])
		tangents.append(sample[1])

	# Facing: outward for a loop; for a line, away from the camera side (up the screen)
	var cam_fwd := -camera.global_transform.basis.z
	cam_fwd = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var facing: Array[Vector3] = []
	for i in n:
		var tan: Vector3 = tangents[i]
		var nrm := Vector3(tan.z, 0.0, -tan.x)
		var away := slots[i] - centroid
		if closed:
			if nrm.dot(Vector3(away.x, 0.0, away.z)) < 0.0:
				nrm = -nrm
		elif nrm.dot(cam_fwd) < 0.0:
			nrm = -nrm
		facing.append(nrm)

	# Who goes where: match soldiers to slots in the same order along the shape,
	# so nobody crosses through the group to reach the far side
	var order := _assign(soldiers, slots, closed, centroid)

	var nav := level.get_navigation_map()
	var out_soldiers: Array = []
	var out_slots: Array[Vector3] = []
	var out_facing: Array[Vector3] = []
	for i in n:
		out_soldiers.append(order[i])
		out_slots.append(NavigationServer3D.map_get_closest_point(nav, slots[i]))
		out_facing.append(facing[i])
	return {"soldiers": out_soldiers, "slots": out_slots, "facing": out_facing, "closed": closed}


func _assign(soldiers: Array, slots: Array[Vector3], closed: bool, centroid: Vector3) -> Array:
	var n := soldiers.size()
	if n <= 1:
		return soldiers.duplicate()
	var ordered := soldiers.duplicate()
	if closed:
		# Sort by angle around the loop's centre, then try every rotation of the ring
		ordered.sort_custom(func(s1, s2):
			return _angle(s1.global_position, centroid) < _angle(s2.global_position, centroid))
		var slot_order: Array = range(n)
		slot_order.sort_custom(func(i1, i2):
			return _angle(slots[i1], centroid) < _angle(slots[i2], centroid))
		var best_shift := 0
		var best_cost := INF
		for shift in n:
			var cost := 0.0
			for k in n:
				cost += ordered[(k + shift) % n].global_position.distance_to(slots[slot_order[k]])
			if cost < best_cost:
				best_cost = cost
				best_shift = shift
		var result: Array = []
		result.resize(n)
		for k in n:
			result[slot_order[k]] = ordered[(k + best_shift) % n]
		return result
	# Open line: keep the soldiers' left-to-right order along the line, either way round
	var dir := Vector3(slots[-1].x - slots[0].x, 0.0, slots[-1].z - slots[0].z).normalized()
	ordered.sort_custom(func(s1, s2): return s1.global_position.dot(dir) < s2.global_position.dot(dir))
	return ordered


func _angle(p: Vector3, c: Vector3) -> float:
	return atan2(p.z - c.z, p.x - c.x)


func _path_length(pts: Array[Vector3], closed: bool) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += _flat_dist(pts[i - 1], pts[i])
	if closed:
		total += _flat_dist(pts[-1], pts[0])
	return total


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func _point_at(pts: Array[Vector3], closed: bool, t: float) -> Array:
	## Point and direction at distance t along the shape
	var count := pts.size() + (1 if closed else 0)
	var walked := 0.0
	for i in range(1, count):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i % pts.size()]
		var seg := _flat_dist(a, b)
		if seg < 0.0001:
			continue
		if walked + seg >= t or i == count - 1:
			var f := clampf((t - walked) / seg, 0.0, 1.0)
			var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			return [a.lerp(b, f), tan]
		walked += seg
	return [pts[-1], Vector3.RIGHT]


# --- HUD --------------------------------------------------------------------

func _on_off(v: bool) -> String:
	return "on" if v else "off"


func _update_hud() -> void:
	## Developer stats panel (F4)
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var obj_lines: PackedStringArray = []
	for o in enemy.objectives:
		obj_lines.append("%s: %s  red %d / blue %d  %d%%" % [o.name, o.owner, o.red, o.blue, int(o.progress * 100.0)])
	hud.info.text = "TAKING BACK DFW  —  M1 push in and clear\n" \
		+ "Time %d:%02d   Counterattack %d in %d s\n" % [floori(battle_time / 60.0), floori(fmod(battle_time, 60.0)), enemy.wave + 1, ceili(enemy.next_wave_in)] \
		+ "Red riflemen %d   tanks %d   killed %d / %d tanks\n" % [enemy.alive.size(), enemy.tanks.size(), enemy.kills, enemy.tanks_destroyed] \
		+ "\n".join(obj_lines) + "\n" \
		+ "FPS %d   Physics %.1f ms   Effects %d" % [Engine.get_frames_per_second(), phys_ms, enemy.gibs.chunk_count]
	var lines: PackedStringArray = []
	for sq in squads:
		var tag := "> " if sq.selected else ""
		if sq.soldiers.is_empty():
			lines.append("%s%s  WIPED OUT" % [tag, sq.squad_name.to_upper()])
			continue
		var next := "MAX" if sq.is_maxed() else "%d/%d" % [sq.kills_into_level, sq.next_level_at]
		var ride := carrier_of(sq)
		var where := "  (in %s)" % ride.display_name if ride != null else ""
		lines.append("%s%s  %d/%d  Lv %d  kills %d  next %s%s" % [tag, sq.squad_name.to_upper(), sq.soldiers.size(), sq.max_members, sq.total_level(), sq.kills, next, where])
	var gun := artillery
	if gun != null:
		lines.append("M777  crew %d/4  Lv %d/%d  %d s/shot  kills %d" % [gun.crew_count(), gun.level, Artillery.MAX_LEVEL, int(gun.cycle_time()), gun.kills])
	lines.append("FOB: %d rects, %d pieces left, barracks %s, shed %s, runway slots %d free" % [fob.rects.size(), fob.unfinished().size(), fob.has_built("barracks"), fob.has_built("shed"), free_runway_slots()])
	for v in vehicles:
		if v is GroundVehicle:
			lines.append("%s  crew %d  hp %d  %s" % [v.display_name.to_upper(), v.crew.count(), int(v.hp), "WRECK" if v.destroyed else ("driving" if v.driving else "parked")])
	for h in helis:
		lines.append("%s  crew %d  hp %d  %s%s" % [h.display_name.to_upper(), h.crew.count(), int(h.hp), h.state_name(), "  (hover mode)" if h.hover_mode else ""])
	for a in a10s:
		lines.append("%s  %s  fuel %d s  runs %d  kills %d" % [a.callsign.to_upper(), a.status_text(), int(a.fuel), a.runs_left, a.kills])
	hud.squads_label.text = "\n".join(lines)


# --- Headless self-test -----------------------------------------------------

func _start_autotest() -> void:
	print("AUTOTEST: start")


func _test_objective(i: int) -> Dictionary:
	return enemy.objectives[i] if i < enemy.objectives.size() else {}


func _nearest_tank(to: Vector3) -> RedTank:
	var best: RedTank = null
	for t in enemy.tanks:
		if best == null or t.global_position.distance_to(to) < best.global_position.distance_to(to):
			best = t
	return best


var _test_tank: RedTank
var _test_tank2: RedTank


func _support_selftest(delta: float) -> void:
	# Look at Globe Life Field first, the way a player would before calling fire on it
	if _at(4.5, delta):
		camera.focus = _test_objective(0).pos
		camera.size = 70.0
		camera._target_size = 70.0
	# M777: one call behind the gun (must be refused), one toward Globe Life Field via G + click
	if _at(5.0, delta):
		var behind := artillery.to_global(Vector3(0, 0, 25))
		print("AUTOTEST: M777 — call behind the gun: \"%s\"" % artillery.call_fire(behind))
		var glf: Vector3 = _test_objective(0).pos
		_on_key(KEY_G)
		_click(MOUSE_BUTTON_LEFT, _to_screen(glf))
		print("AUTOTEST: M777 — call on Globe Life Field via G + click: mission=%s target=%s in field %s" % [artillery.has_mission, artillery.mission_target.round(), artillery.in_field(glf)])
	# A-10: V + drag a line over the Globe Life Field tank
	if _at(7.0, delta):
		_test_tank = _nearest_tank(_test_objective(0).pos)
		var tp := _test_tank.global_position
		_call_a10(tp + Vector3(-10, 0, -35), tp + Vector3(10, 0, 35))
		print("AUTOTEST: A-10 — gun run called on the Globe Life Field tank at %s: state %s" % [tp.round(), a10s[0].state])
		camera.focus = Vector3(-10, 0, 10)
	if _at(12.0, delta):
		print("AUTOTEST: A-10 — after 5 s: state %s, height %.0f m, pos %s" % [a10s[0].state, a10s[0].global_position.y, a10s[0].global_position.round()])
	if _at(39.5, delta):
		_test_tank2 = _nearest_tank(_test_objective(2).pos)
		camera.focus = _test_tank2.global_position
	if _at(40.0, delta):
		print("AUTOTEST: A-10 — t=40: state %s, runs left %d, fuel %d, kills %d | tank alive %s hp %d" % [a10s[0].state, a10s[0].runs_left, int(a10s[0].fuel), a10s[0].kills, _test_tank.alive, int(_test_tank.hp)])
		# Second run through the real input: V, then drag a line over a Downtown Arlington tank
		var tp2 := _test_tank2.global_position
		_on_key(KEY_V)
		_drag(MOUSE_BUTTON_LEFT, _to_screen(tp2 + Vector3(0, 0, -40)), _to_screen(tp2 + Vector3(0, 0, 40)))
		print("AUTOTEST: A-10 — V + drag over the tank at %s: line %s -> %s, state %s" % [tp2.round(), _a10_from.round(), _a10_to.round(), a10s[0].state])
		camera.focus = Vector3(-10, 0, 10)
	if _at(75.0, delta):
		print("AUTOTEST: A-10 — t=75: state %s, runs left %d, fuel %d, kills %d | 2nd tank alive %s hp %d" % [a10s[0].state, a10s[0].runs_left, int(a10s[0].fuel), a10s[0].kills, _test_tank2.alive, int(_test_tank2.hp)])
		_on_key(KEY_V)
		print("AUTOTEST: A-10 — V with no jet ready: targeting %s" % _a10_targeting)
	if _at(140.0, delta):
		print("AUTOTEST: A-10 — t=140: state %s at %s, rearm left %d, fuel %d, runs %d" % [a10s[0].state, a10s[0].global_position.round(), int(a10s[0].rearm_left), int(a10s[0].fuel), a10s[0].runs_left])
	# Stryker: Alpha climbs in from the roof by right-clicking it, rides toward Globe Life Field, unloads
	if _at(9.0, delta):
		_select_only([squads[0]])
		_click(MOUSE_BUTTON_RIGHT, _to_screen(stryker.global_position + Vector3.UP * 1.3))
		var walking := 0
		for sd in squads[0].soldiers:
			if sd.board_target == stryker:
				walking += 1
		print("AUTOTEST: Stryker — right-click with Alpha selected: %d soldiers heading to it" % walking)
	if _at(34.0, delta):
		print("AUTOTEST: Stryker — aboard: %d soldiers (%d squads)" % [stryker.passengers.size(), stryker.passenger_squads().size()])
		_select_only([stryker])
		_order_vehicles([stryker], Vector3(-185, 0, 12))
	if _at(62.0, delta):
		print("AUTOTEST: Stryker — at %s, hp %d" % [stryker.global_position.round(), int(stryker.hp)])
		_select_only([stryker])
		_on_key(KEY_U)
		_select_only([squads[0]])
		squads[0].order_move(_test_objective(0).pos, level.get_navigation_map())
	if _at(130.0, delta):
		var o := _test_objective(0)
		print("AUTOTEST: Globe Life Field — owner %s, red %d, blue %d, progress %d%% | Alpha %d alive, kills %d, Lv %d | Stryker hp %d" % [o.owner, o.red, o.blue, int(o.progress * 100.0), squads[0].soldiers.size(), squads[0].kills, squads[0].total_level(), int(stryker.hp)])
	# Huey: Bravo boards by right-clicking the Huey, it flies across the FOB, then unloads
	if _at(10.0, delta):
		_select_only([squads[1]])
		_click(MOUSE_BUTTON_RIGHT, _to_screen(huey.global_position + Vector3.UP * 1.3))
	if _at(32.0, delta):
		print("AUTOTEST: Huey — aboard: %d soldiers, state %s" % [huey.passengers.size(), huey.state])
		_order_vehicles([huey], Vector3(-5.0, 0.0, -15.0))
	if _at(58.0, delta):
		_select_only([huey])
		_on_key(KEY_U)
	if _at(63.0, delta):
		print("AUTOTEST: Huey — after unload: Bravo on the ground %d/%d, Huey %s" % [squads[1].active_soldiers().size(), squads[1].soldiers.size(), huey.state])
	# Red Army counterattack (normally every 2 minutes; Space forces one)
	if _at(118.0, delta):
		_on_key(KEY_SPACE)
	if _at(146.0, delta):
		var best := INF
		for sq in enemy.squads:
			if sq.role == "assault" or sq.post.distance_to(Vector3.ZERO) < 30.0:
				for m in sq.alive_members():
					best = minf(best, m.global_position.distance_to(Vector3.ZERO))
		print("AUTOTEST: counterattack — closest attacker %.0f m from the FOB, assault squads %d" % [best, enemy.squads.filter(func(q): return q.role == "assault").size()])
	_chinook_selftest(delta)
	_reinforce_selftest(delta)
	_fob_selftest(delta)
	if _at(120.0, delta):
		print("AUTOTEST: M777 — rounds fired %d, kills %d, level %d, crew %d" % [artillery.rounds_fired, artillery.kills, artillery.level, artillery.crew_count()])
		print("AUTOTEST: losses — Humvee hp %d crew %d | Stryker hp %d | Huey hp %d crew %d | Chinook hp %d crew %d" % [humvee.hp, humvee.crew.count(), stryker.hp, huey.hp, huey.crew.count(), chinook.hp, chinook.crew.count()])


func _input_selftest() -> void:
	# Drives the real input handlers with synthetic events
	var roof_px := camera.unproject_position(Vector3(-3.0, Level.ROOF_HEIGHT, 3.0)) * pixel_scale
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	_unhandled_input(key)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = roof_px
	_unhandled_input(rmb)
	var rmb_up := InputEventMouseButton.new()
	rmb_up.button_index = MOUSE_BUTTON_RIGHT
	rmb_up.pressed = false
	rmb_up.position = roof_px
	_unhandled_input(rmb_up)
	var ordered := 0
	for sd in squads[0].soldiers:
		if sd._has_order:
			ordered += 1
	print("AUTOTEST: input — Alpha selected=%s, %d soldiers took the move order (click at %s)" % [squads[0].selected, ordered, roof_px])
	# Box-select everything on screen
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	lmb.position = Vector2(2, 2)
	_unhandled_input(lmb)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(1270, 710)
	_unhandled_input(motion)
	var lmb_up := InputEventMouseButton.new()
	lmb_up.button_index = MOUSE_BUTTON_LEFT
	lmb_up.pressed = false
	lmb_up.position = Vector2(1270, 710)
	_unhandled_input(lmb_up)
	print("AUTOTEST: input — box select picked %d squads" % _selected().size())
	# Right-drag a circle on the roof with both squads selected
	_select_only(squads.slice(0, 2))
	var center := Vector3(-0.5, Level.ROOF_HEIGHT, 0.5)
	var first := camera.unproject_position(center + Vector3(3.5, 0, 0)) * pixel_scale
	var rdown := InputEventMouseButton.new()
	rdown.button_index = MOUSE_BUTTON_RIGHT
	rdown.pressed = true
	rdown.position = first
	_unhandled_input(rdown)
	var last := first
	for k in range(1, 41):
		var ang := TAU * k / 40.0
		var rmove := InputEventMouseMotion.new()
		rmove.position = camera.unproject_position(center + Vector3(cos(ang) * 3.5, 0, sin(ang) * 3.5)) * pixel_scale
		last = rmove.position
		_unhandled_input(rmove)
	print("AUTOTEST: input — circle preview shows %d markers" % hud._formation.size())
	var rup := InputEventMouseButton.new()
	rup.button_index = MOUSE_BUTTON_RIGHT
	rup.pressed = false
	rup.position = last
	_unhandled_input(rup)
	_line_test_pending = true
	for k in [KEY_Q, KEY_E, KEY_F2]:
		_on_key(k)
	print("AUTOTEST: input — keys ok, Alpha kills after F2 = %d" % squads[0].kills)


func _queue_shot(t: float, shot_name: String, focus, shot_size: float) -> void:
	_shot_queue.append({"t": t, "name": shot_name, "focus": focus, "size": shot_size, "framed": false})


func _city_shot_tick(delta: float) -> void:
	# A tour of the city for screenshots: [name, focus, size, camera turns]
	var tour := [["overview", Vector3(0, 0, 0), 1000.0], ["dallas", Vector3(640, 0, -70), 200.0],
		["fortworth", Vector3(-640, 0, -120), 170.0], ["arlington", Vector3(-70, 0, 30), 170.0],
		["neighborhood", Vector3(-330, 0, 190), 60.0], ["airport", Vector3(90, 0, -370), 190.0],
		["plaza", Vector3(0, 0, 0), 40.0], ["mid_zoom", Vector3(-640, 0, -80), 120.0]]
	var i := int(_test_clock / 1.5)
	if i >= tour.size():
		get_tree().quit()
		return
	var shot: Array = tour[i]
	camera.distance = 1100.0 if shot[2] > 500.0 else RtsCamera.DISTANCE
	camera.far = 2600.0 if shot[2] > 500.0 else 760.0
	camera.focus = shot[1]
	camera.size = shot[2]
	camera._target_size = shot[2]
	enemy.spawning_enabled = false
	if fmod(_test_clock, 1.5) >= 1.2 and fmod(_test_clock - delta, 1.5) < 1.2:
		var img := get_viewport().get_texture().get_image()
		var path := _shot_path.replace(".png", "_%s.png" % shot[0])
		img.save_png(path)
		print("AUTOTEST: saved %s" % path)


func _at(t: float, delta: float) -> bool:
	return _test_clock >= t and _test_clock - delta < t


func _click(button: MouseButton, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = at
		_unhandled_input(e)


func _chinook_selftest(delta: float) -> void:
	# Hover toggle, a Humvee driving up the ramp of a hovering Chinook (it lands for it and
	# lifts again), a flight in hover mode, Bravo picked up from the hover, then unload (U)
	if _at(12.0, delta):
		print("AUTOTEST: Chinook — capacity: squads with 0/1/2 Humvees aboard = %d/%d/%d; Huey takes vehicles: %s" % [chinook.max_squads(0), chinook.max_squads(1), chinook.max_squads(2), huey.vehicle_capacity > 0])
		_select_only([chinook])
		_on_key(KEY_L)
	if _at(17.0, delta):
		print("AUTOTEST: Chinook — after L: state %s, hover mode %s, height %.1f m" % [chinook.state, chinook.hover_mode, chinook.global_position.y])
	if _at(22.0, delta):
		_select_only([humvee])
		_click(MOUSE_BUTTON_RIGHT, _to_screen(chinook.global_position + Vector3.UP * 2.0))
		print("AUTOTEST: Chinook — right-click with the Humvee selected: Chinook %s, Humvee heading to it: %s" % [chinook.state, humvee.board_target == chinook])
	if _at(44.0, delta):
		print("AUTOTEST: Chinook — Humvee aboard: %s (cargo %d), Chinook state %s, height %.1f m" % [humvee.carried_by == chinook, chinook.cargo.size(), chinook.state, chinook.global_position.y])
		_select_only([chinook])
		_order_vehicles([chinook], Vector3(5.0, 0.0, -35.0))
	if _at(64.0, delta):
		print("AUTOTEST: Chinook — after flying in hover mode: state %s at %s" % [chinook.state, chinook.global_position.round()])
	if _at(66.0, delta):
		_select_only([squads[1]])
		_click(MOUSE_BUTTON_RIGHT, _to_screen(chinook.global_position + Vector3.UP * 2.0))
		var walking := 0
		for sd in squads[1].soldiers:
			if sd.board_target == chinook:
				walking += 1
		print("AUTOTEST: Chinook — right-click with Bravo selected: Chinook %s, %d soldiers heading to it" % [chinook.state, walking])
	if _at(90.0, delta):
		print("AUTOTEST: Chinook — aboard: %d soldiers (%d squads) + %d Humvee, state %s, height %.1f m" % [chinook.passengers.size(), chinook.passenger_squads().size(), chinook.cargo.size(), chinook.state, chinook.global_position.y])
		_select_only([chinook])
		_on_key(KEY_U)
	if _at(104.0, delta):
		print("AUTOTEST: Chinook — after U: state %s, Bravo on the ground %d/%d, Humvee out: %s at %s, visible %s, gunner exposed %s" % [chinook.state, squads[1].active_soldiers().size(), squads[1].soldiers.size(), humvee.carried_by == null, humvee.global_position.round(), humvee.visible, humvee.crew.occupant(1).exposed if humvee.crew.count() > 1 else false])


var _test_eng: Squad
var _test_hog3: A10


func _fob_selftest(delta: float) -> void:
	if _at(14.0, delta):
		fob.work_speed = 12.0
		print("AUTOTEST: FOB — building sped up x12 for the test")
		var bad := fob.plan_walls(Fob.snap_rect(Vector3(-10, 0, -10), Vector3(10, 0, 10)))
		print("AUTOTEST: FOB — walls over the plaza building: \"%s\"" % bad)
		var ok := fob.plan_walls(Fob.snap_rect(Vector3(32, 0, 8), Vector3(68, 0, 40)))
		var kinds := {}
		for p in fob.pieces:
			kinds[p.kind] = kinds.get(p.kind, 0) + 1
		print("AUTOTEST: FOB — walls 36 x 32 m: \"%s\", pieces %s" % [ok, kinds])
		print("AUTOTEST: FOB — barracks outside the walls: \"%s\"" % fob.plan_building("barracks", Vector3(0, 0, 30), 0.0))
		print("AUTOTEST: FOB — runway: \"%s\" | barracks inside: \"%s\" | shed: \"%s\"" % [
			fob.plan_building("runway", Vector3(0, 0, -41), 0.0), fob.plan_building("barracks", Vector3(50, 0, 18), 0.0),
			fob.plan_building("shed", Vector3(48, 0, 30), 0.0)])
		_test_eng = squads[2]
	if _at(15.0, delta):
		# Extend the base east through the real input: F menu -> walls -> drag
		camera.focus = Vector3(70, 0, 24)
		camera.size = 60.0
		camera._target_size = 60.0
	if _at(15.5, delta):
		var before := fob.pieces.size()
		begin_build("walls")
		_drag(MOUSE_BUTTON_LEFT, _to_screen(Vector3(68, 0, 8)), _to_screen(Vector3(84, 0, 40)))
		var east_wall := 0
		for p in fob.pieces:
			if absf(p.position.x - 67.3) < 0.5 or absf(p.position.x - 68.7) < 0.5:
				east_wall += 1
		print("AUTOTEST: FOB — extended east by dragging: rects %d, pieces %d -> %d, old east wall pieces left %d, build mode \"%s\"" % [fob.rects.size(), before, fob.pieces.size(), east_wall, build_mode])
		camera.focus = Vector3(-10, 0, 10)
	for t in [40.0, 70.0, 100.0]:
		if _at(t, delta):
			var built := 0
			for p in fob.pieces:
				if p.is_built():
					built += 1
			print("AUTOTEST: FOB — t=%d: %d/%d pieces built, barracks %s, shed %s, runway slots free %d, engineers %d, status: %s" % [
				int(t), built, fob.pieces.size(), fob.has_built("barracks"), fob.has_built("shed"), free_runway_slots(), _test_eng.soldiers.size(),
				hud._cards[2].status.text if hud._cards.size() > 2 else "?"])
	if _at(101.0, delta):
		# Refills and repairs: lose an engineer inside the walls; damage the Humvee and drive it in
		var inside := 0
		for sd in _test_eng.soldiers:
			if fob.contains(sd.global_position):
				inside += 1
		_test_eng.soldiers[-1].die()
		if not humvee.destroyed:
			humvee.order_move(Vector3(50, 0, 26))
		print("AUTOTEST: FOB — killed an engineer (%d left, %d inside the walls), Humvee driving in" % [_test_eng.soldiers.size(), inside])
		# Nav: a path from outside to the middle should go round the walls, through a gate
		var path := Level.find_path(level.get_navigation_map(), Vector3(50, 0, 0), Vector3(50, 0, 24))
		var through_wall := false
		for i in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var b: Vector3 = path[i]
			for k in 10:
				var q := a.lerp(b, k / 10.0)
				var st := level.structure_at(q, 0.0)
				if st != null and st.is_solid() and st.kind in ["wall", "ramp"] and st.flat_distance(q) == 0.0 and q.y < 1.0:
					through_wall = true
		print("AUTOTEST: FOB — path from outside to the middle: %d points, length %.0f m, crosses a wall at ground level: %s" % [path.size(), _path_len(path), through_wall])
	if _at(122.0, delta):
		print("AUTOTEST: FOB — Humvee inside the walls: %s (hp %d); setting hp to 40" % [fob.contains(humvee.global_position), int(humvee.hp)])
		if not humvee.destroyed:
			humvee.hp = 40.0
	if _at(127.0, delta):
		_test_hog3 = spawn_unit("a10", Vector3(-830, 0, -400), 0.0, true)
		_test_hog3.fuel = 3.0
		print("AUTOTEST: A-10 — %s arrives with no free slot (has slot %s), fuel set to 3 s" % [_test_hog3.callsign, _test_hog3.has_slot])
	if _at(148.0, delta):
		var pilot: Squad = null
		for sq in squads:
			if sq.kind == "pilot":
				pilot = sq
		print("AUTOTEST: FOB — t=148: engineers %d/5 | Humvee hp %d at %s, inside %s | Hog 1 %s, slot %s | %s %s, pilot squad %s at height %.1f" % [
			_test_eng.soldiers.size(), int(humvee.hp), humvee.global_position.round(), fob.contains(humvee.global_position),
			a10s[0].state, a10s[0].has_slot, _test_hog3.callsign, "destroyed" if _test_hog3.destroyed else _test_hog3.state,
			pilot.squad_name if pilot else "none", pilot.soldiers[0].global_position.y if pilot and not pilot.soldiers.is_empty() else -1.0])


func _deploy_test_tick(delta: float) -> void:
	## Deploy a given loadout through the real setup screen, then report what the player has
	var before := _dt
	_dt += delta
	var now := Time.get_ticks_usec()
	if has_meta("dt_last") and has_meta("dt_at"):
		set_meta("dt_peak", maxf(float(get_meta("dt_peak", 0.0)), (now - int(get_meta("dt_last"))) / 1000.0))
	set_meta("dt_last", now)
	if state == "setup" and level.map_settled() and hud._setup != null and not has_meta("dt_deployed"):
		set_meta("dt_deployed", true)
		var st: MissionSetup = hud._setup
		for k in st.counts:
			st.counts[k] = 0
		for part in _deploy_test.split(","):
			var kv := part.split(":")
			st.counts[kv[0]] = int(kv[1])
		st._refresh()
		print("DEPLOY: pressing Deploy with %s (button disabled %s, text \"%s\")" % [st.counts, st._deploy.disabled, st._deploy.text])
		st._on_deploy()
		set_meta("dt_at", _dt)
	if has_meta("dt_at") and _dt > float(get_meta("dt_at")) + float(OS.get_environment("DT_WAIT") if OS.get_environment("DT_WAIT") != "" else "30") and not has_meta("dt_done"):
		set_meta("dt_done", true)
		print("DEPLOY: state %s, squads %d, vehicles %d, A-10s %d, cards %d, hotkeys %d" % [state, squads.size(), vehicles.size(), a10s.size(), hud._cards.size(), hotkey_units().size()])
		if level.city.real_map != null:
			var nav := level.get_navigation_map()
			for pair in [[Vector3(-300, 0, 100), Vector3(100, 0, 100)], [Vector3(-850, 0, 0), enemy.red_fob.sally_point()], [Vector3(-300, 0, -255), Vector3(100, 0, -265)]]:
				var a: Vector3 = NavigationServer3D.map_get_closest_point(nav, pair[0])
				var b: Vector3 = NavigationServer3D.map_get_closest_point(nav, pair[1])
				var path := Level.find_path(nav, a, b)
				var end: Vector3 = path[path.size() - 1] if not path.is_empty() else a
				print("DEPLOY: real map path %s -> %s: %d points, %.0f m long, ends %.1f m from goal, crosses x=-90 at %s" % [pair[0], pair[1], path.size(), _path_len(path), end.distance_to(b), _crossing(path, -90.0)])
			var line := ""
			var a0: Vector3 = NavigationServer3D.map_get_closest_point(nav, Vector3(-CityBuilder.HALF_X + 60, 0, 116))
			var xi := -CityBuilder.HALF_X + 100.0
			while xi < CityBuilder.HALF_X:
				var g: Vector3 = NavigationServer3D.map_get_closest_point(nav, Vector3(xi, 0, 116))
				var pth := Level.find_path(nav, a0, g)
				var ok: bool = not pth.is_empty() and pth[pth.size() - 1].distance_to(g) < 2.0
				line += "%d:%s " % [xi, "ok" if ok else "NO"]
				xi += 200.0
			print("DEPLOY: reach along z=116 from the west edge: " + line)
		for a in a10s:
			print("   %s %s at %s fuel %d slot %s" % [a.callsign, a.state, a.global_position.round(), int(a.fuel), a.has_slot])
		if not guns.is_empty():
			print("DEPLOY: guns %s | crews %s | manned %s" % [guns.map(func(g): return g.display_name), guns.map(func(g): return g.crew_squad.squad_name), guns.map(func(g): return g.crew_count())])
			begin_fire()
			print("DEPLOY: G with nothing selected -> %d guns; targeting %s" % [fire_guns().size(), _targeting])
			_cancel_calls()
			_select_only([guns[1].crew_squad] if guns.size() > 1 else [])
			begin_fire()
			print("DEPLOY: G with the 2nd crew selected -> %s" % fire_guns().map(func(g): return g.display_name))
			_cancel_calls()
			reinforcements = 1
			print("DEPLOY: M777 reinforcement blocked: \"%s\"" % reinforcement_blocked("m777"))
			call_reinforcement("m777")
			print("DEPLOY: after calling one in: guns %d, cards %d" % [guns.size(), hud._cards.size()])
		_select_only([a10s[0]] if not a10s.is_empty() else [])
		print("DEPLOY: selected A-10 1: %s; selection panel: %s" % [a10s[0].selected if not a10s.is_empty() else false, hud._detail.get_child_count()])
		get_tree().quit()


func _setup_shot_tick(delta: float) -> void:
	## Screenshots of the mission setup screen, then a fresh deployment with walls being planned
	var before := _setup_clock
	_setup_clock += delta
	var at := func(t: float) -> bool: return _setup_clock >= t and before < t
	if at.call(2.0):
		hud._setup.pick_zone(7)
		get_viewport().get_texture().get_image().save_png(_setup_shot.replace(".png", "_setup.png"))
		print("SHOT: setup")
	if state == "setup" and _setup_clock > 3.0 and level.map_settled():
		hud._setup._on_deploy()
		_setup_clock = 100.0
	if at.call(102.0):
		var c: Vector3 = zone_pos(start_zone)
		var spot := level.ground_spot(c + Vector3(0, 0, -60), 30.0)
		var r := Fob.snap_rect(spot + Vector3(-16, 0, -14), spot + Vector3(16, 0, 14))
		print("SHOT: walls at %s: \"%s\"" % [r, fob.plan_walls(r)])
		camera.focus = spot
		camera.size = 55.0
		camera._target_size = 55.0
		fob.work_speed = 25.0
	if at.call(104.0):
		begin_build("barracks")
		_build_cursor = camera.focus + Vector3(2, 0, 2)
	if at.call(105.0):
		get_viewport().get_texture().get_image().save_png(_setup_shot.replace(".png", "_deployed.png"))
		print("SHOT: deployed")
	if at.call(125.0):
		end_build()
		get_viewport().get_texture().get_image().save_png(_setup_shot.replace(".png", "_building.png"))
		print("SHOT: building")
		get_tree().quit()


func _supply_lab_tick(delta: float) -> void:
	## Rounds running out and refilling, an airdrop fetched by a PLS and by a Chinook, the
	## Black Hawk fast-roping, the M777 out of shells
	var nav := level.get_navigation_map()
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for mm in sq.members:
				if is_instance_valid(mm) and mm is RedSoldier:
					mm.process_mode = Node.PROCESS_MODE_DISABLED
		# The FOB, built at once, and a PLS beside it
		fob.plan_walls(Fob.snap_rect(Vector3(32, 0, 8), Vector3(68, 0, 40)))
		for p in fob.pieces:
			p.finish()
		_sl["pls"] = spawn_unit("pls", level.ground_spot(Vector3(80, 0, 24), 8.0), 90.0)
		print("SUPPLY: stock at the start: %s" % Fob.stock_text(fob.stock))
		# Alpha's rounds: one soldier empty, the rest half
		var alpha: Squad = squads[0]
		for i in alpha.soldiers.size():
			alpha.soldiers[i].rounds = 0 if i == 0 else 140
			alpha.soldiers[i].ammo = mini(alpha.soldiers[i].ammo, alpha.soldiers[i].rounds)
		var stryker: Node3D = null
		for v in vehicles:
			if v is Stryker:
				stryker = v
		_sl["stryker"] = stryker
		print("SUPPLY: Alpha rounds %s, out of ammo: %s | Stryker cans %d" % [alpha.soldiers.map(func(x): return x.rounds), alpha.soldiers[0].out_of_ammo(), stryker.can_rounds if stryker else -1])
		if stryker != null:
			_order_board([alpha], stryker)
		# Two airdrops: ammo near the PLS, shells near the Chinook's start
		call_airdrop(level.ground_spot(Vector3(100, 0, 40), 10.0), "ammo")
		call_airdrop(level.ground_spot(Vector3(-20, 0, 60), 10.0), "shells")
	if _at(20.0, delta):
		_order_board([squads[0]], _sl.stryker)
	if _at(60.0, delta):
		var alpha: Squad = squads[0]
		var st: Node3D = _sl.stryker
		print("SUPPLY: Alpha after riding in the Stryker: rounds %s | Stryker cans %d (used %d)" % [alpha.soldiers.map(func(x): return x.rounds), st.can_rounds, st.can_rounds_max - st.can_rounds])
	if _at(45.0, delta):
		var ps: Array = get_tree().get_nodes_in_group("pallets")
		print("SUPPLY: pallets: %s" % ", ".join(ps.map(func(x): return "%s %s at (%.0f, %.0f)" % [x.display_name, x.state, x.global_position.x, x.global_position.z])))
		for p in ps:
			if p.kind == "ammo":
				_sl["ammop"] = p
			elif p.kind == "shells":
				var ch: Chinook = null
				for h in helis:
					if h is Chinook:
						ch = h
				ch.start_sling(p)
				_sl["ch"] = ch
				_sl["shellp"] = p
		camera.focus = Vector3(90, 0, 30)
		camera.size = 40.0
		camera._target_size = 40.0
	if _at(50.0, delta):
		print("SUPPLY: PLS to the ammo pallet: \"%s\"" % _sl.pls.go_load(_sl.ammop))
	if _at(58.0, delta):
		_sl_shot("pallet_fetch")
	if _at(85.0, delta):
		var pl: Pls = _sl.pls
		print("SUPPLY: PLS cargo: %s" % pl.cargo_text())
		pl.order_move(NavigationServer3D.map_get_closest_point(nav, fob.center()))
	if _at(75.0, delta):
		var ch: Chinook = _sl.ch
		print("SUPPLY: Chinook sling: phase %s, slung %s" % [ch.sling_phase, ch.is_slung()])
		ch.order_fly(fob.center())
	if _at(110.0, delta):
		var ch: Chinook = _sl.ch
		if ch.is_slung():
			ch.order_drop(level.ground_spot(fob.center() + Vector3(6, 0, 6), 6.0), 0.0)
	if _at(135.0, delta):
		print("SUPPLY: stock after deliveries: %s | PLS cargo: %s | Chinook phase \"%s\"" % [Fob.stock_text(fob.stock), _sl.pls.cargo_text(), _sl.ch.sling_phase])
		_sl_shot("fob_stock")
		# The M777 with no shells
		var g: Artillery = guns[0]
		g.shells = 0
		print("SUPPLY: M777 with no shells: \"%s\"" % g.call_fire(g.to_global(Vector3(0, 0, -150))))
		# Black Hawk: Bravo aboard, then hover and fast-rope
		_order_board([squads[1]], huey)
	if _at(160.0, delta):
		print("SUPPLY: Black Hawk aboard %d, state %s" % [huey.passengers.size(), huey.state])
		huey.set_hover_mode(true)
		huey.order_fly(level.ground_spot(huey.global_position + Vector3(40, 0, 0), 10.0))
		camera.focus = huey.global_position + Vector3(40, 0, 0)
		camera.size = 30.0
		camera._target_size = 30.0
	if _at(180.0, delta):
		print("SUPPLY: Black Hawk %s at height %.1f, unloading" % [huey.state, huey.global_position.y])
		huey.unload()
	if _at(182.5, delta):
		_sl_shot("fast_rope")
	if _at(186.0, delta):
		var on_ground := 0
		for sd in (squads[1] as Squad).soldiers:
			if not sd.boarded:
				on_ground += 1
		print("SUPPLY: after fast-roping: %d on the ground, %d still aboard, Black Hawk %s" % [on_ground, huey.passengers.size(), huey.state])
		get_tree().quit()


func _move_lab_tick(delta: float) -> void:
	## Move-and-face orders and their path lines, click-to-deselect, fuel running out, the
	## fuel truck, the new units, the Bradley's TOWs and the Apache's Hellfires
	var nav := level.get_navigation_map()
	# Top speeds actually reached
	for k in ["humvee", "stryker", "huey"]:
		var u = get(k)
		if u != null and is_instance_valid(u):
			_sl["peak_" + k] = maxf(_sl.get("peak_" + k, 0.0), u.speed)
	if _at(41.0, delta):
		print("MOVE: peak speeds — Humvee %.1f m/s (%.0f mph), Stryker %.1f (%.0f mph), Black Hawk %.1f (%.0f mph)" % [_sl.peak_humvee, _sl.peak_humvee * 2.237, _sl.peak_stryker, _sl.peak_stryker * 2.237, _sl.peak_huey, _sl.peak_huey * 2.237])
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for mm in sq.members:
				if is_instance_valid(mm):
					mm.process_mode = Node.PROCESS_MODE_DISABLED
		for t in enemy.tanks:
			t.process_mode = Node.PROCESS_MODE_DISABLED
		var spots := {"fuel": Vector3(-10, 0, 70), "lmtv": Vector3(-60, 0, 60), "bradley": Vector3(-20, 0, -30), "apache": Vector3(-80, 0, -20), "mh6": Vector3(-90, 0, 40)}
		for id in ["fuel", "lmtv", "bradley", "apache", "mh6"]:
			_sl[id] = spawn_unit(id, level.ground_spot(spots[id], 15.0), 90.0)
			print("MOVE: spawned %s at (%.0f, %.0f), fuel %s, in transports %s" % [_sl[id].display_name, _sl[id].global_position.x, _sl[id].global_position.z, _sl[id].fuel_text(), _sl[id] in transports])
	if _at(13.0, delta):
		# Right-drag with the Humvee and the Stryker: go to A, face toward B
		var a := level.ground_spot(humvee.global_position + Vector3(330, 0, -10), 10.0)
		var b := a + Vector3(0, 0, 20)          # face south (+Z)
		_sl["a"] = a
		_select_only([humvee, stryker])
		_line_points.clear()
		_line_points.append(a)
		_line_points.append(b)
		_line_dragging = true
		_line_moved = true
		_line_start = _to_screen(a)
		_preview_vehicle_move()
		_end_line(_to_screen(b))
		print("MOVE: humvee path %d pts, face %.0f deg | stryker face %.0f deg" % [humvee.planned_path().size(), rad_to_deg(humvee.face_yaw), rad_to_deg(stryker.face_yaw)])
		# The Black Hawk too, facing east
		huey.order_fly(level.ground_spot(huey.global_position + Vector3(700, 0, 30), 10.0), atan2(-1.0, 0.0))
		camera.focus = a
		camera.size = 70.0
		camera._target_size = 70.0
	if _at(16.0, delta):
		_select_only([humvee, stryker, huey])
	if _at(16.5, delta):
		_sl_shot("paths")
	if _at(40.0, delta):
		var a: Vector3 = _sl.a
		for v in [humvee, stryker]:
			print("MOVE: %s at %.1f m from the spot, heading %.0f deg (wanted %.0f), driving %s turning %s" % [v.display_name, Vector2(v.global_position.x - a.x, v.global_position.z - a.z).length(), rad_to_deg(wrapf(v._yaw, -PI, PI)), rad_to_deg(v.face_yaw), v.driving, v._turning])
		print("MOVE: Black Hawk %s, heading %.0f deg (wanted -90)" % [huey.state, rad_to_deg(wrapf(huey._yaw, -PI, PI))])
		# Click the Humvee while it's selected: it drops out of the selection
		_select_only([humvee, stryker])
		_drag_start = _vehicle_screen_pos(humvee)
		_finish_select(_drag_start, false)
		print("MOVE: clicked the selected Humvee: humvee selected %s, stryker selected %s" % [humvee.selected, stryker.selected])
		# The Humvee runs dry on the way somewhere
		humvee.fuel = 0.6
		humvee.order_move(NavigationServer3D.map_get_closest_point(nav, humvee.global_position + Vector3(80, 0, 0)))
	if _at(55.0, delta):
		print("MOVE: Humvee fuel %.2f, driving %s" % [humvee.fuel, humvee.driving])
		var ft: FuelTruck = _sl.fuel
		print("MOVE: fuel truck to the Humvee: \"%s\" (tanker %s)" % [ft.go_refuel(humvee), ft.cargo_text()])
		# The Little Bird lifts off and runs dry in the air
		var mh: Helicopter = _sl.mh6
		mh.order_fly(level.ground_spot(mh.global_position + Vector3(60, 0, 0), 10.0))
	if _at(62.0, delta):
		var mh: Helicopter = _sl.mh6
		print("MOVE: Little Bird %s at %.0f m up, fuel %s" % [mh.state, mh.global_position.y - mh._ground_y(mh.global_position), mh.fuel_text()])
		mh.fuel = 0.2
	if _at(80.0, delta):
		var mh: Helicopter = _sl.mh6
		mh.order_fly(mh.global_position + Vector3(50, 0, 0))
		print("MOVE: Little Bird after running dry: %s, can it take off: %s" % [mh.state, mh.state != "landed"])
		# A Red tank in front of the Bradley
		var br: Bradley = _sl.bradley
		var tank := enemy.spawn_tank(level.ground_spot(br.global_position + Vector3(70, 0, 0), 10.0), 90.0)
		tank.process_mode = Node.PROCESS_MODE_DISABLED
		_sl["tank"] = tank
		camera.focus = br.global_position + Vector3(35, 0, 0)
	if _at(84.0, delta):
		_sl_shot("tow")
	if _at(100.0, delta):
		var br: Bradley = _sl.bradley
		print("MOVE: Bradley TOWs %s, tank alive %s" % [br.missiles_text(), _sl.tank.alive])
		# The Apache takes on a tank from the air
		var ap: Apache = _sl.apache
		var t2 := enemy.spawn_tank(level.ground_spot(ap.global_position + Vector3(160, 0, 0), 10.0), 90.0)
		t2.process_mode = Node.PROCESS_MODE_DISABLED
		_sl["tank2"] = t2
		ap.set_hover_mode(true)
		ap.order_fly(ap.global_position + Vector3(60, 0, 0), atan2(-1.0, 0.0))
	if _at(125.0, delta):
		var ap: Apache = _sl.apache
		print("MOVE: Apache %s, %s, tank alive %s, fuel %s" % [ap.state, ap.missiles_text(), _sl.tank2.alive, ap.fuel_text()])
		var ft: FuelTruck = _sl.fuel
		print("MOVE: Humvee fuel after the truck: %s, truck tanker %s" % [humvee.fuel_text(), ft.cargo_text()])
		_sl_shot("apache")
		# The LMTV carries a squad
		_order_board([squads[0]], _sl.lmtv)
	if _at(150.0, delta):
		var lm: Lmtv = _sl.lmtv
		print("MOVE: LMTV aboard: %s" % ", ".join(lm.passenger_squads().map(func(x): return x.squad_name)))
		print("MOVE: done")
		get_tree().quit()


func _flight_lab_tick(delta: float) -> void:
	## Helicopters banking, flying low over the city, waypoints, autorotation; the A-10's bank
	## matching its turns, a gun run and a landing
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for mm in sq.members:
				if is_instance_valid(mm):
					mm.process_mode = Node.PROCESS_MODE_DISABLED
		for t in enemy.tanks:
			if not (t is RedAA):
				t.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				t.process_mode = Node.PROCESS_MODE_DISABLED
		_sl["mh6"] = spawn_unit("mh6", level.ground_spot(Vector3(-90, 0, 40), 15.0), 90.0)
		_sl["mh6b"] = spawn_unit("mh6", level.ground_spot(Vector3(-110, 0, 60), 15.0), 90.0)
		_sl["stats"] = {"bank_max": 0.0, "agl_min": 999.0, "agl_sum": 0.0, "agl_n": 0, "left_ok": 0, "left_bad": 0, "a10_bank_max": 0.0}
	if not _sl.has("stats"):
		return
	var st: Dictionary = _sl.stats
	# Black Hawk: bank and height over the ground while cruising
	if huey.state == "cruise" and huey.speed > 30.0:
		st.bank_max = maxf(st.bank_max, absf(huey._bank))
		var agl: float = huey._pos.y - huey._ahead_ceiling(huey._pos, huey._pos + Vector3(0.01, 0, 0))
		st.agl_min = minf(st.agl_min, agl)
		st.agl_sum += agl
		st.agl_n += 1
	# A-10: turning left (yaw growing) must dip the left wing (its right wing, basis.x, goes up)
	if not a10s.is_empty():
		var j: A10 = a10s[0]
		if j.state in ["loiter", "transit", "egress", "rtb"] and absf(j._bank) > 0.2:
			var right_wing_up: bool = j.global_basis.x.y > 0.0
			var turning_left: bool = j._bank > 0.0
			if right_wing_up == turning_left:
				st.left_ok += 1
			else:
				st.left_bad += 1
			st.a10_bank_max = maxf(st.a10_bank_max, absf(j._bank))
	if _at(12.0, delta):
		# Black Hawk across the city: 1.2 km over the buildings
		var far := level.ground_spot(huey.global_position + Vector3(900, 0, -600), 20.0)
		huey.order_fly(level.ground_spot(huey.global_position + Vector3(500, 0, 300), 20.0))
		huey.queue_fly(far)
		_sl["bh_t0"] = _test_clock
		_sl["far"] = far
		camera.focus = huey.global_position
		camera.size = 120.0
		camera._target_size = 120.0
		# Little Bird: three waypoints, then land
		var mh: Helicopter = _sl.mh6
		var o := mh.global_position
		mh.order_fly(level.ground_spot(o + Vector3(300, 0, 0), 15.0))
		mh.queue_fly(level.ground_spot(o + Vector3(300, 0, 300), 15.0))
		mh.queue_fly(level.ground_spot(o + Vector3(0, 0, 300), 15.0))
		print("FLIGHT: Little Bird route %d points" % mh.planned_path().size())
		# A-10 gun run on a spot out east
		if not a10s.is_empty():
			var j: A10 = a10s[0]
			var tgt := level.ground_spot(Vector3(250, 0, 30), 20.0)
			print("FLIGHT: A-10 gun run: \"%s\" (state %s)" % [j.call_run(tgt - Vector3(40, 0, 0), tgt + Vector3(40, 0, 0)), j.state])
	if _sl.has("bh_t0") and not _sl.has("bh_done") and huey.state in ["descend", "landed", "hover"]:
		_sl["bh_done"] = true
		print("FLIGHT: Black Hawk 1.2 km trip took %.0f s, max bank %.0f deg, height over the city min %.0f m avg %.0f m" % [_test_clock - _sl.bh_t0, rad_to_deg(st.bank_max), st.agl_min, st.agl_sum / maxf(1, st.agl_n)])
	if _at(16.0, delta):
		camera.focus = huey.global_position
		_sl_shot("bank")
	if _at(30.0, delta):
		var mh2: Helicopter = _sl.mh6b
		mh2.order_fly(level.ground_spot(mh2.global_position + Vector3(400, 0, 200), 15.0))
	if _at(40.0, delta):
		var mh2: Helicopter = _sl.mh6b
		print("FLIGHT: second Little Bird %s at %.0f m, engines quit" % [mh2.state, mh2._pos.y])
		mh2.fuel = 0.05
		mh2.force_outcome = "hard"
		camera.focus = mh2.global_position
	if _at(44.0, delta):
		_sl_shot("autorotate")
	if _at(60.0, delta):
		var mh: Helicopter = _sl.mh6
		var mh2: Helicopter = _sl.mh6b
		print("FLIGHT: Little Bird with waypoints: %s, path left %d" % [mh.state, mh.planned_path().size()])
		print("FLIGHT: second Little Bird after autorotation: state %s, destroyed %s, armor %d%%" % [mh2.state, mh2.destroyed, int(100.0 * mh2.hp / mh2.max_hp)])
	if not a10s.is_empty():
		var states: Array = _sl.get("a10_states", [])
		var now: String = "%s@%d" % [a10s[0].state, int(_test_clock)]
		if states.is_empty() or not (states[-1] as String).begins_with(a10s[0].state + "@"):
			states.append(now)
		_sl["a10_states"] = states
	if _at(62.0, delta) and not a10s.is_empty():
		# Out of ammo: it heads home and lands on the FOB runway
		a10s[0].assign_slot(Vector3(-600, 0, 0), Vector3.RIGHT, Vector3(-520, 0, 0), "lab")
		a10s[0].runs_left = 0
		if a10s[0].state == "loiter":
			a10s[0].state = "rtb"
	if _at(75.0, delta):
		var mh: Helicopter = _sl.mh6
		mh.force_outcome = "crash"
		mh.order_fly(level.ground_spot(mh.global_position + Vector3(-300, 0, 0), 15.0))
	if _at(82.0, delta):
		var mh: Helicopter = _sl.mh6
		print("FLIGHT: first Little Bird %s at %.0f m, engines quit" % [mh.state, mh._pos.y])
		mh.fuel = 0.05
	if _at(110.0, delta):
		var mh: Helicopter = _sl.mh6
		print("FLIGHT: first Little Bird after autorotation: state %s, destroyed %s" % [mh.state, mh.destroyed])
	if _at(200.0, delta):
		var j: A10 = a10s[0] if not a10s.is_empty() else null
		print("FLIGHT: A-10 turns: left wing down in left turns %d frames, wrong way %d frames; max bank %.0f deg" % [st.left_ok, st.left_bad, rad_to_deg(st.a10_bank_max)])
		if j != null:
			print("FLIGHT: A-10 after its run: state %s, runs left %d, kills %d" % [j.state, j.runs_left, j.kills])
			print("FLIGHT: A-10 landing: %s" % ", ".join(_sl.get("a10_states", [])))
		print("FLIGHT: done")
		get_tree().quit()


func _vehicle_lab_tick(delta: float) -> void:
	## Close-ups of every vehicle model, one at a time on the same spot
	var at := Vector3(10, 0, 24)
	var kinds := ["humvee", "stryker", "m777", "red_tank", "red_aa", "huey", "chinook", "a10", "fuel", "lmtv", "bradley", "apache", "mh6", "mh6_smooth"]
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for mm in sq.members:
				if is_instance_valid(mm):
					mm.process_mode = Node.PROCESS_MODE_DISABLED
		_sl["i"] = 0
		_sl["t"] = 1.2
	if not _sl.has("i"):
		return
	_sl.t -= delta
	if _sl.t > 0.0:
		return
	_sl.t = 0.7
	if _sl.has("model"):
		_sl_shot(kinds[_sl.i])
		(_sl.model as Node).queue_free()
		_sl.erase("model")
		_sl.i += 1
		if _sl.i >= kinds.size():
			get_tree().quit()
		return
	var k: String = kinds[_sl.i]
	var m: VehicleModel
	match k:
		"humvee": m = VehicleModel.humvee()
		"stryker": m = VehicleModel.stryker()
		"m777": m = VehicleModel.m777(20.0)
		"red_tank": m = VehicleModel.red_tank()
		"red_aa": m = VehicleModel.red_aa()
		"huey": m = VehicleModel.huey()
		"chinook": m = VehicleModel.chinook()
		"fuel": m = VehicleModel.fuel_truck()
		"lmtv": m = VehicleModel.lmtv()
		"bradley": m = VehicleModel.bradley()
		"apache": m = VehicleModel.apache()
		"mh6": m = VehicleModel.mh6()
		"mh6_smooth": m = VehicleModel.mh6_smooth()
		_: m = VehicleModel.a10()
	m.rotor_factor = 0.0
	level.add_child(m)
	var air := k in ["huey", "chinook", "a10", "apache", "mh6", "mh6_smooth"]
	m.position = at + Vector3(0, 6.0 if air else 0.05, 0)
	m.rotation.y = deg_to_rad(210)
	_sl["model"] = m
	var size := {"humvee": 9.0, "stryker": 11.0, "m777": 13.0, "red_tank": 12.0, "red_aa": 11.0, "huey": 16.0, "chinook": 22.0, "a10": 22.0, "fuel": 13.0, "lmtv": 11.0, "bradley": 11.0, "apache": 16.0, "mh6": 10.0, "mh6_smooth": 10.0}
	camera.focus = at + Vector3(0, 6.0 if air else 1.0, 0)
	camera.size = size[k]
	camera._target_size = size[k]


func _base_lab_tick(delta: float) -> void:
	## Five guns on one target, engineers switching jobs, gates opening, a watch tower
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for m in sq.members:
				if is_instance_valid(m) and m is RedSoldier:
					m.process_mode = Node.PROCESS_MODE_DISABLED
		# Four more guns beside the first, all facing the same way
		var g0: Artillery = guns[0]
		for i in 4:
			var at := level.ground_spot(g0.global_position + g0.global_basis.x * (8.0 * (i + 1)), 6.0)
			spawn_unit("m777", at, rad_to_deg(g0.global_rotation.y))
		_sl["impacts"] = []
		for g in guns:
			g.impact.connect(func(at): _sl.impacts.append(at))
	if _at(3.0, delta):
		_select_only(guns.duplicate())
		begin_fire()
		var g0: Artillery = guns[0]
		var target: Vector3 = g0.to_global(Vector3(0, 0, -180))
		target = level.ground_spot(target, 10.0)
		_sl["target"] = target
		_call_artillery(camera.unproject_position(target) * pixel_scale)
		print("BASE: 5 guns on one target: spread %.0f m (one gun: %.0f m), on mission %d" % [guns[0].mission_spread, Artillery.SPREAD, guns.filter(func(g): return g.has_mission).size()])
		_sl["target"] = guns[0].mission_target
		# The FOB: a wall job, then a barracks
		fob.work_speed = 6.0
		fob.plan_walls(Fob.snap_rect(Vector3(32, 0, 8), Vector3(68, 0, 40)))
		fob.plan_building("barracks", Vector3(50, 0, 18), 0.0)
	if _at(12.0, delta):
		var eng: Squad = null
		for sq in squads:
			if sq.kind == "engineer":
				eng = sq
		var t: Structure = eng.get_meta("build_target", null)
		print("BASE: engineers on: %s" % (t.display_name() if t != null else "nothing"))
		var bar: Structure = fob.pieces[-1]
		fob.prioritize(bar)
		_sl["bar"] = bar
		_sl["eng"] = eng
	if _at(14.0, delta):
		var t: Structure = _sl.eng.get_meta("build_target", null)
		print("BASE: after the priority order, engineers on: %s" % (t.display_name() if t != null else "nothing"))
	if _test_clock > 14.0 and not _sl.has("bar_done") and _sl.has("bar") and (_sl.bar as Structure).is_built():
		_sl["bar_done"] = _test_clock
		print("BASE: barracks built at t=%.0f; walls built %d of %d" % [_test_clock, fob.pieces.filter(func(p): return p.kind != "barracks" and p.is_built()).size(), fob.pieces.size() - 1])
	if _sl.has("bar_done") and _at(float(_sl.bar_done) + 4.0, delta):
		var t: Structure = _sl.eng.get_meta("build_target", null)
		print("BASE: then back to: %s" % (t.display_name() if t != null else "nothing"))
		var hits: Array = _sl.impacts
		var far := 0.0
		var ds: PackedStringArray = []
		for h in hits:
			var dd := Vector2(h.x - _sl.target.x, h.z - _sl.target.z).length()
			ds.append("%.0f" % dd)
			far = maxf(far, dd)
		print("BASE: impact distances %s" % ", ".join(ds))
		print("BASE: %d rounds landed, farthest %.1f m from the aim point" % [hits.size(), far])
		for p in fob.pieces:
			p.finish()
		# A watch tower on the wall line (the middle of the north wall)
		var north: Structure = null
		for p in fob.pieces:
			if p.kind == "wall" and absf(p.position.z - 8.0) < 1.0 and (north == null or absf(p.position.x - 50.0) < absf(north.position.x - 50.0)):
				north = p
		var why := fob.plan_building("tower", north.position + Vector3(0, 0, 0.5), 0.0)
		print("BASE: watch tower on the north wall: %s" % ("planned" if why == "" else why))
		var twr: Structure = fob.pieces[-1]
		twr.finish()
		_sl["tower"] = twr
		var gate: Structure = null
		for p in fob.pieces:
			if p.kind == "gate":
				gate = p
		_sl["gate"] = gate
		_sl["gate_t"] = _test_clock
		camera.focus = gate.position
		camera.size = 40.0
		camera._target_size = 40.0
		var nav := level.get_navigation_map()
		var alpha: Squad = squads[0]
		for sd in alpha.soldiers:
			sd.global_position = level.ground_spot(gate.to_global_flat(Vector3(0, 0, -20)), 4.0) + Vector3.UP * 0.2
		_sl["alpha_far"] = true
	if _sl.has("gate_t"):
		var gt: float = _sl.gate_t
		var gate: Structure = _sl.gate
		if _at(gt + 1.0, delta):
			# Everyone else out of the way
			for sq in squads:
				if sq != squads[0]:
					for sd in sq.active_soldiers():
						if sd.manning == null and gate.flat_distance(sd.global_position) < 30.0:
							sd.global_position = level.ground_spot(gate.to_global_flat(Vector3(30, 0, 25)), 8.0) + Vector3.UP * 0.2
							sd.process_mode = Node.PROCESS_MODE_DISABLED
		if _at(gt + 3.0, delta):
			var near: PackedStringArray = []
			for n in get_tree().get_nodes_in_group("soldiers"):
				if gate.flat_distance(n.global_position) < 14.0:
					near.append("%s %.0f" % [n.squad.squad_name, gate.flat_distance(n.global_position)])
			print("BASE: gate with nobody near: open %s %s" % [gate.is_open(), near])
			# A Red rifleman right outside your gate: it stays shut for him
			var r := enemy.spawn_soldier(gate.to_global_flat(Vector3(2, 0, -3)))
			r.process_mode = Node.PROCESS_MODE_DISABLED
			_sl["red"] = r
		if _at(gt + 5.0, delta):
			print("BASE: Red rifleman at your gate: open %s" % gate.is_open())
			(_sl.red as Node).queue_free()
			var nav := level.get_navigation_map()
			for sd in (squads[0] as Squad).soldiers:
				sd.order_move(NavigationServer3D.map_get_closest_point(nav, gate.to_global_flat(Vector3(0, 0, 10))))
		if _at(gt + 7.0, delta):
			print("BASE: Alpha walking through: open %s" % gate.is_open())
			_sl_shot("gate_open")
		if _at(gt + 22.0, delta):
			var inside := 0
			for sd in (squads[0] as Squad).soldiers:
				if fob.contains(sd.global_position):
					inside += 1
			print("BASE: Alpha inside %d/5, gate open %s" % [inside, gate.is_open()])
			# Up the tower
			var twr: Structure = _sl.tower
			var nav := level.get_navigation_map()
			var n := 0
			for sd in (squads[0] as Squad).soldiers:
				if n >= 4:
					break
				sd.order_move(NavigationServer3D.map_get_closest_point(nav, twr.door_point(sd.global_position)))
				sd.board_target = twr
				n += 1
			camera.focus = twr.position
		if _at(gt + 40.0, delta):
			var twr: Structure = _sl.tower
			var hs: PackedStringArray = []
			for sd in twr.manned:
				hs.append("%.1f" % sd.global_position.y)
			print("BASE: on the tower: %d (heights %s), range %.0f" % [twr.manned.size(), ", ".join(hs), twr.manned[0].weapon_range if not twr.manned.is_empty() else 0.0])
			_sl_shot("tower")
			get_tree().quit()


func _orders_lab_tick(delta: float) -> void:
	## Selecting the M777, single shot / repeat, A-10 orbit and force stay, dead units' cards
	## going away and an ejected pilot taking a new jet
	var gun: Artillery = guns[0] if not guns.is_empty() else null
	var jet: A10 = a10s[0] if not a10s.is_empty() else null
	if _at(12.0, delta):
		enemy.spawning_enabled = false
		var gp := camera.unproject_position(gun.global_position + Vector3.UP * 0.5) * pixel_scale
		camera.focus = gun.global_position
		_sl["gp"] = gp
	if _at(12.3, delta):
		var gp := camera.unproject_position(gun.global_position + Vector3.UP * 0.5) * pixel_scale
		_select_only([squads[0]])
		_drag_start = gp
		_finish_select(gp, false)
		hud._update_cards()
		hud._update_commands()
		var vis: PackedStringArray = []
		for k in hud._buttons:
			if (hud._buttons[k] as Button).visible:
				vis.append(k)
		print("ORDERS: click on the gun: gun selected %s, Alpha still selected %s, buttons: %s" % [gun.selected, squads[0].selected, " ".join(vis)])
		_on_key(KEY_T)
		print("ORDERS: T: repeat %s" % gun.repeat)
		var target := gun.to_global(Vector3(0, 0, -150))
		_sl["rounds"] = gun.rounds_fired
		print("ORDERS: fire mission: %s" % ("accepted" if gun.call_fire(target) == "" else "refused"))
	if _at(13.0, delta):
		hud._update_detail()
		_sl_shot("gun_selected")
	if _at(13.2, delta):
		_select_only([jet])
		var p := jet.global_position
		_sl["orbit"] = Vector3(p.x - 250.0, 0, p.z + 120.0)
		_order_vehicles([jet], _sl.orbit)
		hud._update_commands()
		var vis: PackedStringArray = []
		for k in hud._buttons:
			if (hud._buttons[k] as Button).visible:
				vis.append(k)
		print("ORDERS: A-10 selected, buttons: %s | state %s" % [" ".join(vis), jet.state])
		camera.focus = _sl.orbit
		camera.size = 140.0
		camera._target_size = 140.0
	if _at(14.0, delta):
		hud._update_detail()
		_sl_shot("jet_selected")
	if _at(45.0, delta):
		var o: Vector3 = _sl.orbit
		print("ORDERS: A-10 after 32 s: %.0f m from the orbit point, on station %s, status \"%s\"" % [Vector2(jet.global_position.x - o.x, jet.global_position.z - o.z).length(), jet.on_station(), jet.status_text()])
		print("ORDERS: M777 single shot: rounds fired %d, mission still on %s" % [gun.rounds_fired - _sl.rounds, gun.has_mission])
		_sl_shot("jet_orbit")
		# Give it a runway slot far to the west, then fuel just under bingo
		jet.assign_slot(Vector3(-600, 0, 0), Vector3.RIGHT, Vector3(-520, 0, 0), "lab")
		_on_key(KEY_X)
		var home: float = Vector2(-600 - jet.global_position.x, -jet.global_position.z).length() / A10.CRUISE_SPEED
		jet.fuel = home + 15.0
		_sl["home"] = home
	if _at(46.0, delta):
		print("ORDERS: force stay %s, below bingo: state %s (want loiter)" % [jet.force_stay, jet.state])
		jet.fuel = _sl.home + 2.0
	if _at(47.0, delta):
		print("ORDERS: at emergency fuel: state %s (want rtb), force stay now %s" % [jet.state, jet.force_stay])
		# Bravo wiped out, the jet shot down (Red riflemen held still so the pilot can be checked)
		for sd in (squads[1] as Squad).soldiers.duplicate():
			sd.die()
		for rsq in enemy.squads:
			for mm in rsq.members:
				if is_instance_valid(mm):
					mm.process_mode = Node.PROCESS_MODE_DISABLED
		jet.take_flak(1000.0)
	if _at(48.0, delta):
		hud._update_cards()
		var titles: PackedStringArray = []
		for c in hud._cards:
			titles.append(c.title)
		print("ORDERS: cards after Bravo died and the jet went down: %s" % ", ".join(titles))
	if _at(70.0, delta):
		var pilot: Squad = null
		for sq in squads:
			if sq.kind == "pilot" and not sq.soldiers.is_empty():
				pilot = sq
		if pilot == null:
			print("ORDERS: no pilot")
		else:
			var ps: Soldier = pilot.soldiers[0]
			print("ORDERS: pilot down: chute %s" % ps.chute)
			fob.rects.append(Rect2(ps.global_position.x - 15, ps.global_position.z - 15, 30, 30))
			var nj = spawn_unit("a10", ps.global_position + Vector3(-200, 0, 0), 0.0, true)
			hud._update_cards()
			var titles: PackedStringArray = []
			for c in hud._cards:
				titles.append(c.title)
			print("ORDERS: new jet %s (kills %d), pilot squad left %d | cards: %s" % [nj.callsign, nj.kills, pilot.soldiers.size(), ", ".join(titles)])
		_sl_shot("after")
		get_tree().quit()


func _soldier_lab_tick(delta: float) -> void:
	## Close-ups of the soldiers for judging their look: a squad holding, a squad walking,
	## Red riflemen, a gun crew, at close and normal zoom
	var p := Vector3(-34, 0, 24)
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for m in sq.members:
				if is_instance_valid(m):
					m.process_mode = Node.PROCESS_MODE_DISABLED
		var alpha: Squad = squads[0]
		for i in alpha.soldiers.size():
			var sd: Soldier = alpha.soldiers[i]
			sd.global_position = p + Vector3(-4.0 + i * 2.0, 0.1, 0)
			sd.rotation.y = 0.0
			sd.stop()
		var bravo: Squad = squads[1]
		for i in bravo.soldiers.size():
			var sd: Soldier = bravo.soldiers[i]
			sd.global_position = p + Vector3(-5.0 + i * 1.6, 0.1, 6.0 + (i % 2) * 1.2)
			sd.order_move(p + Vector3(30.0 + i * 1.6, 0, 6.0 + (i % 2) * 1.2))
		_sl["reds"] = []
		for i in 4:
			var r := enemy.spawn_soldier(p + Vector3(-12.0, 0, -3.0 + i * 2.2))
			r.rotation.y = -PI * 0.5
			r.health = 1.0e9
			_sl.reds.append(r)
		camera.focus = p + Vector3(-4, 0, 2)
		camera.size = 16.0
		camera._target_size = 14.0
	if _at(1.3, delta):
		for r in _sl.reds:
			r.process_mode = Node.PROCESS_MODE_DISABLED
	if _at(2.6, delta):
		for sd in (squads[0] as Squad).soldiers:
			sd._model.muzzle_flash()
		for r in _sl.reds:
			r._model.muzzle_flash()
	if _at(2.62, delta):
		_sl_shot("close")
	if _at(2.66, delta):
		camera.size = 28.0
		camera._target_size = 28.0
	if _at(2.76, delta):
		_sl_shot("normal")
	if _at(2.8, delta):
		camera.size = 60.0
		camera._target_size = 60.0
	if _at(2.82, delta):
		hud._tab = "air"
		hud._order_dirty = true
		hud._update_cards()
	if _at(2.9, delta):
		_sl_shot("far")
		hud._tab = "all"
		hud._order_dirty = true
	if _at(3.0, delta):
		# From the other side, close: their faces
		camera._yaw += PI
		camera._target_yaw += PI
		camera.focus = p + Vector3(-5, 0, 1)
		camera.size = 9.0
		camera._target_size = 9.0
	if _at(3.08, delta):
		for sd in (squads[0] as Squad).soldiers:
			sd._model.muzzle_flash()
		_sl_shot("front")
	if _at(3.1, delta):
		camera._yaw -= PI
		camera._target_yaw -= PI
		camera.focus = artillery.global_position
		camera.size = 14.0
		camera._target_size = 14.0
	if _at(3.6, delta):
		_sl_shot("gun_crew")
		get_tree().quit()


func _growth_lab_tick(delta: float) -> void:
	## The Red FOB grows through all its sections; new Red units arrive; anti-air vs the A-10
	## and a Huey; reinforcements arrive at the start point; barracks/shed limits.
	var rf := enemy.red_fob
	var mid := RedFob.center()
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sd in enemy.alive:
			sd.process_mode = Node.PROCESS_MODE_DISABLED
		print("GROW: start: rects %d, pieces %d, towers %d, gates %s, AA %d, tanks %d" % [rf.rects.size(), rf.pieces.size(), rf.towers.size(), rf.gates.map(func(g): return g.position.round()), enemy.aa_count(), enemy.tanks.size()])
		camera.focus = Vector3(770, 0, 136)
		camera.size = 150.0
		camera._target_size = 150.0
		# Limits: no barracks or shed yet
		reinforcements = 3
		print("GROW: limits with no barracks/shed: squad \"%s\" | engineer \"%s\" | humvee \"%s\" | m777 \"%s\" | %s" % [reinforcement_blocked("squad"), reinforcement_blocked("engineer"), reinforcement_blocked("humvee"), reinforcement_blocked("m777"), limits_text()])
		var b := Structure.make("barracks", Vector3(50, 0, 18), 0.0)
		b.state = "built"
		level.add_structure(b)
		fob.pieces.append(b)
		print("GROW: with one barracks: squad \"%s\" | %s" % [reinforcement_blocked("squad"), limits_text()])
		start_zone = 1
		call_reinforcement("squad")
		var sq: Squad = squads[squads.size() - 1]
		print("GROW: reinforcement squad %s arrived at %s (start point %s)" % [sq.squad_name, sq.soldiers[0].global_position.round(), zone_pos(1)])
	# Grow one section at a time
	if _test_clock > 2.0 and not _gl.has("done") and rf._rising.is_empty() and fmod(_test_clock, 1.0) < delta:
		var n := rf.steps_done
		if n > 0 and _gl.get("reported", 0) < n:
			_gl["reported"] = n
			print("GROW: section %d up at t=%.1f: rects %d, pieces %d, towers %d, sally %s, Red on towers %d" % [n, _test_clock, rf.rects.size(), rf.pieces.size(), rf.towers.size(), rf.sally_point().round(), enemy.alive.filter(func(x): return x.fixed).size()])
		if n >= RedFob.STEPS.size():
			_gl["done"] = _test_clock
			print("GROW: fully grown; path from outside to the middle: %s" % _path_into(Vector3(660, 0, 136), mid))
			for k in 4:
				enemy.red_unit()
			print("GROW: 4 new Red units: AA %d, tanks %d, Red alive %d" % [enemy.aa_count(), enemy.tanks.size(), enemy.alive.size()])
			_sl_shot("grown")
		else:
			print("GROW: growing section %d: \"%s\"" % [n + 1, enemy.grow_fob([])])
	# Anti-air: the A-10 makes a run over the Red FOB; a Huey hovers near it
	if _gl.has("done") and not _gl.has("aa"):
		_gl["aa"] = _test_clock
		var jet: A10 = a10s[0]
		_call_a10(Vector3(700, 0, 90), Vector3(760, 0, 150))
		print("GROW: A-10 run called over the Red FOB: state %s hp %d" % [jet.state, jet.hp])
		huey.place(Vector3(560, 0, 120), 90.0)
		huey.hover_mode = true
		huey.order_fly(Vector3(640, 0, 116))
	if _gl.has("aa") and fmod(_test_clock, 3.0) < delta:
		var jet: A10 = a10s[0]
		print("GROW t=%.0f: %s %s hp %d at %s | Huey %s hp %d at %s" % [_test_clock, jet.callsign, jet.state, jet.hp, jet.global_position.round(), huey.state, huey.hp, huey.global_position.round()])
		if jet.state == "run" or jet.state == "egress":
			camera.focus = jet.global_position
			camera.size = 90.0
			camera._target_size = 90.0
			_sl_shot("aa_fire")
	if _gl.has("aa") and _test_clock > _gl.aa + 75.0:
		print("GROW: end — A-10 destroyed %s, Huey destroyed %s, pilots %d" % [a10s[0].destroyed or a10s[0].state == "crash", huey.destroyed, squads.filter(func(q): return q.kind == "pilot").size()])
		get_tree().quit()
	if _test_clock > 260.0:
		print("GROW: TIMEOUT")
		get_tree().quit()


func _path_into(from: Vector3, to: Vector3) -> String:
	var nav := level.get_navigation_map()
	var path := Level.find_path(nav, NavigationServer3D.map_get_closest_point(nav, from), NavigationServer3D.map_get_closest_point(nav, to))
	if path.is_empty():
		return "no path"
	var end: Vector3 = path[path.size() - 1]
	return "ends %.0f m from the goal (%d points)" % [Vector2(end.x - to.x, end.z - to.z).length(), path.size()]


func _redfob_lab_tick(delta: float) -> void:
	## The Red FOB: walls, towers and garrison; the gates keep you out; an M777 shell and an
	## engineer breach charge open the wall; then you can walk in and take it.
	var mid := RedFob.center()
	var eng: Squad = squads[2]
	var wall_spot := Vector3(RedFob.RECT.position.x, 0, 136.0)
	if _at(1.0, delta):
		for sq in enemy.squads:
			for m in sq.members:
				if is_instance_valid(m):
					m.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.spawning_enabled = false
		var rf := enemy.red_fob
		var kinds := {}
		for st in rf.pieces:
			kinds[st.kind] = kinds.get(st.kind, 0) + 1
		var inside := 0
		var on_walls := 0
		for sd in enemy.alive:
			if RedFob.contains(sd.global_position):
				inside += 1
				if sd.global_position.y > 1.0:
					on_walls += 1
		print("REDFOB: pieces %s | Red inside the walls %d (%d up on the catwalk or towers), tanks inside %d" % [kinds, inside, on_walls, enemy.tanks.filter(func(t): return RedFob.contains(t.global_position)).size()])
		print("REDFOB: objective %s owner %s" % [enemy.fob_objective().get("name", "?"), enemy.fob_objective().get("owner", "?")])
		# Move the engineers and the gun up to the Red FOB
		for i in eng.soldiers.size():
			eng.soldiers[i].global_position = level.ground_spot(Vector3(736, 0, 130 + i * 1.5), 20.0) + Vector3.UP * 0.1
		artillery.set_down(level.ground_spot(Vector3(560, 0, 136), 30.0), -PI * 0.5)
		camera.focus = mid + Vector3(-20, 0, 0)
		camera.size = 110.0
		camera._target_size = 110.0
	if _at(2.0, delta):
		var start := enemy.alive.size()
		enemy.counterattack(false)
		var newest: RedSoldier = enemy.alive[enemy.alive.size() - 1]
		print("REDFOB: counterattack spawned %d at %s (sally point %s), FOB held %s" % [enemy.alive.size() - start, newest.global_position.round(), enemy.red_fob.sally_point(), enemy.fob_held()])
		for sd in enemy.alive.slice(start):
			sd.process_mode = Node.PROCESS_MODE_DISABLED
	if _at(4.0, delta):
		_sl_shot("overview")
		print("REDFOB: path from outside to the middle before the breach: %s" % _path_into(Vector3(736, 0, 116), mid))
		var w := level.structure_at(wall_spot + Vector3(0, 0, -20), 2.0)
		print("REDFOB: M777 at %s; call on the west wall at %s: \"%s\"" % [artillery.global_position.round(), w.position.round(), artillery.call_fire(w.position)])
		_rf["shelled"] = w
		_rf["hp0"] = w.hp
	if _at(6.0, delta):
		camera.focus = wall_spot + Vector3(-8, 0, 0)
		camera.size = 40.0
		camera._target_size = 40.0
		_select_only([eng])
		_order_move(_to_screen(wall_spot + Vector3(-0.6, 1.2, 0)))
		print("REDFOB: right-click the west wall with the engineers: breaches %d, target %s" % [_breaches.size(), _breaches[0].target.kind if not _breaches.is_empty() else "-"])
		_rf["target"] = _breaches[0].target if not _breaches.is_empty() else null
	if not _breaches.is_empty() and _breaches[0].state == "fuse" and not _rf.has("fuse_t"):
		_rf["fuse_t"] = _test_clock
		print("REDFOB: charge set at t=%.1f" % _test_clock)
		_sl_shot("charge")
	if _rf.has("fuse_t") and not _rf.has("boom") and _breaches.is_empty():
		_rf["boom"] = _test_clock
		var t: Structure = _rf.target
		var dist := INF
		for sd in eng.soldiers:
			dist = minf(dist, sd.global_position.distance_to(t.position))
		print("REDFOB: boom at t=%.1f: target %s, engineers alive %d (closest %.0f m), Red FOB breached %s" % [_test_clock, t.state, eng.soldiers.size(), dist, enemy.red_fob.breached()])
		_sl_shot("breach")
	if _rf.has("boom") and not _rf.has("in") and fmod(_test_clock, 1.0) < delta and _path_into(Vector3(736, 0, 136), mid).begins_with("ends 0 "):
		_rf["open_t"] = _test_clock
		print("REDFOB: the map shows the way in %.0f s after the blast" % (_test_clock - _rf.boom))
	if _rf.has("boom") and (_rf.has("open_t") or _test_clock > _rf.boom + 30.0) and not _rf.has("in"):
		_rf["in"] = true
		var w: Structure = _rf.shelled
		print("REDFOB: shelled wall hp %d -> %d (%s), M777 rounds %d" % [_rf.hp0, w.hp, w.state, artillery.rounds_fired])
		print("REDFOB: path from outside to the middle after the breach: %s" % _path_into(Vector3(736, 0, 136), mid))
		# Clear the inside and walk in
		for sd in enemy.alive.duplicate():
			if Vector2(sd.global_position.x - mid.x, sd.global_position.z - mid.z).length() < RedArmy.OBJECTIVE_RADIUS + 2.0:
				sd.take_hit(999.0, Vector3.UP, null)
		for t in enemy.tanks.duplicate():
			if RedFob.contains(t.global_position):
				t.take_damage(9999.0)
		_select_only([eng])
		_order_move(_to_screen(mid))
		camera.focus = mid + Vector3(-15, 0, 10)
		camera.size = 70.0
		camera._target_size = 70.0
	if _rf.has("in") and fmod(_test_clock, 4.0) < delta:
		var o := enemy.fob_objective()
		print("REDFOB t=%.0f: engineers at %s, objective %s red %d blue %d progress %.0f%%" % [_test_clock, eng.soldiers[0].global_position.round() if not eng.soldiers.is_empty() else Vector3.ZERO, o.owner, o.red, o.blue, o.progress * 100.0])
		if o.owner == "blue" and not _rf.has("taken"):
			_rf["taken"] = _test_clock
			_sl_shot("taken")
			var before := enemy.wave
			enemy.counterattack(false)
			print("REDFOB: taken at t=%.0f; counterattack after that: waves %d -> %d (none)" % [_test_clock, before, enemy.wave])
			get_tree().quit()
	if _test_clock > 120.0:
		print("REDFOB: TIMEOUT")
		get_tree().quit()


func _sl_shot(shot_name: String) -> void:
	if _sling_shot == "" or _sl.has("shot_" + shot_name):
		return
	_sl["shot_" + shot_name] = true
	var path := _sling_shot.replace(".png", "_%s.png" % shot_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("SLING: saved %s" % path)


func _sling_lab_tick(delta: float) -> void:
	## The M777 sling load: the crew boards the Chinook, it hooks the gun, carries it, and sets
	## it down somewhere else facing a new way; the crew is dropped off and mans it.
	var gun := artillery
	var ch := chinook
	var crew_sq := gun.crew_squad
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for m in sq.members:
				if is_instance_valid(m):
					m.process_mode = Node.PROCESS_MODE_DISABLED
		for t in enemy.tanks:
			t.process_mode = Node.PROCESS_MODE_DISABLED
		_sl["home"] = gun.global_position
		_sl["home_yaw"] = gun.rotation.y
		camera.focus = (gun.global_position + ch.global_position) * 0.5
		camera.size = 60.0
		camera._target_size = 60.0
		print("SLING: gun at %s yaw %.0f, manned %d, Chinook at %s" % [gun.global_position.round(), rad_to_deg(gun.rotation.y), gun.crew_count(), ch.global_position.round()])
	if _at(3.0, delta):
		# A rifle squad flies along too, so the Chinook isn't empty
		_select_only([ch])
		_order_move(_to_screen(gun.global_position + Vector3.UP * 0.8))
		print("SLING: right-click the gun with the Chinook: pending %s, crew walking %d, manned %d" % [ch.sling_pending != null, crew_sq.soldiers.filter(func(x): return x.board_target == ch).size(), gun.crew_count()])
		_select_only([squads[0]])
		_order_board([squads[0]], ch)
		_select_only([ch])
	if _test_clock > 3.0 and fmod(_test_clock, 2.0) < delta:
		print("SLING t=%.0f: Chinook %s at %s, phase '%s', aboard %s, gun slung %s at %s, manned %d" % [_test_clock, ch.state, ch.global_position.round(), ch.sling_phase, hud._cargo_names(ch), gun.slung_by != null, gun.global_position.round(), gun.crew_count()])
		if ch.sling_pending != null:
			var where: PackedStringArray = []
			for sd in crew_sq.soldiers:
				where.append("%s%s" % [sd.global_position.round(), " in" if sd.boarded else ""])
			print("   crew: %s" % " ".join(where))
	if ch.sling_phase == "hooking" and ch._rope.visible:
		camera.focus = gun.global_position
		_sl_shot("hooking")
	if gun.slung_by != null and not _sl.has("hooked_t"):
		_sl["hooked_t"] = _test_clock
		print("SLING: hooked at t=%.1f; can it land? %s; pickup refused for Bravo: next line" % [_test_clock, ch.can_land()])
		_order_board([squads[1]], ch)
		ch.order_fly(Vector3(25, 0, 30))
	if _sl.has("hooked_t") and not _sl.has("drag") and _test_clock > _sl.hooked_t + 9.0:
		_sl["drag"] = true
		camera.focus = (ch.global_position + _sl.home) * 0.5
		camera.size = 70.0
		camera._target_size = 70.0
	if _sl.has("drag") and not _sl.has("dragged") and _test_clock > _sl.hooked_t + 10.0:
		_sl_shot("carry")
		# Right-drag from the old spot toward Globe Life Field: the barrel should face that way
		var a: Vector3 = _sl.home
		var to_glf := (_test_objective(0).pos as Vector3) - a
		to_glf.y = 0.0
		var b := a + to_glf.normalized() * 22.0
		_select_only([ch])
		_begin_line(_to_screen(a))
		for k in range(1, 11):
			_preview_line(_to_screen(a.lerp(b, k / 10.0)))
		_sl["want_yaw"] = atan2(-to_glf.x, -to_glf.z)
		_sl["dragged"] = true
	if _sl.has("dragged") and not _sl.has("released") and _test_clock > _sl.hooked_t + 10.5:
		_sl_shot("drop_preview")
		var a: Vector3 = _sl.home
		var to_glf := (_test_objective(0).pos as Vector3) - a
		to_glf.y = 0.0
		_end_line(_to_screen(a + to_glf.normalized() * 22.0))
		_sl["released"] = true
		print("SLING: right-drag drop ordered: phase '%s', want yaw %.0f" % [ch.sling_phase, rad_to_deg(_sl.want_yaw)])
	if ch.sling_phase == "lowering":
		camera.focus = gun.global_position
		if absf(wrapf(gun.global_rotation.y - _sl.want_yaw, -PI, PI)) < 0.15:
			_sl_shot("lowering")
	if _sl.has("released") and gun.slung_by == null and not _sl.has("down_t"):
		_sl["down_t"] = _test_clock
		print("SLING: set down at t=%.1f at %s (asked %s), yaw %.1f (asked %.1f)" % [_test_clock, gun.global_position.round(), (_sl.home as Vector3).round(), rad_to_deg(gun.rotation.y), rad_to_deg(_sl.want_yaw)])
	if _sl.has("down_t") and gun.crew_count() == 4 and not _sl.has("manned_t"):
		_sl["manned_t"] = _test_clock
		camera.focus = gun.global_position + Vector3(0, 0, 6)
		camera.size = 40.0
		camera._target_size = 40.0
		print("SLING: crew manning again at t=%.1f; Chinook %s, aboard %s" % [_test_clock, ch.state, hud._cargo_names(ch)])
	if _sl.has("manned_t") and _test_clock > _sl.manned_t + 2.0 and not _sl.has("fire"):
		_sl["fire"] = true
		_sl_shot("manned")
		print("SLING: call on Globe Life Field: \"%s\"" % gun.call_fire(_test_objective(0).pos))
		# Moving the crew off: they stay put; right-click the gun brings them back
		_select_only([crew_sq])
		_order_move(_to_screen(gun.global_position + Vector3(10, 0, 10)))
		print("SLING: crew ordered off: manned %d, stand_down %s" % [gun.crew_count(), crew_sq.get_meta("stand_down", false)])
	if _sl.has("fire") and not _sl.has("back") and _test_clock > _sl.manned_t + 12.0:
		_sl["back"] = true
		print("SLING: after 10 s away: manned %d" % gun.crew_count())
		_order_move(_to_screen(gun.global_position + Vector3.UP * 0.8))
	if _sl.has("back") and _test_clock > _sl.manned_t + 24.0:
		print("SLING: after right-clicking the gun: manned %d, fired %d" % [gun.crew_count(), gun.rounds_fired])
		get_tree().quit()
	if _test_clock > 150.0:
		print("SLING: TIMEOUT")
		get_tree().quit()


func _fob_lab_tick(delta: float) -> void:
	## Quick test bed: a finished base, then units walking in, out and up onto the catwalk
	if _at(1.0, delta):
		enemy.spawning_enabled = false
		for sq in enemy.squads:
			for m in sq.members:
				if is_instance_valid(m) and m is RedSoldier:
					m.process_mode = Node.PROCESS_MODE_DISABLED
		fob.plan_walls(Fob.snap_rect(Vector3(32, 0, 8), Vector3(68, 0, 40)))
		fob.plan_building("barracks", Vector3(50, 0, 18), 0.0)
		for p in fob.pieces:
			p.finish()
		print("LAB: base finished, %d pieces" % fob.pieces.size())
	if _at(2.0, delta) or _at(3.0, delta) or _at(5.0, delta) or _at(7.0, delta):
		print("LAB t=%.0f: dirty tiles %d, baking %d, queued %d" % [_test_clock, level._dirty_tiles.size(), level._nav_running, level._nav_queue.size()])
		var src := level._bake_src()
		var built := 0
		var faces := 0
		for st in level.structures:
			if st.is_built():
				built += 1
				faces += (st.nav_part().faces as PackedVector3Array).size()
		print("LAB src verts %d (base %d), obstructions %d (base %d), built %d, face verts %d, region tile0 polys %d" % [src.get_vertices().size(), level._nav_src.get_vertices().size(), src.get_projected_obstructions().size(), level._nav_src.get_projected_obstructions().size(), built, faces, 0])
		var q := NavigationServer3D.map_get_closest_point(level.get_navigation_map(), Vector3(41, 1.6, 10.4))
		print("LAB closest to catwalk point: %s" % q)
		for t in level._tiles:
			var o: Vector3 = t.origin
			if Rect2(o.x, o.z, Level.NAV_TILE, Level.NAV_TILE).has_point(Vector2(46, 24)):
				var nm: NavigationMesh = t.region.navigation_mesh
				var hi := 0
				for vv in nm.get_vertices():
					if vv.y > 1.0:
						hi += 1
				print("LAB tile verts above 1 m: %d" % hi)
				print("LAB tile at %s: mesh id %d, polys %d, verts %d, queued %s" % [o, nm.get_instance_id() if nm else 0, nm.get_polygon_count() if nm else 0, nm.get_vertices().size() if nm else 0, t.get("queued", false)])
	if _at(8.0, delta):
		var nav := level.get_navigation_map()
		var eng: Squad = squads[2]
		var dests := [Vector3(38, 0, -4), Vector3(20, 0, 14), Vector3(60, 0, 50), Vector3(80, 0, 34), Vector3(41, 1.6, 10.4)]
		for i in eng.soldiers.size():
			eng.soldiers[i].order_move(NavigationServer3D.map_get_closest_point(nav, dests[i]))
			var path := Level.find_path(nav, eng.soldiers[i].global_position, dests[i])
			print("LAB: engineer %d from %s to %s: path %d pts, ends %s, length %.0f" % [i, eng.soldiers[i].global_position.round(), dests[i], path.size(), path[-1] if path.size() > 0 else Vector3.ZERO, _path_len(path)])
	if _shot_path != "" and _at(20.0, delta):
		var bravo: Squad = squads[1]
		for i in bravo.soldiers.size():
			bravo.soldiers[i].order_move(NavigationServer3D.map_get_closest_point(level.get_navigation_map(), Vector3(54 + i * 1.5, 1.6, 10.4)))
		camera.focus = Vector3(50, 0, 24)
		camera.size = 50.0
		camera._target_size = 50.0
	if _shot_path != "" and _at(30.0, delta):
		get_viewport().get_texture().get_image().save_png(_shot_path.replace(".png", "_fob_built.png"))
		camera.focus = Vector3(56, 1.5, 12)
		camera.size = 18.0
		camera._target_size = 18.0
	if _shot_path != "" and _at(31.0, delta):
		get_viewport().get_texture().get_image().save_png(_shot_path.replace(".png", "_catwalk.png"))
		print("LAB: saved shots")
	for t in [12.0, 18.0, 26.0, 34.0]:
		if _at(t, delta):
			var info: PackedStringArray = []
			for sd in squads[2].soldiers:
				info.append("%s%s" % [sd.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " moving" if sd._has_order else ""])
			print("LAB t=%d: %s" % [int(t), " | ".join(info)])
	if _test_clock > 35.0:
		get_tree().quit()


func _crossing(path: PackedVector3Array, x: float) -> String:
	for i in range(1, path.size()):
		if (path[i - 1].x - x) * (path[i].x - x) <= 0.0:
			return "z %.0f" % path[i].z
	return "-"


func _path_len(path: PackedVector3Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i - 1].distance_to(path[i])
	return d


var _test_new_squad: Squad
var _test_new_jet: A10


func _reinforce_selftest(delta: float) -> void:
	if _at(119.0, delta):
		print("AUTOTEST: reinforcements — before 2:00: %d available, next in %d s, picker blocked: \"%s\"" % [reinforcements, int(reinforce_in), reinforcement_blocked("squad")])
	if _at(124.0, delta):
		print("AUTOTEST: reinforcements — after 2:00: %d available | limits: %s | squad: \"%s\" | Stryker: \"%s\"" % [reinforcements, limits_text(), reinforcement_blocked("squad"), reinforcement_blocked("stryker")])
		limit_bonus = 20      # the rest of the test isn't about the limits
		var before := squads.size()
		hud.toggle_reinforcements()
		var buttons := hud._reinforce_list.get_children()
		(buttons[0] as Button).pressed.emit()    # "Rifle squad", through the picker
		_test_new_squad = squads[-1] if squads.size() > before else null
		print("AUTOTEST: reinforcements — picked a squad from the picker: %s, %d soldiers at %s, picker open %s" % [
			_test_new_squad.squad_name if _test_new_squad else "none", _test_new_squad.soldiers.size() if _test_new_squad else 0,
			_test_new_squad.soldiers[0].global_position.round() if _test_new_squad else Vector3.ZERO, hud.reinforcements_open()])
		_select_only([_test_new_squad])
		_test_new_squad.order_move(Vector3(0, 0, 30), level.get_navigation_map())
		# Three more, to check the vehicles and the A-10 ferry flight
		reinforcements = 3
		var before_v := vehicles.size()
		for id in ["stryker", "chinook", "a10"]:
			call_reinforcement(id)
		var names: PackedStringArray = []
		for v in vehicles.slice(before_v):
			names.append("%s at %s" % [v.display_name if not (v is A10) else v.callsign, v.global_position.round()])
		_test_new_jet = a10s[-1]
		print("AUTOTEST: reinforcements — new vehicles: %s | runway full now: \"%s\" | cards %d" % [", ".join(names), reinforcement_blocked("a10"), hud._cards.size()])
	if _at(149.0, delta):
		var d := 0.0
		if _test_new_squad and not _test_new_squad.soldiers.is_empty():
			d = _test_new_squad.soldiers[0].global_position.distance_to(Vector3(0, 0, 30))
		print("AUTOTEST: reinforcements — t=149: new squad %.0f m from the FOB (walking) | %s %s at %s, slot %d" % [d, _test_new_jet.callsign, _test_new_jet.state, _test_new_jet.global_position.round(), _test_new_jet.slot_index])


func _drag(button: MouseButton, from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = from
	_unhandled_input(e)
	for k in range(1, 6):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, k / 5.0)
		_unhandled_input(m)
	var u := InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = to
	_unhandled_input(u)


func _support_shot_tick(delta: float) -> void:
	## Screenshot tour of the new units (godot -- --shot=path.png --support-shots)
	if _chinook_shots:
		_chinook_shot_actions(delta)
	elif _reinforce_shots:
		_reinforce_shot_actions(delta)
	else:
		if _at(0.5, delta):
			_queue_shot(1.0, "fob", Vector3(0, 0, -10), 70.0)
			_queue_shot(1.6, "a10_parked", a10s[0], 16.0)
			_queue_shot(2.2, "stryker", stryker, 9.0)
		if _at(2.5, delta):
			var t := _nearest_tank(enemy.objectives[0].pos)
			_queue_shot(3.0, "red_tank", t, 11.0)
			_queue_shot(3.6, "red_garrison", enemy.objectives[0].pos, 40.0)
			_test_tank = t
		if _at(4.0, delta):
			var tp := _test_tank.global_position
			_call_a10(tp + Vector3(-35, 0, -10), tp + Vector3(35, 0, 10))
		if _at(5.0, delta):
			_queue_shot(5.2, "a10_takeoff", a10s[0], 30.0)
		if _test_clock > 6.0 and a10s[0].state == "run" and a10s[0]._fired > 3 and not _shot_queue.any(func(s): return s.name == "a10_gun_run") and not has_meta("gun_shot"):
			set_meta("gun_shot", true)
			_queue_shot(_test_clock + 0.45, "a10_gun_run", _test_tank.global_position + Vector3(0, 10, 0), 50.0)
	for shot in _shot_queue.duplicate():
		if not shot.framed and _test_clock >= shot.t - 0.15:
			shot.framed = true
			var f = shot.focus
			camera.focus = (f as Node3D).global_position + Vector3.UP * 1.0 if f is Node3D else f
			camera.size = shot.size
			camera._target_size = shot.size
		if _test_clock >= shot.t:
			var img := get_viewport().get_texture().get_image()
			var path := _shot_path.replace(".png", "_%s.png" % shot.name)
			img.save_png(path)
			print("AUTOTEST: saved %s" % path)
			_shot_queue.erase(shot)
	var done_at := 17.0 if _chinook_shots else (50.0 if _reinforce_shots else 40.0)
	if (_test_clock > done_at and _shot_queue.is_empty()) or _test_clock > 60.0:
		get_tree().quit()


func _reinforce_shot_actions(delta: float) -> void:
	if _at(0.5, delta):
		reinforcements = 2
		reinforce_in = 47.0
		hud.toggle_reinforcements()
		_queue_shot(1.5, "reinforce_picker", Vector3(0, 0, 0), 60.0)
	if _at(2.0, delta):
		hud.toggle_reinforcements()
	# Call them in once the whole city is mapped (as it is by 2:00 in a real game)
	if not has_meta("called") and level.nav_done >= level.nav_total and _test_clock > 3.0:
		set_meta("called", true)
		_corner_uses.clear()
		_rng.seed = 7
		call_reinforcement("stryker")
		call_reinforcement("squad")
		var a: Vector3 = arrivals[0][0]
		_queue_shot(_test_clock + 1.0, "reinforce_arrival", a, 34.0)
		_queue_shot(_test_clock + 1.6, "reinforce_minimap", Vector3(0, 0, 0), 60.0)


func _chinook_shot_actions(delta: float) -> void:
	if _at(0.5, delta):
		_select_only([chinook])
		_queue_shot(1.5, "chinook", chinook, 15.0)
	if _at(2.0, delta):
		_on_key(KEY_L)
		_queue_shot(8.0, "chinook_hover", chinook, 19.0)
	if _at(8.5, delta):
		_select_only([humvee])
		_click(MOUSE_BUTTON_RIGHT, _to_screen(chinook.global_position + Vector3.UP * 2.0))
		_queue_shot(16.0, "chinook_humvee", chinook, 20.0)


func _autotest_tick(delta: float) -> void:
	_test_clock += delta
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if _test_clock > 2.0:
		_test_peak_phys = maxf(_test_peak_phys, phys_ms)
	_test_report -= delta
	if _test_report <= 0.0:
		_test_report = 10.0
		var objs: PackedStringArray = []
		for o in enemy.objectives:
			objs.append("%s:%s(%d/%d)" % [o.name.substr(0, 6), o.owner, o.red, o.blue])
		print("t=%5.1f red %d tanks %d | killed %d tanks %d | soldiers A%d B%d kills A%d B%d | %s | phys=%.2fms" % [
			_test_clock, enemy.alive.size(), enemy.tanks.size(), enemy.kills, enemy.tanks_destroyed,
			squads[0].soldiers.size(), squads[1].soldiers.size(), squads[0].kills, squads[1].kills, " ".join(objs), phys_ms])
	if _test_clock > 3.0 and _test_clock - delta <= 3.0 and _shot_path == "":
		_input_selftest()
	if _line_test_pending and _test_clock > 8.5:
		_line_test_pending = false
		var radii: PackedStringArray = []
		for sq in squads.slice(0, 2):
			for sd in sq.soldiers:
				var d: Vector3 = sd.global_position - Vector3(-0.5, 0, 0.5)
				radii.append("%.1f" % Vector2(d.x, d.z).length())
		print("AUTOTEST: circle — distance from centre: %s" % " ".join(radii))
	if _fob_lab:
		_fob_lab_tick(delta)
		return
	if _sling_lab:
		_sling_lab_tick(delta)
		return
	if _redfob_lab:
		_redfob_lab_tick(delta)
		return
	if _growth_lab:
		_growth_lab_tick(delta)
		return
	if _orders_lab:
		_orders_lab_tick(delta)
		return
	if _base_lab:
		_base_lab_tick(delta)
		return
	if _vehicle_lab:
		_vehicle_lab_tick(delta)
		return
	if _supply_lab:
		_supply_lab_tick(delta)
		return
	if _move_lab:
		_move_lab_tick(delta)
		return
	if _flight_lab:
		_flight_lab_tick(delta)
		return
	if _soldier_lab:
		_soldier_lab_tick(delta)
		return
	if _support_shots:
		_support_shot_tick(delta)
		return
	if _city_shots:
		_city_shot_tick(delta)
		return
	if _shot_path != "":
		_support_selftest(delta)
		if not _shot_times.is_empty() and _test_clock >= _shot_times[0]:
			var img := get_viewport().get_texture().get_image()
			var path := _shot_path.replace(".png", "_%02d.png" % int(_shot_times[0]))
			img.save_png(path)
			print("AUTOTEST: saved %s" % path)
			_shot_times.remove_at(0)
			if _shot_times.is_empty():
				get_tree().quit()
		return
	_support_selftest(delta)
	if _test_clock >= TEST_LENGTH:
		print("AUTOTEST: done state=%s peak_phys=%.2fms" % [state, _test_peak_phys])
		get_tree().quit()
