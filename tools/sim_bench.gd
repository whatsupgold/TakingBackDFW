extends SceneTree
func _initialize() -> void:
	TexasGeo.setup()
	var roads := TexasRoads.new()
	var sim := TexasSim.new(roads)
	sim.seed_demo(1.5, 1500)
	sim.threaded = false
	var t := Time.get_ticks_usec()
	for k in 5:
		sim._combat_acc = 0.0
		sim.tick(4.0)
	print("BENCH: move only: %.1f ms per tick (%d units)" % [(Time.get_ticks_usec() - t) / 5000.0, sim.count])
	for k in 6:
		t = Time.get_ticks_usec()
		sim._combat(5.0)
		print("BENCH: combat round %d: %.1f ms" % [k + 1, (Time.get_ticks_usec() - t) / 1000.0])
	# Threaded: what the main thread pays to start a round (copying the arrays)
	sim.threaded = true
	t = Time.get_ticks_usec()
	sim._combat(5.0)
	print("BENCH: starting a threaded round on the main thread: %.2f ms" % [(Time.get_ticks_usec() - t) / 1000.0])
	quit()

