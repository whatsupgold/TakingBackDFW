extends SceneTree
## Ships never sail over land: fleets and single ships to the ports round Galveston Bay
## godot --headless --path . -s tools/aground_test.gd
var sim: TexasSim
var c: TexasCampaign


func _initialize() -> void:
	TexasGeo.setup()
	var trips := [["Texas City", Vector2(29.37, -94.89)], ["Barbours Cut", Vector2(29.68, -94.99)],
		["Galveston port", Vector2(29.31, -94.79)], ["Freeport", Vector2(28.94, -95.31)], ["Bay middle", Vector2(29.50, -94.85)]]
	var total := 0
	for k in TexasFormation.SHAPES.size() + 1:
		for trip in trips:
			_fresh()
			var goal := TexasGeo.to_xz(trip[1].x, trip[1].y)
			var ids: Array = c.formation._ships(c.ships.values())
			var label := "fleet in %s" % TexasFormation.SHAPES[k].name if k < TexasFormation.SHAPES.size() else "destroyer alone"
			if k < TexasFormation.SHAPES.size():
				c.formation.shape = k
			else:
				ids = [c.ships.destroyer0]
			c.command_move(ids, goal)
			var bad := {}
			var worst := 0.0
			var where := ""
			var t := 0
			while t < 9000:
				sim.tick(1.0); c.tick(1.0)
				t += 1
				for i in ids:
					var p := Vector2(sim.x[i], sim.z[i])
					if not TexasWater.sea(p):
						var d := _inland(p)
						bad[i] = true
						if d > worst:
							worst = d
							where = "%s (%s) at %s, %s, leg %d/%d" % [c.formation.role_of(i), c.formation.mode.get(i, "lead" if i == c.formation.lead else "own"), TexasGeo.to_latlon(p.x, p.y), "flags sea" if TexasSea.is_sea(p) else "flags land", sim.leg[i], (sim.wps[i] as PackedVector2Array).size()]
				var moving := c.formation.active()
				for i in ids:
					moving = moving or sim.is_moving(i)
				if not moving:
					break
			if worst > 30.0:
				total += 1
			print("AGROUND: %s to %s: %d s, ships over land %d, furthest %.0f m from water%s" % [label, trip[0], t, bad.size(), worst, (": " + where) if worst > 0.0 else ""])
	print("AGROUND: %d trips with a ship more than 30 m onto land" % total)
	TexasWater.finish()
	quit()


func _fresh() -> void:
	sim = TexasSim.new(TexasRoads.new())
	sim.threaded = false
	seed(7)
	c = TexasCampaign.new()
	c.setup(sim)
	# nobody shooting: just the sailing
	for i in sim.count:
		if sim.side[i] == 1:
			sim.alive[i] = 0


func _inland(p: Vector2) -> float:
	for r in [10.0, 20.0, 30.0, 45.0, 65.0, 90.0, 130.0, 180.0, 250.0, 350.0, 500.0, 800.0]:
		for k in 16:
			if TexasWater.sea(p + Vector2.from_angle(TAU * k / 16.0) * r):
				return r
	return 1000.0
