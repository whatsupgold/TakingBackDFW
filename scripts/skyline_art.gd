class_name SkylineArt
extends Control
## Title-screen backdrop: the DFW skyline at dusk, drawn as 320x180 pixel art and scaled up
## with whole-number pixels. Fort Worth on the left, AT&T Stadium in the middle, Dallas on
## the right with Reunion Tower and the green outline of Bank of America Plaza. A Huey and
## an A-10 cross the sky while a Red Army column with tanks rolls along the highway.

const W := 320
const H := 180
const HORIZON := 140

const SKY_TOP := Color(0.10, 0.07, 0.20)
const SKY_MID := Color(0.42, 0.20, 0.36)
const SKY_LOW := Color(0.96, 0.52, 0.26)
const SILHOUETTE := Color(0.09, 0.07, 0.12)
const SILHOUETTE_FAR := Color(0.20, 0.13, 0.22)
const WINDOW := Color(1.0, 0.78, 0.40)
const GROUND := Color(0.08, 0.06, 0.07)

var _towers: Array = []      # [x, w, h, far, lit windows]
var _troops: Array = []      # [x, y, height] Red Army column (marches left)
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 214
	# Far layer first, then near
	for far in [true, false]:
		var x := 6
		while x < W - 6:
			var w := rng.randi_range(6, 13)
			var dallas := x > 188
			var fortworth := x < 112
			var h := 6
			if dallas:
				h = rng.randi_range(28, 70)
			elif fortworth:
				h = rng.randi_range(18, 44)
			else:
				h = rng.randi_range(4, 12)
			if far:
				h = int(h * 0.75) + 6
			var lit: Array = []
			if not far:
				for k in rng.randi_range(2, int(h * w / 18.0) + 2):
					lit.append(Vector2i(rng.randi_range(1, w - 2), rng.randi_range(2, h - 2)))
			_towers.append([x, w, h, far, lit])
			x += w + rng.randi_range(0 if not far else 2, 4)
	for i in 34:
		_troops.append([i * 9.0 + rng.randf_range(-2, 2), 160 + (i % 3) * 6, rng.randi_range(6, 7)])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := maxf(1.0, floorf(minf(size.x / W, size.y / H)))
	var off := ((size - Vector2(W, H) * s) * 0.5).floor()
	# Fill the margins (window shapes other than 16:9)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, off.y + HORIZON * s)), SKY_TOP)
	draw_rect(Rect2(Vector2(0, off.y + HORIZON * s), Vector2(size.x, size.y)), GROUND)
	draw_set_transform(off, 0.0, Vector2(s, s))

	# Sky: banded gradient
	for y in HORIZON:
		var f := float(y) / HORIZON
		var c := SKY_TOP.lerp(SKY_MID, clampf(f * 1.6, 0, 1)) if f < 0.62 else SKY_MID.lerp(SKY_LOW, (f - 0.62) / 0.38)
		draw_rect(Rect2(0, y, W, 1), c)
	# Sun sinking behind the city
	_disc(Vector2(150, 118), 20, Color(1.0, 0.70, 0.35))
	_disc(Vector2(150, 118), 15, Color(1.0, 0.82, 0.50))

	# Skyline
	for t in _towers:
		var col := SILHOUETTE_FAR if t[3] else SILHOUETTE
		draw_rect(Rect2(t[0], HORIZON - t[2], t[1], t[2]), col)
		for p in t[4]:
			if (int(_t * 0.7 + p.x * 7 + p.y * 3) % 23) != 0:   # the odd window flickers
				draw_rect(Rect2(t[0] + p.x, HORIZON - t[2] + p.y, 1, 1), WINDOW)
	# AT&T Stadium's low dome in the middle
	for x in range(124, 176):
		var h := int(10.0 * sin((x - 124) / 52.0 * PI)) + 4
		draw_rect(Rect2(x, HORIZON - h, 1, h), SILHOUETTE)
	# Bank of America Plaza with its green outline
	draw_rect(Rect2(262, HORIZON - 96, 12, 96), SILHOUETTE)
	var green := Color(0.35, 1.0, 0.45)
	draw_rect(Rect2(262, HORIZON - 96, 1, 96), green)
	draw_rect(Rect2(273, HORIZON - 96, 1, 96), green)
	draw_rect(Rect2(262, HORIZON - 96, 12, 1), green)
	# Reunion Tower: stalk and the lit ball
	draw_rect(Rect2(185, HORIZON - 74, 3, 74), SILHOUETTE)
	_disc(Vector2(186.5, HORIZON - 80), 7, SILHOUETTE)
	for k in 12:
		var a := TAU * k / 12.0 + _t * 0.6
		var p := Vector2(186.5, HORIZON - 80) + Vector2(cos(a) * 5.0, sin(a) * 4.0)
		if sin(a) < 0.3:
			draw_rect(Rect2(p.floor(), Vector2(1, 1)), WINDOW)

	# Highway with abandoned cars
	draw_rect(Rect2(0, HORIZON, W, 16), GROUND)
	draw_rect(Rect2(0, HORIZON + 2, W, 9), Color(0.14, 0.12, 0.13))
	for x in range(0, W, 12):
		draw_rect(Rect2(x, HORIZON + 6, 5, 1), Color(0.55, 0.45, 0.25))
	for x in [22, 70, 131, 205, 248, 296]:
		draw_rect(Rect2(x, HORIZON + 3, 7, 3), Color(0.20, 0.15, 0.16))
		draw_rect(Rect2(x + 2, HORIZON + 2, 3, 1), Color(0.20, 0.15, 0.16))

	# The Red Army column, marching left, with two tanks
	var shade := Color(0.05, 0.04, 0.05)
	for tr in _troops:
		var x := fposmod(tr[0] - _t * 3.0, W + 40) - 20
		var y: int = tr[1]
		var h: int = tr[2]
		var step := int(_t * 4.0 + tr[0]) % 2
		draw_rect(Rect2(x, y - h, 3, h - 2), shade)
		draw_rect(Rect2(x, y - h - 2, 3, 2), shade)
		draw_rect(Rect2(x - 2, y - h + 1, 3, 1), shade)                       # rifle
		draw_rect(Rect2(x + (0 if step == 0 else 1), y - 2, 1, 2), shade)
		draw_rect(Rect2(x + 1, y - h + 2, 1, 1), Color(0.75, 0.15, 0.10))     # red armband
	for k in 2:
		var tx := fposmod(70.0 + k * 170.0 - _t * 3.0, W + 60) - 30
		var ty := 170.0
		draw_rect(Rect2(tx, ty - 5, 26, 5), shade)              # hull and tracks
		draw_rect(Rect2(tx + 7, ty - 9, 11, 4), shade)          # turret
		draw_rect(Rect2(tx - 10, ty - 8, 17, 1), shade)         # gun
		draw_rect(Rect2(tx + 12, ty - 8, 2, 2), Color(0.95, 0.75, 0.25))   # star

	# An A-10 streaking right to left, low
	var jx := fposmod(-_t * 42.0, W + 120) - 60
	var jy := 62.0
	draw_rect(Rect2(jx, jy, 14, 2), heli_col())
	draw_rect(Rect2(jx + 4, jy - 3, 3, 8), heli_col())          # wing (seen edge-on)
	draw_rect(Rect2(jx + 11, jy - 2, 3, 2), heli_col())         # engines
	draw_rect(Rect2(jx + 13, jy - 4, 1, 3), heli_col())         # tail

	# A Huey crossing the sky, rotor flickering
	var hx := fposmod(_t * 14.0, W + 60) - 30
	var hy := 36.0 + sin(_t * 0.8) * 2.0
	var heli := Color(0.07, 0.06, 0.09)
	draw_rect(Rect2(hx, hy, 12, 5), heli)
	draw_rect(Rect2(hx - 11, hy + 1, 11, 2), heli)
	draw_rect(Rect2(hx - 13, hy - 1, 2, 4), heli)
	draw_rect(Rect2(hx + 1, hy + 6, 10, 1), heli)
	draw_rect(Rect2(hx + 5, hy - 2, 2, 2), heli)
	var blade := 14 if int(_t * 12.0) % 2 == 0 else 10
	draw_rect(Rect2(hx + 6 - blade, hy - 3, blade * 2, 1), heli)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func heli_col() -> Color:
	return Color(0.07, 0.06, 0.09)


func _disc(c: Vector2, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		var half := int(sqrt(float(r * r - dy * dy)))
		draw_rect(Rect2(floorf(c.x) - half, floorf(c.y) + dy, half * 2 + 1, 1), col)
