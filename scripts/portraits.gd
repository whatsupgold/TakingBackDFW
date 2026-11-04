class_name Portraits
extends Node
## Little pixel portraits of the units for the HUD cards: each kind is rendered once from
## its real 3D model in a tiny off-screen viewport (its own world, light and camera) and the
## texture is shared by every card of that kind. Soldiers get a head-and-shoulders shot in
## their squad color; vehicles are shown whole.

const SIZE := Vector2i(36, 24)        # rendered pixels (shown at 2x)

var _cache := {}


func texture_for(unit) -> Texture2D:
	var key := _key(unit)
	if not _cache.has(key):
		_cache[key] = _render(unit)
	return _cache[key]


func _key(unit) -> String:
	if unit is Squad:
		return "squad_%s_%s" % [unit.kind, (unit.color as Color).to_html()]
	if unit is Artillery:
		return "m777"
	if unit is A10:
		return "a10"
	if unit is Chinook:
		return "chinook"
	if unit is Apache:
		return "apache"
	if unit is LittleBird:
		return "mh6"
	if unit is Helicopter:
		return "huey"
	if unit is Bradley:
		return "bradley"
	if unit is Lmtv:
		return "lmtv"
	if unit is FuelTruck:
		return "fuel"
	if unit is Stryker:
		return "stryker"
	if unit is Pls:
		return "pls"
	return "humvee"


func _render(unit) -> Texture2D:
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
	var focus := Vector3.ZERO
	var frame := 1.0                     # vertical metres in view
	var yaw := 0.0
	if unit is Squad:
		var sm := SoldierModel.new()
		vp.add_child(sm)
		sm.build(unit.color, false, unit.kind, unit.kind == "rifle")
		sm.allow_kneel = false
		model = sm
		focus = Vector3(0, 1.28, 0)
		frame = 0.95
		yaw = PI - deg_to_rad(25.0)        # models face -Z: turn him toward the camera
	else:
		match _key(unit):
			"m777":
				model = VehicleModel.m777(20.0)
				focus = Vector3(0, 1.0, -1.2)
				frame = 5.5
			"a10":
				model = HeliModels.a10()
				focus = Vector3(0, 2.4, 0)
				frame = 11.0
			"chinook":
				model = HeliModels.chinook()
				focus = Vector3(0, 2.6, 0)
				frame = 11.0
			"huey":
				model = HeliModels.black_hawk()
				focus = Vector3(0, 2.0, 1.5)
				frame = 8.5
			"apache":
				model = HeliModels.apache()
				focus = Vector3(0, 2.0, 1.2)
				frame = 8.0
			"mh6":
				model = VehicleModel.mh6_smooth()
				focus = Vector3(0, 1.4, 0.8)
				frame = 5.0
			"bradley":
				model = VehicleModel.bradley()
				focus = Vector3(0, 1.5, 0)
				frame = 5.8
			"lmtv":
				model = VehicleModel.lmtv()
				focus = Vector3(0, 1.5, 0)
				frame = 6.0
			"fuel":
				model = VehicleModel.fuel_truck()
				focus = Vector3(0, 1.5, 0)
				frame = 7.0
			"pls":
				model = VehicleModel.pls()
				focus = Vector3(0, 1.5, 0)
				frame = 7.0
			"stryker":
				model = VehicleModel.stryker()
				focus = Vector3(0, 1.4, 0)
				frame = 5.5
			_:
				model = VehicleModel.humvee()
				focus = Vector3(0, 1.1, 0)
				frame = 4.2
		vp.add_child(model)
		yaw = PI - deg_to_rad(55.0)
	model.rotation.y = yaw

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame
	cam.near = 0.1
	cam.far = 200.0
	var b := Basis.from_euler(Vector3(deg_to_rad(-20.0), 0.0, 0.0))
	cam.transform = Transform3D(b, focus + b.z * 60.0)
	vp.add_child(cam)
	cam.current = true
	return vp.get_texture()
