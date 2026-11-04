class_name TexasUI
extends Control
## The Galveston campaign's panels: objectives and the next delivery, the fleet and what's
## aboard each ship (with the buttons to land the force and launch aircraft), ordering units
## for the next delivery wave, and what you have selected.

const AIRCRAFT := ["black_hawk", "chinook", "little_bird", "apache", "hornet", "a10"]
const ORDERABLE := ["rifle", "humvee", "stryker", "bradley", "tank", "lmtv", "aa", "black_hawk", "chinook",
	"little_bird", "apache", "hornet", "a10"]

var main: Node                          # TexasMain
var camp: TexasCampaign
var _objectives: Label
var _delivery: Label
var _fleet: Label
var _launch := {}                       # type id -> Button
var _orders_box: VBoxContainer
var _order_rows := {}                   # type id -> Label (count)
var _orders_head: Label
var dock: TexasDock
var _join: OptionButton
var _join_ids: Array = []
var _join_key := ""
var _result: Label
var _log: Label
var _log_lines: Array = []
var _t := 0.0
var _right: PanelContainer
var _scroll: ScrollContainer
var _right_box: VBoxContainer
var _form_btns: Array = []
var _form_state: Label


class FormationIcon extends Control:
	## A little picture of a formation: the ships as boxes, the bow up
	var shape := 0
	var lit := false

	func _draw() -> void:
		var slots: Dictionary = TexasFormation.SHAPES[shape].slots
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var k := size.y / 2300.0
		var lo := 0.0
		var hi := 0.0
		for r in slots:
			lo = minf(lo, slots[r].y)
			hi = maxf(hi, slots[r].y)
		c.y += (hi + lo) * 0.5 * k
		for r in slots:
			var o: Vector2 = slots[r]
			var hull: Vector2 = TexasFormation.HULL["destroyer" if r.begins_with("destroyer") else r]
			var w := maxf(7.0, hull.y * k * 4.5)
			var h := maxf(12.0, hull.x * k * 1.9)
			var p := c + Vector2(o.x * k, -o.y * k)
			var col := UiTheme.ACCENT if lit else UiTheme.TEXT_DIM
			if r == "carrier":
				col = col.lightened(0.25)
			draw_rect(Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h)), col, false, 1.5)


func _init(m: Node, c: TexasCampaign) -> void:
	main = m
	camp = c
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.09, 0.10, 0.86)))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _btn(text: String, tip: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, tip)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build() -> void:
	# Right column: objectives, delivery, fleet
	# Fits the window's height and scrolls when there's more than fits
	var right := _panel()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -330
	right.offset_right = -10
	right.offset_top = 10
	add_child(right)
	_right = right
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_right_box = v
	v.add_child(UiTheme.label("OBJECTIVES", 13, UiTheme.ACCENT, false, true))
	_objectives = UiTheme.label("", 12, UiTheme.TEXT)
	v.add_child(_objectives)
	_delivery = UiTheme.label("", 12, UiTheme.TEXT_DIM)
	v.add_child(_delivery)
	v.add_child(HSeparator.new())
	v.add_child(UiTheme.label("FLEET", 13, UiTheme.ACCENT, false, true))
	_fleet = UiTheme.label("", 11, UiTheme.TEXT)
	_fleet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleet.custom_minimum_size = Vector2(290, 0)
	v.add_child(_fleet)
	# Formation the fleet sails in
	var fh := HBoxContainer.new()
	var fl := UiTheme.label("Formation (G)", 11, UiTheme.TEXT_DIM)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(fl)
	fh.add_child(_btn("Select fleet", "Select every ship you have (then right-click to sail them in formation)", func(): main.select_fleet()))
	v.add_child(fh)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 4)
	v.add_child(fr)
	for k in TexasFormation.SHAPES.size():
		var sh: Dictionary = TexasFormation.SHAPES[k]
		var b := _btn("", "%s: %s" % [sh.name, sh.tip], func(): main.set_formation(k))
		b.custom_minimum_size = Vector2(98, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var icon := FormationIcon.new()
		icon.shape = k
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_top = 4
		icon.offset_bottom = -18
		b.add_child(icon)
		var nm := UiTheme.label(sh.name, 11, UiTheme.TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		nm.offset_top = -17
		nm.offset_bottom = -2
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(nm)
		fr.add_child(b)
		_form_btns.append([b, icon, nm])
	_form_state = UiTheme.label("", 11, UiTheme.TEXT_DIM)
	_form_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form_state.custom_minimum_size = Vector2(290, 0)
	v.add_child(_form_state)
	var row := HBoxContainer.new()
	row.add_child(_btn("Set landing zone", "Then right-click on the map where the force should land (Z)", func(): main.begin_lz()))
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(_btn("All vehicles ashore", "Landing craft carry every vehicle still aboard to the beach nearest the landing zone (or unload at a port you hold). To send only some, pick them on the unit cards and use Ashore (V), or right-click on land.", func(): main.vehicles_ashore()))
	row2.add_child(_btn("All squads ashore", "Helicopters fly every squad still aboard to the landing zone. To send only some, pick them on the unit cards and use Ashore (V), or right-click on land.", func(): main.troops_ashore()))
	v.add_child(row2)
	v.add_child(UiTheme.label("Launch aircraft", 11, UiTheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for id in AIRCRAFT:
		var t := TexasUnits.id(id)
		var b := _btn(TexasUnits.label(t, 0), "Put one in the air from the ship (or airfield) it's on", func(): main.launch(t))
		b.custom_minimum_size = Vector2(140, 0)
		grid.add_child(b)
		_launch[id] = b
	v.add_child(HSeparator.new())
	var oh := HBoxContainer.new()
	_orders_head = UiTheme.label("", 12, UiTheme.TEXT)
	_orders_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(_orders_head)
	oh.add_child(_btn("Order units", "Show or hide the order list for the next delivery wave (O)", func(): toggle_orders()))
	v.add_child(oh)
	_orders_box = VBoxContainer.new()
	_orders_box.visible = false
	v.add_child(_orders_box)
	var jr := HBoxContainer.new()
	jr.add_child(UiTheme.label("New units join:", 11, UiTheme.TEXT_DIM))
	_join = OptionButton.new()
	_join.focus_mode = Control.FOCUS_NONE
	_join.add_theme_font_size_override("font_size", 11)
	_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join.clip_text = true
	_join.custom_minimum_size = Vector2(170, 0)
	_join.tooltip_text = "Which company the units you order next will join when they arrive"
	jr.add_child(_join)
	_orders_box.add_child(jr)
	for id in ORDERABLE:
		var t := TexasUnits.id(id)
		var r := HBoxContainer.new()
		var nm := UiTheme.label("%s  (%d)" % [TexasUnits.label(t, 0), TexasUnits.TYPES[t].cost], 11, UiTheme.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nm)
		var cnt := UiTheme.label("0", 11, UiTheme.ACCENT)
		cnt.custom_minimum_size = Vector2(22, 0)
		r.add_child(cnt)
		r.add_child(_btn("−", "Take one off the order", func(): camp.remove_order(t); refresh()))
		r.add_child(_btn("+", "Add one to the next delivery", func(): main.order(t); refresh()))
		_orders_box.add_child(r)
		_order_rows[id] = cnt
	# Along the bottom: the unit dock (organisation, cards, the selection and its commands)
	dock = TexasDock.new(main, camp)
	add_child(dock)
	# Messages, top centre
	_log = UiTheme.label("", 13, UiTheme.TEXT, true)
	_log.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_log.offset_left = -330
	_log.offset_right = 330
	_log.offset_top = 12
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	# Win or lose
	_result = UiTheme.label("", 26, UiTheme.ACCENT, true, true)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.offset_left = -420
	_result.offset_right = 420
	_result.offset_top = -60
	_result.offset_bottom = 60
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.visible = false
	add_child(_result)


func toggle_orders() -> void:
	_orders_box.visible = not _orders_box.visible


func message(t: String) -> void:
	# The same message again: count it instead of repeating it
	if not _log_lines.is_empty() and (_log_lines[-1][2] as String) == t:
		_log_lines[-1][3] += 1
		_log_lines[-1][0] = "%s  ×%d" % [t, _log_lines[-1][3]]
		_log_lines[-1][1] = 9.0
		return
	_log_lines.append([t, 9.0, t, 1])
	if _log_lines.size() > 4:
		_log_lines.pop_front()


func _process(delta: float) -> void:
	var keep: Array = []
	var lines: Array = []
	for l in _log_lines:
		l[1] -= delta
		if l[1] > 0.0:
			keep.append(l)
			lines.append(l[0])
	_log_lines = keep
	_log.text = "\n".join(lines)
	# As tall as what's in it, but never taller than the window
	var want := _right_box.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - 54.0
	_scroll.custom_minimum_size = Vector2(310, minf(want, room))
	_right.size = Vector2(320, 0)
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		refresh()


func refresh() -> void:
	var sim := camp.sim
	_objectives.text = camp.objectives_text()
	var w := camp.next_wave_in()
	_delivery.text = "Next delivery in %d:%02d  ·  %d points to spend" % [floori(w / 60.0), floori(fmod(w, 60.0)), camp.points]
	var lines: Array = []
	for role in ["carrier", "amphib", "destroyer0", "destroyer1", "cruiser"]:
		if not camp.ships.has(role):
			continue
		var i: int = camp.ships[role]
		if sim.alive[i] == 0:
			lines.append("%s: sunk" % camp._ship_name(role))
			continue
		var cargo := camp.ship_cargo(role)
		var parts: Array = []
		for nm in cargo:
			parts.append("%d %s" % [cargo[nm], nm])
		var line := "%s  %d%%" % [camp._ship_name(role), int(sim.strength[i] * 100.0)]
		if not parts.is_empty():
			line += "\n   " + ", ".join(parts)
		lines.append(line)
	var lzs := "not set" if camp.lz.x == INF else "set"
	lines.append("Landing zone: %s · waiting to go ashore: %d vehicles, %d squads · in transit: %d" % [lzs, camp.vehicle_queue.size(), camp.troop_queue.size(), camp.ferries.size()])
	_fleet.text = "\n".join(lines)
	var fm := camp.formation
	for k in _form_btns.size():
		var on: bool = k == fm.shape
		var ic: FormationIcon = _form_btns[k][1]
		if ic.lit != on:
			ic.lit = on
			ic.queue_redraw()
		(_form_btns[k][2] as Label).add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT)
	if fm.active():
		var wake := 0
		for m in fm.mode:
			if fm.mode[m] != "station":
				wake += 1
		_form_state.text = "%s in %s formation: %d ships at the slowest one's pace%s" % ["Forming up" if fm.forming else "Sailing", fm.shape_name().to_lower(), fm.members.size() + 1,
			(" · %d in line astern through narrow water" % wake) if wake > 0 else ""]
	else:
		_form_state.text = "Select two or more ships and right-click: they sail in this formation."
	for id in AIRCRAFT:
		var t := TexasUnits.id(id)
		var n := camp.aircraft_ready(t)
		var b: Button = _launch[id]
		b.text = "%s  ×%d" % [TexasUnits.label(t, 0), n]
		b.disabled = n == 0
	var ordered := {}
	for t in camp.orders:
		ordered[t] = ordered.get(t, 0) + 1
	for id in ORDERABLE:
		(_order_rows[id] as Label).text = str(ordered.get(TexasUnits.id(id), 0))
	_orders_head.text = "Ordered for the next wave: %d" % camp.orders.size()
	dock.refresh()
	_refresh_join()
	if camp.result != "":
		_result.visible = true
		_result.text = ("VICTORY\nDowntown Houston is yours." if camp.result == "won" else "DEFEAT\nThe carrier is lost.")


func _refresh_join() -> void:
	## The companies new orders can join (rebuilt when the organisation changes)
	var org := camp.org
	var cs := org.companies()
	var key := str(cs) + str(org.nodes.size())
	if key == _join_key:
		return
	_join_key = key
	var keep := order_company()
	_join.clear()
	_join_ids = [-1]
	_join.add_item("Wherever they fit")
	for c in cs:
		_join.add_item(org.full_name(c))
		_join_ids.append(c)
	var k := _join_ids.find(keep)
	_join.select(maxi(k, 0))


func order_company() -> int:
	## The company picked for new orders (-1: let the organisation decide)
	if _join == null or _join.selected < 0 or _join.selected >= _join_ids.size():
		return -1
	return _join_ids[_join.selected]
