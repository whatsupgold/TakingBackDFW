class_name TexasMap
extends Node3D
## The strategic map: the whole state drawn once into a big texture (the Gulf, the land shaded
## by elevation, highways, cities and their names, the border), laid flat under the world, and
## every unit as a coloured icon on it. It's what you see zoomed out; zoomed in, the streamed
## tiles and the 3D units take over.

const TEX := 4096
const SHADE := 192                     # resolution of the elevation shading
const ICON_REFRESH := 0.1              # seconds between icon updates

var sim: TexasSim
var roads: TexasRoads
var ready_to_show := false
var origin_x := 0.0
var origin_z := 0.0
var _plane: MeshInstance3D
var _vp: SubViewport
var _icons: MultiMeshInstance3D
var _icon_t := 0.0
var _shade_img: Image
var _bounds: Rect2
var _thread_done := false
var icon_size := 1000.0
var selected := {}
var _built_img: Image
var _shade_task := -1


func finish() -> void:
	if _shade_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shade_task)
		_shade_task = -1


func setup(s: TexasSim, r: TexasRoads) -> void:
	sim = s
	roads = r
	_bounds = TexasGeo.bounds()
	if TexasGeo.built:
		# The map builder drew the map: relief, sea, lakes, roads, railways, the border
		var mb: Array = TexasData.meta.map_bounds
		_bounds = Rect2(mb[0], mb[1], mb[2], mb[3])
		_built_img = Image.load_from_file(ProjectSettings.globalize_path(TexasData.DIR + "map.png"))
		_thread_done = true
	else:
		# The elevation shading takes a moment: work it out on a thread, draw when it's ready
		_shade_task = WorkerThreadPool.add_task(_make_shade)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	_icons = MultiMeshInstance3D.new()
	_icons.multimesh = mm
	var im := StandardMaterial3D.new()
	im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.vertex_color_use_as_albedo = true
	im.no_depth_test = true
	im.render_priority = 10
	_icons.material_override = im
	_icons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_icons)


func _make_shade() -> void:
	var img := Image.create(SHADE, SHADE, false, Image.FORMAT_RGB8)
	var cache := {}
	var es := PackedFloat32Array()
	es.resize(SHADE * SHADE)
	for j in SHADE:
		for i in SHADE:
			var x := _bounds.position.x + (i + 0.5) / SHADE * _bounds.size.x
			var z := _bounds.position.y + (j + 0.5) / SHADE * _bounds.size.y
			es[j * SHADE + i] = TexasGeo.elevation_cached(x, z, cache)
	for j in SHADE:
		for i in SHADE:
			var x := _bounds.position.x + (i + 0.5) / SHADE * _bounds.size.x
			var z := _bounds.position.y + (j + 0.5) / SHADE * _bounds.size.y
			var e := es[j * SHADE + i]
			# Light from the north-west: slopes facing it brighter
			var ex := es[j * SHADE + mini(i + 1, SHADE - 1)] - es[j * SHADE + maxi(i - 1, 0)]
			var ez := es[mini(j + 1, SHADE - 1) * SHADE + i] - es[maxi(j - 1, 0) * SHADE + i]
			var light := clampf(1.0 - (ex + ez) * 0.004, 0.75, 1.2)
			var c := TexasGeo.ground_color(x, z, e)
			img.set_pixel(i, j, Color(c.r * light, c.g * light, c.b * light))
	_shade_img = img
	_thread_done = true


func _process(delta: float) -> void:
	if _thread_done and _vp == null:
		if _shade_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_shade_task)
			_shade_task = -1
		_draw_map()
	if _vp != null and not ready_to_show:
		# One frame for the viewport to draw, then show it
		ready_to_show = true
		_plane.visible = _map_on
	_icon_t -= delta
	if _icon_t <= 0.0 and _icons.visible:
		_icon_t = ICON_REFRESH
		_update_icons()


func set_origin(ox: float, oz: float) -> void:
	origin_x = ox
	origin_z = oz
	if _plane != null:
		var c := _bounds.get_center()
		_plane.position = Vector3(c.x - origin_x, -2.0, c.y - origin_z)
	_icon_t = 0.0


var _map_on := true


func show_icons(on: bool) -> void:
	_icons.visible = on


func show_map(on: bool) -> void:
	_map_on = on
	if _plane != null and ready_to_show:
		_plane.visible = on


func _px(p: Vector2) -> Vector2:
	return (p - _bounds.position) / _bounds.size * TEX


func _draw_map() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(TEX, TEX)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.disable_3d = true
	_vp.transparent_bg = false
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.36, 0.34)
	bg.size = Vector2(TEX, TEX)
	_vp.add_child(bg)
	if _built_img != null:
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(_built_img)
		tr.size = Vector2(TEX, TEX)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		_vp.add_child(tr)
		_built_img = null
		var marks := _MapCities.new()
		marks.px = _px
		_vp.add_child(marks)
		_finish_plane()
		return
	# The Gulf: offshore from the coast, and off Louisiana and Tamaulipas
	var water := PackedVector2Array()
	var coast_from := 18                  # Sabine Pass in OUTLINE
	var coast_to := 35                    # mouth of the Rio Grande
	water.append(_px(TexasGeo.to_xz(29.62, -93.84)))
	water.append(_px(TexasGeo.to_xz(29.62, -93.0)))
	water.append(_px(TexasGeo.to_xz(25.0, -93.0)))
	water.append(_px(TexasGeo.to_xz(25.0, -97.40)))
	water.append(_px(TexasGeo.to_xz(25.96, -97.40)))
	for i in range(coast_to, coast_from - 1, -1):
		var o: Array = TexasGeo.OUTLINE[i]
		water.append(_px(TexasGeo.to_xz(o[0], o[1])))
	var wp := Polygon2D.new()
	wp.polygon = water
	wp.color = Color(0.20, 0.36, 0.52)
	_vp.add_child(wp)
	# The state, its land shaded by elevation
	var tex := ImageTexture.create_from_image(_shade_img)
	var poly := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in TexasGeo.outline():
		poly.append(_px(p))
		uv.append((p - _bounds.position) / _bounds.size * SHADE)
	var tp := Polygon2D.new()
	tp.polygon = poly
	tp.uv = uv
	tp.texture = tex
	tp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vp.add_child(tp)
	# Highways
	for seg in roads.segments:
		var ln := Line2D.new()
		ln.points = PackedVector2Array([_px(roads.nodes[seg[0]]), _px(roads.nodes[seg[1]])])
		var interstate: bool = (seg[2] as String).begins_with("I-")
		ln.width = 5.0 if interstate else 3.0
		ln.default_color = Color(0.92, 0.84, 0.55) if interstate else Color(0.82, 0.78, 0.62)
		_vp.add_child(ln)
	# The border
	var border := Line2D.new()
	var bp := poly.duplicate()
	bp.append(poly[0])
	border.points = bp
	border.width = 6.0
	border.default_color = Color(0.12, 0.12, 0.12, 0.8)
	_vp.add_child(border)
	# Cities and their names
	var dots := _MapCities.new()
	dots.px = _px
	_vp.add_child(dots)
	_finish_plane()


func _finish_plane() -> void:
	# Lay it flat under the world
	var pm := PlaneMesh.new()
	pm.size = _bounds.size
	_plane = MeshInstance3D.new()
	_plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_plane.material_override = mat
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane.visible = false
	add_child(_plane)
	set_origin(origin_x, origin_z)


func _update_icons() -> void:
	## Every live unit as a square on the map, blue for you and red for Red; aircraft paler
	var mm := _icons.multimesh
	var n := 0
	for i in sim.count:
		if sim.alive[i] == 1 and sim.aboard[i] < 0:
			n += 1
	if mm.instance_count != n:
		mm.instance_count = n
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	var k := 0
	var s := icon_size
	for i in sim.count:
		if sim.alive[i] == 0 or sim.aboard[i] >= 0:
			continue
		var ship: bool = sim.kind[i] == TexasSim.Kind.SHIP
		var air: bool = sim.kind[i] == TexasSim.Kind.HELI or sim.kind[i] == TexasSim.Kind.JET
		var sz := s * (0.8 if sim.kind[i] == TexasSim.Kind.INFANTRY else (2.2 if ship else 1.0))
		var c: Color
		if sim.side[i] == 0:
			c = Color(0.45, 0.75, 1.0) if air else (Color(0.10, 0.25, 0.75) if ship else Color(0.20, 0.50, 1.0))
		else:
			c = Color(1.0, 0.60, 0.55) if air else Color(0.95, 0.20, 0.18)
		if selected.has(i):
			c = Color(1.0, 1.0, 1.0)
			sz *= 1.3
		var o := k * 16
		buf[o] = sz
		buf[o + 3] = sim.x[i] - origin_x
		buf[o + 5] = 1.0
		buf[o + 7] = 40.0 if air else 20.0
		buf[o + 10] = sz
		buf[o + 11] = sim.z[i] - origin_z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1.0
		k += 1
	mm.buffer = buf


class _MapCities extends Node2D:
	var px: Callable

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		if TexasGeo.built:
			# Ports and the airfields that can take jets
			for pt in TexasData.meta.ports:
				var pp: Vector2 = px.call(Vector2(pt[1], pt[2]))
				draw_rect(Rect2(pp - Vector2(7, 7), Vector2(14, 14)), Color(0.15, 0.3, 0.75))
				draw_rect(Rect2(pp - Vector2(7, 7), Vector2(14, 14)), Color(0.95, 0.95, 1.0), false, 2.0)
		for c in TexasGeo.cities:
			var p: Vector2 = px.call(TexasGeo.city_xz(c))
			var tier: int = c[3]
			if TexasGeo.built and tier < 2:
				draw_circle(p, 3.0, Color(0.1, 0.1, 0.1))
				draw_circle(p, 2.0, Color(0.95, 0.92, 0.82))
				continue
			# Just the dot: the names are screen-size labels drawn by TexasMain, fewer when zoomed out
			var r := 2.0 + tier * 1.6
			draw_circle(p, r + 1.5, Color(0.1, 0.1, 0.1))
			draw_circle(p, r, Color(0.98, 0.95, 0.85))
