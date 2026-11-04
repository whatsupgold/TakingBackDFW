class_name UnitLook
extends RefCounted
## Shared look for units: the outline and the soldier material.
##
## Outline: every unit part gets a child mesh with the same shape, a little bigger, drawn
## dark and inside-out (front faces culled), so a 1-pixel dark edge shows around the unit's
## silhouette. The outline is pushed a bit away from the camera, so the unit's own parts
## hide it inside the silhouette (no lines across the body) while the ground behind doesn't.
## Its width follows the zoom: the camera reports the size of one game pixel in metres every
## frame (set_pixel). Soldiers drop their outline when zoomed far out.
##
## Soldier parts are merged meshes with vertex colors. Vertex alpha 0 marks "team color"
## (the vest, helmet band): those take the soldier's team_color, times the vertex color as a
## shade, so the meshes are shared and each soldier only has his own small material.

const OUTLINE_COLOR := Color(0.07, 0.06, 0.06)
const PUSH := 0.25                     # metres the outline is pushed away from the camera
const WIDTH := 0.55                    # outline growth per game pixel (see set_pixel)
const SOLDIER_FADE := Vector2(0.12, 0.15)   # metres per game pixel: full outline .. none
const TEAM_RANGE := 1.25               # team shades are stored divided by this

const OUTLINE_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, skip_vertex_transform, shadows_disabled, fog_disabled;
global uniform float unit_outline;
global uniform float soldier_outline;
uniform vec4 outline_color : source_color;
uniform bool box_mode = false;
uniform bool soldier_width = true;   // merged meshes: soldiers fade their outline out when zoomed far
uniform float push = 0.25;

void vertex() {
	// box_mode: a plain BoxMesh/CylinderMesh centred on its origin; otherwise each vertex
	// carries its box's outward corner direction in CUSTOM0
	vec3 dir = box_mode ? sign(VERTEX) : CUSTOM0.xyz;
	vec3 v = VERTEX + dir * ((box_mode || !soldier_width) ? unit_outline : soldier_outline);
	VERTEX = (MODELVIEW_MATRIX * vec4(v, 1.0)).xyz;
	VERTEX.z -= push;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

const SOLDIER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 team_color : source_color = vec4(1.0);

void fragment() {
	// COLOR arrives already linear (the mesh's vertex colors are converted on the way in)
	vec3 c;
	if (COLOR.a < 0.5) {
		c = COLOR.rgb * 1.25 * team_color.rgb;
	} else {
		c = COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""

static var _outline_box: ShaderMaterial
static var _outline_merged: ShaderMaterial
static var _outline_vehicle: ShaderMaterial
static var _soldier: ShaderMaterial
static var _vehicle: ShaderMaterial

const VEHICLE_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec3 key_dir = vec3(0.45, 0.85, 0.30);
uniform float shadow_side = 0.6;    // a face turned away from key_dir is this much of its colour

void fragment() {
	// Low-poly vehicles: flat-shaded faces in their vertex colours, with a fixed "key light"
	// baked into the colour so neighbouring facets read as clearly different tones
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float k = clamp(dot(wn, normalize(key_dir)), 0.0, 1.0);
	ALBEDO = COLOR.rgb * mix(shadow_side, 1.0, k) * 0.9;
	ROUGHNESS = 1.0;
}
"""


static func vehicle_material() -> ShaderMaterial:
	if _vehicle == null:
		var sh := Shader.new()
		sh.code = VEHICLE_CODE
		_vehicle = ShaderMaterial.new()
		_vehicle.shader = sh
	return _vehicle


static func soldier_material() -> ShaderMaterial:
	if _soldier == null:
		var sh := Shader.new()
		sh.code = SOLDIER_CODE
		_soldier = ShaderMaterial.new()
		_soldier.shader = sh
	return _soldier


static func outline_material(box_mode: bool, soldier := true) -> ShaderMaterial:
	if box_mode and _outline_box != null:
		return _outline_box
	if not box_mode and soldier and _outline_merged != null:
		return _outline_merged
	if not box_mode and not soldier and _outline_vehicle != null:
		return _outline_vehicle
	var sh := Shader.new()
	sh.code = OUTLINE_CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("outline_color", OUTLINE_COLOR)
	m.set_shader_parameter("box_mode", box_mode)
	m.set_shader_parameter("push", PUSH)
	m.set_shader_parameter("soldier_width", soldier)
	m.render_priority = -1
	if box_mode:
		_outline_box = m
	elif soldier:
		_outline_merged = m
	else:
		_outline_vehicle = m
	return m


static func add_outline(mi: MeshInstance3D, box_mode := true, soldier := true) -> MeshInstance3D:
	## A dark inside-out copy of this mesh as its child (so it moves and hides with it)
	var o := MeshInstance3D.new()
	o.name = "Outline"
	o.mesh = mi.mesh
	o.material_override = outline_material(box_mode, soldier)
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.set_meta("outline", true)
	mi.add_child(o)
	return o


static func outline_tree(root: Node) -> void:
	## Outline every plain mesh under root (vehicles: BoxMesh and CylinderMesh parts)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta("outline") or mi.has_meta("no_outline"):
			continue
		if mi.mesh is BoxMesh or mi.mesh is CylinderMesh:
			add_outline(mi, true)


static func set_pixel(metres: float) -> void:
	## Called by the camera with the size of one game pixel. Boxes seen at the isometric angle
	## grow on screen by about 1.5x what they grow in the world, so this keeps the edge 1 pixel.
	RenderingServer.global_shader_parameter_set("unit_outline", metres * WIDTH)
	# Zoomed far out a soldier is only a few pixels tall and an outline would swallow him:
	# soldiers' outlines fade out between SOLDIER_FADE pixel sizes (vehicles keep theirs)
	var k := clampf(inverse_lerp(SOLDIER_FADE.y, SOLDIER_FADE.x, metres), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("soldier_outline", metres * WIDTH * k)
