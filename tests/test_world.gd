extends SceneTree
## Generates the world and reports timing, height range, rivers, road steepness and sites.
## Run: godot --headless --path . --script res://tests/test_world.gd [-- --map=<png path>]

const WorldGen = preload("res://scripts/world/world_gen.gd")


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.new(1849)
	w.generate()
	print("Generated in %d ms" % (Time.get_ticks_msec() - t0))
	var lo := 1.0e9
	var hi := -1.0e9
	for j in 65:
		for i in 65:
			var h := w.surface(i * 32.0, j * 32.0)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	print("Height range %.1f to %.1f m" % [lo, hi])
	for r in w.rivers:
		var pts: PackedVector2Array = r["pts"]
		var wl: PackedFloat32Array = r["wl"]
		var length := 0.0
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
		# Is the water actually in a channel? Check the bank is above water at the edge + 3 m.
		var dry := 0
		var wet := 0
		for i in range(5, pts.size() - 5, 10):
			var p := pts[i]
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var hw: float = (r["hw"] as PackedFloat32Array)[i]
			for s: float in [-1.0, 1.0]:
				var q := p + side * s * (hw + 3.0)
				if w.surface(q.x, q.y) > w.water_level(q.x, q.y):
					dry += 1
				else:
					wet += 1
			if w.surface(p.x, p.y) >= wl[i]:
				print("  ! %s dry centerline at %s" % [r["name"], p])
		print("  %-18s %5.0f m long, water %.1f -> %.1f m, richness %.2f, banks above water %d/%d" % [
			r["name"], length, wl[0], wl[wl.size() - 1], r["rich"], dry, dry + wet])
	for road in w.roads:
		var pts: PackedVector2Array = road["pts"]
		var worst := 0.0
		var length := 0.0
		for i in pts.size() - 1:
			var dist := pts[i].distance_to(pts[i + 1])
			length += dist
			var dh := absf(w.surface(pts[i + 1].x, pts[i + 1].y) - w.surface(pts[i].x, pts[i].y))
			worst = maxf(worst, dh / maxf(dist, 0.1))
		print("  road %5.0f m, steepest %.0f%%" % [length, worst * 100.0])
	for s in w.sites:
		var site: Dictionary = w.sites[s]
		print("  site %-5s at %s, height %.1f" % [s, site["pos"], site.get("height", 0.0)])
	print("  creek boulders: %d" % w.boulders.size())
	var t1 := Time.get_ticks_msec()
	var samples := 0.0
	for i in 20000:
		samples += w.sample(100.0 + i * 0.09, 900.0 + i * 0.05).x
	print("  20000 samples in %d ms" % (Time.get_ticks_msec() - t1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			var t2 := Time.get_ticks_msec()
			var img := w.make_map_image(512)
			img.save_png(a.substr(6))
			print("  map image in %d ms" % (Time.get_ticks_msec() - t2))
	quit()
