extends RefCounted
## Where the gold is. Deterministic from the seed, so the same valley always holds the same gold.
## Gold collects where the creek slows down: the inside of bends, the deepest line of the
## channel, just downstream of boulders, and the old bench channel. It is richest just above
## bedrock (the paystreak).

const Valley = preload("res://scripts/world/valley.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")

const MAX_GRAMS_PER_SHOVEL := 0.28
const PAYSTREAK := 0.25          # metres above bedrock where the rich layer sits
const MEAN_PIECE := 0.017        # average mass of one piece of gold (grams)

var valley: Valley
var boulders: Array[Vector4] = []     # creek boulders: x, y, z, radius
var _patch := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(v: Valley, world_seed: int) -> void:
	valley = v
	_patch.seed = world_seed + 10
	_patch.frequency = 0.06
	_patch.fractal_octaves = 3
	_rng.seed = world_seed + 11


## How good a spot is (about 0..1.4), ignoring depth.
func richness(x: float, z: float) -> float:
	var g := valley.geometry(x, z)
	var d := g.x
	var e := g.y
	var inside := g.z
	var outside := g.w
	var r: float
	if e < 0.0:
		var t := absf(d) / valley.half_width(x)
		r = lerpf(0.75, 0.45, t)            # the deepest line of the channel is richest
		r += 0.2 * inside * t               # and the inside edge of a bend
	else:
		var bar := exp(-e / (2.5 + 6.0 * inside))
		r = (0.35 + 0.6 * inside) * bar * (1.0 - 0.7 * outside)
		r += 0.12 * exp(-e / 15.0)          # a little flood gold on the floodplain
		if d > 0.0:
			r = maxf(r, 0.8 * valley.bench_mask(d))   # the ancient channel on the bench
	r += _boulder_bonus(x, z)
	var patch := 0.35 + 1.3 * clampf(_patch.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	return clampf(r * patch, 0.0, 1.4)


## Gold drops out in the slack water just downstream (+x) of a creek boulder.
func _boulder_bonus(x: float, z: float) -> float:
	var best := 0.0
	for b in boulders:
		var dx := x - b.x
		var reach := b.w * 4.0
		if dx < 0.0 or dx > reach:
			continue
		var dz := absf(z - b.z)
		var wide := b.w * 1.3
		if dz > wide:
			continue
		best = maxf(best, 0.6 * (1.0 - dx / reach) * (1.0 - dz / wide))
	return best


## Fill one shovelful dug at (x, z) from top_h down to bottom_h.
func shovelful(x: float, z: float, top_h: float, bottom_h: float, bedrock_h: float) -> Paydirt:
	var above := (top_h + bottom_h) * 0.5 - bedrock_h
	var near_bedrock := above < PAYSTREAK
	var vertical := 1.0 if near_bedrock else 0.12 + 0.88 * exp(-(above - PAYSTREAK) / 0.2)
	var rich := richness(x, z)
	var p := Paydirt.new()
	p.source = Vector3(x, top_h, z)
	p.black_sand = clampf(0.04 + 0.22 * rich * (0.5 + 0.5 * vertical) + _rng.randf() * 0.04, 0.0, 0.35)
	var pieces := _poisson(MAX_GRAMS_PER_SHOVEL * rich * vertical / MEAN_PIECE)
	for i in pieces:
		p.add_gold(_piece_mass(near_bedrock))
	return p


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
