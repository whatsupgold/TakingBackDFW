extends SceneTree
## Line of sight past buildings: godot --headless --path . -s tools/sight_test.gd
func _initialize() -> void:
	TexasGeo.setup()
	var hou := TexasGeo.to_xz(29.7604, -95.3698)          # downtown Houston
	var key := Vector2i(floori(hou.x / TexasData.tile_size), floori(hou.y / TexasData.tile_size))
	var t0 := Time.get_ticks_usec()
	var g := TexasSight.roofs(key)
	print("SIGHT: rooftop grid for the downtown tile in %.1f ms, %d of %d cells built on, tallest %d m" % [(Time.get_ticks_usec() - t0) / 1000.0, Array(g).filter(func(v): return v > 0).size(), g.size(), Array(g).max()])
	# the tallest cell: stand either side of it
	var best := 0
	for k in g.size():
		if g[k] > g[best]:
			best = k
	var c := Vector2(key.x * TexasData.tile_size + (best % 256 + 0.5) * 8.0, key.y * TexasData.tile_size + (best / 256 + 0.5) * 8.0)
	for dir in [Vector2(1, 0), Vector2(0, 1)]:
		var a: Vector2 = c - dir * 150.0
		var b: Vector2 = c + dir * 150.0
		print("SIGHT: tank to tank across the tallest building (%s): clear %s; helicopter overhead to tank: clear %s; jet: clear %s" % [dir,
			TexasSight.clear(a.x, a.y, 1.2, b.x, b.y, 1.2), TexasSight.clear(a.x, a.y, 45.0, b.x, b.y, 1.2), TexasSight.clear(a.x, a.y, 160.0, b.x, b.y, 1.2)])
	# open country west of Houston, and out at sea
	var open := TexasGeo.to_xz(29.80, -96.30)
	print("SIGHT: open country 1 km: clear %s" % TexasSight.clear(open.x, open.y, 1.2, open.x + 1000.0, open.y, 1.2))
	var sea := TexasGeo.to_xz(29.10, -94.60)
	print("SIGHT: at sea 6 km: clear %s" % TexasSight.clear(sea.x, sea.y, 12.0, sea.x + 6000.0, sea.y, 1.2))
	# across downtown, many random lines: how many are blocked and how long they take
	seed(3)
	var n := 2000
	var shut := 0
	t0 = Time.get_ticks_usec()
	for k in n:
		var p := hou + Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		var q := p + Vector2.from_angle(randf() * TAU) * randf_range(100, 1200)
		if not TexasSight.clear(p.x, p.y, 1.2, q.x, q.y, 1.2):
			shut += 1
	var us := float(Time.get_ticks_usec() - t0) / n
	print("SIGHT: downtown, ground to ground 100-1200 m: %d of %d blocked, %.0f us a line (with the tiles' grids made on the way)" % [shut, n, us])
	t0 = Time.get_ticks_usec()
	for k in n:
		var p := hou + Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		var q := p + Vector2.from_angle(randf() * TAU) * randf_range(100, 1200)
		TexasSight.clear(p.x, p.y, 1.2, q.x, q.y, 1.2)
	print("SIGHT: again with the grids ready: %.0f us a line" % (float(Time.get_ticks_usec() - t0) / n))
	quit()
