class_name Hud
extends Control
## The in-battle interface, laid out as one dock along the bottom of the screen:
##   - a stats strip above it (battle clock, objectives, Red Army strength and timers, your
##     combat personnel)
##   - support tiles (A-10s, M777 guns, reinforcements, FOB building): click one to use it
##   - unit cards with pixel portraits, tabs for All / Ground / Air, and the hotkey number
##   - the selection panel with the command buttons
##   - the minimap with its legend, view direction, scale, zoom buttons and FOB build button
## Plus pause, settings, controls and end-of-battle panels. Developer stats toggle with F4.

const DOCK_H := 168.0
const GAP := 6.0
const CARD_W := 96.0
const SUPPORT_W := 112.0

const CONTROLS := [
	["Left click / drag a box", "Select units"],
	["Shift + click", "Add to the selection"],
	["Right click", "Move (infantry, Humvee, Stryker, PLS) / fly (Black Hawk, Chinook)"],
	["Right click + drag", "Draw a line or loop: soldiers spread out along it"],
	["Right click a transport", "Board it: Black Hawk 2 squads, Stryker 2 squads, Chinook 5 squads"],
	["U (Black Hawk hovering)", "Fast-rope: the troops slide down without it landing"],
	["Right click a pallet", "PLS selected: load it.  Chinook selected: sling it"],
	["", "Chinook also takes 2 Humvees, or 1 Humvee + 3 squads"],
	["L", "Helicopter: switch land / hover mode"],
	["K (or right click the M777)", "Chinook: sling-load the M777. Its gun crew boards first (one squad's place)"],
	["Right click + drag (gun slung)", "Set the M777 down where you press; the drag points the barrel"],
	["Right click the M777", "Gun crew selected: man the gun (idle crew near it man it anyway)"],
	["Right click a Red FOB wall or gate", "Engineers selected: blow a breach in it (6 s to plant, 5 s fuse)"],
	["U", "Unload the selected transport (a hovering helicopter lands first); Chinook with the gun: set it down here"],
	["1 - 9, 0", "Select units by the number on their card"],
	["V, then drag a line", "A-10 gun run along the line (click: a short run on a spot)"],
	["Right click (A-10 selected)", "The A-10 flies there and circles it until it needs fuel or ammo"],
	["X", "A-10: force stay — keeps circling past bingo fuel until it only just has enough to get home"],
	["Click the M777 (or its card)", "Select the gun; then G to fire. T: switch repeat fire / single shot"],
	["G, then left click", "M777 fire mission: every manned gun that can reach (gun crews selected: just theirs; gun card: just that gun)"],
	["C", "Cancel the fire mission"],
	["H", "Hold (stop moving)"],
	["WASD / arrows / screen edge", "Pan the camera"],
	["Mouse wheel", "Zoom (zoom out to see district names)"],
	["Q  E", "Rotate the camera 90 degrees"],
	["Minimap", "Click or drag to jump the camera"],
	["Esc", "Cancel a call for fire / pause"],
	["F1  F4", "This list / developer stats"],
	["B", "Reinforcements: pick a new unit (one every 2 minutes)"],
	["F", "Build menu (needs engineers): FOB walls, barracks, shed, runway"],
	["R (while placing)", "Rotate a building 90 degrees"],
	["Space  F2  R", "Dev: Red counterattack now, +10 kills, restart"],
]

var game: Node

# Used by main.gd
var info: Label
var squads_label: Label
var messages: Label

var _drag_rect := Rect2()
var _show_drag := false
var _msgs: Array = []          # [text, time_left]
var _formation: Array = []     # [screen_pos, color] per soldier slot
var _trail := PackedVector2Array()
var _overlay: Array = []       # [points, color, closed, width] (artillery)

var _stats := {}               # name -> value Label in the stats strip
var _mapping: Label
var _support := {}             # id -> {panel, value, dot, name}
var _tabs := {}                # tab id -> Button (see TABS)
var _tab := "all"
var _selected_count: Label
var _roster: HBoxContainer
var _roster_scroll: ScrollContainer
var _build_panel: PanelContainer
var _build_info: Label
var _hint: Label
var _sel_chip: Label
var _setup: MissionSetup
var _reinforce_panel: PanelContainer
var _airdrop_panel: PanelContainer
var _reinforce_info: Label
var _reinforce_list: VBoxContainer
var _cards: Array = []         # {unit, panel, status, pips, line, kind, title, bar, key}
var _detail: VBoxContainer
var _detail_title: Label
var _buttons := {}
var _minimap: Minimap
var _view_label: Label
var _debug_panel: PanelContainer
var _dim: ColorRect
var _pause_panel: PanelContainer
var _settings: SettingsPanel
var _help_panel: PanelContainer
var _end_panel: PanelContainer
var _end_title: Label
var _end_stats: Label
var _portraits: Portraits
var _dock: HBoxContainer
var _tick := 0.0
var _cards_built := false
var _shown_reinforcements := -1
var _building_cards := false
var _order_dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	_portraits = Portraits.new()
	add_child(_portraits)

	_build_dock()
	_build_corner_buttons()
	_build_debug()

	messages = UiTheme.label("", 17, UiTheme.TEXT, true)
	messages.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	messages.grow_horizontal = Control.GROW_DIRECTION_BOTH
	messages.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	messages.offset_top = 14
	add_child(messages)

	_build_overlays()
	_build_build_menu()
	_build_airdrop_menu()
	_hint = UiTheme.label("", 15, UiTheme.ACCENT, true)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -(DOCK_H + 84.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


# --- Layout -------------------------------------------------------------------

func _panel(bg := UiTheme.BG, parent: Node = self) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel_box(bg))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _tight(bg := UiTheme.BG, border := UiTheme.BORDER, pad := 6) -> StyleBoxFlat:
	var b := UiTheme.panel_box(bg, border)
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b


func _build_dock() -> void:
	## Everything along the bottom, in one row: support | cards | selection | minimap
	var dock := HBoxContainer.new()
	_dock = dock
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_left = GAP
	dock.offset_right = -GAP
	dock.offset_bottom = -GAP
	dock.add_theme_constant_override("separation", int(GAP))
	dock.alignment = BoxContainer.ALIGNMENT_END
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dock)

	# Left column: stats strip on top of the support tiles
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", int(GAP))
	left.size_flags_vertical = Control.SIZE_SHRINK_END
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(left)
	_build_stats(left)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", int(GAP))
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(low)
	_build_support(low)
	_build_roster(low)

	# Selection column: hint chip above the panel
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", int(GAP))
	mid.size_flags_vertical = Control.SIZE_SHRINK_END
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(mid)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER_DIM, 5))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(chip)
	_sel_chip = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	chip.add_child(_sel_chip)
	_build_detail(mid)

	_build_minimap(dock)


func _build_stats(parent: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER, 6))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	for d in [["clock", "clock", UiTheme.TEXT, "Battle time"],
			["obj", "flag", UiTheme.TEXT, "Objectives taken back"],
			["troops", "enemy", Color(1.0, 0.45, 0.40), "Red Army riflemen"],
			["tanks", "tank", Color(1.0, 0.45, 0.40), "Red tanks"],
			["aa", "aa", Color(1.0, 0.62, 0.25), "Red anti-air"],
			["unit", "plus", UiTheme.TEXT_DIM, "Next Red unit arrives in"],
			["grow", "grow", UiTheme.TEXT_DIM, "The Red FOB grows in"],
			["attack", "attack", UiTheme.WARN, "Next Red counterattack in"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		item.tooltip_text = d[3]
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(item)
		item.add_child(UiIcon.make(d[1], d[2]))
		var v := UiTheme.label("", 14, UiTheme.TEXT, false, true)
		item.add_child(v)
		_stats[d[0]] = v
	for d in [["ammo", "ammo", Color(0.95, 0.80, 0.35), "FOB stock: rounds (rifles, machine guns, the A-10's cannon)"],
			["shells", "shell", Color(0.85, 0.80, 0.55), "FOB stock: 155 mm shells for the M777"],
			["fuel", "fuel", Color(0.55, 0.80, 1.0), "FOB stock: fuel, gallons (A-10 refuels)"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		item.tooltip_text = d[3]
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(item)
		item.add_child(UiIcon.make(d[1], d[2]))
		var v := UiTheme.label("", 14, UiTheme.TEXT, false, true)
		item.add_child(v)
		_stats[d[0]] = v
	var pers := UiTheme.label("COMBAT PERSONNEL", 12, UiTheme.TEXT_DIM)
	h.add_child(pers)
	var pv := UiTheme.label("", 14, UiTheme.TEXT, false, true)
	h.add_child(pv)
	_stats["personnel"] = pv
	_mapping = UiTheme.label("", 12, UiTheme.WARN)
	h.add_child(_mapping)


func _build_support(parent: Control) -> void:
	## Tiles for the things you call on rather than command directly
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	grid.size_flags_vertical = Control.SIZE_SHRINK_END
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)
	for d in [["a10", "jet", "A-10", "Gun run (V): drag a line across the target"],
			["m777", "gun", "M777", "Fire mission (G): click a target. While firing: cease fire (C)"],
			["reinforce", "plus", "Reinforce", "Call in a new unit (B)"],
			["fob", "build", "FOB", "Build menu (F): walls, barracks, shed, runway"],
			["airdrop", "chute", "Airdrop", "Call in a supply pallet: ammo, shells or fuel. Fetch it with a PLS or a Chinook"]]:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(SUPPORT_W, (DOCK_H - GAP) * 0.5)
		p.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER, 7))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = d[3]
		p.gui_input.connect(_on_support_input.bind(d[0]))
		grid.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		v.add_child(top)
		top.add_child(UiIcon.make(d[1], UiTheme.TEXT))
		var name_l := UiTheme.label(d[2], 14, UiTheme.TEXT, false, true)
		top.add_child(name_l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var val := UiTheme.label("", 13, UiTheme.TEXT_DIM)
		row.add_child(val)
		_support[d[0]] = {"panel": p, "value": val, "dot": dot}


func _build_roster(parent: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER, 6))
	p.custom_minimum_size = Vector2(0, DOCK_H)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	v.add_child(head)
	for t in TABS:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_tab = t
			_order_dirty = true
			_update_cards())
		head.add_child(b)
		_tabs[t] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_selected_count = UiTheme.label("Selected 0", 13, UiTheme.TEXT_DIM)
	head.add_child(_selected_count)
	var line := ColorRect.new()
	line.color = UiTheme.BORDER_DIM
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	_roster_scroll = ScrollContainer.new()
	_roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_roster_scroll)
	_roster = HBoxContainer.new()
	_roster.add_theme_constant_override("separation", 5)
	_roster_scroll.add_child(_roster)


func _build_detail(parent: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER, 8))
	p.custom_minimum_size = Vector2(420, DOCK_H)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	_detail_title = UiTheme.label("", 14, UiTheme.ACCENT, false, true)
	v.add_child(_detail_title)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail)
	_build_commands(v)


func _build_commands(parent: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	parent.add_child(h)
	var defs := [
		["hold", "Hold H", "Stop moving"],
		["board", "Board", "Selected infantry (or the Humvee) go to the selected or nearest transport"],
		["unload", "Unload U", "Everyone climbs out (a hovering helicopter lands first)"],
		["hover", "Hover L", "Switch the selected helicopter between landing and hovering at its destination"],
		["a10", "A-10 V", "Gun run: drag a line across the target. The only thing besides artillery that kills tanks"],
		["stay", "Stay X", "Force stay: the A-10 keeps circling past bingo fuel, until it only just has enough to get home"],
		["fire", "Fire G", "M777 fire mission: pick a target inside its field of fire. While it's firing: cancel (C)"],
		["mode", "Repeat T", "Switch the M777 between repeat fire and a single shot per fire mission"],
	]
	for d in defs:
		var b := UiTheme.button(d[1], d[2])
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_command.bind(d[0]))
		h.add_child(b)
		_buttons[d[0]] = b


func _build_minimap(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(GAP))
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(col)
	# Zoom buttons and the FOB build button
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	col.add_child(top)
	var zin := UiTheme.button("+", "Zoom in")
	zin.custom_minimum_size = Vector2(28, 26)
	zin.pressed.connect(func(): game.camera.zoom(0.8))
	top.add_child(zin)
	var zout := UiTheme.button("−", "Zoom out")
	zout.custom_minimum_size = Vector2(28, 26)
	zout.pressed.connect(func(): game.camera.zoom(1.25))
	top.add_child(zout)
	var rot := UiTheme.button("⟳", "Rotate the view (Q / E)")
	rot.custom_minimum_size = Vector2(28, 26)
	rot.pressed.connect(func(): game.camera.rotate_step(1))
	top.add_child(rot)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var fob := UiTheme.button("FOB Build · F", "FOB walls, barracks, maintenance shed, runway (needs engineers)")
	fob.add_theme_font_size_override("font_size", 13)
	fob.pressed.connect(toggle_build_menu)
	top.add_child(fob)
	_buttons["build"] = fob

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _tight(UiTheme.BG, UiTheme.BORDER, 5))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	# Legend
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 4)
	v.add_child(legend)
	for d in [["m_infantry", Minimap.C_INFANTRY, "Infantry"], ["m_vehicle", Minimap.C_VEHICLE, "Vehicle"],
			["m_air", Minimap.C_AIR, "Air"], ["m_enemy", Minimap.C_ENEMY, "Enemy"]]:
		legend.add_child(UiIcon.make(d[0], d[1], 12))
		var l := UiTheme.label(d[2] + "  ", 12, UiTheme.TEXT_DIM)
		legend.add_child(l)
	_minimap = Minimap.new()
	v.add_child(_minimap)


func _build_corner_buttons() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.offset_top = GAP
	h.offset_right = -GAP
	h.add_theme_constant_override("separation", 4)
	add_child(h)
	var help := UiTheme.button("Controls · F1")
	help.add_theme_font_size_override("font_size", 13)
	help.pressed.connect(toggle_help)
	h.add_child(help)
	var menu := UiTheme.button("Menu · Esc")
	menu.add_theme_font_size_override("font_size", 13)
	menu.pressed.connect(toggle_pause)
	h.add_child(menu)


func _build_debug() -> void:
	_debug_panel = _panel(Color(0, 0, 0, 0.6))
	_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_debug_panel.offset_top = GAP
	_debug_panel.offset_left = GAP
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	_debug_panel.add_child(v)
	info = UiTheme.label("", 13)
	squads_label = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	v.add_child(info)
	v.add_child(squads_label)


func _build_overlays() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_pause_panel = _centered_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(260, 0)
	_pause_panel.add_child(v)
	var title := UiTheme.label("PAUSED", 24, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for item in [["Resume", toggle_pause], ["Settings", _open_settings], ["Controls", toggle_help],
			["Restart battle", _restart], ["Main menu", _main_menu], ["Quit to desktop", func(): get_tree().quit()]]:
		var b := UiTheme.button(item[0])
		b.pressed.connect(item[1])
		v.add_child(b)

	_settings = SettingsPanel.new()
	_settings.visible = false
	add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.closed.connect(func(): _pause_panel.visible = get_tree().paused)

	_help_panel = _centered_panel()
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	_help_panel.add_child(hv)
	hv.add_child(UiTheme.label("CONTROLS", 22, UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	hv.add_child(grid)
	for c in CONTROLS:
		grid.add_child(UiTheme.label(c[0], 14, UiTheme.ACCENT))
		grid.add_child(UiTheme.label(c[1], 14))
	var close := UiTheme.button("Close (F1)")
	close.pressed.connect(toggle_help)
	hv.add_child(close)

	_reinforce_panel = _centered_panel()
	_reinforce_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rv.custom_minimum_size = Vector2(470, 0)
	_reinforce_panel.add_child(rv)
	rv.add_child(UiTheme.label("CALL IN REINFORCEMENTS", 22, UiTheme.ACCENT))
	_reinforce_info = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	_reinforce_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_reinforce_info)
	_reinforce_list = VBoxContainer.new()
	_reinforce_list.add_theme_constant_override("separation", 6)
	rv.add_child(_reinforce_list)
	var rclose := UiTheme.button("Close (B)")
	rclose.pressed.connect(toggle_reinforcements)
	rv.add_child(rclose)

	_end_panel = _centered_panel()
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 10)
	ev.custom_minimum_size = Vector2(360, 0)
	_end_panel.add_child(ev)
	_end_title = UiTheme.label("", 30, UiTheme.ACCENT)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(_end_title)
	_end_stats = UiTheme.label("", 15)
	ev.add_child(_end_stats)
	var again := UiTheme.button("Play again")
	again.pressed.connect(_restart)
	ev.add_child(again)
	var menu := UiTheme.button("Main menu")
	menu.pressed.connect(_main_menu)
	ev.add_child(menu)


func _centered_panel() -> PanelContainer:
	var p := _panel(UiTheme.BG_SOLID)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	return p


# --- Public API (main.gd) ---------------------------------------------------

func push_message(text: String) -> void:
	if game != null and game._autotest:
		print("MSG %5.1f: %s" % [game._test_clock, text])
	_msgs.append([text, 3.5])


func _build_airdrop_menu() -> void:
	_airdrop_panel = _panel(UiTheme.BG_SOLID)
	_airdrop_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_airdrop_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_airdrop_panel.offset_left = GAP
	_airdrop_panel.offset_bottom = -(DOCK_H + 60.0)
	_airdrop_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.custom_minimum_size = Vector2(420, 0)
	_airdrop_panel.add_child(v)
	v.add_child(UiTheme.label("AIRDROP  (a C-130 drops it on a parachute)", 15, UiTheme.ACCENT, false, true))
	for k in ["ammo", "shells", "fuel"]:
		var info: Dictionary = SupplyPallet.KINDS[k]
		var b := UiTheme.button("%s  —  %s %s" % [info.name, Fob._thousands(info.amount), info.unit])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_airdrop_panel.visible = false
			game.begin_airdrop(k))
		v.add_child(b)
	var note := UiTheme.label("Then click where it should land (shift-click for more). It lands where the wind takes it: fetch it with a PLS (right-click the pallet) or sling it with a Chinook, and bring it inside the FOB walls.", 11, UiTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


func toggle_airdrop() -> void:
	_airdrop_panel.visible = not _airdrop_panel.visible


func build_menu_open() -> bool:
	return _build_panel.visible


func toggle_build_menu() -> void:
	if not game.has_engineers():
		push_message("You need an engineer squad to build (call one in with B)")
		_build_panel.visible = false
		return
	_build_panel.visible = not _build_panel.visible
	if _build_panel.visible:
		var todo: Array = game.fob.unfinished()
		var work := 0.0
		for p in todo:
			work += p.work_needed - p.work
		var crews := 0
		for sq in game.squads:
			if sq.kind == "engineer" and not sq.soldiers.is_empty():
				crews += sq.soldiers.size()
		var eta := work / maxf(1.0, crews)
		_build_info.text = "%d pieces waiting, about %d:%02d of work for your %d engineers.\nEngineers build whenever you're not moving them." % [todo.size(), floori(eta / 60.0), floori(fmod(eta, 60.0)), crews]


func set_hint(text: String) -> void:
	_hint.text = text


func show_setup() -> void:
	_setup = MissionSetup.new()
	add_child(_setup)
	_setup.build(game)
	_setup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_setup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_setup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dim.visible = true
	_setup.deployed.connect(func(loadout: Dictionary, zone: int):
		_setup.queue_free()
		_setup = null
		_dim.visible = false
		game.start_mission(loadout, zone))


func reinforcements_open() -> bool:
	return _reinforce_panel.visible


func toggle_reinforcements() -> void:
	_reinforce_panel.visible = not _reinforce_panel.visible
	if _reinforce_panel.visible:
		_refresh_reinforcements()


func _refresh_reinforcements() -> void:
	for k in _reinforce_list.get_children():
		k.queue_free()
	_shown_reinforcements = game.reinforcements
	_reinforce_info.text = _reinforce_text()
	for opt in game.REINFORCEMENTS:
		var why: String = game.reinforcement_blocked(opt.id)
		var note: String = game.reinforcement_note(opt.id)
		var b := UiTheme.button("%s  —  %s" % [opt.name, note if note != "" else opt.desc] if why == "" else "%s  —  %s" % [opt.name, why])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.disabled = why != ""
		b.pressed.connect(func():
			if game.call_reinforcement(opt.id):
				if game.reinforcements <= 0:
					_reinforce_panel.visible = false
				else:
					_refresh_reinforcements())
		_reinforce_list.add_child(b)


func _reinforce_text() -> String:
	var n: int = game.reinforcements
	var wait: float = game.reinforce_in
	var where: String = game.zone_name(game.start_zone) if game.start_zone >= 0 else "a corner of the map"
	return "%d available. The next one in %d:%02d.\n%s.\nNew units arrive at your start point (%s). Walk, drive or fly them to the FOB, or go and pick them up." % [n, floori(wait / 60.0), floori(fmod(wait, 60.0)), game.limits_text(), where]


func set_drag(rect: Rect2, show: bool) -> void:
	_drag_rect = rect.abs()
	_show_drag = show
	queue_redraw()


func set_overlay(items: Array) -> void:
	_overlay = items
	queue_redraw()


func set_formation(marks: Array, trail: PackedVector2Array) -> void:
	_formation = marks
	_trail = trail
	queue_redraw()


func toggle_pause() -> void:
	if _end_panel.visible:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	_dim.visible = paused
	_pause_panel.visible = paused
	_settings.visible = false
	_help_panel.visible = false


func toggle_help() -> void:
	_help_panel.visible = not _help_panel.visible
	_pause_panel.visible = get_tree().paused and not _help_panel.visible
	_dim.visible = get_tree().paused or _help_panel.visible


func toggle_debug() -> void:
	Settings.show_debug = not Settings.show_debug
	Settings.save_settings()


func show_end(won: bool, stats: String) -> void:
	_end_title.text = "ROOF HELD" if won else "ALL UNITS LOST"
	_end_title.label_settings.font_color = UiTheme.GOOD if won else UiTheme.BAD
	_end_stats.text = stats
	_dim.visible = true
	_end_panel.visible = true


func _open_settings() -> void:
	_pause_panel.visible = false
	_settings.visible = true


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	# While paused the game doesn't get input, so Esc / F1 are handled here
	if not get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _settings.visible:
				_settings.visible = false
				_pause_panel.visible = true
			elif _help_panel.visible:
				toggle_help()
			else:
				toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			toggle_help()
			get_viewport().set_input_as_handled()


func _build_build_menu() -> void:
	_build_panel = _panel(UiTheme.BG_SOLID)
	_build_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_panel.offset_right = -GAP
	_build_panel.offset_bottom = -(Minimap.MAP_H + 90.0)
	_build_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.custom_minimum_size = Vector2(380, 0)
	_build_panel.add_child(v)
	v.add_child(UiTheme.label("BUILD  (engineers do the work)", 15, UiTheme.ACCENT, false, true))
	v.add_child(UiTheme.label("Shift-click when placing: build it first. Right-click a planned piece with engineers: build that now.", 11, UiTheme.TEXT_DIM))
	for item in [["walls", "FOB walls", "Drag a rectangle. Catwalk, ramps and gates included"],
			["barracks", "Barracks", "Inside the walls. Refills squads and crews; each one supports 5 squads"],
			["shed", "Maintenance shed", "Inside the walls. Repairs vehicles and helicopters; each one supports 5 vehicles"],
			["tower", "Watch tower", "Anywhere, on your wall line too. Right-click it with infantry: 4 men shoot from the top"],
			["runway", "Runway", "Anywhere open (96 x 14 m). 2 aircraft slots"]]:
		var b := UiTheme.button("%s  —  %s" % [item[1], item[2]])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_build_panel.visible = false
			game.begin_build(item[0]))
		v.add_child(b)
	_build_info = UiTheme.label("", 12, UiTheme.TEXT_DIM)
	_build_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_build_info)


# --- Commands ---------------------------------------------------------------

func _on_command(cmd: String) -> void:
	match cmd:
		"hold":
			game._on_key(KEY_H)
		"board":
			if _sling_mode():
				game._on_key(KEY_K)
				return
			var riders: Array = []
			for v in game._selected_vehicles():
				if v is Humvee:
					riders.append(v)
			if not game._selected().is_empty() or not riders.is_empty():
				game._order_board(game._selected(), null, riders)
		"unload":
			game._on_key(KEY_U)
		"hover":
			game._on_key(KEY_L)
		"a10":
			game._on_key(KEY_V)
		"build":
			toggle_build_menu()
		"stay":
			game._on_key(KEY_X)
		"mode":
			game._on_key(KEY_T)
		"fire":
			if _any_mission():
				game._on_key(KEY_C)
			else:
				game._on_key(KEY_G)


func _on_support_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	match id:
		"airdrop":
			toggle_airdrop()
		"a10":
			game._on_key(KEY_V)
		"m777":
			_on_command("fire")
		"reinforce":
			toggle_reinforcements()
		"fob":
			toggle_build_menu()


# --- Per-frame updates --------------------------------------------------------

func _process(delta: float) -> void:
	for i in range(_msgs.size() - 1, -1, -1):
		_msgs[i][1] -= delta
		if _msgs[i][1] <= 0.0:
			_msgs.remove_at(i)
	var lines: PackedStringArray = []
	for m in _msgs:
		lines.append(m[0])
	messages.text = "\n".join(lines)
	_debug_panel.visible = Settings.show_debug and _setup == null
	_dock.visible = game != null and game.state != "setup"

	# Once the mission has started (a force with no infantry at all, say 7 A-10s, still gets its cards)
	if game == null or game.state == "setup" or (game.squads.is_empty() and game.vehicles.is_empty() and game.guns.is_empty()):
		return
	if not _cards_built:
		_build_cards()
		_minimap.setup(game)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.15
	_update_stats()
	_update_support()
	_update_cards()
	_update_detail()
	_update_commands()


static func _mmss(t: float) -> String:
	t = maxf(t, 0.0)
	return "%d:%02d" % [floori(t / 60.0), floori(fmod(t, 60.0))]


func _update_stats() -> void:
	var army: RedArmy = game.enemy
	_stats.clock.text = _mmss(game.battle_time)
	_stats.obj.text = "%d / %d" % [army.objectives_held(), army.objectives.size()]
	var aa: int = army.aa_count()
	_stats.troops.text = str(army.alive.size())
	_stats.tanks.text = str(army.tanks.size() - aa)
	_stats.aa.text = str(aa)
	var fob_mode: bool = army.red_fob != null and not army.legacy_objectives
	_stats.unit.text = _mmss(army.next_unit_in) if fob_mode else "—"
	_stats.grow.text = "full" if not fob_mode or army.red_fob.steps_done >= RedFob.STEPS.size() else _mmss(army.grow_in)
	_stats.attack.text = _mmss(army.next_wave_in)
	var people := 0
	for sq in game.squads:
		people += sq.soldiers.size()
	_stats.personnel.text = str(people)
	var st: Dictionary = game.fob.stock
	_stats.ammo.text = Fob._thousands(st.ammo)
	_stats.shells.text = str(st.shells)
	_stats.fuel.text = Fob._thousands(st.fuel)
	var lvl: Level = game.level
	_mapping.text = "" if lvl.nav_done >= lvl.nav_total else "Mapping city %d%%" % int(100.0 * lvl.nav_done / maxf(1.0, lvl.nav_total))
	if _reinforce_panel.visible:
		if game.reinforcements != _shown_reinforcements:
			_refresh_reinforcements()
		else:
			_reinforce_info.text = _reinforce_text()


func _set_support(id: String, text: String, state: String) -> void:
	## state: ready (green), busy (amber), alert (amber border), off (grey)
	var t: Dictionary = _support[id]
	(t.value as Label).text = text
	var c := UiTheme.GOOD
	match state:
		"busy", "alert":
			c = UiTheme.WARN
		"off":
			c = Color(0.35, 0.38, 0.42)
	(t.dot as ColorRect).color = c
	(t.value as Label).label_settings.font_color = UiTheme.TEXT if state != "off" else UiTheme.TEXT_DIM
	var border := UiTheme.ACCENT if state == "alert" else UiTheme.BORDER
	(t.panel as PanelContainer).add_theme_stylebox_override("panel", _tight(Color(0.16, 0.14, 0.09, 0.92) if state == "alert" else UiTheme.BG, border, 7))


func _update_support() -> void:
	var jets: int = 0
	var ready: int = 0
	for a in game.a10s:
		if not a.destroyed:
			jets += 1
			if a.is_ready():
				ready += 1
	if jets == 0:
		_set_support("a10", "none", "off")
	else:
		_set_support("a10", "%d/%d Ready" % [ready, jets], "ready" if ready > 0 else "busy")
	var guns: int = game.guns.size()
	var loaded := 0
	for g in game.guns:
		if g.crew_count() > 0 and g.slung_by == null and g.loaded:
			loaded += 1
	if guns == 0:
		_set_support("m777", "none", "off")
	elif _any_mission():
		_set_support("m777", "%d/%d Firing" % [loaded, guns], "alert")
	else:
		_set_support("m777", "%d/%d Ready" % [loaded, guns], "ready" if loaded > 0 else "busy")
	var n: int = game.reinforcements
	if n > 0:
		_set_support("reinforce", "%d Ready · B" % n, "alert")
	else:
		_set_support("reinforce", "in " + _mmss(game.reinforce_in), "busy")
	var falling := 0
	var waiting := 0
	for pn in get_tree().get_nodes_in_group("pallets"):
		if pn.state == "falling":
			falling += 1
		elif pn.state == "ground":
			waiting += 1
	if waiting > 0:
		_set_support("airdrop", "%d to fetch" % waiting, "alert")
	elif falling > 0:
		_set_support("airdrop", "%d coming down" % falling, "busy")
	else:
		_set_support("airdrop", "Request", "ready")
	if not game.has_engineers():
		_set_support("fob", "no engineers", "off")
	else:
		var total := 0
		var built := 0
		for pc in game.fob.pieces:
			if is_instance_valid(pc) and pc.state != "removed":
				total += 1
				if pc.is_built():
					built += 1
		if total == 0:
			_set_support("fob", "Plan walls · F", "ready")
		else:
			_set_support("fob", "%d/%d built" % [built, total], "ready" if built >= total else "busy")


# --- Unit cards ---------------------------------------------------------------

func _build_cards() -> void:
	_building_cards = true
	for sq in game.squads:
		add_unit_card(sq)
	for v in game.vehicles:
		add_unit_card(v)
	for g in game.guns:
		add_unit_card(g)
	_building_cards = false
	_cards_built = true
	_order_dirty = true


func add_unit_card(unit) -> void:
	## A card for a unit (also called when reinforcements arrive)
	if not _cards_built and not _building_cards:
		return   # cards are built all at once on the first frame
	if unit is Squad and unit.kind == "gun_crew":
		return   # gun crews go with their M777: its card shows them
	var kind := "squad"
	var title := ""
	var color := Color.WHITE
	if unit is Squad:
		title = unit.squad_name.to_upper()
		color = unit.color
	elif unit is Artillery:
		kind = "gun"
		title = unit.display_name.to_upper()
		color = Color(0.78, 0.68, 0.40)
	elif unit is A10:
		kind = "jet"
		title = unit.callsign.to_upper()
		color = Color(0.60, 0.72, 0.90)
	elif unit is Helicopter:
		kind = "heli"
		title = unit.display_name.to_upper()
		color = Color(0.80, 0.70, 0.40) if unit is Chinook else Color(0.55, 0.65, 0.80)
	else:
		kind = "ground"
		title = unit.display_name.to_upper()
		color = Color(0.40, 0.70, 0.45) if unit is Stryker else (Color(0.85, 0.72, 0.35) if unit is FuelTruck else Color(0.35, 0.75, 0.35))
	_add_card(unit, title, color, kind)
	_order_dirty = true


const KIND_ICON := {"squad": "squad", "ground": "vehicle", "heli": "heli", "jet": "jet", "gun": "gun"}


func _add_card(unit, title: String, color: Color, kind: String) -> void:
	## A card: kind icon and hotkey, portrait, name, status, crew pips and a bar
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_box(false))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.custom_minimum_size = Vector2(CARD_W, 0)
	match kind:
		_:
			panel.tooltip_text = "%s: click to select (shift: add, double-click: jump the camera)" % title
	panel.gui_input.connect(_on_card_input.bind(unit, kind))
	_roster.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(UiIcon.make(KIND_ICON.get(kind, "squad"), color, 12))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hsp)
	var key := UiTheme.label("", 11, UiTheme.TEXT_DIM)
	head.add_child(key)
	var pic := TextureRect.new()
	pic.texture = _portraits.texture_for(unit)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(Portraits.SIZE) * 2.0
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var name_l := UiTheme.label(title, 13, UiTheme.TEXT, false, true)
	name_l.clip_text = true
	name_l.custom_minimum_size = Vector2(CARD_W - 12, 0)
	v.add_child(name_l)
	var status := UiTheme.label("", 11, UiTheme.TEXT_DIM)
	status.clip_text = true
	status.custom_minimum_size = Vector2(CARD_W - 12, 0)
	v.add_child(status)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 2)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pips)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.20, 0.23, 0.26)
	bar.add_theme_stylebox_override("background", bg)
	v.add_child(bar)
	var line := UiTheme.label("", 10, UiTheme.TEXT_DIM)   # kept for tooltips and tests
	line.visible = false
	v.add_child(line)
	_cards.append({"unit": unit, "panel": panel, "status": status, "pips": pips, "line": line, "kind": kind,
		"title": title, "bar": bar, "key": key})


func _card_box(selected: bool) -> StyleBoxFlat:
	var b := _tight(Color(0.17, 0.17, 0.12, 0.97) if selected else UiTheme.BG_CARD, UiTheme.ACCENT if selected else UiTheme.BORDER_DIM, 5)
	if selected:
		b.set_border_width_all(2)
	return b


func _on_card_input(event: InputEvent, unit, kind: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.double_click:
		# Double-click: just this one, and the camera jumps to it
		game._select_only([unit])
		game.camera.focus = _unit_position(unit, kind)
	elif event.shift_pressed or unit.selected:
		# Shift-click adds or drops it; clicking a card that's already selected drops it
		unit.set_selected(not unit.selected)
	else:
		game._select_only([unit])


func _unit_position(unit, kind: String) -> Vector3:
	if kind == "squad":
		var active: Array = unit.active_soldiers()
		if active.is_empty():
			var ride = game.carrier_of(unit)
			return ride.global_position if ride != null else game.camera.focus
		return active[0].global_position
	return unit.global_position


func _members(unit, kind: String) -> Array:
	if kind == "gun":
		return unit.manned
	return unit.soldiers if kind == "squad" else unit.crew.squad.soldiers


func _member_slots(unit, kind: String) -> int:
	match kind:
		"squad":
			return unit.max_members
		"gun":
			return Artillery.SEATS.size()
		_:
			return unit.crew.seats.size()


const TABS := ["all", "ground", "mech", "air", "artillery"]
const TAB_NAMES := {"all": "All", "ground": "Ground", "mech": "Mech", "air": "Air", "artillery": "Artillery"}


func _group(c: Dictionary) -> String:
	## Which tab a card belongs to: infantry, vehicles, aircraft, or the guns and their crews
	match c.kind:
		"squad":
			return "artillery" if c.unit.kind == "gun_crew" else "ground"
		"ground":
			return "mech"
		"heli", "jet":
			return "air"
		"gun":
			return "artillery"
	return "ground"


func _in_tab(c: Dictionary) -> bool:
	return _tab == "all" or _group(c) == _tab


func _is_gone(c: Dictionary) -> bool:
	## Dead and gone: its card comes off the list (an A-10 shot down hands over to its pilot's card)
	var u = c.unit
	if not is_instance_valid(u):
		return true
	match c.kind:
		"squad":
			return u.soldiers.is_empty()
		"ground", "heli":
			return u.destroyed
		"jet":
			return u.destroyed or u.state == "crash"
	return false


func _set_bar(bar: ProgressBar, value: float, max_value: float, color: Color) -> void:
	bar.max_value = maxf(max_value, 0.001)
	bar.value = value
	var f := StyleBoxFlat.new()
	f.bg_color = color
	bar.add_theme_stylebox_override("fill", f)


func _health_color(f: float) -> Color:
	return UiTheme.GOOD if f > 0.6 else (UiTheme.WARN if f > 0.3 else UiTheme.BAD)


func _update_cards() -> void:
	for i in range(_cards.size() - 1, -1, -1):
		if _is_gone(_cards[i]):
			(_cards[i].panel as Control).queue_free()
			_cards.remove_at(i)
			_order_dirty = true
	var hot: Array = game.hotkey_units()
	var counts := {"all": _cards.size(), "ground": 0, "mech": 0, "air": 0, "artillery": 0}
	var n_sel := 0
	for c in _cards:
		counts[_group(c)] += 1
	for t in TABS:
		(_tabs[t] as Button).text = "%s %d" % [TAB_NAMES[t], counts[t]]
	for t in _tabs:
		(_tabs[t] as Button).add_theme_color_override("font_color", UiTheme.TEXT if t == _tab else UiTheme.TEXT_DIM)
		(_tabs[t] as Button).add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	if _order_dirty:
		# Hotkey order (squads, then vehicles), guns at the end
		_order_dirty = false
		var order := _cards.duplicate()
		order.sort_custom(func(a, b):
			var ia: int = hot.find(a.unit)
			var ib: int = hot.find(b.unit)
			ia = 1000 + _cards.find(a) if ia < 0 else ia
			ib = 1000 + _cards.find(b) if ib < 0 else ib
			return ia < ib)
		for i in order.size():
			_roster.move_child(order[i].panel, i)
	for c in _cards:
		var unit = c.unit
		var kind: String = c.kind
		(c.panel as Control).visible = _in_tab(c)
		var hk: int = hot.find(unit)
		(c.key as Label).text = str((hk + 1) % 10) if hk >= 0 and hk < 10 else ""
		var members: Array = _members(unit, kind)
		# Health pips: one per slot, grey when the slot is empty
		var pips: HBoxContainer = c.pips
		var slots := _member_slots(unit, kind)
		while pips.get_child_count() < slots:
			var r := ColorRect.new()
			r.custom_minimum_size = Vector2(minf(12.0, (CARD_W - 12.0) / maxf(1.0, slots) - 2.0), 5)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(r)
		for i in slots:
			var r: ColorRect = pips.get_child(i)
			if i < members.size():
				r.color = _health_color(members[i].health / Soldier.MAX_HEALTH)
			else:
				r.color = Color(0.25, 0.28, 0.31)
		var status: Label = c.status
		var line: Label = c.line
		var bar: ProgressBar = c.bar
		var selected := false
		var st_color := UiTheme.TEXT_DIM
		match kind:
			"squad":
				selected = unit.selected
				if members.is_empty():
					status.text = "WIPED OUT"
					st_color = UiTheme.BAD
				elif unit.active_soldiers().is_empty():
					var ride = game.carrier_of(unit)
					status.text = "in the %s" % ride.display_name if ride != null else "aboard"
				else:
					var moving := false
					var manual := false
					for s in unit.active_soldiers():
						moving = moving or s._has_order or s.board_target != null
						manual = manual or s.manual
					var target = unit.get_meta("build_target") if unit.has_meta("build_target") else null
					if unit.kind == "engineer" and target != null and is_instance_valid(target) and not manual and target.state in ["planned", "building"]:
						status.text = "building %s" % target.display_name().to_lower()
						st_color = UiTheme.WARN
					else:
						status.text = "moving" if moving else "holding"
						st_color = UiTheme.GOOD if moving else UiTheme.TEXT_DIM
					# Ammunition: everyone dry, or running low
					var total := 0
					var dry := 0
					for s in members:
						total += s.rounds
						if s.rounds <= 0:
							dry += 1
					if dry == members.size():
						status.text = "OUT OF AMMO"
						st_color = UiTheme.BAD
					elif dry > 0 or total < members.size() * Soldier.CARRY / 4:
						status.text = "low ammo"
						st_color = UiTheme.WARN
				var next: String = "MAX" if unit.is_maxed() else "%d/%d" % [unit.kills_into_level, unit.next_level_at]
				line.text = "Lv %d   kills %d   next %s" % [unit.total_level(), unit.kills, next]
				_set_bar(bar, unit.kills_into_level if not unit.is_maxed() else 1.0, unit.next_level_at if not unit.is_maxed() else 1.0, UiTheme.ACCENT)
			"ground":
				selected = unit.selected
				if unit.destroyed:
					status.text = "DESTROYED"
					st_color = UiTheme.BAD
				elif unit.carried_by != null:
					status.text = "in the Chinook"
				elif unit.crew.count() == 0:
					status.text = "no crew"
					st_color = UiTheme.WARN
				elif unit.board_target != null:
					status.text = "boarding"
				elif unit.fuel <= 0.0:
					status.text = "NO FUEL"
					st_color = UiTheme.BAD
				else:
					status.text = "driving" if unit.driving else ("turning" if unit._turning else "parked")
					st_color = UiTheme.GOOD if unit.driving else UiTheme.TEXT_DIM
					if unit.fuel < unit.fuel_max * 0.2:
						status.text += " · low fuel"
						st_color = UiTheme.WARN
				var extra := ""
				if unit is Stryker:
					var cargo := _cargo_names(unit)
					extra = ("   " + ", ".join(cargo)) if not cargo.is_empty() else ""
				line.text = "Armor %d%%   Fuel %d%%   kills %d%s" % [int(100.0 * unit.hp / unit.max_hp), int(100.0 * unit.fuel / unit.fuel_max), unit.crew.squad.kills, extra]
				_set_bar(bar, unit.hp, unit.max_hp, _health_color(unit.hp / unit.max_hp))
			"heli":
				selected = unit.selected
				if unit.destroyed:
					status.text = "DESTROYED"
					st_color = UiTheme.BAD
				elif unit.fuel <= 0.0:
					status.text = "NO FUEL"
					st_color = UiTheme.BAD
				else:
					status.text = "no crew" if unit.crew.count() == 0 else unit.state_name() + (" · hover" if unit.hover_mode else "")
					if unit.fuel < unit.fuel_max * 0.2:
						status.text += " · low fuel"
						st_color = UiTheme.WARN
				var cargo := _cargo_names(unit)
				line.text = "Armor %d%%   Fuel %d%%   kills %d%s" % [int(100.0 * unit.hp / unit.max_hp), int(100.0 * unit.fuel / unit.fuel_max), unit.crew.squad.kills, ("   " + ", ".join(cargo)) if not cargo.is_empty() else ""]
				_set_bar(bar, unit.hp, unit.max_hp, _health_color(unit.hp / unit.max_hp))
			"jet":
				selected = unit.selected
				status.text = unit.status_text()
				st_color = UiTheme.GOOD if unit.is_ready() else (UiTheme.BAD if unit.destroyed else UiTheme.WARN)
				line.text = "Fuel %d:%02d   runs %d/%d   kills %d" % [floori(unit.fuel / 60.0), floori(fmod(unit.fuel, 60.0)), unit.runs_left, A10.RUNS_PER_SORTIE, unit.kills]
				_set_bar(bar, unit.fuel, maxf(A10.MAX_FUEL, unit.fuel), UiTheme.ACCENT)
			"gun":
				selected = unit.selected
				if unit.slung_by != null:
					status.text = "SLUNG"
					st_color = UiTheme.WARN
				elif unit.crew_count() == 0:
					status.text = "UNMANNED"
					st_color = UiTheme.BAD
				elif unit.shells <= 0:
					status.text = "NO SHELLS"
					st_color = UiTheme.BAD
				elif unit.loaded:
					status.text = "FIRING" if unit.has_mission else "LOADED"
					st_color = UiTheme.WARN if unit.has_mission else UiTheme.GOOD
				else:
					status.text = "reload %ds" % ceili(unit.seconds_to_ready())
					st_color = UiTheme.WARN
				line.text = "Shells %d/%d   Lv %d/%d   %d s/shot   %s   kills %d%s" % [unit.shells, Artillery.MAX_SHELLS, unit.level, Artillery.MAX_LEVEL, int(unit.cycle_time()), "repeat" if unit.repeat else "single shot", unit.kills, "   FIRING" if unit.has_mission else ""]
				var cyc: float = maxf(1.0, unit.cycle_time())
				_set_bar(bar, cyc - unit.seconds_to_ready() if not unit.loaded else cyc, cyc, UiTheme.ACCENT)
		status.label_settings.font_color = st_color
		(c.panel as Control).tooltip_text = "%s — %s\n%s" % [c.title, status.text, line.text]
		if selected:
			n_sel += 1
		(c.panel as PanelContainer).add_theme_stylebox_override("panel", _card_box(selected))
	_selected_count.text = "Selected %d" % n_sel


# --- Selection details --------------------------------------------------------

func _update_detail() -> void:
	var sel: Array = []
	for c in _cards:
		if c.unit.selected:
			sel.append(c)
	for k in _detail.get_children():
		k.queue_free()
	var nkeys := mini(game.hotkey_units().size(), 10)
	var keys := "1" if nkeys <= 1 else ("1–%d" % nkeys if nkeys < 10 else "1–0")
	if sel.is_empty():
		_sel_chip.text = "No selection · click a card · drag a box · keys %s" % keys
		_detail_title.text = "NO SELECTION"
		_detail_title.label_settings.font_color = UiTheme.TEXT_DIM
		_detail.add_child(UiTheme.label("V: A-10 gun run    G: artillery    B: reinforcements\nF: build the FOB    F1: all controls", 12, UiTheme.TEXT_DIM))
		return
	_detail_title.label_settings.font_color = UiTheme.ACCENT
	if sel.size() > 1:
		_sel_chip.text = "%d units selected · right-drag to draw a formation" % sel.size()
		_detail_title.text = "%d UNITS SELECTED" % sel.size()
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 2)
		_detail.add_child(grid)
		for c in sel:
			var members: Array = _members(c.unit, c.kind)
			grid.add_child(UiTheme.label("%s   %d alive" % [c.title, members.size()], 12))
		return
	var c: Dictionary = sel[0]
	var unit = c.unit
	_sel_chip.text = "%s · %s" % [c.title, (c.status as Label).text]
	match c.kind:
		"squad":
			_detail_title.text = unit.squad_name.to_upper() + ("" if unit.kind != "rifle" else " SQUAD")
			var note := ""
			if unit.kind == "engineer":
				note = "Builds whatever you've planned (F) when you're not moving them. %d pieces left." % game.fob.unfinished().size()
			elif unit.kind == "gun_crew":
				var gun = game.gun_of(unit)
				var at_gun: int = 0 if gun == null else gun.crew_count()
				note = "Crews the %s: %d of 4 at the gun. Right-click the gun to man it." % ["M777" if gun == null else gun.display_name, at_gun]
			elif unit.kind == "pilot":
				note = "Ejected pilot. Get him inside the FOB walls."
			if note != "":
				var nl := UiTheme.label(note, 11, UiTheme.TEXT_DIM)
				nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nl.custom_minimum_size = Vector2(400, 0)
				_detail.add_child(nl)
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 2)
			_detail.add_child(grid)
			var i := 1
			for s in unit.soldiers:
				var role: String = {"engineer": "Engineer", "gun_crew": "Gunner", "pilot": "Pilot"}.get(unit.kind, "Rifleman")
				if unit.kind == "gun_crew":
					role = ["Chief", "Gunner", "Loader", "Ammo", "Crewman"][mini(i - 1, 4)]
				grid.add_child(_health_row("%s%s%s" % [role, "" if unit.kind == "gun_crew" else " %d" % i, " (in)" if s.boarded else (" (gun)" if s.manning != null else "")], s.health, s.rounds))
				i += 1
			var next := "MAX" if unit.is_maxed() else "%d/%d" % [unit.kills_into_level, unit.next_level_at]
			_detail.add_child(UiTheme.label("ACC %s   AMMO %s   WPN %s   ·   Lv %d   next %s" % [_pips(unit.levels["accuracy"]), _pips(unit.levels["ammo"]), _pips(unit.levels["weapons"]), unit.total_level(), next], 12))
		"ground", "heli":
			_detail_title.text = unit.long_name + ("  —  DESTROYED" if unit.destroyed else "")
			var crew: Crew = unit.crew
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 2)
			_detail.add_child(grid)
			for i in crew.seats.size():
				var s := crew.occupant(i)
				if s == null:
					grid.add_child(UiTheme.label("%s — vacant" % crew.role(i), 12, UiTheme.BAD))
				else:
					grid.add_child(_health_row(crew.role(i), s.health))
			grid.add_child(_progress_row("Armor", unit.hp, unit.max_hp))
			grid.add_child(_progress_row("Fuel", unit.fuel, unit.fuel_max))
			var ammo_line: PackedStringArray = []
			if unit.gun_rounds_max > 0:
				ammo_line.append("Gun %s/%s" % [Fob._thousands(unit.gun_rounds), Fob._thousands(unit.gun_rounds_max)])
			if unit.can_rounds_max > 0:
				ammo_line.append("Ammo cans %s/%s rounds (refill squads riding in it)" % [Fob._thousands(unit.can_rounds), Fob._thousands(unit.can_rounds_max)])
			if not ammo_line.is_empty():
				_detail.add_child(UiTheme.label("   ·   ".join(ammo_line), 12, UiTheme.BAD if unit.gun_rounds_max > 0 and unit.gun_rounds <= 0 else UiTheme.TEXT))
			if unit.has_method("missiles_text"):
				_detail.add_child(UiTheme.label("Missiles: %s  (fired automatically at tanks and anti-air; reloaded inside the FOB walls)" % unit.missiles_text(), 12, UiTheme.BAD if unit.missiles_text().begins_with("0 ") else UiTheme.TEXT))
			if unit.fuel <= 0.0:
				_detail.add_child(UiTheme.label("OUT OF FUEL: send the fuel truck (select it, right-click this one)", 12, UiTheme.BAD))
			if unit is FuelTruck:
				_detail.add_child(UiTheme.label("Tanker: %s" % unit.cargo_text(), 12))
				_detail.add_child(UiTheme.label("Parked, it fills anything stopped within %d m. Right-click a vehicle or landed helicopter to go to it. Fills up from the FOB stock inside the walls." % int(FuelTruck.REACH), 11, UiTheme.TEXT_DIM))
			if unit is Pls:
				_detail.add_child(UiTheme.label("Flatrack: %s (%d/%d)" % [unit.cargo_text(), unit.cargo.size(), Pls.CAPACITY], 12))
				_detail.add_child(UiTheme.label("Right-click a pallet to load it. Stop inside the FOB walls to unload. U: set them down here.", 11, UiTheme.TEXT_DIM))
			if (c.kind == "heli" and unit.squad_capacity > 0) or unit is Stryker:
				var cargo := _cargo_names(unit)
				_detail.add_child(UiTheme.label("Aboard: %s   (holds %s)" % [", ".join(cargo) if not cargo.is_empty() else "nobody", unit.capacity_text()], 12))
			if c.kind == "heli":
				_detail.add_child(UiTheme.label("Mode: %s   (L to switch)" % ("HOVER — stays in the air" if unit.hover_mode else "LAND — sets down on arrival"), 12, UiTheme.TEXT_DIM))
			elif unit is Stryker:
				_detail.add_child(UiTheme.label("Right-click it with infantry selected to load. U unloads.", 12, UiTheme.TEXT_DIM))
			elif unit.carried_by != null:
				_detail.add_child(UiTheme.label("Inside the Chinook. Select it and press U to unload.", 12, UiTheme.TEXT_DIM))
		"gun":
			_detail_title.text = "%s HOWITZER" % unit.display_name.to_upper()
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 2)
			_detail.add_child(grid)
			for i in Artillery.SEATS.size():
				if i < unit.manned.size():
					grid.add_child(_health_row(Artillery.SEATS[i].role, unit.manned[i].health))
				else:
					grid.add_child(UiTheme.label("%s — not at the gun" % Artillery.SEATS[i].role, 12, UiTheme.WARN))
			var state: String = "slung under the Chinook" if unit.slung_by != null else ("loaded" if unit.loaded else "reloading, %d s" % ceili(unit.seconds_to_ready()))
			_detail.add_child(UiTheme.label("%s · %s · %d s per round · Lv %d/%d · kills %d" % [state, "FIRING" if unit.has_mission else "no mission", int(unit.cycle_time()), unit.level, Artillery.MAX_LEVEL, unit.kills], 12))
			_detail.add_child(UiTheme.label("Shells %d/%d (refilled near the FOB, or from a PLS carrying a shell pallet)" % [unit.shells, Artillery.MAX_SHELLS], 12, UiTheme.BAD if unit.shells <= 0 else UiTheme.TEXT))
			_detail.add_child(UiTheme.label("Mode: %s   (T to switch)" % ("REPEAT — keeps firing until you cease fire (C)" if unit.repeat else "SINGLE SHOT — one round per fire mission"), 12, UiTheme.ACCENT if not unit.repeat else UiTheme.TEXT))
			_detail.add_child(UiTheme.label("G, then click a target inside its field of fire.", 11, UiTheme.TEXT_DIM))
		"jet":
			_detail_title.text = "A-10 THUNDERBOLT II  —  %s" % unit.callsign.to_upper()
			_detail.add_child(UiTheme.label("Status: %s" % unit.status_text(), 12))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 2)
			_detail.add_child(grid)
			grid.add_child(_progress_row("Fuel", unit.fuel, maxf(A10.MAX_FUEL, unit.fuel)))
			grid.add_child(_progress_row("Runs", unit.runs_left, A10.RUNS_PER_SORTIE))
			grid.add_child(_progress_row("Armor", unit.hp, A10.MAX_HP))
			if unit.force_stay:
				grid.add_child(UiTheme.label("FORCE STAY ON (X)", 12, UiTheme.ACCENT, false, true))
			var tip := UiTheme.label(("Right-click: orbit there. V: gun run. X: force stay. Lands to rearm (%d s) when Winchester or at bingo fuel." % int(A10.REARM_TIME)) if unit.has_slot else "No runway slot yet: build a runway (F) before its fuel runs out, or the pilot ejects and the jet is lost.", 11, UiTheme.TEXT_DIM if unit.has_slot else UiTheme.WARN)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.custom_minimum_size = Vector2(400, 0)
			_detail.add_child(tip)


func _cargo_names(heli) -> PackedStringArray:
	var out: PackedStringArray = []
	for sq in heli.passenger_squads():
		out.append(sq.squad_name)
	if heli is Helicopter:
		for v in heli.cargo:
			out.append("Humvee")
	if heli is Chinook and heli.is_slung():
		out.append("%s (slung)" % heli.sling_gun.display_name)
	return out


func _sling_mode() -> bool:
	## Only Chinooks selected, and there's an M777: the Board button slings it
	if game.guns.is_empty() or not game._selected().is_empty():
		return false
	var veh: Array = game._selected_vehicles()
	if veh.is_empty():
		return false
	for v in veh:
		if not (v is Chinook):
			return false
	return true


func _health_row(title: String, health: float, rounds := -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UiTheme.label(title, 12)
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	if rounds >= 0:
		l.custom_minimum_size = Vector2(80, 0)
		var r := UiTheme.label(str(rounds), 11, UiTheme.BAD if rounds <= 0 else (UiTheme.WARN if rounds < Soldier.CARRY / 4 else UiTheme.TEXT_DIM))
		r.custom_minimum_size = Vector2(28, 0)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.tooltip_text = "Rounds left (of %d)" % Soldier.CARRY
		h.add_child(r)
	var bar := ProgressBar.new()
	bar.max_value = Soldier.MAX_HEALTH
	bar.value = health
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(86, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = _health_color(health / Soldier.MAX_HEALTH)
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	return h


func _progress_row(title: String, value: float, max_value: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UiTheme.label("%s %d/%d" % [title, value, max_value], 12, UiTheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = maxf(max_value, 0.001)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(86, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.ACCENT
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	return h


func _pips(n: int) -> String:
	return "■".repeat(n) + "□".repeat(5 - n)


func _update_commands() -> void:
	var inf: Array = game._selected()
	var veh: Array = game._selected_vehicles()
	var helis: Array = game._selected_helis()
	var has_humvee := false
	for v in veh:
		has_humvee = has_humvee or v is Humvee
	var loaded := false
	for t in game.transports:
		if t.selected and not t.destroyed:
			loaded = loaded or not t.passengers.is_empty() or (t is Helicopter and not t.cargo.is_empty())
	var hovering := false
	for h in helis:
		hovering = hovering or h.hover_mode
	(_buttons["hold"] as Button).disabled = inf.is_empty() and veh.is_empty()
	var bb: Button = _buttons["board"]
	if _sling_mode():
		bb.text = "Sling K"
		var ground := false
		for g in game.guns:
			ground = ground or g.slung_by == null
		bb.disabled = not ground
	else:
		bb.text = "Board"
		bb.disabled = inf.is_empty() and not has_humvee
	var ub: Button = _buttons["unload"]
	ub.disabled = not loaded
	ub.text = "Unload U"
	for h in helis:
		if h is Chinook and h.is_slung():
			ub.text = "Drop gun U"
			ub.disabled = false
	var hb: Button = _buttons["hover"]
	hb.disabled = helis.is_empty()
	hb.text = "Land L" if hovering else "Hover L"
	(_buttons["a10"] as Button).disabled = game._ready_a10() == null
	var fb: Button = _buttons["fire"]
	var manned := false
	for g in game.guns:
		manned = manned or (g.crew_count() > 0 and g.slung_by == null)
	fb.disabled = not manned and not _any_mission()
	fb.text = "Cease C" if _any_mission() else "Fire G"
	(_buttons["build"] as Button).disabled = not game.has_engineers()

	# Only the buttons that make sense for what's selected
	var jets: Array = []
	var ground_veh := false
	for v in veh:
		if v is A10:
			jets.append(v)
		elif v is GroundVehicle:
			ground_veh = true
	var guns_sel: Array = game._selected_guns()
	var crews := false
	for sq in inf:
		crews = crews or sq.kind == "gun_crew"
	var transports := false
	for t in game.transports:
		transports = transports or (t.selected and not t.destroyed)
	var nothing: bool = inf.is_empty() and veh.is_empty() and guns_sel.is_empty()
	var only_jets: bool = not jets.is_empty() and inf.is_empty() and guns_sel.is_empty() and jets.size() == veh.size()
	var only_guns: bool = not guns_sel.is_empty() and inf.is_empty() and veh.is_empty()
	_show("hold", not inf.is_empty() or ground_veh or not helis.is_empty())
	_show("board", not inf.is_empty() or has_humvee or _sling_mode())
	var trucks := false
	for v in veh:
		if v is Pls:
			trucks = true
			if not v.cargo.is_empty():
				(_buttons["unload"] as Button).disabled = false
				(_buttons["unload"] as Button).text = "Drop U"
	_show("unload", transports or trucks)
	_show("hover", not helis.is_empty())
	_show("a10", not only_guns and (nothing or not jets.is_empty() or not inf.is_empty() or ground_veh or not helis.is_empty()))
	_show("stay", not jets.is_empty())
	_show("fire", not only_jets)
	_show("mode", not guns_sel.is_empty() or crews)
	if not jets.is_empty():
		var sb: Button = _buttons["stay"]
		sb.text = "Stay ON X" if jets[0].force_stay else "Stay X"
		sb.add_theme_color_override("font_color", UiTheme.ACCENT if jets[0].force_stay else UiTheme.TEXT)
		(_buttons["a10"] as Button).text = "Gun run V"
	else:
		(_buttons["a10"] as Button).text = "A-10 V"
	var mode_guns: Array = guns_sel.duplicate()
	for sq in inf:
		var g = game.gun_of(sq)
		if g != null:
			mode_guns.append(g)
	if not mode_guns.is_empty():
		(_buttons["mode"] as Button).text = "Repeat T" if mode_guns[0].repeat else "Single T"


func _show(id: String, on: bool) -> void:
	(_buttons[id] as Button).visible = on


# --- World-space overlays (drawn under the panels) ---------------------------

func _draw() -> void:
	for item in _overlay:
		var pts: PackedVector2Array = item[0]
		if pts.size() < 2:
			continue
		if item[2]:
			pts = pts.duplicate()
			pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.5), item[3] + 2.0)
		draw_polyline(pts, item[1], item[3])
	if _trail.size() >= 2:
		draw_polyline(_trail, Color(1, 1, 1, 0.55), 2.0)
	for m in _formation:
		draw_circle(m[0], 7.0, Color(0, 0, 0, 0.6))
		draw_circle(m[0], 5.0, (m[1] as Color).lightened(0.3))
	if _show_drag:
		draw_rect(_drag_rect, Color(0.45, 1.0, 0.45, 0.12), true)
		draw_rect(_drag_rect, Color(0.45, 1.0, 0.45, 0.9), false, 1.0)


func _any_mission() -> bool:
	for g in game.guns:
		if g.has_mission:
			return true
	return false
