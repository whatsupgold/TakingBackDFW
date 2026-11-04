class_name Structure
extends StaticBody3D
## One buildable or destructible piece of a base: a wall segment (with its catwalk), a ramp
## segment (a wall segment with a ramp down from the catwalk), a gate, a barracks, a
## maintenance shed or a runway. Your engineers build them; the Red FOB comes pre-built.
##
## States: planned (a see-through ghost: nothing solid yet), building (rises as engineers
## work), built (solid, blocks movement and line of sight), destroyed (rubble you can walk over).
## Walls face their local +Z inward: the catwalk runs along the inside so soldiers standing on
## it can shoot over the top, while soldiers on the ground inside are covered.
## A built structure tells the Level how it changes the navigation map (see nav_part()).
##
## Gates have two steel leaves that swing open when one of their own side's units comes
## within GATE_RANGE and close again behind them. Closed, your gate's leaves stop Red riflemen
## (collision layer 32) and the Red FOB's stop yours (layer 16).
## Watch towers (yours: "tower", placed anywhere, on the wall line too) hold TOWER_SEATS
## soldiers on top: right-click one with infantry selected. Up there they see and shoot further.

signal state_changed(s: Structure)

const WALL_LEN := 4.0
const WALL_H := 2.4
const WALL_T := 1.4
const DECK_Y := 1.5
const DECK_W := 2.0
const RAMP_L := 4.2
const GATE_LEN := 8.0
const GATE_RANGE := 6.0              # a friendly unit this close (past the gate's ends) opens it
const GATE_SPEED := 1.4              # opening per second (0..1)
const TOWER_TOP := 6.2
const TOWER_SEATS := [Vector3(-0.9, 0, -0.9), Vector3(0.9, 0, -0.9), Vector3(-0.9, 0, 0.9), Vector3(0.9, 0, 0.9)]
const TOWER_RANGE_BONUS := 1.5       # weapon range up on a tower

const KINDS := {
	# work = engineer-seconds (a full squad of 5 divides it by 5)
	"wall": {"work": 30.0, "hp": 300.0},
	"ramp": {"work": 40.0, "hp": 300.0},
	"gate": {"work": 15.0, "hp": 250.0},
	"tower": {"work": 60.0, "hp": 450.0, "size": Vector3(4, 8, 4)},
	"barracks": {"work": 200.0, "hp": 500.0, "size": Vector3(10, 3.4, 7)},
	"shed": {"work": 225.0, "hp": 600.0, "size": Vector3(14, 5.0, 10)},
	"runway": {"work": 450.0, "hp": 99999.0, "size": Vector3(96, 0.0, 14)},
}
const NAMES := {"wall": "Wall", "ramp": "Wall + ramp", "gate": "Gate", "tower": "Watch tower", "barracks": "Barracks", "shed": "Maintenance shed", "runway": "Runway"}

const C_HESCO := Color(0.62, 0.55, 0.40)
const C_HESCO_DARK := Color(0.50, 0.44, 0.32)
const C_DECK := Color(0.42, 0.34, 0.24)
const C_RED_WALL := Color(0.52, 0.48, 0.45)
const C_RED_WALL_DARK := Color(0.40, 0.30, 0.28)
const C_TENT := Color(0.38, 0.42, 0.30)
const C_ROOF := Color(0.30, 0.33, 0.24)
const C_SHED := Color(0.48, 0.50, 0.46)
const C_RUNWAY := Color(0.20, 0.21, 0.22)
const C_PAINT := Color(0.88, 0.88, 0.84)
const C_RUBBLE := Color(0.36, 0.33, 0.29)

var kind := "wall"
var side := "blue"                # blue: yours, red: the Red FOB
var state := "planned"
var work := 0.0
var work_needed := 30.0
var hp := 300.0
var max_hp := 300.0
var length := WALL_LEN            # walls and gates: length along the wall
var yaw := 0.0
var level: Level
var label := ""

var _built_root: Node3D           # everything solid; scaled up while building
var _ghost_root: Node3D
var _rubble: MeshInstance3D
var _shapes: Array[CollisionShape3D] = []
var _leaves: Array = []            # gate leaf pivots
var _leaf_shapes: Array[CollisionShape3D] = []
var _open := 0.0
var _want_open := false
var _gate_cd := 0.0
var manned: Array = []             # soldiers up on a watch tower

static var _ghost_mat: StandardMaterial3D
static var _ghost_bad_mat: StandardMaterial3D


static func make(k: String, at: Vector3, yaw_rad: float, owner_side := "blue", seg_len := WALL_LEN) -> Structure:
	var s := Structure.new()
	s.kind = k
	s.side = owner_side
	s.yaw = yaw_rad
	s.length = seg_len
	s.position = at
	s.rotation.y = yaw_rad
	var def: Dictionary = KINDS.get(k.trim_prefix("red_"), KINDS["wall"])
	s.work_needed = def.work * (seg_len / WALL_LEN if k in ["wall", "ramp"] else 1.0)
	s.max_hp = def.hp * (1.4 if owner_side == "red" else 1.0)
	s.hp = s.max_hp
	return s


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_built_root = Node3D.new()
	add_child(_built_root)
	_ghost_root = Node3D.new()
	add_child(_ghost_root)
	_build_visuals()
	_apply_state()


func display_name() -> String:
	return NAMES.get(kind.trim_prefix("red_"), kind)


func size() -> Vector3:
	## Full footprint in local space (x along, z inward), for walls including the catwalk
	match kind.trim_prefix("red_"):
		"wall", "ramp":
			return Vector3(length, WALL_H, WALL_T + DECK_W + (RAMP_L if kind.ends_with("ramp") else 0.0))
		"gate":
			return Vector3(length, WALL_H, WALL_T)
	var def: Dictionary = KINDS.get(kind.trim_prefix("red_"), {})
	return def.get("size", Vector3(4, 2, 4))


func footprint_center_local() -> Vector3:
	var s := size()
	if kind.trim_prefix("red_") in ["wall", "ramp", "gate"]:
		return Vector3(0, 0, s.z * 0.5 - WALL_T * 0.5)
	return Vector3.ZERO


func footprint_world() -> PackedVector3Array:
	var s := size()
	var c := footprint_center_local()
	var out := PackedVector3Array()
	for k in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		out.append(to_global_flat(c + Vector3(k.x * s.x * 0.5, 0, k.z * s.z * 0.5)))
	return out


func to_global_flat(local: Vector3) -> Vector3:
	return position + Basis(Vector3.UP, yaw) * local


func flat_distance(p: Vector3) -> float:
	## Distance on the ground plane from p to the footprint (0 inside)
	var local := Basis(Vector3.UP, -yaw) * (Vector3(p.x, 0, p.z) - Vector3(position.x, 0, position.z)) - footprint_center_local()
	var s := size() * 0.5
	var dx := maxf(absf(local.x) - s.x, 0.0)
	var dz := maxf(absf(local.z) - s.z, 0.0)
	return Vector2(dx, dz).length()


func work_spot(i: int, n: int) -> Vector3:
	## Where engineer i of n stands to work on this piece (just outside its footprint, inside the base)
	var s := size()
	var c := footprint_center_local()
	if kind in ["wall", "ramp", "gate"]:
		var along := (float(i) / maxf(1.0, n - 1) - 0.5) * (s.x - 1.0) if n > 1 else 0.0
		return to_global_flat(c + Vector3(along, 0, s.z * 0.5 + 1.1))
	var a := TAU * float(i) / maxf(1.0, n)
	var r := Vector2(s.x * 0.5 + 1.4, s.z * 0.5 + 1.4)
	return to_global_flat(c + Vector3(cos(a) * r.x, 0, sin(a) * r.y))


func is_built() -> bool:
	return state == "built"


func is_solid() -> bool:
	return state == "built" and kind != "runway"


# --- Building and damage ------------------------------------------------------------

func add_work(amount: float) -> bool:
	## Returns true when this finishes the piece
	if state != "planned" and state != "building":
		return false
	state = "building"
	work = minf(work + amount, work_needed)
	_apply_state()
	if work >= work_needed:
		finish()
		return true
	return false


func finish() -> void:
	state = "built"
	work = work_needed
	_apply_state()
	state_changed.emit(self)


func take_damage(amount: float) -> void:
	if state != "built" or kind == "runway":
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		state = "destroyed"
		_apply_state()
		state_changed.emit(self)


func cancel() -> void:
	## A planned piece that's no longer wanted (the base was extended over it)
	state = "removed"
	state_changed.emit(self)
	queue_free()


func _apply_state() -> void:
	if _built_root == null:
		return
	var solid := state == "built"
	_ghost_root.visible = (state == "planned" or state == "building") and side != "red"
	_built_root.visible = state == "building" or state == "built"
	var f := clampf(work / maxf(work_needed, 0.01), 0.0, 1.0)
	_built_root.scale = Vector3(1, maxf(0.06, f) if state == "building" else 1.0, 1)
	for c in _shapes:
		c.disabled = not solid
	for c in _leaf_shapes:
		c.disabled = not solid or _open > 0.3
	if not solid:
		for sd in manned.duplicate():
			if is_instance_valid(sd):
				release(sd)
	if _rubble:
		_rubble.visible = state == "destroyed"


# --- Gates opening, towers manned ----------------------------------------------------

func _physics_process(delta: float) -> void:
	if _leaves.is_empty():
		return
	_gate_cd -= delta
	if _gate_cd <= 0.0:
		_gate_cd = 0.2
		_want_open = state == "built" and _friend_near()
	var before := _open
	_open = move_toward(_open, 1.0 if _want_open else 0.0, GATE_SPEED * delta)
	if _open != before:
		for pv in _leaves:
			(pv as Node3D).rotation.y = float(pv.get_meta("sign")) * _open * 1.65   # inward (+Z)
		for c in _leaf_shapes:
			c.disabled = state != "built" or _open > 0.3


func _friend_near() -> bool:
	var me := Vector2(position.x, position.z)
	var groups := ["red_soldiers", "red_tanks"] if side == "red" else ["soldiers", "blue_vehicles"]
	for g in groups:
		for n in get_tree().get_nodes_in_group(g):
			var u := n as Node3D
			if u == null or not u.visible:
				continue
			if u.get("dead") == true or u.get("alive") == false or u.get("destroyed") == true:
				continue
			if Vector2(u.global_position.x, u.global_position.z).distance_to(me) < GATE_RANGE + length * 0.5:
				return true
	return false


func is_open() -> bool:
	return _open > 0.3


func tower_free() -> int:
	## Free places up on a (built) watch tower of yours
	if kind != "tower" or side != "blue" or state != "built":
		return 0
	return TOWER_SEATS.size() - manned.size()


func in_reach(p: Vector3, _extra := 0.0) -> bool:
	return flat_distance(p) < 1.6


func door_point(from: Vector3) -> Vector3:
	## The foot of the tower, on the side he's coming from
	var d := Vector3(from.x - position.x, 0, from.z - position.z)
	if d.length() < 0.1:
		d = Vector3.BACK
	return position + d.normalized() * 3.2


func board_soldier(sd: Soldier) -> bool:
	## He climbs the ladder: placed on top, shoots from there with more range
	if tower_free() <= 0 or sd in manned:
		return false
	sd.man_gun(self)
	manned.append(sd)
	var i := manned.size() - 1
	sd.can_fire = true
	sd.weapon_range = Soldier.RANGE * TOWER_RANGE_BONUS
	sd.global_position = to_global_flat(TOWER_SEATS[i]) + Vector3.UP * (TOWER_TOP + 0.1)
	return true


func release(sd: Soldier) -> void:
	## Down the ladder (a new order, or the tower is gone)
	if not (sd in manned):
		return
	manned.erase(sd)
	sd.leave_gun()
	sd.global_position = door_point(sd.global_position) + Vector3.UP * 0.2


# --- Navigation ---------------------------------------------------------------------

func nav_part() -> Dictionary:
	## How this piece changes the navigation map: footprints to cut out, walkable faces to add
	var obs: Array = []
	var faces := PackedVector3Array()
	if state != "built":
		return {"obs": obs, "faces": faces}
	var k := kind.trim_prefix("red_")
	match k:
		"tower":
			obs.append([_rect_world(Vector3.ZERO, Vector3(4.0, 0, 4.0)), -1.0, 5.6])
		"wall", "ramp":
			obs.append([_rect_world(Vector3(0, 0, 0), Vector3(length, 0, WALL_T)), -1.0, WALL_H - 0.3])
			# Catwalk deck along the inside
			faces.append_array(_quad(Vector3(0, DECK_Y, WALL_T * 0.5 + DECK_W * 0.5), Vector2(length + 0.02, DECK_W)))
			if k == "ramp":
				faces.append_array(_ramp_faces())
		"gate":
			if side == "red":
				obs.append([_rect_world(Vector3.ZERO, Vector3(length, 0, WALL_T)), -1.0, WALL_H - 0.3])
		"barracks", "shed":
			var s := size()
			obs.append([_rect_world(Vector3.ZERO, Vector3(s.x, 0, s.z)), -1.0, s.y - 0.3])
	return {"obs": obs, "faces": faces}


func _rect_world(center: Vector3, s: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		out.append(to_global_flat(center + Vector3(c.x * s.x * 0.5, 0, c.z * s.z * 0.5)))
	return out


func _quad(center: Vector3, s: Vector2) -> PackedVector3Array:
	var a := to_global_flat(center + Vector3(-s.x * 0.5, 0, -s.y * 0.5))
	var b := to_global_flat(center + Vector3(s.x * 0.5, 0, -s.y * 0.5))
	var c := to_global_flat(center + Vector3(s.x * 0.5, 0, s.y * 0.5))
	var d := to_global_flat(center + Vector3(-s.x * 0.5, 0, s.y * 0.5))
	# Recast wants counter-clockwise from above for an upward face; give both windings
	return PackedVector3Array([a, c, b, a, d, c, a, b, c, a, c, d])


func _ramp_faces() -> PackedVector3Array:
	var z0 := WALL_T * 0.5 + DECK_W          # top edge (catwalk side)
	var z1 := z0 + RAMP_L                    # bottom edge (on the ground)
	var w := DECK_W * 0.5
	var a := to_global_flat(Vector3(-w, 0, z0)) + Vector3.UP * DECK_Y
	var b := to_global_flat(Vector3(w, 0, z0)) + Vector3.UP * DECK_Y
	var c := to_global_flat(Vector3(w, 0, z1)) + Vector3.UP * 0.02
	var d := to_global_flat(Vector3(-w, 0, z1)) + Vector3.UP * 0.02
	return PackedVector3Array([a, c, b, a, d, c, a, b, c, a, c, d])


# --- Visuals and collision ------------------------------------------------------------

func _build_visuals() -> void:
	var red := side == "red"
	var k := kind.trim_prefix("red_")
	match k:
		"wall", "ramp":
			var main := C_RED_WALL if red else C_HESCO
			var seam := C_RED_WALL_DARK if red else C_HESCO_DARK
			_solid_box(Vector3(0, WALL_H * 0.5, 0), Vector3(length, WALL_H, WALL_T), main)
			# Basket seams (HESCO) or panel joints (concrete), drawn on both faces
			var n := int(round(length / 1.33))
			for i in range(1, n):
				var x := -length * 0.5 + length * i / n
				_visual_box(_built_root, Vector3(x, WALL_H * 0.5, 0), Vector3(0.08, WALL_H + 0.02, WALL_T + 0.04), seam)
			# Catwalk: deck on posts, with a low kick-board on the inner edge
			_solid_box(Vector3(0, DECK_Y - 0.1, WALL_T * 0.5 + DECK_W * 0.5), Vector3(length, 0.2, DECK_W), C_DECK)
			for x in [-length * 0.5 + 0.3, length * 0.5 - 0.3]:
				_visual_box(_built_root, Vector3(x, DECK_Y * 0.5 - 0.1, WALL_T * 0.5 + DECK_W - 0.15), Vector3(0.15, DECK_Y - 0.2, 0.15), C_DECK.darkened(0.3))
			_visual_box(_built_root, Vector3(0, DECK_Y + 0.08, WALL_T * 0.5 + DECK_W - 0.05), Vector3(length, 0.16, 0.08), C_DECK.darkened(0.2))
			if k == "ramp":
				var rl := sqrt(RAMP_L * RAMP_L + DECK_Y * DECK_Y)
				var ang := atan2(DECK_Y, RAMP_L)
				var mid := Vector3(0, DECK_Y * 0.5 - 0.1, WALL_T * 0.5 + DECK_W + RAMP_L * 0.5)
				_solid_box(mid, Vector3(DECK_W, 0.2, rl), C_DECK, Basis(Vector3.RIGHT, ang))
		"gate":
			var post := C_RED_WALL_DARK if red else C_HESCO_DARK
			for x in [-length * 0.5 + 0.4, length * 0.5 - 0.4]:
				_solid_box(Vector3(x, WALL_H * 0.6, 0), Vector3(0.8, WALL_H * 1.2, WALL_T + 0.2), post)
			if not red:
				_visual_box(_built_root, Vector3(0, WALL_H * 1.15, 0), Vector3(length, 0.3, 0.4), post)
			# Two steel leaves, hinged at the posts, swinging inward
			var leaf := Color(0.30, 0.22, 0.20) if red else Color(0.36, 0.38, 0.30)
			var w := (length - 1.6) * 0.5
			for sgn in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(sgn * (length * 0.5 - 0.8), 0, 0)
				_built_root.add_child(pivot)
				pivot.set_meta("sign", sgn)
				_leaves.append(pivot)
				var mid := Vector3(-sgn * w * 0.5, WALL_H * 0.5, 0)
				_visual_box(pivot, mid, Vector3(w, WALL_H, 0.3), leaf)
				for i in 3:
					_visual_box(pivot, mid + Vector3((i - 1) * w * 0.3, 0, 0), Vector3(0.1, WALL_H, 0.4), leaf.darkened(0.3))
				_visual_box(pivot, mid + Vector3(0, WALL_H * 0.3, 0), Vector3(w, 0.12, 0.4), leaf.darkened(0.3))
				var body := StaticBody3D.new()
				body.collision_layer = 16 if red else 32
				body.collision_mask = 0
				var shape := BoxShape3D.new()
				shape.size = Vector3(w, WALL_H, 0.3)
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.position = mid
				body.add_child(cs)
				pivot.add_child(body)
				_leaf_shapes.append(cs)
		"tower":
			var wall_c := C_RED_WALL if red else C_HESCO
			var dark_c := C_RED_WALL_DARK if red else C_DECK
			_solid_box(Vector3(0, 3.0, 0), Vector3(4.0, 6.0, 4.0), wall_c)
			if not red:
				for y in [1.5, 3.0, 4.5]:
					_visual_box(_built_root, Vector3(0, y, 0), Vector3(4.04, 0.08, 4.04), C_HESCO_DARK)
			_solid_box(Vector3(0, 6.1, 0), Vector3(4.6, 0.2, 4.6), dark_c)
			for c in [Vector3(-2.2, 6.6, 0), Vector3(2.2, 6.6, 0), Vector3(0, 6.6, -2.2), Vector3(0, 6.6, 2.2)]:
				var horizontal_x := absf(c.z) > 0.1
				_visual_box(_built_root, c, Vector3(4.6 if horizontal_x else 0.2, 0.8, 0.2 if horizontal_x else 4.6), dark_c)
			_visual_box(_built_root, Vector3(0, 7.9, 0), Vector3(4.8, 0.2, 4.8), dark_c)
			for c in [Vector3(-2.1, 7.2, -2.1), Vector3(2.1, 7.2, -2.1), Vector3(-2.1, 7.2, 2.1), Vector3(2.1, 7.2, 2.1)]:
				_visual_box(_built_root, c, Vector3(0.2, 1.4, 0.2), dark_c)
		"barracks":
			var s := size()
			_solid_box(Vector3(0, s.y * 0.4, 0), Vector3(s.x, s.y * 0.8, s.z), C_TENT)
			_visual_box(_built_root, Vector3(0, s.y * 0.9, 0), Vector3(s.x + 0.4, s.y * 0.2, s.z + 0.4), C_ROOF)
			_visual_box(_built_root, Vector3(0, 1.0, s.z * 0.5 + 0.02), Vector3(1.4, 2.0, 0.05), Color(0.10, 0.10, 0.09))
			for x in [-3.0, 3.0]:
				_visual_box(_built_root, Vector3(x, 1.6, s.z * 0.5 + 0.02), Vector3(1.0, 0.6, 0.05), Color(0.28, 0.38, 0.44))
		"shed":
			var s := size()
			_solid_box(Vector3(0, s.y * 0.5, 0), Vector3(s.x, s.y, s.z), C_SHED)
			_visual_box(_built_root, Vector3(0, s.y + 0.15, 0), Vector3(s.x + 0.6, 0.3, s.z + 0.6), C_SHED.darkened(0.3))
			_visual_box(_built_root, Vector3(0, s.y * 0.4, s.z * 0.5 + 0.02), Vector3(s.x * 0.7, s.y * 0.8, 0.05), Color(0.12, 0.12, 0.12))
			for i in 7:
				_visual_box(_built_root, Vector3(-s.x * 0.35 + i * s.x * 0.7 / 6.0, s.y * 0.4, s.z * 0.5 + 0.05), Vector3(0.08, s.y * 0.8, 0.04), Color(0.95, 0.80, 0.25))
		"runway":
			var s := size()
			_visual_box(_built_root, Vector3(0, 0.15, 0), Vector3(s.x, 0.02, s.z), C_RUNWAY)
			var x := -s.x * 0.5 + 8.0
			while x < s.x * 0.5 - 8.0:
				_visual_box(_built_root, Vector3(x + 2.0, 0.17, 0), Vector3(4.0, 0.02, 0.4), C_PAINT)
				x += 8.0
			for end in [-1.0, 1.0]:
				for i in 5:
					_visual_box(_built_root, Vector3(end * (s.x * 0.5 - 2.0), 0.17, -5.0 + i * 2.5), Vector3(2.5, 0.02, 1.0), C_PAINT)
			for slot in [-1.0, 1.0]:
				for z in [-s.z * 0.5 + 0.4, s.z * 0.5 - 0.4]:
					_visual_box(_built_root, Vector3(slot * (s.x * 0.5 - 10.0), 0.17, z), Vector3(8.0, 0.02, 0.3), Color(0.95, 0.80, 0.25))
	# Ghost: one see-through box over the whole footprint
	var gs := size()
	var gm := BoxMesh.new()
	gm.size = Vector3(gs.x, maxf(0.15, gs.y if kind != "runway" else 0.15), gs.z)
	var g := MeshInstance3D.new()
	g.mesh = gm
	g.material_override = ghost_material(false)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = footprint_center_local() + Vector3.UP * gm.size.y * 0.5
	_ghost_root.add_child(g)
	# Rubble left when it's destroyed
	if kind != "runway":
		var rm := BoxMesh.new()
		rm.size = Vector3(gs.x, 0.35, minf(gs.z, WALL_T + 1.0) if kind.trim_prefix("red_") in ["wall", "ramp", "gate"] else gs.z)
		_rubble = MeshInstance3D.new()
		_rubble.mesh = rm
		_rubble.material_override = Level.make_material(C_RUBBLE)
		_rubble.position = Vector3(0, 0.17, 0) if kind.trim_prefix("red_") in ["wall", "ramp", "gate"] else Vector3(0, 0.17, 0)
		_rubble.visible = false
		add_child(_rubble)


static func ghost_material(bad: bool) -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.55, 0.95, 0.55, 0.28)
		_ghost_bad_mat = _ghost_mat.duplicate()
		_ghost_bad_mat.albedo_color = Color(1.0, 0.35, 0.3, 0.35)
	return _ghost_bad_mat if bad else _ghost_mat


func _solid_box(pos: Vector3, s: Vector3, color: Color, rot := Basis.IDENTITY) -> void:
	_visual_box(_built_root, pos, s, color, rot)
	var shape := BoxShape3D.new()
	shape.size = s
	var c := CollisionShape3D.new()
	c.shape = shape
	c.transform = Transform3D(rot, pos)
	add_child(c)
	_shapes.append(c)


func _visual_box(parent: Node3D, pos: Vector3, s: Vector3, color: Color, rot := Basis.IDENTITY) -> void:
	var m := BoxMesh.new()
	m.size = s
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(color)
	mi.transform = Transform3D(rot, pos)
	parent.add_child(mi)


static var _mats := {}


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		_mats[key] = Level.make_material(c)
	return _mats[key]
