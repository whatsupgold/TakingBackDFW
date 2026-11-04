class_name Airlifter
extends Node3D
## The C-130 that flies an airdrop: it comes in from the west map edge, passes over the drop
## point and pushes a supply pallet out of the back on a parachute, then flies on off the map.
## It isn't one of your units (you can't select it) and the Red anti-air leaves it alone.

signal dropped(pallet: SupplyPallet)

const ALT := 150.0
const SPEED := 70.0

var target := Vector3.ZERO
var kind := "ammo"
var world: Node3D
var _dir := Vector3.RIGHT
var _done := false
var _model: Node3D

var _props: Array = []


static func fly(to: Vector3, pallet_kind: String, parent: Node3D) -> Airlifter:
	var a := Airlifter.new()
	a.target = to
	a.kind = pallet_kind
	a.world = parent
	parent.add_child(a)
	var start := Vector3(-CityBuilder.HALF_X - 300.0, ALT, to.z + randf_range(-60.0, 60.0))
	a._dir = (Vector3(to.x, ALT, to.z) - start).normalized()
	a.global_position = start
	a.rotation.y = atan2(-a._dir.x, -a._dir.z)
	return a


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_props = HeliModels.c130(_model)

func _physics_process(delta: float) -> void:
	global_position += _dir * SPEED * delta
	for p in _props:
		(p as Node3D).rotate_object_local(Vector3.BACK, 30.0 * delta)
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z)
	# Drop when it's over the point (pushed out the back a moment early, since it drifts on)
	if not _done and flat.dot(Vector2(_dir.x, _dir.z)) < 25.0:
		_done = true
		var p := SupplyPallet.make(kind)
		world.add_child(p)
		p.global_position = global_position - _dir * 14.0 + Vector3.DOWN * 2.0
		dropped.emit(p)
	if global_position.x > CityBuilder.HALF_X + 400.0 or absf(global_position.z) > CityBuilder.HALF_Z + 600.0:
		queue_free()
