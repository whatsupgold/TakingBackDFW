extends SceneTree
## Renders each fleet model from a few angles, for checking them.
## godot --path . --rendering-driver opengl3 -s tools/ship_preview.gd -- out_prefix

var _vp: SubViewport
var _cam: Camera3D
var _frame := 0
var _prefix := "ships"
var _shots: Array = []                 # [ship node, yaw, pitch, size, focus offset, name]
var _ships := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_prefix = args[0]
	_vp = SubViewport.new()
	_vp.size = Vector2i(1400, 800)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.80)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	_vp.add_child(sun)
	TexasWaterLook.setup()
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	sea.mesh = pm
	sea.material_override = TexasWaterLook.sea
	_vp.add_child(sea)
	var x := 0.0
	for id in ["carrier", "amphib", "destroyer", "cruiser", "lcac"]:
		var m := ShipModels.by_type(id)
		m.position = Vector3(x, 0, 0)
		_vp.add_child(m)
		_ships[id] = m
		x += 600.0
	ShipModels.hull_number(_ships.destroyer, "57")
	ShipModels.hull_number(_ships.cruiser, "60")
	ShipModels.hull_number(_ships.amphib, "3")
	if _ships.amphib.has_meta("gate"):
		(_ships.amphib.get_meta("gate") as Node3D).rotation.x = deg_to_rad(95)
	_shots = [["carrier", -35.0, -30.0, 300.0, Vector3.ZERO], ["carrier", 150.0, -25.0, 120.0, Vector3(25, 25, 60)],
		["amphib", -40.0, -28.0, 230.0, Vector3.ZERO], ["amphib", 160.0, -18.0, 70.0, Vector3(0, 6, 120)],
		["destroyer", -40.0, -25.0, 110.0, Vector3.ZERO], ["destroyer", -150.0, -30.0, 60.0, Vector3(0, 10, -30)],
		["cruiser", 40.0, -25.0, 120.0, Vector3.ZERO], ["lcac", -40.0, -30.0, 34.0, Vector3.ZERO]]
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_cam.current = true


func _process(_delta: float) -> bool:
	var v: int = _frame / 4
	if v >= _shots.size():
		return true
	var s: Array = _shots[v]
	var b := Basis.from_euler(Vector3(deg_to_rad(s[2]), deg_to_rad(s[1]), 0))
	_cam.size = s[3]
	_cam.far = 6000
	var focus: Vector3 = (_ships[s[0]] as Node3D).position + s[4]
	_cam.global_transform = Transform3D(b, focus + b.z * 2000.0)
	if _frame % 4 == 3:
		_vp.get_texture().get_image().save_png("%s_%d_%s.png" % [_prefix, v, s[0]])
	_frame += 1
	return false
