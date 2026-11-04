extends SceneTree
## Checks that aircraft and ships turn like the real thing: godot --headless --path . -s tools/flight_test.gd
func _initialize() -> void:
	TexasGeo.setup()
	var sim := TexasSim.new(TexasRoads.new())
	sim.threaded = false
	seed(1836)
	var c := TexasCampaign.new()
	c.setup(sim)
	var carrier: int = c.ships.carrier
	for id in ["hornet", "black_hawk"]:
		var u := c.launch(TexasUnits.id(id))
		sim.heading[u] = 0.0                        # facing north
		var goal := Vector2(sim.x[u], sim.z[u] + 3000.0)   # 3 km behind it (south)
		c.command_move([u], goal)
		var max_rate := 0.0
		var prev := sim.heading[u]
		var reached := -1.0
		var min_d := INF
		var path_len := 0.0
		var last := Vector2(sim.x[u], sim.z[u])
		for k in 240:
			sim.tick(0.5)
			c.tick(0.5)
			var rate := absf(wrapf(sim.heading[u] - prev, -PI, PI)) / 0.5
			prev = sim.heading[u]
			max_rate = maxf(max_rate, rate)
			var p := Vector2(sim.x[u], sim.z[u])
			path_len += p.distance_to(last)
			last = p
			min_d = minf(min_d, p.distance_to(goal))
			if reached < 0.0 and not sim.is_moving(u):
				reached = k * 0.5
		print("FLIGHT: %s sent 3 km behind itself: fastest turn %.1f deg/s (limit %.1f), closest to the spot %.0f m, there after %.0f s, flew %.0f m, still flying %s, leaning %.0f deg" % [
			id, rad_to_deg(max_rate), rad_to_deg(TexasUnits.turn[sim.utype[u]]), min_d, reached, path_len, sim.airborne(u), rad_to_deg(sim.bank[u])])
		# then home to the carrier
		c.return_to_base([u])
		var landed := -1.0
		for k in 600:
			sim.tick(1.0)
			c.tick(1.0)
			if sim.aboard[u] == carrier:
				landed = k
				break
		print("FLIGHT: %s back aboard the carrier after %.0f s (alive %d, aboard %d, state %d, returning %s, %.0f m from the carrier, dest %.0f m from it)" % [id, landed, sim.alive[u], sim.aboard[u], sim.state[u], c.returning.get(u, "-"), Vector2(sim.x[u] - sim.x[carrier], sim.z[u] - sim.z[carrier]).length(), Vector2(sim.dest_x[u] - sim.x[carrier], sim.dest_z[u] - sim.z[carrier]).length()])
	# a destroyer told to turn round
	var dd: int = c.ships.destroyer0
	sim.heading[dd] = 0.0
	sim.order_move(dd, Vector2(sim.x[dd], sim.z[dd] + 4000.0))
	var mr := 0.0
	var ph := sim.heading[dd]
	for k in 500:
		sim.tick(1.0)
		mr = maxf(mr, absf(wrapf(sim.heading[dd] - ph, -PI, PI)))
		ph = sim.heading[dd]
	print("FLIGHT: destroyer turning round: fastest turn %.1f deg/s, arrived %s" % [rad_to_deg(mr), not sim.is_moving(dd)])
	TexasWater.finish()
	quit()
