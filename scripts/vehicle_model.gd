class_name VehicleModel
extends Node3D
## Low-poly, flat-shaded vehicles: tapered noses, rounded (octagonal) fuselages, sloped armour
## and bevelled edges, built from cross-sections with LowPoly, with a 1-pixel dark outline.
## Build one with VehicleModel.humvee(), .stryker(), .huey(), .chinook(), .a10(), .m777(),
## .red_tank() or .red_aa(). Each faces -Z, sits on y = 0, and is sized in real metres.
## Moving parts are their own pieces under pivots (turret, rotors, ramp, gear, gun cradle);
## anything added to `spinners` (rotors) turns every frame. Meshes are built once per kind
## and shared.

const OD := Color(0.33, 0.36, 0.23)          # olive drab
const OD_DARK := Color(0.25, 0.28, 0.17)
const OD_LIGHT := Color(0.40, 0.43, 0.29)
const OD_PALE := Color(0.46, 0.49, 0.34)      # roofs and tops
const TIRE := Color(0.10, 0.10, 0.10)
const HUB := Color(0.22, 0.23, 0.20)
const GLASS := Color(0.24, 0.33, 0.40)
const GLASS_LIGHT := Color(0.42, 0.55, 0.62)
const STEEL := Color(0.20, 0.21, 0.20)
const STEEL_LIGHT := Color(0.32, 0.33, 0.32)
const INTERIOR := Color(0.08, 0.09, 0.08)
const LIGHT := Color(1.0, 0.92, 0.6)
const STAR := Color(0.85, 0.86, 0.82)
const BLADE := Color(0.14, 0.15, 0.13)
const TANK_RED := Color(0.50, 0.17, 0.13)      # Red Army armor
const TANK_RED_DARK := Color(0.34, 0.12, 0.09)
const TANK_RED_LIGHT := Color(0.60, 0.24, 0.18)
const TRACK := Color(0.12, 0.11, 0.10)
const RED_STAR := Color(0.95, 0.80, 0.25)
const JET_GRAY := Color(0.47, 0.50, 0.52)
const JET_DARK := Color(0.36, 0.38, 0.40)
const JET_LIGHT := Color(0.56, 0.59, 0.61)

var spinners: Array = []      # [node, axis, radians per second]
var rotor_factor := 1.0       # multiplies spinner speed (Huey spins up for flight)
var turret: Node3D            # Humvee gun turret (turns around Y)
var traverse: Node3D          # M777: turns the cradle left/right
var cradle: Node3D            # M777: elevation (rotation.x)
var recoil: Node3D            # M777: barrel group that slides back when firing
var ramp: Node3D              # Chinook: rear ramp, hinged at the bottom of the cabin
var gear: Node3D              # A-10: landing gear (hidden in flight)
var muzzle: Node3D            # tank / A-10: where shots come from

const RAMP_OPEN := deg_to_rad(17.0)      # resting on the ground
const RAMP_CLOSED := deg_to_rad(-90.0)   # folded up into the back of the cabin

const TO_X := Basis(Vector3.UP, PI * 0.5)        # turns a shape built along Z to lie along X
const TO_Y := Basis(Vector3.RIGHT, -PI * 0.5)    # ... or to stand along Y

static var _mats := {}
static var _meshes := {}


func _ready() -> void:
	UnitLook.outline_tree(self)


func _process(delta: float) -> void:
	for s in spinners:
		(s[0] as Node3D).rotate_object_local(s[1], s[2] * rotor_factor * delta)


static func T(pos: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, pos)


# --- Humvee -----------------------------------------------------------------

static func humvee() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Humvee"
	for x in [-0.95, 0.95]:
		for z in [-1.45, 1.45]:
			v._lp_wheel(v, Vector3(x, 0.45, z), 0.45, 0.40)
	v._lp(v, "humvee_body", func(lp: LowPoly):
		# Lower body, wide and flat
		lp.hull([[-2.35, 1.95, 0.45, 0.90, 0.35], [-2.15, 2.15, 0.62, 0.95, 0.2], [2.20, 2.15, 0.62, 0.95, 0.2], [2.32, 2.0, 0.5, 0.95, 0.3]], OD)
		# Hood sloping down to the grille
		lp.hull([[-2.32, 1.95, 0.20, 1.30, 0.35], [-0.85, 2.10, 0.42, 1.43, 0.2]], OD, Transform3D.IDENTITY, OD_LIGHT)
		# Fender flares over the wheels
		for x in [-1.02, 1.02]:
			for z in [-1.45, 1.45]:
				lp.box(Vector3(0.26, 0.16, 1.15), Vector3(x, 1.02, z), OD_DARK, 0.06)
		# Cabin: steep windscreen, flat roof
		lp.hull([[-0.95, 2.00, 0.55, 1.50, 0.15], [-0.70, 2.02, 0.98, 1.72, 0.12], [1.10, 2.02, 0.98, 1.72, 0.12], [1.20, 1.92, 0.90, 1.72, 0.18]], OD_LIGHT, Transform3D.IDENTITY, OD_PALE)
		# Rear cargo deck
		lp.hull([[1.10, 2.05, 0.46, 1.44, 0.15], [2.30, 2.05, 0.46, 1.44, 0.2]], OD, Transform3D.IDENTITY, OD_LIGHT)
		# Glass: windscreen (two panes) and side windows
		for x in [-0.46, 0.46]:
			lp.box(Vector3(0.82, 0.42, 0.04), Vector3(x, 1.86, -0.80), GLASS, 0.0, T(Vector3.ZERO, Basis(Vector3.RIGHT, -0.18)))
		for x in [-1.025, 1.025]:
			lp.box(Vector3(0.03, 0.38, 0.72), Vector3(x, 1.88, -0.38), GLASS)
			lp.box(Vector3(0.03, 0.38, 0.72), Vector3(x, 1.88, 0.58), GLASS)
			lp.box(Vector3(0.06, 0.08, 0.22), Vector3(x * 1.07, 1.62, -0.78), STEEL)      # mirrors
		# Grille, headlights, bumpers
		lp.box(Vector3(1.40, 0.36, 0.05), Vector3(0, 1.00, -2.36), OD_DARK)
		for x in [-0.45, -0.15, 0.15, 0.45]:
			lp.box(Vector3(0.06, 0.32, 0.03), Vector3(x, 1.00, -2.39), STEEL)
		for x in [-0.78, 0.78]:
			lp.box(Vector3(0.20, 0.12, 0.04), Vector3(x, 1.16, -2.36), LIGHT)
		lp.box(Vector3(2.25, 0.20, 0.24), Vector3(0, 0.66, -2.40), STEEL, 0.05)
		lp.box(Vector3(2.00, 0.12, 0.12), Vector3(0, 1.08, 2.34), STEEL, 0.03)
		# Door seams
		for x in [-1.03, 1.03]:
			lp.box(Vector3(0.02, 0.85, 0.04), Vector3(x * 1.055, 1.45, 0.10), OD_DARK))
	# Roof gun turret (turns as a unit; the gunner stands in the hatch below it)
	var t := v._pivot(Vector3(0, 2.12, 0.15))
	v.turret = t
	v._lp(t, "humvee_turret", func(lp: LowPoly):
		lp.cyl(0.50, 0.14, 8, T(Vector3.ZERO, TO_Y), OD_DARK)
		# Gunner's shield: a front plate and two angled wings
		lp.box(Vector3(0.80, 0.50, 0.07), Vector3(0, 0.32, -0.45), OD_DARK, 0.02)
		for s in [-1.0, 1.0]:
			lp.box(Vector3(0.40, 0.46, 0.07), Vector3(0, 0, 0), OD_DARK, 0.02, T(Vector3(s * 0.52, 0.31, -0.33), Basis(Vector3.UP, s * 0.7)))
		lp.box(Vector3(0.20, 0.22, 0.55), Vector3(0, 0.24, -0.20), STEEL, 0.04)
		lp.cyl(0.045, 1.10, 6, T(Vector3(0, 0.26, -1.00)), STEEL)
		lp.box(Vector3(0.30, 0.22, 0.22), Vector3(0.28, 0.18, -0.10), OD, 0.03))
	return v


# --- UH-60 Black Hawk -----------------------------------------------------------
# (built by huey(): the Black Hawk took the Huey's place)

const BH := Color(0.22, 0.25, 0.19)            # Black Hawk green-black
const BH_TOP := Color(0.28, 0.31, 0.24)
const BH_DARK := Color(0.15, 0.17, 0.13)


static func huey() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "BlackHawk"
	v._lp(v, "blackhawk_body", func(lp: LowPoly):
		# Short sloped nose into a wide, flat-sided cabin
		lp.hull([[-3.65, 1.00, 0.70, 1.30, 0.7], [-3.25, 1.85, 1.40, 1.52, 0.5], [-2.40, 2.30, 1.90, 1.75, 0.35],
			[1.80, 2.40, 2.00, 1.80, 0.3], [2.65, 1.55, 1.40, 2.05, 0.4]], BH, Transform3D.IDENTITY, BH_TOP)
		# Engine and gearbox fairing on the roof, an exhaust each side
		lp.hull([[-2.10, 1.10, 0.35, 2.92, 0.5], [-1.50, 1.85, 0.80, 3.15, 0.4], [1.80, 1.85, 0.80, 3.15, 0.4], [2.70, 1.00, 0.55, 3.05, 0.5]], BH, Transform3D.IDENTITY, BH_TOP)
		for x in [-0.98, 0.98]:
			lp.hull([[0.70, 0.40, 0.40, 3.05, 1.0, x], [1.70, 0.44, 0.44, 3.05, 1.0, x], [2.05, 0.34, 0.34, 3.10, 1.0, x]], BH_DARK)
			lp.cyl(0.14, 0.06, 8, T(Vector3(x, 3.10, 2.08)), INTERIOR)
		# Long tail boom up to the tall fin, stabilator, tail wheel
		lp.hull([[2.50, 1.10, 1.00, 2.20, 0.5], [5.20, 0.62, 0.68, 2.40, 0.5], [7.70, 0.44, 0.58, 2.55, 0.5]], BH)
		lp.hull([[7.10, 0.20, 0.70, 2.95, 0.3], [7.95, 0.22, 1.90, 3.55, 0.3], [8.55, 0.18, 1.30, 4.15, 0.3]], BH, Transform3D.IDENTITY, BH_TOP)
		lp.box(Vector3(3.10, 0.07, 0.75), Vector3(0, 2.25, 7.90), BH_DARK, 0.02)
		lp.cyl(0.04, 0.55, 6, T(Vector3(0, 0.55, 7.55), TO_Y), STEEL)
		# Glass: windscreen panes over the nose, chin windows, cockpit doors
		for x in [-0.48, 0.48]:
			lp.box(Vector3(0.85, 0.60, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 2.15, -2.95), Basis(Vector3.UP, -signf(x) * 0.30) * Basis(Vector3.RIGHT, -0.75)))
			lp.box(Vector3(0.50, 0.28, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x * 0.85, 1.12, -3.45), Basis(Vector3.RIGHT, 0.45)))
		for x in [-1.16, 1.16]:
			lp.box(Vector3(0.03, 0.60, 0.80), Vector3(x, 2.05, -1.95), GLASS)
			lp.box(Vector3(0.03, 1.35, 1.70), Vector3(x * 1.04, 1.55, 0.25), INTERIOR)       # open cabin door
			lp.box(Vector3(0.03, 0.36, 0.40), Vector3(x * 1.04, 2.20, 1.45), GLASS)
			lp.box(Vector3(0.04, 0.28, 0.28), Vector3(x * 1.05, 1.95, 2.10), STAR)
		# Main wheels on struts under the cockpit
		for x in [-1.45, 1.45]:
			lp.cyl(0.06, 0.80, 6, T(Vector3(x * 0.85, 0.75, -1.70), Basis(Vector3.FORWARD, deg_to_rad(-30 * signf(x))) * TO_Y), STEEL)
			lp.tyre(0.36, 0.24, 16, T(Vector3(x, 0.36, -1.70), TO_X), TIRE)
		lp.tyre(0.22, 0.14, 16, T(Vector3(0, 0.22, 7.55), TO_X), TIRE)
		# Rotor mast
		lp.cyl(0.14, 0.45, 8, T(Vector3(0, 3.70, 0.10), TO_Y), STEEL))
	# Tail rotor, canted on the right of the fin
	var tail := v._pivot(Vector3(0.22, 3.75, 8.20))
	v._lp(tail, "blackhawk_tail_rotor", func(lp: LowPoly):
		for k in 2:
			lp.box(Vector3(0.04, 2.70, 0.20), Vector3.ZERO, BLADE, 0.0, T(Vector3.ZERO, Basis(Vector3.RIGHT, k * PI * 0.5)))
		lp.cyl(0.10, 0.14, 8, T(Vector3.ZERO, TO_X), STEEL))
	v.spinners.append([tail, Vector3.RIGHT, 9.0])
	# Main rotor: four blades
	var rotor := v._pivot(Vector3(0, 3.95, 0.10))
	v._lp(rotor, "blackhawk_rotor", func(lp: LowPoly):
		for k in 4:
			lp.hull([[0.35, 0.52, 0.06, 0.0, 0.3], [7.80, 0.52, 0.05, 0.0, 0.3], [8.20, 0.30, 0.04, 0.0, 0.3]], BLADE, T(Vector3.ZERO, Basis(Vector3.UP, k * PI * 0.5) * TO_X))
		lp.cyl(0.42, 0.24, 8, T(Vector3.ZERO, TO_Y), STEEL)
		lp.cyl(0.16, 0.30, 8, T(Vector3(0, 0.22, 0), TO_Y), STEEL_LIGHT))
	v.spinners.append([rotor, Vector3.UP, 3.2])
	return v


# --- CH-47 Chinook ------------------------------------------------------------

static func chinook() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Chinook"
	v._lp(v, "chinook_body", func(lp: LowPoly):
		# The long, rounded-square fuselage with its nose taper, lighter along the roof
		lp.hull([[-8.25, 1.50, 0.95, 1.30, 0.7], [-7.85, 2.35, 1.85, 1.62, 0.55], [-7.10, 2.90, 2.70, 1.95, 0.45],
			[-6.10, 3.00, 2.90, 2.02, 0.40], [5.60, 3.00, 2.90, 2.02, 0.40], [6.95, 2.90, 2.60, 2.12, 0.40]], OD, Transform3D.IDENTITY, OD_LIGHT)
		# Panel seams round the fuselage
		for z in [-4.3, -0.6, 3.1]:
			lp.hull([[z - 0.04, 3.04, 2.94, 2.02, 0.40], [z + 0.04, 3.04, 2.94, 2.02, 0.40]], OD_DARK, Transform3D.IDENTITY, OD)
		# Cockpit glass: windscreen across the nose, chin windows, side windows
		for x in [-0.62, 0.62]:
			lp.box(Vector3(1.05, 0.70, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 2.45, -7.55), Basis(Vector3.UP, -signf(x) * 0.25) * Basis(Vector3.RIGHT, -0.75)))
			lp.box(Vector3(0.70, 0.42, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 1.25, -8.05), Basis(Vector3.RIGHT, 0.55)))
		for x in [-1.47, 1.47]:
			lp.box(Vector3(0.03, 0.62, 1.00), Vector3(x, 2.42, -6.75), GLASS)
			# A row of cabin windows
			for k in 6:
				lp.box(Vector3(0.03, 0.38, 0.38), Vector3(x * 1.02, 2.40, -3.0 + k * 1.5), GLASS)
		lp.box(Vector3(0.03, 1.70, 1.00), Vector3(1.525, 1.55, -5.0), INTERIOR)          # open crew door
		lp.box(Vector3(0.03, 0.70, 0.80), Vector3(-1.525, 2.05, -5.0), INTERIOR)         # gun window
		# Fuel sponsons down both sides, star marking
		for x in [-1.72, 1.72]:
			lp.hull([[-2.40, 0.55, 0.70, 1.05, 0.6, x], [-1.70, 0.75, 1.05, 1.05, 0.5, x], [3.90, 0.75, 1.05, 1.05, 0.5, x], [4.70, 0.50, 0.70, 1.05, 0.6, x]], OD_DARK)
			lp.box(Vector3(0.04, 0.40, 0.40), Vector3(x * 1.22, 1.05, 2.4), STAR)
		# Front rotor pylon
		lp.hull([[-7.05, 0.70, 0.30, 3.42, 0.5], [-6.40, 1.50, 1.00, 3.70, 0.45], [-5.00, 1.50, 1.00, 3.70, 0.45], [-4.10, 1.00, 0.35, 3.50, 0.5]], OD_LIGHT, Transform3D.IDENTITY, OD_PALE)
		lp.cyl(0.20, 0.60, 8, T(Vector3(0, 4.30, -6.0), TO_Y), STEEL)
		# Aft pylon rising over the back, an engine pod on each side
		lp.hull([[3.50, 1.20, 0.50, 3.50, 0.4], [4.30, 1.80, 2.30, 4.35, 0.35], [6.50, 1.80, 2.60, 4.55, 0.35], [7.00, 1.30, 2.30, 4.65, 0.4]], OD, Transform3D.IDENTITY, OD_PALE)
		lp.cyl(0.22, 0.50, 8, T(Vector3(0, 5.95, 5.6), TO_Y), STEEL)
		for x in [-1.38, 1.38]:
			lp.hull([[3.60, 0.70, 0.70, 3.90, 1.0, x], [4.00, 0.98, 0.98, 3.90, 1.0, x], [6.40, 0.98, 0.98, 3.90, 1.0, x], [6.90, 0.72, 0.72, 3.90, 1.0, x]], OD_DARK)
			lp.cyl(0.30, 0.12, 8, T(Vector3(x, 3.90, 6.95)), INTERIOR)
			lp.cyl(0.36, 0.10, 8, T(Vector3(x, 3.90, 3.58)), STEEL_LIGHT)
		# Dark cabin interior, seen when the ramp is down
		lp.box(Vector3(2.60, 2.20, 0.04), Vector3(0, 1.85, 7.00), INTERIOR)
		# Landing gear: two up front, two under the sponsons
		for x in [-1.2, 1.2]:
			lp.cyl(0.07, 0.70, 6, T(Vector3(x, 0.60, -4.6), TO_Y), STEEL)
		for x in [-1.72, 1.72]:
			lp.cyl(0.07, 0.60, 6, T(Vector3(x, 0.55, 4.4), TO_Y), STEEL))
	for x in [-1.2, 1.2]:
		v._lp_wheel(v, Vector3(x, 0.35, -4.6), 0.35, 0.30)
	for x in [-1.72, 1.72]:
		v._lp_wheel(v, Vector3(x, 0.35, 4.4), 0.35, 0.34)
	# Rear ramp, hinged at the cabin floor
	var r := v._pivot(Vector3(0, 0.75, 7.0))
	v.ramp = r
	r.rotation.x = RAMP_OPEN
	v._lp(r, "chinook_ramp", func(lp: LowPoly):
		lp.box(Vector3(2.60, 0.16, 2.60), Vector3(0, 0, 1.3), OD_DARK, 0.04)
		for z in [0.6, 1.6]:
			lp.box(Vector3(2.50, 0.04, 0.10), Vector3(0, 0.09, z), STEEL))
	# Tandem rotors, three tapered blades each, turning opposite ways
	for hub in [[Vector3(0, 4.65, -6.0), 3.0], [Vector3(0, 6.25, 5.6), -3.0]]:
		var rotor := v._pivot(hub[0])
		v._lp(rotor, "chinook_rotor", func(lp: LowPoly):
			for k in 3:
				var a := TAU * k / 3.0 + 0.3
				lp.hull([[0.4, 0.62, 0.07, 0.0, 0.3], [8.6, 0.62, 0.06, 0.0, 0.3], [9.1, 0.36, 0.05, 0.0, 0.3]], BLADE, T(Vector3.ZERO, Basis(Vector3.UP, a) * TO_X))
			lp.cyl(0.38, 0.30, 8, T(Vector3.ZERO, TO_Y), STEEL)
			lp.cyl(0.14, 0.30, 6, T(Vector3(0, 0.25, 0), TO_Y), STEEL_LIGHT))
		v.spinners.append([rotor, Vector3.UP, hub[1]])
	return v


# --- M1126 Stryker ----------------------------------------------------------

static func stryker() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Stryker"
	for x in [-1.22, 1.22]:
		for z in [-2.6, -1.3, 1.0, 2.3]:
			v._lp_wheel(v, Vector3(x, 0.55, z), 0.55, 0.40)
	v._lp(v, "stryker_body", func(lp: LowPoly):
		# Angled hull: sloped nose, sides leaning in toward the roof
		lp.hull([[-3.55, 2.20, 0.45, 1.10, 0.25], [-3.10, 2.55, 1.20, 1.50, 0.3], [-2.30, 2.62, 1.80, 1.80, 0.3],
			[3.30, 2.62, 1.80, 1.80, 0.3], [3.42, 2.45, 1.65, 1.80, 0.35]], OD, Transform3D.IDENTITY, OD_LIGHT)
		# Side stowage bins and wheel-well lip
		for x in [-1.36, 1.36]:
			lp.box(Vector3(0.18, 0.42, 4.70), Vector3(x, 1.62, 0.40), OD_DARK, 0.05)
			lp.box(Vector3(0.10, 0.10, 6.20), Vector3(x * 0.985, 1.12, 0.10), OD_DARK)
			lp.box(Vector3(0.04, 0.28, 0.28), Vector3(x * 1.04, 2.15, 1.20), STAR)
		# Rear ramp outline, hatches, lights
		lp.box(Vector3(1.60, 1.40, 0.06), Vector3(0, 1.62, 3.44), OD_DARK)
		lp.cyl(0.30, 0.16, 8, T(Vector3(-0.70, 2.76, -2.20), TO_Y), OD_DARK)
		lp.cyl(0.30, 0.16, 8, T(Vector3(-0.30, 2.76, 1.60), TO_Y), OD_DARK)
		lp.box(Vector3(1.70, 0.06, 1.20), Vector3(0.1, 2.73, 2.40), OD_DARK)
		for x in [-0.95, 0.95]:
			lp.box(Vector3(0.22, 0.14, 0.05), Vector3(x, 1.52, -3.40), LIGHT, 0.0, T(Vector3.ZERO, Basis(Vector3.RIGHT, -0.5)))
		# Driver's vision blocks
		lp.box(Vector3(0.50, 0.08, 0.04), Vector3(-0.70, 2.62, -2.55), GLASS))
	# Remote weapon station with the .50 cal (turns as a unit)
	var t := v._pivot(Vector3(0.35, 2.55, -0.40))
	v.turret = t
	v._lp(t, "stryker_rws", func(lp: LowPoly):
		lp.hull([[-0.38, 0.55, 0.30, 0.10, 0.4], [0.35, 0.70, 0.38, 0.12, 0.3]], OD_DARK)
		lp.box(Vector3(0.22, 0.20, 0.60), Vector3(0.18, 0.35, -0.05), STEEL, 0.03)
		lp.cyl(0.045, 1.20, 6, T(Vector3(0.18, 0.37, -0.85)), STEEL)
		lp.box(Vector3(0.25, 0.25, 0.30), Vector3(-0.22, 0.40, -0.10), OD, 0.04)
		lp.box(Vector3(0.18, 0.14, 0.03), Vector3(-0.22, 0.42, -0.26), GLASS)
		lp.box(Vector3(0.22, 0.18, 0.28), Vector3(0.40, 0.30, 0.05), OD, 0.03))
	return v


# --- M1074A1 PLS truck ------------------------------------------------------

static func pls() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "PLS"
	for z in [-3.30, -1.90, 1.20, 2.55, 3.90]:
		for x in [-1.10, 1.10]:
			v._lp_wheel(v, Vector3(x, 0.60, z), 0.60, 0.42)
	v._lp(v, "pls_body", func(lp: LowPoly):
		# Chassis rails the length of the truck
		lp.box(Vector3(1.30, 0.40, 9.80), Vector3(0, 0.95, 0.30), OD_DARK, 0.05)
		# Cab: flat front, sloped windscreen, roof
		lp.hull([[-5.00, 2.40, 1.30, 1.45, 0.12], [-4.85, 2.50, 2.10, 1.85, 0.1], [-4.40, 2.50, 2.40, 2.00, 0.1], [-2.80, 2.50, 2.40, 2.00, 0.1], [-2.70, 2.40, 2.20, 1.95, 0.15]], OD, Transform3D.IDENTITY, OD_LIGHT)
		for x in [-0.60, 0.60]:
			lp.box(Vector3(1.05, 0.62, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 2.55, -4.68), Basis(Vector3.RIGHT, -0.32)))
		for x in [-1.26, 1.26]:
			lp.box(Vector3(0.03, 0.55, 0.80), Vector3(x, 2.55, -3.70), GLASS)
			lp.box(Vector3(0.10, 0.12, 0.30), Vector3(x * 1.06, 2.40, -4.55), STEEL)      # mirrors
		lp.box(Vector3(2.0, 0.55, 0.06), Vector3(0, 1.30, -5.02), OD_DARK)                  # grille
		for x in [-0.95, 0.95]:
			lp.box(Vector3(0.22, 0.14, 0.05), Vector3(x, 1.20, -5.03), LIGHT)
		lp.box(Vector3(2.50, 0.22, 0.30), Vector3(0, 0.75, -5.10), STEEL, 0.05)          # bumper
		# Fuel tank and toolbox under the cab
		lp.cyl(0.30, 1.20, 8, T(Vector3(-1.05, 1.05, -2.10)), OD_DARK)
		lp.box(Vector3(0.40, 0.45, 1.00), Vector3(1.05, 1.05, -2.10), OD_DARK, 0.04)
		# Load-handling arm (the hook) and the flatrack bed
		lp.hull([[-2.50, 1.80, 1.90, 2.15, 0.2], [-1.90, 1.80, 0.50, 1.55, 0.2]], OD_LIGHT)
		lp.box(Vector3(0.30, 0.30, 0.80), Vector3(0, 3.0, -2.30), STEEL, 0.05)
		lp.box(Vector3(2.40, 0.18, 6.60), Vector3(0, 1.38, 1.40), OD_LIGHT, 0.03, Transform3D.IDENTITY, OD_PALE)
		for z in [-1.8, 4.6]:
			lp.box(Vector3(2.40, 0.55, 0.10), Vector3(0, 1.70, z), OD_DARK)
		# Mudguards over the wheels
		for z in [-3.30, -1.90]:
			for x in [-1.12, 1.12]:
				lp.box(Vector3(0.48, 0.08, 1.30), Vector3(x, 1.30, z), OD_DARK, 0.02)
		for x in [-1.12, 1.12]:
			lp.box(Vector3(0.48, 0.08, 4.00), Vector3(x, 1.30, 2.55), OD_DARK, 0.02))
	return v


# --- M978A4 HEMTT fuel truck --------------------------------------------------

const FUEL_TANK := Color(0.36, 0.39, 0.26)


static func fuel_truck() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "FuelTruck"
	for z in [-3.40, -2.05, 2.30, 3.65]:
		for x in [-1.12, 1.12]:
			v._lp_wheel(v, Vector3(x, 0.62, z), 0.62, 0.46)
	v._lp(v, "fueltruck_body", func(lp: LowPoly):
		lp.box(Vector3(1.30, 0.40, 9.60), Vector3(0, 1.00, 0.20), OD_DARK, 0.05)
		# HEMTT cab: blunt nose, the engine hood sticking out in front of a flat windscreen
		lp.hull([[-5.00, 2.30, 1.10, 1.55, 0.15], [-4.30, 2.40, 1.20, 1.62, 0.12]], OD, Transform3D.IDENTITY, OD_LIGHT)
		lp.hull([[-4.30, 2.50, 2.00, 2.05, 0.10], [-2.75, 2.50, 2.00, 2.05, 0.10], [-2.60, 2.40, 1.90, 2.05, 0.15]], OD, Transform3D.IDENTITY, OD_LIGHT)
		for x in [-0.60, 0.60]:
			lp.box(Vector3(1.05, 0.62, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 2.55, -4.30), Basis(Vector3.RIGHT, -0.12)))
		for x in [-1.26, 1.26]:
			lp.box(Vector3(0.03, 0.55, 0.90), Vector3(x, 2.55, -3.50), GLASS)
			lp.box(Vector3(0.10, 0.12, 0.30), Vector3(x * 1.06, 2.40, -4.40), STEEL)
		lp.box(Vector3(2.0, 0.55, 0.06), Vector3(0, 1.40, -5.02), OD_DARK)
		for x in [-0.95, 0.95]:
			lp.box(Vector3(0.22, 0.14, 0.05), Vector3(x, 1.25, -5.03), LIGHT)
		lp.box(Vector3(2.50, 0.22, 0.30), Vector3(0, 0.85, -5.10), STEEL, 0.05)
		lp.cyl(0.10, 0.90, 6, T(Vector3(1.05, 3.05, -2.75), TO_Y), STEEL)                 # exhaust stack
		# The tanker: a long rounded tank in a frame, ladder and catwalk on top
		lp.hull([[-2.25, 1.60, 1.30, 2.15, 0.85], [-1.95, 2.25, 1.75, 2.20, 0.75], [4.45, 2.25, 1.75, 2.20, 0.75], [4.75, 1.60, 1.30, 2.15, 0.85]], FUEL_TANK, Transform3D.IDENTITY, OD_LIGHT)
		for z in [-1.0, 1.25, 3.5]:
			lp.hull([[z - 0.05, 2.32, 1.82, 2.20, 0.75], [z + 0.05, 2.32, 1.82, 2.20, 0.75]], OD_DARK)
		lp.box(Vector3(0.60, 0.06, 5.60), Vector3(0, 3.12, 1.25), STEEL)
		for z in [0.0, 2.6]:
			lp.cyl(0.24, 0.12, 8, T(Vector3(0, 3.16, z), TO_Y), STEEL_LIGHT)                # filler hatches
		# Pump and hose reels at the back
		lp.box(Vector3(2.30, 1.10, 0.70), Vector3(0, 1.75, 5.05), OD_DARK, 0.05)
		for x in [-0.55, 0.55]:
			lp.cyl(0.40, 0.30, 12, T(Vector3(x, 1.80, 5.45)), STEEL)
		for x in [-1.10, 1.10]:
			lp.box(Vector3(0.04, 0.40, 0.40), Vector3(x * 1.02, 2.30, 0.8), STAR)
		# Mudguards
		for z in [-3.40, -2.05]:
			for x in [-1.12, 1.12]:
				lp.box(Vector3(0.50, 0.08, 1.30), Vector3(x, 1.32, z), OD_DARK, 0.02)
		for x in [-1.12, 1.12]:
			lp.box(Vector3(0.50, 0.08, 2.70), Vector3(x, 1.32, 2.98), OD_DARK, 0.02))
	return v


# --- M1078 LMTV ---------------------------------------------------------------

const CANVAS := Color(0.38, 0.40, 0.27)


static func lmtv() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "LMTV"
	for z in [-2.20, 1.90]:
		for x in [-1.05, 1.05]:
			v._lp_wheel(v, Vector3(x, 0.58, z), 0.58, 0.44)
	v._lp(v, "lmtv_body", func(lp: LowPoly):
		lp.box(Vector3(1.20, 0.35, 7.20), Vector3(0, 1.00, 0.0), OD_DARK, 0.05)
		# Flat-nosed cab-over: tall square cab, short sloped hood
		lp.hull([[-3.50, 2.30, 1.10, 1.50, 0.15], [-3.10, 2.40, 1.25, 1.58, 0.12]], OD, Transform3D.IDENTITY, OD_LIGHT)
		lp.hull([[-3.10, 2.40, 2.00, 2.00, 0.10], [-1.55, 2.40, 2.00, 2.00, 0.10], [-1.45, 2.30, 1.90, 2.00, 0.15]], OD, Transform3D.IDENTITY, OD_LIGHT)
		for x in [-0.56, 0.56]:
			lp.box(Vector3(1.00, 0.60, 0.04), Vector3.ZERO, GLASS, 0.0, T(Vector3(x, 2.55, -3.12), Basis(Vector3.RIGHT, -0.10)))
		for x in [-1.21, 1.21]:
			lp.box(Vector3(0.03, 0.55, 0.85), Vector3(x, 2.55, -2.40), GLASS)
			lp.box(Vector3(0.10, 0.12, 0.30), Vector3(x * 1.07, 2.45, -3.20), STEEL)
		lp.box(Vector3(1.90, 0.50, 0.06), Vector3(0, 1.38, -3.52), OD_DARK)
		for x in [-0.90, 0.90]:
			lp.box(Vector3(0.22, 0.14, 0.05), Vector3(x, 1.25, -3.53), LIGHT)
		lp.box(Vector3(2.40, 0.22, 0.30), Vector3(0, 0.85, -3.60), STEEL, 0.05)
		# Cargo bed with low sides, and the canvas cover on its bows
		lp.box(Vector3(2.40, 0.55, 4.60), Vector3(0, 1.55, 1.30), OD, 0.04, Transform3D.IDENTITY, OD_LIGHT)
		lp.hull([[-1.00, 2.36, 1.30, 2.45, 0.5], [3.55, 2.36, 1.30, 2.45, 0.5]], CANVAS, Transform3D.IDENTITY, OD_PALE)
		for z in [0.15, 1.30, 2.45]:
			lp.hull([[z - 0.04, 2.40, 1.34, 2.45, 0.5], [z + 0.04, 2.40, 1.34, 2.45, 0.5]], OD_DARK, Transform3D.IDENTITY, CANVAS)
		lp.box(Vector3(1.60, 0.90, 0.04), Vector3(0, 2.35, 3.58), INTERIOR)                # open tailgate flap
		for x in [-1.18, 1.18]:
			lp.box(Vector3(0.04, 0.35, 0.35), Vector3(x * 1.02, 1.55, 0.6), STAR)
			lp.cyl(0.26, 0.90, 8, T(Vector3(x * 0.92, 1.02, -0.60)), OD_DARK)            # fuel tanks
		for z in [-2.20, 1.90]:
			for x in [-1.06, 1.06]:
				lp.box(Vector3(0.48, 0.08, 1.30), Vector3(x, 1.25, z), OD_DARK, 0.02))
	return v


# --- M2A3 Bradley ---------------------------------------------------------------

static func bradley() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Bradley"
	v._lp(v, "bradley_hull", func(lp: LowPoly):
		v._tracks(lp, 1.42, 6.30, 0.55, 0.95, 6, 0.33)
		# Side skirts over the tracks
		for x in [-1.72, 1.72]:
			lp.box(Vector3(0.08, 0.55, 6.20), Vector3(x, 0.98, 0.0), OD_DARK, 0.02)
		# Boxy hull: long sloped glacis, near-vertical sides, flat deck
		lp.hull([[-3.30, 3.30, 0.45, 1.00, 0.10], [-2.20, 3.40, 1.25, 1.42, 0.08], [3.15, 3.40, 1.30, 1.40, 0.08], [3.25, 3.30, 1.20, 1.40, 0.12]], OD, Transform3D.IDENTITY, OD_LIGHT)
		# Applique armour tiles down the sides
		for x in [-1.73, 1.73]:
			for k in 5:
				lp.box(Vector3(0.10, 0.45, 1.05), Vector3(x, 1.65, -2.10 + k * 1.10), OD_LIGHT, 0.03)
			lp.box(Vector3(0.04, 0.30, 0.30), Vector3(x * 1.035, 1.62, 2.20), STAR)
		# Rear ramp, driver's hatch, lights, exhaust grille
		lp.box(Vector3(1.90, 1.10, 0.06), Vector3(0, 1.45, 3.26), OD_DARK)
		lp.cyl(0.30, 0.12, 8, T(Vector3(-0.95, 2.08, -1.90), TO_Y), OD_DARK)
		lp.box(Vector3(0.80, 0.04, 0.70), Vector3(1.00, 2.04, -2.10), OD_DARK)
		for x in [-1.30, 1.30]:
			lp.box(Vector3(0.22, 0.14, 0.05), Vector3.ZERO, LIGHT, 0.0, T(Vector3(x, 1.52, -2.90), Basis(Vector3.RIGHT, -0.6))))
	# Turret: 25 mm Bushmaster in front, the TOW launcher box on the left
	var t := v._pivot(Vector3(0.25, 2.05, -0.30))
	v.turret = t
	v._lp(t, "bradley_turret", func(lp: LowPoly):
		lp.hull([[-1.15, 1.60, 0.40, 0.25, 0.10], [-0.75, 2.05, 0.75, 0.38, 0.10], [1.15, 2.05, 0.75, 0.38, 0.10], [1.30, 1.90, 0.65, 0.38, 0.12]], OD, Transform3D.IDENTITY, OD_LIGHT)
		lp.box(Vector3(0.45, 0.35, 0.50), Vector3(0.55, 0.92, 0.10), OD_DARK, 0.04)        # commander's sight
		lp.box(Vector3(0.30, 0.18, 0.04), Vector3(0.55, 0.95, -0.16), GLASS)
		lp.box(Vector3(0.40, 0.40, 0.70), Vector3(0.15, 0.35, -1.20), OD_DARK, 0.05)       # gun mantlet
		lp.cyl(0.06, 2.10, 8, T(Vector3(0.15, 0.38, -2.40)), STEEL)
		lp.cyl(0.09, 0.30, 8, T(Vector3(0.15, 0.38, -3.40)), STEEL_LIGHT)
		# TOW launcher: two tubes in a box on an arm
		lp.box(Vector3(0.10, 0.35, 0.50), Vector3(-1.08, 0.40, 0.30), OD_DARK)
		lp.box(Vector3(0.48, 0.55, 1.35), Vector3(-1.40, 0.55, 0.05), OD, 0.04, Transform3D.IDENTITY, OD_LIGHT)
		for y in [0.42, 0.70]:
			lp.cyl(0.11, 0.04, 8, T(Vector3(-1.40, y, -0.64)), INTERIOR)
		# Smoke grenade launchers
		for x in [-0.85, 0.85]:
			lp.box(Vector3(0.30, 0.18, 0.18), Vector3(x, 0.55, -0.95), STEEL, 0.03))
	return v


# --- AH-64D Apache ---------------------------------------------------------------

const AH := Color(0.20, 0.23, 0.19)
const AH_TOP := Color(0.27, 0.30, 0.24)
const HELLFIRE := Color(0.62, 0.62, 0.56)


static func apache() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "Apache"
	v._lp(v, "apache_body", func(lp: LowPoly):
		# Narrow, flat-sided fuselage with the tandem cockpit stepped up at the front
		lp.hull([[-4.10, 0.60, 0.70, 1.35, 0.4], [-3.50, 0.95, 1.20, 1.45, 0.35], [-1.00, 1.15, 1.45, 1.55, 0.3],
			[1.80, 1.20, 1.50, 1.65, 0.3], [2.70, 0.90, 1.10, 1.80, 0.35]], AH, Transform3D.IDENTITY, AH_TOP)
		# Canopy: gunner in front, pilot raised behind
		lp.hull([[-3.75, 0.55, 0.25, 2.05, 0.4], [-3.15, 0.85, 0.55, 2.20, 0.35], [-2.20, 0.85, 0.60, 2.25, 0.35], [-1.95, 0.80, 0.85, 2.40, 0.35],
			[-0.90, 0.80, 0.85, 2.40, 0.35], [-0.55, 0.60, 0.45, 2.45, 0.4]], GLASS, Transform3D.IDENTITY, GLASS_LIGHT)
		lp.box(Vector3(0.82, 0.06, 0.06), Vector3(0, 2.62, -2.05), AH_TOP)
		# Sensor turret on the nose (TADS) and the 30 mm chain gun under the chin
		lp.cyl(0.32, 0.50, 8, T(Vector3(0, 1.20, -4.15), TO_Y), AH_TOP)
		lp.box(Vector3(0.30, 0.22, 0.10), Vector3(0, 1.22, -4.48), GLASS)
		lp.box(Vector3(0.36, 0.30, 0.50), Vector3(0, 0.80, -2.70), STEEL, 0.05)
		lp.cyl(0.05, 1.40, 6, T(Vector3(0, 0.80, -3.60)), STEEL)
		# Engine nacelles each side of the rotor mast, with the black-hole exhausts
		for x in [-0.95, 0.95]:
			lp.hull([[-0.70, 0.55, 0.60, 2.35, 1.0, x], [-0.40, 0.70, 0.75, 2.35, 1.0, x], [1.30, 0.70, 0.75, 2.35, 1.0, x], [1.80, 0.50, 0.55, 2.40, 1.0, x]], AH, Transform3D.IDENTITY, AH_TOP)
			lp.cyl(0.22, 0.10, 8, T(Vector3(x, 2.35, -0.72)), INTERIOR)
			lp.box(Vector3(0.50, 0.25, 0.30), Vector3(x * 1.05, 2.45, 1.95), BH_DARK, 0.03)
		lp.hull([[-0.80, 0.70, 0.55, 2.55, 0.4], [1.20, 0.70, 0.55, 2.55, 0.4]], AH_TOP)
		# Stub wings, two pylons each side: Hellfires outboard, rocket pods inboard
		lp.hull([[-1.95, 0.40, 0.10, 1.65, 0.4, 0.15], [1.95, 0.55, 0.12, 1.65, 0.4, 0.15]], AH, T(Vector3.ZERO, TO_X))
		for x in [-1.75, 1.75]:
			for y in [1.25, 1.00]:
				for dx in [-0.12, 0.12]:
					lp.cyl(0.07, 1.30, 6, T(Vector3(x + dx, y, 0.10)), HELLFIRE)
					lp.cyl(0.07, 0.10, 6, T(Vector3(x + dx, y, -0.58)), Color(0.2, 0.2, 0.18))
		for x in [-1.05, 1.05]:
			lp.hull([[-0.80, 0.22, 0.22, 1.18, 1.0], [-0.65, 0.42, 0.42, 1.18, 1.0], [0.75, 0.42, 0.42, 1.18, 1.0]], AH_TOP, T(Vector3(x, 0, 0.15)))
			lp.cyl(0.18, 0.04, 8, T(Vector3(x, 1.18, -0.66)), INTERIOR)
		# Tail boom, fin, tailplane, tail wheel
		lp.hull([[2.50, 0.75, 0.80, 1.85, 0.4], [5.80, 0.38, 0.45, 2.05, 0.4], [7.60, 0.32, 0.38, 2.20, 0.4]], AH)
		lp.hull([[6.85, 0.18, 0.60, 2.45, 0.3], [7.45, 0.20, 1.70, 3.00, 0.3], [7.95, 0.16, 1.30, 3.25, 0.3]], AH, Transform3D.IDENTITY, AH_TOP)
		lp.box(Vector3(2.10, 0.06, 0.65), Vector3(0, 2.15, 7.35), BH_DARK, 0.02)
		lp.cyl(0.04, 0.45, 6, T(Vector3(0, 1.30, 7.30), TO_Y), STEEL)
		lp.tyre(0.20, 0.12, 16, T(Vector3(0, 1.00, 7.30), TO_X), TIRE)
		# Main gear: struts out to the sides under the cockpit
		for x in [-1.10, 1.10]:
			lp.cyl(0.06, 0.95, 6, T(Vector3(x * 0.75, 0.70, -1.30), Basis(Vector3.FORWARD, deg_to_rad(-35 * signf(x))) * TO_Y), STEEL)
			lp.tyre(0.34, 0.20, 16, T(Vector3(x, 0.34, -1.30), TO_X), TIRE)
		# Mast with the Longbow radar dome on top
		lp.cyl(0.13, 0.55, 8, T(Vector3(0, 3.05, 0.25), TO_Y), STEEL)
		lp.cyl(0.42, 0.40, 10, T(Vector3(0, 3.95, 0.25), TO_Y), AH_TOP, 0.30))
	var tail := v._pivot(Vector3(-0.22, 3.10, 7.65))
	v._lp(tail, "apache_tail_rotor", func(lp: LowPoly):
		for k in 2:
			lp.box(Vector3(0.04, 2.40, 0.18), Vector3.ZERO, BLADE, 0.0, T(Vector3.ZERO, Basis(Vector3.RIGHT, k * PI * 0.5 + 0.6)))
		lp.cyl(0.10, 0.14, 8, T(Vector3.ZERO, TO_X), STEEL))
	v.spinners.append([tail, Vector3.RIGHT, 9.0])
	var rotor := v._pivot(Vector3(0, 3.40, 0.25))
	v._lp(rotor, "apache_rotor", func(lp: LowPoly):
		for k in 4:
			lp.hull([[0.30, 0.50, 0.06, 0.0, 0.3], [6.80, 0.50, 0.05, 0.0, 0.3], [7.20, 0.30, 0.04, 0.0, 0.3]], BLADE, T(Vector3.ZERO, Basis(Vector3.UP, k * PI * 0.5 + 0.3) * TO_X))
		lp.cyl(0.38, 0.22, 8, T(Vector3.ZERO, TO_Y), STEEL))
	v.spinners.append([rotor, Vector3.UP, 3.2])
	return v


# --- MH-6 Little Bird -------------------------------------------------------------

const MH := Color(0.12, 0.13, 0.12)
const MH_TOP := Color(0.19, 0.20, 0.18)


static func mh6() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "LittleBird"
	v._lp(v, "mh6_body", func(lp: LowPoly):
		# The egg: a short, round cabin bulging out at the front
		lp.hull([[-1.75, 0.55, 0.55, 1.15, 0.8], [-1.45, 1.20, 1.15, 1.25, 0.7], [-0.70, 1.45, 1.55, 1.40, 0.6],
			[0.60, 1.40, 1.50, 1.45, 0.6], [1.30, 0.95, 1.05, 1.60, 0.6]], MH, Transform3D.IDENTITY, MH_TOP)
		# Big bubble windscreen over the front half
		lp.hull([[-1.78, 0.45, 0.35, 1.30, 0.8], [-1.50, 1.05, 0.90, 1.50, 0.7], [-0.75, 1.30, 1.10, 1.70, 0.6], [-0.30, 1.20, 0.80, 1.90, 0.6]], GLASS, Transform3D.IDENTITY, GLASS_LIGHT)
		# Thin tail boom with the T-tail
		lp.hull([[1.10, 0.45, 0.45, 1.70, 0.6], [3.80, 0.20, 0.22, 1.85, 0.6], [4.30, 0.18, 0.20, 1.90, 0.6]], MH)
		lp.box(Vector3(1.20, 0.05, 0.40), Vector3(0, 2.40, 4.10), MH_TOP, 0.01)
		lp.hull([[3.85, 0.10, 0.30, 1.85, 0.3], [4.15, 0.10, 0.80, 2.15, 0.3], [4.40, 0.08, 0.70, 2.30, 0.3]], MH_TOP)
		# Skids, and the outboard benches the assaulters ride on
		for x in [-0.80, 0.80]:
			lp.box(Vector3(0.08, 0.08, 2.90), Vector3(x, 0.05, -0.10), STEEL, 0.02)
			for z in [-0.80, 0.70]:
				lp.cyl(0.035, 0.75, 6, T(Vector3(x * 0.85, 0.40, z), Basis(Vector3.FORWARD, deg_to_rad(15 * signf(x))) * TO_Y), STEEL)
		for x in [-1.05, 1.05]:
			lp.box(Vector3(0.45, 0.06, 1.70), Vector3(x, 0.92, -0.15), STEEL_LIGHT, 0.02)
			lp.box(Vector3(0.04, 0.30, 1.70), Vector3(x * 1.20, 1.08, -0.15), STEEL)
		# Mast and the engine hump
		lp.hull([[-0.30, 0.70, 0.30, 2.15, 0.6], [0.80, 0.70, 0.30, 2.15, 0.6]], MH_TOP)
		lp.cyl(0.08, 0.40, 6, T(Vector3(0, 2.45, 0.0), TO_Y), STEEL))
	var tail := v._pivot(Vector3(0.14, 2.05, 4.30))
	v._lp(tail, "mh6_tail_rotor", func(lp: LowPoly):
		lp.box(Vector3(0.03, 1.10, 0.12), Vector3.ZERO, BLADE)
		lp.cyl(0.06, 0.08, 6, T(Vector3.ZERO, TO_X), STEEL))
	v.spinners.append([tail, Vector3.RIGHT, 12.0])
	var rotor := v._pivot(Vector3(0, 2.62, 0.0))
	v._lp(rotor, "mh6_rotor", func(lp: LowPoly):
		for k in 6:
			lp.hull([[0.15, 0.22, 0.04, 0.0, 0.3], [3.80, 0.22, 0.03, 0.0, 0.3], [4.00, 0.14, 0.03, 0.0, 0.3]], BLADE, T(Vector3.ZERO, Basis(Vector3.UP, k * TAU / 6.0) * TO_X))
		lp.cyl(0.18, 0.14, 8, T(Vector3.ZERO, TO_Y), STEEL))
	v.spinners.append([rotor, Vector3.UP, 4.0])
	return v


# --- MH-6 Little Bird, smooth (test of a realistic, non-faceted look) -------------------

static func _pbr(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static var _mh6_cache := {}


static func mh6_smooth() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "LittleBirdSmooth"
	var paint := _pbr(Color(0.11, 0.115, 0.12), 0.42, 0.3)
	var glass := _pbr(Color(0.08, 0.11, 0.14, 0.42), 0.04, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := _pbr(Color(0.03, 0.03, 0.035), 0.9)
	var inner := _pbr(Color(0.05, 0.05, 0.055), 0.95)
	inner.cull_mode = BaseMaterial3D.CULL_FRONT         # the cabin's inside walls
	var metal := _pbr(Color(0.38, 0.39, 0.40), 0.32, 0.8)
	var blade_m := _pbr(Color(0.075, 0.075, 0.08), 0.55, 0.2)
	var bench := _pbr(Color(0.15, 0.16, 0.14), 0.8)

	if not _mh6_cache.has("body"):
		var sm := SmoothMesh.new()
		var s_paint := sm.surface(paint)
		var s_glass := sm.surface(glass)
		var s_dark := sm.surface(dark)
		var s_inner := sm.surface(inner)
		var s_metal := sm.surface(metal)

		# The egg: round nose, widest just behind the pilots, tapering into the tail boom
		var body := [[-1.82, 0.02, 0.02, 1.02], [-1.74, 0.34, 0.40, 1.06], [-1.55, 0.54, 0.62, 1.13],
			[-1.22, 0.66, 0.76, 1.21], [-0.80, 0.71, 0.84, 1.27], [-0.30, 0.72, 0.85, 1.30],
			[0.20, 0.69, 0.80, 1.33], [0.62, 0.58, 0.68, 1.39], [0.96, 0.42, 0.50, 1.49],
			[1.25, 0.25, 0.31, 1.58], [1.55, 0.19, 0.22, 1.62], [3.00, 0.14, 0.16, 1.68],
			[4.25, 0.10, 0.11, 1.74], [4.40, 0.02, 0.02, 1.75]]
		sm.loft(body, 120, 40, func(p: Vector3, _n: Vector3) -> int:
			# Doors off: open beside the pilots and behind them, with the frame post between
			if p.z > -1.00 and p.z < 0.52 and absf(p.x) > 0.42 and p.y > 0.74 and p.y < 1.90:
				return s_paint if absf(p.z + 0.26) < 0.045 else -1
			# Bubble windscreen over the front, down to the chin windows; a slim centre post
			if p.z < -0.32:
				if absf(p.x) < 0.03 and p.y > 0.95:
					return s_paint
				if p.y < 0.74 and p.z > -1.30:
					return s_paint
				if p.y < 0.62:
					return s_paint
				return s_glass
			return s_paint)
		# The cabin's inside walls and floor (seen through the glass and the door openings)
		sm.loft([[-1.70, 0.30, 0.34, 1.07], [-1.40, 0.60, 0.68, 1.14], [-0.80, 0.68, 0.80, 1.27],
			[0.30, 0.66, 0.76, 1.33], [0.70, 0.52, 0.60, 1.40]], 30, 24, func(p: Vector3, _n: Vector3) -> int:
				return -1 if p.z > -1.00 and p.z < 0.52 and absf(p.x) > 0.36 and p.y > 0.72 and p.y < 1.92 else s_inner)
		# Engine fairing on the roof and the exhaust out the back of it
		sm.loft([[-0.30, 0.02, 0.02, 2.10], [-0.18, 0.22, 0.11, 2.12], [0.40, 0.30, 0.15, 2.13],
			[0.95, 0.20, 0.11, 2.05], [1.12, 0.05, 0.05, 1.98]], 24, 20, func(_p, _n): return s_paint)
		sm.sweep([Vector3(0, 1.98, 1.00), Vector3(0, 1.96, 1.22)], 0.075, 12, s_dark)
		# Rotor mast
		sm.sweep([Vector3(0, 2.10, 0.02), Vector3(0, 2.60, 0.02)], 0.065, 12, s_metal)
		# Skid gear: two skids with turned-up toes on arched cross tubes
		for x in [-0.92, 0.92]:
			sm.sweep([Vector3(x, 0.24, -1.98), Vector3(x, 0.12, -1.82), Vector3(x, 0.065, -1.55),
				Vector3(x, 0.065, 1.05), Vector3(x, 0.09, 1.25)], 0.045, 12, s_paint)
		for z in [-0.85, 0.45]:
			sm.sweep([Vector3(-0.92, 0.07, z), Vector3(-0.88, 0.32, z), Vector3(-0.70, 0.50, z), Vector3(-0.30, 0.56, z),
				Vector3(0.30, 0.56, z), Vector3(0.70, 0.50, z), Vector3(0.88, 0.32, z), Vector3(0.92, 0.07, z)], 0.05, 12, s_paint)
		# Outboard bench supports (the benches themselves are planks, below)
		for x in [-1.0, 1.0]:
			for z in [-0.70, 0.40]:
				sm.sweep([Vector3(x * 0.62, 0.72, z), Vector3(x * 1.30, 0.76, z)], 0.03, 8, s_metal)
		# FLIR ball under the nose
		sm.loft([[-1.60, 0.01, 0.01, 0.62], [-1.56, 0.12, 0.12, 0.62], [-1.42, 0.165, 0.165, 0.62],
			[-1.28, 0.12, 0.12, 0.62], [-1.24, 0.01, 0.01, 0.62]], 12, 16, func(p, _n): return s_glass if p.z < -1.54 and p.y > 0.58 and p.y < 0.68 else s_dark)
		sm.sweep([Vector3(0, 0.66, -1.42), Vector3(0, 0.80, -1.42)], 0.04, 8, s_dark)
		# Tail: fin, T-tail with endplates, ventral fin and the tail skid
		sm.blade(Vector3(0, 1.80, 4.02), Vector3(0, 2.46, 4.30), 0.46, 0.06, s_paint, Transform3D.IDENTITY, 0.30, Vector3.BACK)
		for x in [-1.0, 1.0]:
			sm.blade(Vector3(0, 2.44, 4.30), Vector3(x * 0.82, 2.44, 4.30), 0.40, 0.05, s_paint, Transform3D.IDENTITY, 0.32, Vector3.BACK)
			sm.blade(Vector3(x * 0.84, 2.24, 4.27), Vector3(x * 0.84, 2.64, 4.36), 0.30, 0.04, s_paint, Transform3D.IDENTITY, 0.22, Vector3.BACK)
		sm.blade(Vector3(0, 1.66, 4.08), Vector3(0, 1.18, 4.30), 0.36, 0.05, s_paint, Transform3D.IDENTITY, 0.22, Vector3.BACK)
		sm.sweep([Vector3(0, 1.20, 4.10), Vector3(0, 1.08, 4.40), Vector3(0, 1.16, 4.62)], 0.022, 8, s_metal)
		_mh6_cache["body"] = sm.commit()
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = _mh6_cache["body"]
	v.add_child(body_mi)
	UnitLook.add_outline(body_mi, false, false)

	# Benches (planks), seats and the two pilots inside
	for x in [-1.14, 1.14]:
		var b := v._prim_box(Vector3(0.44, 0.05, 1.65), Vector3(x, 0.79, -0.15), bench)
		b.set_meta("no_outline", true)
	v.add_child(_cockpit())

	# Main rotor: six thin blades on a hub
	var rotor := v._pivot(Vector3(0, 2.64, 0.02))
	if not _mh6_cache.has("rotor"):
		var rm := SmoothMesh.new()
		var r_blade := rm.surface(blade_m)
		var r_hub := rm.surface(metal)
		for k in 6:
			var a := TAU * k / 6.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			rm.blade(dir * 0.22, dir * 4.15 + Vector3.DOWN * 0.05, 0.19, 0.035, r_blade)
			rm.sweep([dir * 0.05, dir * 0.30], 0.045, 8, r_hub)
		rm.loft([[-0.09, 0.02, 0.02, 0.0], [-0.07, 0.17, 0.17, 0.0], [0.06, 0.17, 0.17, 0.0], [0.10, 0.06, 0.06, 0.0]], 8, 20,
			func(_p, _n): return r_hub, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
		_mh6_cache["rotor"] = rm.commit()
	var rotor_mi := MeshInstance3D.new()
	rotor_mi.mesh = _mh6_cache["rotor"]
	rotor.add_child(rotor_mi)
	UnitLook.add_outline(rotor_mi, false, false)
	v.spinners.append([rotor, Vector3.UP, 4.0])

	# Tail rotor on the left of the fin
	var tail := v._pivot(Vector3(-0.17, 1.76, 4.18))
	if not _mh6_cache.has("tail"):
		var tm := SmoothMesh.new()
		var t_blade := tm.surface(blade_m)
		var t_hub := tm.surface(metal)
		for y in [-1.0, 1.0]:
			tm.blade(Vector3(0, y * 0.05, 0), Vector3(0, y * 0.70, 0), 0.10, 0.02, t_blade, Transform3D.IDENTITY, 0.08, Vector3.BACK)
		tm.sweep([Vector3(0.06, 0, 0), Vector3(-0.08, 0, 0)], 0.05, 10, t_hub)
		_mh6_cache["tail"] = tm.commit()
	var tail_mi := MeshInstance3D.new()
	tail_mi.mesh = _mh6_cache["tail"]
	tail.add_child(tail_mi)
	v.spinners.append([tail, Vector3.RIGHT, 12.0])
	return v


static var _pilot_cache := {}


static func add_pilot(parent: Node3D, seat: Vector3, skin := "skin_a", right_seat := false) -> MeshInstance3D:
	## A seated aircrewman (seat, harness, hands on the controls, feet on the pedals), placed so
	## his seat cushion is at `seat` (local to parent), facing -Z. Built once, then shared.
	var key := "%s_%s" % [skin, right_seat]
	if not _pilot_cache.has(key):
		var sm := SmoothMesh.new()
		var m := crew_materials(sm)
		_pilot(sm, m, 0.0, skin, right_seat)
		_pilot_cache[key] = sm.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _pilot_cache[key]
	mi.position = seat - Vector3(0.0, 0.80, -0.60)
	mi.set_meta("no_outline", true)
	parent.add_child(mi)
	return mi


static func crew_materials(sm: SmoothMesh) -> Dictionary:
	return {
		"suit": sm.surface(_pbr(Color(0.36, 0.38, 0.29), 0.95)),        # sage flight suit
		"vest": sm.surface(_pbr(Color(0.45, 0.39, 0.28), 0.9)),         # coyote survival vest
		"pouch": sm.surface(_pbr(Color(0.40, 0.35, 0.25), 0.9)),
		"skin_a": sm.surface(_pbr(Color(0.80, 0.60, 0.47), 0.7)),
		"skin_b": sm.surface(_pbr(Color(0.52, 0.37, 0.27), 0.7)),
		"helmet": sm.surface(_pbr(Color(0.30, 0.32, 0.26), 0.55)),
		"visor": sm.surface(_pbr(Color(0.04, 0.05, 0.06), 0.06, 0.85)),
		"black": sm.surface(_pbr(Color(0.05, 0.05, 0.055), 0.7)),       # gloves, mic, sticks
		"boot": sm.surface(_pbr(Color(0.27, 0.21, 0.15), 0.8)),
		"seat": sm.surface(_pbr(Color(0.10, 0.10, 0.11), 0.85)),
		"strap": sm.surface(_pbr(Color(0.15, 0.17, 0.14), 0.9)),
		"metal": sm.surface(_pbr(Color(0.35, 0.36, 0.37), 0.35, 0.8)),
		"screen": sm.surface(_screen_mat()),
	}


static func _cockpit() -> MeshInstance3D:
	## The two pilots in their seats, hands on the controls, and the instrument panel
	if _mh6_cache.has("cockpit"):
		var c := MeshInstance3D.new()
		c.mesh = _mh6_cache["cockpit"]
		c.set_meta("no_outline", true)
		return c
	var sm := SmoothMesh.new()
	var m := crew_materials(sm)
	_pilot(sm, m, -0.30, "skin_a", false)      # pilot on the left
	_pilot(sm, m, 0.30, "skin_b", true)        # co-pilot on the right
	# Instrument panel: a small pod low between the pilots' knees, two screens facing them
	sm.loft([[-1.30, 0.02, 0.02, 0.80], [-1.27, 0.15, 0.13, 0.82], [-1.12, 0.15, 0.13, 0.84], [-1.08, 0.02, 0.02, 0.84]], 8, 16,
		func(_p, _n): return m.seat, Transform3D.IDENTITY, 5.0)
	for x in [-0.07, 0.07]:
		sm.loft([[-1.09, 0.055, 0.075, 0.86, x], [-1.08, 0.055, 0.075, 0.86, x]], 1, 4,
			func(_p, n: Vector3): return m.screen if n.z > 0.5 else m.seat, Transform3D.IDENTITY, 8.0)
	sm.loft([[-1.12, 0.07, 0.12, 0.62], [-0.70, 0.07, 0.06, 0.55], [-0.62, 0.02, 0.02, 0.54]], 6, 12,
		func(_p, _n): return m.seat, Transform3D.IDENTITY, 4.0)
	var mi := MeshInstance3D.new()
	mi.mesh = sm.commit()
	_mh6_cache["cockpit"] = mi.mesh
	mi.set_meta("no_outline", true)
	return mi


static func _screen_mat() -> StandardMaterial3D:
	var s := _pbr(Color(0.10, 0.30, 0.22), 0.3)
	s.emission_enabled = true
	s.emission = Color(0.20, 0.75, 0.45)
	s.emission_energy_multiplier = 0.8
	return s


static func _pilot(sm: SmoothMesh, m: Dictionary, x: float, skin: String, right_seat: bool) -> void:
	## One aircrewman sitting at x, facing -Z: right hand on the cyclic, left on the collective
	var sx := 1.0 if right_seat else -1.0
	# Armoured bucket seat with a high back, and the harness over the shoulders
	sm.loft([[-0.82, 0.21, 0.035, 0.80, x], [-0.40, 0.22, 0.04, 0.80, x], [-0.36, 0.22, 0.04, 0.79, x]], 4, 16,
		func(_p, _n): return m.seat, Transform3D.IDENTITY, 6.0)
	sm.loft([[0.80, 0.22, 0.04, 0.36], [1.52, 0.21, 0.04, 0.36]], 4, 16, func(_p, _n): return m.seat,
		Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 0, 0)), 6.0)
	# Body: hips to shoulders (built upright: stations are heights)
	var up := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 0, 0))
	sm.loft([[0.84, 0.13, 0.11, 0.53], [0.92, 0.155, 0.125, 0.53], [1.06, 0.145, 0.115, 0.545],
		[1.20, 0.165, 0.12, 0.555], [1.34, 0.185, 0.115, 0.555], [1.42, 0.16, 0.10, 0.55],
		[1.47, 0.07, 0.055, 0.55]], 24, 24, func(_p, _n): return m.suit, up)
	# Survival vest over the chest, with pouches
	sm.loft([[1.02, 0.155, 0.128, 0.553], [1.12, 0.163, 0.132, 0.558], [1.28, 0.178, 0.135, 0.562],
		[1.37, 0.176, 0.12, 0.558], [1.40, 0.15, 0.10, 0.555]], 12, 24, func(_p, _n): return m.vest, up)
	for px in [-0.09, 0.0, 0.09]:
		sm.loft([[-0.70, 0.035, 0.05, 1.15, x + px], [-0.66, 0.04, 0.055, 1.15, x + px], [-0.635, 0.03, 0.045, 1.15, x + px]], 3, 10,
			func(_p, _n): return m.pouch, Transform3D.IDENTITY, 6.0)
	# Harness straps over the shoulders down to the lap belt
	for sxs in [-1.0, 1.0]:
		sm.limb([Vector3(x + sxs * 0.10, 1.45, -0.48), Vector3(x + sxs * 0.11, 1.41, -0.66), Vector3(x + sxs * 0.06, 1.12, -0.70), Vector3(x, 0.98, -0.68)],
			[0.018, 0.018, 0.018, 0.018], 6, m.strap)
	sm.limb([Vector3(x - 0.16, 0.92, -0.56), Vector3(x, 0.94, -0.68), Vector3(x + 0.16, 0.92, -0.56)], [0.02, 0.02, 0.02], 6, m.strap)
	# Neck and head, a little forward of the shoulders
	sm.limb([Vector3(x, 1.43, -0.55), Vector3(x, 1.56, -0.57)], [0.052, 0.048], 12, m[skin])
	sm.blob(Vector3(x, 1.645, -0.585), Vector3(0.082, 0.108, 0.098), 20, func(_p, _n): return m[skin])
	sm.limb([Vector3(x, 1.635, -0.68), Vector3(x, 1.605, -0.695)], [0.016, 0.019], 8, m[skin])     # nose
	sm.limb([Vector3(x - 0.03, 1.565, -0.672), Vector3(x + 0.03, 1.565, -0.672)], [0.007, 0.007], 6, m.black)   # mouth
	# Flight helmet (HGU-56/P): a rounded shell with the face open, its visor down, a boom mic
	var hc := Vector3(x, 1.675, -0.57)
	sm.blob(hc, Vector3(0.122, 0.128, 0.132), 24, func(p: Vector3, n: Vector3) -> int:
		if n.z < -0.25 and p.y < hc.y + 0.035 and p.y > hc.y - 0.15:
			return -1                                   # face opening
		if p.y < hc.y - 0.095 and n.z < 0.3:
			return -1                                   # open underneath, round the jaw
		return m.helmet)
	sm.blob(hc + Vector3(0, 0.005, -0.004), Vector3(0.128, 0.132, 0.138), 24, func(p: Vector3, n: Vector3) -> int:
		if n.z < -0.35 and p.y > hc.y - 0.06 and p.y < hc.y + 0.045:
			return m.visor
		return -1)
	sm.loft([[-0.70, 0.005, 0.005, hc.y + 0.075, x], [-0.69, 0.09, 0.03, hc.y + 0.078, x], [-0.62, 0.10, 0.035, hc.y + 0.085, x], [-0.55, 0.005, 0.005, hc.y + 0.10, x]], 6, 12,
		func(_p, _n): return m.helmet)                 # visor housing
	sm.loft([[-0.715, 0.02, 0.02, hc.y + 0.06, x], [-0.705, 0.035, 0.03, hc.y + 0.06, x], [-0.69, 0.035, 0.03, hc.y + 0.06, x]], 3, 8,
		func(_p, _n): return m.metal, Transform3D.IDENTITY, 6.0)        # NVG mount
	sm.limb([Vector3(x + sx * 0.115, 1.63, -0.56), Vector3(x + sx * 0.10, 1.58, -0.63), Vector3(x + sx * 0.03, 1.565, -0.685)],
		[0.008, 0.008, 0.008], 6, m.black)
	sm.blob(Vector3(x + sx * 0.025, 1.565, -0.69), Vector3(0.014, 0.012, 0.014), 8, func(_p, _n): return m.black)
	# Arms: right hand on the cyclic between the knees, left on the collective by the seat
	var r_sh := Vector3(x + 0.18, 1.37, -0.56)
	var r_el := Vector3(x + 0.20, 1.12, -0.63)
	var r_wr := Vector3(x + 0.05, 1.03, -0.82)
	var l_sh := Vector3(x - 0.18, 1.37, -0.56)
	var l_el := Vector3(x - 0.24, 1.12, -0.57)
	var l_wr := Vector3(x - 0.26, 0.99, -0.73)
	for arm in [[r_sh, r_el, r_wr], [l_sh, l_el, l_wr]]:
		sm.limb([arm[0], arm[1], arm[2]], [0.058, 0.048, 0.038], 12, m.suit)
		var hand: Vector3 = arm[2] + ((arm[2] as Vector3) - (arm[1] as Vector3)).normalized() * 0.06
		sm.blob(hand, Vector3(0.042, 0.05, 0.048), 12, func(_p, _n): return m.black)
	# The controls in his hands
	sm.limb([Vector3(x + 0.05, 0.50, -0.84), Vector3(x + 0.05, 0.80, -0.86), Vector3(x + 0.05, 1.02, -0.88)], [0.016, 0.016, 0.022], 8, m.black)
	sm.limb([Vector3(x - 0.27, 0.80, -0.42), Vector3(x - 0.27, 0.92, -0.62), Vector3(x - 0.27, 0.96, -0.79)], [0.016, 0.016, 0.02], 8, m.black)
	# Legs: thighs on the seat, knees up, shins down to the pedals, boots on them
	for lx in [-0.085, 0.085]:
		sm.limb([Vector3(x + lx, 0.90, -0.52), Vector3(x + lx * 1.15, 0.93, -0.80), Vector3(x + lx * 1.3, 0.96, -0.98)],
			[0.082, 0.07, 0.058], 14, m.suit)
		sm.limb([Vector3(x + lx * 1.3, 0.95, -0.99), Vector3(x + lx * 1.35, 0.74, -1.08), Vector3(x + lx * 1.4, 0.58, -1.14)],
			[0.056, 0.048, 0.044], 12, m.suit)
		sm.limb([Vector3(x + lx * 1.4, 0.56, -1.12), Vector3(x + lx * 1.4, 0.52, -1.20), Vector3(x + lx * 1.4, 0.52, -1.30)],
			[0.05, 0.045, 0.04], 12, m.boot)
		sm.loft([[-1.33, 0.06, 0.012, 0.50, x + lx * 1.4], [-1.18, 0.06, 0.012, 0.50, x + lx * 1.4]], 2, 8,
			func(_p, _n): return m.metal, Transform3D.IDENTITY, 6.0)     # pedal


func _prim_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


# --- Red Army tank -----------------------------------------------------------

static func red_tank() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "RedTank"
	v._lp(v, "redtank_hull", func(lp: LowPoly):
		v._tracks(lp, 1.50, 6.60, 0.62, 0.90, 6, 0.33)
		lp.box(Vector3(3.60, 0.07, 6.80), Vector3(0, 0.95, 0), TANK_RED_DARK)                 # fenders
		# Hull with a sharply sloped glacis
		lp.hull([[-3.55, 2.30, 0.30, 0.92, 0.1], [-2.55, 2.40, 0.86, 1.05, 0.08], [3.25, 2.40, 0.80, 1.05, 0.08], [3.40, 2.30, 0.66, 1.03, 0.15]], TANK_RED, Transform3D.IDENTITY, TANK_RED_LIGHT)
		# Fuel drums on the back deck, lying across
		for x in [-0.70, 0.70]:
			lp.cyl(0.22, 0.90, 8, T(Vector3(x, 1.68, 3.05), TO_X), TANK_RED_DARK)
		# Driver's hatch and headlights
		lp.cyl(0.28, 0.08, 8, T(Vector3(0, 1.48, -2.45), TO_Y), TANK_RED_DARK)
		for x in [-0.95, 0.95]:
			lp.box(Vector3(0.16, 0.12, 0.10), Vector3(x, 1.25, -3.05), LIGHT))
	# Turret: a low dome, long gun
	var t := v._pivot(Vector3(0, 1.45, 0.30))
	v.turret = t
	v._lp(t, "redtank_turret", func(lp: LowPoly):
		lp.hull([[-1.40, 1.30, 0.30, 0.25, 0.8], [-0.95, 2.20, 0.68, 0.36, 0.55], [0.85, 2.30, 0.70, 0.36, 0.5], [1.30, 1.70, 0.50, 0.32, 0.6]], TANK_RED, Transform3D.IDENTITY, TANK_RED_LIGHT)
		lp.box(Vector3(0.50, 0.40, 0.30), Vector3(0, 0.40, -1.35), TANK_RED_DARK, 0.06)        # mantlet
		lp.cyl(0.10, 4.60, 8, T(Vector3(0, 0.40, -3.50)), TANK_RED_DARK)                       # gun
		lp.cyl(0.17, 0.55, 8, T(Vector3(0, 0.40, -2.60)), TANK_RED_DARK)                       # fume extractor
		lp.cyl(0.12, 0.25, 8, T(Vector3(0, 0.40, -5.70)), TANK_RED_DARK)                       # muzzle
		lp.cyl(0.30, 0.25, 8, T(Vector3(0.55, 0.78, 0.30), TO_Y), TANK_RED_DARK)               # cupola
		lp.cyl(0.035, 0.70, 6, T(Vector3(0.55, 1.00, -0.10)), STEEL)                          # roof MG
		lp.box(Vector3(0.60, 0.25, 0.40), Vector3(0, 0.45, 1.45), TANK_RED_DARK, 0.05)          # stowage box
		for x in [-1.13, 1.13]:
			lp.box(Vector3(0.04, 0.30, 0.30), Vector3(x, 0.38, 0.10), RED_STAR, 0.0, T(Vector3.ZERO, Basis(Vector3.FORWARD, -signf(x) * 0.25))))
	var m := Node3D.new()
	m.position = Vector3(0, 0.40, -5.85)
	t.add_child(m)
	v.muzzle = m
	return v


static func red_aa() -> VehicleModel:
	## Tracked anti-air vehicle (ZSU-23-4 style): big flat turret, four short cannons, radar dish
	var v := VehicleModel.new()
	v.name = "RedAA"
	v._lp(v, "redaa_hull", func(lp: LowPoly):
		v._tracks(lp, 1.40, 6.20, 0.58, 0.85, 6, 0.31)
		lp.box(Vector3(3.30, 0.07, 6.40), Vector3(0, 0.88, 0), TANK_RED_DARK)
		lp.hull([[-3.15, 2.20, 0.40, 0.92, 0.12], [-2.50, 2.30, 0.78, 1.00, 0.1], [3.05, 2.30, 0.76, 1.00, 0.1], [3.15, 2.20, 0.66, 0.98, 0.15]], TANK_RED, Transform3D.IDENTITY, TANK_RED_LIGHT))
	var t := v._pivot(Vector3(0, 1.40, 0.40))
	v.turret = t
	v._lp(t, "redaa_turret", func(lp: LowPoly):
		# Big boxy turret with bevelled edges and a sloped front
		lp.hull([[-1.45, 2.50, 0.55, 0.30, 0.12], [-1.05, 2.70, 1.05, 0.52, 0.1], [1.45, 2.70, 1.05, 0.52, 0.1]], TANK_RED, Transform3D.IDENTITY, TANK_RED_LIGHT)
		# Radar dish on a mast at the back
		lp.cyl(0.06, 0.70, 6, T(Vector3(0, 1.40, 1.10), TO_Y), STEEL)
		lp.hull([[-0.06, 1.30, 0.70, 2.00, 0.6], [0.10, 1.10, 0.55, 2.00, 0.6]], TANK_RED_DARK, T(Vector3(0, 0, 1.10)))
		for x in [-1.36, 1.36]:
			lp.box(Vector3(0.04, 0.30, 0.30), Vector3(x, 0.55, 0.30), RED_STAR))
	# Four cannons on an elevating cradle at the front
	var c := Node3D.new()
	c.position = Vector3(0, 0.75, -1.30)
	t.add_child(c)
	v.cradle = c
	v._lp(c, "redaa_guns", func(lp: LowPoly):
		lp.box(Vector3(1.40, 0.40, 0.40), Vector3(0, 0.13, 0.05), TANK_RED_DARK, 0.06)
		for x in [-0.55, 0.55]:
			for y in [0.0, 0.26]:
				lp.cyl(0.045, 2.20, 6, T(Vector3(x, y, -1.10)), STEEL)
				lp.cyl(0.07, 0.25, 6, T(Vector3(x, y, -2.15)), STEEL_LIGHT))
	var m := Node3D.new()
	m.position = Vector3(0, 0.14, -2.30)
	c.add_child(m)
	v.muzzle = m
	return v


func _tracks(lp: LowPoly, x_off: float, length: float, width: float, height: float, wheels: int, wheel_r: float) -> void:
	## Both track runs (rounded at the ends) with the road wheels showing on their outsides
	for x in [-x_off, x_off]:
		var h := length * 0.5
		lp.hull([[-h, width, height * 0.35, height * 0.62, 0.3, x], [-h + 0.45, width, height, height * 0.5, 0.3, x],
			[h - 0.45, width, height, height * 0.5, 0.3, x], [h, width, height * 0.45, height * 0.58, 0.3, x]], TRACK)
		for k in wheels:
			var z := -h + 0.9 + k * (length - 1.8) / maxf(1.0, wheels - 1)
			lp.cyl(wheel_r, 0.06, 16, T(Vector3(x + signf(x) * (width * 0.5 + 0.03), wheel_r + 0.05, z), TO_X), HUB)


# --- A-10 Thunderbolt II -----------------------------------------------------

static func a10() -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "A10"
	v._lp(v, "a10_body", func(lp: LowPoly):
		# Fuselage: pointed nose, slim tail
		lp.hull([[-7.30, 0.45, 0.45, 1.85, 1.0], [-6.60, 1.10, 1.15, 1.95, 0.7], [-5.00, 1.40, 1.50, 2.00, 0.6],
			[3.50, 1.40, 1.50, 2.05, 0.6], [6.50, 0.80, 0.90, 2.30, 0.6], [7.70, 0.40, 0.50, 2.45, 0.6]], JET_GRAY, Transform3D.IDENTITY, JET_LIGHT)
		lp.cyl(0.07, 1.10, 6, T(Vector3(0, 1.62, -7.55)), STEEL)                              # GAU-8 barrel
		for z in [-2.0, 1.8]:
			lp.hull([[z - 0.04, 1.44, 1.54, 2.01, 0.6], [z + 0.04, 1.44, 1.54, 2.01, 0.6]], JET_DARK, Transform3D.IDENTITY, JET_GRAY)
		# Bubble canopy
		lp.hull([[-4.95, 0.45, 0.25, 2.72, 0.8], [-4.45, 0.85, 0.58, 2.88, 0.7], [-3.35, 0.85, 0.58, 2.88, 0.7], [-2.85, 0.45, 0.30, 2.80, 0.8]], GLASS, Transform3D.IDENTITY, GLASS_LIGHT)
		# Straight wing, tapering to the tips (built along the span)
		lp.hull([[-8.75, 1.80, 0.16, 1.60, 0.5, -0.40], [-1.20, 2.70, 0.30, 1.60, 0.5, -0.40], [1.20, 2.70, 0.30, 1.60, 0.5, -0.40], [8.75, 1.80, 0.16, 1.60, 0.5, -0.40]], JET_GRAY, T(Vector3.ZERO, TO_X), JET_LIGHT)
		for x in [-8.35, 8.35]:
			lp.box(Vector3(0.80, 0.20, 1.80), Vector3(x, 1.62, 0.40), JET_DARK, 0.06)       # drooped wingtips
		# Stores under the wings
		for x in [-5.6, -3.6, 3.6, 5.6]:
			lp.hull([[-0.80, 0.10, 0.10, 0.0, 1.0], [-0.50, 0.30, 0.30, 0.0, 1.0], [0.80, 0.30, 0.30, 0.0, 1.0], [1.00, 0.20, 0.20, 0.0, 1.0]], OD_DARK, T(Vector3(x, 1.28, 0.20)))
		# Engines high on the back, on pylons
		for x in [-1.35, 1.35]:
			lp.hull([[1.85, 1.05, 1.05, 3.10, 1.0, x], [2.10, 1.15, 1.15, 3.10, 1.0, x], [4.50, 1.10, 1.10, 3.10, 1.0, x], [4.95, 0.85, 0.85, 3.10, 1.0, x]], JET_LIGHT)
			lp.cyl(0.42, 0.10, 8, T(Vector3(x, 3.10, 1.80)), INTERIOR)
			lp.cyl(0.36, 0.10, 8, T(Vector3(x, 3.10, 4.98)), INTERIOR)
			lp.box(Vector3(0.22, 0.55, 1.10), Vector3(x * 0.70, 2.68, 3.40), JET_DARK, 0.04)
		# Tailplane and twin fins
		lp.hull([[-2.90, 1.20, 0.12, 2.45, 0.5, -6.90], [-0.4, 1.60, 0.16, 2.45, 0.5, -6.90], [0.4, 1.60, 0.16, 2.45, 0.5, -6.90], [2.90, 1.20, 0.12, 2.45, 0.5, -6.90]], JET_GRAY, T(Vector3.ZERO, TO_X), JET_LIGHT)
		for x in [-2.85, 2.85]:
			lp.hull([[6.25, 0.14, 1.40, 2.95, 0.4, x], [7.10, 0.16, 2.30, 3.30, 0.3, x], [7.75, 0.14, 2.10, 3.40, 0.4, x]], JET_GRAY))
	# Landing gear
	var g := Node3D.new()
	v.add_child(g)
	v.gear = g
	v._lp(g, "a10_gear", func(lp: LowPoly):
		for p in [Vector3(0, 0.0, -4.6), Vector3(-1.7, 0.0, 0.9), Vector3(1.7, 0.0, 0.9)]:
			lp.cyl(0.06, 1.10, 6, T(p + Vector3(0, 0.80, 0), TO_Y), STEEL)
			lp.tyre(0.32, 0.22, 16, T(p + Vector3(0, 0.32, 0), TO_X), TIRE))
	var m := Node3D.new()
	m.position = Vector3(0, 1.60, -8.1)
	v.add_child(m)
	v.muzzle = m
	return v


# --- Damage -------------------------------------------------------------------

func burn() -> void:
	## A destroyed vehicle: everything goes charred
	var dark := _mat(Color(0.10, 0.09, 0.08))
	for n in find_children("*", "MeshInstance3D", true, false):
		if not n.has_meta("outline"):
			(n as MeshInstance3D).material_override = dark
	spinners.clear()


# --- M777 howitzer ----------------------------------------------------------

static func m777(elevation_deg := 28.0) -> VehicleModel:
	var v := VehicleModel.new()
	v.name = "M777"
	for x in [-1.25, 1.25]:
		v._lp_wheel(v, Vector3(x, 0.55, 0.30), 0.55, 0.35)
	v._lp(v, "m777_carriage", func(lp: LowPoly):
		# Carriage and saddle
		lp.hull([[-0.55, 1.40, 0.35, 0.80, 0.3], [-0.20, 1.60, 0.50, 0.85, 0.2], [0.65, 1.60, 0.50, 0.85, 0.2], [0.90, 1.30, 0.40, 0.85, 0.3]], OD, Transform3D.IDENTITY, OD_LIGHT)
		lp.box(Vector3(1.20, 0.35, 0.80), Vector3(0, 1.20, 0.30), OD_DARK, 0.08)
		# Front stabiliser arms with pads
		for side in [-1.0, 1.0]:
			lp.hull([[-0.70, 0.16, 0.14, 0.0, 0.3], [0.70, 0.24, 0.20, 0.0, 0.3]], OD, T(Vector3(0.55 * side, 0.30, -0.95), Basis(Vector3.UP, deg_to_rad(-32 * side))))
			lp.box(Vector3(0.55, 0.08, 0.55), Vector3(0.92 * side, 0.05, -1.55), STEEL, 0.03)
		# Split trail legs, tapering down to the spades
		for side in [-1.0, 1.0]:
			var spread := Basis(Vector3.UP, deg_to_rad(22 * side)) * Basis(Vector3.RIGHT, deg_to_rad(8))
			lp.hull([[-1.85, 0.34, 0.34, 0.0, 0.3], [1.85, 0.24, 0.22, 0.0, 0.3]], OD, T(Vector3(0.75 * side, 0.45, 2.55), spread), OD_LIGHT)
			lp.box(Vector3(0.65, 0.60, 0.10), Vector3.ZERO, STEEL, 0.03, T(Vector3(1.40 * side, 0.28, 4.25), Basis(Vector3.UP, deg_to_rad(22 * side))))
		# Ammo crate between the trail legs, a couple of rounds on top
		lp.box(Vector3(0.80, 0.40, 0.50), Vector3(0, 0.20, 2.25), OD_DARK, 0.04)
		for x in [-0.18, 0.0, 0.18]:
			lp.cyl(0.07, 0.55, 6, T(Vector3(x, 0.47, 2.25)), Color(0.55, 0.50, 0.28))
		# Sight and crew seat
		lp.box(Vector3(0.25, 0.30, 0.25), Vector3(-0.75, 1.35, 0.10), STEEL, 0.04)
		lp.box(Vector3(0.40, 0.08, 0.40), Vector3(0.75, 1.15, 0.55), OD_DARK, 0.02))
	# Traverse (left/right), cradle (elevation) and the recoiling barrel group
	var trav := v._pivot(Vector3(0, 1.40, 0.30))
	v.traverse = trav
	var cradle := Node3D.new()
	trav.add_child(cradle)
	cradle.rotation.x = deg_to_rad(elevation_deg)
	v.cradle = cradle
	v._lp(cradle, "m777_cradle", func(lp: LowPoly):
		lp.hull([[-1.70, 0.45, 0.38, 0.0, 0.3], [0.60, 0.58, 0.48, 0.0, 0.25]], OD_LIGHT, Transform3D.IDENTITY, OD_PALE)
		for x in [-0.20, 0.20]:
			lp.cyl(0.07, 1.90, 8, T(Vector3(x, 0.30, -0.70)), STEEL))
	var rec := Node3D.new()
	cradle.add_child(rec)
	v.recoil = rec
	v._lp(rec, "m777_barrel", func(lp: LowPoly):
		lp.box(Vector3(0.50, 0.50, 0.70), Vector3(0, 0, 0.85), STEEL, 0.08)
		lp.cyl(0.11, 5.20, 8, T(Vector3(0, 0.02, -3.30)), OD_DARK, 0.09)
		lp.hull([[-0.28, 0.34, 0.26, 0.0, 0.3], [0.28, 0.34, 0.26, 0.0, 0.3]], STEEL, T(Vector3(0, 0.02, -6.00))))
	return v


# --- Helpers ----------------------------------------------------------------

func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func _lp(parent: Node3D, key: String, build: Callable, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	## A low-poly piece (built once per key and shared), with its outline
	if not _meshes.has(key):
		var lp := LowPoly.new()
		build.call(lp)
		_meshes[key] = lp.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = UnitLook.vehicle_material()
	mi.transform = xf
	parent.add_child(mi)
	UnitLook.add_outline(mi, false, false)
	return mi


func _lp_wheel(parent: Node3D, pos: Vector3, radius: float, width: float) -> void:
	## A round tyre (16 sides) with a rim and a hub
	var key := "wheel_%.2f_%.2f" % [radius, width]
	_lp(parent, key, func(lp: LowPoly):
		lp.tyre(radius, width, 16, T(Vector3.ZERO, TO_X), TIRE)
		lp.cyl(radius * 0.55, width + 0.03, 12, T(Vector3.ZERO, TO_X), HUB)
		lp.cyl(radius * 0.20, width + 0.10, 8, T(Vector3.ZERO, TO_X), STEEL_LIGHT), T(pos))


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.transform = Transform3D(rot, pos)
	parent.add_child(mi)


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		_mats[key] = Level.make_material(c)
	return _mats[key]
