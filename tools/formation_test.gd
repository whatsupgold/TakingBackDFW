extends SceneTree
## Fleet formations: godot --headless --path . -s tools/formation_test.gd
var sim: TexasSim
var c: TexasCampaign

func _initialize() -> void:
	TexasGeo.setup()
	for k in TexasFormation.SHAPES.size():
		_open_sea(k)
	_through_the_pass()
	_guide_sunk()
	TexasWater.finish()
	quit()


func _fresh() -> void:
	sim = TexasSim.new(TexasRoads.new())
	sim.threaded = false
	seed(7)
	c = TexasCampaign.new()
	c.setup(sim)


func _fleet() -> Array:
	return c.formation._ships(c.ships.values())


func _run(secs: int, report_every := 0) -> Dictionary:
	## Run until the fleet has arrived; worst place-keeping error once formed, closest two ships
	var worst := 0.0
	var closest := INF
	var near_at := ""
	var t := 0
	var fleet := _fleet()
	if c.formation.active():
		fleet = [c.formation.lead] + c.formation.members.keys()
	var wake := 0
	while t < secs:
		sim.tick(1.0); c.tick(1.0)
		t += 1
		var f := c.formation
		if f.active() and not f.forming and t > 700:
			var ax := TexasFormation.axes(f.course)
			for m in f.members:
				var st: Vector2 = Vector2(sim.x[f.lead], sim.z[f.lead]) + ax[0] * f.members[m].x + ax[1] * f.members[m].y
				if f.mode.get(m, "") == "station":
					worst = maxf(worst, st.distance_to(Vector2(sim.x[m], sim.z[m])))
				else:
					wake += 1
		for a in fleet:
			for b in fleet:
				if a < b:
					var dd := Vector2(sim.x[a] - sim.x[b], sim.z[a] - sim.z[b]).length()
					if dd < closest:
						closest = dd
						near_at = "t=%d %s(%s)-%s(%s) active %s" % [t, c.formation.role_of(a), c.formation.mode.get(a, "lead" if a == c.formation.lead else "-"), c.formation.role_of(b), c.formation.mode.get(b, "lead" if b == c.formation.lead else "-"), c.formation.active()]
		var moving := false
		for i in fleet:
			moving = moving or sim.is_moving(i)
		if not f.active() and not moving:
			break
	return {"t": t, "worst": worst, "closest": closest, "wake": wake, "near": near_at}


func _layout() -> String:
	## Where everyone ended up, relative to the guide (right, ahead), rounded
	var g: int = c.ships.carrier
	var ax := TexasFormation.axes(c.formation.course)
	var parts: Array = []
	for r in ["cruiser", "destroyer0", "destroyer1", "amphib"]:
		var i: int = c.ships[r]
		var d := Vector2(sim.x[i] - sim.x[g], sim.z[i] - sim.z[g])
		parts.append("%s (%d, %d)" % [r, roundi(d.dot(ax[0]) / 10.0) * 10, roundi(d.dot(ax[1]) / 10.0) * 10])
	return ", ".join(parts)


func _open_sea(k: int) -> void:
	_fresh()
	c.formation.shape = k
	var cv := Vector2(sim.x[c.ships.carrier], sim.z[c.ships.carrier])
	var goal := cv + Vector2(-9000, 6000)        # out in the Gulf, south-west
	print("FORM: %s: goal at sea %s" % [c.formation.shape_name(), TexasSea.is_sea(goal)])
	var ok := c.command_move(_fleet(), goal)
	var r := _run(4000)
	print("FORM: %s across open water: ordered %d, done after %d s, worst distance from its place while sailing %.0f m, closest two ships %.0f m (%s), carrier %.0f m from the goal" % [
		c.formation.shape_name(), ok, r.t, r.worst, r.closest, r.near, Vector2(sim.x[c.ships.carrier], sim.z[c.ships.carrier]).distance_to(goal)])
	print("FORM: %s want: %s" % [c.formation.shape_name(), TexasFormation.SHAPES[k].slots])
	print("FORM: %s got:  %s" % [c.formation.shape_name(), _layout()])


func _through_the_pass() -> void:
	_fresh()
	c.formation.shape = 0
	var bay := TexasGeo.to_xz(29.42, -94.85)            # Galveston Bay, through Bolivar Roads
	print("FORM: pass: bay point at sea %s" % TexasSea.is_sea(bay))
	var ok := c.command_move(_fleet(), bay)
	var modes := {}
	var t := 0
	var arrived := false
	while t < 8000:
		sim.tick(1.0); c.tick(1.0)
		t += 1
		for m in c.formation.mode:
			modes[c.formation.mode[m]] = modes.get(c.formation.mode[m], 0) + 1
		var moving := false
		for i in _fleet():
			moving = moving or sim.is_moving(i)
		if not c.formation.active() and not moving:
			arrived = true
			break
	var far := 0.0
	for i in _fleet():
		far = maxf(far, Vector2(sim.x[i], sim.z[i]).distance_to(bay))
	var land := 0
	for i in _fleet():
		if not TexasSea.is_sea(Vector2(sim.x[i], sim.z[i])):
			land += 1
	print("FORM: into Galveston Bay in cross: ordered %d, all stopped %s after %d s, furthest ship %.0f m from the spot, on land %d, ship-seconds by mode %s" % [ok, arrived, t, far, land, modes])


func _guide_sunk() -> void:
	## Without the carrier the assault ship guides; sink it on the way and the next takes over
	_fresh()
	c.formation.shape = 2
	var cv := Vector2(sim.x[c.ships.carrier], sim.z[c.ships.carrier])
	var goal := cv + Vector2(-9000, 6000)
	var rest: Array = _fleet()
	rest.erase(c.ships.carrier)
	c.command_move(rest, goal)
	var g0 := c.formation.lead
	for k in 300:
		sim.tick(1.0); c.tick(1.0)
	sim._kill(c.ships.amphib)
	var r := _run(4000)
	print("FORM: guide (%s) sunk on the way: done after %d s, the rest %.0f m from the goal on average" % [c.formation.role_of(g0), r.t, _avg_dist(goal, [c.ships.carrier])])


func _avg_dist(p: Vector2, skip := []) -> float:
	var s := 0.0
	var n := 0
	for i in _fleet():
		if i in skip:
			continue
		s += Vector2(sim.x[i], sim.z[i]).distance_to(p)
		n += 1
	return s / maxi(n, 1)
