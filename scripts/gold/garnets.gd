extends RefCounted
## Garnets: dark red gemstones, heavy like gold (but not that heavy), so they sink to the bottom
## of a shaken sieve. Flip the sieve over and they sit on top of the pile, in the middle.
## Found on Garnet Beach along the Big Sable River, and now and then chipped out of the mine
## walls (the schist there carries them). A fun side line, not a way to get rich.

const LOAD_SECONDS := 14.0     # scoop, shake under water, flip, pick: one sieve load
const PER_LOAD := 0.3          # garnets in a load on the beach, on average
const MINE_CHANCE := 0.02      # chance a chip of plain mine rock frees a garnet
const DOLLARS_PER_CARAT := 1.5


const BEACH_RADIUS := 40.0

## Garnet Beach: the gravel bar on the inside of the strongest bend of the Big Sable River east
## of town. Set by find_beach(); zero until then.
static var beach := Vector2.ZERO


## Pick the beach: along the river east of town, the bank point most on the inside of a bend.
static func find_beach(world) -> Vector2:
	var best := Vector2.ZERO
	var best_in := -1.0
	for i in 60:
		var t := 0.56 + i * 0.004
		for frac: float in [-1.3, 1.3]:
			var p: Vector2 = world.river_point("Big Sable River", t, frac)
			var info: Vector4 = world.river_info(p.x, p.y)
			if info.y > best_in:
				best_in = info.y
				best = p
	beach = best
	return best


## True where you can sieve: on the beach, between knee-deep water and a few metres up the bank.
static func on_beach(world, x: float, z: float) -> bool:
	if beach == Vector2.ZERO or Vector2(x, z).distance_to(beach) > BEACH_RADIUS:
		return false
	var e: float = world.river_info(x, z).x
	return e > -2.5 and e < 4.0


## How good this part of the beach is, 0..1: best in the middle, in streaks.
static func beach_richness(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(beach) / BEACH_RADIUS
	var streak := 0.5 + 0.5 * sin(x * 0.21 + z * 0.17)
	return clampf((1.0 - d) * (0.6 + 0.6 * streak), 0.0, 1.0)


## The size of one garnet in carats: mostly small, a few fine big ones.
static func carats(rng: RandomNumberGenerator) -> float:
	var u := rng.randf()
	if u < 0.6:
		return snappedf(rng.randf_range(0.2, 0.6), 0.05)
	if u < 0.92:
		return snappedf(rng.randf_range(0.6, 1.5), 0.05)
	if u < 0.99:
		return snappedf(rng.randf_range(1.5, 4.0), 0.05)
	return snappedf(rng.randf_range(4.0, 9.0), 0.05)       # a beauty


## What the assay office pays for one: per carat, and more per carat for big clean stones.
static func value(ct: float) -> int:
	return maxi(1, roundi(ct * DOLLARS_PER_CARAT * (1.0 + 0.35 * ct)))


## The garnets in one sieve load. `richness` 0..1: how good this part of the beach is.
static func sieve_load(rng: RandomNumberGenerator, richness: float) -> Array:
	var out := []
	var lam := PER_LOAD * (0.4 + 1.2 * richness)
	# Poisson count
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			break
		k += 1
	for i in k:
		out.append(carats(rng))
	return out


## Average dollars an hour of steady sieving on decent beach (for the balance test).
static func dollars_per_hour() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var total := 0
	var loads := 4000
	for i in loads:
		for ct in sieve_load(rng, 0.6):
			total += value(ct)
	return roundi(float(total) / loads * 3600.0 / LOAD_SECONDS)
