class_name SettingsPanel
extends PanelContainer
## Settings, used by both the main menu and the in-game pause menu.

signal closed

var _pixel: OptionButton
var _full: CheckButton
var _edge: CheckButton
var _debug: CheckButton
var _pan: HSlider


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG_SOLID))
	custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UiTheme.label("SETTINGS", 22, UiTheme.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	grid.add_child(UiTheme.label("Pixel size"))
	_pixel = OptionButton.new()
	_pixel.focus_mode = Control.FOCUS_NONE
	for opt in [[2, "Fine (2x)"], [3, "Classic (3x)"], [4, "Chunky (4x)"]]:
		_pixel.add_item(opt[1], opt[0])
	_pixel.item_selected.connect(func(i): Settings.pixel_scale = _pixel.get_item_id(i); _save())
	grid.add_child(_pixel)

	grid.add_child(UiTheme.label("Fullscreen"))
	_full = CheckButton.new()
	_full.focus_mode = Control.FOCUS_NONE
	_full.toggled.connect(func(on): Settings.fullscreen = on; _save())
	grid.add_child(_full)

	grid.add_child(UiTheme.label("Camera pan speed"))
	_pan = HSlider.new()
	_pan.min_value = 0.5
	_pan.max_value = 2.0
	_pan.step = 0.1
	_pan.custom_minimum_size = Vector2(180, 20)
	_pan.focus_mode = Control.FOCUS_NONE
	_pan.value_changed.connect(func(x): Settings.pan_speed = x; _save())
	grid.add_child(_pan)

	grid.add_child(UiTheme.label("Edge scrolling"))
	_edge = CheckButton.new()
	_edge.focus_mode = Control.FOCUS_NONE
	_edge.toggled.connect(func(on): Settings.edge_scroll = on; _save())
	grid.add_child(_edge)

	grid.add_child(UiTheme.label("Developer stats (F4)"))
	_debug = CheckButton.new()
	_debug.focus_mode = Control.FOCUS_NONE
	_debug.toggled.connect(func(on): Settings.show_debug = on; _save())
	grid.add_child(_debug)

	var back := UiTheme.button("Back")
	back.pressed.connect(func(): hide(); closed.emit())
	v.add_child(back)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _pixel == null:
		return
	for i in _pixel.item_count:
		if _pixel.get_item_id(i) == Settings.pixel_scale:
			_pixel.select(i)
	_full.set_pressed_no_signal(Settings.fullscreen)
	_edge.set_pressed_no_signal(Settings.edge_scroll)
	_debug.set_pressed_no_signal(Settings.show_debug)
	_pan.set_value_no_signal(Settings.pan_speed)


func _save() -> void:
	Settings.save_settings()
	Settings.apply()
