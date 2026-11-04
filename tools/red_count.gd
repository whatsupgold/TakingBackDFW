extends SceneTree
## Why does Red's count in the Galveston-Houston area change with nobody fighting?
func _initialize() -> void:
	TexasGeo.setup()
	var roads := TexasRoads.new()
	var sim := TexasSim.new(roads)
	sim.threaded = false
	seed(1836)
	var c := TexasCampaign.new()
	c.setup(sim)
	for h in 5:
		var by := {}
		var n := 0
		for i in sim.count:
			if sim.alive[i] == 1 and sim.side[i] == 1 and c.slice.has_point(Vector2(sim.x[i], sim.z[i])):
				n += 1
				var key := "%s%s%s" % [TexasUnits.TYPES[sim.utype[i]].id, " parked" if sim.aboard[i] <= -2 else "", " airborne" if sim.airborne(i) else ""]
				by[key] = by.get(key, 0) + 1
		print("RED: hour %d: %d in the area %s" % [h, n, by])
		for k in 120:
			sim.tick(30.0)
			c.tick(30.0)
	quit()
