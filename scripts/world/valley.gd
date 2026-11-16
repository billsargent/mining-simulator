extends RefCounted
## The shape of the M1 test valley: a meandering creek flowing toward +x, gravel bars on
## the inside of bends, steep cut banks on the outside, a floodplain, wooded hills, and an
## old bench (an ancient, higher creek channel) on the north side.

const SIZE := 256.0
const WATER_LEVEL := 0.08
const BENCH_HEIGHT := 9.5
const MAX_BEND := 0.045      # curvature that counts as a "full" bend

var _hills := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _gravel_noise := FastNoiseLite.new()


func _init(world_seed: int = 1849) -> void:
	_hills.seed = world_seed
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_bumps.seed = world_seed + 1
	_bumps.frequency = 0.15
	_bumps.fractal_octaves = 2
	_gravel_noise.seed = world_seed + 2
	_gravel_noise.frequency = 0.08


# --- Creek centerline: z as a function of x -------------------------------------------

func center_z(x: float) -> float:
	return 128.0 + 22.0 * sin(x * 0.035) + 9.0 * sin(x * 0.06 + 1.3)


func center_dz(x: float) -> float:
	return 22.0 * 0.035 * cos(x * 0.035) + 9.0 * 0.06 * cos(x * 0.06 + 1.3)


func center_ddz(x: float) -> float:
	return -22.0 * 0.035 * 0.035 * sin(x * 0.035) - 9.0 * 0.06 * 0.06 * sin(x * 0.06 + 1.3)


func half_width(x: float) -> float:
	return 4.2 + 1.0 * sin(x * 0.05 + 0.7)


## Where a point sits relative to the creek. Returns Vector4(d, e, inside, outside):
##   d = signed distance from the centerline (+ is the north / +z side)
##   e = distance beyond the water's edge (negative = in the channel)
##   inside / outside = 0..1 strength of the inside / outside of a bend at this spot
func geometry(x: float, z: float) -> Vector4:
	var dz := center_dz(x)
	var d := (z - center_z(x)) / sqrt(1.0 + dz * dz)
	var e := absf(d) - half_width(x)
	var bend := clampf(center_ddz(x) / MAX_BEND, -1.0, 1.0)
	var s := signf(d)
	return Vector4(d, e, maxf(0.0, bend * s), maxf(0.0, -bend * s))


## 0..1: how much of the old bench (ancient channel) covers this distance from the creek.
func bench_mask(d: float) -> float:
	return smoothstep(38.0, 44.0, d) * (1.0 - smoothstep(60.0, 66.0, d))


## Everything the terrain needs for one point: Vector3(height, gravel depth, bare-gravel look).
func sample(x: float, z: float) -> Vector3:
	var g := geometry(x, z)
	return Vector3(_height(x, z, g), _gravel_depth(x, z, g), _gravel_surface(g))


func height(x: float, z: float) -> float:
	return _height(x, z, geometry(x, z))


func _height(x: float, z: float, g: Vector4) -> float:
	var d := g.x
	var e := g.y
	var h: float
	if e < 0.0:
		var t := absf(d) / half_width(x)
		h = -0.85 * (1.0 - t * t)
	else:
		var slope0 := lerpf(0.22, 0.06, g.z)      # gentle gravel bar on the inside of bends
		slope0 = lerpf(slope0, 0.9, g.w)          # steep cut bank on the outside
		h = 1.3 * (1.0 - exp(-e * slope0 / 1.3))
		var rise := e - 24.0                      # valley sides climb past the floodplain
		h += 0.3 * 0.5 * (rise + sqrt(rise * rise + 16.0))
		h += _hills.get_noise_2d(x, z) * 9.0 * smoothstep(18.0, 70.0, e)
		if d > 0.0:
			h = lerpf(h, BENCH_HEIGHT + _bumps.get_noise_2d(x * 0.3, z * 0.3) * 0.4, bench_mask(d))
	return h + _bumps.get_noise_2d(x, z) * 0.1


## How deep the loose gravel goes before bedrock.
func _gravel_depth(x: float, z: float, g: Vector4) -> float:
	var e := g.y
	var depth: float
	if e < 0.0:
		depth = 0.45
	else:
		depth = lerpf(0.7 + 0.25 * g.z, 1.1, smoothstep(0.0, 20.0, e))
		depth = lerpf(depth, 0.35, g.w * (1.0 - smoothstep(0.0, 5.0, e)))   # cut banks: shallow bedrock
		depth = lerpf(depth, 0.6, smoothstep(22.0, 40.0, e))                # hills: thin soil
		if g.x > 0.0:
			depth = lerpf(depth, 1.1, bench_mask(g.x))
	return maxf(0.2, depth + _gravel_noise.get_noise_2d(x, z) * 0.15)


## 0..1: where bare gravel shows at the surface (creek bed and gravel bars).
func _gravel_surface(g: Vector4) -> float:
	if g.y < 0.0:
		return 1.0
	return 1.0 - smoothstep(0.4 + 4.0 * g.z, 1.5 + 8.0 * g.z, g.y)
