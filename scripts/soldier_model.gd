class_name SoldierModel
extends Node3D
## Blocky "voxel" soldier, so it reads as pixel art through the low-res pipeline, with a dark
## 1-pixel outline (see UnitLook).
##
## Built from boxes merged into one mesh per moving part (legs in two pieces, torso, head,
## arms with the rifle), with vertex colors in two or three tones per part. The meshes are
## shared by every soldier of a kind; the squad color (vest, helmet band) is a parameter of
## the soldier's own material, so set_damage() only changes a parameter.
##
## Your soldiers: olive uniform, plate carrier in the squad color, helmet with an NVG mount and
## a squad-color band, knee pads, backpack, M4. The squad leader carries a radio with an
## antenna; engineers carry a shovel. Red Army: khaki uniform, red chest rig over it, round
## helmet with a wide flared rim and a red star, bedroll and canteen instead of a backpack,
## AK with a wooden stock and a curved magazine.
##
## Animation: legs walk with bending knees, the rifle sways at the low ready while walking,
## comes up to the shoulder when he fires (and stays up a moment), kicks back with each shot,
## and a soldier who stands still while fighting drops to one knee.
## The model faces -Z (the direction look_at() points), about 1.75 m tall.

const UNIFORM := Color(0.30, 0.34, 0.22)      # olive drab
const UNIFORM_DARK := Color(0.22, 0.25, 0.16)
const BOOTS := Color(0.24, 0.19, 0.13)
const SKIN := Color(0.80, 0.62, 0.48)
const GEAR := Color(0.13, 0.13, 0.12)          # rifle, belt, straps
const PADS := Color(0.19, 0.19, 0.16)
const GLOVES := Color(0.45, 0.39, 0.28)
const PACK := Color(0.35, 0.30, 0.20)
const HELMET := Color(0.36, 0.38, 0.26)
const FLASH := Color(1.0, 0.85, 0.35)
const WOOD := Color(0.42, 0.30, 0.17)
const STEEL := Color(0.30, 0.31, 0.31)
const EYES := Color(0.12, 0.10, 0.10)
const RED_UNIFORM := Color(0.46, 0.41, 0.29)    # Red Army khaki
const RED_UNIFORM_DARK := Color(0.34, 0.30, 0.21)
const RED_HELMET := Color(0.30, 0.33, 0.26)
const RED_GEAR := Color(0.40, 0.24, 0.12)       # wooden AK furniture, leather belt
const RED_METAL := Color(0.17, 0.17, 0.17)
const RED_BOOTS := Color(0.12, 0.10, 0.09)
const RED_STAR := Color(0.85, 0.16, 0.10)
const BEDROLL := Color(0.38, 0.35, 0.27)

const HIP := 0.70
const THIGH := 0.34
const STRIDE_DEG := 28.0
const STRIDE_SPEED := 11.0
const KNEE_BEND := 0.75
const LOW_READY := -0.45        # rifle angled down while not fighting
const AIM_HOLD := 2.5           # seconds the rifle stays up after a shot
const KNEEL_DROP := 0.28

var allow_kneel := true         # off for vehicle crews and tower gunners

var _color: Color
var _parts: Array[MeshInstance3D] = []
var _material: ShaderMaterial
var _rig: Node3D
var _thigh_l: Node3D
var _thigh_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Node3D
var _flash: MeshInstance3D
var _flash_time := 0.0
var _carry: MeshInstance3D
var _carrying := false
var _walk := 0.0
var _aim_t := 0.0
var _aim := 0.0                 # 0 low ready .. 1 aimed
var _recoil := 0.0
var _kneel := 0.0
var _walk_amt := 0.0

static var _meshes := {}        # shared part meshes
static var _mats := {}


func build(squad_color: Color, red := false, kind := "rifle", leader := false) -> void:
	_color = squad_color
	_material = UnitLook.soldier_material().duplicate()
	var side := "r" if red else "b"
	_rig = Node3D.new()
	add_child(_rig)

	_thigh_l = _pivot(_rig, Vector3(-0.11, HIP, 0.0), "thigh_l_" + side, func(): return _thigh_boxes(red, -1.0))
	_thigh_r = _pivot(_rig, Vector3(0.11, HIP, 0.0), "thigh_r_" + side, func(): return _thigh_boxes(red, 1.0))
	_shin_l = _pivot(_thigh_l, Vector3(0, -THIGH, 0), "shin_" + side, func(): return _shin_boxes(red))
	_shin_r = _pivot(_thigh_r, Vector3(0, -THIGH, 0), "shin_" + side, func(): return _shin_boxes(red))

	var extra := ""
	if not red:
		if leader:
			extra = "_leader"
		elif kind == "engineer":
			extra = "_eng"
	_torso = _pivot(_rig, Vector3(0, HIP, 0), "torso_" + side + extra, func(): return _torso_boxes(red, extra))
	_head = _pivot(_torso, Vector3(0, 0.68, 0), "head_" + side, func(): return _head_boxes(red))
	_arms = _pivot(_torso, Vector3(0, 0.46, 0), "arms_" + side, func(): return _arms_boxes(red))
	_arms.rotation.x = LOW_READY

	# Muzzle flash, shown for a split second per shot
	var fm := BoxMesh.new()
	fm.size = Vector3(0.16, 0.16, 0.16)
	_flash = MeshInstance3D.new()
	_flash.mesh = fm
	_flash.material_override = Level.make_material(FLASH, true)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = Vector3(0.10, 0.01, -0.88)
	_flash.visible = false
	_arms.add_child(_flash)
	_apply_color(_color)


func animate(delta: float, moving: bool) -> void:
	if moving:
		_walk += delta * STRIDE_SPEED
		_walk_amt = move_toward(_walk_amt, 1.0, delta * 6.0)
	else:
		# Ease the legs back to standing
		_walk = lerpf(_walk, roundf(_walk / PI) * PI, 1.0 - exp(-14.0 * delta))
		_walk_amt = move_toward(_walk_amt, 0.0, delta * 4.0)

	# Aim: up while fighting, low ready otherwise
	_aim_t = maxf(0.0, _aim_t - delta)
	var want_aim := 1.0 if _aim_t > 0.0 and not _carrying else 0.0
	_aim = move_toward(_aim, want_aim, delta * 6.0)
	_recoil = move_toward(_recoil, 0.0, delta * 9.0)
	# Kneel: standing still in a fight
	var want_kneel := 1.0 if allow_kneel and not moving and _aim_t > 0.0 and not _carrying else 0.0
	_kneel = move_toward(_kneel, want_kneel, delta * (4.0 if want_kneel > 0.0 else 7.0))
	var k := _smooth(_kneel)

	var s := sin(_walk)
	var c := cos(_walk)
	var swing := s * deg_to_rad(STRIDE_DEG)
	var bend_l := -maxf(0.0, c) * KNEE_BEND * _walk_amt
	var bend_r := -maxf(0.0, -c) * KNEE_BEND * _walk_amt
	# Kneeling: left foot forward, right knee on the ground
	_thigh_l.rotation.x = lerpf(swing, 1.45, k)
	_shin_l.rotation.x = lerpf(bend_l, -1.45, k)
	_thigh_r.rotation.x = lerpf(-swing, -0.12, k)
	_shin_r.rotation.x = lerpf(bend_r, -1.45, k)
	var bob := absf(s) * 0.04 * _walk_amt
	_rig.position.y = bob - KNEEL_DROP * k

	var a := _smooth(_aim)
	_torso.rotation.x = -0.08 * a
	_torso.rotation.y = s * 0.06 * _walk_amt * (1.0 - a)
	var ready := LOW_READY - 0.08 * _walk_amt
	if _carrying:
		ready = -0.65
	_arms.rotation.x = lerpf(ready, 0.08, a) + 0.14 * _recoil
	_arms.rotation.y = s * 0.07 * _walk_amt * (1.0 - a)
	_arms.position.z = 0.06 * _recoil
	_head.rotation.x = 0.06 * a

	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.visible = false


func muzzle_flash() -> void:
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash_time = 0.05
	_aim_t = AIM_HOLD
	_recoil = 1.0


func set_carry(value: bool) -> void:
	## An artillery shell held in both hands (for gun crews)
	_carrying = value
	if _carry == null:
		if not value:
			return
		var m := BoxMesh.new()
		m.size = Vector3(0.18, 0.18, 0.62)
		_carry = MeshInstance3D.new()
		_carry.mesh = m
		_carry.material_override = _mat(Color(0.55, 0.50, 0.28))
		_carry.position = Vector3(0.03, -0.12, -0.36)
		_arms.add_child(_carry)
		UnitLook.add_outline(_carry, true)
	_carry.visible = value


func set_damage(fraction: float) -> void:
	## 0 = healthy, 1 = nearly dead: the vest darkens toward blood red
	_apply_color(_color.lerp(Color(0.45, 0.05, 0.05), clampf(fraction, 0.0, 1.0)))


func _apply_color(c: Color) -> void:
	_material.set_shader_parameter("team_color", c)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# --- Parts ------------------------------------------------------------------------
# Each box: [size, position, color, rotation]. A color with alpha 0 is a shade of the
# squad color (1 = the color itself).

static func _team(shade: float) -> Color:
	return Color(shade, shade, shade, 0.0)


static func _store(c: Color) -> Color:
	## Vertex colors are 8-bit: team shades are stored at 1/TEAM_RANGE so they can go above 1
	if c.a < 0.5:
		var k := 1.0 / UnitLook.TEAM_RANGE
		return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), 0.0)
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


static func _thigh_boxes(red: bool, sx: float) -> Array:
	var uni_dark := RED_UNIFORM_DARK if red else UNIFORM_DARK
	var out := [
		[Vector3(0.17, 0.36, 0.20), Vector3(0, -0.17, 0), uni_dark],
		[Vector3(0.03, 0.11, 0.11), Vector3(sx * 0.095, -0.17, 0.0), uni_dark.darkened(0.18)],   # cargo pocket
	]
	if not red:
		out.append([Vector3(0.15, 0.09, 0.04), Vector3(0, -0.31, -0.105), PADS])   # knee pad
	return out


static func _shin_boxes(red: bool) -> Array:
	var uni_dark := RED_UNIFORM_DARK if red else UNIFORM_DARK
	if red:
		# Tall jackboots
		return [
			[Vector3(0.15, 0.14, 0.17), Vector3(0, -0.07, 0), uni_dark],
			[Vector3(0.17, 0.22, 0.19), Vector3(0, -0.23, 0), RED_BOOTS],
			[Vector3(0.17, 0.08, 0.26), Vector3(0, -0.31, -0.035), RED_BOOTS],
			[Vector3(0.18, 0.03, 0.27), Vector3(0, -0.35, -0.035), RED_BOOTS.darkened(0.4)],
		]
	return [
		[Vector3(0.16, 0.24, 0.18), Vector3(0, -0.12, 0), uni_dark],
		[Vector3(0.18, 0.11, 0.27), Vector3(0, -0.295, -0.04), BOOTS],
		[Vector3(0.185, 0.03, 0.28), Vector3(0, -0.35, -0.04), BOOTS.darkened(0.45)],
	]


static func _torso_boxes(red: bool, extra: String) -> Array:
	var uni := RED_UNIFORM if red else UNIFORM
	var uni_dark := RED_UNIFORM_DARK if red else UNIFORM_DARK
	var out := [
		[Vector3(0.38, 0.50, 0.22), Vector3(0, 0.28, 0), uni],                       # shirt
		[Vector3(0.11, 0.11, 0.23), Vector3(-0.23, 0.47, 0), uni],                   # shoulders
		[Vector3(0.11, 0.11, 0.23), Vector3(0.23, 0.47, 0), uni],
		[Vector3(0.12, 0.06, 0.12), Vector3(0, 0.54, 0), SKIN.darkened(0.12)],       # neck
	]
	if red:
		out.append_array([
			[Vector3(0.44, 0.07, 0.26), Vector3(0, 0.0, 0), RED_GEAR],               # leather belt
			[Vector3(0.37, 0.26, 0.25), Vector3(0, 0.25, 0), _team(1.0)],            # chest rig
			[Vector3(0.06, 0.16, 0.235), Vector3(-0.12, 0.40, 0), _team(0.8)],       # straps
			[Vector3(0.06, 0.16, 0.235), Vector3(0.12, 0.40, 0), _team(0.8)],
			[Vector3(0.08, 0.12, 0.05), Vector3(-0.10, 0.21, -0.14), _team(0.62)],   # AK mag pouches
			[Vector3(0.08, 0.12, 0.05), Vector3(0.0, 0.21, -0.14), _team(0.62)],
			[Vector3(0.08, 0.12, 0.05), Vector3(0.10, 0.21, -0.14), _team(0.62)],
			[Vector3(0.44, 0.10, 0.12), Vector3(0, 0.50, 0.15), BEDROLL],            # bedroll over the shoulders
			[Vector3(0.09, 0.13, 0.08), Vector3(0.22, -0.05, 0.08), Color(0.33, 0.32, 0.24)],   # canteen
			[Vector3(0.16, 0.15, 0.06), Vector3(-0.10, 0.05, 0.14), uni_dark],       # side bag
		])
		return out
	out.append_array([
		[Vector3(0.44, 0.08, 0.26), Vector3(0, 0.0, 0), GEAR],                       # belt
		[Vector3(0.08, 0.10, 0.08), Vector3(0.21, -0.02, 0.06), uni_dark],           # hip pouch
		[Vector3(0.42, 0.36, 0.27), Vector3(0, 0.30, 0), _team(1.0)],                # plate carrier
		[Vector3(0.08, 0.05, 0.27), Vector3(-0.13, 0.49, 0), _team(0.82)],           # shoulder straps
		[Vector3(0.08, 0.05, 0.27), Vector3(0.13, 0.49, 0), _team(0.82)],
		[Vector3(0.11, 0.10, 0.05), Vector3(-0.12, 0.22, -0.155), _team(0.66)],      # front pouches
		[Vector3(0.11, 0.10, 0.05), Vector3(0.0, 0.22, -0.155), _team(0.66)],
		[Vector3(0.11, 0.10, 0.05), Vector3(0.12, 0.22, -0.155), _team(0.66)],
		[Vector3(0.24, 0.26, 0.12), Vector3(0, 0.26, 0.19), PACK],                   # small assault pack
		[Vector3(0.26, 0.06, 0.13), Vector3(0, 0.41, 0.19), PACK.darkened(0.2)],
		[Vector3(0.15, 0.10, 0.04), Vector3(0, 0.20, 0.265), PACK.darkened(0.14)],
	])
	if extra == "_leader":
		out.append([Vector3(0.10, 0.16, 0.06), Vector3(0.10, 0.36, 0.30), GEAR])            # radio
		out.append([Vector3(0.025, 0.55, 0.025), Vector3(0.13, 0.70, 0.31), GEAR])           # antenna
	elif extra == "_eng":
		out.append([Vector3(0.035, 0.44, 0.035), Vector3(-0.10, 0.40, 0.30), WOOD])         # shovel
		out.append([Vector3(0.14, 0.15, 0.025), Vector3(-0.10, 0.13, 0.30), STEEL])
	return out


static func _head_boxes(red: bool) -> Array:
	var out := [
		[Vector3(0.22, 0.24, 0.22), Vector3(0, 0, 0), SKIN],
		[Vector3(0.222, 0.05, 0.222), Vector3(0, -0.10, 0), SKIN.darkened(0.12)],   # jaw shade
		[Vector3(0.04, 0.03, 0.01), Vector3(-0.05, 0.015, -0.111), EYES],
		[Vector3(0.04, 0.03, 0.01), Vector3(0.05, 0.015, -0.111), EYES],
	]
	if red:
		# Round helmet with a wide flared rim
		out.append_array([
			[Vector3(0.24, 0.08, 0.24), Vector3(0, 0.20, 0), RED_HELMET.lightened(0.06)],
			[Vector3(0.29, 0.08, 0.29), Vector3(0, 0.135, 0), RED_HELMET],
			[Vector3(0.37, 0.035, 0.37), Vector3(0, 0.085, 0.0), RED_HELMET.darkened(0.22)],
			[Vector3(0.045, 0.045, 0.01), Vector3(0, 0.14, -0.148), RED_STAR],
		])
		return out
	out.append_array([
		[Vector3(0.27, 0.10, 0.27), Vector3(0, 0.175, 0.0), HELMET],                 # dome
		[Vector3(0.29, 0.10, 0.29), Vector3(0, 0.095, 0.01), HELMET.darkened(0.12)], # sides, over the ears
		[Vector3(0.295, 0.045, 0.295), Vector3(0, 0.135, 0.01), _team(1.15)],         # squad band
		[Vector3(0.06, 0.05, 0.03), Vector3(0, 0.11, -0.155), GEAR],                 # NVG mount
	])
	return out


static func _arms_boxes(red: bool) -> Array:
	var uni := RED_UNIFORM if red else UNIFORM
	var hand := SKIN if red else GLOVES
	var out := [
		[Vector3(0.12, 0.12, 0.22), Vector3(0.24, -0.05, -0.06), uni],              # right arm
		[Vector3(0.11, 0.11, 0.20), Vector3(0.17, -0.08, -0.19), uni, Basis(Vector3.UP, 0.35)],
		[Vector3(0.09, 0.09, 0.09), Vector3(0.11, -0.075, -0.21), hand],
		[Vector3(0.12, 0.12, 0.24), Vector3(-0.23, -0.04, -0.10), uni],             # left arm
		[Vector3(0.11, 0.11, 0.34), Vector3(-0.08, -0.05, -0.33), uni, Basis(Vector3.UP, -0.55)],
		[Vector3(0.09, 0.09, 0.09), Vector3(0.07, -0.04, -0.50), hand],
	]
	if red:
		out.append([Vector3(0.13, 0.06, 0.13), Vector3(0.24, -0.02, -0.06), _team(1.0)])    # armbands
		out.append([Vector3(0.13, 0.06, 0.13), Vector3(-0.23, -0.01, -0.10), _team(1.0)])
		# AK: wooden stock, grip and handguard, curved magazine
		out.append_array([
			[Vector3(0.055, 0.09, 0.20), Vector3(0.10, -0.03, -0.03), RED_GEAR],
			[Vector3(0.065, 0.09, 0.28), Vector3(0.10, 0.0, -0.27), RED_METAL],
			[Vector3(0.05, 0.09, 0.05), Vector3(0.10, -0.085, -0.20), RED_GEAR],
			[Vector3(0.05, 0.10, 0.07), Vector3(0.10, -0.085, -0.34), RED_METAL],
			[Vector3(0.05, 0.10, 0.07), Vector3(0.10, -0.165, -0.37), RED_METAL, Basis(Vector3.RIGHT, 0.5)],
			[Vector3(0.07, 0.08, 0.16), Vector3(0.10, -0.005, -0.49), RED_GEAR],
			[Vector3(0.035, 0.035, 0.16), Vector3(0.10, 0.055, -0.49), RED_METAL],
			[Vector3(0.03, 0.03, 0.24), Vector3(0.10, 0.005, -0.69), RED_METAL],
		])
		return out
	# M4 with an optic
	out.append_array([
		[Vector3(0.06, 0.09, 0.16), Vector3(0.10, -0.01, -0.02), GEAR],
		[Vector3(0.065, 0.10, 0.30), Vector3(0.10, 0.0, -0.25), GEAR],
		[Vector3(0.05, 0.09, 0.05), Vector3(0.10, -0.085, -0.18), GEAR],
		[Vector3(0.05, 0.14, 0.07), Vector3(0.10, -0.10, -0.32), GEAR.lightened(0.12)],
		[Vector3(0.05, 0.06, 0.10), Vector3(0.10, 0.075, -0.27), GEAR.darkened(0.4)],
		[Vector3(0.07, 0.08, 0.20), Vector3(0.10, 0.0, -0.50), GEAR.lightened(0.08)],
		[Vector3(0.035, 0.035, 0.20), Vector3(0.10, 0.01, -0.70), GEAR],
	])
	return out


# --- Building -----------------------------------------------------------------------

func _pivot(parent: Node3D, pos: Vector3, key: String, boxes: Callable) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	if not _meshes.has(key):
		_meshes[key] = _merge(boxes.call())
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = _material
	n.add_child(mi)
	UnitLook.add_outline(mi, false)
	_parts.append(mi)
	return n


const _FACES := [
	# normal, u (v = normal x u)
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
	[Vector3.LEFT, Vector3.UP, Vector3.BACK],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.UP, Vector3.RIGHT],
	[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]


static func _merge(boxes: Array) -> ArrayMesh:
	## One mesh from a list of boxes, with vertex colors (tops a touch lighter, undersides
	## darker) and, in CUSTOM0, each corner's outward direction for the outline
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for b in boxes:
		var size: Vector3 = b[0]
		var pos: Vector3 = b[1]
		var col: Color = b[2]
		var rot: Basis = b[3] if b.size() > 3 else Basis.IDENTITY
		var h := size * 0.5
		for f in _FACES:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = n.cross(u)          # u x v = n: every face wound the same way
			var shade := 1.08 if n.y > 0.5 else (0.8 if n.y < -0.5 else 1.0)
			var c := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
			var corners: Array[Vector3] = [n - u - v, n + u - v, n + u + v, n - u + v]
			for i in [0, 2, 1, 0, 3, 2]:          # clockwise seen from outside (Godot's front)
				var sgn: Vector3 = corners[i]
				st.set_color(_store(c))
				st.set_normal(rot * n)
				var d := rot * sgn
				st.set_custom(0, Color(d.x, d.y, d.z, 0.0))
				st.add_vertex(pos + rot * (sgn * h))
	return st.commit()


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		_mats[key] = Level.make_material(c)
	return _mats[key]
