class_name TexasGeo
extends RefCounted
## The shape of Texas for the 1:3 world: the projection from latitude/longitude to game
## metres, the state outline and Gulf coast, the cities, and (until the map builder brings in
## real elevation data) a stand-in terrain made from known heights around the state.
##
## Game coordinates: x east, z south (north is -z), 1 game metre = 3 real metres. The centre
## of the state is (0, 0). Positions are kept as 64-bit floats in the simulation; the scene
## shifts its origin so the 32-bit render positions near the camera stay precise.

const SCALE := 3.0                 # real metres per game metre
const VERTICAL := 1.0 / 3.0        # terrain heights are scaled like distances, so slopes stay real
const LAT0 := 31.0
const LON0 := -99.9
const M_PER_DEG_LAT := 110950.0
const M_PER_DEG_LON := 95420.0     # at 31 degrees north

# The state border, clockwise from the north-west corner of the Panhandle (lat, lon)
const OUTLINE := [
	[36.50, -103.04], [36.50, -100.00], [34.56, -100.00], [34.42, -99.70], [34.20, -99.20], [34.10, -98.60],
	[33.90, -98.00], [33.83, -97.40], [33.73, -96.60], [33.86, -96.10], [33.83, -95.50], [33.64, -94.90],
	[33.55, -94.04], [31.99, -94.04], [31.50, -93.82], [31.00, -93.55], [30.40, -93.70], [30.05, -93.72],
	[29.70, -93.84],
	# Gulf coast, Sabine Pass to the mouth of the Rio Grande
	[29.55, -94.35], [29.30, -94.80], [29.05, -95.10], [28.95, -95.36], [28.75, -95.70], [28.60, -96.00],
	[28.43, -96.40], [28.20, -96.75], [28.00, -97.05], [27.80, -97.25], [27.60, -97.30], [27.20, -97.38],
	[26.80, -97.37], [26.55, -97.30], [26.20, -97.18], [25.96, -97.15],
	# The Rio Grande, up to El Paso
	[25.90, -97.50], [26.05, -97.80], [26.10, -98.20], [26.40, -98.95], [26.80, -99.25], [27.50, -99.50],
	[28.00, -99.95], [28.70, -100.50], [29.35, -100.90], [29.77, -101.40], [29.80, -101.80], [29.60, -102.40],
	[29.20, -102.80], [28.97, -103.20], [29.20, -103.70], [29.55, -104.40], [30.10, -104.70], [30.60, -104.95],
	[31.00, -105.50], [31.40, -106.10], [31.75, -106.45], [32.00, -106.62],
	# New Mexico line
	[32.00, -103.06],
]

# name, lat, lon, size tier (1 town .. 5 metro), elevation in real metres
const CITIES := [
	["Houston", 29.76, -95.37, 5, 15], ["San Antonio", 29.42, -98.49, 5, 200], ["Dallas", 32.78, -96.80, 5, 140],
	["Fort Worth", 32.75, -97.33, 4, 200], ["Austin", 30.27, -97.74, 4, 150], ["El Paso", 31.76, -106.49, 4, 1140],
	["Arlington", 32.74, -97.11, 3, 180], ["Corpus Christi", 27.80, -97.40, 3, 10], ["Plano", 33.02, -96.70, 3, 200],
	["Laredo", 27.53, -99.49, 3, 140], ["Lubbock", 33.58, -101.85, 3, 990], ["Amarillo", 35.22, -101.83, 3, 1100],
	["Brownsville", 25.90, -97.50, 3, 10], ["McAllen", 26.20, -98.23, 3, 40], ["Denton", 33.21, -97.13, 2, 190],
	["Killeen", 31.12, -97.73, 2, 260], ["Waco", 31.55, -97.15, 2, 140], ["Beaumont", 30.08, -94.10, 2, 5],
	["Midland", 32.00, -102.08, 2, 870], ["Odessa", 31.85, -102.37, 2, 890], ["Abilene", 32.45, -99.73, 2, 520],
	["San Angelo", 31.46, -100.44, 2, 560], ["Wichita Falls", 33.91, -98.49, 2, 290], ["Tyler", 32.35, -95.30, 2, 170],
	["College Station", 30.63, -96.33, 2, 100], ["Galveston", 29.30, -94.80, 2, 2], ["Victoria", 28.80, -97.00, 1, 30],
	["Longview", 32.50, -94.74, 1, 100], ["Texarkana", 33.43, -94.05, 1, 100], ["Lufkin", 31.34, -94.73, 1, 100],
	["Del Rio", 29.36, -100.90, 1, 300], ["Eagle Pass", 28.71, -100.50, 1, 240], ["Fort Stockton", 30.89, -102.88, 1, 920],
	["Pecos", 31.42, -103.49, 1, 850], ["Big Spring", 32.25, -101.48, 1, 750], ["Sweetwater", 32.47, -100.41, 1, 660],
	["Junction", 30.49, -99.77, 1, 520], ["Kerrville", 30.05, -99.14, 1, 500], ["Temple", 31.10, -97.34, 1, 210],
	["Huntsville", 30.72, -95.55, 1, 120], ["Conroe", 30.31, -95.46, 1, 70], ["Port Arthur", 29.90, -93.93, 1, 2],
	["Freeport", 28.95, -95.36, 1, 3], ["Sherman", 33.64, -96.61, 1, 230], ["Gainesville", 33.63, -97.13, 1, 220],
	["Childress", 34.43, -100.20, 1, 580], ["Dalhart", 36.06, -102.52, 1, 1220], ["Pampa", 35.54, -100.96, 1, 990],
	["Van Horn", 31.04, -104.83, 1, 1200], ["Alpine", 30.36, -103.66, 1, 1370], ["Marfa", 30.31, -104.02, 1, 1470],
	["Uvalde", 29.21, -99.79, 1, 280], ["New Braunfels", 29.70, -98.12, 1, 190], ["San Marcos", 29.88, -97.94, 1, 180],
	["Kingsville", 27.52, -97.86, 1, 20], ["Harlingen", 26.19, -97.70, 1, 12], ["Nacogdoches", 31.60, -94.66, 1, 85],
	["Palestine", 31.76, -95.63, 1, 150], ["Corsicana", 32.10, -96.47, 1, 130], ["Brownwood", 31.71, -98.99, 1, 410],
	["Stephenville", 32.22, -98.20, 1, 390], ["Weatherford", 32.76, -97.80, 1, 320], ["Bay City", 28.98, -95.97, 1, 15],
	["Columbus", 29.71, -96.54, 1, 60], ["Fredericksburg", 30.27, -98.87, 1, 520], ["Snyder", 32.72, -100.92, 1, 710],
	["Plainview", 34.18, -101.71, 1, 1030], ["Vernon", 34.15, -99.27, 1, 370], ["Paris", 33.66, -95.56, 1, 180],
	["Mount Pleasant", 33.16, -94.97, 1, 120], ["Marshall", 32.54, -94.37, 1, 110], ["Jasper", 30.92, -94.00, 1, 70],
	["Orange", 30.09, -93.74, 1, 3], ["Alice", 27.75, -98.07, 1, 60], ["Beeville", 28.40, -97.75, 1, 70],
	["Zapata", 26.91, -99.27, 1, 100], ["Rio Grande City", 26.38, -98.82, 1, 70], ["Monahans", 31.59, -102.89, 1, 800],
	["Lamesa", 32.74, -101.95, 1, 900], ["Brady", 31.13, -99.33, 1, 520], ["Sonora", 30.57, -100.64, 1, 650],
	["Ozona", 30.71, -101.20, 1, 720], ["Sanderson", 30.14, -102.39, 1, 850], ["Lampasas", 31.06, -98.18, 1, 310],
	["Brenham", 30.17, -96.40, 1, 100], ["Hillsboro", 32.01, -97.13, 1, 190], ["Cotulla", 28.44, -99.23, 1, 130],
	["George West", 28.33, -98.12, 1, 50], ["Seguin", 29.57, -97.96, 1, 160], ["Greenville", 33.14, -96.11, 1, 170],
	["Sulphur Springs", 33.14, -95.60, 1, 160], ["Decatur", 33.23, -97.59, 1, 300], ["Shamrock", 35.22, -100.25, 1, 720],
	["Carrizo Springs", 28.52, -99.86, 1, 180], ["Cisco", 32.39, -98.98, 1, 490], ["Terrell", 32.74, -96.28, 1, 160],
	["Fairfield", 31.72, -96.16, 1, 140], ["Jacksboro", 33.22, -98.16, 1, 330], ["Marble Falls", 30.58, -98.27, 1, 240],
	["Menard", 30.92, -99.79, 1, 570], ["Kent", 31.07, -104.22, 1, 1200], ["Port Lavaca", 28.62, -96.63, 1, 5],
]

# Extra height points so the west has its mountains and the coast its plain (lat, lon, metres)
const HEIGHTS := [
	[31.90, -104.86, 1900], [30.60, -103.90, 1700], [29.30, -103.30, 1100], [30.00, -104.40, 1300],
	[31.50, -105.40, 1350], [34.50, -102.50, 1150], [35.80, -101.50, 1050], [33.00, -102.80, 1050],
	[29.00, -95.00, 0], [28.20, -96.80, 0], [27.00, -97.40, 0], [29.80, -94.30, 0], [30.80, -95.00, 80],
	[32.80, -94.40, 90], [33.70, -95.00, 140], [30.60, -101.80, 750], [29.60, -101.20, 450],
]

# Interstates and main highways as lists of city names (and a few border points)
const HIGHWAYS := [
	["I-35", "Laredo", "Cotulla", "San Antonio", "New Braunfels", "San Marcos", "Austin", "Temple", "Waco", "Hillsboro", "Fort Worth", "Denton", "Gainesville", "@33.86,-97.17"],
	["I-35E", "Hillsboro", "Dallas", "Denton"],
	["I-10", "@31.80,-106.55", "El Paso", "Van Horn", "Kent", "Fort Stockton", "Ozona", "Sonora", "Junction", "Kerrville", "San Antonio", "Seguin", "Columbus", "Houston", "Beaumont", "Orange", "@30.10,-93.65"],
	["I-20", "Kent", "Pecos", "Monahans", "Odessa", "Midland", "Big Spring", "Sweetwater", "Abilene", "Cisco", "Weatherford", "Fort Worth", "Arlington", "Dallas", "Terrell", "Tyler", "Longview", "Marshall", "@32.52,-94.00"],
	["I-45", "Dallas", "Corsicana", "Fairfield", "Huntsville", "Conroe", "Houston", "Galveston"],
	["I-37", "San Antonio", "George West", "Corpus Christi"],
	["I-30", "Dallas", "Greenville", "Sulphur Springs", "Mount Pleasant", "Texarkana"],
	["I-27", "Lubbock", "Plainview", "Amarillo"],
	["I-40", "@35.18,-103.10", "Amarillo", "Shamrock", "@35.20,-99.95"],
	["US-287", "Dalhart", "Amarillo", "Childress", "Vernon", "Wichita Falls", "Decatur", "Fort Worth"],
	["US-59", "Laredo", "George West", "Victoria", "Houston", "Lufkin", "Nacogdoches", "Marshall", "Texarkana"],
	["I-69E", "Brownsville", "Harlingen", "Kingsville", "Corpus Christi", "Victoria"],
	["US-83", "Brownsville", "Harlingen", "McAllen", "Rio Grande City", "Zapata", "Laredo", "Carrizo Springs", "Uvalde", "Junction", "Menard", "Abilene"],
	["US-90", "Van Horn", "Marfa", "Alpine", "Sanderson", "Del Rio", "Uvalde", "San Antonio"],
	["US-87", "Lubbock", "Lamesa", "Big Spring", "San Angelo", "Brady", "Fredericksburg", "San Antonio"],
	["US-281", "Wichita Falls", "Jacksboro", "Stephenville", "Lampasas", "Marble Falls", "San Antonio", "George West", "Alice", "McAllen"],
	["US-290", "Austin", "Brenham", "Houston"],
	["US-290W", "Austin", "Fredericksburg", "Junction"],
	["TX-6", "Waco", "College Station", "Brenham"],
	["US-190", "Killeen", "Temple"],
	["I-14", "Killeen", "Lampasas", "Brownwood", "Abilene"],
	["US-75", "Dallas", "Plano", "Sherman"],
	["US-82", "Wichita Falls", "Gainesville", "Sherman", "Paris", "Texarkana"],
	["US-69", "Tyler", "Palestine", "Lufkin", "Jasper", "Beaumont"],
	["TX-35", "Galveston", "Freeport", "Bay City", "Port Lavaca", "Victoria"],
	["US-385", "Fort Stockton", "Alpine"],
	["US-285", "Pecos", "Fort Stockton"],
	["US-84", "Lubbock", "Snyder", "Sweetwater"],
	["US-277", "Del Rio", "Eagle Pass", "Carrizo Springs"],
	["US-287S", "Pampa", "Amarillo"],
	["US-79", "Palestine", "Huntsville"],
	["I-69", "Beeville", "George West"],
	["US-59S", "Beeville", "Victoria"],
	["US-96", "Port Arthur", "Beaumont"],
	["Kingsville-Alice", "Kingsville", "Alice"],
]

const MIN_LAT := 25.5
const MAX_LAT := 36.8
const MIN_LON := -106.9
const MAX_LON := -93.2

static var _outline_xz := PackedVector2Array()
static var built := false              # true when the map builder's real Texas is loaded
static var cities: Array = CITIES      # [name, lat, lon, tier, elevation]; real towns when built
static var _height_pts: Array = []      # [x, z, h]
static var _noise: FastNoiseLite


static func to_xz(lat: float, lon: float) -> Vector2:
	## Latitude/longitude to game metres (x east, z south)
	return Vector2((lon - LON0) * M_PER_DEG_LON / SCALE, (LAT0 - lat) * M_PER_DEG_LAT / SCALE)


static func to_latlon(x: float, z: float) -> Vector2:
	## Game metres back to (lat, lon)
	return Vector2(LAT0 - z * SCALE / M_PER_DEG_LAT, LON0 + x * SCALE / M_PER_DEG_LON)


static func bounds() -> Rect2:
	var a := to_xz(MAX_LAT, MIN_LON)
	var b := to_xz(MIN_LAT, MAX_LON)
	return Rect2(a, b - a)


static func outline() -> PackedVector2Array:
	if _outline_xz.is_empty() and built:
		for p in TexasData.meta.outline:
			_outline_xz.append(Vector2(p[0], p[1]))
	if _outline_xz.is_empty():
		for p in OUTLINE:
			_outline_xz.append(to_xz(p[0], p[1]))
	return _outline_xz


static func in_texas(x: float, z: float) -> bool:
	if built:
		return TexasData.flags(x, z) & 1 != 0
	return Geometry2D.is_point_in_polygon(Vector2(x, z), outline())


static func is_gulf(x: float, z: float) -> bool:
	## Open water: outside the state on its Gulf side (and off Louisiana and Tamaulipas)
	if built:
		return TexasData.flags(x, z) & 2 != 0
	if in_texas(x, z):
		return false
	var ll := to_latlon(x, z)
	var lat := ll.x
	var lon := ll.y
	if lon > -93.84:
		return lat < 29.62
	if lon > -97.65 and lat < 30.0:
		return true
	return lat < 25.96 and lon > -97.40


static func city_xz(c: Array) -> Vector2:
	return to_xz(c[1], c[2])


static func city(name: String) -> Array:
	for c in cities:
		if c[0] == name:
			return c
	for c in CITIES:
		if c[0] == name:
			return c
	return []


static func city_radius(tier: int) -> float:
	## How far a city's built-up area reaches, in game metres (thinned to 1:3)
	return [0.0, 700.0, 1800.0, 3200.0, 5500.0, 9000.0][clampi(tier, 0, 5)]


static func setup() -> void:
	## Call once on the main thread before any tile threads start. Uses the map builder's real
	## Texas when data/texas/build/ has one, the stand-in otherwise.
	built = TexasData.load_meta()
	if built:
		cities = []
		for c in TexasData.meta.cities:
			if int(c[3]) >= 1 and c[6]:
				var ll := to_latlon(c[1], c[2])
				cities.append([c[0], ll.x, ll.y, int(c[3]), float(c[5]), int(c[4])])
	_setup()
	outline()


static func _setup() -> void:
	if not _height_pts.is_empty():
		return
	for c in CITIES:
		var p := city_xz(c)
		_height_pts.append([p.x, p.y, float(c[4])])
	for h in HEIGHTS:
		var p := to_xz(h[0], h[1])
		_height_pts.append([p.x, p.y, float(h[2])])
	_noise = FastNoiseLite.new()
	_noise.seed = 1836
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.00012
	_noise.fractal_octaves = 4


static func base_elevation(x: float, z: float) -> float:
	## Real metres above sea level, smoothly blended from the known heights (inverse distance)
	_setup()
	var num := 0.0
	var den := 0.0
	for hp in _height_pts:
		var dx: float = x - hp[0]
		var dz: float = z - hp[1]
		var d2 := dx * dx + dz * dz + 4.0e6
		var w := 1.0 / (d2 * d2)
		num += w * hp[2]
		den += w
	return num / den


const LATTICE := 512.0             # the stand-in elevation is blended on this grid, then smoothed


static func height_cached(x: float, z: float, cache: Dictionary) -> float:
	## Ground height in game metres, fast: elevation from a 512 m grid (each grid point worked
	## out once and kept in `cache`), bilinear in between, plus rolling noise, rougher in the
	## west. Every caller gets the same answer for the same point, so tiles, roads and units
	## all sit on the same ground. Water is at 0; the sea floor dips below it.
	if built:
		return TexasData.height_real(x, z) * VERTICAL
	if is_gulf(x, z):
		return -3.0
	var e := elevation_cached(x, z, cache)
	var rough := 6.0 + e * 0.06
	return maxf(e + _noise.get_noise_2d(x, z) * rough, 1.0) * VERTICAL


static func elevation_cached(x: float, z: float, cache: Dictionary) -> float:
	if built:
		return TexasData.height_real(x, z)
	_setup()
	var fx := x / LATTICE
	var fz := z / LATTICE
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var e00 := _lattice(ix, iz, cache)
	var e10 := _lattice(ix + 1, iz, cache)
	var e01 := _lattice(ix, iz + 1, cache)
	var e11 := _lattice(ix + 1, iz + 1, cache)
	return lerpf(lerpf(e00, e10, tx), lerpf(e01, e11, tx), tz)


static func _lattice(ix: int, iz: int, cache: Dictionary) -> float:
	var k := Vector2i(ix, iz)
	if cache.has(k):
		return cache[k]
	var v := base_elevation(ix * LATTICE, iz * LATTICE)
	cache[k] = v
	return v


static func height(x: float, z: float) -> float:
	## Ground height in game metres: the stand-in elevation (scaled by VERTICAL) plus rolling
	## noise, rougher in the west. Water is at 0; the sea floor dips below it.
	if built:
		return TexasData.height_real(x, z) * VERTICAL
	if is_gulf(x, z):
		return -3.0
	var e := base_elevation(x, z)
	var rough := 6.0 + e * 0.06
	var h := e + _noise.get_noise_2d(x, z) * rough
	return maxf(h, 1.0) * VERTICAL


static func ground_color(x: float, z: float, h_real: float) -> Color:
	## What the land looks like from above: desert in the far west, plains in the Panhandle,
	## brush country in the middle, pine woods in the east, marsh and sand along the coast
	if not in_texas(x, z):
		return Color(0.40, 0.40, 0.37)
	var lon := to_latlon(x, z).y
	var west := Color(0.62, 0.54, 0.40)
	var plains := Color(0.60, 0.57, 0.40)
	var middle := Color(0.48, 0.50, 0.32)
	var east := Color(0.30, 0.42, 0.24)
	var c: Color
	if lon < -102.5:
		c = west.lerp(plains, clampf((lon + 104.0) / 1.5, 0.0, 1.0))
	elif lon < -99.0:
		c = plains.lerp(middle, clampf((lon + 102.5) / 3.5, 0.0, 1.0))
	else:
		c = middle.lerp(east, clampf((lon + 99.0) / 4.0, 0.0, 1.0))
	if built and TexasData.flags(x, z) & 4 != 0:
		c = c.lerp(Color(0.56, 0.55, 0.50), 0.45)         # built-up ground
	if h_real < 25.0:
		c = c.lerp(Color(0.44, 0.52, 0.34), 0.5)          # coastal marsh
	if h_real < 4.0 and not built:
		c = Color(0.80, 0.74, 0.56)                       # beach
	return c
