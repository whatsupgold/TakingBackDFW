class_name SupplyPallet
extends Node3D
## An air-dropped supply pallet: AMMO (rounds), SHELLS (155 mm) or FUEL (a fuel bladder).
## It comes down under a parachute, drifting with the wind, and then sits where it landed
## until a PLS truck loads it (right-click it with the PLS) or a Chinook sling-loads it
## (right-click it with the Chinook). Brought inside your FOB walls, it's unloaded into the
## FOB's stock. A PLS carrying a shell pallet also refills an M777 it parks next to.

const KINDS := {
	"ammo": {"name": "Ammo pallet", "amount": 16800, "unit": "rounds"},     # 20 cans of 840
	"shells": {"name": "Shell pallet", "amount": 16, "unit": "155 mm shells"},
	"fuel": {"name": "Fuel pallet", "amount": 1000, "unit": "gal"},
}
const FALL_SPEED := 5.5            # m/s under the canopy
const WIND := 1.2                  # m/s of sideways drift

var kind := "ammo"
var amount := 0
var display_name := "Pallet"
var state := "falling"             # falling, ground, slung, loaded, delivered
var slung_by: Node3D = null        # a Chinook (same hook as the M777's)
var carried_by: Node3D = null      # a PLS
var crew_squad = null              # (the Chinook's sling code asks; pallets have no crew)
var _drift := Vector3.ZERO
var _chute: Node3D
var _chute_t := 0.0

static var _meshes := {}


static func make(k: String) -> SupplyPallet:
	var p := SupplyPallet.new()
	p.kind = k
	p.amount = KINDS[k].amount
	p.display_name = KINDS[k].name
	return p


func _ready() -> void:
	add_to_group("pallets")
	var a := randf() * TAU
	_drift = Vector3(cos(a), 0, sin(a)) * WIND
	_build_model()


func describe() -> String:
	return "%s: %s %s" % [display_name, Fob._thousands(amount), KINDS[kind].unit]


func _physics_process(delta: float) -> void:
	if state == "falling":
		var p := global_position + (_drift + Vector3.DOWN * FALL_SPEED) * delta
		var ground := _ground_y(p)
		if p.y <= ground:
			p.y = ground
			state = "ground"
			_chute_t = 2.0
			_land_message()
		global_position = p
		# Swing a little under the canopy
		rotation.z = sin(Time.get_ticks_msec() * 0.002) * 0.06
	elif _chute != null and _chute_t > 0.0:
		# The canopy collapses on landing
		_chute_t -= delta
		rotation.z = 0.0
		_chute.scale = Vector3(1.0, maxf(0.05, _chute_t / 2.0), 1.0)
		_chute.position.y = 1.0 + 6.0 * (_chute_t / 2.0)
		if _chute_t <= 0.0:
			_chute.queue_free()
			_chute = null


func is_on_ground() -> bool:
	return state == "ground"


# --- Chinook sling (same calls as the M777) ---------------------------------------

func hook(by: Node3D) -> void:
	slung_by = by
	state = "slung"


func set_down(at: Vector3, yaw: float) -> void:
	slung_by = null
	carried_by = null
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	state = "ground"
	_try_deliver()


# --- PLS ----------------------------------------------------------------------------

func load_on(truck: Node3D, slot: Node3D) -> void:
	carried_by = truck
	state = "loaded"
	var keep := global_transform
	get_parent().remove_child(self)
	slot.add_child(self)
	transform = Transform3D.IDENTITY
	set_physics_process(false)


func unload_to(world: Node, at: Vector3, yaw: float) -> void:
	get_parent().remove_child(self)
	world.add_child(self)
	set_physics_process(true)
	set_down(at, yaw)


func deliver() -> void:
	## Into the FOB's stock
	var f := Fob.current
	if f == null:
		return
	f.add_stock(kind, amount)
	f.message.emit("%s delivered to the FOB: +%s %s" % [display_name, Fob._thousands(amount), KINDS[kind].unit])
	state = "delivered"
	queue_free()


func _try_deliver() -> void:
	var f := Fob.current
	if f != null and f.contains(global_position):
		deliver()


func _land_message() -> void:
	var f := Fob.current
	if f == null:
		return
	if f.contains(global_position):
		deliver()
		return
	f.message.emit("%s is down. Send a PLS or a Chinook to bring it in (right-click it)" % display_name)


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 1.0, p.z), Vector3(p.x, -5.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else hit.position.y


# --- Model ---------------------------------------------------------------------------

func _build_model() -> void:
	var key := "pallet_" + kind
	if not _meshes.has(key):
		var lp := LowPoly.new()
		var wood := Color(0.46, 0.36, 0.22)
		lp.box(Vector3(1.6, 0.14, 1.6), Vector3(0, 0.07, 0), wood, 0.02)
		match kind:
			"ammo":
				# Green ammo crates, two layers, a strap round them
				for y in [0.38, 0.86]:
					for x in [-0.4, 0.4]:
						lp.box(Vector3(0.74, 0.46, 1.5), Vector3(x, y, 0), Color(0.30, 0.36, 0.22), 0.03)
						lp.box(Vector3(0.76, 0.06, 1.52), Vector3(x, y + 0.1, 0), Color(0.80, 0.65, 0.20))
			"shells":
				# 155 mm rounds standing in rows
				for x in 4:
					for z in 4:
						var pos := Vector3(-0.54 + x * 0.36, 0.14, -0.54 + z * 0.36)
						lp.cyl(0.08, 0.62, 8, VehicleModel.T(pos + Vector3(0, 0.31, 0), VehicleModel.TO_Y), Color(0.44, 0.46, 0.30))
						lp.cyl(0.05, 0.16, 8, VehicleModel.T(pos + Vector3(0, 0.70, 0), VehicleModel.TO_Y), Color(0.75, 0.62, 0.25), 0.02)
			"fuel":
				# A black rubber fuel bladder
				lp.hull([[-0.75, 1.10, 0.50, 0.45, 0.8], [-0.55, 1.45, 0.70, 0.50, 0.8], [0.55, 1.45, 0.70, 0.50, 0.8], [0.75, 1.10, 0.50, 0.45, 0.8]], Color(0.12, 0.12, 0.12))
				lp.box(Vector3(0.20, 0.10, 0.20), Vector3(0, 0.88, 0), Color(0.70, 0.60, 0.20))
		_meshes[key] = lp.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = UnitLook.vehicle_material()
	add_child(mi)
	UnitLook.add_outline(mi, false, false)
	# Parachute: a canopy on lines
	if not _meshes.has("chute"):
		var lp := LowPoly.new()
		lp.hull([[-0.8, 5.6, 0.2, 0.0, 0.9], [-0.2, 6.4, 0.9, 0.35, 0.8], [0.6, 5.2, 0.6, 0.6, 0.9]], Color(0.38, 0.42, 0.30), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
		for a in 4:
			var d := Vector3(cos(TAU * a / 4.0 + PI / 4.0), 0, sin(TAU * a / 4.0 + PI / 4.0))
			var top := d * 2.6
			var mid := (top + Vector3(0, -6.0, 0)) * 0.5
			var dir := (top - Vector3(0, -6.0, 0)).normalized()
			var b := Basis(Quaternion(Vector3.FORWARD, dir))
			lp.cyl(0.02, 6.6, 4, Transform3D(b, mid), Color(0.8, 0.8, 0.75))
		_meshes["chute"] = lp.commit()
	_chute = Node3D.new()
	_chute.position = Vector3(0, 7.0, 0)
	add_child(_chute)
	var cm := MeshInstance3D.new()
	cm.mesh = _meshes["chute"]
	cm.material_override = UnitLook.vehicle_material()
	_chute.add_child(cm)
	if state != "falling":
		_chute.queue_free()
		_chute = null
