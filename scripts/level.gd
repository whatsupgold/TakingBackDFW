class_name Level
extends NavigationRegion3D
## The battlefield: the DFW city (see CityBuilder) plus a two-story building with a ramp up
## to its roof in the Arlington plaza at the origin.
## Bases are built during play out of Structures (see structure.gd): when one is finished or
## destroyed, the navigation tiles around it are re-baked so units path around (or through) it.

const ROOF_HEIGHT := 6.5
const HOLDOUT_HALF := 6.0
const MAP_HALF := 60.0
const RAMP_CENTER_Z := 3.5


static func is_ramp_area(p: Vector3) -> bool:
	return p.x > HOLDOUT_HALF and p.x < HOLDOUT_HALF + 4.0 and p.z > -6.0 and p.z < 10.0

const COL_GROUND := Color(0.30, 0.31, 0.33)
const COL_STREET_LINE := Color(0.78, 0.72, 0.45)
const COL_SIDEWALK := Color(0.47, 0.47, 0.46)
const COL_HOLDOUT := Color(0.66, 0.60, 0.50)
const COL_PARAPET := Color(0.55, 0.50, 0.42)
const COL_RAMP := Color(0.42, 0.42, 0.44)


signal nav_progress(done: int, total: int)

const NAV_TILE := 128.0
const NAV_BORDER := 2.0
const NAV_PARALLEL := 4
const NAV_INSTANT_RADIUS := 270.0     # tiles this close to the FOB bake before play starts (covers the objectives)
const NAV_APPLY_INTERVAL := 0.5       # finished tiles are added in batches (each add rebuilds the map)

var city: CityBuilder
var structures: Array = []            # every Structure (yours and the Red FOB's)
var blockers: Array = []              # other things that block paths (an emplaced M777): nav_part(), footprint_world()
var pre_bake: Callable                # called after the city is parsed, before tiles bake (Red FOB)
var _tiles: Array = []                # {origin, region}
var _dyn_src: NavigationMeshSourceGeometryData3D
var _dyn_dirty := true
var _dirty_tiles := {}                # tile index -> true
var _rebake_cd := 0.0
const REBAKE_DELAY := 1.0             # batch changes that happen close together
var _extra_solids: Array = []        # level boxes (command post, shops, cars) carved like city buildings
var nav_done := 0
var nav_total := 0
var _nav_src: NavigationMeshSourceGeometryData3D
var _nav_queue: Array = []
var _nav_running := 0
var _nav_finished: Array = []         # [region, mesh] waiting to be added
var _nav_apply_cd := 0.0
var _touch_after := -1                # see _after_nav_change()
var _touch_flip := false
var _settle_iter := -1
var _held: Array = []                 # first bakes waiting to go in together


func build() -> void:
	_add_lighting()

	# The city: a compressed Dallas–Fort Worth around an Arlington plaza at the origin
	city = CityBuilder.new()
	city.build(self)

	# The holdout: 12 x 12 m, 6.5 m tall
	_add_box(Vector3(0, ROOF_HEIGHT * 0.5, 0), Vector3(12, ROOF_HEIGHT, 12), COL_HOLDOUT)
	_solid(Vector3(0, 0, 0), Vector3(12, ROOF_HEIGHT, 12))

	# Low parapet around the roof, with a gap on the east side where the ramp lands
	var ph := 0.5
	var py := ROOF_HEIGHT + ph * 0.5
	_add_box(Vector3(0, py, -5.85), Vector3(12, ph, 0.3), COL_PARAPET)       # north
	_add_box(Vector3(0, py, 5.85), Vector3(12, ph, 0.3), COL_PARAPET)        # south
	_add_box(Vector3(-5.85, py, 0), Vector3(0.3, ph, 12), COL_PARAPET)       # west
	_add_box(Vector3(5.85, py, 2.0), Vector3(0.3, ph, 8.0), COL_PARAPET)     # east, south part
	_add_box(Vector3(5.85, py, -5.75), Vector3(0.3, ph, 0.5), COL_PARAPET)   # east, north stub (gap z -5.5..-2)

	# Ramp up the east side, 1 m out from the wall: 30 degrees, bottom at z = +9.1, top at z = -2.0
	var ramp := _add_box(Vector3(8.5, 3.03, RAMP_CENTER_Z), Vector3(3, 0.5, 13), COL_RAMP)
	ramp.rotation.x = deg_to_rad(30.0)
	# Landing at roof height that joins the ramp top to the gap in the parapet
	_add_box(Vector3(8.0, ROOF_HEIGHT - 0.25, -3.75), Vector3(4, 0.5, 3.5), COL_RAMP)

	# Small shops around the plaza: cover, choke points, and other walls to pile against
	for b in [[Vector3(-26, 4.5, 18), Vector3(10, 9, 8), Color(0.50, 0.47, 0.52)],
			[Vector3(24, 2.0, -20), Vector3(12, 4, 8), Color(0.56, 0.50, 0.44)],
			[Vector3(24, 2.0, 24), Vector3(8, 4, 8), Color(0.46, 0.52, 0.50)],
			[Vector3(-40, 3.0, -16), Vector3(9, 6, 8), Color(0.48, 0.48, 0.55)],
			# A few wrecked cars as small obstacles
			[Vector3(-9, 0.7, 14), Vector3(2.0, 1.4, 4.2), Color(0.55, 0.20, 0.18)],
			[Vector3(14, 0.7, 4), Vector3(4.2, 1.4, 2.0), Color(0.22, 0.30, 0.45)],
			[Vector3(-15, 0.7, -8), Vector3(2.0, 1.4, 4.2), Color(0.35, 0.36, 0.30)]]:
		_add_box(b[0], b[1], b[2])
		_solid(b[0], b[1])

	# The M777 is added by main before build() so the navmesh routes around it;
	# vehicles move, so they stay out of the navmesh.

	# Tiles share their edges exactly, so they join up without "edge connections" (which look
	# for near-misses between every pair of loose edges: minutes per map update on a big map)
	NavigationServer3D.map_set_use_edge_connections(get_world_3d().navigation_map, false)
	_bake_navigation()


func floor_y(p: Vector3) -> float:
	## Height of the ground (or whatever is solid) right below p
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 2.0, p.z), Vector3(p.x, p.y - 10.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p.y if hit.is_empty() else (hit.position as Vector3).y


func ground_spot(p: Vector3, search := 30.0) -> Vector3:
	## The nearest walkable spot at street level: on the navmesh, not on a roof and not
	## inside anything solid. Searches outward in rings up to `search` metres.
	var map := get_navigation_map()
	var space := get_world_3d().direct_space_state
	var r := 0.0
	while r <= search:
		var n := 1 if r == 0.0 else int(TAU * r / 3.0)
		for k in n:
			var a := TAU * k / n
			var q := NavigationServer3D.map_get_closest_point(map, p + Vector3(cos(a) * r, 0.0, sin(a) * r))
			if q == Vector3.ZERO or q.y > 1.0:
				continue
			var probe := PhysicsShapeQueryParameters3D.new()
			var shape := SphereShape3D.new()
			shape.radius = 0.4
			probe.shape = shape
			probe.transform = Transform3D(Basis.IDENTITY, q + Vector3.UP * 0.9)
			probe.collision_mask = 1
			if space.intersect_shape(probe, 1).is_empty():
				return q
		r += 3.0
	var fallback := NavigationServer3D.map_get_closest_point(map, p)
	return p if fallback == Vector3.ZERO else fallback


func _solid(center: Vector3, box_size: Vector3) -> void:
	var hx := box_size.x * 0.5
	var hz := box_size.z * 0.5
	var pts := PackedVector3Array([Vector3(center.x - hx, 0, center.z - hz), Vector3(center.x + hx, 0, center.z - hz),
		Vector3(center.x + hx, 0, center.z + hz), Vector3(center.x - hx, 0, center.z + hz)])
	_extra_solids.append([pts, box_size.y])


func _add_box(pos: Vector3, box_size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = box_size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = make_material(color)
	body.add_child(mi)
	add_child(body)
	body.position = pos
	return body


func _add_visual(pos: Vector3, box_size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = make_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = pos


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.60, 0.64)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.70)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


const PATH_POLYS := 0            # how many navmesh polygons a path search may visit: 0 = no limit (Godot's default, 4096,
                                 # cuts long paths short on a big detailed map)


static func find_path(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	## Like NavigationServer3D.map_get_path, without the default search limit
	var q := NavigationPathQueryParameters3D.new()
	q.map = map
	q.start_position = from
	q.target_position = to
	q.path_search_max_polygons = PATH_POLYS
	q.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path


func nav_ready() -> bool:
	## True once the navigation map around the holdout is built and usable
	var map := get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	return NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 20)) != Vector3.ZERO


func _nav_template() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.border_size = NAV_BORDER
	return nm


func _bake_navigation() -> void:
	## The city is too big to bake in one go, so it's cut into 64 m tiles. Tiles near the
	## holdout bake immediately; the rest bake in the background, a few at a time.
	_nav_src = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_nav_template(), _nav_src, self)
	# Carve every solid box out of the navmesh (otherwise the floor inside each building
	# bakes as a sealed walkable room, and units can be snapped into it). Roofs stay: the
	# obstruction stops just under them.
	for s in city.solids:
		_nav_src.add_projected_obstruction(s[0], -1.0, maxf(0.5, s[1] - 0.4), false)
	for s in _extra_solids:
		_nav_src.add_projected_obstruction(s[0], -1.0, maxf(0.5, s[1] - 0.4), false)
	if pre_bake.is_valid():
		pre_bake.call()
	# Tiles are offset by half a tile so the holdout sits in the middle of one, not on a seam
	var tiles: Array = []
	var nx := int(ceilf((CityBuilder.HALF_X - NAV_TILE * 0.5) / NAV_TILE))
	var nz := int(ceilf((CityBuilder.HALF_Z - NAV_TILE * 0.5) / NAV_TILE))
	for ix in range(-nx - 1, nx + 1):
		for iz in range(-nz - 1, nz + 1):
			var origin := Vector3(ix * NAV_TILE - NAV_TILE * 0.5, 0.0, iz * NAV_TILE - NAV_TILE * 0.5)
			if origin.x + NAV_TILE < -CityBuilder.HALF_X or origin.x > CityBuilder.HALF_X:
				continue
			if origin.z + NAV_TILE < -CityBuilder.HALF_Z or origin.z > CityBuilder.HALF_Z:
				continue
			var centre := origin + Vector3(NAV_TILE, 0, NAV_TILE) * 0.5
			tiles.append({"origin": origin, "dist": Vector2(centre.x, centre.z).length()})
	tiles.sort_custom(func(a, b): return a.dist < b.dist)
	nav_total = tiles.size()
	for t in tiles:
		var region := NavigationRegion3D.new()
		add_child(region)
		# Take each tile into the map as soon as it's set (on a big map, background processing
		# of hundreds of tiles fell far behind and left whole areas off the map)
		NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
		t["region"] = region
		_tiles.append(t)
		if t.dist < NAV_INSTANT_RADIUS:
			var nm := _tile_mesh(t.origin)
			NavigationServer3D.bake_from_source_geometry_data(nm, _bake_src())
			region.navigation_mesh = nm
			nav_done += 1
		else:
			_nav_queue.append(t)
	set_process(true)


func map_settled() -> bool:
	## Every tile is baked and the navigation map has caught up with all of them
	return nav_done >= nav_total and _held.is_empty() and _touch_after < 0 and _nav_finished.is_empty() \
		and NavigationServer3D.map_get_iteration_id(get_navigation_map()) >= _settle_iter


func _after_nav_change() -> void:
	## The navigation map rebuilds itself in the background. On a big map one rebuild takes a
	## while, and tiles changed while a rebuild is running can be left out of it (parts of the
	## map then stay unreachable). So once the rebuild that was running finishes, nudge the map
	## to rebuild once more, which picks up everything.
	_touch_after = NavigationServer3D.map_get_iteration_id(get_navigation_map()) + 1
	set_process(true)


func _tile_mesh(origin: Vector3) -> NavigationMesh:
	var nm := _nav_template()
	nm.filter_baking_aabb = AABB(origin - Vector3(NAV_BORDER, 2.0, NAV_BORDER),
		Vector3(NAV_TILE + NAV_BORDER * 2.0, 130.0, NAV_TILE + NAV_BORDER * 2.0))
	return nm


func _process(delta: float) -> void:
	# Re-bake tiles touched by structures that were finished or destroyed (batched)
	if not _dirty_tiles.is_empty():
		_rebake_cd -= delta
		if _rebake_cd <= 0.0:
			for idx in _dirty_tiles.keys():
				var t: Dictionary = _tiles[idx]
				if not t.get("queued", false):
					t["queued"] = true
					t["rebake"] = true
					_nav_queue.push_front(t)
			_dirty_tiles.clear()
	while _nav_running < NAV_PARALLEL and not _nav_queue.is_empty():
		var t: Dictionary = _nav_queue.pop_front()
		t["queued"] = false
		var nm := _tile_mesh(t.origin)
		_nav_running += 1
		NavigationServer3D.bake_from_source_geometry_data_async(nm, _bake_src(), _tile_baked.bind(t.region, nm, t.get("rebake", false)))
		t["rebake"] = false
	_nav_apply_cd -= delta
	if _nav_apply_cd <= 0.0 and not _nav_finished.is_empty():
		_nav_apply_cd = NAV_APPLY_INTERVAL
		var fresh := 0
		var changed := false
		for f in _nav_finished:
			if f[2]:
				(f[0] as NavigationRegion3D).navigation_mesh = f[1]     # a re-bake: in right away
				changed = true
			else:
				_held.append(f)       # a first bake: held until they're all done (see below)
				fresh += 1
		_nav_finished.clear()
		if fresh > 0:
			nav_done += fresh
			# Every rebuild of the navigation map has to redo the whole map, so on a big map
			# adding tiles a few at a time means dozens of slow rebuilds. All at once: one.
			if nav_done >= nav_total:
				for f in _held:
					if (f[0] as NavigationRegion3D).navigation_mesh == null:     # (unless a re-bake got there first)
						(f[0] as NavigationRegion3D).navigation_mesh = f[1]
				_held.clear()
				changed = true
			nav_progress.emit(nav_done, nav_total)
		if changed:
			_after_nav_change()
	# (see _after_nav_change)
	if _touch_after >= 0 and NavigationServer3D.map_get_iteration_id(get_navigation_map()) >= _touch_after:
		_touch_after = -1
		_touch_flip = not _touch_flip
		NavigationServer3D.region_set_travel_cost(_tiles[0].region.get_rid(), 1.000001 if _touch_flip else 1.0)
		_settle_iter = NavigationServer3D.map_get_iteration_id(get_navigation_map()) + 1


func _tile_baked(region: NavigationRegion3D, nm: NavigationMesh, rebake: bool) -> void:
	_tile_done.call_deferred(region, nm, rebake)


func _tile_done(region: NavigationRegion3D, nm: NavigationMesh, rebake: bool) -> void:
	_nav_running -= 1
	_nav_finished.append([region, nm, rebake])


# --- Structures ---------------------------------------------------------------------

func add_structure(s: Structure) -> void:
	s.level = self
	if s.get_parent() == null:
		add_child(s)
	structures.append(s)
	s.state_changed.connect(_on_structure_changed)
	if s.is_built():
		_on_structure_changed(s)


func _on_structure_changed(s: Structure) -> void:
	if s.state == "removed":
		structures.erase(s)
	if s.kind == "runway" or s.state == "planned" or s.state == "building":
		return
	_mark_dirty(s.footprint_world())


func add_blocker(n: Node3D) -> void:
	if not (n in blockers):
		blockers.append(n)
	_mark_dirty(n.footprint_world())


func remove_blocker(n: Node3D) -> void:
	if n in blockers:
		blockers.erase(n)
		_mark_dirty(n.footprint_world())


func _mark_dirty(pts: PackedVector3Array) -> void:
	_dyn_dirty = true
	# Every tile whose bake area overlaps the piece
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var r := Rect2(lo, hi - lo).grow(NAV_BORDER + 1.0)
	for i in _tiles.size():
		var o: Vector3 = _tiles[i].origin
		if Rect2(Vector2(o.x, o.z), Vector2(NAV_TILE, NAV_TILE)).intersects(r):
			_dirty_tiles[i] = true
	_rebake_cd = REBAKE_DELAY
	set_process(true)


func _bake_src() -> NavigationMeshSourceGeometryData3D:
	## The city as parsed at the start, plus every built structure
	if not _dyn_dirty and _dyn_src != null:
		return _dyn_src
	var any := not blockers.is_empty()
	for s in structures:
		if s.is_built():
			any = true
			break
	if not any:
		_dyn_dirty = false
		_dyn_src = _nav_src
		return _dyn_src
	var src := NavigationMeshSourceGeometryData3D.new()
	src.merge(_nav_src)
	for s in structures + blockers:
		var part: Dictionary = s.nav_part()
		for o in part.obs:
			src.add_projected_obstruction(o[0], o[1], o[2], false)
		if not (part.faces as PackedVector3Array).is_empty():
			src.add_faces(part.faces, Transform3D.IDENTITY)
	_dyn_src = src
	_dyn_dirty = false
	return src


func damage_structures(at: Vector3, radius: float, amount: float, sides := ["blue", "red"]) -> void:
	## Blast damage to walls and buildings (falls off to half at the edge)
	for s in structures.duplicate():
		if not is_instance_valid(s) or not s.is_solid() or not (s.side in sides):
			continue
		var d: float = s.flat_distance(at)
		if d < radius:
			s.take_damage(amount * (1.0 - 0.5 * d / radius))


func structure_at(p: Vector3, max_dist := 1.0) -> Structure:
	for s in structures:
		if is_instance_valid(s) and s.state != "removed" and s.flat_distance(p) <= max_dist:
			return s
	return null


static func make_material(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
