class_name TexasDock
extends Control
## The unit dock along the bottom of the screen: find any unit of yours without moving the
## camera. Tabs (All, Ground, Mech, Air, Navy) and a path through the organisation
## (All forces ▸ 1st Brigade ▸ 3rd Battalion ▸ Easy Company): brigades, battalions and companies
## show as cards to open, a company's units as cards with their portraits. Click a unit's card to
## select it (shift: add), double-click to take the camera there. The selection and its commands
## sit on the left, with "Move to…" to put units in another company, battalion or brigade.

const TABS := [["all", "All"], ["ground", "Ground"], ["mech", "Mech"], ["air", "Air"], ["navy", "Navy"]]
const CARD_W := 92.0
const ICON := {"ground": "squad", "mech": "tank", "air": "heli", "navy": "vehicle"}
const JUMP_SIZE := 900.0               # how close the camera comes when you double-click a card

var main: Node                         # TexasMain
var camp: TexasCampaign
var org: TexasOrg
var portraits: TexasPortraits
var at := 0                            # the part of the organisation being looked at
var tab := "all"
var _tab_btns := {}
var _path_box: HBoxContainer
var _cards_box: HBoxContainer
var _scroll: ScrollContainer
var _sel: Label
var _note: Label
var _select_all: Button
var _disband: Button
var _move_btn: Button
var _cards: Array = []                 # {"unit"} or {"node"} with "panel", "bar", "status"
var _built_for := ""
var _menu: PopupMenu
var _menu_actions := {}                # popup item id -> [action, node]


func _init(m: Node, c: TexasCampaign) -> void:
	main = m
	camp = c
	org = c.org
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portraits = TexasPortraits.new()
	add_child(portraits)
	_build()


func _btn(text: String, tip: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, tip)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _box(bg: Color, border: Color, pad := 5) -> StyleBoxFlat:
	var b := UiTheme.panel_box(bg, border)
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b


func _build() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.09, 0.10, 0.88)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 10
	panel.offset_right = -340
	panel.offset_top = -238
	panel.offset_bottom = -28
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	# Left: the selection and its commands
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(236, 0)
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	left.add_child(UiTheme.label("SELECTED", 12, UiTheme.ACCENT, false, true))
	_sel = UiTheme.label("", 12, UiTheme.TEXT)
	_sel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel.custom_minimum_size = Vector2(230, 0)
	_sel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_sel)
	var g := GridContainer.new()
	g.columns = 3
	left.add_child(g)
	g.add_child(_btn("Board (L)", "Squads climb into the nearest transport with room", func(): main.cmd_board()))
	g.add_child(_btn("Unload (U)", "Transports let everyone out (helicopters land first)", func(): main.cmd_unload()))
	g.add_child(_btn("Refuel (R)", "Aircraft fly back to a ship or an airfield you hold to refuel and rearm", func(): main.cmd_rtb()))
	g.add_child(_btn("Stop (X)", "Stop where they are", func(): main.cmd_stop()))
	g.add_child(_btn("Ashore (V)", "Send the selected troops and vehicles that are still aboard ship ashore, to the landing zone. Or right-click on land (or right-drag a line) to send them there.", func(): main.cmd_ashore()))
	_move_btn = _btn("Move to…", "Put the selected units in another company (in any battalion or brigade), or a new one", func(): _open_move_menu())
	g.add_child(_move_btn)
	row.add_child(VSeparator.new())
	# Right: tabs, the path through the organisation, the cards
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	for t in TABS:
		var id: String = t[0]
		var b := _btn(t[1], "Show only %s" % t[1].to_lower() if id != "all" else "Show everything", func(): _set_tab(id))
		tabs.add_child(b)
		_tab_btns[id] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	_select_all = _btn("Select all", "Select every unit shown here (in this part of the organisation, on this tab)", func(): _select_everything())
	tabs.add_child(_select_all)
	var path_row := HBoxContainer.new()
	right.add_child(path_row)
	_path_box = HBoxContainer.new()
	_path_box.add_theme_constant_override("separation", 2)
	_path_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path_box)
	_disband = _btn("Disband", "Remove this empty company, battalion or brigade", func(): _disband_here())
	path_row.add_child(_disband)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(0, 136)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_scroll)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_cards_box)
	_note = UiTheme.label("", 12, UiTheme.TEXT_DIM)
	_cards_box.add_child(_note)
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


# --- Looking around -----------------------------------------------------------------------------

func _set_tab(id: String) -> void:
	tab = id
	refresh()


func open(node: int) -> void:
	if org.nodes.has(node):
		at = node
		refresh()


func _shown() -> Array:
	## What the card row shows: [["node", id] ...] or [["unit", i] ...]
	var out: Array = []
	if tab == "navy":
		for i in camp.sim.count:
			if camp.sim.alive[i] == 1 and camp.sim.side[i] == 0 and org.group_of(i) == "navy":
				out.append(["unit", i])
		return out
	if org.nodes[at].level == TexasOrg.Level.COMPANY:
		for i in org.units_in(at, tab):
			out.append(["unit", i])
		return out
	for k in org.children(at):
		if tab == "all" or not org.units_in(k, tab).is_empty() or org.units_in(k).is_empty():
			out.append(["node", k])
	return out


func _visible_units() -> Array:
	if tab == "navy":
		var out: Array = []
		for s in _shown():
			out.append(s[1])
		return out
	return org.units_in(at, tab)


# --- Keeping it up to date ----------------------------------------------------------------------

func refresh() -> void:
	var sim := camp.sim
	# anything of yours not yet in a company (Navy apart) finds one
	for i in sim.count:
		if sim.side[i] == 0 and sim.alive[i] == 1 and not org.unit_of.has(i):
			org.settle(i)
	if not org.nodes.has(at):
		at = 0
	# tabs with their counts (in this part of the organisation)
	for t in TABS:
		var id: String = t[0]
		var n := 0
		if id == "navy":
			for i in sim.count:
				if sim.alive[i] == 1 and sim.side[i] == 0 and org.group_of(i) == "navy":
					n += 1
		else:
			n = org.units_in(at, id).size()
		var b: Button = _tab_btns[id]
		b.text = "%s %d" % [t[1], n]
		b.add_theme_color_override("font_color", UiTheme.ACCENT if id == tab else UiTheme.TEXT)
	_build_path()
	var shown := _shown()
	var key := "%s|%d|%s" % [tab, at, str(shown)]
	if key != _built_for:
		_built_for = key
		_build_cards(shown)
	_update_cards()
	_update_selection()


func _build_path() -> void:
	for c in _path_box.get_children():
		c.queue_free()
	if tab == "navy":
		_path_box.add_child(UiTheme.label("The fleet: ships and landing craft", 12, UiTheme.TEXT_DIM))
		_disband.visible = false
		return
	var p := org.path(at)
	for k in p.size():
		var n: int = p[k]
		if k > 0:
			_path_box.add_child(UiTheme.label("▸", 12, UiTheme.TEXT_DIM))
		var b := _btn(org.name_of(n), "Go back up to %s" % org.name_of(n), func(): open(n))
		if n == at:
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
		_path_box.add_child(b)
	_disband.visible = at != 0 and org.units_in(at).is_empty()


func _build_cards(shown: Array) -> void:
	for c in _cards_box.get_children():
		if c != _note:
			c.queue_free()
	_cards.clear()
	_note.visible = shown.is_empty()
	_note.text = "Nothing here yet." if tab != "navy" else "No ships left."
	for s in shown:
		if s[0] == "node":
			_add_node_card(s[1])
		else:
			_add_unit_card(s[1])


func _add_node_card(n: int) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(UiTheme.BG_CARD, UiTheme.BORDER_DIM))
	p.custom_minimum_size = Vector2(CARD_W + 30, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = "%s: click to open" % org.name_of(n)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open.call_deferred(n))
	_cards_box.add_child(p)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(UiIcon.make("flag", UiTheme.ACCENT, 12))
	var nm := UiTheme.label(org.name_of(n), 13, UiTheme.TEXT, false, true)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)
	var info := UiTheme.label("", 11, UiTheme.TEXT_DIM)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(CARD_W + 18, 0)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info)
	var bar := _bar()
	v.add_child(bar)
	var sel := _btn("Select", "Select every unit in %s%s" % [org.name_of(n), "" if tab == "all" else " on this tab"], func(): _select_units(_filter(org.units_in(n, tab)), Input.is_key_pressed(KEY_SHIFT)))
	v.add_child(sel)
	_cards.append({"node": n, "panel": p, "bar": bar, "status": info})


func _add_unit_card(i: int) -> void:
	var sim := camp.sim
	var t: int = sim.utype[i]
	var id: String = TexasUnits.TYPES[t].id
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _card_style(false))
	p.custom_minimum_size = Vector2(CARD_W, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var title := _title(i)
	p.tooltip_text = "%s%s\nClick to select (shift: add), double-click to go there" % [title, ("\n" + org.full_name(org.unit_of[i])) if org.unit_of.has(i) else ""]
	p.gui_input.connect(_on_unit_card.bind(i))
	_cards_box.add_child(p)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(UiIcon.make(_icon(t), UiTheme.TEXT_DIM, 12))
	var pic := TextureRect.new()
	pic.texture = portraits.texture_for(id)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(TexasPortraits.SIZE) * 2.0
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var nm := UiTheme.label(title, 12, UiTheme.TEXT, false, true)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(CARD_W - 12, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var status := UiTheme.label("", 10, UiTheme.TEXT_DIM)
	status.clip_text = true
	status.custom_minimum_size = Vector2(CARD_W - 12, 0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(status)
	var bar := _bar()
	v.add_child(bar)
	_cards.append({"unit": i, "panel": p, "bar": bar, "status": status, "sel": false})


func _bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.20, 0.23, 0.26)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _card_style(selected: bool) -> StyleBoxFlat:
	var b := _box(Color(0.17, 0.17, 0.12, 0.97) if selected else UiTheme.BG_CARD, UiTheme.ACCENT if selected else UiTheme.BORDER_DIM)
	if selected:
		b.set_border_width_all(2)
	return b


func _icon(t: int) -> String:
	match TexasUnits.cat[t]:
		TexasUnits.Cat.INFANTRY:
			return "squad"
		TexasUnits.Cat.ARMOR:
			return "tank"
		TexasUnits.Cat.HELI:
			return "heli"
		TexasUnits.Cat.JET:
			return "jet"
	return "vehicle"


func _title(i: int) -> String:
	var t: int = camp.sim.utype[i]
	if TexasUnits.is_ship(t):
		return camp.ship_title(i).get_slice(" (", 0)
	return TexasUnits.label(t, 0)


func _status(i: int) -> String:
	var sim := camp.sim
	var host := sim.aboard[i]
	if host >= 0:
		if TexasUnits.is_ship(sim.utype[host]):
			return "On deck" if sim.is_air(i) and main._deck_slot.has(i) else "Aboard %s" % camp.ship_title(host).get_slice(" (", 0).trim_prefix("USS ")
		return "In a %s" % TexasUnits.label(sim.utype[host], 0)
	if host <= -2:
		return "At the airfield"
	if camp.ferries.has(i):
		return "Ferrying"
	if sim.target[i] >= 0:
		return "Fighting"
	if sim.airborne(i):
		return "Flying"
	if sim.is_moving(i):
		return "Moving"
	return "Holding"


func _update_cards() -> void:
	var sim := camp.sim
	var sel := {}
	for i in main.selected:
		sel[i] = true
	for c in _cards:
		if c.has("unit"):
			var i: int = c.unit
			var on := sel.has(i)
			if on != c.sel:
				c.sel = on
				(c.panel as PanelContainer).add_theme_stylebox_override("panel", _card_style(on))
			(c.bar as ProgressBar).value = sim.strength[i]
			var st := _status(i)
			if TexasUnits.is_ship(sim.utype[i]):
				st = "%s · %s" % [TexasUnits.label(sim.utype[i], 0).get_slice(" ", 0) if sim.utype[i] == TexasUnits.id("amphib") else TexasUnits.label(sim.utype[i], 0), st]
			(c.status as Label).text = st
		else:
			var units := org.units_in(c.node, tab)
			var counts := {}
			var s := 0.0
			for i in units:
				var g := org.group_of(i)
				counts[g] = counts.get(g, 0) + 1
				s += sim.strength[i]
			var parts: Array = []
			for g in ["ground", "mech", "air"]:
				if counts.has(g):
					parts.append("%d %s" % [counts[g], {"ground": "squads", "mech": "vehicles", "air": "aircraft"}[g]])
			var sub := org.children(c.node).size()
			var lvl: int = org.nodes[c.node].level
			var inside := "" if lvl == TexasOrg.Level.COMPANY else "%d %s\n" % [sub, "battalions" if lvl == TexasOrg.Level.BRIGADE else "companies"]
			(c.status as Label).text = inside + (", ".join(parts) if not parts.is_empty() else "empty")
			(c.bar as ProgressBar).value = s / units.size() if not units.is_empty() else 0.0


func _update_selection() -> void:
	var sim := camp.sim
	var sel: Array = main.selected
	_move_btn.disabled = sel.is_empty()
	if sel.is_empty():
		_sel.text = "Nothing selected.\nPick units on the map or from the cards."
		return
	var counts := {}
	var stren := 0.0
	var fuel := 0.0
	var n := 0
	var companies := {}
	for i in sel:
		if sim.alive[i] == 0:
			continue
		var nm := _title(i) if TexasUnits.is_ship(sim.utype[i]) else TexasUnits.label(sim.utype[i], 0)
		counts[nm] = counts.get(nm, 0) + 1
		stren += sim.strength[i]
		fuel += sim.fuel[i]
		n += 1
		if org.unit_of.has(i):
			companies[org.unit_of[i]] = true
	var parts: Array = []
	for nm in counts:
		parts.append("%d %s" % [counts[nm], nm] if counts[nm] > 1 else nm)
	var where := ""
	if companies.size() == 1:
		where = "\n" + org.full_name(companies.keys()[0])
	elif companies.size() > 1:
		where = "\nfrom %d companies" % companies.size()
	_sel.text = "%s%s\nStrength %d%% · fuel %d%%" % [", ".join(parts), where, int(stren / maxi(n, 1) * 100.0), int(fuel / maxi(n, 1) * 100.0)]


# --- Picking ------------------------------------------------------------------------------------

func _filter(units: Array) -> Array:
	## The ones that can be picked: out on the map, or aboard a ship waiting to go ashore
	## (not riding inside a transport that's on its way)
	var out: Array = []
	for i in units:
		if main._selectable(i):
			out.append(i)
	return out


func _select_units(units: Array, add: bool) -> void:
	if not add:
		main.selected.clear()
	for i in units:
		if not (i in main.selected):
			main.selected.append(i)
	refresh()


func _select_everything() -> void:
	var all := _visible_units()
	var ok := _filter(all)
	_select_units(ok, Input.is_key_pressed(KEY_SHIFT))
	if ok.size() < all.size():
		main._say("%d selected; %d are on their way in a transport." % [ok.size(), all.size() - ok.size()])


func _on_unit_card(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var sim := camp.sim
	if event.double_click:
		# Just this one, and the camera goes there (closing in if it's zoomed out)
		if main._selectable(i):
			main.selected = [i]
		go_to(i)
	elif not main._selectable(i):
		main._say("%s is %s: it can take orders once it's off." % [_title(i), _status(i).to_lower()])
	elif event.shift_pressed:
		if i in main.selected:
			main.selected.erase(i)
		else:
			main.selected.append(i)
	else:
		main.selected = [i]
	refresh()


func go_to(i: int) -> void:
	var sim := camp.sim
	main.focus_x = sim.x[i]
	main.focus_z = sim.z[i]
	if main._target_size > JUMP_SIZE:
		main._target_size = JUMP_SIZE


# --- Moving units between companies -------------------------------------------------------------

func _open_move_menu() -> void:
	var units: Array = []
	for i in main.selected:
		if camp.sim.alive[i] == 1 and org.group_of(i) != "navy":
			units.append(i)
	if units.is_empty():
		main._say("Ships stay with the fleet: select ground units or aircraft to move them to another company.")
		return
	for c in _menu.get_children():
		c.queue_free()
	_menu.clear()
	_menu_actions.clear()
	var next := [0]
	var add_item := func(menu: PopupMenu, text: String, action: String, node: int) -> void:
		menu.add_item(text, next[0])
		_menu_actions[next[0]] = [action, node]
		next[0] += 1
	for b in org.children(0):
		var bm := PopupMenu.new()
		bm.id_pressed.connect(_on_menu)
		for bn in org.children(b):
			var cm := PopupMenu.new()
			cm.id_pressed.connect(_on_menu)
			for co in org.children(bn):
				add_item.call(cm, "%s  (%d)" % [org.name_of(co), org.units_in(co).size()], "to", co)
			cm.add_separator()
			add_item.call(cm, "New company in %s" % org.name_of(bn), "new_company", bn)
			bm.add_submenu_node_item(org.name_of(bn), cm)
		bm.add_separator()
		add_item.call(bm, "New battalion in %s" % org.name_of(b), "new_battalion", b)
		_menu.add_submenu_node_item(org.name_of(b), bm)
	_menu.add_separator()
	add_item.call(_menu, "New brigade", "new_brigade", 0)
	_menu.position = Vector2i(get_global_mouse_position()) + Vector2i(0, -10)
	_menu.reset_size()
	_menu.position.y -= _menu.size.y
	_menu.popup()


func _on_menu(id: int) -> void:
	if not _menu_actions.has(id):
		return
	var a: Array = _menu_actions[id]
	var target: int = a[1]
	match a[0]:
		"new_company":
			target = org.add_company(target)
		"new_battalion":
			target = org.add_company(org.add_battalion(target))
		"new_brigade":
			target = org.add_company(org.add_battalion(org.add_brigade()))
	move_selected_to(target)


func move_selected_to(company: int) -> int:
	var n := 0
	for i in main.selected:
		if camp.sim.alive[i] == 1 and org.group_of(i) != "navy":
			org.assign(i, company)
			n += 1
	if n > 0:
		main._say("%d moved to %s." % [n, org.full_name(company)])
		at = company
		tab = "all" if tab == "navy" else tab
	refresh()
	return n


func _disband_here() -> void:
	var parent: int = org.nodes[at].parent
	var nm := org.name_of(at)
	if org.disband(at):
		main._say("%s disbanded." % nm)
		at = parent
	refresh()
