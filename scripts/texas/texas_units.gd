class_name TexasUnits
extends RefCounted
## Every kind of unit in Taking Back Texas, for both sides (Red mirrors you: the same types, in
## its own colours). Numbers are per unit at full strength; the simulation scales them by how
## much of the unit is left.
##
## Categories (what a weapon is aimed at): infantry, soft vehicles, armour, helicopters, jets,
## ships. Each type has a damage rate and a range against each category; 0 means it can't
## engage that category at all.

enum Cat {INFANTRY, SOFT, ARMOR, HELI, JET, SHIP}
enum Move {GROUND, AIR, SEA, HOVER}
enum Deck {NONE, AMPHIB, CARRIER, AIRFIELD}

const CAT_COUNT := 6

# id, name (yours), name (Red), category, how it moves, speed (game m/s = real m/s),
# toughness, fuel endurance (s of use), damage per s vs each category, range (game m) vs each,
# squads it carries, vehicle slots it takes up / carries, delivery cost, where it's delivered,
# refit time (s)
const TYPES := [
	{"id": "rifle", "name": "Rifle squad", "red": "Rifle squad", "cat": Cat.INFANTRY, "move": Move.GROUND,
		"speed": 1.6, "hp": 1.0, "fuel": 1.0e9, "dps": [0.010, 0.006, 0.002, 0.003, 0.0, 0.0],
		"range": [300, 300, 250, 300, 0, 0], "seats": 0, "size": 0, "cost": 4, "deck": Deck.AMPHIB},
	{"id": "humvee", "name": "Humvee", "red": "Scout car", "cat": Cat.SOFT, "move": Move.GROUND,
		"speed": 24.0, "hp": 1.0, "fuel": 7200.0, "dps": [0.012, 0.008, 0.002, 0.004, 0.0, 0.0],
		"range": [600, 600, 400, 600, 0, 0], "seats": 1, "size": 1, "cost": 4, "deck": Deck.AMPHIB},
	{"id": "stryker", "name": "Stryker", "red": "Wheeled APC", "cat": Cat.SOFT, "move": Move.GROUND,
		"speed": 22.0, "hp": 1.6, "fuel": 9000.0, "dps": [0.014, 0.010, 0.004, 0.004, 0.0, 0.0],
		"range": [700, 700, 500, 700, 0, 0], "seats": 2, "size": 2, "cost": 8, "deck": Deck.AMPHIB},
	{"id": "bradley", "name": "Bradley", "red": "Infantry fighting vehicle", "cat": Cat.ARMOR, "move": Move.GROUND,
		"speed": 16.0, "hp": 2.5, "fuel": 9000.0, "dps": [0.020, 0.030, 0.015, 0.004, 0.0, 0.0],
		"range": [1200, 1200, 1200, 1000, 0, 0], "seats": 1, "size": 2, "cost": 12, "deck": Deck.AMPHIB},
	{"id": "lmtv", "name": "LMTV truck", "red": "Truck", "cat": Cat.SOFT, "move": Move.GROUND,
		"speed": 24.0, "hp": 0.8, "fuel": 9000.0, "dps": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"range": [0, 0, 0, 0, 0, 0], "seats": 4, "size": 2, "cost": 4, "deck": Deck.AMPHIB},
	{"id": "black_hawk", "name": "Black Hawk", "red": "Transport helicopter", "cat": Cat.HELI, "move": Move.AIR,
		"speed": 70.0, "hp": 1.2, "fuel": 8300.0, "dps": [0.006, 0.003, 0.0, 0.0, 0.0, 0.0],
		"range": [400, 400, 0, 0, 0, 0], "seats": 2, "size": 0, "cost": 10, "deck": Deck.CARRIER, "refit": 900.0},
	{"id": "chinook", "name": "Chinook", "red": "Heavy helicopter", "cat": Cat.HELI, "move": Move.AIR,
		"speed": 75.0, "hp": 1.8, "fuel": 8000.0, "dps": [0.004, 0.002, 0.0, 0.0, 0.0, 0.0],
		"range": [400, 400, 0, 0, 0, 0], "seats": 8, "size": 0, "cost": 14, "deck": Deck.CARRIER, "refit": 1200.0},
	{"id": "little_bird", "name": "Little Bird", "red": "Light helicopter", "cat": Cat.HELI, "move": Move.AIR,
		"speed": 60.0, "hp": 0.7, "fuel": 7000.0, "dps": [0.008, 0.006, 0.001, 0.0, 0.0, 0.0],
		"range": [500, 500, 300, 0, 0, 0], "seats": 1, "size": 0, "cost": 6, "deck": Deck.CARRIER, "refit": 600.0},
	{"id": "apache", "name": "Apache", "red": "Attack helicopter", "cat": Cat.HELI, "move": Move.AIR,
		"speed": 75.0, "hp": 2.0, "fuel": 7200.0, "dps": [0.030, 0.045, 0.040, 0.010, 0.0, 0.0],
		"range": [1500, 2500, 2500, 1500, 0, 0], "seats": 0, "size": 0, "cost": 16, "deck": Deck.CARRIER, "refit": 1200.0},
	{"id": "hornet", "name": "Super Hornet", "red": "Fighter jet", "cat": Cat.JET, "move": Move.AIR,
		"speed": 220.0, "hp": 1.2, "fuel": 5000.0, "dps": [0.015, 0.025, 0.025, 0.020, 0.060, 0.040],
		"range": [1500, 1500, 1500, 2500, 2800, 3000], "seats": 0, "size": 0, "cost": 20, "deck": Deck.CARRIER, "refit": 1500.0},
	{"id": "a10", "name": "A-10", "red": "Ground-attack jet", "cat": Cat.JET, "move": Move.AIR,
		"speed": 160.0, "hp": 2.0, "fuel": 6000.0, "dps": [0.040, 0.060, 0.060, 0.010, 0.0, 0.0],
		"range": [1500, 1500, 1500, 800, 0, 0], "seats": 0, "size": 0, "cost": 18, "deck": Deck.AIRFIELD, "refit": 1200.0},
	{"id": "lcac", "name": "LCAC hovercraft", "red": "Hovercraft", "cat": Cat.SOFT, "move": Move.HOVER,
		"speed": 20.0, "hp": 1.0, "fuel": 1.0e9, "dps": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"range": [0, 0, 0, 0, 0, 0], "seats": 4, "size": 0, "slots": 4, "cost": 0, "deck": Deck.AMPHIB},
	{"id": "carrier", "name": "Aircraft carrier", "red": "Carrier", "cat": Cat.SHIP, "move": Move.SEA,
		"speed": 15.0, "hp": 60.0, "fuel": 1.0e9, "dps": [0.0, 0.0, 0.0, 0.08, 0.08, 0.0],
		"range": [0, 0, 0, 6000, 6000, 0], "seats": 0, "size": 0, "cost": 0, "deck": Deck.NONE},
	{"id": "amphib", "name": "Amphibious assault ship", "red": "Assault ship", "cat": Cat.SHIP, "move": Move.SEA,
		"speed": 11.0, "hp": 40.0, "fuel": 1.0e9, "dps": [0.0, 0.0, 0.0, 0.06, 0.06, 0.0],
		"range": [0, 0, 0, 6000, 6000, 0], "seats": 0, "size": 0, "cost": 0, "deck": Deck.NONE},
	{"id": "destroyer", "name": "Destroyer", "red": "Destroyer", "cat": Cat.SHIP, "move": Move.SEA,
		"speed": 15.0, "hp": 25.0, "fuel": 1.0e9, "dps": [0.020, 0.030, 0.020, 0.10, 0.12, 0.0],
		"range": [8000, 8000, 8000, 7000, 7000, 0], "seats": 0, "size": 0, "cost": 0, "deck": Deck.NONE},
	{"id": "cruiser", "name": "Cruiser", "red": "Cruiser", "cat": Cat.SHIP, "move": Move.SEA,
		"speed": 15.0, "hp": 30.0, "fuel": 1.0e9, "dps": [0.030, 0.040, 0.030, 0.12, 0.14, 0.0],
		"range": [8000, 8000, 8000, 7000, 7000, 0], "seats": 0, "size": 0, "cost": 0, "deck": Deck.NONE},
	{"id": "tank", "name": "Tank", "red": "Tank", "cat": Cat.ARMOR, "move": Move.GROUND,
		"speed": 14.0, "hp": 3.0, "fuel": 8000.0, "dps": [0.020, 0.030, 0.025, 0.002, 0.0, 0.0],
		"range": [1200, 1200, 1200, 600, 0, 0], "seats": 0, "size": 4, "cost": 18, "deck": Deck.AMPHIB},
	{"id": "aa", "name": "Mobile air defence", "red": "Mobile air defence", "cat": Cat.SOFT, "move": Move.GROUND,
		"speed": 14.0, "hp": 1.2, "fuel": 8000.0, "dps": [0.004, 0.004, 0.0, 0.06, 0.05, 0.0],
		"range": [400, 400, 0, 2500, 2500, 0], "seats": 0, "size": 2, "cost": 10, "deck": Deck.AMPHIB},
]

# Quick lookups (filled once)
static var _ready := false
static var speed := PackedFloat32Array()
static var hp := PackedFloat32Array()
static var endurance := PackedFloat32Array()
static var cat := PackedByteArray()
static var move := PackedByteArray()
static var dps := PackedFloat32Array()        # type * 6 + category
static var rng := PackedFloat32Array()        # type * 6 + category
static var max_range := PackedFloat32Array()
static var seats := PackedInt32Array()
static var size := PackedInt32Array()
static var slots := PackedInt32Array()
static var refit := PackedFloat32Array()
static var foot := PackedFloat32Array()      # how much room it takes (radius, game m)
static var turn := PackedFloat32Array()      # fastest turn, radians a second (0: turns on the spot)
static var max_bank := PackedFloat32Array()  # how far it leans into a turn, radians
# Degrees a second: jets bank round in wide arcs, helicopters turn quickly but slow down to do
# it, ships come about slowly. Ground units follow the road and turn with it.
const TURN := {"hornet": 9.0, "a10": 11.0, "black_hawk": 30.0, "chinook": 22.0, "little_bird": 40.0,
	"apache": 32.0, "carrier": 1.4, "amphib": 1.7, "destroyer": 2.8, "cruiser": 2.6, "lcac": 9.0}
const BANK := {"hornet": 60.0, "a10": 50.0, "black_hawk": 25.0, "chinook": 18.0, "little_bird": 30.0, "apache": 28.0}
const FOOT := {"rifle": 6.0, "humvee": 5.0, "stryker": 7.0, "bradley": 7.0, "lmtv": 6.0, "black_hawk": 12.0,
	"chinook": 16.0, "little_bird": 6.0, "apache": 10.0, "hornet": 0.0, "a10": 0.0, "lcac": 15.0,
	"carrier": 200.0, "amphib": 160.0, "destroyer": 90.0, "cruiser": 100.0, "tank": 7.0, "aa": 6.0}
static var _by_id := {}


static func setup() -> void:
	if _ready:
		return
	for t in TYPES.size():
		var d: Dictionary = TYPES[t]
		_by_id[d.id] = t
		speed.append(d.speed)
		hp.append(d.hp)
		endurance.append(d.fuel)
		cat.append(d.cat)
		move.append(d.move)
		var mr := 0.0
		for c in CAT_COUNT:
			dps.append(d.dps[c])
			rng.append(d.range[c])
			if d.dps[c] > 0.0:
				mr = maxf(mr, d.range[c])
		max_range.append(mr)
		seats.append(d.seats)
		size.append(d.size)
		slots.append(d.get("slots", 0))
		refit.append(d.get("refit", 900.0))
		foot.append(FOOT.get(d.id, 6.0))
		turn.append(deg_to_rad(TURN.get(d.id, 0.0)))
		max_bank.append(deg_to_rad(BANK.get(d.id, 0.0)))
	_ready = true


static func id(name: String) -> int:
	setup()
	return _by_id.get(name, -1)


static func label(t: int, side: int) -> String:
	return TYPES[t].name if side == 0 else TYPES[t].red


static func is_air(t: int) -> bool:
	return move[t] == Move.AIR


static func is_ship(t: int) -> bool:
	return move[t] == Move.SEA


static func is_ground(t: int) -> bool:
	return move[t] == Move.GROUND


static func default_type(kind: int, side: int) -> int:
	## The Phase 2 test world's kinds as types
	setup()
	match kind:
		0:
			return id("rifle")
		1:
			return id("humvee") if side == 0 else id("stryker")
		2:
			return id("bradley") if side == 0 else id("tank")
		3:
			return id("black_hawk") if side == 0 else id("apache")
		4:
			return id("a10") if side == 0 else id("hornet")
	return id("rifle")
