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

const Garnets = preload("res://scripts/gold/garnets.gd")
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
var _town_pad := Vector4.ZERO    # the town's pad, which is bare street rather than grass
var sites := {}              # name -> {pos: Vector2, facing: Vector2}
var boulders: Array[Vector4] = []   # creek boulders: x, 0, z, radius
var progress := ""
var progress_frac := 0.0      # 0..1, read by the loading screen while generate() runs on a thread

# Detail near rivers, roads and the bench lives in 64 m tiles, built the first time something
# asks about that ground (see _fi). Away from them the land is the plain base formula.
const TILE_M := 64.0
const TP := 33                 # points per tile side (2 m apart, edges shared)
const FD := 0                  # distance to the nearest river centerline
const FWL := 1                 # water level of that river
const FHW := 2                 # its half width
const FBEND := 3               # how hard it bends here (signed)
const FRICH := 4               # its richness (negative for a dry wash)
const FROAD := 5
const FROADH := 6
const FBENCH := 7
const FBENCHH := 8
const FIELDS := 9

var _tiles := {}               # Vector2i -> Array of FIELDS PackedFloat32Array
var _tile_mutex := Mutex.new()
var _river_index := {}         # tile -> Array of Vector2i(river, segment) that reach it
var _band_index := {}          # tile -> Array of Vector2i(band, segment) that reach it
var _bands: Array = []         # [path, heights, inner, outer, is_road]
var _cnear := PackedByteArray()   # coarse grid: 1 where rivers or bands change the land
var _empty_tile: Array = []
var tiles_built := 0

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
	progress_frac = 0.45
	progress = "Carving the creeks"
	_stamp_rivers()
	progress_frac = 0.75
	progress = "Building roads"
	_make_sites_and_roads()
	# Garnet Beach: a bare gravel bar on an inside bend of the big river (see garnets.gd).
	_beach = Garnets.find_beach(self)
	sites["garnet"] = {"pos": _beach}
	progress = "Leaving things by the roads"
	_make_places()
	_make_shafts()
	progress_frac = 1.0
	progress = "Done"


# --- Queries ---------------------------------------------------------------------------

## Ground height (no digging, no micro detail).
func surface(x: float, z: float, roads_on: bool = true) -> float:
	var h := _base_at(x, z)
	var f := _fi(x, z)
	var d := _bl(f, FD)
	if d < R_FINE:
		var floor_h := _profile(d, _bl(f, FHW), _bl(f, FWL), _bl(f, FBEND))
		h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
	var bw := _bl(f, FBENCH)
	if bw > 0.001:
		h = lerpf(h, _bl(f, FBENCHH), bw)
	if roads_on:
		var rw := _bl(f, FROAD)
		if rw > 0.001:
			h = lerpf(h, _bl(f, FROADH), rw)
	return _apply_pads(x, z, h)


## Everything the terrain needs at a point: Vector4(height, gravel look, water level, gravel depth).
## Water level is NO_WATER away from rivers.
func sample(x: float, z: float) -> Vector4:
	var h := _base_at(x, z)
	var f := _fi(x, z)
	var d := _bl(f, FD)
	var look := 0.0
	var wl := NO_WATER
	var gdepth := 0.6
	if d < R_FINE:
		var hw := _bl(f, FHW)
		var bend := _bl(f, FBEND)
		var wlv := _bl(f, FWL)
		var floor_h := _profile(d, hw, wlv, bend)
		h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
		wl = wlv if _bl(f, FRICH) >= 0.0 else NO_WATER
		var e := d - hw
		var inside := maxf(0.0, bend)
		look = 1.0 if e < 0.0 else 1.0 - smoothstep(0.4 + 4.0 * inside, 1.5 + 8.0 * inside, e)
		gdepth = _gravel_depth(e, inside, maxf(0.0, -bend))
	var bw := _bl(f, FBENCH)
	if bw > 0.001:
		h = lerpf(h, _bl(f, FBENCHH), bw)
		gdepth = lerpf(gdepth, 1.1, bw)
	var rw := _bl(f, FROAD)
	if rw > 0.001:
		h = lerpf(h, _bl(f, FROADH), rw)
		# The bare track's edge wanders, so grass creeps onto the shoulders in patches.
		var rag := 0.5 + 0.5 * sin(x * 0.31 + z * 0.13) * sin(z * 0.27 - x * 0.19 + 1.7)
		var t0 := 0.42 + 0.33 * rag
		look = maxf(look, smoothstep(t0, t0 + 0.15, rw))
	look = maxf(look, _street(x, z))
	if _beach != Vector2.ZERO and absf(x - _beach.x) < Garnets.BEACH_RADIUS and absf(z - _beach.y) < Garnets.BEACH_RADIUS:
		var bd := Vector2(x, z).distance_to(_beach)
		var be := d - _bl(f, FHW)
		if bd < Garnets.BEACH_RADIUS and be < 12.0:
			look = maxf(look, (1.0 - smoothstep(Garnets.BEACH_RADIUS * 0.7, Garnets.BEACH_RADIUS, bd)) * (1.0 - smoothstep(7.0, 12.0, be)))
	return Vector4(_apply_pads(x, z, h), look, wl, gdepth)


var _beach := Vector2.ZERO


## The town's packed-dirt street and yard: bare ground over the town pad, fading at its edge.
func _street(x: float, z: float) -> float:
	if _town_pad.z <= 0.0:
		return 0.0
	var d := Vector2(x - _town_pad.x, z - _town_pad.y).length()
	return 1.0 - smoothstep(_town_pad.z - 10.0, _town_pad.z - 3.0, d)


## Where a point sits relative to the nearest river: Vector4(e, inside, outside, richness).
## e = distance beyond the water's edge (negative in the channel), 1e6 when far from any river.
func river_info(x: float, z: float) -> Vector4:
	var f := _fi(x, z)
	var d := _bl(f, FD)
	if d >= R_FINE:
		return Vector4(1.0e6, 0.0, 0.0, 0.0)
	var bend := _bl(f, FBEND)
	return Vector4(d - _bl(f, FHW), maxf(0.0, bend), maxf(0.0, -bend), absf(_bl(f, FRICH)))


func water_level(x: float, z: float) -> float:
	var f := _fi(x, z)
	if _bl(f, FD) >= R_FINE or _bl(f, FRICH) < 0.0:
		return NO_WATER
	return _bl(f, FWL)


## Downstream direction of the nearest river (x, z).
func flow_dir(x: float, z: float) -> Vector2:
	var gx := _bl(_fi(x + 2.0, z), FWL) - _bl(_fi(x - 2.0, z), FWL)
	var gz := _bl(_fi(x, z + 2.0), FWL) - _bl(_fi(x, z - 2.0), FWL)
	var g := Vector2(-gx, -gz)
	return g.normalized() if g.length() > 1e-5 else Vector2(1, 0)


func road_weight(x: float, z: float) -> float:
	return _bl(_fi(x, z), FROAD)


func bench_weight(x: float, z: float) -> float:
	return _bl(_fi(x, z), FBENCH)


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
	if not _spots.is_empty():
		var c := Vector2i(floori(x / SPOT_CELL), floori(z / SPOT_CELL))
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for p: Vector4 in _spots.get(c + Vector2i(di, dj), []):
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
	# Built from the coarse data only, so drawing the map never forces detail tiles to exist.
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGB8)
	var cell := SIZE / px
	var hs := PackedFloat32Array()
	hs.resize(px * px)
	var ds := PackedFloat32Array()
	ds.resize(px * px)
	for j in px:
		for i in px:
			var x := (i + 0.5) * cell
			var z := (j + 0.5) * cell
			var d := _coarse_at(_cd, x, z)
			var h := _base_at(x, z)
			if d < R_FINE:
				var floor_h := _profile(d, _coarse_at(_chw, x, z), _coarse_at(_cwl, x, z), 0.0)
				h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
			hs[j * px + i] = _apply_pads(x, z, h)
			ds[j * px + i] = d - _coarse_at(_chw, x, z)
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
			if forest(x, z) > 0.55 and ds[k] > R_FINE * 0.5:
				c = c.lerp(Color(0.32, 0.43, 0.29), 0.5)
			c = c * shade
			if floori(h / 10.0) != floori(hr / 10.0) or floori(h / 10.0) != floori(hd / 10.0):
				c = c.darkened(0.22)
			c.a = 1.0
			img.set_pixel(i, j, c)
	# Roads, then water (dry washes as gravel), drawn along their lines.
	for road in roads:
		_draw_line(img, road["pts"], cell, Color(0.8, 0.7, 0.5), 1)
	for r in rivers:
		var col := Color(0.62, 0.58, 0.5) if r.get("dry", false) else Color(0.3, 0.48, 0.62)
		_draw_line(img, r["pts"], cell, col, 1 if not r["main"] else 2)
	return img


func _draw_line(img: Image, pts: PackedVector2Array, cell: float, col: Color, width: int) -> void:
	var px := img.get_width()
	for p in pts:
		var ci := int(p.x / cell)
		var cj := int(p.y / cell)
		for dj in range(-width + 1, width):
			for di in range(-width + 1, width):
				if ci + di >= 0 and cj + dj >= 0 and ci + di < px and cj + dj < px:
					img.set_pixel(ci + di, cj + dj, col)


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

## Where a point sits in its detail tile: [tile fields, Vector3(index, fx, fz)].
## Ground nothing has changed gets a shared empty tile, so most of the world needs none.
func _fi(x: float, z: float) -> Array:
	if not _near(x, z):
		return [_empty_tile, Vector3.ZERO]
	var key := Vector2i(clampi(floori(x / TILE_M), 0, int(SIZE / TILE_M) - 1), clampi(floori(z / TILE_M), 0, int(SIZE / TILE_M) - 1))
	_tile_mutex.lock()
	var t = _tiles.get(key)
	_tile_mutex.unlock()
	if t == null:
		var built := _build_tile(key)
		_tile_mutex.lock()
		t = _tiles.get(key)
		if t == null:
			_tiles[key] = built
			tiles_built += 1
			t = built
		_tile_mutex.unlock()
	var fx := clampf((x - key.x * TILE_M) / FINE, 0.0, TP - 1.001)
	var fz := clampf((z - key.y * TILE_M) / FINE, 0.0, TP - 1.001)
	var i := int(fx)
	var j := int(fz)
	return [t, Vector3(j * TP + i, fx - i, fz - j)]


func _bl(t: Array, field: int) -> float:
	var a: PackedFloat32Array = t[0][field]
	var f: Vector3 = t[1]
	var k := int(f.x)
	return lerpf(lerpf(a[k], a[k + 1], f.y), lerpf(a[k + TP], a[k + TP + 1], f.y), f.z)


## Ground height from the coarse data only: no detail tiles needed. Close to surface() away
## from roads and the bench, and within a little of it on river banks.
func coarse_surface(x: float, z: float) -> float:
	var h := _base_at(x, z)
	var d := _coarse_at(_cd, x, z)
	if d < R_FINE:
		var floor_h := _profile(d, _coarse_at(_chw, x, z), _coarse_at(_cwl, x, z), 0.0)
		h = lerpf(floor_h, maxf(h, floor_h), smoothstep(R_FINE * 0.45, R_FINE * 0.95, d))
	return _apply_pads(x, z, h)


## sample() from the coarse data, for distant terrain: no detail tiles, no roads.
func coarse_sample(x: float, z: float) -> Vector4:
	var d := _coarse_at(_cd, x, z)
	var hw := _coarse_at(_chw, x, z)
	var look := 1.0 - smoothstep(0.5, 2.5, d - hw)
	var wl := NO_WATER
	if d < R_FINE and not _dry_near(x, z):
		wl = _coarse_at(_cwl, x, z)
	return Vector4(coarse_surface(x, z), look, wl, 0.6)


func _dry_near(x: float, z: float) -> bool:
	var i := clampi(roundi(x / COARSE), 0, CG - 1)
	var j := clampi(roundi(z / COARSE), 0, CG - 1)
	return (_cnear[j * CG + i] & 4) != 0


## Distance from a river's edge, from the coarse data (negative in the water).
func coarse_river_edge(x: float, z: float) -> float:
	return _coarse_at(_cd, x, z) - _coarse_at(_chw, x, z)


## True near a road or the bench (coarse).
func near_band(x: float, z: float) -> bool:
	if _cnear.is_empty():
		return false
	var i := clampi(roundi(x / COARSE), 0, CG - 1)
	var j := clampi(roundi(z / COARSE), 0, CG - 1)
	return (_cnear[j * CG + i] & 2) != 0


## True where a river or a band (road, bench) is close enough to change the land.
func _near(x: float, z: float) -> bool:
	if _cnear.is_empty():
		return false
	var i := clampi(roundi(x / COARSE), 0, CG - 1)
	var j := clampi(roundi(z / COARSE), 0, CG - 1)
	return _cnear[j * CG + i] != 0


## The land before rivers, roads and pads: valleys rising away from the water into hills.
func _base_at(x: float, z: float) -> float:
	var d := _coarse_at(_cd, x, z)
	var wl := _coarse_at(_cwl, x, z)
	var hw := _coarse_at(_chw, x, z)
	var dp := maxf(0.0, d - (14.0 + 5.0 * hw))
	var rise := 60.0 * (1.0 - exp(-dp / 200.0)) + 0.1 * dp
	var hills := _region_at(_rhills, x, z)
	var ridges := _region_at(_rridges, x, z)
	var amp := minf(1.5 + 0.22 * dp, 80.0) * hills
	var ridge := minf(0.12 * dp, 50.0) * ridges * (_ridges.get_noise_2d(x, z) * 0.5 + 0.5)
	return wl + 1.4 + rise * lerpf(1.0, hills, 0.6) + _hills.get_noise_2d(x, z) * amp + ridge


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
	if not _spots.is_empty():
		for p: Vector4 in _spots.get(Vector2i(floori(x / SPOT_CELL), floori(z / SPOT_CELL)), []):
			var dd := (x - p.x) * (x - p.x) + (z - p.y) * (z - p.y)
			if dd < p.z * p.z:
				h = lerpf(h, p.w, 1.0 - smoothstep(p.z * 0.5, p.z, sqrt(dd)))
	return h


# --- Generation ------------------------------------------------------------------------

func _make_rivers() -> void:
	var main := _river("Big Sable River", Vector2(-30, 1000 * LAYOUT), Vector2(SIZE + 30, 1070 * LAYOUT), 64.0, 44.0, 8.0, 9.5, 1.1, 70.0, 1.0, true)
	rivers.append(main)
	# name, source, x of the junction on the main river, richness, gradient, meander
	var creeks := [
		["Cabin Creek", Vector2(780, 1780), 840.0, 1.0, 0.04, 26.0],
		["Rattlesnake Gulch", Vector2(240, 1830), 360.0, 1.15, 0.055, 18.0],
		["Last Chance Creek", Vector2(1860, 1890), 1640.0, 1.7, 0.05, 22.0],
		["Willow Creek", Vector2(430, 210), 520.0, 1.2, 0.035, 30.0],
		["Tamarack Creek", Vector2(1310, 180), 1250.0, 1.25, 0.045, 24.0],
		# One or two more for each region of the big world.
		["Ptarmigan Creek", Vector2(180, 140), 260.0, 1.45, 0.07, 18.0],          # Alpine Creeks
		["Granite Creek", Vector2(820, 90), 900.0, 1.3, 0.065, 20.0],             # Alpine Creeks
		["Red Rock Creek", Vector2(1930, 260), 1880.0, 1.35, 0.06, 10.0],         # Canyon Country
		["Bench Creek", Vector2(1230, 1960), 1180.0, 1.1, 0.03, 28.0],            # Foothill Benches
		["Coyote Wash", Vector2(1990, 1930), 1800.0, 1.6, 0.035, 16.0, true],     # Desert Washes: dry
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
		var r := _river(c[0], source, mouth, wl_mouth + float(c[4]) / LAYOUT * length, wl_mouth, 2.6, 4.6, c[3], c[5], 1.4, false)
		r["dry"] = c.size() > 6 and c[6]
		rivers.append(r)


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
	return {"name": n, "pts": pts, "wl": wl, "hw": hw, "curv": _curvature(pts), "rich": rich, "main": is_main, "dry": false}


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





## Exact distance, water level, width and bend for every fine cell near a river.
## Note which river segments reach each tile, and mark the coarse cells they change.
func _stamp_rivers() -> void:
	_cnear.resize(CG * CG)
	_cnear.fill(0)
	var e := []
	for f in FIELDS:
		var a := PackedFloat32Array()
		a.resize(TP * TP)
		a.fill(R_STAMP if f == FD else 0.0)
		e.append(a)
	_empty_tile = e
	for ri in rivers.size():
		progress_frac = lerpf(0.45, 0.72, float(ri) / rivers.size())
		var pts: PackedVector2Array = rivers[ri]["pts"]
		for sgi in pts.size() - 1:
			_index_segment(_river_index, Vector2i(ri, sgi), pts[sgi], pts[sgi + 1], R_STAMP, 5 if rivers[ri].get("dry", false) else 1)


func _index_segment(index: Dictionary, entry: Vector2i, a: Vector2, b: Vector2, reach: float, bit: int = 1) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
	var nt := int(SIZE / TILE_M)
	for tj in range(maxi(0, floori(lo.y / TILE_M)), mini(nt - 1, floori(hi.y / TILE_M)) + 1):
		for ti in range(maxi(0, floori(lo.x / TILE_M)), mini(nt - 1, floori(hi.x / TILE_M)) + 1):
			var key := Vector2i(ti, tj)
			if not index.has(key):
				index[key] = []
			(index[key] as Array).append(entry)
	for cj in range(maxi(0, floori(lo.y / COARSE) - 1), mini(CG - 1, ceili(hi.y / COARSE) + 1) + 1):
		for ci in range(maxi(0, floori(lo.x / COARSE) - 1), mini(CG - 1, ceili(hi.x / COARSE) + 1) + 1):
			_cnear[cj * CG + ci] |= bit


## Fill one detail tile: river distance, level, width, bend and richness, then roads and bench.
func _build_tile(key: Vector2i) -> Array:
	var x0 := key.x * TILE_M
	var z0 := key.y * TILE_M
	var t := []
	for f in FIELDS:
		var a := PackedFloat32Array()
		a.resize(TP * TP)
		a.fill(R_STAMP if f == FD else 0.0)
		t.append(a)
	var fd: PackedFloat32Array = t[FD]
	var fwl: PackedFloat32Array = t[FWL]
	var fhw: PackedFloat32Array = t[FHW]
	var fbend: PackedFloat32Array = t[FBEND]
	var frich: PackedFloat32Array = t[FRICH]
	for entry: Vector2i in _river_index.get(key, []):
		var r: Dictionary = rivers[entry.x]
		var pts: PackedVector2Array = r["pts"]
		var wl: PackedFloat32Array = r["wl"]
		var hw: PackedFloat32Array = r["hw"]
		var curv: PackedFloat32Array = r["curv"]
		# A dry wash stores its richness negative: same channel and gold, but no water.
		var rich: float = -float(r["rich"]) if r.get("dry", false) else float(r["rich"])
		var sg := entry.y
		var a := pts[sg]
		var ab := pts[sg + 1] - a
		var len2 := maxf(ab.length_squared(), 1e-6)
		var i0 := maxi(0, floori((minf(a.x, a.x + ab.x) - R_STAMP - x0) / FINE))
		var i1 := mini(TP - 1, ceili((maxf(a.x, a.x + ab.x) + R_STAMP - x0) / FINE))
		var j0 := maxi(0, floori((minf(a.y, a.y + ab.y) - R_STAMP - z0) / FINE))
		var j1 := mini(TP - 1, ceili((maxf(a.y, a.y + ab.y) + R_STAMP - z0) / FINE))
		for j in range(j0, j1 + 1):
			var pz := z0 + j * FINE
			for i in range(i0, i1 + 1):
				var px := x0 + i * FINE
				var tt := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
				var qx := a.x + ab.x * tt
				var qz := a.y + ab.y * tt
				var d := sqrt((px - qx) * (px - qx) + (pz - qz) * (pz - qz))
				var k := j * TP + i
				if d < fd[k]:
					fd[k] = d
					fwl[k] = lerpf(wl[sg], wl[sg + 1], tt)
					fhw[k] = lerpf(hw[sg], hw[sg + 1], tt)
					var side := signf(ab.x * (pz - a.y) - ab.y * (px - a.x))
					fbend[k] = clampf(lerpf(curv[sg], curv[sg + 1], tt) / MAX_BEND, -1.0, 1.0) * side
					frich[k] = rich
	# Points no river reached get the coarse level and width, so blending near the edge stays sane.
	for j in TP:
		for i in TP:
			var k := j * TP + i
			if fd[k] >= R_STAMP:
				fwl[k] = _coarse_at(_cwl, x0 + i * FINE, z0 + j * FINE)
				fhw[k] = _coarse_at(_chw, x0 + i * FINE, z0 + j * FINE)
	for entry: Vector2i in _band_index.get(key, []):
		_stamp_band_tile(t, x0, z0, _bands[entry.x], entry.y)
	return t


func _stamp_band_tile(t: Array, x0: float, z0: float, band: Array, sg: int) -> void:
	var path: PackedVector2Array = band[0]
	var hs: PackedFloat32Array = band[1]
	var inner: float = band[2]
	var outer: float = band[3]
	var f_w: PackedFloat32Array = t[FROAD if band[4] else FBENCH]
	var f_h: PackedFloat32Array = t[FROADH if band[4] else FBENCHH]
	var a := path[sg]
	var ab := path[sg + 1] - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	# Heights are also written just outside the band (weight 0), because heights and
	# weights are interpolated separately: a blank height next to the band would drag
	# the blended ground toward zero and punch pits along the edge.
	var reach := outer + FINE * 3.0
	var i0 := maxi(0, floori((minf(a.x, a.x + ab.x) - reach - x0) / FINE))
	var i1 := mini(TP - 1, ceili((maxf(a.x, a.x + ab.x) + reach - x0) / FINE))
	var j0 := maxi(0, floori((minf(a.y, a.y + ab.y) - reach - z0) / FINE))
	var j1 := mini(TP - 1, ceili((maxf(a.y, a.y + ab.y) + reach - z0) / FINE))
	for j in range(j0, j1 + 1):
		var pz := z0 + j * FINE
		for i in range(i0, i1 + 1):
			var px := x0 + i * FINE
			var tt := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
			var dx := px - (a.x + ab.x * tt)
			var dz := pz - (a.y + ab.y * tt)
			var w := 1.0 - smoothstep(inner, outer, sqrt(dx * dx + dz * dz))
			var k := j * TP + i
			if w > f_w[k] or (f_w[k] <= 0.0 and f_h[k] == 0.0):
				f_w[k] = w
				f_h[k] = lerpf(hs[sg], hs[sg + 1], tt)


func _make_sites_and_roads() -> void:
	sites["base"] = _site_beside("Cabin Creek", 0.55, 1.0, 26.0)
	sites["camp"] = _site_beside("Last Chance Creek", 0.4, -1.0, 24.0)
	sites["mine"] = _site_beside("Rattlesnake Gulch", 0.55, -1.0, 52.0)
	# The town sits on the valley road, east of where Cabin Creek comes in.
	sites["town"] = _site_beside("Big Sable River", 0.51, 1.0, 66.0)
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
	var valley: PackedVector2Array = paths[1]
	# The creek roads run on to meet the valley road: the cabin road at its lower end, the Last
	# Chance road at its first point. Water on the way becomes a ford (below).
	paths[0] = _join(paths[0], valley, false)
	paths[2] = _join(paths[2], valley, true)
	# A ford across the main river from the valley road to the Tamarack road.
	var tam: PackedVector2Array = paths[3]
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
		_stamp_band(path, hs, 1.6, 5.5, "road")
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
		if s[0] == "town":
			_town_pad = pads[pads.size() - 1]
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


# --- Roadside places --------------------------------------------------------------------------

## Things along the roads: signposts at junctions and now and then, and old places a little way
## off the road (a ruined cabin, a wreck, graves...). Each gets a small level clearing. The
## world's places are fixed by the seed; roadside.gd builds them and their secrets.
var places: Array = []         # {id, kind, pos: Vector2, yaw, h, road: Vector2 (nearest road point)}
var _spots := {}               # Vector2i(cell) -> Array[Vector4(x, z, radius, height)]
const SPOT_CELL := 256.0
const PLACE_KINDS := ["ruin_cabin", "wreck", "graves", "ore_cart", "wagon", "old_sluice", "chimney", "prospect"]
const PLACE_RADIUS := {"ruin_cabin": 9.0, "wreck": 6.0, "graves": 5.0, "ore_cart": 6.0, "wagon": 5.5,
	"old_sluice": 7.0, "chimney": 5.0, "prospect": 5.0, "sign": 2.5}


func _add_spot(p: Vector2, r: float, h: float) -> void:
	var v := Vector4(p.x, p.y, r, h)
	var c0 := Vector2i(floori((p.x - r) / SPOT_CELL), floori((p.y - r) / SPOT_CELL))
	var c1 := Vector2i(floori((p.x + r) / SPOT_CELL), floori((p.y + r) / SPOT_CELL))
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var k := Vector2i(i, j)
			if not _spots.has(k):
				_spots[k] = []
			(_spots[k] as Array).append(v)


func _add_place(kind: String, p: Vector2, road_p: Vector2) -> void:
	var h := surface(p.x, p.y)
	var yaw := atan2(road_p.x - p.x, road_p.y - p.y)       # faces the road
	places.append({"id": "%s_%d" % [kind, places.size()], "kind": kind, "pos": p, "yaw": yaw, "h": h, "road": road_p})
	_add_spot(p, PLACE_RADIUS[kind], h)


func _place_ok(p: Vector2, min_gap: float) -> bool:
	if p.x < 40.0 or p.y < 40.0 or p.x > SIZE - 40.0 or p.y > SIZE - 40.0:
		return false
	if river_info(p.x, p.y).x < 10.0 or in_pad(p.x, p.y, 30.0) or road_weight(p.x, p.y) > 0.05:
		return false
	for s in ["base", "town", "camp", "mine"]:
		if (sites[s]["pos"] as Vector2).distance_to(p) < 220.0:
			return false
	for pl in places:
		if (pl["pos"] as Vector2).distance_to(p) < min_gap:
			return false
	# Not on a steep slope.
	var h := surface(p.x, p.y, false)
	for d: Vector2 in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
		if absf(surface(p.x + d.x, p.y + d.y, false) - h) > 3.2:
			return false
	return true


func _make_places() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed + 77
	# Signposts where roads meet, and at the ends of the creek roads.
	var junctions := [roads[0]["pts"][roads[0]["pts"].size() - 1], roads[2]["pts"][0], roads[4]["pts"][0],
		roads[3]["pts"][0], roads[0]["pts"][0], roads[2]["pts"][roads[2]["pts"].size() - 1]]
	for jp: Vector2 in junctions:
		for a in 12:
			var p := jp + Vector2(cos(a * TAU / 12.0), sin(a * TAU / 12.0)) * 8.0
			if road_weight(p.x, p.y) < 0.3 and river_info(p.x, p.y).x > 1.0 and not in_pad(p.x, p.y, 0.0):
				_add_place("sign", p, jp)
				break
	# Old places a little way off the roads, every kilometre or so.
	var kinds := PLACE_KINDS.duplicate()
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	var n := 0
	for ri in [1, 0, 2, 3]:
		var pts: PackedVector2Array = roads[ri]["pts"]
		var along := 0.0
		var next_at := rng.randf_range(300.0, 700.0)
		var next_sign := 1800.0
		for i in range(1, pts.size()):
			along += pts[i].distance_to(pts[i - 1])
			var dir := (pts[i] - pts[i - 1]).normalized()
			var perp := Vector2(-dir.y, dir.x)
			if ri == 1 and along > next_sign:
				# Signposts along the long valley road too.
				for side: float in [1.0, -1.0]:
					var sp := pts[i] + perp * side * 7.5
					if river_info(sp.x, sp.y).x > 1.0 and not in_pad(sp.x, sp.y, 0.0):
						_add_place("sign", sp, pts[i])
						next_sign = along + 1800.0
						break
			if along < next_at:
				continue
			for attempt in 14:
				var side := 1.0 if attempt % 2 == 0 else -1.0
				var p := pts[i] + perp * side * rng.randf_range(18.0, 40.0)
				if _place_ok(p, 260.0):
					_add_place(kinds[n % kinds.size()], p, pts[i])
					n += 1
					break
			next_at = along + rng.randf_range(550.0, 950.0)


# --- Old mineshafts ---------------------------------------------------------------------------

## A few old vertical shafts up in the hills of the Old Mining District, off the roads. Each gets a
## small level pad for its collar and headframe; climbing down leads into a small mine of its own.
var shafts: Array = []         # {id, pos: Vector2, yaw, h, seed}
const SHAFT_COUNT := 3
const SHAFT_RADIUS := 6.0


func _make_shafts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed + 313
	var center: Vector2 = (REGIONS[1][1] as Vector2) * LAYOUT
	for attempt in 400:
		if shafts.size() >= SHAFT_COUNT:
			break
		var a := rng.randf() * TAU
		var p := center + Vector2(cos(a), sin(a)) * rng.randf_range(150.0, 900.0)
		if not _place_ok(p, 120.0) or road_weight(p.x, p.y) > 0.0:
			continue
		var far := true
		for s in shafts:
			if (s["pos"] as Vector2).distance_to(p) < 300.0:
				far = false
		if not far:
			continue
		var h := surface(p.x, p.y)
		shafts.append({"id": "shaft_%d" % shafts.size(), "pos": p, "yaw": rng.randf() * TAU, "h": h, "seed": rng.randi()})
		_add_spot(p, SHAFT_RADIUS, h)


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


## Extend a road from one end (its start if `at_start`) straight to the nearest point of another.
func _join(path: PackedVector2Array, to: PackedVector2Array, at_start: bool) -> PackedVector2Array:
	var end := path[0] if at_start else path[path.size() - 1]
	var best := to[0]
	for q in to:
		if q.distance_to(end) < best.distance_to(end):
			best = q
	var n := maxi(1, ceili(end.distance_to(best) / SPACING))
	var link := PackedVector2Array()
	for k in range(1, n + 1):
		link.append(end.lerp(best, float(k) / n))
	if at_start:
		link.reverse()
		link.append_array(path)
		return link
	var out := path.duplicate()
	out.append_array(link)
	return out


## Stamp a band along a path into the road or bench fields (the strongest weight wins).
## (Packed arrays are copied when passed, so this picks its target fields by name.)
## Register a road or bench band; tiles stamp it when they are built.
func _stamp_band(path: PackedVector2Array, hs: PackedFloat32Array, inner: float, outer: float, target: String) -> void:
	var id := _bands.size()
	_bands.append([path, hs, inner, outer, target == "road"])
	for sg in path.size() - 1:
		_index_segment(_band_index, Vector2i(id, sg), path[sg], path[sg + 1], outer + FINE * 3.0, 2)
	# Tiles built so far (while working out road heights) lack this band: start them over.
	_tile_mutex.lock()
	_tiles.clear()
	_tile_mutex.unlock()