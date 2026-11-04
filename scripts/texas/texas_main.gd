class_name TexasMain
extends Node3D
## Taking Back Texas, Phase 2: the 1:3 Texas world. Ties together the simulation (every unit,
## everywhere, as data), the streamed ground tiles, the strategic map, and the 3D units shown
## near the camera; plus the camera, origin shifting, time speed-up, save and load, and the HUD.
##
## Origin shifting: positions in the simulation are 64-bit world metres. The scene keeps its
## origin near the camera and draws everything relative to it, so render coordinates stay
## small and precise anywhere in the state.

const SAVE_PATH := "user://texas_save.sav"
const START_DATE := "1 Nov 2026"
const START_HOUR := 6.0
const SPEEDS := [0.0, 1.0, 4.0, 16.0, 64.0, 256.0]
const TACTICAL_SIZE := 9000.0          # camera size (m) below which the 3D world is shown
const MIN_SIZE := 60.0
const MAX_SIZE := 520000.0
const SHIFT_AT := 4000.0               # move the origin when the camera is this far from it
const MAX_PROXIES := 420
const PITCH := -50.0
const RING_SIZE := {"rifle": 7.0, "humvee": 8.0, "stryker": 9.0, "bradley": 9.0, "lmtv": 9.0, "tank": 10.0, "aa": 9.0,
	"black_hawk": 13.0, "chinook": 16.0, "little_bird": 8.0, "apache": 12.0, "hornet": 15.0, "a10": 15.0,
	"lcac": 18.0, "carrier": 190.0, "amphib": 150.0, "destroyer": 90.0, "cruiser": 100.0}

static var start_mode := "test"         # "galveston": the first playable slice

var sim: TexasSim
var roads: TexasRoads
var tiles: TexasTiles
var map: TexasMap
var camera: Camera3D
var origin_x := 0.0
var origin_z := 0.0
var focus_x := 0.0                     # what the camera looks at, world metres (64-bit)
var focus_z := 0.0
var size := 400000.0
var _target_size := 400000.0
var _yaw := deg_to_rad(20.0)
var speed_i := 1
var _acc := 0.0
var _step := 1.0
var _height_cache := {}
var _proxies := {}                     # unit index -> Node3D
var _pool := {}                        # proxy kind key -> [Node3D]
var _proxy_t := 0.0
var _hud: Label
var _hud2: Label
var _help: Label
var _msg: Label
var _msg_t := 0.0
var _dragging := false
var _water: MeshInstance3D
# Performance numbers for the HUD and the test
var frame_ms_log: Array = []
var script_ms_log: Array = []
var sim_ms_log: Array = []
var lab := false
var _lab_prefix := ""
var _lab_t := 0.0
var _lab_step := 0
var _lab_data := {}
var _startup_ms := {}
var galveston_lab := false
var campaign: TexasCampaign
var ui: TexasUI
var fx: TexasFx
var selected: Array = []
var lz_mode := false
var _lpress := Vector2(-1.0, -1.0)
var _rpress := Vector2.ZERO
var _rmoved := false
var _drawing := false                  # right-dragging a line for the selected units to spread along
var _draw_pts := PackedVector2Array()  # the line, in map metres
var _draw_last := Vector2.ZERO
var _marks: Array = []                 # spots just ordered (shown for a moment)
var _marks_t := 0.0
var _box: ColorRect
var _rings := {}                       # unit -> its ring
var _ring_pool: Array = []
var _ring_mesh: TorusMesh
var _ring_mat := {}                    # "blue", "red", "sel" -> material
var _zone_nodes: Array = []            # [ring, label] per zone
var _lz_node: Node3D
var _deck_slot := {}                   # aircraft aboard a ship -> deck spot
var _seen_shots: PackedInt32Array
var _city_labels: Array = []           # [x, z, tier, name]
var _names: TexasNames
var naval: TexasNavalFx                # the fleet's guns and missiles up close
var _ghosts: GhostMarks                # outlines where the ships of a formation will end up
var _ghost_list: Array = []            # [[position, heading, type id], ...]
var _ghost_t := 0.0


class GhostMarks extends Control:
	## Dashed-looking outlines of ships on the water (screen space), the line being drawn for
	## a move, and the spots units have just been sent to
	var polys: Array = []
	var alpha := 1.0
	var line := PackedVector2Array()
	var dots: Array = []
	var dot_alpha := 1.0

	func _draw() -> void:
		if line.size() >= 2:
			draw_polyline(line, Color(0.0, 0.0, 0.0, 0.5), 5.0, true)
			draw_polyline(line, Color(0.55, 1.0, 0.55, 0.95), 2.5, true)
		for d in dots:
			draw_circle(d, 5.0, Color(0, 0, 0, 0.5 * dot_alpha))
			draw_circle(d, 3.5, Color(0.55, 1.0, 0.55, 0.95 * dot_alpha))
		var col := Color(0.55, 0.85, 1.0, 0.85 * alpha)
		for pts in polys:
			var loop: PackedVector2Array = pts
			loop.append(pts[0])
			draw_polyline(loop, col, 2.0, true)
			draw_circle((pts[0] + pts[1]) * 0.5, 2.5, col)
var show_names := true                 # N hides and shows every name on the map


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--texas-lab"):
			lab = true
			_lab_prefix = a.trim_prefix("--texas-lab").trim_prefix("=")
		elif a.begins_with("--ui-lab"):
			lab = true
			galveston_lab = true
			ui_lab = true
			_lab_prefix = a.trim_prefix("--ui-lab").trim_prefix("=")
		elif a.begins_with("--command-lab"):
			lab = true
			galveston_lab = true
			command_lab = true
			_lab_prefix = a.trim_prefix("--command-lab").trim_prefix("=")
		elif a.begins_with("--navy-lab"):
			lab = true
			galveston_lab = true
			navy_lab = true
			_lab_prefix = a.trim_prefix("--navy-lab").trim_prefix("=")
		elif a.begins_with("--org-lab"):
			lab = true
			galveston_lab = true
			org_lab = true
			_lab_prefix = a.trim_prefix("--org-lab").trim_prefix("=")
		elif a.begins_with("--water-lab"):
			lab = true
			galveston_lab = true
			water_lab = true
			_lab_prefix = a.trim_prefix("--water-lab").trim_prefix("=")
		elif a.begins_with("--galveston-lab"):
			lab = true
			galveston_lab = true
			_lab_prefix = a.trim_prefix("--galveston-lab").trim_prefix("=")
	var t0 := Time.get_ticks_usec()
	TexasGeo.setup()
	var t1 := Time.get_ticks_usec()
	roads = TexasRoads.new()
	var t2 := Time.get_ticks_usec()
	sim = TexasSim.new(roads)
	if start_mode == "galveston" or galveston_lab:
		seed(1836)
		campaign = TexasCampaign.new()
		campaign.setup(sim)
	else:
		sim.seed_demo(1.5 if lab else 1.0, 1500 if lab else 900)
	_startup_ms = {"geo": (t1 - t0) / 1000.0, "roads": (t2 - t1) / 1000.0, "seed": (Time.get_ticks_usec() - t2) / 1000.0}
	_build_scene()
	_set_origin(0.0, 0.0)
	if campaign != null:
		var c: int = campaign.ships.carrier
		look_at_world(sim.x[c], sim.z[c], 2400.0)
		_set_origin(roundf(focus_x / 1024.0) * 1024.0, roundf(focus_z / 1024.0) * 1024.0)
		speed_i = 1
		_say("Galveston to Houston. The fleet is off Galveston with the first landing force aboard.")
	else:
		_say("Taking Back Texas: Texas test world. %d units in the field." % sim.count)


func _exit_tree() -> void:
	# Let the background work finish before everything it uses is freed
	if sim != null:
		sim.finish()
	if tiles != null:
		tiles.finish()
	TexasWater.finish()
	if map != null:
		map.finish()


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.36, 0.52)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	sun.light_energy = 1.1
	add_child(sun)
	# The Gulf: one big water plane at sea level under everything
	var wm := PlaneMesh.new()
	wm.size = Vector2(1.2e6, 1.2e6)
	_water = MeshInstance3D.new()
	_water.mesh = wm
	TexasWaterLook.setup()
	_water.material_override = TexasWaterLook.sea
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	tiles = TexasTiles.new(roads)
	add_child(tiles)
	map = TexasMap.new()
	map.setup(sim, roads)
	add_child(map)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	add_child(camera)
	camera.current = true
	fx = TexasFx.new(sim)
	fx.pos_of = unit_pos
	add_child(fx)
	naval = TexasNavalFx.new(sim, self, fx)
	add_child(naval)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.86
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	for key in ["blue", "red", "sel", "zone_blue", "zone_red", "lz"]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"blue": Color(0.35, 0.65, 1.0, 0.55), "red": Color(1.0, 0.3, 0.25, 0.55), "sel": Color(1.0, 1.0, 1.0),
			"zone_blue": Color(0.35, 0.65, 1.0, 0.8), "zone_red": Color(1.0, 0.3, 0.25, 0.8), "lz": Color(1.0, 0.85, 0.2)}[key]
		if m.albedo_color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = key == "sel" or key == "lz"
		if key == "blue" or key == "red":
			m.render_priority = -20            # under the sea's surface for ships, as a faint glow
		_ring_mat[key] = m
	if campaign != null:
		_build_markers()
	_build_city_labels()
	_build_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.09, 0.10, 0.82)))
	panel.position = Vector2(10, 10)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UiTheme.label("TAKING BACK TEXAS  ·  %s" % ("Galveston to Houston" if campaign != null else "Texas test world"), 15, UiTheme.ACCENT))
	_hud = UiTheme.label("", 13, UiTheme.TEXT)
	v.add_child(_hud)
	_hud2 = UiTheme.label("", 11, UiTheme.TEXT_DIM)
	v.add_child(_hud2)
	_help = UiTheme.label("WASD / right-drag: pan · wheel: zoom · Q/E: rotate · Space: pause · 1-5: time speed · Home: whole state · N names · F5 save · F9 load", 11, UiTheme.TEXT_DIM)
	if campaign != null:
		_help.text = "Left-click / drag: select · cards: click select, double-click go to · right-click: move there · right-drag: spread along a line · V send ashore · L board · U unload · R refuel · X stop · Z landing zone · O order units · F fleet · G formation · N names · WASD / middle-drag: pan · wheel: zoom · Q/E rotate · Space pause · 1-5 speed · F5/F9 save/load"
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 12
	_help.offset_top = -26
	layer.add_child(_help)
	_msg = UiTheme.label("", 14, UiTheme.TEXT)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_msg.offset_top = 14
	_msg.offset_left = -300
	_msg.offset_right = 300
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_msg)
	_names = TexasNames.new()
	layer.add_child(_names)
	layer.move_child(_names, 0)
	_ghosts = GhostMarks.new()
	_ghosts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ghosts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ghosts)
	layer.move_child(_ghosts, 1)
	_box = ColorRect.new()
	_box.color = Color(1, 1, 1, 0.12)
	_box.visible = false
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_box)
	if campaign != null:
		_msg.visible = false
		ui = TexasUI.new(self, campaign)
		layer.add_child(ui)


func _say(text: String) -> void:
	_msg.text = text
	_msg_t = 5.0
	print("TEXAS: " + text)
	if ui != null:
		ui.message(text)


# --- Input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(0.8, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.25, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmoved = false
				_rpress = mb.position
				# with units selected, right-drag draws where they go; otherwise it pans
				if campaign != null and not selected.is_empty() and not lz_mode:
					_drawing = true
					_draw_pts = PackedVector2Array([_ground_under(mb.position)])
					_draw_last = mb.position
				else:
					_dragging = true
			else:
				_dragging = false
				if _drawing:
					_drawing = false
					if _rmoved and _draw_pts.size() >= 2:
						_line_order(_draw_pts)
					else:
						_right_click(mb.position)
					_draw_pts = PackedVector2Array()
				elif not _rmoved and campaign != null:
					_right_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and campaign != null:
			if mb.pressed:
				_lpress = mb.position
			elif _lpress.x >= 0.0:
				if mb.position.distance_to(_lpress) > 8.0:
					_box_select(Rect2(_lpress, Vector2.ZERO).expand(mb.position), mb.shift_pressed)
				else:
					_click_select(mb.position, mb.shift_pressed)
				_lpress = Vector2(-1.0, -1.0)
				_box.visible = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _lpress.x >= 0.0 and mm.position.distance_to(_lpress) > 8.0:
			_box.visible = true
			var r := Rect2(_lpress, Vector2.ZERO).expand(mm.position)
			_box.position = r.position
			_box.size = r.size
		if _drawing:
			if mm.position.distance_to(_rpress) > 10.0:
				_rmoved = true
			if mm.position.distance_to(_draw_last) > 8.0:
				_draw_last = mm.position
				_draw_pts.append(_ground_under(mm.position))
		if _dragging:
			if mm.position.distance_to(_rpress) > 6.0:
				_rmoved = true
			var px := size / get_viewport().get_visible_rect().size.y
			var right := Vector2(cos(_yaw), -sin(_yaw))
			var fwd := Vector2(-sin(_yaw), -cos(_yaw))
			var d := -right * mm.relative.x * px + fwd * mm.relative.y * px / sin(deg_to_rad(-PITCH))
			focus_x += d.x
			focus_z += d.y
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				speed_i = 1 if speed_i == 0 else 0
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				speed_i = event.keycode - KEY_1 + 1
			KEY_HOME:
				look_at_world(0.0, 0.0, 400000.0)
			KEY_Q:
				_yaw += PI * 0.25
			KEY_E:
				_yaw -= PI * 0.25
			KEY_F5:
				save_game()
			KEY_F9:
				load_game()
			KEY_N:
				show_names = not show_names
				_say("Names on the map %s (N)." % ("shown" if show_names else "hidden"))
		if campaign != null:
			match event.keycode:
				KEY_L:
					cmd_board()
				KEY_U:
					cmd_unload()
				KEY_R:
					cmd_rtb()
				KEY_X:
					cmd_stop()
				KEY_V:
					cmd_ashore()
				KEY_G:
					set_formation((campaign.formation.shape + 1) % TexasFormation.SHAPES.size())
				KEY_Z:
					begin_lz()
				KEY_O:
					ui.toggle_orders()
				KEY_F:
					var c := campaign._any_ship()
					if c >= 0:
						look_at_world(sim.x[c], sim.z[c], 2400.0)
				KEY_ESCAPE:
					lz_mode = false
					selected.clear()


# --- Commands (campaign) ------------------------------------------------------------------------

func begin_lz() -> void:
	lz_mode = true
	_say("Right-click on land where the force should come ashore.")


func vehicles_ashore() -> void:
	var n := campaign.send_vehicles_ashore()
	_say("%d vehicles queued for the landing craft." % n if n > 0 else "No vehicles waiting aboard.")


func troops_ashore() -> void:
	var n := campaign.send_troops_ashore()
	_say("%d squads queued for the helicopters." % n if n > 0 else "No squads waiting aboard.")


func launch(t: int) -> void:
	var i := campaign.launch(t)
	if i >= 0:
		selected = [i]
		_say("%s launched." % TexasUnits.label(t, 0))


func order(t: int) -> void:
	if not campaign.add_order(t, ui.order_company()):
		_say("Not enough points for a %s (it costs %d, you have %d)." % [TexasUnits.label(t, 0), TexasUnits.TYPES[t].cost, campaign.points])


func cmd_board() -> void:
	var n := campaign.board_nearest(selected)
	_say("%d squads boarded." % n if n > 0 else "No transport with room within 750 m real (squads only).")
	_drop_hidden()


func cmd_unload() -> void:
	var n := campaign.unload(selected)
	_say("%d unloaded." % n if n > 0 else "Nothing to unload here (not over water).")


func cmd_rtb() -> void:
	var n := campaign.return_to_base(selected)
	_say("%d aircraft heading back to refuel and rearm." % n if n > 0 else "Select aircraft in the air to send them back.")


func select_fleet() -> void:
	selected = campaign.formation._ships(campaign.ships.values())
	_say("%d ships selected. Right-click to sail them in %s formation." % [selected.size(), campaign.formation.shape_name().to_lower()])


func set_formation(k: int) -> void:
	var fm := campaign.formation
	_say(fm.set_shape(k, selected))
	if not fm.active():
		var s := fm._ships(selected)
		if s.size() < 2:
			s = fm._ships(campaign.ships.values())
		var g: int = fm.places(s)[0]
		if g >= 0:
			_show_ghosts(fm.preview(s, Vector2(sim.x[g], sim.z[g])))
	else:
		_show_ghosts(fm.preview([fm.lead] + fm.members.keys(), fm.dest))


func _show_ghosts(list: Array) -> void:
	_ghost_list = list
	_ghost_t = 6.0


func _screen_at(p: Vector2) -> Vector2:
	var y := maxf(_ground(p.x, p.y), 0.0) if size < TACTICAL_SIZE else 0.0
	var local := Vector3(p.x - origin_x, y, p.y - origin_z)
	if camera.is_position_behind(local):
		return Vector2(-1e5, -1e5)
	return camera.unproject_position(local)


func _update_ghosts(delta: float) -> void:
	_ghost_t -= delta
	var polys: Array = []
	if _ghost_t > 0.0 and size < TACTICAL_SIZE * 2.0:
		for g in _ghost_list:
			var p: Vector2 = g[0]
			var ax := TexasFormation.axes(g[1])
			var id: String = g[2]
			var hull: Vector2 = TexasFormation.HULL.get(id, Vector2(150, 20))
			# never smaller on screen than a few pixels, so they show from further out
			var px := size / get_viewport().get_visible_rect().size.y
			var L := maxf(hull.x * 0.5, 14.0 * px)
			var B := maxf(hull.y * 0.5, 4.0 * px)
			var pts := PackedVector2Array()
			var ok := true
			for c in [Vector2(-B, L), Vector2(B, L), Vector2(B, -L), Vector2(-B, -L)]:
				var w: Vector2 = p + ax[0] * c.x + ax[1] * c.y
				var local := Vector3(w.x - origin_x, 0.0, w.y - origin_z)
				if camera.is_position_behind(local):
					ok = false
					break
				pts.append(camera.unproject_position(local))
			if ok:
				# the bow end comes first (the dot marks it)
				polys.append(pts)
	_ghosts.polys = polys
	_ghosts.alpha = clampf(_ghost_t / 1.5, 0.0, 1.0)
	# the line being drawn, and the spots just ordered
	var line := PackedVector2Array()
	if _drawing:
		for p in _draw_pts:
			line.append(_screen_at(p))
	_ghosts.line = line
	_marks_t -= delta
	var dots: Array = []
	if _marks_t > 0.0:
		for p in _marks:
			dots.append(_screen_at(p))
	_ghosts.dots = dots
	_ghosts.dot_alpha = clampf(_marks_t / 1.0, 0.0, 1.0)
	_ghosts.queue_redraw()


func cmd_stop() -> void:
	campaign.formation.release(selected)
	for i in selected:
		if sim.alive[i] == 1 and sim.aboard[i] == -1:
			sim.stop(i)


func _drop_hidden() -> void:
	## Units that went aboard something leave the selection
	var keep: Array = []
	for i in selected:
		if sim.alive[i] == 1 and sim.aboard[i] == -1:
			keep.append(i)
	selected = keep


func _right_click(pos: Vector2) -> void:
	var p := _ground_under(pos)
	if lz_mode:
		if campaign.set_lz(p):
			lz_mode = false
		return
	if selected.is_empty():
		return
	var aboard: Array = []
	for i in selected:
		if _aboard_ship(i):
			aboard.append(i)
	if not aboard.is_empty():
		if TexasSim.is_water(p):
			_say("Pick a spot on land for them to go ashore.")
		else:
			_say_ashore(campaign.send_ashore(aboard, p), "here")
			_show_marks([p])
		if aboard.size() == selected.size():
			return
	if campaign.formation._ships(selected).size() >= 2:
		_show_ghosts(campaign.formation.preview(selected, p))
	var n := campaign.command_move(selected, p)
	if n == 0 and aboard.is_empty():
		_say("They can't go there.")


func _screen_of(i: int) -> Vector2:
	var w := unit_pos(i)
	var local := Vector3(w.x - origin_x, w.y if size < TACTICAL_SIZE else 30.0, w.z - origin_z)
	if camera.is_position_behind(local):
		return Vector2(-1e6, -1e6)
	return camera.unproject_position(local)


func _pickable(i: int) -> bool:
	## Your units in the open, and your aircraft parked on a deck or an airfield
	if sim.alive[i] == 0 or sim.side[i] != 0:
		return false
	return sim.aboard[i] == -1 or _deck_slot.has(i) or (sim.aboard[i] <= -2 and sim.is_air(i))


func _click_select(pos: Vector2, add: bool) -> void:
	var best := -1
	var best_d := 22.0
	for i in sim.count:
		if not _pickable(i):
			continue
		var d := _screen_of(i).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if not add:
		selected.clear()
	if best >= 0:
		if best in selected:
			selected.erase(best)
		else:
			selected.append(best)


func _box_select(r: Rect2, add: bool) -> void:
	if not add:
		selected.clear()
	var found: Array = []
	var any_not_ship := false
	for i in sim.count:
		if not _pickable(i):
			continue
		if r.has_point(_screen_of(i)):
			found.append(i)
			if sim.kind[i] != TexasSim.Kind.SHIP:
				any_not_ship = true
	for i in found:
		if any_not_ship and sim.kind[i] == TexasSim.Kind.SHIP:
			continue
		if not (i in selected):
			selected.append(i)


func _zoom_at(factor: float, mouse: Vector2) -> void:
	## Zoom keeping the ground under the mouse where it is
	var before := _ground_under(mouse)
	_target_size = clampf(_target_size * factor, MIN_SIZE, MAX_SIZE)
	size = _target_size
	_apply_camera()
	var after := _ground_under(mouse)
	focus_x += before.x - after.x
	focus_z += before.y - after.y


func _ground_under(mouse: Vector2) -> Vector2:
	## World metres of the point on the ground plane under the mouse
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var gy := _ground(focus_x, focus_z) if size < TACTICAL_SIZE else 0.0
	if absf(dir.y) < 1e-4:
		return Vector2(focus_x, focus_z)
	var t := (gy - from.y) / dir.y
	var p := from + dir * t
	return Vector2(p.x + origin_x, p.z + origin_z)


func look_at_world(x: float, z: float, at_size: float) -> void:
	focus_x = x
	focus_z = z
	_target_size = at_size
	size = at_size


# --- Every frame ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pan(delta)
	size = lerpf(size, _target_size, 1.0 - exp(-12.0 * delta))
	# Origin shifting: keep the scene's origin near the camera
	if Vector2(focus_x - origin_x, focus_z - origin_z).length() > SHIFT_AT:
		_set_origin(roundf(focus_x / 1024.0) * 1024.0, roundf(focus_z / 1024.0) * 1024.0)
	_run_sim(delta)
	if campaign != null:
		_campaign_frame()
	var tactical := size < TACTICAL_SIZE
	tiles.visible = tactical
	_water.visible = tactical
	map.show_map(not tactical)
	map.show_icons(not tactical)
	map.icon_size = size / 140.0
	if tactical:
		var aspect := get_viewport().get_visible_rect().size.aspect()
		var reach := size * 0.5 * maxf(aspect, 1.0) / sin(deg_to_rad(-PITCH)) * 1.25
		tiles.wanted(focus_x, focus_z, reach)
	_proxy_t -= delta
	if _proxy_t <= 0.0:
		_proxy_t = 0.25
		_pick_proxies(tactical)
	_move_proxies(delta)
	if campaign != null or not sim.shots.is_empty():
		var reach := size * 0.9 if tactical else 0.0
		fx.update(delta, Vector2(focus_x, focus_z), reach, SPEEDS[speed_i])
	if naval != null:
		naval.update(delta, SPEEDS[speed_i])
	_update_rings()
	_update_city_labels(tactical)
	if campaign != null:
		_update_ghosts(delta)
	_apply_camera()
	_update_hud(delta)
	frame_ms_log.append(delta * 1000.0)
	script_ms_log.append((Time.get_ticks_usec() - t0) / 1000.0)
	if frame_ms_log.size() > 600:
		frame_ms_log.pop_front()
		script_ms_log.pop_front()
	if ui_lab:
		_ui_lab_tick(delta)
	elif water_lab:
		_water_lab_tick(delta)
	elif org_lab:
		_org_lab_tick(delta)
	elif navy_lab:
		_navy_lab_tick(delta)
	elif command_lab:
		_command_lab_tick(delta)
	elif galveston_lab:
		_galveston_lab_tick(delta)
	elif lab:
		_lab_tick(delta)


func _pan(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if move == Vector2.ZERO:
		return
	var right := Vector2(cos(_yaw), -sin(_yaw))
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	var d := (right * move.x + fwd * move.y).normalized() * size * 0.9 * delta
	focus_x += d.x
	focus_z += d.y


func _run_sim(delta: float) -> void:
	## Game time runs at the chosen speed; the simulation ticks in steps that grow with it
	var spd: float = SPEEDS[speed_i]
	if spd <= 0.0:
		return
	if campaign != null and campaign.result != "":
		return
	# Longer steps at high speed: fewer ticks (and fight rounds) per real second
	_step = clampf(spd / 6.0, 0.5, 30.0)
	_acc += delta * spd
	var n := 0
	while _acc >= _step and n < 2:
		sim.tick(_step)
		if campaign != null:
			campaign.tick(_step)
		sim_ms_log.append(sim.tick_ms)
		if sim_ms_log.size() > 300:
			sim_ms_log.pop_front()
		_acc -= _step
		n += 1
	if n == 2 and _acc > _step * 4.0:
		_acc = _step        # can't keep up: drop the backlog rather than spiral
	if sim.shots != _seen_shots:
		_seen_shots = sim.shots
		fx.set_pairs(sim.shots)
	# Losses near the camera blow up and leave wrecks
	if not sim.killed_recent.is_empty():
		var tactical := size < TACTICAL_SIZE
		for i in sim.killed_recent:
			if sim.aboard[i] != -1:
				continue
			var w := unit_pos(i)
			if tactical and Vector2(w.x - focus_x, w.z - focus_z).length() < size * 1.2:
				var k: int = sim.kind[i]
				var big := 60.0 if k == TexasSim.Kind.SHIP else (14.0 if k >= TexasSim.Kind.WHEELED else 5.0)
				var wreck := Vector3.ZERO
				if k == TexasSim.Kind.WHEELED or k == TexasSim.Kind.ARMOR:
					wreck = Vector3(3.2, 2.0, 6.5)
				elif k == TexasSim.Kind.HELI:
					wreck = Vector3(3.0, 1.6, 12.0)
				if k == TexasSim.Kind.HELI or k == TexasSim.Kind.JET:
					w.y = _ground(w.x, w.z)
				fx.explode(w, big, wreck, sim.heading[i])
			if campaign != null and sim.side[i] == 0 and sim.kind[i] >= TexasSim.Kind.HELI and sim.kind[i] != TexasSim.Kind.SHIP:
				_say("Lost: %s." % TexasUnits.label(sim.utype[i], 0))
		sim.killed_recent = PackedInt32Array()
	for i in sim.crashed_recent:
		if sim.side[i] == 0:
			_say("A %s ran out of fuel and %s." % [TexasUnits.label(sim.utype[i], 0), "crashed" if sim.alive[i] == 0 else "came down hard"])
	sim.crashed_recent = PackedInt32Array()


func _campaign_frame() -> void:
	for m in campaign.messages:
		_say(m)
	campaign.messages.clear()
	if not campaign.alerts.is_empty():
		campaign.alerts.clear()
		if speed_i > 2 and not galveston_lab:
			speed_i = 2
			_say("Slowing down to 4x.")
	map.selected = {}
	for i in selected:
		map.selected[i] = true
	_drop_dead_from_selection()
	_update_markers()


func _drop_dead_from_selection() -> void:
	var keep: Array = []
	for i in selected:
		if _selectable(i):
			keep.append(i)
	selected = keep


func _selectable(i: int) -> bool:
	## What can be in the selection: what you can click on the map, and (from the unit cards)
	## troops and vehicles still aboard a ship, waiting to be sent ashore
	if _pickable(i):
		return true
	if sim.alive[i] == 0 or sim.side[i] != 0:
		return false
	var h := sim.aboard[i]
	return h >= 0 and TexasUnits.is_ship(sim.utype[h]) and TexasUnits.is_ground(sim.utype[i])


func _aboard_ship(i: int) -> bool:
	var h := sim.aboard[i]
	return sim.alive[i] == 1 and h >= 0 and TexasUnits.is_ship(sim.utype[h]) and TexasUnits.is_ground(sim.utype[i])


func _line_order(pts: PackedVector2Array) -> void:
	## Spread the selection along the line drawn
	var r: Dictionary = campaign.command_line(selected, pts)
	_show_marks(r.spots)
	if r.ashore[0] + r.ashore[1] > 0:
		_say_ashore(r.ashore, "along the line")
	elif r.moved == 0:
		_say("They can't go there.")


func _show_marks(spots: Array) -> void:
	_marks = spots
	_marks_t = 4.0


func cmd_ashore() -> void:
	## Send ashore what's selected and still aboard, to the landing zone
	var ids: Array = []
	for i in selected:
		if _aboard_ship(i):
			ids.append(i)
	if ids.is_empty():
		_say("Select troops or vehicles still aboard (on the unit cards) to send them ashore.")
		return
	if campaign.lz.x == INF:
		_say("Right-click on land where they should go ashore (or set a landing zone).")
		return
	var r: Array = campaign.send_ashore(ids)
	_say_ashore(r, "the landing zone")


func _say_ashore(r: Array, where: String) -> void:
	var parts: Array = []
	if r[0] > 0:
		parts.append("%d vehicles by landing craft" % r[0])
	if r[1] > 0:
		parts.append("%d squads by helicopter" % r[1])
	_say("Going ashore to %s: %s." % [where, " and ".join(parts)])


func _set_origin(ox: float, oz: float) -> void:
	var dx := ox - origin_x
	var dz := oz - origin_z
	origin_x = ox
	origin_z = oz
	if naval != null:
		naval.set_origin(dx, dz)
	tiles.set_origin(ox, oz)
	map.set_origin(ox, oz)
	if fx != null:
		fx.set_origin(ox, oz)
	TexasWaterLook.set_origin(ox, oz)
	_water.position = Vector3(0.0, 0.0, 0.0)


func _ground(x: float, z: float) -> float:
	return TexasGeo.height_cached(x, z, _height_cache)


func _apply_camera() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(PITCH), _yaw, 0.0))
	var gy := _ground(focus_x, focus_z) if size < TACTICAL_SIZE else 0.0
	var dist := maxf(2000.0, size * 1.5)
	var target := Vector3(focus_x - origin_x, gy, focus_z - origin_z)
	camera.size = size
	camera.far = dist * 2.0 + size * 2.0
	camera.global_transform = Transform3D(b, target + b.z * dist)
	_water.position = Vector3(target.x, 0.0, target.z)


# --- 3D units near the camera ------------------------------------------------------------------

func _pick_proxies(tactical: bool) -> void:
	## Which units get a 3D model: the nearest ones in view, when zoomed in. Aircraft aboard a
	## ship are shown parked on its deck; anyone inside a vehicle or landing craft isn't shown.
	var keep := {}
	_deck_slot.clear()
	if tactical:
		var r := size * 1.3
		var r2 := r * r
		var near: Array = []
		var slots := {}
		for i in sim.count:
			if sim.alive[i] == 0:
				continue
			var host := sim.aboard[i]
			if host >= 0:
				if not (sim.is_air(i) and TexasUnits.is_ship(sim.utype[host])):
					continue
			var dx: float = sim.x[i] - focus_x
			var dz: float = sim.z[i] - focus_z
			var d2 := dx * dx + dz * dz
			if d2 < r2:
				if host >= 0:
					var k: int = slots.get(host, 0)
					if k >= 16:
						continue
					slots[host] = k + 1
					_deck_slot[i] = k
				near.append([d2, i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in mini(near.size(), MAX_PROXIES):
			keep[near[k][1]] = true
	for i in _proxies.keys():
		if not keep.has(i):
			_release(i)
	for i in keep:
		if not _proxies.has(i):
			_proxies[i] = _take(i)


func _proxy_key(i: int) -> String:
	return "%d_%d" % [sim.side[i], sim.utype[i]]


func _take(i: int) -> Node3D:
	var key := _proxy_key(i)
	var pool: Array = _pool.get(key, [])
	var n: Node3D
	if not pool.is_empty():
		n = pool.pop_back()
	else:
		n = _make_proxy(sim.side[i], sim.utype[i])
		add_child(n)
	n.visible = true
	# each ship wears its own hull number
	if n.has_meta("ship") and campaign != null:
		var num := {"amphib": "3", "destroyer0": "57", "destroyer1": "58", "cruiser": "60"}
		for role in campaign.ships:
			if campaign.ships[role] == i and num.has(role):
				ShipModels.hull_number(n.get_meta("ship"), num[role])
	return n


func _release(i: int) -> void:
	var n: Node3D = _proxies[i]
	_proxies.erase(i)
	n.visible = false
	TexasWaterLook.set_wake(n.get_node_or_null("Wake"), false)
	var key := _proxy_key(i)
	if not _pool.has(key):
		_pool[key] = []
	(_pool[key] as Array).append(n)


func _make_proxy(s: int, t: int) -> Node3D:
	var root := Node3D.new()
	var blue := s == 0
	var id: String = TexasUnits.TYPES[t].id
	match id:
		"rifle":
			# A squad of 4 in a loose diamond
			var col := Color(0.30, 0.55, 0.90) if blue else Color(0.75, 0.22, 0.20)
			for off in [Vector3(0, 0, -2.0), Vector3(-2.0, 0, 0), Vector3(2.0, 0, 0), Vector3(0, 0, 2.0)]:
				var sm := SoldierModel.new()
				sm.position = off
				root.add_child(sm)
				sm.build(col, not blue, "rifle", off.z < 0.0)
				sm.allow_kneel = false
		"humvee":
			root.add_child(VehicleModel.humvee())
		"stryker":
			root.add_child(VehicleModel.stryker())
		"bradley":
			root.add_child(VehicleModel.bradley())
		"lmtv":
			root.add_child(VehicleModel.lmtv())
		"tank":
			root.add_child(VehicleModel.red_tank())
		"aa":
			root.add_child(VehicleModel.red_aa())
		"black_hawk":
			root.add_child(HeliModels.black_hawk())
		"chinook":
			root.add_child(HeliModels.chinook())
		"little_bird":
			root.add_child(VehicleModel.mh6_smooth())
		"apache":
			root.add_child(HeliModels.apache())
		"hornet", "a10":
			root.add_child(HeliModels.a10())
		_:
			var ship := ShipModels.by_type(id)
			if ship != null:
				root.add_child(ship)
				root.set_meta("ship", ship)
	# Ships and hovercraft leave foam behind them on the water
	if TexasFormation.HULL.has(id) or id == "lcac":
		var hull: Vector2 = TexasFormation.HULL.get(id, Vector2(27, 14))
		root.add_child(TexasWaterLook.wake(hull.x, hull.y))
	return root


func _move_proxies(delta: float) -> void:
	for i in _proxies:
		var n: Node3D = _proxies[i]
		var w := unit_pos(i)
		n.position = Vector3(w.x - origin_x, w.y, w.z - origin_z)
		var k: int = sim.kind[i]
		var h: float = sim.heading[i]
		if _deck_slot.has(i):
			h = sim.heading[sim.aboard[i]] + PI * 0.5
		n.rotation.y = lerp_angle(n.rotation.y, h, 1.0 - exp(-8.0 * delta))
		# Aircraft lean into their turns
		var lean: float = sim.bank[i] if sim.airborne(i) else 0.0
		n.rotation.z = lerpf(n.rotation.z, lean, 1.0 - exp(-4.0 * delta))
		var wk := n.get_node_or_null("Wake")
		if wk != null:
			TexasWaterLook.set_wake(wk, sim.is_moving(i) and SPEEDS[speed_i] > 0.0 and sim.aboard[i] == -1
				and TexasSea.hover_water(Vector2(sim.x[i], sim.z[i])), SPEEDS[speed_i])
		if k == TexasSim.Kind.INFANTRY:
			var moving: bool = sim.is_moving(i) and SPEEDS[speed_i] > 0.0
			for c in n.get_children():
				(c as SoldierModel).animate(delta, moving)
		elif k == TexasSim.Kind.HELI or k == TexasSim.Kind.JET:
			var vm := n.get_child(0) as VehicleModel
			if vm != null:
				vm.rotor_factor = 9.0 if sim.airborne(i) else 0.0


func unit_pos(i: int) -> Vector3:
	## Where a unit is in world metres, with its height: ships on the water, aircraft in the air
	## (or parked on a deck), everything else on the ground
	var alpha := clampf(_acc / maxf(_step, 0.001), 0.0, 1.0) if SPEEDS[speed_i] > 0.0 else 1.0
	var host := sim.aboard[i]
	if host >= 0 and _deck_slot.has(i):
		var ht: String = TexasUnits.TYPES[sim.utype[host]].id
		var k: int = _deck_slot[i]
		var off: Vector3
		if ht == "carrier":
			off = Vector3(-14.0 if k % 2 == 0 else 6.0, 0.0, -120.0 + (k / 2) * 30.0)
		elif ht == "amphib":
			off = Vector3(-6.0, 0.0, -95.0 + k * 24.0)
		else:
			off = Vector3(0.0, 0.0, 66.0)
		var hx: float = lerpf(sim.px[host], sim.x[host], alpha)
		var hz: float = lerpf(sim.pz[host], sim.z[host], alpha)
		var o := Basis(Vector3.UP, sim.heading[host]) * off
		return Vector3(hx + o.x, ShipModels.deck_height(ht), hz + o.z)
	var wx: float = lerpf(sim.px[i], sim.x[i], alpha)
	var wz: float = lerpf(sim.pz[i], sim.z[i], alpha)
	var k: int = sim.kind[i]
	var g := _ground(wx, wz)
	if k == TexasSim.Kind.SHIP:
		return Vector3(wx, 0.0, wz)
	if TexasUnits.move[sim.utype[i]] == TexasUnits.Move.HOVER:
		return Vector3(wx, maxf(g, 0.0), wz)
	if sim.airborne(i):
		var alt := 45.0 if k == TexasSim.Kind.HELI else 160.0
		return Vector3(wx, maxf(g, 0.0) + alt, wz)
	return Vector3(wx, maxf(g, 0.0) if k == TexasSim.Kind.HELI or k == TexasSim.Kind.JET else g, wz)


# --- Rings under units, places to take, the landing zone ---------------------------------------

func _update_rings() -> void:
	var want := {}
	for i in _proxies:
		if sim.alive[i] == 1:
			want[i] = true
	for i in _rings.keys():
		if not want.has(i):
			var r: MeshInstance3D = _rings[i]
			r.visible = false
			_ring_pool.append(r)
			_rings.erase(i)
	for i in want:
		var r: MeshInstance3D
		if _rings.has(i):
			r = _rings[i]
		else:
			r = _ring_pool.pop_back() if not _ring_pool.is_empty() else null
			if r == null:
				r = MeshInstance3D.new()
				r.mesh = _ring_mesh
				r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(r)
			r.visible = true
			_rings[i] = r
		var key: String = "sel" if map.selected.has(i) else ("blue" if sim.side[i] == 0 else "red")
		if r.get_meta("key", "") != key or r.get_meta("unit", -1) != i:
			r.material_override = _ring_mat[key]
			var sz: float = RING_SIZE.get(TexasUnits.TYPES[sim.utype[i]].id, 8.0)
			r.scale = Vector3(sz, 1.0, sz)
			r.set_meta("key", key)
			r.set_meta("unit", i)
		var n: Node3D = _proxies[i]
		var y := n.position.y + 0.6
		if sim.kind[i] == TexasSim.Kind.SHIP:
			y = 1.0
		r.position = Vector3(n.position.x, y, n.position.z)


func _build_markers() -> void:
	for z in campaign.zones:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.985
		tm.outer_radius = 1.0
		tm.rings = 64
		tm.ring_segments = 4
		ring.mesh = tm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_zone_nodes.append([ring])
	_lz_node = Node3D.new()
	var lr := MeshInstance3D.new()
	lr.mesh = _ring_mesh
	lr.material_override = _ring_mat.lz
	lr.scale = Vector3(160, 1, 160)
	_lz_node.add_child(lr)
	_lz_node.visible = false
	add_child(_lz_node)


func _build_city_labels() -> void:
	## Town and city names (drawn by TexasNames, flat on the screen)
	for c in TexasGeo.cities:
		var tier: int = c[3]
		if tier >= 2:
			var p := TexasGeo.city_xz(c)
			_city_labels.append([p.x, p.y, tier, c[0]])
	_city_labels.sort_custom(func(a, b): return a[2] > b[2])


func _update_city_labels(tactical: bool) -> void:
	## Every name to show this frame, most important first: the objectives, the landing zone,
	## then cities by size (fewer the further out), then ports and airfields close up
	var items: Array = []
	if not show_names:
		_names.items = items
		return
	if campaign != null:
		for z in campaign.zones:
			if z.get("objective", false):
				var st := " (%d%%)" % int(z.progress * 100.0) if z.progress > 0.0 else ""
				_add_name(items, z.x, z.z, tactical, "★ %s%s" % [z.name, st], 15, Color(0.6, 0.82, 1.0) if z.owner == 0 else Color(1.0, 0.62, 0.55))
		if campaign.lz.x != INF:
			_add_name(items, campaign.lz.x, campaign.lz.y, tactical, "Landing zone", 14, Color(1.0, 0.85, 0.25))
	var min_tier := 5
	if size < 30000.0:
		min_tier = 2
	elif size < 90000.0:
		min_tier = 3
	elif size < 220000.0:
		min_tier = 4
	for e in _city_labels:
		if int(e[2]) < min_tier:
			continue
		_add_name(items, e[0], e[1], tactical, e[3], [0, 0, 12, 13, 15, 17][int(e[2])], Color(1.0, 0.97, 0.9))
	if campaign != null and size < 30000.0:
		for z in campaign.zones:
			if z.kind != "town" and not z.get("objective", false):
				_add_name(items, z.x, z.z, tactical, z.name, 12, Color(0.6, 0.82, 1.0) if z.owner == 0 else Color(1.0, 0.68, 0.62))
	_names.items = items


func _add_name(items: Array, x: float, z: float, tactical: bool, text: String, fs: int, col: Color) -> void:
	var y := maxf(_ground(x, z), 0.0) if tactical else 0.0
	var local := Vector3(x - origin_x, y, z - origin_z)
	if camera.is_position_behind(local):
		return
	items.append([camera.unproject_position(local), text, fs, col])


func _update_markers() -> void:
	var tactical := size < TACTICAL_SIZE
	for k in campaign.zones.size():
		var z: Dictionary = campaign.zones[k]
		var ring: MeshInstance3D = _zone_nodes[k][0]
		var gy := _ground(z.x, z.z) if tactical else 0.0
		ring.position = Vector3(z.x - origin_x, maxf(gy, 0.0) + 3.0, z.z - origin_z)
		ring.scale = Vector3(z.r, 1.0 if tactical else 40.0, z.r)
		ring.material_override = _ring_mat["zone_blue" if z.owner == 0 else "zone_red"]
	if campaign.lz.x != INF:
		_lz_node.visible = true
		var gy := _ground(campaign.lz.x, campaign.lz.y) if tactical else 0.0
		_lz_node.position = Vector3(campaign.lz.x - origin_x, maxf(gy, 0.0) + 4.0, campaign.lz.y - origin_z)
		_lz_node.scale = Vector3.ONE if tactical else Vector3(8, 1, 8)


# --- HUD ----------------------------------------------------------------------------------------

func clock_text() -> String:
	var h := START_HOUR + sim.time / 3600.0
	var day := floori(h / 24.0)
	var hh := fmod(h, 24.0)
	return "Day %d (from %s)  %02d:%02d" % [day + 1, START_DATE, floori(hh), floori(fmod(hh * 60.0, 60.0))]


func _update_hud(delta: float) -> void:
	var spd: float = SPEEDS[speed_i]
	var blue := sim.live_count(0) if Engine.get_process_frames() % 15 == 0 else int(_hud.get_meta("blue", 0))
	var red := sim.live_count(1) if Engine.get_process_frames() % 15 == 0 else int(_hud.get_meta("red", 0))
	_hud.set_meta("blue", blue)
	_hud.set_meta("red", red)
	var ll := TexasGeo.to_latlon(focus_x, focus_z)
	_hud.text = "%s   ·   %s\nYou %s units   ·   Red %s units   ·   destroyed: Red %d, yours %d" % [
		clock_text(), "PAUSED" if spd <= 0.0 else "%dx speed" % int(spd), Fob._thousands(blue), Fob._thousands(red),
		sim.kills[0], sim.kills[1]]
	var fps := Engine.get_frames_per_second()
	_hud2.text = "view %s across · %.2f N %.2f W · FPS %d · sim %.1f ms · tiles %d (+%d building) · 3D units %d" % [
		_dist_text(size), ll.x, -ll.y, fps, sim.tick_ms, tiles.tiles.size(), tiles.pending_count(), _proxies.size()]
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0 and ui == null


func _dist_text(m: float) -> String:
	## Real-world distance (the map is 1:3)
	var real := m * TexasGeo.SCALE
	return "%.1f km" % (real / 1000.0) if real >= 1000.0 else "%d m" % int(real)


# --- Save and load -------------------------------------------------------------------------------

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_say("Couldn't save: %s" % error_string(FileAccess.get_open_error()))
		return false
	var d := {"sim": sim.to_dict(), "focus": [focus_x, focus_z], "size": _target_size, "speed": speed_i, "yaw": _yaw}
	if campaign != null:
		d["campaign"] = campaign.to_dict()
	f.store_var(d)
	f.close()
	_say("Saved (%s)" % clock_text())
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		_say("No saved game yet (F5 saves)")
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = f.get_var()
	f.close()
	if not (d is Dictionary) or not d.has("sim"):
		_say("That save file couldn't be read")
		return false
	for i in _proxies.keys():
		_release(i)
	if campaign != null and not d.has("campaign"):
		_say("That save is from the test world, not this campaign")
		return false
	sim.from_dict(d.sim)
	if campaign != null:
		campaign.from_dict(d.campaign)
		selected.clear()
		fx.clear()
	focus_x = d.focus[0]
	focus_z = d.focus[1]
	_target_size = d.size
	size = d.size
	speed_i = d.speed
	_yaw = d.yaw
	_acc = 0.0
	_say("Loaded (%s)" % clock_text())
	return true


# --- The Phase 2 test ------------------------------------------------------------------------------

func _shot(name: String) -> void:
	if _lab_prefix == "":
		return
	var path := _lab_prefix.replace(".png", "_%s.png" % name)
	get_viewport().get_texture().get_image().save_png(path)
	print("TEXAS: saved %s" % path)


func _stats(arr: Array) -> String:
	if arr.is_empty():
		return "n/a"
	var s := arr.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	return "avg %.1f, 95%% %.1f, max %.1f ms" % [total / s.size(), s[int(s.size() * 0.95)], s[-1]]


func _lab_tick(delta: float) -> void:
	_lab_t += delta
	var houston := TexasGeo.city_xz(TexasGeo.city("Houston"))
	var dallas := TexasGeo.city_xz(TexasGeo.city("Dallas"))
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 1.0:
				look_at_world(0.0, 0.0, 430000.0)
				print("TEXAS: %d units (%d yours, %d Red), road network %d nodes / %d stretches, map ready at %.1f s" % [sim.count, sim.live_count(0), sim.live_count(1), roads.nodes.size(), roads.segments.size(), _lab_t])
				if TexasGeo.built:
					var m: Dictionary = TexasData.meta
					print("TEXAS: real map (built %s): %d towns, %d airfields, %d ports, %d road junctions, %d buildings" % [m.built, TexasGeo.cities.size(), m.airfields.size(), m.ports.size(), roads.junctions, m.counts.buildings_kept])
				print("TEXAS: start-up: map data %.0f ms, roads %.0f ms, placing units and their routes %.0f ms" % [_startup_ms.geo, _startup_ms.roads, _startup_ms.seed])
				_lab_step = 1
				_lab_t = 0.0
		1:
			if _lab_t > 1.0:
				_shot("state")
				speed_i = 4                 # 64x
				sim_ms_log.clear()
				_lab_data["moving0"] = sim.moving_count()
				_lab_data["clock0"] = sim.time
				_lab_step = 2
				_lab_t = 0.0
		2:
			if _lab_t > 8.0:
				print("TEXAS: 8 s at 64x: game time +%.0f min, sim tick %s (%d units, %d moving)" % [(sim.time - _lab_data.clock0) / 60.0, _stats(sim_ms_log), sim.count, sim.moving_count()])
				print("TEXAS: fighting so far: Red lost %d, you lost %d" % [sim.kills[0], sim.kills[1]])
				speed_i = 5                 # 256x
				sim_ms_log.clear()
				_lab_data["clock1"] = sim.time
				_lab_step = 3
				_lab_t = 0.0
		3:
			if _lab_t > 6.0:
				print("TEXAS: 6 s at 256x: game time +%.0f min, sim tick %s" % [(sim.time - _lab_data.clock1) / 60.0, _stats(sim_ms_log)])
				speed_i = 1
				look_at_world(houston.x, houston.y, 60000.0)
				_lab_step = 4
				_lab_t = 0.0
		4:
			if _lab_t > 1.5:
				_shot("houston_region")
				look_at_world(houston.x + 1200.0, houston.y - 800.0, 2500.0)
				_lab_data["t_stream"] = Time.get_ticks_msec()
				_lab_step = 5
				_lab_t = 0.0
		5:
			if tiles.pending_count() == 0 and tiles.tiles.size() > 4 and not _lab_data.has("streamed"):
				_lab_data["streamed"] = true
				print("TEXAS: Houston close-up: %d tiles loaded in %.1f s (avg %.0f ms each on a worker thread), %d 3D units" % [tiles.tiles.size(), (Time.get_ticks_msec() - _lab_data.t_stream) / 1000.0, tiles.build_ms_total / maxf(1, tiles.built_count), _proxies.size()])
			if _lab_t > 6.0:
				_shot("houston_close")
				# Follow one of your convoys driving in from the coast, close enough to see it
				var best := -1
				var best_d := INF
				for i in sim.count:
					if sim.side[i] == 0 and sim.alive[i] == 1 and sim.is_moving(i) and sim.kind[i] in [TexasSim.Kind.WHEELED, TexasSim.Kind.ARMOR]:
						var d := Vector2(sim.x[i], sim.z[i]).distance_to(houston)
						if d < best_d:
							best_d = d
							best = i
				_lab_data["follow"] = best
				_lab_step = 55
				_lab_t = 0.0
		55:
			var f: int = _lab_data.follow
			if f >= 0:
				look_at_world(lerpf(sim.px[f], sim.x[f], clampf(_acc / _step, 0.0, 1.0)), lerpf(sim.pz[f], sim.z[f], clampf(_acc / _step, 0.0, 1.0)), 220.0)
			if _lab_t > 5.0:
				print("TEXAS: following unit %d (%s) on the road, %d 3D units around it" % [f, TexasSim.KIND_NAMES[sim.kind[f]] if f >= 0 else "none", _proxies.size()])
				_shot("convoy")
				look_at_world(houston.x, houston.y, 6000.0)
				_lab_step = 6
				_lab_t = 0.0
		6:
			if _lab_t > 3.0:
				_shot("houston_mid")
				# Fly the camera west along I-10 for 20 s at 1.2 km/s, streaming as it goes
				frame_ms_log.clear()
				script_ms_log.clear()
				_lab_data["fly0"] = Vector2(focus_x, focus_z)
				_lab_data["shifts"] = 0
				_lab_data["ox"] = origin_x
				_lab_step = 7
				_lab_t = 0.0
		7:
			focus_x -= 1200.0 * delta
			focus_z += 150.0 * delta
			if origin_x != _lab_data.ox:
				_lab_data.shifts += 1
				_lab_data.ox = origin_x
			if _lab_t > 20.0:
				print("TEXAS: flew %.0f km west at 1.2 km/s: %d origin shifts, %d tiles loaded now (%d built so far)" % [(_lab_data.fly0 as Vector2).distance_to(Vector2(focus_x, focus_z)) / 1000.0, _lab_data.shifts, tiles.tiles.size(), tiles.built_count])
				print("TEXAS: while flying: frame %s | game logic on the main thread %s" % [_stats(frame_ms_log), _stats(script_ms_log)])
				print("TEXAS: precision far from the centre: origin at (%.0f, %.0f) km, camera render offset %.1f m" % [origin_x / 1000.0, origin_z / 1000.0, Vector2(focus_x - origin_x, focus_z - origin_z).length()])
				_shot("flying")
				look_at_world(dallas.x, dallas.y, 3000.0)
				_lab_step = 8
				_lab_t = 0.0
		8:
			if _lab_t > 6.0:
				_shot("dallas")
				var before := sim.checksum()
				var t_before := sim.time
				save_game()
				speed_i = 4
				_lab_data["sum"] = before
				_lab_data["t"] = t_before
				_lab_step = 9
				_lab_t = 0.0
		9:
			if _lab_t > 2.0:
				var moved := sim.checksum()
				load_game()
				print("TEXAS: save/load: checksum saved %.3f, after 2 s at 64x %.3f, after load %.3f (match %s), clock back to %s" % [_lab_data.sum, moved, sim.checksum(), is_equal_approx(_lab_data.sum, sim.checksum()), clock_text()])
				_lab_step = 10
				_lab_t = 0.0
		10:
			if _lab_t > 1.0:
				if not TexasGeo.built:
					print("TEXAS: done")
					get_tree().quit()
					return
				var g := TexasGeo.city_xz(TexasGeo.city("Galveston"))
				look_at_world(g.x, g.y, 4000.0)
				_lab_step = 11
				_lab_t = 0.0
		11:
			if _lab_t > 6.0:
				_shot("galveston")
				var best: Dictionary = {}
				for a in TexasData.meta.airfields:
					if best.is_empty() or (a.military and not best.military) or (a.military == best.military and a.longest_runway > best.longest_runway):
						best = a
				if not best.is_empty():
					print("TEXAS: airfield: %s (%s), longest runway %d m, %d runways, military %s" % [best.name, best.icao, best.longest_runway, best.runways, best.military])
					look_at_world(best.x, best.z, 3500.0)
				_lab_step = 12
				_lab_t = 0.0
		12:
			if _lab_t > 6.0:
				_shot("airfield")
				print("TEXAS: done")
				get_tree().quit()


# --- The Phase 4 play-through test --------------------------------------------------------------

func _blue_ashore() -> Array:
	var out: Array = []
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 0 and sim.aboard[i] == -1 and TexasUnits.is_ground(sim.utype[i]):
			out.append(i)
	return out


func _zone_pos(k: int) -> Vector2:
	return Vector2(campaign.zones[k].x, campaign.zones[k].z)


func _lab_spend() -> void:
	var plan := ["bradley", "rifle", "rifle", "tank", "stryker", "apache", "rifle", "bradley", "aa"]
	var k: int = _lab_data.get("plan_k", 0)
	var tries := 0
	while tries < plan.size():
		var t := TexasUnits.id(plan[k % plan.size()])
		if campaign.add_order(t):
			k += 1
			tries = 0
		else:
			tries += 1
			if campaign.points < 4:
				break
			k += 1
	_lab_data["plan_k"] = k


func _lab_status() -> String:
	var owned: Array = []
	for z in campaign.zones:
		if z.owner == 0:
			owned.append(z.name)
	var red_slice := 0
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 1 and campaign.slice.has_point(Vector2(sim.x[i], sim.z[i])):
			red_slice += 1
	var hz: Dictionary = campaign.zones[campaign.zone_named("Houston")]
	return "%s: yours ashore %d, Red in the area %d, Red lost %d, you lost %d, downtown Houston: yours %d / Red %d; you hold %s" % [clock_text(), _blue_ashore().size(),
		red_slice, sim.kills[0], sim.kills[1], hz.get("blue_here", 0), hz.get("red_here", 0), ", ".join(owned) if not owned.is_empty() else "nothing yet"]


func _water_audit() -> void:
	## (lab) Ground units standing in water and hovercraft driven inland, as the player would see them
	var wa: Dictionary = _lab_data.get("wa", {"samples": 0, "sea": 0, "inland": 0, "ex": {}, "lcac_in": 0.0, "lcac_ex": ""})
	wa.samples += 1
	for i in sim.count:
		if sim.alive[i] == 0 or sim.aboard[i] != -1:
			continue
		var t: int = sim.utype[i]
		var p := Vector2(sim.x[i], sim.z[i])
		if not campaign.slice.has_point(p):
			continue
		if TexasUnits.move[t] == TexasUnits.Move.GROUND:
			var dry := not TexasWater.any(p)
			var s_ := not dry and TexasWater.sea(p)
			var l_ := not dry and not s_
			if s_ or l_:
				wa[("sea" if s_ else "inland")] += 1
				var why := "%s %s side%d state%d leg%d/%d" % ["sea" if s_ else "inland", TexasUnits.TYPES[t].id, sim.side[i], sim.state[i], sim.leg[i], (sim.routes[i] as PackedInt32Array).size()]
				var ex: Dictionary = wa.ex
				if not ex.has(i):
					ex[i] = "%s at %s" % [why, TexasGeo.to_latlon(p.x, p.y)]
					var cat := "side%d %s %s" % [sim.side[i], "moving" if sim.state[i] == TexasSim.State.MOVING else "still", "sea" if s_ else "inland"]
					var cats: Dictionary = wa.get("cats", {})
					cats[cat] = cats.get(cat, 0) + 1
					wa["cats"] = cats
		elif TexasUnits.TYPES[t].id == "lcac" and not TexasWater.sea(p):
			var d := 0.0
			for r in [20.0, 40.0, 60.0, 90.0, 130.0, 180.0, 250.0, 350.0, 500.0]:
				d = r
				var found := false
				for k in 16:
					if TexasWater.sea(p + Vector2.from_angle(TAU * k / 16.0) * r):
						found = true
						break
				if found:
					break
			if d > wa.lcac_in:
				wa.lcac_in = d
				wa.lcac_ex = "hovercraft %d about %.0f m from the water (state %d) at %s" % [i, d, sim.state[i], TexasGeo.to_latlon(p.x, p.y)]
	_lab_data["wa"] = wa


func _lab_mop_up() -> void:
	## (lab) What a player does now that units only move when told: in a place both sides are
	## in, send each idle unit of yours at the nearest defender
	var c := campaign
	for z in c.zones:
		if z.owner == 0:
			continue
		var zc := Vector2(z.x, z.z)
		var r2: float = z.r * z.r
		var mine: Array = []
		var theirs: Array = []
		for i in sim.count:
			if sim.alive[i] == 0 or sim.aboard[i] != -1 or TexasUnits.move[sim.utype[i]] != TexasUnits.Move.GROUND:
				continue
			if Vector2(sim.x[i], sim.z[i]).distance_squared_to(zc) < r2:
				(mine if sim.side[i] == 0 else theirs).append(i)
		if mine.is_empty() or theirs.is_empty():
			continue
		for i in mine:
			if sim.state[i] != TexasSim.State.IDLE:
				continue
			var best := -1
			var bd := INF
			for j in theirs:
				var d := Vector2(sim.x[j] - sim.x[i], sim.z[j] - sim.z[i]).length_squared()
				if d < bd:
					bd = d
					best = j
			if best >= 0 and bd > 150.0 * 150.0:
				c.command_move([i], Vector2(sim.x[best], sim.z[best]))


func _galveston_lab_tick(delta: float) -> void:
	_lab_t += delta
	var c := campaign
	if _lab_step >= 2:
		var mop: float = _lab_data.get("mop", 0.0)
		if sim.time - mop > 60.0:
			_lab_data["mop"] = sim.time
			_lab_mop_up()
	if _lab_step >= 2 and Engine.get_process_frames() % 10 == 0:
		_water_audit()
	var port := -1
	var field := -1
	for k in c.zones.size():
		if c.zones[k].objective and c.zones[k].kind == "port":
			port = k
		if c.zones[k].objective and c.zones[k].kind == "airfield":
			field = k
	var hou := c.zone_named("Houston")
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0 and tiles.pending_count() == 0:
				var names: Array = []
				for z in c.zones:
					names.append("%s%s (%s)" % ["*" if z.objective else "", z.name, z.kind])
				print("GALV: start-up %.0f ms; %d places to take: %s" % [_startup_ms.seed, c.zones.size(), ", ".join(names)])
				print("GALV: " + _lab_status())
				_shot("fleet")
				_lab_step = 1
				_lab_t = 0.0
		1:
			var g := TexasGeo.city_xz(TexasGeo.city("Galveston"))
			c.set_lz(g)
			print("GALV: vehicles queued %d, squads queued %d" % [c.send_vehicles_ashore(), c.send_troops_ashore()])
			var ap: Array = []
			for q in 2:
				var i := c.launch(TexasUnits.id("apache"))
				if i >= 0:
					ap.append(i)
			c.command_move(ap, g)
			for q in 2:
				c.launch(TexasUnits.id("hornet"))
			_lab_data["t0"] = sim.time
			_lab_data["next_status"] = sim.time + 3600.0
			speed_i = 3
			_lab_step = 2
			_lab_t = 0.0
		2:
			if _lab_data.has("follow") and not _lab_data.has("landing_shot_done"):
				var f: int = _lab_data.follow
				var fp := unit_pos(f)
				focus_x = fp.x
				focus_z = fp.z
			if not _lab_data.has("landing_shot") and sim.time - _lab_data.t0 > 150.0:
				# Find a landing craft on its way in and look at it
				for i in c.ferries:
					if TexasUnits.TYPES[sim.utype[i]].id == "lcac" and c.ferries[i].stage == "out":
						look_at_world(sim.x[i], sim.z[i], 260.0)
						_lab_data["follow"] = i
						break
				_lab_data["landing_shot"] = _lab_t
			if _lab_data.has("landing_shot") and not _lab_data.has("landing_shot_done") and _lab_t - _lab_data.landing_shot > 4.0:
				_shot("landing_craft")
				look_at_world(c.lz.x, c.lz.y, 2600.0)
				_lab_data["landing_shot_done"] = _lab_t
			if _lab_data.has("landing_shot_done") and not _lab_data.has("beach_shot") and _lab_t - _lab_data.landing_shot_done > 4.0:
				_shot("beachhead")
				_lab_data["beach_shot"] = true
				speed_i = 4
			var done: bool = c.vehicle_queue.is_empty() and c.troop_queue.is_empty() and c.ferries.is_empty() and sim.time - _lab_data.t0 > 300.0
			if done or sim.time - _lab_data.t0 > 3.0 * 3600.0:
				print("GALV: landing done in %.0f min (game time): %d units ashore" % [(sim.time - _lab_data.t0) / 60.0, _blue_ashore().size()])
				print("GALV: " + _lab_status())
				_lab_step = 3
		3:
			var ground := _blue_ashore()
			var a: Array = []
			var b: Array = []
			for k in ground.size():
				(a if k % 2 == 0 else b).append(ground[k])
			if port >= 0:
				c.command_move(a, _zone_pos(port))
			if field >= 0:
				c.command_move(b, _zone_pos(field))
			_lab_spend()
			speed_i = 5
			_lab_data["t1"] = sim.time
			_lab_data["reissue"] = sim.time + 1200.0
			_lab_step = 4
		4:
			if sim.time > _lab_data.next_status:
				_lab_data.next_status += 3600.0
				print("GALV: " + _lab_status())
			if sim.time > _lab_data.reissue:
				_lab_data.reissue = sim.time + 1200.0
				_lab_spend()
				var goal := port if port >= 0 and c.zones[port].owner != 0 else field
				var idle: Array = []
				for i in _blue_ashore():
					if not sim.is_moving(i):
						idle.append(i)
				if goal >= 0:
					c.command_move(idle, _zone_pos(goal))
				c.send_troops_ashore()
				c.send_vehicles_ashore()
			var both: bool = (port < 0 or c.zones[port].owner == 0) and (field < 0 or c.zones[field].owner == 0)
			if both or sim.time - _lab_data.t1 > 6.0 * 3600.0:
				print("GALV: Galveston port %s, airfield %s after %.0f min" % [c.zones[port].owner == 0 if port >= 0 else "n/a", c.zones[field].owner == 0 if field >= 0 else "n/a", (sim.time - _lab_data.t1) / 60.0])
				# The assault ship comes into the harbour to unload at the dock from now on
				var amphib: int = c.ships.amphib
				if port >= 0 and sim.alive[amphib] == 1:
					var ok := sim.order_move(amphib, _zone_pos(port))
					print("GALV: assault ship heading for the dock: %s (%d waypoints)" % [ok, (sim.wps[amphib] as PackedVector2Array).size()])
				c.set_lz(_zone_pos(port))
				_lab_data["t2"] = sim.time
				_lab_data["reissue"] = sim.time
				_lab_step = 5
		5:
			if sim.time > _lab_data.next_status:
				_lab_data.next_status += 3600.0
				print("GALV: " + _lab_status())
			if sim.time > _lab_data.reissue:
				_lab_data.reissue = sim.time + 900.0
				_lab_spend()
				c.send_troops_ashore()
				c.send_vehicles_ashore()
				# Gather at a staging point, then go in together: a few at a time just get picked off
				var stage: Vector2 = _lab_data.get("stage", Vector2.ZERO)
				if stage == Vector2.ZERO:
					# Gather on ground you hold: the edge of Galveston towards the causeway
					stage = _zone_pos(port).lerp(_zone_pos(hou), 0.08)
					_lab_data["stage"] = stage
					_lab_data["attacking"] = false
				var at_stage: Array = []
				var idle: Array = []
				var hold := 6
				for i in _blue_ashore():
					var p := Vector2(sim.x[i], sim.z[i])
					if hold > 0 and port >= 0 and p.distance_to(_zone_pos(port)) < 1000.0 and not sim.is_moving(i):
						hold -= 1
						continue
					if p.distance_to(stage) < 4000.0 and not sim.is_moving(i):
						at_stage.append(i)
					elif not sim.is_moving(i) and p.distance_to(_zone_pos(hou)) > 6000.0:
						idle.append(i)
				c.command_move(idle, stage)
				var push_n := 40
				if at_stage.size() >= push_n:
					c.command_move(at_stage, _zone_pos(hou))
					var ap: Array = []
					for q in 4:
						var i := c.launch(TexasUnits.id("apache"))
						if i >= 0:
							ap.append(i)
					c.command_move(ap, _zone_pos(hou))
					print("GALV: attack on Houston with %d units from the staging area (%s)" % [at_stage.size(), clock_text()])
				# Units already in the fight keep pressing on
				var near: Array = []
				for i in _blue_ashore():
					var p := Vector2(sim.x[i], sim.z[i])
					if p.distance_to(_zone_pos(hou)) < 12000.0 and not sim.is_moving(i):
						near.append(i)
				c.command_move(near, _zone_pos(hou))
				var bands := [0, 0, 0, 0, 0]
				for i in _blue_ashore():
					var d := Vector2(sim.x[i], sim.z[i]).distance_to(_zone_pos(hou))
					bands[mini(int(d / 10000.0), 4)] += 1
				print("GALV: push: %d gathering, %d at the staging area, %d pressing on; distance to Houston 0-10/10-20/20-30/30-40/40+ km: %s" % [idle.size(), at_stage.size(), near.size(), bands])
			if not _lab_data.has("battle_shot"):
				for i in _blue_ashore():
					if Vector2(sim.x[i], sim.z[i]).distance_to(_zone_pos(hou)) < 9000.0 and sim.state[i] == TexasSim.State.ENGAGED:
						look_at_world(sim.x[i], sim.z[i], 380.0)
						speed_i = 1
						_lab_data["battle_shot"] = _lab_t
						break
			elif _lab_data.battle_shot > 0.0 and _lab_t - _lab_data.battle_shot > 3.0:
				_shot("battle")
				print("GALV: the fight near Houston, close up: %d 3D units, %d shots this round" % [_proxies.size(), sim.shots.size() / 2])
				_lab_data.battle_shot = -1.0
				speed_i = 5
			if c.result != "" or sim.time - _lab_data.t2 > 30.0 * 3600.0:
				print("GALV: result: %s after %.1f hours of game time" % [c.result if c.result != "" else "not decided", sim.time / 3600.0])
				var wa: Dictionary = _lab_data.get("wa", {})
				if not wa.is_empty():
					print("GALV: water: %d looks; ground units seen in the sea %d times, in lakes/rivers %d times; %d different units; hovercraft furthest inland: %s" % [wa.samples, wa.sea, wa.inland, wa.ex.size(), wa.lcac_ex])
					print("GALV: water by kind: %s" % wa.get("cats", {}))
					var n := 0
					for k in wa.ex:
						if n < 14 and (wa.ex[k] as String).contains("side0") or (wa.ex[k] as String).contains("state1"):
							print("GALV:   " + wa.ex[k])
							n += 1
				print("GALV: " + _lab_status())
				var hz := _zone_pos(hou)
				look_at_world(hz.x, hz.y, 5000.0)
				_lab_step = 6
				_lab_t = 0.0
		6:
			if _lab_t > 4.0:
				_shot("end")
				look_at_world(0.0, 0.0, 430000.0)
				size = 120000.0
				_target_size = 120000.0
				var hz := _zone_pos(hou)
				focus_x = hz.x
				focus_z = hz.y + 30000.0
				_lab_step = 7
				_lab_t = 0.0
		7:
			if _lab_t > 2.0:
				_shot("map")
				var before := sim.checksum()
				var res := c.result
				save_game()
				c.result = ""
				speed_i = 4
				_lab_data["sum"] = before
				_lab_data["res"] = res
				_lab_step = 8
				_lab_t = 0.0
		8:
			if _lab_t > 1.5:
				load_game()
				print("GALV: save/load: checksum %.3f -> %.3f (match %s), result back to '%s', %d places held" % [_lab_data.sum, sim.checksum(), is_equal_approx(_lab_data.sum, sim.checksum()), c.result, c.zones.filter(func(z): return z.owner == 0).size()])
				print("GALV: done")
				get_tree().quit()


# --- Input test: click and drag on units like a player would -----------------------------------

var ui_lab := false
var water_lab := false
var org_lab := false
var navy_lab := false
var command_lab := false


func _command_lab_tick(delta: float) -> void:
	## (lab) Choosing what goes ashore, units holding where they're put, and spreading a
	## selection along a drawn line
	_lab_t += delta
	var c := campaign
	var org := c.org
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0:
				# pick 3 Bradleys and 4 rifle squads from the cards while they're still aboard
				var bde: int = org.children(0)[0]
				var inf: int = org.children(bde)[0]
				var brads: Array = []
				for i in org.units_in(org.children(inf)[2]):
					if TexasUnits.TYPES[sim.utype[i]].id == "bradley" and brads.size() < 3:
						brads.append(i)
				var sq: Array = org.units_in(org.children(inf)[0], "ground").slice(0, 4)
				ui.dock.open(org.children(inf)[2])
				ui.dock._select_units(brads + sq, false)
				var spot := TexasSim.nearest_land(TexasGeo.to_xz(29.205, -94.950))
				look_at_world(spot.x, spot.y, 1600.0)
				_lab_data["spot"] = spot
				_lab_data["picked"] = selected.duplicate()
				print("CMD: picked from the cards while aboard: %d selected (%s)" % [selected.size(), ", ".join(selected.map(func(i): return TexasUnits.label(sim.utype[i], 0)))])
				# a Red tank a kilometre off, to see if anyone wanders after it
				for i in sim.count:
					if sim.side[i] == 1 and (Vector2(sim.x[i], sim.z[i]).distance_to(spot) < 12000.0 or sim.is_air(i)):
						sim.alive[i] = 0           # a quiet stretch of beach for the test, no raids
				for z in c.raid_timer:
					c.raid_timer[z] = INF
				c._ai_acc = -1.0e12              # and Red's commander sits this one out
				var red := sim.add_typed(1, TexasUnits.id("rifle"), TexasSim.nearest_land(spot + Vector2(1350, -200)))
				sim.flags[red] |= TexasSim.Flag.GARRISON
				sim.strength[red] = 50.0
				_lab_data["red"] = red
				_lab_step = 1
				_lab_t = 0.0
		1:
			if _lab_t > 0.5:
				var spot: Vector2 = _lab_data.spot
				_right_click(_screen_at(spot))
				var aboard_before := 0
				for i in sim.count:
					if _aboard_ship(i):
						aboard_before += 1
				_lab_data["aboard_before"] = aboard_before
				speed_i = 4
				_lab_step = 2
				_lab_t = 0.0
		2:
			if sim.time > 2400.0:
				speed_i = 0
				var spot: Vector2 = _lab_data.spot
				var picked: Array = _lab_data.picked
				var ashore := 0
				var far := 0.0
				var near := INF
				for i in picked:
					if sim.alive[i] == 1 and sim.aboard[i] == -1:
						ashore += 1
						far = maxf(far, Vector2(sim.x[i], sim.z[i]).distance_to(spot))
						for j in picked:
							if j != i and sim.alive[j] == 1 and sim.aboard[j] == -1:
								near = minf(near, Vector2(sim.x[i] - sim.x[j], sim.z[i] - sim.z[j]).length())
				var others := 0
				var lcac := TexasUnits.id("lcac")
				for i in sim.count:
					if sim.side[i] == 0 and sim.alive[i] == 1 and sim.aboard[i] == -1 and TexasUnits.is_ground(sim.utype[i]) and not (i in picked):
						others += 1
				print("CMD: after 40 min: %d of the %d picked are ashore, furthest %.0f m from the spot, closest two %.0f m apart; others ashore that weren't picked: %d" % [ashore, picked.size(), far, near, others])
				var pos: Dictionary = {}
				for i in picked:
					pos[i] = Vector2(sim.x[i], sim.z[i])
				_lab_data["pos"] = pos
				look_at_world(spot.x, spot.y, 700.0)
				_shot("landed")
				speed_i = 4
				_lab_step = 3
				_lab_t = 0.0
		3:
			if _lab_t > 6.0:
				speed_i = 0
				var moved := 0.0
				var pos: Dictionary = _lab_data.pos
				for i in pos:
					if sim.alive[i] == 1:
						moved = maxf(moved, Vector2(sim.x[i], sim.z[i]).distance_to(pos[i]))
				var red: int = _lab_data.red
				print("CMD: with a Red squad %.0f m away, the furthest any of them moved on their own: %.0f m" % [Vector2(sim.x[red], sim.z[red]).distance_to(_lab_data.spot), moved])
				# draw a line for them: right-drag from one end to the other
				selected = (_lab_data.picked as Array).filter(func(i): return sim.alive[i] == 1 and sim.aboard[i] == -1)
				var spot: Vector2 = _lab_data.spot
				var a := TexasSim.nearest_land(spot + Vector2(-300, 250))
				var b := TexasSim.nearest_land(spot + Vector2(300, 250))
				_drawing = true
				_draw_pts = PackedVector2Array([a, (a + b) * 0.5 + Vector2(0, 60), b])
				_lab_data["line"] = [a, b]
				look_at_world((a.x + b.x) * 0.5, (a.y + b.y) * 0.5 + 120.0, 380.0)
				_lab_step = 4
				_lab_t = 0.0
		4:
			if _lab_t > 0.3:
				_shot("drawing")
				_drawing = false
				_line_order(_draw_pts)
				_draw_pts = PackedVector2Array()
				_lab_step = 5
				_lab_t = 0.0
		5:
			if _lab_t > 0.3 and not _lab_data.has("m"):
				_lab_data["m"] = true
				_shot("ordered")
				speed_i = 4
			if _lab_t > 14.0:
				speed_i = 0
				var spots: Array = _marks
				var errs: Array = []
				for i in selected:
					var best := INF
					for p in spots:
						best = minf(best, Vector2(sim.x[i], sim.z[i]).distance_to(p))
					errs.append(roundi(best))
				var xs: Array = selected.map(func(i): return roundi(sim.x[i]))
				print("CMD: line order: %d units, %d spots, each this far from a spot: %s; x positions in order of the line: %s" % [selected.size(), spots.size(), errs, xs])
				_shot("on_line")
				print("CMD: done")
				get_tree().quit()


func _navy_spawn(type_name: String, at: Vector2) -> int:
	var i := sim.add_typed(1, TexasUnits.id(type_name), at)
	sim.strength[i] = 40.0                  # (tough, so the show goes on)
	sim.flags[i] |= TexasSim.Flag.GARRISON
	return i


func _navy_clear() -> void:
	for i in _lab_data.get("red", []):
		sim.alive[i] = 0
	_lab_data["red"] = []


func _navy_view(i: int, at_size: float, yaw_off := 0.6, ahead := 0.0) -> void:
	var h: float = sim.heading[i]
	var fwd := Vector2(-sin(h), -cos(h))
	look_at_world(sim.x[i] + fwd.x * ahead, sim.z[i] + fwd.y * ahead, at_size)
	_yaw = h + yaw_off


func _navy_lab_tick(delta: float) -> void:
	## (lab) The fleet's weapons up close, fired through the normal fight rounds
	_lab_t += delta
	var c := campaign
	var d0: int = c.ships.destroyer0
	var counts: Dictionary = naval.launches
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0:
				speed_i = 1
				for i in sim.count:
					if sim.side[i] == 1 and Vector2(sim.x[i] - sim.x[d0], sim.z[i] - sim.z[d0]).length() < 30000.0:
						sim.alive[i] = 0          # nobody else joins in
				var h: float = sim.heading[d0]
				var red: Array = []
				for k in 2:
					red.append(_navy_spawn("apache", Vector2(sim.x[d0], sim.z[d0]) + Vector2.from_angle(h + 1.2 + k * 0.3) * 4200.0))
				_lab_data["red"] = red
				_navy_view(d0, 170.0, 0.9, 25.0)
				_lab_step = 1
				_lab_t = 0.0
		1:
			_navy_view(d0, 170.0, 0.9, 25.0)
			if counts.get("standard", 0) >= 1:
				_lab_step = 2
				_lab_t = 0.0
			elif _lab_t > 40.0:
				print("NAVY: no Standard missile launched in 40 s")
				_lab_step = 2
		2:
			if _lab_t > 0.35 and not _lab_data.has("s1"):
				_lab_data["s1"] = true
				_shot("vls_launch")
			if _lab_t > 1.1 and not _lab_data.has("s15"):
				_lab_data["s15"] = true
				_navy_view(d0, 520.0, 0.9, -120.0)
			if _lab_t > 1.6 and not _lab_data.has("s2"):
				_lab_data["s2"] = true
				_shot("vls_climb")
			if _lab_t > 3.0 and not _lab_data.has("s3"):
				_lab_data["s3"] = true
				_navy_view(d0, 1400.0, 0.9, -400.0)
				_shot("vls_pitch")
			if _lab_t > 4.5:
				_navy_view(d0, 2600.0, 0.9, -800.0)
				_shot("vls_away")
				_navy_clear()
				# a tank ashore, within gun range: the 5-inch gun and a Tomahawk
				# bring the destroyer in to 5 km off Galveston's beach
				var g := TexasGeo.city_xz(TexasGeo.city("Galveston"))
				var p := g
				while not TexasSea.is_sea(p) and p.y < g.y + 20000.0:
					p.y += 100.0
				var beach := TexasSim.nearest_land(p - Vector2(0, 60.0))
				p.y += 4200.0
				sim.x[d0] = p.x
				sim.z[d0] = p.y
				sim.px[d0] = p.x
				sim.pz[d0] = p.y
				sim.stop(d0)
				c.formation.release([d0])
				_lab_data["red"] = [_navy_spawn("tank", beach)]
				print("NAVY: tank ashore %.0f m from the destroyer" % Vector2(sim.x[_lab_data.red[0]] - sim.x[d0], sim.z[_lab_data.red[0]] - sim.z[d0]).length())
				_lab_step = 3
				_lab_t = 0.0
		3:
			_navy_view(d0, 90.0, 2.4, 50.0)
			if counts.get("gun", 0) >= 1 and not _lab_data.has("g"):
				_lab_data["g"] = _lab_t
			if _lab_data.has("g") and _lab_t > float(_lab_data.g) + 0.04 and not _lab_data.has("g1"):
				_lab_data["g1"] = true
				_shot("gun_fire")
			if _lab_data.has("g") and _lab_t > float(_lab_data.g) + 0.7 and not _lab_data.has("g2"):
				_lab_data["g2"] = true
				_shot("gun_smoke")
			if counts.get("tomahawk", 0) >= 1 and not _lab_data.has("tw"):
				_lab_data["tw"] = _lab_t
			if _lab_data.has("tw") and _lab_t > float(_lab_data.tw) + 1.2 and not _lab_data.has("tw1"):
				_lab_data["tw1"] = true
				_navy_view(d0, 300.0, 0.9, 0.0)
				_shot("tomahawk")
			if (_lab_data.has("tw1") and _lab_data.has("g2")) or _lab_t > 60.0:
				_navy_clear()
				var h: float = sim.heading[d0]
				_lab_data["red"] = [_navy_spawn("apache", Vector2(sim.x[d0], sim.z[d0]) + Vector2.from_angle(h + 0.3) * 1000.0)]
				_lab_step = 4
				_lab_t = 0.0
		4:
			_navy_view(d0, 140.0, 0.4, 10.0)
			if counts.get("ciws", 0) >= 1 and not _lab_data.has("cw"):
				_lab_data["cw"] = _lab_t
			if _lab_data.has("cw") and _lab_t > float(_lab_data.cw) + 0.9:
				_shot("ciws")
				_navy_clear()
				var car: int = c.ships.carrier
				var h: float = sim.heading[car]
				_lab_data["red"] = [_navy_spawn("apache", Vector2(sim.x[car], sim.z[car]) + Vector2.from_angle(h - 0.8) * 2600.0)]
				_lab_step = 5
				_lab_t = 0.0
			elif _lab_t > 40.0:
				print("NAVY: no Phalanx burst in 40 s")
				_lab_step = 5
		5:
			var car: int = c.ships.carrier
			_navy_view(car, 380.0, 0.5, 60.0)
			if counts.get("ram", 0) >= 1 and not _lab_data.has("rm"):
				_lab_data["rm"] = _lab_t
			if _lab_data.has("rm") and _lab_t > float(_lab_data.rm) + 0.8:
				_shot("ram")
				_navy_clear()
				c.set_lz(TexasSim.nearest_land(TexasGeo.city_xz(TexasGeo.city("Galveston"))))
				c.send_vehicles_ashore()
				_lab_step = 6
				_lab_t = 0.0
			elif _lab_t > 40.0:
				print("NAVY: no RAM in 40 s")
				_lab_step = 6
		6:
			var am: int = c.ships.amphib
			var h: float = sim.heading[am]
			var aft := Vector2(sin(h), cos(h))
			look_at_world(sim.x[am] + aft.x * 150.0, sim.z[am] + aft.y * 150.0, 230.0)
			_yaw = h + 0.5
			if _lab_t > 6.0 and not _lab_data.has("w1"):
				_lab_data["w1"] = true
				_shot("well_open")
			if _lab_t > 16.0:
				_shot("well_out")
				look_at_world(sim.x[am] + aft.x * 400.0, sim.z[am] + aft.y * 400.0, 700.0)
				_lab_step = 7
				_lab_t = 0.0
		7:
			if _lab_t > 1.0:
				_shot("well_away")
				print("NAVY: weapons fired: %s" % naval.launches)
				var lcac := TexasUnits.id("lcac")
				var out := 0
				for i in sim.count:
					if sim.utype[i] == lcac and sim.alive[i] == 1 and sim.aboard[i] == -1:
						out += 1
				print("NAVY: landing craft out of the well deck: %d" % out)
				print("NAVY: done")
				get_tree().quit()


func _click_card(i: int, double := false, shift := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = double
	ev.shift_pressed = shift
	ui.dock._on_unit_card(ev, i)


func _org_lab_tick(delta: float) -> void:
	## (lab) The unit dock: browse the organisation, pick units from cards, move them between
	## companies, order into a company, save and load
	_lab_t += delta
	var c := campaign
	var org := c.org
	var dock: TexasDock = ui.dock
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0:
				var car: int = c.ships.carrier
				look_at_world(sim.x[car], sim.z[car], 60000.0)
				dock.refresh()
				_shot("dock_all")
				var lines: Array = []
				for b in org.children(0):
					for bn in org.children(b):
						for co in org.children(bn):
							var kinds := {}
							for i in org.units_in(co):
								var nm := TexasUnits.label(sim.utype[i], 0)
								kinds[nm] = kinds.get(nm, 0) + 1
							lines.append("%s: %s" % [org.full_name(co), kinds])
				print("ORG: starting line-up:\n  " + "\n  ".join(lines))
				var bde: int = org.children(0)[0]
				dock.open(bde)
				_lab_step = 1
				_lab_t = 0.0
		1:
			if _lab_t > 0.6:
				_shot("dock_brigade")
				var bn: int = org.children(org.children(0)[0])[0]
				dock.open(bn)
				_lab_step = 2
				_lab_t = 0.0
		2:
			if _lab_t > 0.6:
				_shot("dock_battalion")
				var bn: int = org.children(org.children(0)[0])[0]
				dock.open(org.children(bn)[2])          # Charlie: the Bradleys and Strykers
				_lab_step = 3
				_lab_t = 0.0
		3:
			if _lab_t > 1.0:
				_shot("dock_company")
				# get some of the company ashore so they can take orders: unload at the dock
				var units := org.units_in(dock.at)
				for i in units:
					sim.aboard[i] = -1
					var p := TexasSim.nearest_land(TexasGeo.city_xz(TexasGeo.city("Galveston")) + Vector2(randf_range(-300, 300), randf_range(-300, 300)))
					sim.x[i] = p.x
					sim.z[i] = p.y
					sim.stop(i)
				dock.refresh()
				var first: int = units[0]
				_click_card(first)
				var one_ok: bool = selected == [first]
				_click_card(units[1], false, true)
				print("ORG: click a card selects it: %s; shift-click adds: %s (%d selected)" % [one_ok, selected.size() == 2, selected.size()])
				look_at_world(0.0, 0.0, 400000.0)
				_click_card(units[2], true)
				_lab_data["jump"] = units[2]
				_lab_step = 4
				_lab_t = 0.0
		4:
			if _lab_t > 1.2:
				var j: int = _lab_data.jump
				print("ORG: double-click from the whole-state view: camera %.0f m from the unit, view %.0f m across (was 400 km), selected only it: %s" % [Vector2(focus_x - sim.x[j], focus_z - sim.z[j]).length(), size, selected == [j]])
				_shot("dock_jump")
				# move two Bradleys to a brand-new brigade
				var units := org.units_in(dock.at)
				selected = [units[0], units[1]]
				dock._open_move_menu()
				var sub: PopupMenu = dock._menu.get_item_submenu_node(0)
				sub.popup(Rect2i(Vector2i(dock._menu.position) + Vector2i(dock._menu.size.x, 0), Vector2i.ZERO))
				var sub2: PopupMenu = sub.get_item_submenu_node(0)
				sub2.popup(Rect2i(Vector2i(sub.position) + Vector2i(sub.size.x, 0), Vector2i.ZERO))
				_lab_data["menu"] = "top: %d items, 1st Brigade: %d, 1st Battalion: %d (%s)" % [dock._menu.item_count, sub.item_count, sub2.item_count, sub2.get_item_text(0)]
				_lab_step = 40
				_lab_t = 0.0
		40:
			if _lab_t > 0.5:
				_shot("dock_menu")
				print("ORG: Move to… menu: %s" % _lab_data.menu)
				dock._menu.hide()
				var units := org.units_in(dock.at)
				selected = [units[0], units[1]]
				var co := org.add_company(org.add_battalion(org.add_brigade()))
				var n := dock.move_selected_to(co)
				print("ORG: moved %d to %s; it now has %d; the old company has %d" % [n, org.full_name(co), org.units_in(co).size(), org.units_in(org.children(org.children(org.children(0)[0])[0])[2]).size()])
				_shot("dock_moved")
				dock._set_tab("navy")
				_lab_step = 5
				_lab_t = 0.0
		5:
			if _lab_t > 0.8:
				_shot("dock_navy")
				dock._set_tab("all")
				# order two tanks into Able Company and one rifle squad left to find its own place
				var able: int = org.children(org.children(org.children(0)[0])[0])[0]
				ui.toggle_orders()
				ui._refresh_join()
				ui._join.select(ui._join_ids.find(able))
				order(TexasUnits.id("tank"))
				order(TexasUnits.id("tank"))
				ui._join.select(0)
				order(TexasUnits.id("rifle"))
				var before := sim.count
				c._delivery()
				var where: Array = []
				for i in range(before, sim.count):
					where.append("%s -> %s" % [TexasUnits.label(sim.utype[i], 0), org.full_name(org.unit_of.get(i, -1)) if org.unit_of.has(i) else "none"])
				print("ORG: delivery: %s" % ", ".join(where))
				_shot("dock_orders")
				ui.toggle_orders()
				# save and load: the organisation comes back the same
				_lab_data["before"] = str(org.unit_of) + str(org.nodes.keys())
				save_game()
				org.unit_of.clear()
				load_game()
				var after := str(campaign.org.unit_of) + str(campaign.org.nodes.keys())
				print("ORG: save/load keeps the organisation: %s" % (after == _lab_data.before))
				print("ORG: done")
				get_tree().quit()


func _water_lab_tick(delta: float) -> void:
	## (lab) Pictures of the water: surf on Galveston's beach, the fleet's wakes, a lake
	_lab_t += delta
	var c := campaign
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0:
				var beach := TexasGeo.to_xz(29.2795, -94.8030)
				look_at_world(beach.x, beach.y, 520.0)
				_lab_step = 1
				_lab_t = 0.0
		1:
			if _lab_t > 4.0 and tiles.pending_count() == 0:
				_shot("shore")
				var beach := TexasGeo.to_xz(29.2795, -94.8030)
				look_at_world(beach.x, beach.y, 2600.0)
				_lab_step = 2
				_lab_t = 0.0
		2:
			if _lab_t > 4.0 and tiles.pending_count() == 0:
				_shot("coast")
				select_fleet()
				var car: int = c.ships.carrier
				c.command_move(selected, Vector2(sim.x[car] - 9000.0, sim.z[car] + 3000.0))
				speed_i = 4
				_lab_step = 3
				_lab_t = 0.0
		3:
			if _lab_t > 6.0:
				speed_i = 2
				var car: int = c.ships.carrier
				look_at_world(sim.x[car], sim.z[car], 1800.0)
			if _lab_t > 22.0:
				_shot("fleet")
				var car: int = c.ships.carrier
				look_at_world(sim.x[car], sim.z[car], 420.0)
				_lab_step = 4
				_lab_t = 0.0
		4:
			var car: int = c.ships.carrier
			look_at_world(sim.x[car], sim.z[car], 420.0)
			if _lab_t > 6.0:
				_shot("carrier")
				var lake := TexasGeo.to_xz(29.555, -95.075)
				look_at_world(lake.x, lake.y, 2200.0)
				speed_i = 0
				_lab_step = 5
				_lab_t = 0.0
		5:
			if _lab_t > 4.0 and tiles.pending_count() == 0:
				_shot("lake")
				print("WATER: done")
				get_tree().quit()


func _ui_lab_tick(_delta: float) -> void:
	_lab_t += _delta
	var c := campaign
	match _lab_step:
		0:
			if map.ready_to_show and _lab_t > 2.0:
				var carrier: int = c.ships.carrier
				look_at_world(sim.x[carrier], sim.z[carrier], 900.0)
				_lab_step = 1
				_lab_t = 0.0
		1:
			if _lab_t > 1.5:
				# 1. click a helicopter parked on the carrier deck, then right-click somewhere: it takes off
				var heli := -1
				for i in _deck_slot:
					if TexasUnits.TYPES[sim.utype[i]].id == "black_hawk":
						heli = i
						break
				_shot("deck")
				if heli >= 0:
					_click_at(_screen_of(heli))
					var sel_ok := heli in selected
					var goal := Vector2(sim.x[heli] - 3000.0, sim.z[heli] - 3000.0)
					c.command_move(selected, goal)
					print("UI: deck helicopter clicked: selected %s; after the move order it is %s" % [sel_ok, "in the air" if sim.airborne(heli) else "still on deck"])
				# 2. a jet with nowhere to go circles
				var j := c.launch(TexasUnits.id("hornet"))
				sim.heading[j] = 0.0
				c.command_move([j], Vector2(sim.x[j] + 5000.0, sim.z[j] + 2000.0))
				_lab_data["j"] = j
				# 3. two ships sent to the same spot
				var a: int = c.ships.destroyer0
				var b: int = c.ships.destroyer1
				var spot := Vector2(sim.x[c.ships.carrier] + 4000.0, sim.z[c.ships.carrier] + 3000.0)
				sim.order_move(a, spot)
				sim.order_move(b, spot)
				# 4. a Bradley on Galveston Island sent out into the bay
				var gal := TexasGeo.city_xz(TexasGeo.city("Galveston"))
				var br := sim.add_typed(0, TexasUnits.id("bradley"), TexasSim.nearest_land(gal))
				var bay := TexasGeo.to_xz(29.40, -94.85)
				var ok := sim.order_move(br, bay)
				_lab_data["br"] = br
				print("UI: Bradley ordered into Galveston Bay (water there: %s): order %s" % [TexasSim.is_water(bay), ok])
				# 5. squads flown to a landing zone right on the shore
				c.set_lz(TexasSim.nearest_land(TexasGeo.to_xz(29.29, -94.80)))
				c.send_troops_ashore()
				speed_i = 4
				_lab_step = 2
				_lab_t = 0.0
		2:
			if _lab_t > 0.2 and _lab_t < 1.5:
				var jj: int = _lab_data.j
				var wp := unit_pos(jj)
				# a plane high up shows further up the screen: aim at the ground point it lines up with
				var fwd := Vector2(-sin(_yaw), -cos(_yaw))
				var up := (wp.y - _ground(wp.x, wp.z)) / tan(deg_to_rad(-PITCH))
				look_at_world(wp.x + fwd.x * up, wp.z + fwd.y * up, 260.0)
				speed_i = 1
			if _lab_t > 1.4 and not _lab_data.has("bank_shot"):
				_lab_data["bank_shot"] = true
				_shot("jet_turning")
				print("UI: jet leaning %.0f degrees in its turn" % rad_to_deg(sim.bank[_lab_data.j]))
				speed_i = 4
			if _lab_t > 1.5 and not _lab_data.has("jp"):
				var j: int = _lab_data.j
				_lab_data["jp"] = Vector2(sim.x[j], sim.z[j])
				print("UI: jet arrived (moving order %s), watching it" % sim.is_moving(j))
			if _lab_t > 20.0:
				var j: int = _lab_data.j
				print("UI: jet with nowhere to go, %.0f s of game time later: moved %.0f m, %.0f m from its spot, still in the air %s" % [sim.time, (_lab_data.jp as Vector2).distance_to(Vector2(sim.x[j], sim.z[j])), Vector2(sim.dest_x[j] - sim.x[j], sim.dest_z[j] - sim.z[j]).length(), sim.airborne(j)])
				var a: int = c.ships.destroyer0
				var b: int = c.ships.destroyer1
				print("UI: the two destroyers sent to one spot are %.0f m apart" % Vector2(sim.x[a] - sim.x[b], sim.z[a] - sim.z[b]).length())
				var br: int = _lab_data.br
				print("UI: the Bradley stopped at %s, on water: %s" % [TexasGeo.to_latlon(sim.x[br], sim.z[br]), TexasSim.is_water(Vector2(sim.x[br], sim.z[br]))])
				var wet := 0
				var ashore := 0
				for i in sim.count:
					if sim.alive[i] == 1 and sim.side[i] == 0 and sim.aboard[i] == -1 and TexasUnits.is_ground(sim.utype[i]):
						ashore += 1
						if TexasSim.is_water(Vector2(sim.x[i], sim.z[i])):
							wet += 1
				print("UI: units ashore %d, standing in the sea %d" % [ashore, wet])
				speed_i = 1
				get_window().size = Vector2i(1280, 600)
				_lab_step = 3
				_lab_t = 0.0
		3:
			if _lab_t > 1.5:
				ui.toggle_orders()
				_lab_step = 4
				_lab_t = 0.0
		4:
			if _lab_t > 1.0:
				_shot("short_window")
				get_window().size = Vector2i(1600, 900)
				var hou := TexasGeo.city_xz(TexasGeo.city("Houston"))
				look_at_world(hou.x + 8000.0, hou.y + 25000.0, 110000.0)
				_lab_step = 5
				_lab_t = 0.0
		5:
			if _lab_t > 2.0:
				_shot("names_region")
				look_at_world(0.0, 0.0, 400000.0)
				_lab_step = 6
				_lab_t = 0.0
		6:
			if _lab_t > 2.0:
				_shot("names_state")
				var hou := TexasGeo.city_xz(TexasGeo.city("Houston"))
				look_at_world(hou.x, hou.y + 8000.0, 26000.0)
				_lab_step = 7
				_lab_t = 0.0
		7:
			if _lab_t > 3.0:
				_shot("names_close")
				# The fleet: select it, pick the screen formation, sail it somewhere
				select_fleet()
				set_formation(1)
				var car: int = c.ships.carrier
				var goal := Vector2(sim.x[car] - 7000.0, sim.z[car] + 5000.0)
				_show_ghosts(c.formation.preview(selected, goal))
				var n := c.command_move(selected, goal)
				print("UI: fleet of %d sent in %s formation (water at the spot: %s), formation active %s" % [n, c.formation.shape_name(), TexasSea.is_sea(goal), c.formation.active()])
				_lab_data["goal"] = goal
				look_at_world(goal.x, goal.y, 4200.0)
				_lab_step = 8
				_lab_t = 0.0
		8:
			if _lab_t > 1.5:
				_shot("formation_ghosts")
				speed_i = 4
				_lab_step = 9
				_lab_t = 0.0
		9:
			var car: int = c.ships.carrier
			look_at_world(sim.x[car], sim.z[car], 4200.0)
			if _lab_t > 4.0:
				speed_i = 0
			if _lab_t > 5.5:
				_shot("formation_sailing")
				var f := c.formation
				print("UI: after %.0f game s the fleet is %s; modes %s" % [sim.time, "sailing in formation" if f.active() else "there", f.mode])
				print("UI: done")
				get_tree().quit()


func _click_at(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _drag(a: Vector2, b: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = a
	ev.global_position = a
	Input.parse_input_event(ev)
	var mv := InputEventMouseMotion.new()
	mv.position = b
	mv.global_position = b
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	Input.parse_input_event(up)
	Input.flush_buffered_events()
