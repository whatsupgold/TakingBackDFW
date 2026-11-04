class_name Missile
extends Node3D
## A guided anti-tank missile (TOW from the Bradley, Hellfire from the Apache): it flies
## straight at a Red tank or anti-air vehicle, leaving a smoke line, and blows it up on impact.

const TOW_SPEED := 280.0          # m/s
const HELLFIRE_SPEED := 425.0     # about Mach 1.3

var army: RedArmy
var target: Node3D
var damage := 120.0
var speed := TOW_SPEED
var _aim := Vector3.ZERO
var _life := 6.0


static func launch(parent: Node, from: Vector3, at: Node3D, red_army: RedArmy, dmg := 120.0, spd := TOW_SPEED) -> Missile:
	var m := Missile.new()
	m.speed = spd
	m.army = red_army
	m.target = at
	m.damage = dmg
	parent.add_child(m)
	m.global_position = from
	m._aim = at.global_position + Vector3.UP * 1.2
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = 1.0
	cm.radial_segments = 6
	body.mesh = cm
	body.rotation.x = PI * 0.5
	body.material_override = Level.make_material(Color(0.75, 0.75, 0.68))
	m.add_child(body)
	red_army.gibs.muzzle_blast(from, (m._aim - from).normalized())
	return m


func _physics_process(delta: float) -> void:
	_life -= delta
	if is_instance_valid(target) and target.alive:
		_aim = target.global_position + Vector3.UP * 1.2
	var p := global_position
	var to := _aim - p
	var step := speed * delta
	if to.length() <= step or _life <= 0.0:
		army.gibs.explosion(_aim)
		if is_instance_valid(target) and target.alive:
			target.take_damage(damage)
		queue_free()
		return
	var np := p + to.normalized() * step
	army.add_tracer(p, np)
	look_at_from_position(np, np + to, Vector3.UP if absf(to.normalized().y) < 0.99 else Vector3.FORWARD)
