extends SceneTree
## Whole fleet sent to one spot, and hovercraft left on top of each other
func _initialize() -> void:
	TexasGeo.setup()
	var sim := TexasSim.new(TexasRoads.new())
	sim.threaded = false
	var c := TexasCampaign.new()
	c.setup(sim)
	var fleet: Array = []
	for i in sim.count:
		if sim.alive[i] == 1 and sim.side[i] == 0 and TexasUnits.is_ship(sim.utype[i]):
			fleet.append(i)
	var cx := 0.0; var cz := 0.0
	for i in fleet:
		cx += sim.x[i]; cz += sim.z[i]
	var goal := Vector2(cx / fleet.size(), cz / fleet.size()) + Vector2(1500, -2500)
	if not TexasSea.is_sea(goal):
		goal = Vector2(cx / fleet.size(), cz / fleet.size())
	print("FLEET: %d ships, goal sea %s" % [fleet.size(), TexasSea.is_sea(goal)])
	c.command_move(fleet, goal)
	var done := -1
	for k in 3600:
		sim.tick(1.0); c.tick(1.0)
		var any := false
		for i in fleet:
			if sim.is_moving(i):
				any = true
		if not any:
			done = k
			break
	for i in fleet:
		print("FLEET: %s moving %s, %.0f m from goal" % [TexasUnits.TYPES[sim.utype[i]].id, sim.is_moving(i), Vector2(sim.x[i], sim.z[i]).distance_to(goal)])
	print("FLEET: all stopped after %d s" % done)
	# hovercraft stacked on one point at sea
	var hv: Array = []
	for i in sim.count:
		if sim.alive[i] == 1 and TexasUnits.TYPES[sim.utype[i]].id == "lcac":
			hv.append(i)
	for i in hv:
		sim.aboard[i] = -1
		sim.x[i] = goal.x + 2000; sim.z[i] = goal.y
		sim.stop(i)
	for k in 60:
		sim.tick(1.0); c.tick(1.0)
	var mind := INF
	for a in hv:
		for b in hv:
			if a < b:
				mind = minf(mind, Vector2(sim.x[a] - sim.x[b], sim.z[a] - sim.z[b]).length())
	print("FLEET: %d hovercraft, closest pair %.0f m apart" % [hv.size(), mind])
	TexasWater.finish()
	quit()
