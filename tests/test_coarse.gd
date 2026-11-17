extends SceneTree
## How far coarse_surface() is from surface() on river banks (where trees grow).

const WorldGen = preload("res://scripts/world/world_gen.gd")


func _initialize() -> void:
	var w := WorldGen.new(1849)
	w.generate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var errs: Array[float] = []
	var tries := 0
	while errs.size() < 4000 and tries < 2000000:
		tries += 1
		var x := rng.randf_range(10.0, WorldGen.SIZE - 10.0)
		var z := rng.randf_range(10.0, WorldGen.SIZE - 10.0)
		var e := w.coarse_river_edge(x, z)
		if e < 10.0 or e > 40.0 or w.near_band(x, z):
			continue
		errs.append(absf(w.coarse_surface(x, z) - w.surface(x, z)))
	errs.sort()
	print("Bank points %d: median %.2f m, 90%% %.2f m, 99%% %.2f m, worst %.2f m" % [errs.size(),
		errs[errs.size() / 2], errs[int(errs.size() * 0.9)], errs[int(errs.size() * 0.99)], errs[-1]])
	var berr: Array[float] = []
	for b in w.boulders:
		berr.append(absf(w.coarse_surface(b.x, b.z) - w.surface(b.x, b.z)))
	berr.sort()
	print("Boulders %d: median %.2f m, 90%% %.2f m, worst %.2f m" % [berr.size(), berr[berr.size() / 2], berr[int(berr.size() * 0.9)], berr[-1]])
	quit()
