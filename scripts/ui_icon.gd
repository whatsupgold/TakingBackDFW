class_name UiIcon
extends Control
## Small flat icons for the HUD, drawn with shapes (no image files): clock, objective flag,
## Red troops, tank, anti-air, new unit, growth, attack, your personnel, and the unit kinds
## (squad, vehicle, helicopter, jet, gun, build) plus the minimap legend marks.

var kind := ""
var color := Color.WHITE


static func make(k: String, c: Color, px := 14) -> UiIcon:
	var i := UiIcon.new()
	i.kind = k
	i.color = c
	i.custom_minimum_size = Vector2(px, px)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := color
	var u := s / 14.0                      # drawn on a 14 x 14 grid
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * u
	match kind:
		"clock":
			draw_arc(P.call(7, 7), 5.5 * u, 0, TAU, 20, c, 1.5 * u)
			draw_line(P.call(7, 7), P.call(7, 3.5), c, 1.5 * u)
			draw_line(P.call(7, 7), P.call(9.5, 8.5), c, 1.5 * u)
		"flag":
			draw_line(P.call(3, 1), P.call(3, 13), c, 1.5 * u)
			draw_colored_polygon(PackedVector2Array([P.call(3.5, 1.5), P.call(12, 4), P.call(3.5, 7)]), c)
		"enemy", "personnel", "squad":
			# A soldier: head, shoulders
			draw_circle(P.call(7, 4), 2.6 * u, c)
			draw_colored_polygon(PackedVector2Array([P.call(2.5, 13), P.call(3.5, 8), P.call(10.5, 8), P.call(11.5, 13)]), c)
		"tank":
			draw_rect(Rect2(P.call(1, 7), Vector2(12, 4) * u), c)
			draw_rect(Rect2(P.call(4, 4), Vector2(6, 3) * u), c)
			draw_line(P.call(9, 5.5), P.call(13.5, 4.5), c, 1.5 * u)
		"aa":
			draw_colored_polygon(PackedVector2Array([P.call(7, 1), P.call(13, 7), P.call(7, 13), P.call(1, 7)]), c)
		"plus":
			draw_rect(Rect2(P.call(5.5, 1.5), Vector2(3, 11) * u), c)
			draw_rect(Rect2(P.call(1.5, 5.5), Vector2(11, 3) * u), c)
		"grow":
			draw_rect(Rect2(P.call(1.5, 1.5), Vector2(11, 11) * u), c, false, 1.5 * u)
			draw_rect(Rect2(P.call(4.5, 4.5), Vector2(5, 5) * u), c)
		"attack":
			draw_line(P.call(2, 12), P.call(12, 2), c, 2.0 * u)
			draw_colored_polygon(PackedVector2Array([P.call(13, 1), P.call(8, 2), P.call(12, 6)]), c)
		"vehicle":
			draw_rect(Rect2(P.call(1, 5), Vector2(12, 5) * u), c)
			draw_circle(P.call(4, 11), 1.8 * u, c)
			draw_circle(P.call(10, 11), 1.8 * u, c)
		"heli":
			draw_line(P.call(1, 3), P.call(13, 3), c, 1.2 * u)
			draw_line(P.call(7, 3), P.call(7, 6), c, 1.2 * u)
			draw_rect(Rect2(P.call(3, 6), Vector2(6, 4) * u), c)
			draw_line(P.call(9, 8), P.call(13, 7), c, 1.5 * u)
		"jet":
			# Seen from above: fuselage, swept wings, tailplane
			draw_rect(Rect2(P.call(6, 1), Vector2(2, 12) * u), c)
			draw_colored_polygon(PackedVector2Array([P.call(7, 4), P.call(13, 8.5), P.call(13, 9.5), P.call(1, 9.5), P.call(1, 8.5)]), c)
			draw_colored_polygon(PackedVector2Array([P.call(7, 11), P.call(10, 13), P.call(4, 13)]), c)
		"gun":
			draw_line(P.call(2, 11), P.call(12, 3), c, 2.0 * u)
			draw_circle(P.call(5, 10.5), 2.2 * u, c)
		"build":
			draw_rect(Rect2(P.call(2, 2), Vector2(10, 4) * u), c)
			draw_line(P.call(7, 6), P.call(7, 13), c, 2.0 * u)
		"ammo":
			# A rifle cartridge
			draw_rect(Rect2(P.call(5, 5), Vector2(4, 8) * u), c)
			draw_colored_polygon(PackedVector2Array([P.call(5, 5), P.call(7, 1), P.call(9, 5)]), c)
		"shell":
			draw_rect(Rect2(P.call(4.5, 5), Vector2(5, 8) * u), c)
			draw_colored_polygon(PackedVector2Array([P.call(4.5, 5), P.call(7, 1), P.call(9.5, 5)]), c)
			draw_line(P.call(4.5, 10.5), P.call(9.5, 10.5), Color(0, 0, 0, 0.5), 1.2 * u)
		"fuel":
			# A drop
			draw_circle(P.call(7, 9), 3.8 * u, c)
			draw_colored_polygon(PackedVector2Array([P.call(3.4, 8), P.call(7, 1), P.call(10.6, 8)]), c)
		"chute":
			draw_colored_polygon(PackedVector2Array([P.call(1, 6), P.call(4, 2.5), P.call(10, 2.5), P.call(13, 6)]), c)
			for x in [2.0, 7.0, 12.0]:
				draw_line(P.call(x, 6), P.call(7, 10.5), c, 1.0 * u)
			draw_rect(Rect2(P.call(5.5, 10), Vector2(3, 3) * u), c)
		# Minimap legend marks
		"m_infantry":
			draw_colored_polygon(PackedVector2Array([P.call(7, 3), P.call(11, 7), P.call(7, 11), P.call(3, 7)]), c)
		"m_vehicle":
			draw_rect(Rect2(P.call(3.5, 3.5), Vector2(7, 7) * u), c)
		"m_air":
			draw_colored_polygon(PackedVector2Array([P.call(7, 2.5), P.call(11.5, 11), P.call(2.5, 11)]), c)
		"m_enemy":
			draw_circle(P.call(7, 7), 3.5 * u, c)
		_:
			draw_circle(P.call(7, 7), 3.0 * u, c)
