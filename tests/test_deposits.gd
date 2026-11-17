extends SceneTree
## Prints how much gold a shovelful holds near each river and creek, at the surface and near
## bedrock, plus the bench and the hills, so the gold distribution can be tuned.
## Run: godot --headless --path . --script res://tests/test_deposits.gd

const WorldGen = preload("res://scripts/world/world_gen.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")

const SAMPLES := 300


func _initialize() -> void:
	var world := WorldGen.new(1849)
	world.generate()
	var field := DepositField.new(world, 1849)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	print("Grams per shovelful (pieces): surface / bedrock")
	for r in world.rivers:
		var pts: PackedVector2Array = r["pts"]
		var bars: Array[Vector2] = []
		var channel: Array[Vector2] = []
		for i in SAMPLES:
			var t := rng.randf_range(0.08, 0.92)
			bars.append(world.river_point(r["name"], t, rng.randf_range(1.1, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)))
			channel.append(world.river_point(r["name"], t, rng.randf_range(-0.8, 0.8)))
		print("  %-18s channel %s   banks %s" % [r["name"], _zone(world, field, channel), _zone(world, field, bars)])
	var bench: Array[Vector2] = []
	var hills: Array[Vector2] = []
	var tries := 0
	while (bench.size() < SAMPLES or hills.size() < SAMPLES) and tries < 4000000:
		tries += 1
		var x := rng.randf_range(10.0, WorldGen.SIZE - 10.0)
		var z := rng.randf_range(10.0, WorldGen.SIZE - 10.0)
		if world.bench_weight(x, z) > 0.9 and bench.size() < SAMPLES:
			bench.append(Vector2(x, z))
		elif world.river_info(x, z).x > 1.0e5 and world.bench_weight(x, z) < 0.01 and hills.size() < SAMPLES:
			hills.append(Vector2(x, z))
	print("  %-18s %s" % ["old bench", _zone(world, field, bench)])
	print("  %-18s %s" % ["hills", _zone(world, field, hills)])
	quit()


func _zone(world: WorldGen, field: DepositField, pts: Array[Vector2]) -> String:
	var top_g := 0.0
	var top_n := 0
	var deep_g := 0.0
	var deep_n := 0
	for p in pts:
		var s := world.sample(p.x, p.y)
		var bed := s.x - s.w
		var surface := field.shovelful(p.x, p.y, s.x, s.x - 0.15, bed)
		var deep := field.shovelful(p.x, p.y, bed + 0.15, bed, bed)
		top_g += surface.gold_grams()
		top_n += surface.gold.size()
		deep_g += deep.gold_grams()
		deep_n += deep.gold.size()
	var n := float(maxi(pts.size(), 1))
	return "%.3f g (%.1f) / %.3f g (%.1f)" % [top_g / n, top_n / n, deep_g / n, deep_n / n]
