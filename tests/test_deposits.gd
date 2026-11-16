extends SceneTree
## Prints how much gold a shovelful holds in different parts of the valley, near the
## surface and near bedrock, so the gold distribution can be tuned.
## Run: godot --headless --path . --script res://tests/test_deposits.gd

const Valley = preload("res://scripts/world/valley.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")

const SAMPLES := 400


func _initialize() -> void:
	var valley := Valley.new(1849)
	var field := DepositField.new(valley, 1849)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var zones := {
		"channel": [], "inside bar (edge)": [], "outside bank": [],
		"floodplain": [], "bench": [], "hills": [],
	}
	var tries := 0
	while tries < 200000:
		tries += 1
		var x := rng.randf_range(5.0, 250.0)
		var z := rng.randf_range(5.0, 250.0)
		var g := valley.geometry(x, z)
		var zone := ""
		if g.y < 0.0:
			zone = "channel"
		elif g.y < 3.0 and g.z > 0.5:
			zone = "inside bar (edge)"
		elif g.y < 3.0 and g.w > 0.5:
			zone = "outside bank"
		elif g.y > 8.0 and g.y < 20.0 and valley.bench_mask(g.x) < 0.1:
			zone = "floodplain"
		elif g.x > 0.0 and valley.bench_mask(g.x) > 0.9:
			zone = "bench"
		elif g.y > 45.0:
			zone = "hills"
		if zone == "" or (zones[zone] as Array).size() >= SAMPLES:
			continue
		(zones[zone] as Array).append(Vector2(x, z))
	print("Grams per shovelful (pieces) by zone")
	for zone in zones:
		var pts: Array = zones[zone]
		var top_g := 0.0
		var top_n := 0
		var deep_g := 0.0
		var deep_n := 0
		for p: Vector2 in pts:
			var s := valley.sample(p.x, p.y)
			var bed := s.x - s.y
			var surface := field.shovelful(p.x, p.y, s.x, s.x - 0.15, bed)
			var deep := field.shovelful(p.x, p.y, bed + 0.15, bed, bed)
			top_g += surface.gold_grams()
			top_n += surface.gold.size()
			deep_g += deep.gold_grams()
			deep_n += deep.gold.size()
		var n := maxi(pts.size(), 1)
		print("  %-18s surface %.3f g (%.1f)   bedrock %.3f g (%.1f)   [%d samples]" % [
			zone, top_g / n, float(top_n) / n, deep_g / n, float(deep_n) / n, pts.size()])
	quit()
