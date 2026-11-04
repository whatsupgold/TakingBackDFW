extends SceneTree
## Checks the sea lanes around Galveston: godot --headless --path . -s tools/sea_test.gd
func _initialize() -> void:
	TexasGeo.setup()
	var sa := TexasGeo.to_xz(29.95, -95.60)
	var sb := TexasGeo.to_xz(28.55, -94.25)
	var t0 := Time.get_ticks_msec()
	var sea := TexasSea.new(Rect2(sa, sb - sa))
	print("SEA: grid built in %d ms" % (Time.get_ticks_msec() - t0))
	var fleet := TexasGeo.to_xz(29.12, -94.62)
	for pt in [["Galveston port", 29.310, -94.795], ["Texas City", 29.37, -94.895], ["Barbours Cut", 29.683, -95.0], ["Bolivar Roads", 29.34, -94.74]]:
		var p := TexasGeo.to_xz(pt[1], pt[2])
		var r := sea.route(fleet, p)
		print("SEA: %s sea=%s nearest cell=%s route waypoints=%d" % [pt[0], TexasSea.is_sea(p), sea.nearest_sea(p), r.size()])
	# Is the channel open? sample a line through Bolivar Roads into the harbour
	var s := ""
	for k in 21:
		var lat := 29.30 + k * 0.004
		var row := ""
		for q in 41:
			var lon := -94.86 + q * 0.004
			row += "~" if TexasSea.is_sea(TexasGeo.to_xz(lat, lon)) else "#"
		s = row + "\n" + s
	print(s)
	quit()
