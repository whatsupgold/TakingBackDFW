class_name UiTheme
extends RefCounted
## One look for every menu and HUD panel: dark slate glass, thin cool-grey borders, amber
## accents and green/amber/red status colors.

const BG := Color(0.09, 0.11, 0.13, 0.88)
const BG_SOLID := Color(0.10, 0.12, 0.14, 0.97)
const BG_CARD := Color(0.13, 0.15, 0.18, 0.95)
const BORDER := Color(0.30, 0.35, 0.40)
const BORDER_DIM := Color(0.21, 0.25, 0.29)
const TEXT := Color(0.90, 0.92, 0.94)
const TEXT_DIM := Color(0.58, 0.63, 0.68)
const ACCENT := Color(0.96, 0.74, 0.30)
const GOOD := Color(0.45, 0.85, 0.40)
const WARN := Color(0.98, 0.70, 0.25)
const BAD := Color(0.95, 0.32, 0.25)

static var _theme: Theme
static var _bold: FontVariation


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15

	t.set_stylebox("panel", "PanelContainer", panel_box(BG))
	t.set_stylebox("panel", "Panel", panel_box(BG))

	var normal := _box(Color(0.15, 0.18, 0.21, 0.95), BORDER, 1)
	var hover := _box(Color(0.20, 0.24, 0.28, 0.98), ACCENT, 1)
	var pressed := _box(Color(0.30, 0.26, 0.14, 1.0), ACCENT, 1)
	var disabled := _box(Color(0.11, 0.13, 0.15, 0.8), BORDER_DIM, 1)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 1)
	for k in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", k, normal)
		t.set_stylebox("hover", k, hover)
		t.set_stylebox("pressed", k, pressed)
		t.set_stylebox("disabled", k, disabled)
		t.set_stylebox("focus", k, focus)
		t.set_color("font_color", k, TEXT)
		t.set_color("font_hover_color", k, Color(1, 0.95, 0.8))
		t.set_color("font_pressed_color", k, ACCENT)
		t.set_color("font_disabled_color", k, Color(0.40, 0.44, 0.48))
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)

	var bar_bg := _box(Color(0.05, 0.06, 0.07, 0.9), BORDER_DIM, 1)
	var bar_fill := _box(GOOD, Color(0, 0, 0, 0), 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	var slider := _box(Color(0.05, 0.06, 0.07, 0.9), BORDER, 1)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", _box(Color(0.5, 0.45, 0.2), Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, Color(0, 0, 0, 0), 0))

	t.set_stylebox("panel", "TooltipPanel", _box(BG_SOLID, BORDER, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


static func panel_box(bg: Color, border := BORDER) -> StyleBoxFlat:
	var b := _box(bg, border, 1)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(2)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


static func bold_font() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


static func label(text: String, size := 15, color := TEXT, outline := false, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	if bold:
		ls.font = bold_font()
	ls.font_color = color
	if outline:
		ls.outline_size = 6
		ls.outline_color = Color(0, 0, 0, 0.9)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b
