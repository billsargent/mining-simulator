extends RefCounted
## Generates the 2×2 km world from a seed and answers questions about it.
##
## The skeleton is the river network: a main river with five creeks feeding it. Land rises with
## distance from the nearest water, with hills and ridges on top, so valleys always follow the
## rivers. Near each river (within R_FINE) the channel, gravel bars and banks are shaped from
## exact distance fields. Roads follow the valleys, an old bench sits above Cabin Creek, and
## level pads hold the cabin and other landmarks.
##
## Pure data with no nodes, so generation and queries are safe on worker threads.

const SIZE := 8192.0
const FINE := 2.0            # spacing of the near-river fields (metres)
const FG := int(SIZE / FINE) + 1   # fine grid points per side
const BASE := 4.0            # spacing of the base height field
const BG := int(SIZE / BASE) + 1
const COARSE := 8.0          # spacing of the distance-to-water skeleton
const CG := int(SIZE / COARSE) + 1
const LAYOUT := SIZE / 2048.0   # the river layout was drawn for a 2 km world; scale it to SIZE
## The six regions: name, center (in 2 km layout coordinates), hill height, ridges, forest, bare ground.
## Each region shapes the land around its center and blends into its neighbors.
const REGIONS = [
	["Home Valley", Vector2(825, 1350), 1.0, 1.0, 1.0, 0.0],
	["Old Mining District", Vector2(250, 1425), 1.2, 1.3, 0.55, 0.15],
	["Foothill Benches", Vector2(1350, 1400), 0.55, 0.4, 0.3, 0.1],
	["Desert Washes", Vector2(1750, 1720), 0.45, 0.6, 0.0, 0.85],
	["Canyon Country", Vector2(1650, 560), 1.1, 2.4, 0.25, 0.35],
	["Alpine Creeks", Vector2(520, 380), 2.0, 1.6, 1.45, 0.0],
]
const RGRID := 32.0          # spacing of the region blend grid
const RG := int(SIZE / RGRID) + 1
const REGION_BLEND := 220.0   # metres (at 2 km scale) over which neighboring regions mix
const R_FINE := 30.0         # channel and bank detail out to this distance from a centerline
const R_STAMP := 34.0
const MAX_BEND := 0.045
const SPACING := 6.0         # river and road point spacing
const NO_WATER := -1.0e9

var world_seed := 1849
var rivers: Array = []       # {name, pts, wl, hw, curv, rich, main}
var roads: Array = []        # {pts, h}
var pads: Array[Vector4] = []    # x, z, radius, height
var sites := {}              # name -> {pos: Vector2, facing: Vector2}
var boulders: Array[Vector4] = []   # creek boulders: x, 0, z, radius
var progress := ""
var progress_frac := 0.0      # 0..1, read by the loading screen while generate() runs on a thread

var f_base := PackedFloat32Array()
var f_d := PackedFloat32Array()
var f_wl := PackedFloat32Array()
var f_hw := PackedFloat32Array()
var f_bend := PackedFloat32Array()
var f_rich := PackedFloat32Array()
var f_road := PackedFloat32Array()
var f_road_h := PackedFloat32Array()
var f_bench := PackedFloat32Array()
var f_bench_h := PackedFloat32Array()

var _rhills := PackedFloat32Array()   # region settings on the coarse grid
var _rridges := PackedFloat32Array()
var _rforest := PackedFloat32Array()
var _rbare := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _cwl := PackedFloat32Array()
var _chw := PackedFloat32Array()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(s: int = 1849) -> void:
	world_seed = s
	_hills.seed = s
	_hills.frequency = 0.004
	_hills.fractal_octaves = 5
	_ridges.seed = s + 7
	_ridges.frequency = 0.0025
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 4
	_forest.seed = s + 13
	_forest.frequency = 0.006
	_forest.fractal_octaves = 3
	_rng.seed = s


func generate() -> void:
	progress = "Laying out the rivers"
	_make_rivers()
	progress_frac = 0.03
	progress = "Shaping the mountains"
	_coarse_skeleton()
	progress_frac = 0.15
	_region_fields()
	progress_frac = 0.18
	_base_field()
	progress_frac = 0.45
	progress = "Carving the creeks"
	_stamp_rivers()
	progress_frac = 0.75
	progress = "Building roads"
	_make_sites_and_roads()
	progress_frac = 1.0
	progress = "Done"


# --- Queries ---------------------------------------------------------------------------

## Ground height (no digging, no micro detail).
func surface(x: float, z: float, roads_on: bool = true) -> float:
	var h := _base_at(x, z)
	var f := _fi(x, z)
	var d := _bl(f_d, f)
	if d < R_FINE:
		var floor_h := _profile(d, _bl(f_hw, f), _bl(f_wl, f), _bl(f_bend, f))
		h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
	var bw := _bl(f_bench, f)
	if bw > 0.001:
		h = lerpf(h, _bl(f_bench_h, f), bw)
	if roads_on:
		var rw := _bl(f_road, f)
		if rw > 0.001:
			h = lerpf(h, _bl(f_road_h, f), rw)
	return _apply_pads(x, z, h)


## Everything the terrain needs at a point: Vector4(height, gravel look, water level, gravel depth).
## Water level is NO_WATER away from rivers.
func sample(x: float, z: float) -> Vector4:
	var h := _base_at(x, z)
	var f := _fi(x, z)
	var d := _bl(f_d, f)
	var look := 0.0
	var wl := NO_WATER
	var gdepth := 0.6
	if d < R_FINE:
		var hw := _bl(f_hw, f)
		var bend := _bl(f_bend, f)
		var wlv := _bl(f_wl, f)
		var floor_h := _profile(d, hw, wlv, bend)
		h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
		wl = wlv
		var e := d - hw
		var inside := maxf(0.0, bend)
		look = 1.0 if e < 0.0 else 1.0 - smoothstep(0.4 + 4.0 * inside, 1.5 + 8.0 * inside, e)
		gdepth = _gravel_depth(e, inside, maxf(0.0, -bend))
	var bw := _bl(f_bench, f)
	if bw > 0.001:
		h = lerpf(h, _bl(f_bench_h, f), bw)
		gdepth = lerpf(gdepth, 1.1, bw)
	var rw := _bl(f_road, f)
	if rw > 0.001:
		h = lerpf(h, _bl(f_road_h, f), rw)
		look = maxf(look, smoothstep(0.3, 0.8, rw))
	return Vector4(_apply_pads(x, z, h), look, wl, gdepth)


## Where a point sits relative to the nearest river: Vector4(e, inside, outside, richness).
## e = distance beyond the water's edge (negative in the channel), 1e6 when far from any river.
func river_info(x: float, z: float) -> Vector4:
	var f := _fi(x, z)
	var d := _bl(f_d, f)
	if d >= R_FINE:
		return Vector4(1.0e6, 0.0, 0.0, 0.0)
	var bend := _bl(f_bend, f)
	return Vector4(d - _bl(f_hw, f), maxf(0.0, bend), maxf(0.0, -bend), _bl(f_rich, f))


func water_level(x: float, z: float) -> float:
	var f := _fi(x, z)
	if _bl(f_d, f) >= R_FINE:
		return NO_WATER
	return _bl(f_wl, f)


## Downstream direction of the nearest river (x, z).
func flow_dir(x: float, z: float) -> Vector2:
	var gx := _bl(f_wl, _fi(x + 2.0, z)) - _bl(f_wl, _fi(x - 2.0, z))
	var gz := _bl(f_wl, _fi(x, z + 2.0)) - _bl(f_wl, _fi(x, z - 2.0))
	var g := Vector2(-gx, -gz)
	return g.normalized() if g.length() > 1e-5 else Vector2(1, 0)


func road_weight(x: float, z: float) -> float:
	return _bl(f_road, _fi(x, z))


func bench_weight(x: float, z: float) -> float:
	return _bl(f_bench, _fi(x, z))


func forest(x: float, z: float) -> float:
	var r := _region_at(_rforest, x, z) if not _rforest.is_empty() else 1.0
	return (_forest.get_noise_2d(x, z) * 0.5 + 0.5) * r


## How much bare sand or dirt shows (0 = all grass, 1 = desert).
func bare(x: float, z: float) -> float:
	return _region_at(_rbare, x, z) if not _rbare.is_empty() else 0.0


## How much each region counts at a point (the weights add up to 1).
static func region_weights(x: float, z: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(REGIONS.size())
	var dmin := 1.0e9
	for i in REGIONS.size():
		d[i] = ((REGIONS[i][1] as Vector2) * LAYOUT).distance_to(Vector2(x, z))
		dmin = minf(dmin, d[i])
	var total := 0.0
	for i in d.size():
		d[i] = exp(-(d[i] - dmin) / (REGION_BLEND * LAYOUT * 0.35))
		total += d[i]
	for i in d.size():
		d[i] /= total
	return d


## A region setting (2 hills, 3 ridges, 4 forest) blended at a point.
static func region_mix(x: float, z: float, field: int) -> float:
	var w := region_weights(x, z)
	var v := 0.0
	for i in w.size():
		v += w[i] * float(REGIONS[i][field])
	return v


## Which region a point is in.
static func region_at(x: float, z: float) -> int:
	var w := region_weights(x, z)
	var best := 0
	for i in w.size():
		if w[i] > w[best]:
			best = i
	return best


static func region_name(x: float, z: float) -> String:
	return REGIONS[region_at(x, z)][0]


func in_pad(x: float, z: float, margin: float) -> bool:
	for p in pads:
		if Vector2(x - p.x, z - p.y).length() < p.z + margin:
			return true
	return false


func river_by_name(n: String) -> Dictionary:
	for r in rivers:
		if r["name"] == n:
			return r
	return {}


## A point across a river at fraction t along it: frac 0 = centerline, 1 = water's edge, sign = side.
func river_point(river_name: String, t: float, frac: float) -> Vector2:
	var r := river_by_name(river_name)
	var pts: PackedVector2Array = r["pts"]
	var hw: PackedFloat32Array = r["hw"]
	var i := clampi(int(t * (pts.size() - 1)), 1, pts.size() - 2)
	var dir := (pts[i + 1] - pts[i - 1]).normalized()
	return pts[i] + Vector2(-dir.y, dir.x) * frac * hw[i]


## A top-down picture of the world for the map: relief shading, contours, rivers, roads, forest.
func make_map_image(px: int) -> Image:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGB8)
	var cell := SIZE / px
	var hs := PackedFloat32Array()
	hs.resize(px * px)
	for j in px:
		for i in px:
			hs[j * px + i] = surface((i + 0.5) * cell, (j + 0.5) * cell)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	for j in px:
		for i in px:
			var k := j * px + i
			var x := (i + 0.5) * cell
			var z := (j + 0.5) * cell
			var h := hs[k]
			var hr := hs[k + 1] if i < px - 1 else h
			var hd := hs[k + px] if j < px - 1 else h
			var n := Vector3(-(hr - h) / cell, 1.0, -(hd - h) / cell).normalized()
			var shade := clampf(0.55 + 0.6 * n.dot(light), 0.45, 1.15)
			var c := _height_color(h)
			var f := _fi(x, z)
			var d := _bl(f_d, f)
			if forest(x, z) > 0.55 and d > R_FINE * 0.5:
				c = c.lerp(Color(0.32, 0.43, 0.29), 0.5)
			c = c * shade
			if floori(h / 10.0) != floori(hr / 10.0) or floori(h / 10.0) != floori(hd / 10.0):
				c = c.darkened(0.22)
			if _bl(f_road, f) > 0.55:
				c = Color(0.8, 0.7, 0.5)
			if d < _bl(f_hw, f) + 1.0:
				c = Color(0.3, 0.48, 0.62)
			c.a = 1.0
			img.set_pixel(i, j, c)
	return img


func _height_color(h: float) -> Color:
	var stops := [[40.0, Color(0.56, 0.63, 0.43)], [90.0, Color(0.67, 0.65, 0.47)],
		[160.0, Color(0.63, 0.58, 0.5)], [240.0, Color(0.77, 0.75, 0.72)]]
	if h <= stops[0][0]:
		return stops[0][1]
	for s in range(1, stops.size()):
		if h <= stops[s][0]:
			var t: float = (h - stops[s - 1][0]) / (stops[s][0] - stops[s - 1][0])
			return (stops[s - 1][1] as Color).lerp(stops[s][1], t)
	return stops[stops.size() - 1][1]


# --- Field helpers ---------------------------------------------------------------------

func _fi(x: float, z: float) -> Vector3:
	var fx := clampf(x / FINE, 0.0, FG - 1.001)
	var fz := clampf(z / FINE, 0.0, FG - 1.001)
	var i := int(fx)
	var j := int(fz)
	return Vector3(j * FG + i, fx - i, fz - j)


func _bl(a: PackedFloat32Array, f: Vector3) -> float:
	var k := int(f.x)
	return lerpf(lerpf(a[k], a[k + 1], f.y), lerpf(a[k + FG], a[k + FG + 1], f.y), f.z)


func _base_at(x: float, z: float) -> float:
	var bx := clampf(x / BASE, 0.0, BG - 1.001)
	var bz := clampf(z / BASE, 0.0, BG - 1.001)
	var i := int(bx)
	var j := int(bz)
	var tx := bx - i
	var tz := bz - j
	var k := j * BG + i
	return lerpf(lerpf(f_base[k], f_base[k + 1], tx), lerpf(f_base[k + BG], f_base[k + BG + 1], tx), tz)


func _coarse_at(a: PackedFloat32Array, x: float, z: float) -> float:
	var cx := clampf(x / COARSE, 0.0, CG - 1.001)
	var cz := clampf(z / COARSE, 0.0, CG - 1.001)
	var i := int(cx)
	var j := int(cz)
	var tx := cx - i
	var tz := cz - j
	var k := j * CG + i
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + CG], a[k + CG + 1], tx), tz)


## Cross-section of a river: channel below the water, then a bank that rises gently on the
## inside of a bend (gravel bar) and steeply on the outside (cut bank).
func _profile(d: float, hw: float, wl: float, bend: float) -> float:
	var e := d - hw
	if e < 0.0:
		var t := d / hw
		return wl - 0.08 - (0.55 + 0.05 * hw) * (1.0 - t * t)
	var slope0 := lerpf(lerpf(0.22, 0.06, maxf(0.0, bend)), 0.9, maxf(0.0, -bend))
	return wl - 0.08 + 1.3 * (1.0 - exp(-e * slope0 / 1.3))


func _gravel_depth(e: float, inside: float, outside: float) -> float:
	if e < 0.0:
		return 0.45
	var depth := lerpf(0.7 + 0.25 * inside, 1.1, smoothstep(0.0, 20.0, e))
	depth = lerpf(depth, 0.35, outside * (1.0 - smoothstep(0.0, 5.0, e)))
	return lerpf(depth, 0.6, smoothstep(22.0, 40.0, e))


func _apply_pads(x: float, z: float, h: float) -> float:
	for p in pads:
		var dx := x - p.x
		var dz := z - p.y
		var dd := dx * dx + dz * dz
		if dd < p.z * p.z:
			h = lerpf(h, p.w, 1.0 - smoothstep(p.z - maxf(4.0, p.z * 0.3), p.z, sqrt(dd)))
	return h


# --- Generation ------------------------------------------------------------------------

func _make_rivers() -> void:
	var main := _river("Big Sable River", Vector2(-30, 1000 * LAYOUT), Vector2(SIZE + 30, 1070 * LAYOUT), 64.0, 44.0, 8.0, 9.5, 0.5, 70.0, 1.0, true)
	rivers.append(main)
	# name, source, x of the junction on the main river, richness, gradient, meander
	var creeks := [
		["Cabin Creek", Vector2(780, 1780), 840.0, 1.0, 0.04, 26.0],
		["Rattlesnake Gulch", Vector2(240, 1830), 360.0, 1.15, 0.055, 18.0],
		["Last Chance Creek", Vector2(1860, 1890), 1640.0, 1.7, 0.05, 22.0],
		["Willow Creek", Vector2(430, 210), 520.0, 0.8, 0.035, 30.0],
		["Tamarack Creek", Vector2(1310, 180), 1250.0, 1.25, 0.045, 24.0],
	]
	var mpts: PackedVector2Array = main["pts"]
	var mwl: PackedFloat32Array = main["wl"]
	for c in creeks:
		var best := 0
		for i in mpts.size():
			if absf(mpts[i].x - float(c[2]) * LAYOUT) < absf(mpts[best].x - float(c[2]) * LAYOUT):
				best = i
		var mouth := mpts[best]
		var source: Vector2 = (c[1] as Vector2) * LAYOUT
		var length: float = (mouth - source).length()
		var wl_mouth := mwl[best]
		# Gradients are divided by the scale, so creeks climb as high as they did at 2 km.
		rivers.append(_river(c[0], source, mouth, wl_mouth + float(c[4]) / LAYOUT * length, wl_mouth, 2.6, 4.6, c[3], c[5], 1.4, false))


func _river(n: String, a: Vector2, b: Vector2, wl_a: float, wl_b: float, hw_a: float, hw_b: float,
		rich: float, meander: float, wl_curve: float, is_main: bool) -> Dictionary:
	var length := a.distance_to(b)
	var fwd := (b - a) / length
	var nrm := Vector2(-fwd.y, fwd.x)
	var count := maxi(3, int(length / SPACING) + 1)
	var phases := [_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU]
	var waves := [length / _rng.randf_range(2.0, 2.8), length / _rng.randf_range(4.5, 6.0), length / _rng.randf_range(9.0, 12.0)]
	var amps := [meander, meander * 0.45, meander * 0.2]
	var pts := PackedVector2Array()
	var wl := PackedFloat32Array()
	var hw := PackedFloat32Array()
	for s in count:
		var t := float(s) / (count - 1)
		var env := 1.0 if is_main else pow(sin(PI * t), 0.6)
		var off := 0.0
		for k in 3:
			off += float(amps[k]) * sin(TAU * t * length / float(waves[k]) + float(phases[k]))
		pts.append(a.lerp(b, t) + nrm * off * env)
		wl.append(wl_b + (wl_a - wl_b) * pow(1.0 - t, wl_curve))
		hw.append(lerpf(hw_a, hw_b, t))
	return {"name": n, "pts": pts, "wl": wl, "hw": hw, "curv": _curvature(pts), "rich": rich, "main": is_main}


func _curvature(pts: PackedVector2Array) -> PackedFloat32Array:
	var n := pts.size()
	var c := PackedFloat32Array()
	c.resize(n)
	c.fill(0.0)
	for i in range(1, n - 1):
		var a := (pts[i] - pts[i - 1]).normalized()
		var b := (pts[i + 1] - pts[i]).normalized()
		var seg := maxf((pts[i + 1] - pts[i - 1]).length() * 0.5, 0.01)
		c[i] = atan2(a.x * b.y - a.y * b.x, a.dot(b)) / seg
	for pass_i in 3:
		var sm := c.duplicate()
		for i in range(1, n - 1):
			var acc := 0.0
			var cnt := 0
			for o in range(-3, 4):
				var k := i + o
				if k >= 0 and k < n:
					acc += c[k]
					cnt += 1
			sm[i] = acc / cnt
		c = sm
	return c


## Distance to the nearest river (and its water level and width) on a coarse grid, by
## propagating the nearest river point across the grid in two sweeps.
func _coarse_skeleton() -> void:
	var n := CG
	var total := n * n
	var sx := PackedFloat32Array()
	var sz := PackedFloat32Array()
	var swl := PackedFloat32Array()
	var shw := PackedFloat32Array()
	var dist := PackedFloat32Array()
	sx.resize(total)
	sz.resize(total)
	swl.resize(total)
	shw.resize(total)
	dist.resize(total)
	sx.fill(-1.0e7)
	sz.fill(-1.0e7)
	swl.fill(0.0)
	shw.fill(4.0)
	dist.fill(1.0e18)
	for r in rivers:
		var pts: PackedVector2Array = r["pts"]
		var wl: PackedFloat32Array = r["wl"]
		var hw: PackedFloat32Array = r["hw"]
		for s in pts.size():
			var p := pts[s]
			var i := clampi(roundi(p.x / COARSE), 0, n - 1)
			var j := clampi(roundi(p.y / COARSE), 0, n - 1)
			var k := j * n + i
			var dx := i * COARSE - p.x
			var dz := j * COARSE - p.y
			var d2 := dx * dx + dz * dz
			if d2 < dist[k]:
				dist[k] = d2
				sx[k] = p.x
				sz[k] = p.y
				swl[k] = wl[s]
				shw[k] = hw[s]
	var sweeps := [[Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]]
	for pass_i in 2:
		var offs: Array = sweeps[pass_i]
		for jj in n:
			var j := jj if pass_i == 0 else n - 1 - jj
			for ii in n:
				var i := ii if pass_i == 0 else n - 1 - ii
				var k := j * n + i
				var px := i * COARSE
				var pz := j * COARSE
				for o: Vector2i in offs:
					var ni := i + o.x
					var nj := j + o.y
					if ni < 0 or nj < 0 or ni >= n or nj >= n:
						continue
					var nk := nj * n + ni
					if sx[nk] < -1.0e6:
						continue
					var dx := px - sx[nk]
					var dz := pz - sz[nk]
					var d2 := dx * dx + dz * dz
					if d2 < dist[k]:
						dist[k] = d2
						sx[k] = sx[nk]
						sz[k] = sz[nk]
						swl[k] = swl[nk]
						shw[k] = shw[nk]
	_cd.resize(total)
	for k in total:
		_cd[k] = sqrt(dist[k])
	# Blur level and width so valleys of different rivers meet in smooth ridges, not cliffs.
	_cwl = _blur(swl, n, 6, 2)
	_chw = _blur(shw, n, 6, 2)


func _blur(src: PackedFloat32Array, n: int, r: int, iterations: int) -> PackedFloat32Array:
	var a := src.duplicate()
	var tmp := PackedFloat32Array()
	tmp.resize(n * n)
	var win := float(2 * r + 1)
	for it in iterations:
		for j in n:
			var row := j * n
			var acc := 0.0
			for i in range(-r, r + 1):
				acc += a[row + clampi(i, 0, n - 1)]
			for i in n:
				tmp[row + i] = acc / win
				acc += a[row + clampi(i + r + 1, 0, n - 1)] - a[row + clampi(i - r, 0, n - 1)]
		for i in n:
			var acc := 0.0
			for j in range(-r, r + 1):
				acc += tmp[clampi(j, 0, n - 1) * n + i]
			for j in n:
				a[j * n + i] = acc / win
				acc += tmp[clampi(j + r + 1, 0, n - 1) * n + i] - tmp[clampi(j - r, 0, n - 1) * n + i]
	return a


## Land shape away from the channels: rises with distance from water, plus hills and ridges.
func _region_at(a: PackedFloat32Array, x: float, z: float) -> float:
	var cx := clampf(x / RGRID, 0.0, RG - 1.001)
	var cz := clampf(z / RGRID, 0.0, RG - 1.001)
	var i := int(cx)
	var j := int(cz)
	var tx := cx - i
	var tz := cz - j
	var k := j * RG + i
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + RG], a[k + RG + 1], tx), tz)


## Blend the region settings once, on their own coarse grid.
func _region_fields() -> void:
	_rhills.resize(RG * RG)
	_rridges.resize(RG * RG)
	_rforest.resize(RG * RG)
	_rbare.resize(RG * RG)
	for j in RG:
		for i in RG:
			var w := region_weights(i * RGRID, j * RGRID)
			var hv := 0.0
			var rv := 0.0
			var fv := 0.0
			var bv := 0.0
			for r in w.size():
				hv += w[r] * float(REGIONS[r][2])
				rv += w[r] * float(REGIONS[r][3])
				fv += w[r] * float(REGIONS[r][4])
				bv += w[r] * float(REGIONS[r][5])
			var k := j * RG + i
			_rhills[k] = hv
			_rridges[k] = rv
			_rforest[k] = fv
			_rbare[k] = bv


func _base_field() -> void:
	f_base.resize(BG * BG)
	for j in BG:
		if j % 32 == 0:
			progress_frac = lerpf(0.18, 0.45, float(j) / BG)
		for i in BG:
			var x := i * BASE
			var z := j * BASE
			var d := _coarse_at(_cd, x, z)
			var wl := _coarse_at(_cwl, x, z)
			var hw := _coarse_at(_chw, x, z)
			var dp := maxf(0.0, d - (14.0 + 5.0 * hw))
			var rise := 60.0 * (1.0 - exp(-dp / 200.0)) + 0.1 * dp
			var hills := _region_at(_rhills, x, z)
			var ridges := _region_at(_rridges, x, z)
			var amp := minf(1.5 + 0.22 * dp, 80.0) * hills
			var ridge := minf(0.12 * dp, 50.0) * ridges * (_ridges.get_noise_2d(x, z) * 0.5 + 0.5)
			f_base[j * BG + i] = wl + 1.4 + rise * lerpf(1.0, hills, 0.6) + _hills.get_noise_2d(x, z) * amp + ridge


## Exact distance, water level, width and bend for every fine cell near a river.
func _stamp_rivers() -> void:
	var total := FG * FG
	f_d.resize(total)
	f_wl.resize(total)
	f_hw.resize(total)
	f_bend.resize(total)
	f_rich.resize(total)
	f_d.fill(R_STAMP)
	f_bend.fill(0.0)
	f_rich.fill(0.0)
	for ri in rivers.size():
		progress_frac = lerpf(0.45, 0.72, float(ri) / rivers.size())
		var r: Dictionary = rivers[ri]
		var pts: PackedVector2Array = r["pts"]
		var wl: PackedFloat32Array = r["wl"]
		var hw: PackedFloat32Array = r["hw"]
		var curv: PackedFloat32Array = r["curv"]
		var rich: float = r["rich"]
		for s in pts.size() - 1:
			var a := pts[s]
			var ab := pts[s + 1] - a
			var len2 := maxf(ab.length_squared(), 1e-6)
			var i0 := maxi(0, floori((minf(a.x, a.x + ab.x) - R_STAMP) / FINE))
			var i1 := mini(FG - 1, ceili((maxf(a.x, a.x + ab.x) + R_STAMP) / FINE))
			var j0 := maxi(0, floori((minf(a.y, a.y + ab.y) - R_STAMP) / FINE))
			var j1 := mini(FG - 1, ceili((maxf(a.y, a.y + ab.y) + R_STAMP) / FINE))
			for j in range(j0, j1 + 1):
				var pz := j * FINE
				for i in range(i0, i1 + 1):
					var px := i * FINE
					var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
					var qx := a.x + ab.x * t
					var qz := a.y + ab.y * t
					var d := sqrt((px - qx) * (px - qx) + (pz - qz) * (pz - qz))
					var k := j * FG + i
					if d < f_d[k]:
						f_d[k] = d
						f_wl[k] = lerpf(wl[s], wl[s + 1], t)
						f_hw[k] = lerpf(hw[s], hw[s + 1], t)
						var side := signf(ab.x * (pz - a.y) - ab.y * (px - a.x))
						f_bend[k] = clampf(lerpf(curv[s], curv[s + 1], t) / MAX_BEND, -1.0, 1.0) * side
						f_rich[k] = rich
	# Cells no river reached get the coarse level and width, so blending near the edge stays sane.
	for j in FG:
		for i in FG:
			var k := j * FG + i
			if f_d[k] >= R_STAMP:
				f_wl[k] = _coarse_at(_cwl, i * FINE, j * FINE)
				f_hw[k] = _coarse_at(_chw, i * FINE, j * FINE)


func _make_sites_and_roads() -> void:
	sites["base"] = _site_beside("Cabin Creek", 0.55, 1.0, 26.0)
	sites["camp"] = _site_beside("Last Chance Creek", 0.4, -1.0, 24.0)
	sites["mine"] = _site_beside("Rattlesnake Gulch", 0.55, -1.0, 52.0)
	# The town sits on the valley road, east of where Cabin Creek comes in.
	sites["town"] = _site_beside("Big Sable River", 0.51, 1.0, 66.0)
	var total := FG * FG
	f_bench.resize(total)
	f_bench_h.resize(total)
	f_road.resize(total)
	f_road_h.resize(total)
	f_bench.fill(0.0)
	f_bench_h.fill(0.0)
	f_road.fill(0.0)
	f_road_h.fill(0.0)
	# The old bench: an ancient channel 50 m up the cabin side of Cabin Creek.
	var cabin := river_by_name("Cabin Creek")
	var bench := _offset_path(cabin, 0.16, 0.42, 50.0)
	var bench_h := PackedFloat32Array()
	for p in bench:
		bench_h.append(water_level_near(cabin, p) + 9.5)
	_stamp_band(bench, bench_h, 7.0, 13.0, "bench")
	# Roads follow the valleys, offset from the water.
	var main: Dictionary = rivers[0]
	var paths := [
		_offset_path(cabin, 0.42, 0.93, 16.0),
		_offset_path(main, 0.03, 0.97, 40.0),
		_offset_path(river_by_name("Last Chance Creek"), 0.92, 0.36, -16.0),
		_offset_path(river_by_name("Tamarack Creek"), 0.95, 0.4, 16.0),
	]
	# A ford across the main river from the valley road to the Tamarack road.
	var tam: PackedVector2Array = paths[3]
	var valley: PackedVector2Array = paths[1]
	var near := 0
	for i in valley.size():
		if valley[i].distance_to(tam[0]) < valley[near].distance_to(tam[0]):
			near = i
	var ford := PackedVector2Array()
	for s in 13:
		ford.append(valley[near].lerp(tam[0], s / 12.0))
	paths.append(ford)
	for path: PackedVector2Array in paths:
		var hs := PackedFloat32Array()
		for p in path:
			hs.append(surface(p.x, p.y, false))
		hs = _smooth_values(_smooth_values(hs, 5), 5)
		for i in path.size():
			var wl := water_level(path[i].x, path[i].y)
			if wl > NO_WATER * 0.5 and river_info(path[i].x, path[i].y).x < 1.5:
				hs[i] = clampf(hs[i], wl - 0.45, wl - 0.25)   # fords: always under water, never deep
		roads.append({"pts": path, "h": hs})
		_stamp_band(path, hs, 2.6, 8.0, "road")
	# Level pads for the cabin and landmarks (applied last, over roads).
	for s in [["base", 13.0], ["camp", 10.0], ["mine", 6.0], ["town", 34.0]]:
		var site: Dictionary = sites[s[0]]
		var pos: Vector2 = site["pos"]
		var height := surface(pos.x, pos.y)
		if s[0] == "town":
			# The town is cut into the hillside at the level of the valley road in front of it.
			var road: Dictionary = roads[1]
			var rp: PackedVector2Array = road["pts"]
			var near_i := 0
			for i in rp.size():
				if rp[i].distance_squared_to(pos) < rp[near_i].distance_squared_to(pos):
					near_i = i
			height = (road["h"] as PackedFloat32Array)[near_i] + 0.05
		site["height"] = height
		pads.append(Vector4(pos.x, pos.y, float(s[1]), height))
	# Boulders in and beside the creeks (they trap gold just downstream).
	for r in rivers:
		var pts: PackedVector2Array = r["pts"]
		var hw: PackedFloat32Array = r["hw"]
		var i := _rng.randi_range(2, 8)
		while i < pts.size() - 2:
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var p := pts[i] + Vector2(-dir.y, dir.x) * _rng.randf_range(-0.85, 0.85) * hw[i]
			var radius := _rng.randf_range(0.5, 1.2) if r["main"] else _rng.randf_range(0.35, 0.9)
			if not in_pad(p.x, p.y, 2.0):
				boulders.append(Vector4(p.x, 0.0, p.y, radius))
			i += _rng.randi_range(3, 8)


func water_level_near(r: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = r["pts"]
	var wl: PackedFloat32Array = r["wl"]
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = i
	return wl[best]


func _site_beside(river_name: String, t: float, side: float, dist: float) -> Dictionary:
	var r := river_by_name(river_name)
	var pts: PackedVector2Array = r["pts"]
	var i := clampi(int(t * (pts.size() - 1)), 1, pts.size() - 2)
	var dir := (pts[i + 1] - pts[i - 1]).normalized()
	var nrm := Vector2(-dir.y, dir.x) * side
	return {"pos": pts[i] + nrm * dist, "facing": -nrm, "river": river_name}


## A smooth path running alongside a river between fractions t0 and t1 (either direction),
## offset sideways (positive = left of the downstream direction).
func _offset_path(r: Dictionary, t0: float, t1: float, offset: float) -> PackedVector2Array:
	var pts := _smooth_path(r["pts"], 6)
	var n := pts.size()
	var i0 := clampi(int(t0 * (n - 1)), 0, n - 1)
	var i1 := clampi(int(t1 * (n - 1)), 0, n - 1)
	var step := 1 if i1 >= i0 else -1
	var out := PackedVector2Array()
	for i in range(i0, i1 + step, step):
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		out.append(pts[i] + Vector2(-dir.y, dir.x) * offset)
	return _smooth_path(out, 3)


func _smooth_path(pts: PackedVector2Array, win: int) -> PackedVector2Array:
	var n := pts.size()
	var out := pts.duplicate()
	for i in range(1, n - 1):
		var acc := Vector2.ZERO
		var cnt := 0
		for o in range(-win, win + 1):
			var k := i + o
			if k >= 0 and k < n:
				acc += pts[k]
				cnt += 1
		out[i] = acc / cnt
	return out


func _smooth_values(v: PackedFloat32Array, win: int) -> PackedFloat32Array:
	var n := v.size()
	var out := v.duplicate()
	for i in n:
		var acc := 0.0
		var cnt := 0
		for o in range(-win, win + 1):
			var k := i + o
			if k >= 0 and k < n:
				acc += v[k]
				cnt += 1
		out[i] = acc / cnt
	return out


## Stamp a band along a path into the road or bench fields (the strongest weight wins).
## (Packed arrays are copied when passed, so this picks its target fields by name.)
func _stamp_band(path: PackedVector2Array, hs: PackedFloat32Array, inner: float, outer: float, target: String) -> void:
	var f_w: PackedFloat32Array = f_road if target == "road" else f_bench
	var f_h: PackedFloat32Array = f_road_h if target == "road" else f_bench_h
	for s in path.size() - 1:
		var a := path[s]
		var ab := path[s + 1] - a
		var len2 := maxf(ab.length_squared(), 1e-6)
		# Heights are also written just outside the band (weight 0), because heights and
		# weights are interpolated separately: a blank height next to the band would drag
		# the blended ground toward zero and punch pits along the edge.
		var reach := outer + FINE * 3.0
		var i0 := maxi(0, floori((minf(a.x, a.x + ab.x) - reach) / FINE))
		var i1 := mini(FG - 1, ceili((maxf(a.x, a.x + ab.x) + reach) / FINE))
		var j0 := maxi(0, floori((minf(a.y, a.y + ab.y) - reach) / FINE))
		var j1 := mini(FG - 1, ceili((maxf(a.y, a.y + ab.y) + reach) / FINE))
		for j in range(j0, j1 + 1):
			var pz := j * FINE
			for i in range(i0, i1 + 1):
				var px := i * FINE
				var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
				var dx := px - (a.x + ab.x * t)
				var dz := pz - (a.y + ab.y * t)
				var w := 1.0 - smoothstep(inner, outer, sqrt(dx * dx + dz * dz))
				var k := j * FG + i
				if w > f_w[k] or (f_w[k] <= 0.0 and f_h[k] == 0.0):
					f_w[k] = w
					f_h[k] = lerpf(hs[s], hs[s + 1], t)
	if target == "road":
		f_road = f_w
		f_road_h = f_h
	else:
		f_bench = f_w
		f_bench_h = f_h
