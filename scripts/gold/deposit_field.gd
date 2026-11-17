extends RefCounted
## Where the gold is. Deterministic from the seed, so the same world always holds the same gold.
## Gold collects where the water slows down: the inside of bends, the deepest line of the
## channel, just downstream of boulders, and the old bench channel. It is richest just above
## bedrock (the paystreak). Each river and creek has its own richness on top of that.

const WorldGen = preload("res://scripts/world/world_gen.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")

const MAX_GRAMS_PER_SHOVEL := 0.28
const PAYSTREAK := 0.25          # metres above bedrock where the rich layer sits
const MEAN_PIECE := 0.017        # average mass of one piece of gold (grams)
const BOULDER_CELL := 16.0

var world: WorldGen
var _boulders := {}              # Vector2i cell -> Array[Vector4]
var _patch := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(w: WorldGen, world_seed: int) -> void:
	world = w
	_patch.seed = world_seed + 10
	_patch.frequency = 0.06
	_patch.fractal_octaves = 3
	_rng.seed = world_seed + 11
	for b in w.boulders:
		var c := Vector2i(floori(b.x / BOULDER_CELL), floori(b.z / BOULDER_CELL))
		if not _boulders.has(c):
			_boulders[c] = []
		(_boulders[c] as Array).append(b)


## How good a spot is (about 0..2.4), ignoring depth.
func richness(x: float, z: float) -> float:
	var info := world.river_info(x, z)
	var r := 0.01
	var river_rich := 1.0
	if info.x < 1.0e5:
		var e := info.x
		var inside := info.y
		var outside := info.z
		river_rich = info.w
		if e < 0.0:
			var t := clampf(1.0 + e / 4.0, 0.0, 1.0)     # 0 at the deepest line, 1 at the edge
			r = lerpf(0.75, 0.45, t) + 0.2 * inside * t
		else:
			var bar := exp(-e / (2.5 + 6.0 * inside))
			r = (0.35 + 0.6 * inside) * bar * (1.0 - 0.7 * outside) + 0.12 * exp(-e / 15.0)
		r *= river_rich
	r = maxf(r, 0.8 * world.bench_weight(x, z))
	r += _boulder_bonus(x, z) * river_rich
	var patch := 0.35 + 1.3 * clampf(_patch.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	return clampf(r * patch, 0.0, 2.4)


## The best gravel along a creek, between 15% and 85% of its length.
func rich_spot(river_name: String) -> Vector2:
	var best := Vector2.ZERO
	var best_r := -1.0
	for i in 71:
		for frac: float in [-1.6, -1.2, -0.6, 0.0, 0.6, 1.2, 1.6]:
			var p := world.river_point(river_name, 0.15 + i * 0.01, frac)
			var r := richness(p.x, p.y)
			if r > best_r:
				best_r = r
				best = p
	return best


## Gold drops out in the slack water just downstream of a creek boulder.
func _boulder_bonus(x: float, z: float) -> float:
	var best := 0.0
	var c := Vector2i(floori(x / BOULDER_CELL), floori(z / BOULDER_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for b in _boulders.get(c + Vector2i(dx, dz), []):
				var flow := world.flow_dir(b.x, b.z)
				var rel := Vector2(x - b.x, z - b.z)
				var along := rel.dot(flow)
				var across := absf(rel.dot(Vector2(-flow.y, flow.x)))
				var reach: float = b.w * 4.0
				var wide: float = b.w * 1.3
				if along < 0.0 or along > reach or across > wide:
					continue
				best = maxf(best, 0.6 * (1.0 - along / reach) * (1.0 - across / wide))
	return best


## Fill one shovelful dug at (x, z) from top_h down to bottom_h.
func shovelful(x: float, z: float, top_h: float, bottom_h: float, bedrock_h: float) -> Paydirt:
	var above := (top_h + bottom_h) * 0.5 - bedrock_h
	var near_bedrock := above < PAYSTREAK
	var vertical := 1.0 if near_bedrock else 0.12 + 0.88 * exp(-(above - PAYSTREAK) / 0.2)
	var rich := richness(x, z)
	var p := Paydirt.new()
	p.source = Vector3(x, top_h, z)
	p.black_sand = clampf(0.04 + 0.22 * minf(rich, 1.2) * (0.5 + 0.5 * vertical) + _rng.randf() * 0.04, 0.0, 0.35)
	var pieces := _poisson(MAX_GRAMS_PER_SHOVEL * rich * vertical / MEAN_PIECE)
	for i in pieces:
		p.add_gold(_piece_mass(near_bedrock))
	return p


## One piece of gold with the usual mix of sizes (used for vein ore too).
func piece(allow_nugget: bool) -> float:
	return _piece_mass(allow_nugget)


func _piece_mass(allow_nugget: bool) -> float:
	var u := _rng.randf()
	if u < 0.55:
		return _rng.randf_range(0.001, 0.004)     # fines
	if u < 0.85:
		return _rng.randf_range(0.004, 0.015)     # flakes
	if u < 0.97:
		return _rng.randf_range(0.015, 0.05)      # big flakes
	if u < 0.997 or not allow_nugget:
		return _rng.randf_range(0.05, 0.3)        # pickers
	return _rng.randf_range(0.3, 2.5)             # a nugget


func _poisson(lam: float) -> int:
	if lam <= 0.0:
		return 0
	if lam > 30.0:
		return maxi(0, roundi(_rng.randfn(lam, sqrt(lam))))
	var limit := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= _rng.randf()
		if p <= limit:
			break
		k += 1
	return k
