extends RefCounted
## A prospector's note after a test pan: how many colors, fine or coarse, and where to try next.
## The hint reads the real gold map (deposit_field.richness) and the creek's shape (world_gen.river_info).

const STEP := 40.0          # metres up and down the creek to compare


## Returns [note, hint]: note is the one-line showing, hint is where to go next.
static func make(deposits, x: float, z: float, kept: PackedFloat32Array) -> Array:
	var grams := 0.0
	var biggest := 0.0
	for m in kept:
		grams += m
		biggest = maxf(biggest, m)
	var note: String
	if kept.is_empty():
		note = "No colors."
	else:
		var size := "fine" if biggest < 0.01 else ("coarse" if biggest >= 0.05 else "flaky")
		note = "%d color%s, %s gold, %.3f g." % [kept.size(), "" if kept.size() == 1 else "s", size, grams]
	return [note, hint(deposits, x, z, kept.size(), biggest)]


static func hint(deposits, x: float, z: float, colors: int, biggest: float) -> String:
	var world = deposits.world
	var info: Vector4 = world.river_info(x, z)
	var here: float = deposits.richness(x, z)
	if info.x >= 1.0e5:
		if world.bench_weight(x, z) > 0.3:
			return "Old bench gravel up here. Dig down to bedrock."
		return "Too far from water. Try a creek's inside bend."
	# Compare along the creek.
	var down: Vector2 = world.flow_dir(x, z)
	var up_r: float = deposits.richness(x - down.x * STEP, z - down.y * STEP)
	var dn_r: float = deposits.richness(x + down.x * STEP, z + down.y * STEP)
	var best := maxf(up_r, dn_r)
	if best > here * 1.4 and best > 0.25:
		return "Looks richer %s. Try about %d m that way." % ["upstream" if up_r >= dn_r else "downstream", int(STEP)]
	if info.z > 0.3:
		return "Outside bend, fast water. Cross to the inside of the bend."
	if info.x > 6.0 and info.y < 0.2:
		return "Too high on the bank. Get closer to the water, where it slows."
	if colors > 0 and biggest < 0.01:
		return "Fine gold travels. Dig deeper, the coarse stuff sits near bedrock."
	if here > 0.6:
		return "Good ground. Work this spot, down to bedrock."
	if info.y > 0.3:
		return "Inside bend, slow water. Go deeper toward bedrock."
	return "Thin here. Look for an inside bend or a boulder with slack water behind it."
