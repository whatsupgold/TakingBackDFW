class_name TexasPortraits
extends Node
## Little pixel portraits for the unit cards, one per kind of unit, each rendered once from its
## real 3D model in a tiny off-screen viewport (as in the DFW battle) and shared by every card.

const SIZE := Vector2i(36, 24)         # rendered pixels (shown at 2x)
const BLUE := Color(0.30, 0.55, 0.90)

var _cache := {}


func texture_for(type_id: String) -> Texture2D:
	if not _cache.has(type_id):
		_cache[type_id] = _render(type_id)
	return _cache[type_id]


func _render(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.55
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.1
	vp.add_child(sun)

	var model: Node3D
	var focus := Vector3(0, 1.4, 0)
	var frame := 5.5                       # vertical metres in view
	var yaw := PI - deg_to_rad(55.0)
	match id:
		"rifle":
			var sm := SoldierModel.new()
			vp.add_child(sm)
			sm.build(BLUE, false, "rifle", true)
			sm.allow_kneel = false
			model = sm
			focus = Vector3(0, 1.28, 0)
			frame = 0.95
			yaw = PI - deg_to_rad(25.0)
		"humvee":
			model = VehicleModel.humvee()
			focus = Vector3(0, 1.1, 0)
			frame = 4.2
		"stryker":
			model = VehicleModel.stryker()
		"bradley":
			model = VehicleModel.bradley()
			frame = 5.8
		"lmtv":
			model = VehicleModel.lmtv()
			focus = Vector3(0, 1.5, 0)
			frame = 6.0
		"tank":
			model = VehicleModel.red_tank()
			frame = 6.0
		"aa":
			model = VehicleModel.red_aa()
			frame = 6.0
		"black_hawk":
			model = HeliModels.black_hawk()
			focus = Vector3(0, 2.0, 1.5)
			frame = 8.5
		"chinook":
			model = HeliModels.chinook()
			focus = Vector3(0, 2.6, 0)
			frame = 11.0
		"apache":
			model = HeliModels.apache()
			focus = Vector3(0, 2.0, 1.2)
			frame = 8.0
		"little_bird":
			model = VehicleModel.mh6_smooth()
			focus = Vector3(0, 1.4, 0.8)
			frame = 5.0
		"hornet", "a10":
			model = HeliModels.a10()
			focus = Vector3(0, 2.4, 0)
			frame = 11.0
		_:
			model = ShipModels.by_type(id)
			var hull: Vector2 = TexasFormation.HULL.get(id, Vector2(27, 14))
			frame = hull.x * 0.42
			focus = Vector3(0, hull.x * 0.05, 0)
			yaw = PI - deg_to_rad(70.0)
	if model == null:
		model = VehicleModel.humvee()
	if model.get_parent() == null:
		vp.add_child(model)
	model.rotation.y = yaw
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame
	cam.near = 0.1
	cam.far = 2000.0
	var b := Basis.from_euler(Vector3(deg_to_rad(-20.0), 0.0, 0.0))
	cam.transform = Transform3D(b, focus + b.z * maxf(60.0, frame * 4.0))
	vp.add_child(cam)
	cam.current = true
	return vp.get_texture()
