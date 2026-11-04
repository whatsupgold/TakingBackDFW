class_name TexasWaterLook
extends RefCounted
## The look of the water: one shader for the sea, the lakes and the rivers, with the ripple and
## foam textures made once and shared.

const SHADER := preload("res://scripts/texas/shaders/water.gdshader")
const WRAP := 7680.0                     # the ripple textures repeat within this (game m)

static var sea: ShaderMaterial
static var inland: ShaderMaterial


static func setup() -> void:
	if sea != null:
		return
	var a := _noise(0.018, 7, 6.0)
	var b := _noise(0.03, 23, 4.0)
	var fn := NoiseTexture2D.new()
	fn.seamless = true
	fn.width = 256
	fn.height = 256
	var nf := FastNoiseLite.new()
	nf.seed = 41
	nf.frequency = 0.04
	nf.fractal_octaves = 3
	fn.noise = nf
	sea = ShaderMaterial.new()
	sea.shader = SHADER
	sea.set_shader_parameter("ripples_a", a)
	sea.set_shader_parameter("ripples_b", b)
	sea.set_shader_parameter("foam_noise", fn)
	# drawn before anything see-through (smoke, foam, missile trails) so it never paints over them
	sea.render_priority = -10
	inland = sea.duplicate()
	inland.set_shader_parameter("surf", 0.0)
	inland.set_shader_parameter("depth_tint", 0.0)
	inland.set_shader_parameter("min_alpha", 0.9)
	inland.set_shader_parameter("ripple", 0.35)
	inland.set_shader_parameter("shallow_color", Color(0.16, 0.33, 0.38))


static func _noise(freq: float, seed_: int, bump: float) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = bump
	t.width = 512
	t.height = 512
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = 4
	t.noise = n
	return t


static func set_origin(ox: float, oz: float) -> void:
	## The ripples are laid out in true map coordinates, wrapped so the numbers stay small
	if sea == null:
		return
	var o := Vector2(fposmod(ox, WRAP), fposmod(oz, WRAP))
	sea.set_shader_parameter("origin", o)
	inland.set_shader_parameter("origin", o)


static var _foam_mat: StandardMaterial3D


static func wake(length: float, beam: float) -> Node3D:
	## Foam churned up behind a ship (and a smaller wave at the bow): it stays where it was
	## left on the water and spreads and fades, so a moving ship draws a widening trail.
	## Switch it on and off with set_wake().
	var root := Node3D.new()
	root.name = "Wake"
	# (lifetimes in game seconds: the foam ages with the game clock, so the trail is as long
	# at any speed and stays put while paused)
	var w := maxf(beam, 34.0)              # narrow hulls still churn up a good width of water
	root.add_child(_foam("Stern", Vector3(0, 0.6, length * 0.5), beam * 0.35, 200, 70.0, w * 0.8, 2.2, 0.1, 0.6))
	root.add_child(_foam("Bow", Vector3(0, 0.6, -length * 0.42), beam * 0.25, 60, 12.0, w * 0.5, 2.0, 0.6, 1.6))
	return root


static func set_wake(wake_node: Node, on: bool, game_speed := 1.0) -> void:
	if wake_node == null:
		return
	for c in wake_node.get_children():
		var p := c as CPUParticles3D
		if p == null:
			continue
		if p.emitting != on:
			p.emitting = on
		p.speed_scale = game_speed


static func _foam(nm: String, at: Vector3, half_w: float, amount: int, life: float, size: float,
		grow: float, v0: float, v1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = nm
	p.position = at
	p.local_coords = false
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half_w, 0.0, 2.0)
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.flatness = 1.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.damping_min = 0.15
	p.damping_max = 0.4
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = size * 0.8
	p.scale_amount_max = size * 1.2
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.orientation = PlaneMesh.FACE_Y
	q.material = _foam_material()
	p.mesh = q
	return p


static func _foam_material() -> StandardMaterial3D:
	if _foam_mat != null:
		return _foam_mat
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.7))
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.95, 0.97, 0.98)
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 1
	_foam_mat = m
	return m
