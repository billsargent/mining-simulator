extends SceneTree
## Balance: roughly what an hour of work earns at each claim and creek, with each kind of gear,
## counting the drive from the cabin. Prints tables for tuning richness and claim prices, and
## checks that working farther out pays more and that better gear pays more.
## Run: godot --headless --path . --script res://tests/test_balance.gd
##
## Assumptions (rough, from playing and the machine settings):
##   shovelfuls an hour and share of gold kept: pan only 25 at 90%, sluice 240 at 75%,
##   high banker 300 at 80%, trommel with the excavator 1200 at 75%
##   the player works ground better than the creek average (75th percentile of richness),
##   digging about 1 m down to bedrock; bars are 86% gold at the base price
##   drive: road distance 1.4x the straight line at 40 km/h, there and back, for a 4 hour shift

const WorldGen = preload("res://scripts/world/world_gen.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const Claims = preload("res://scripts/core/claims.gd")
const Market = preload("res://scripts/core/market.gd")
const Garnets = preload("res://scripts/gold/garnets.gd")

const METHODS := [["pan", 25.0, 0.9], ["sluice", 240.0, 0.75], ["high banker", 300.0, 0.8], ["trommel", 1200.0, 0.75]]
const SHIFT_H := 4.0
const SPEED_KMH := 40.0
const PURITY := 0.86

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("BALANCE %-52s %s" % [name, "ok" if ok else "FAIL"])
	if not ok:
		_fails += 1


## Average share of the paystreak's gold in a shovelful, digging 1 m down to bedrock.
func _column_share() -> float:
	var total := 0.0
	var n := 20
	for i in n:
		var above := (i + 0.5) / n * 1.0
		total += 1.0 if above < DepositField.PAYSTREAK else 0.12 + 0.88 * exp(-(above - DepositField.PAYSTREAK) / 0.2)
	return total / n


func _rich_at(world, field, pts: Array) -> float:
	var rs: Array[float] = []
	for p in pts:
		rs.append(field.richness(p.x, p.y))
	rs.sort()
	return rs[int(rs.size() * 0.75)] if not rs.is_empty() else 0.0


func _initialize() -> void:
	var world := WorldGen.new(1849)
	world.generate()
	var field := DepositField.new(world, 1849)
	Claims.setup(world, field)
	var home: Vector2 = world.sites["base"]["pos"]
	var share := _column_share()
	var gram_value := Market.BASE_PRICE * PURITY
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	print("\nClaims (machines run here). Dollars an hour over a %d hour shift, after the drive." % int(SHIFT_H))
	print("  %-24s %6s %6s %7s %7s %7s %8s %8s  %s" % ["claim", "km", "rich", "pan", "sluice", "banker", "trommel", "price", "payback (sluice h)"])
	var rows := []
	for c in Claims.list:
		var pts := []
		for i in 400:
			var t := rng.randf()
			var p := world.river_point(c["river"], t, rng.randf_range(-1.6, 1.6))
			if p.distance_to(c["pos"]) <= float(c["radius"]):
				pts.append(p)
		var rich := _rich_at(world, field, pts)
		var km: float = (c["pos"] as Vector2).distance_to(home) / 1000.0
		var trip_h := km * 1.4 * 2.0 / SPEED_KMH
		var work := SHIFT_H / (SHIFT_H + trip_h)
		var per_h := []
		for m in METHODS:
			per_h.append(DepositField.MAX_GRAMS_PER_SHOVEL * rich * share * float(m[1]) * float(m[2]) * gram_value * work)
		var payback := float(c["price"]) / maxf(per_h[1] - _home_sluice(rows), 1.0) if c["price"] > 0 else 0.0
		rows.append({"id": c["id"], "km": km, "rich": rich, "per_h": per_h, "price": c["price"]})
		print("  %-24s %6.1f %6.2f %7d %7d %7d %8d %8d  %s" % [c["name"], km, rich, per_h[0], per_h[1], per_h[2], per_h[3], c["price"],
			("%.0f" % payback) if c["price"] > 0 else "-"])

	print("\nCreeks for panning (public land, anywhere on the creek):")
	var creeks := []
	for r in world.rivers:
		var pts := []
		for i in 300:
			pts.append(world.river_point(r["name"], rng.randf_range(0.1, 0.9), rng.randf_range(-1.6, 1.6)))
		var rich := _rich_at(world, field, pts)
		var mid := world.river_point(r["name"], 0.5, 0.0)
		var km := mid.distance_to(home) / 1000.0
		var work := SHIFT_H / (SHIFT_H + km * 2.8 / SPEED_KMH)
		var pan_h := DepositField.MAX_GRAMS_PER_SHOVEL * rich * share * 25.0 * 0.9 * gram_value * work
		creeks.append({"name": r["name"], "km": km, "pan": pan_h})
		print("  %-20s %5.1f km  rich %.2f   pan $%d/h%s" % [r["name"], km, rich, pan_h, "  (dry: dry washer only)" if r.get("dry", false) else ""])

	var g := Garnets.dollars_per_hour()
	print("\nGarnet Beach, with the sieve: about $%d an hour of sieving (before the drive)." % g)
	var home_row: Dictionary = rows[0]
	print("")
	# Checks: better gear always pays more, and bought claims beat home with the same gear.
	var gear_ok := true
	for r in rows:
		for i in range(1, METHODS.size()):
			if r["per_h"][i] <= r["per_h"][i - 1]:
				gear_ok = false
	_check("better gear always earns more", gear_ok)
	var claims_ok := true
	for r in rows:
		if r["price"] > 0 and r["per_h"][1] <= home_row["per_h"][1]:
			claims_ok = false
			print("  %s earns less than home with a sluice" % r["id"])
	_check("every bought claim beats home with a sluice", claims_ok)
	var price_ok := true
	for r in rows:
		for r2 in rows:
			if r2["price"] > r["price"] and r2["per_h"][1] < r["per_h"][1] * 0.9:
				price_ok = false
				print("  %s costs more than %s but earns less" % [r2["id"], r["id"]])
	_check("dearer claims earn at least about as much", price_ok)
	# The endgame: Dutch's Ledge should take a good while of mid-game work (8 to 20 hours of the
	# best high banker claim) and then be the richest ground there is.
	var ledge_row := {}
	var best_hb := 0.0
	var best_other := 0.0
	for r in rows:
		if r["id"] == "ledge":
			ledge_row = r
		else:
			best_hb = maxf(best_hb, r["per_h"][2])
			best_other = maxf(best_other, r["rich"])
	_check("Dutch's Ledge exists", not ledge_row.is_empty())
	if not ledge_row.is_empty():
		var hours: float = float(ledge_row["price"]) / best_hb
		print("  Dutch's Ledge: $%d is %.1f hours of the best high banker claim" % [ledge_row["price"], hours])
		_check("Dutch's Ledge takes 8 to 20 hours of mid-game work", hours >= 8.0 and hours <= 20.0)
		_check("Dutch's Ledge is the richest claim", ledge_row["rich"] > best_other)
	_check("garnets are a side line, not a goldmine", g > 0 and g < home_row["per_h"][1])
	print("BALANCE complete: %d failed" % _fails)
	quit(1 if _fails > 0 else 0)


func _home_sluice(rows: Array) -> float:
	return rows[0]["per_h"][1] if not rows.is_empty() else 0.0
