extends Control
## Title screen: New game, Continue (once campaigns can be saved), Settings, Quit.

const GAME_SCENE := "res://scenes/main.tscn"
const TEXAS_SCENE := "res://scenes/texas.tscn"

var _buttons: VBoxContainer
var _settings: SettingsPanel
var _maps: PanelContainer
var _menu_panel: PanelContainer
var _shot_path := ""
var _clock := 0.0


func _ready() -> void:
	# Automated tests and screenshot runs go straight into the battle
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--texas-lab") or a.begins_with("--galveston-lab") or a.begins_with("--ui-lab") or a.begins_with("--water-lab") or a.begins_with("--org-lab") or a.begins_with("--navy-lab") or a.begins_with("--command-lab"):
			get_tree().change_scene_to_file.call_deferred(TEXAS_SCENE)
			return
		if a == "--autotest" or a.begins_with("--shot=") or a.begins_with("--setup-shot="):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
		if a.begins_with("--menu-shot="):
			_shot_path = a.trim_prefix("--menu-shot=")

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	add_child(SkylineArt.new())

	var title := UiTheme.label("TAKING BACK DFW", 64, UiTheme.ACCENT, true)
	title.label_settings.outline_size = 12
	title.position = Vector2(64, 48)
	add_child(title)
	var sub := UiTheme.label("The Red Army holds the city. Take it back.", 20, UiTheme.TEXT, true)
	sub.position = Vector2(68, 128)
	add_child(sub)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 64
	add_child(panel)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.custom_minimum_size = Vector2(260, 0)
	panel.add_child(_buttons)
	_menu_panel = panel
	_add_button("New game", _open_maps)
	var gv := _add_button("Galveston to Houston (Phase 4)", func():
		TexasMain.start_mode = "galveston"
		get_tree().change_scene_to_file(TEXAS_SCENE))
	gv.tooltip_text = "The first playable slice of Taking Back Texas: land at Galveston and fight through to downtown Houston"
	var tx := _add_button("Texas test world (Phase 2)", func():
		TexasMain.start_mode = "test"
		get_tree().change_scene_to_file(TEXAS_SCENE))
	tx.tooltip_text = "The 1:3 Texas world: streaming, thousands of units, time speed-up, save and load"
	var cont := _add_button("Continue", func(): pass)
	cont.disabled = true
	cont.tooltip_text = "Saved campaigns are coming with the campaign mode"
	_add_button("Settings", _open_settings)
	_add_button("Quit", func(): get_tree().quit())

	var ver := UiTheme.label("M1 prototype  ·  Godot " + Engine.get_version_info().string, 13, UiTheme.TEXT_DIM, true)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -14
	ver.offset_bottom = -10
	add_child(ver)

	_settings = SettingsPanel.new()
	_settings.visible = false
	add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.closed.connect(func(): panel.visible = true)
	_settings.set_meta("menu_panel", panel)
	if "--menu-maps" in OS.get_cmdline_user_args():
		_open_maps()


func _open_maps() -> void:
	## Pick the map: a DFW sector (real size, from OpenStreetMap), a custom real map, or the
	## generated city
	_menu_panel.visible = false
	if _maps != null:
		_maps.queue_free()
	_maps = PanelContainer.new()
	_maps.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG))
	add_child(_maps)
	_maps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_maps.grow_vertical = Control.GROW_DIRECTION_BOTH
	_maps.offset_left = 64
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(520, 0)
	_maps.add_child(v)
	v.add_child(UiTheme.label("CHOOSE THE BATTLEFIELD", 22, UiTheme.ACCENT))
	var hint := UiTheme.label("DFW sectors are real-size maps from OpenStreetMap, west to east. Each one needs its map downloaded once: follow the steps in data/sectors/<sector>.txt.", 13, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	v.add_child(hint)
	for sec in OsmImport.sectors():
		var label := "%d.  %s" % [sec.order, sec.name]
		if not sec.ready:
			label += "   (map not downloaded)"
		var b := _map_button(v, label, sec.id)
		b.disabled = not sec.ready
		b.tooltip_text = "%.1f x %.1f km. %s" % [sec.width_m / 1000.0, sec.height_m / 1000.0, "Ready" if sec.ready else "Download it with data/sectors/%s.txt" % sec.id]
	if FileAccess.file_exists(OsmImport.CONFIG_PATH):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(OsmImport.CONFIG_PATH))
		if typeof(cfg) == TYPE_DICTIONARY and FileAccess.file_exists(cfg.get("osm_file", "")):
			_map_button(v, "Custom real map  (data/real_map.json)", "custom")
	_map_button(v, "Generated DFW  (the whole metroplex, simplified; no download)", "")
	var back := UiTheme.button("Back")
	back.pressed.connect(func():
		_maps.queue_free()
		_maps = null
		_menu_panel.visible = true)
	v.add_child(back)


func _map_button(parent: Control, text: String, id: String) -> Button:
	var b := UiTheme.button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 34)
	if id == Settings.sector:
		b.add_theme_color_override("font_color", UiTheme.ACCENT)
	b.pressed.connect(func():
		Settings.sector = id
		Settings.save_settings()
		get_tree().change_scene_to_file(GAME_SCENE))
	parent.add_child(b)
	return b


func _add_button(text: String, action: Callable) -> Button:
	var b := UiTheme.button(text)
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	_buttons.add_child(b)
	return b


func _open_settings() -> void:
	(_settings.get_meta("menu_panel") as Control).visible = false
	_settings.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _maps != null:
		_maps.queue_free()
		_maps = null
		_menu_panel.visible = true
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _settings.visible:
		_settings.visible = false
		(_settings.get_meta("menu_panel") as Control).visible = true


func _process(delta: float) -> void:
	if _shot_path == "":
		return
	_clock += delta
	if _clock > 1.5:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("MENU: saved %s" % _shot_path)
		get_tree().quit()
