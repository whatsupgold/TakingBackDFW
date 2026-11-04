extends SceneTree
func _initialize() -> void:
	TexasGeo.setup()
	var roads := TexasRoads.new()
	var sim := TexasSim.new(roads)
	sim.seed_demo(1.5, 1500)
	# how many units have an enemy within 3 km, and how many enemies each sees
	var near := 0
	var pairs := 0
	for i in sim.count:
		var m := 0
		for j in sim.count:
			if sim.side[j] != sim.side[i] and absf(sim.x[j] - sim.x[i]) < 4500.0 and absf(sim.z[j] - sim.z[i]) < 4500.0:
				m += 1
		if m > 0:
			near += 1
			pairs += m
	print("BENCH: units with an enemy in their 3x3 cells: %d, enemy checks %d" % [near, pairs])
	var t := Time.get_ticks_usec()
	var a := 0.0
	for k in pairs:
		a += float(k) * 0.5
	print("BENCH: %d plain loop iterations: %.1f ms" % [pairs, (Time.get_ticks_usec() - t) / 1000.0])
	quit()
