class_name TexasNames
extends Control
## Names on the map, drawn flat on the screen at a size you can read whatever the zoom. Given in
## order of importance; a name that would overlap one already drawn is left out, so the map
## never fills up with text.

var items: Array = []                  # [screen position, text, font size, colour]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var placed: Array[Rect2] = []
	var seen := {}
	var view := get_viewport_rect()
	for it in items:
		var p: Vector2 = it[0]
		var text: String = it[1]
		var plain := text.trim_prefix("★ ").get_slice(" (", 0)
		if seen.has(plain):
			continue
		var fs: int = it[2]
		var col: Color = it[3]
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var r := Rect2(p.x - sz.x * 0.5, p.y - sz.y - 6.0, sz.x, sz.y).grow(3.0)
		if not view.encloses(r):
			continue
		var clash := false
		for q in placed:
			if q.intersects(r):
				clash = true
				break
		if clash:
			continue
		placed.append(r)
		seen[plain] = true
		var base := Vector2(p.x - sz.x * 0.5, p.y - 6.0 - sz.y * 0.25)
		draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.04, 0.04, 0.04, 0.9))
		draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
