class_name RtsCamera
extends Camera3D
## Isometric-style orthographic RTS camera.
## Rotates in 90-degree steps (Q/E), pans with WASD/arrows, zooms with the wheel.
## The camera position is snapped to the pixel grid so the 3D pixel art stays crisp.

const PITCH_DEG := -35.264   # classic isometric angle
const DISTANCE := 320.0
var distance := DISTANCE      # how far back the camera sits (raised for whole-city screenshots)
const PAN_SPEED := 22.0
const MIN_SIZE := 12.0
const MAX_SIZE := 260.0
const EDGE_MARGIN := 20.0     # how far inside the map edge the camera's focus can go

var focus := Vector3(2.0, 0.0, 2.0)
var _yaw := deg_to_rad(45.0)
var _target_yaw := deg_to_rad(45.0)
var _target_size := 28.0
var _shake := 0.0
var allow_edge_scroll := true   # main turns this off for automated tests
const EDGE := 6.0               # pixels from the window edge that start edge scrolling


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = _target_size
	near = 1.0
	far = 760.0
	_apply()


func rotate_step(dir: int) -> void:
	_target_yaw += dir * PI * 0.5


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func zoom(factor: float) -> void:
	_target_size = clampf(_target_size * factor, MIN_SIZE, MAX_SIZE)


func _process(delta: float) -> void:
	var b := _basis()
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := b.x
	right.y = 0.0
	right = right.normalized()

	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if allow_edge_scroll and Settings.edge_scroll and DisplayServer.window_is_focused():
		var win := get_tree().root
		var m := win.get_mouse_position()
		var vs := win.get_visible_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(m):
			if m.x < EDGE:
				move.x -= 1.0
			elif m.x > vs.x - EDGE:
				move.x += 1.0
			if m.y < EDGE:
				move.y += 1.0
			elif m.y > vs.y - EDGE:
				move.y -= 1.0
	if move != Vector2.ZERO:
		move = move.normalized()
		focus += (right * move.x + fwd * move.y) * PAN_SPEED * Settings.pan_speed * delta * (size / 28.0)
		# The map's own size (sector maps are much bigger than the generated city)
		var lx := CityBuilder.HALF_X - EDGE_MARGIN
		var lz := CityBuilder.HALF_Z - EDGE_MARGIN
		focus.x = clampf(focus.x, -lx, lx)
		focus.z = clampf(focus.z, -lz, lz)

	var k := 1.0 - exp(-12.0 * delta)
	_yaw = lerpf(_yaw, _target_yaw, k)
	if absf(_yaw - _target_yaw) < 0.0005:
		_yaw = _target_yaw
	size = lerpf(size, _target_size, k)
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	_apply()


func _basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), _yaw, 0.0))


func _apply() -> void:
	var b := _basis()
	var pos := focus + b.z * distance
	if _shake > 0.0:
		pos += (b.x * randf_range(-1, 1) + b.y * randf_range(-1, 1)) * _shake * 0.35
	# Snap the camera to whole pixels in its own plane so pixels don't shimmer while panning.
	var vp_h := get_viewport().get_visible_rect().size.y
	if vp_h > 0.0:
		var px := size / vp_h
		UnitLook.set_pixel(px)
		var lx := snappedf(pos.dot(b.x), px)
		var ly := snappedf(pos.dot(b.y), px)
		var lz := pos.dot(b.z)
		pos = b.x * lx + b.y * ly + b.z * lz
	global_transform = Transform3D(b, pos)
