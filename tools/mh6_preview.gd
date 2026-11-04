extends SceneTree
## Renders the faceted and the smooth MH-6 side by side, in close-up, from a few angles.
## godot --path . --rendering-driver opengl3 -s tools/mh6_preview.gd -- out_prefix

var _vp: SubViewport
var _cam: Camera3D
var _frame := 0
var _shots: Array = []
var _prefix := "mh6"
var _models: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_prefix = args[0]
	_vp = SubViewport.new()
	_vp.size = Vector2i(1600, 900)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.55, 0.78)
	sm.sky_horizon_color = Color(0.70, 0.76, 0.82)
	sm.ground_horizon_color = Color(0.55, 0.55, 0.52)
	sm.ground_bottom_color = Color(0.30, 0.30, 0.28)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-38), 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_vp.add_child(sun)
	# Ground: an asphalt pad
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.50, 0.48, 0.44)
	gm.roughness = 0.95
	g.material_override = gm
	_vp.add_child(g)
	# Which model: mh6 (side by side with the faceted one), blackhawk, chinook, apache
	var kind: String = args[1] if args.size() > 1 else "mh6"
	var models := {"blackhawk": HeliModels.black_hawk, "chinook": HeliModels.chinook, "apache": HeliModels.apache, "a10": HeliModels.a10}
	var k: float = {"mh6": 1.0, "blackhawk": 2.0, "chinook": 2.6, "apache": 1.8, "a10": 2.1, "c130": 4.2}[kind]
	var cx := 3.3 if kind == "mh6" else 0.0
	if kind == "mh6":
		var old := VehicleModel.mh6()
		old.position = Vector3(-3.3, 0, 0)
		_models.append(old)
		var smooth := VehicleModel.mh6_smooth()
		smooth.position = Vector3(3.3, 0, 0)
		_models.append(smooth)
	elif kind == "c130":
		var c := Node3D.new()
		c.position = Vector3(0, 2.6, 0)
		HeliModels.c130(c)
		_models.append(c)
	else:
		_models.append((models[kind] as Callable).call())
	for m in _models:
		if m is VehicleModel:
			m.rotor_factor = 0.0
		_vp.add_child(m)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_vp.add_child(_cam)
	_cam.current = true
	var c := Vector3(cx, 1.3 * k, 0.6 * k)
	_shots = [
		["front34", c + Vector3(7.5, 2.4, -7.0) * k, c],
		["side", c + Vector3(11.0, 0.4, 0.0) * k, c],
		["rear34", c + Vector3(8.0, 3.6, 9.0) * k, c],
		["cockpit", Vector3(cx + 1.2 * k, 1.7 * k, -4.6 * k), Vector3(cx, 1.4 * k, -1.6 * k)],
		["top", c + Vector3(0.01, 13.0 * k, 0.0), c],
	]
	RenderingServer.global_shader_parameter_set("unit_outline", 0.008)
	RenderingServer.global_shader_parameter_set("soldier_outline", 0.008)


func _process(_delta: float) -> bool:
	_frame += 1
	var i := (_frame - 5) / 6
	if _frame < 5:
		return false
	if i >= _shots.size():
		return true
	var s: Array = _shots[i]
	_cam.look_at_from_position(s[1], s[2], Vector3.UP if s[0] != "top" else Vector3.FORWARD)
	if (_frame - 5) % 6 == 5:
		var path := "%s_%s.png" % [_prefix, s[0]]
		_vp.get_texture().get_image().save_png(path)
		print("PREVIEW: saved ", path)
	return false
