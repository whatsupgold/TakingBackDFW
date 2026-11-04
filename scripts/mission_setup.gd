class_name MissionSetup
extends PanelContainer
## The screen before a mission: pick START_PICKS units and where on the map edge you come in.
## The Red Army's area is marked on the map. Deploy unlocks once the city is fully mapped
## (so units can path from the edge).

signal deployed(loadout: Dictionary, zone: int)

var game: Node
var counts := {}
var zone := 1
var _rows := {}
var _total: Label
var _deploy: Button
var _zone_label: Label
var _map: StartMap


class StartMap:
	extends Control
	## The city map with the start zones on its edges; click one to choose it
	const SCALE := 2.0
	var game: Node
	var setup: MissionSetup
	var _tex: ImageTexture

	func init(g: Node, s: MissionSetup) -> void:
		game = g
		setup = s
		var helper := Minimap.new()
		_tex = ImageTexture.create_from_image(helper._render(game.level.city))
		helper.free()
		custom_minimum_size = Vector2(Minimap.MAP_W, Minimap.MAP_H) * SCALE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func px(w: Vector3) -> Vector2:
		return Vector2((w.x + CityBuilder.HALF_X) / (CityBuilder.HALF_X * 2.0), (w.z + CityBuilder.HALF_Z) / (CityBuilder.HALF_Z * 2.0)) * custom_minimum_size

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, custom_minimum_size), false)
		# The Red Army: its objectives, and the east edge it's reinforcing from
		var army: RedArmy = game.enemy
		draw_rect(Rect2(Vector2(custom_minimum_size.x - 10, 0), Vector2(10, custom_minimum_size.y)), Color(0.9, 0.2, 0.15, 0.55))
		for o in army.objectives:
			var p := px(o.pos)
			draw_arc(p, 9.0, 0, TAU, 20, Color(0, 0, 0, 0.7), 4.0)
			draw_arc(p, 9.0, 0, TAU, 20, Color(1.0, 0.35, 0.3), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(custom_minimum_size.x - 92, 16), "RED ARMY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.45, 0.4))
		var fa := px(Vector3(RedFob.RECT.position.x, 0, RedFob.RECT.position.y))
		var fb := px(Vector3(RedFob.RECT.end.x, 0, RedFob.RECT.end.y))
		draw_rect(Rect2(fa, fb - fa), Color(0.9, 0.2, 0.15, 0.5), true)
		draw_rect(Rect2(fa, fb - fa), Color(1.0, 0.4, 0.35), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(fa.x - 70, fb.y + 14), "RED FOB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.4))
		# Start zones
		for i in game.START_ZONES.size():
			var p := px(game.zone_pos(i))
			var sel: bool = i == setup.zone
			draw_circle(p, 11.0 if sel else 8.0, Color(0, 0, 0, 0.75))
			draw_circle(p, 8.0 if sel else 6.0, UiTheme.ACCENT if sel else Color(0.55, 0.85, 1.0))
			draw_string(ThemeDB.fallback_font, p + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.05))
		draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), UiTheme.BORDER, false, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var best := -1
			var best_d := 30.0
			for i in game.START_ZONES.size():
				var d := px(game.zone_pos(i)).distance_to(event.position)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				setup.pick_zone(best)
			accept_event()


func build(g: Node) -> void:
	game = g
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG_SOLID))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(UiTheme.label("MISSION: TAKING BACK DFW", 26, UiTheme.ACCENT))
	var intro := UiTheme.label("The Red Army holds a walled FOB on the east edge of the map. Take it to win: its walls have to be breached (M777, A-10, or an engineers' breach charge). It gets a new unit every 2 minutes and grows every 5, and it has anti-air, so the sooner the better. Pick %d units and where you come in: your reinforcements arrive there too. There's no base yet: bring engineers to build one." % game.START_PICKS, 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(980, 0)
	root.add_child(intro)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	root.add_child(cols)

	# Left: the loadout
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	left.custom_minimum_size = Vector2(360, 0)
	cols.add_child(left)
	left.add_child(UiTheme.label("YOUR FORCE", 15, UiTheme.TEXT_DIM))
	for opt in game.LOADOUT:
		counts[opt.id] = 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		left.add_child(row)
		var minus := UiTheme.button("–")
		minus.custom_minimum_size = Vector2(30, 0)
		minus.pressed.connect(_change.bind(opt.id, -1))
		row.add_child(minus)
		var n := UiTheme.label("0", 16, UiTheme.ACCENT)
		n.custom_minimum_size = Vector2(22, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(n)
		var plus := UiTheme.button("+")
		plus.custom_minimum_size = Vector2(30, 0)
		plus.pressed.connect(_change.bind(opt.id, 1))
		row.add_child(plus)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		row.add_child(v)
		v.add_child(UiTheme.label(opt.name, 14))
		var d := UiTheme.label(opt.desc, 11, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(270, 0)
		v.add_child(d)
		_rows[opt.id] = n
	_total = UiTheme.label("", 15, UiTheme.ACCENT)
	left.add_child(_total)

	# Right: where you come in
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(UiTheme.label("WHERE YOU COME IN (click a point on the map edge)", 15, UiTheme.TEXT_DIM))
	_map = StartMap.new()
	_map.init(game, self)
	right.add_child(_map)
	_zone_label = UiTheme.label("", 14)
	right.add_child(_zone_label)
	_deploy = UiTheme.button("Deploy")
	_deploy.custom_minimum_size = Vector2(0, 42)
	_deploy.add_theme_font_size_override("font_size", 18)
	_deploy.pressed.connect(_on_deploy)
	right.add_child(_deploy)

	# A sensible starting pick
	for id in ["squad", "squad", "engineer", "humvee", "chinook", "a10", "m777"]:
		_change(id, 1)
	pick_zone(zone)


func _change(id: String, d: int) -> void:
	var total := 0
	for k in counts:
		total += counts[k]
	var opt: Dictionary = {}
	for o in game.LOADOUT:
		if o.id == id:
			opt = o
	var cap: int = opt.get("max", 99)
	if d > 0 and (total >= game.START_PICKS or counts[id] >= cap):
		return
	counts[id] = clampi(counts[id] + d, 0, cap)
	_refresh()


func pick_zone(i: int) -> void:
	zone = i
	_refresh()


func _refresh() -> void:
	var total := 0
	for k in counts:
		total += counts[k]
		(_rows[k] as Label).text = str(counts[k])
	_total.text = "%d / %d picked" % [total, game.START_PICKS]
	if _zone_label:
		_zone_label.text = "Start: %d — %s" % [zone + 1, game.zone_name(zone)]


func _process(_d: float) -> void:
	if _deploy == null:
		return
	var lvl: Level = game.level
	var total := 0
	for k in counts:
		total += counts[k]
	if lvl.nav_done < lvl.nav_total:
		_deploy.disabled = true
		_deploy.text = "Mapping the city... %d%%" % int(100.0 * lvl.nav_done / maxf(1.0, lvl.nav_total))
	elif not lvl.map_settled():
		_deploy.disabled = true
		_deploy.text = "Finishing the map..."
	elif total == 0:
		_deploy.disabled = true
		_deploy.text = "Pick at least one unit"
	else:
		_deploy.disabled = false
		_deploy.text = "Deploy (%d units)" % total


func _on_deploy() -> void:
	deployed.emit(counts.duplicate(), zone)
