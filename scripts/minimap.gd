class_name Minimap
extends Control
## The whole city at a glance: districts, roads, river and buildings (drawn once from the
## city data), with your units, the Red Army, objectives, the camera's view and artillery targets on top.
## Click or drag on it to move the camera.

const MAP_W := 300
const MAP_H := 150
const C_INFANTRY := Color(0.45, 0.90, 0.45)
const C_VEHICLE := Color(0.98, 0.72, 0.25)
const C_AIR := Color(0.50, 0.75, 1.0)
const C_ENEMY := Color(0.95, 0.27, 0.22)

var game: Node            # main.gd
var _tex: ImageTexture
var _dragging := false


func setup(g: Node) -> void:
	game = g
	custom_minimum_size = Vector2(MAP_W, MAP_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tex = ImageTexture.create_from_image(_render(game.level.city))
	tooltip_text = "Click or drag to move the camera"


# --- Map image ---------------------------------------------------------------

func _render(city: CityBuilder) -> Image:
	var img := Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	img.fill(CityBuilder.C_GROUND.darkened(0.25))
	if city.real_map != null:
		_render_real(img, city)
		return img
	var tint := {"downtown": Color(0.45, 0.45, 0.44), "offices": Color(0.42, 0.44, 0.42),
		"commercial": Color(0.40, 0.40, 0.38), "industrial": Color(0.42, 0.40, 0.34),
		"stockyards": Color(0.46, 0.38, 0.28), "airport": Color(0.42, 0.46, 0.34),
		"park": CityBuilder.C_GRASS2.darkened(0.15), "residential": CityBuilder.C_GRASS.darkened(0.2)}
	var districts := CityBuilder.DISTRICTS.duplicate()
	districts.reverse()
	for d in districts:
		_fill(img, d.rect, tint.get(d.type, CityBuilder.C_GROUND))
	# Street grid
	var road := CityBuilder.C_ASPHALT.darkened(0.1)
	var x := -CityBuilder.HALF_X + CityBuilder.GRID * 0.5
	while x <= CityBuilder.HALF_X:
		_line(img, Vector2(x, -CityBuilder.HALF_Z), Vector2(x, CityBuilder.HALF_Z), 1.0, road)
		x += CityBuilder.GRID
	var z := -CityBuilder.HALF_Z + CityBuilder.GRID * 0.5
	while z <= CityBuilder.HALF_Z:
		_line(img, Vector2(-CityBuilder.HALF_X, z), Vector2(CityBuilder.HALF_X, z), 1.0, road)
		z += CityBuilder.GRID
	for f in city.footprints:
		_fill(img, f[0], (f[1] as Color).darkened(0.1))
	for h in CityBuilder.HIGHWAYS:
		var pts: Array = h.pts
		for i in range(1, pts.size()):
			_line(img, pts[i - 1], pts[i], 3.0, Color(0.62, 0.60, 0.52))
	for i in range(1, CityBuilder.RIVER.size()):
		_line(img, CityBuilder.RIVER[i - 1], CityBuilder.RIVER[i], 3.5, CityBuilder.C_WATER.lightened(0.1))
	_fill(img, CityBuilder.AT_T, Color(0.85, 0.85, 0.86))
	_fill(img, CityBuilder.GLOBE_LIFE, Color(0.62, 0.38, 0.30))
	return img


func _render_real(img: Image, city: CityBuilder) -> void:
	var m: OsmImport = city.real_map
	for pk in m.parks:
		_poly_fill(img, pk.poly, CityBuilder.C_GRASS2.darkened(0.15))
	for lot in m.lots:
		_poly_fill(img, lot, CityBuilder.C_ASPHALT.lerp(CityBuilder.C_CONCRETE, 0.25).darkened(0.1))
	for r in m.roads:
		var pts: PackedVector2Array = r.pts
		var big: bool = r.kind in ["motorway", "trunk"]
		var c := Color(0.62, 0.60, 0.52) if big else CityBuilder.C_ASPHALT.darkened(0.1)
		var wpx := 3.0 if big else (2.0 if r.width >= 11.0 else 1.0)
		for i in range(1, pts.size()):
			_line(img, pts[i - 1], pts[i], wpx, c)
	for f in city.footprints:
		_fill(img, f[0], (f[1] as Color).darkened(0.1))
	for wp in m.water:
		_poly_fill(img, wp, CityBuilder.C_WATER.lightened(0.1))
	for ww in m.waterways:
		if ww.river:
			var pts: PackedVector2Array = ww.pts
			for i in range(1, pts.size()):
				_line(img, pts[i - 1], pts[i], 3.0, CityBuilder.C_WATER.lightened(0.1))


func _poly_fill(img: Image, poly: PackedVector2Array, c: Color) -> void:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	var a := _px(r.position)
	var b := _px(r.end)
	for py in range(maxi(0, floori(a.y)), mini(MAP_H, ceili(b.y) + 1)):
		for px in range(maxi(0, floori(a.x)), mini(MAP_W, ceili(b.x) + 1)):
			var w := _world(Vector2(px + 0.5, py + 0.5))
			if Geometry2D.is_point_in_polygon(Vector2(w.x, w.z), poly):
				img.set_pixel(px, py, c)


func _px(w: Vector2) -> Vector2:
	return Vector2((w.x + CityBuilder.HALF_X) / (CityBuilder.HALF_X * 2.0) * MAP_W,
		(w.y + CityBuilder.HALF_Z) / (CityBuilder.HALF_Z * 2.0) * MAP_H)


func _world(p: Vector2) -> Vector3:
	return Vector3(p.x / MAP_W * CityBuilder.HALF_X * 2.0 - CityBuilder.HALF_X, 0.0,
		p.y / MAP_H * CityBuilder.HALF_Z * 2.0 - CityBuilder.HALF_Z)


func _fill(img: Image, r: Rect2, c: Color) -> void:
	var a := _px(r.position)
	var b := _px(r.end)
	var rect := Rect2i(Vector2i(floori(a.x), floori(a.y)), Vector2i(maxi(1, ceili(b.x - a.x)), maxi(1, ceili(b.y - a.y))))
	rect = rect.intersection(Rect2i(0, 0, MAP_W, MAP_H))
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, c)


func _line(img: Image, a: Vector2, b: Vector2, width_px: float, c: Color) -> void:
	var pa := _px(a)
	var pb := _px(b)
	var steps := int(pa.distance_to(pb)) + 1
	var r := int(width_px * 0.5)
	for i in steps + 1:
		var p := pa.lerp(pb, float(i) / steps)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
				if q.x >= 0 and q.y >= 0 and q.x < MAP_W and q.y < MAP_H:
					img.set_pixelv(q, c)


# --- Live overlay ------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	draw_texture(_tex, Vector2.ZERO)
	# The real map's data credit (OpenStreetMap's licence asks for it)
	if game.level.city.real_map != null:
		draw_rect(Rect2(0, MAP_H - 12, 150, 12), Color(0, 0, 0, 0.55))
		draw_string(ThemeDB.fallback_font, Vector2(3, MAP_H - 2), "© OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.85))
	# Objectives: red while held by the Red Army, blue once taken back
	var army: RedArmy = game.enemy
	for o in army.objectives:
		var op := _px(Vector2(o.pos.x, o.pos.z))
		var oc := Color(0.45, 0.75, 1.0) if o.owner == "blue" else Color(1.0, 0.35, 0.3)
		draw_arc(op, 5.0, 0, TAU, 16, Color(0, 0, 0, 0.7), 3.0)
		draw_arc(op, 5.0, 0, TAU, 16, oc, 1.5)
	# Red Army: riflemen as dots, tanks as bigger squares
	for z in army.alive:
		var p := _px(Vector2(z.global_position.x, z.global_position.z))
		draw_circle(p, 1.2, C_ENEMY)
	for t in army.tanks:
		var p := _px(Vector2(t.global_position.x, t.global_position.z))
		if t is RedAA:
			# Anti-air: a diamond
			var dia := PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0)])
			draw_colored_polygon(dia, Color(0, 0, 0, 0.8))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -2), p + Vector2(2, 0), p + Vector2(0, 2), p + Vector2(-2, 0)]), Color(1.0, 0.6, 0.2))
			continue
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), C_ENEMY)
	# Artillery: gun and active target
	# The Red FOB: its outline, with any breaches shown as gaps
	var rf: RedFob = game.enemy.red_fob
	if rf != null:
		for rr in rf.rects:
			var ra := _px(rr.position)
			var rb := _px(rr.end)
			draw_rect(Rect2(ra, rb - ra), Color(0.9, 0.2, 0.15, 0.22), true)
		for st in rf.pieces:
			if not is_instance_valid(st) or not (st.kind in ["red_wall", "red_ramp", "red_gate"]):
				continue
			var fp: PackedVector3Array = st.footprint_world()
			var mid := (fp[0] + fp[1]) * 0.5
			var c := Color(1.0, 0.35, 0.3)
			if st.state == "destroyed":
				c = Color(1.0, 0.9, 0.3)        # a breach
			elif st.state == "building":
				c = Color(1.0, 0.35, 0.3, 0.45)   # going up
			draw_line(_px(Vector2(fp[0].x, fp[0].z)), _px(Vector2(fp[1].x, fp[1].z)), c, 3.0 if st.state == "destroyed" else 2.0)
	# Your FOB outline and runways
	for r in game.fob.rects:
		var a := _px(r.position)
		var b := _px(r.end)
		draw_rect(Rect2(a, b - a), Color(0.45, 0.75, 1.0, 0.25), true)
		draw_rect(Rect2(a, b - a), Color(0.55, 0.85, 1.0), false, 1.5)
	for st in game.fob.pieces:
		if is_instance_valid(st) and st.kind == "runway":
			var pts: PackedVector3Array = st.footprint_world()
			var poly := PackedVector2Array()
			for p in pts:
				poly.append(_px(Vector2(p.x, p.z)))
			poly.append(poly[0])
			draw_polyline(poly, Color(0.85, 0.85, 0.85) if st.is_built() else Color(0.6, 0.6, 0.6, 0.6), 1.5)
	for gun in game.guns:
		var gp := _px(Vector2(gun.global_position.x, gun.global_position.z))
		draw_rect(Rect2(gp - Vector2(2, 2), Vector2(4, 4)), Color(0.78, 0.68, 0.40))
		if gun.has_mission:
			var t: Vector3 = gun.mission_target
			draw_arc(_px(Vector2(t.x, t.z)), 4.0, 0, TAU, 12, UiTheme.ACCENT, 1.5)
	# Units: infantry diamonds, vehicles squares, aircraft triangles (see the legend)
	for sq in game.squads:
		for s in sq.active_soldiers():
			var p := _px(Vector2(s.global_position.x, s.global_position.z))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -2), p + Vector2(2, 0), p + Vector2(0, 2), p + Vector2(-2, 0)]), C_INFANTRY)
	for v in game.vehicles:
		if not v.visible or v.destroyed:
			continue
		var p := _px(Vector2(v.global_position.x, v.global_position.z))
		if v is Helicopter or v is A10:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(3.5, 3), p + Vector2(-3.5, 3)]), Color(0, 0, 0, 0.8))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3), p + Vector2(2.5, 2), p + Vector2(-2.5, 2)]), C_AIR)
			continue
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), C_VEHICLE)
	# Supply pallets: yellow squares (hollow while still coming down)
	for n in get_tree().get_nodes_in_group("pallets"):
		var pl := n as SupplyPallet
		if pl == null or pl.state in ["loaded", "delivered"]:
			continue
		var pp := _px(Vector2(pl.global_position.x, pl.global_position.z))
		draw_rect(Rect2(pp - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.85, 0.30), pl.state != "falling")
	# Where reinforcements just arrived: a pulsing ring
	for a in game.arrivals:
		var ap := _px(Vector2(a[0].x, a[0].z))
		var pulse := 4.0 + fmod(a[1] * 6.0, 6.0)
		draw_arc(ap, pulse, 0, TAU, 16, Color(0, 0, 0, 0.7), 3.0)
		draw_arc(ap, pulse, 0, TAU, 16, Color(0.55, 1.0, 0.55), 1.5)
	# What the camera sees
	var quad := _camera_quad()
	if quad.size() == 4:
		draw_colored_polygon(quad, Color(1, 1, 1, 0.14))
		quad.append(quad[0])
		draw_polyline(quad, Color(1, 1, 1, 0.9), 1.0)
	_draw_view_and_scale()
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BORDER, false, 1.0)


func _draw_view_and_scale() -> void:
	var font := UiTheme.bold_font()
	# Which way the camera looks
	var fwd: Vector3 = -(game.camera as Camera3D).global_transform.basis.z
	var deg := wrapf(rad_to_deg(atan2(fwd.x, -fwd.z)), 0.0, 360.0)
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var txt := "VIEW %d° %s" % [roundi(deg), names[int(roundf(deg / 45.0)) % 8]]
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_rect(Rect2(3, 3, w + 12, 16), Color(0.06, 0.08, 0.10, 0.85))
	draw_rect(Rect2(3, 3, 2, 16), UiTheme.ACCENT)
	draw_string(font, Vector2(10, 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)
	# North marker
	draw_string(font, Vector2(MAP_W - 12, 13), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT)
	# Scale bar: a round distance about a fifth of the map wide
	var m_per_px := CityBuilder.HALF_X * 2.0 / MAP_W
	var want := m_per_px * MAP_W * 0.2
	var nice := 100.0
	for v in [100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0]:
		if v <= want:
			nice = v
	var len_px := nice / m_per_px
	var y := MAP_H - (18.0 if game.level.city.real_map != null else 6.0)
	var x0 := MAP_W - len_px - 8.0
	draw_rect(Rect2(x0 - 4, y - 13, len_px + 8, 17), Color(0.06, 0.08, 0.10, 0.75))
	draw_line(Vector2(x0, y), Vector2(x0 + len_px, y), UiTheme.TEXT, 1.0)
	draw_line(Vector2(x0, y - 3), Vector2(x0, y), UiTheme.TEXT, 1.0)
	draw_line(Vector2(x0 + len_px, y - 3), Vector2(x0 + len_px, y), UiTheme.TEXT, 1.0)
	var lbl := ("%d m" % nice) if nice < 1000.0 else ("%g km" % (nice / 1000.0))
	draw_string(font, Vector2(x0, y - 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT)


func _camera_quad() -> PackedVector2Array:
	var out := PackedVector2Array()
	var cam: Camera3D = game.camera
	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
	for corner in [Vector2.ZERO, Vector2(vp_size.x, 0), vp_size, Vector2(0, vp_size.y)]:
		var o := cam.project_ray_origin(corner)
		var n := cam.project_ray_normal(corner)
		if absf(n.y) < 0.001:
			return PackedVector2Array()
		var hit := o + n * (-o.y / n.y)
		out.append(_px(Vector2(hit.x, hit.z)))
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_jump(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_jump(event.position)
		accept_event()


func _jump(p: Vector2) -> void:
	var w := _world(p.clamp(Vector2.ZERO, Vector2(MAP_W, MAP_H)))
	game.camera.focus = Vector3(w.x, 0.0, w.z)
