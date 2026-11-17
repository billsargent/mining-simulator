extends Node3D
## The old mine's interior: carvable rock on a 0.5 m grid, hidden far below the surface and
## reached through the portal. Tunnels and rooms are carved out of solid rock at build time;
## quartz veins are marked in the rock and show white in the walls. Chipping opens more cells,
## so the walls really break away. Meshes are built per 8 m chunk with noise-displaced
## vertices and smooth normals, so the rock looks hewn rather than blocky.
## Local axes: the adit runs in +X from the entrance.

const Parts = preload("res://scripts/machines/parts.gd")
const Tex = preload("res://scripts/util/tex.gd")
const MinePortal = preload("res://scripts/world/mine_portal.gd")

const CELL := 0.5
const NX := 144
const NY := 28
const NZ := 120
const CH := 16
const LEVEL1 := 8.0
const LEVEL2 := 1.5
const ROCK := 0
const OPEN := 1
const VEIN_A := 2          # upper vein
const VEIN_B := 3          # lower, richer vein
const ROCK_COLOR := Color(0.42, 0.39, 0.36)
const QUARTZ_COLOR := Color(1.0, 0.98, 0.95)
const DIRS = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var cells := PackedByteArray()
var carved := PackedInt32Array()      # cells the player has opened (saved)
var built := false

var _chunks := {}                     # Vector3i -> [MeshInstance3D, CollisionShape3D]
var _pos_cache := {}                  # smoothed corner positions (cleared when the rock changes)
var _relax_cache := {}
var _noise := FastNoiseLite.new()
var _mat: StandardMaterial3D
var _body: StaticBody3D


func build(saved_carved: PackedInt32Array = PackedInt32Array()) -> void:
	_noise.seed = 1887
	_noise.frequency = 0.35
	cells.resize(NX * NY * NZ)
	cells.fill(ROCK)
	_layout()
	for c in saved_carved:
		if c >= 0 and c < cells.size():
			cells[c] = OPEN
	carved = saved_carved
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.albedo_texture = Tex.noise(0.05, 90, 256)
	_mat.normal_enabled = true
	_mat.normal_texture = Tex.noise(0.08, 91, 256, true, 8.0)
	_mat.uv1_triplanar = true
	_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body = StaticBody3D.new()
	_body.add_to_group("mine")
	add_child(_body)
	for cz in ceili(float(NZ) / CH):
		for cy in ceili(float(NY) / CH):
			for cx in ceili(float(NX) / CH):
				_build_chunk(Vector3i(cx, cy, cz))
	_props()
	built = true


## Where you stand after walking in, and which way you face.
func spawn_point() -> Vector3:
	return to_global(Vector3(4.5, LEVEL1 + 0.15, 30.0))


func spawn_yaw() -> float:
	return -PI / 2.0


## Chip the rock at a hit point. Returns how many cells of each kind broke away.
func chip(world_pos: Vector3, normal: Vector3, radius: float = 1.2) -> Dictionary:
	var p := to_local(world_pos - normal * 0.3) / CELL
	var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var out := {"rock": 0, "vein_a": 0, "vein_b": 0}
	var touched := {}
	_pos_cache.clear()
	_relax_cache.clear()
	for dj in range(-2, 3):
		for dk in range(-2, 3):
			for di in range(-2, 3):
				var q := c + Vector3i(di, dj, dk)
				if Vector3(di, dj, dk).length() > radius or not _inside(q):
					continue
				var k := _idx(q.x, q.y, q.z)
				var kind := cells[k]
				if kind == OPEN:
					continue
				out["rock" if kind == ROCK else ("vein_a" if kind == VEIN_A else "vein_b")] += 1
				cells[k] = OPEN
				carved.append(k)
				# Smoothing reaches a few cells, so rebuild every chunk within that range.
				for sx in [-4, 0, 4]:
					for sy in [-4, 0, 4]:
						for sz in [-4, 0, 4]:
							var n := q + Vector3i(sx, sy, sz)
							if n.x >= 0 and n.y >= 0 and n.z >= 0 and n.x < NX and n.y < NY and n.z < NZ:
								touched[Vector3i(n.x / CH, n.y / CH, n.z / CH)] = true
	for ch: Vector3i in touched:
		_build_chunk(ch)
	return out


func _idx(i: int, j: int, k: int) -> int:
	return (j * NZ + k) * NX + i


## Border cells stay solid so the mine can never be opened to the void.
func _inside(q: Vector3i) -> bool:
	return q.x >= 2 and q.y >= 2 and q.z >= 2 and q.x < NX - 2 and q.y < NY - 2 and q.z < NZ - 2


func _open(i: int, j: int, k: int) -> bool:
	if i < 0 or j < 0 or k < 0 or i >= NX or j >= NY or k >= NZ:
		return false
	return cells[_idx(i, j, k)] == OPEN


# --- Layout ------------------------------------------------------------------------------

func _layout() -> void:
	var z0 := 30.0
	_tunnel(Vector3(1.5, LEVEL1, z0), Vector3(34, LEVEL1, z0), 1.45, 2.8)       # adit
	_room(Vector3(34, LEVEL1, z0), Vector3(3.0, 1.7, 3.0))                      # junction
	_tunnel(Vector3(34, LEVEL1, z0), Vector3(34, LEVEL1, 14), 1.3, 2.6)         # north drift
	_room(Vector3(34, LEVEL1, 9), Vector3(5.0, 2.8, 4.5))                       # stope
	_tunnel(Vector3(34, LEVEL1, z0), Vector3(37, LEVEL1, 46), 1.3, 2.6)         # south drift
	_tunnel(Vector3(37, LEVEL1, 46), Vector3(52, LEVEL1, 50), 1.3, 2.6)
	_tunnel(Vector3(34, LEVEL1, z0), Vector3(50, LEVEL1, z0), 1.4, 2.7)         # east drift
	_tunnel(Vector3(50, LEVEL1, z0), Vector3(63, LEVEL2, z0), 1.5, 3.2)         # incline down
	_room(Vector3(64.5, LEVEL2, z0), Vector3(2.5, 1.6, 2.5))
	_tunnel(Vector3(64.5, LEVEL2, z0), Vector3(64.5, LEVEL2, 16), 1.3, 2.6)     # lower drift
	_tunnel(Vector3(64.5, LEVEL2, 16), Vector3(40, LEVEL2, 14), 1.3, 2.6)
	# Quartz veins: thin slanted sheets of white rock that cross the drifts.
	for j in NY:
		for k in NZ:
			for i in NX:
				if cells[_idx(i, j, k)] != ROCK:
					continue
				var x := (i + 0.5) * CELL
				var y := (j + 0.5) * CELL
				var z := (k + 0.5) * CELL
				var wob := _noise.get_noise_3d(x * 0.4, y * 0.4, z * 0.4) * 0.5
				if y > 5.5 and y < 12.0 and z > 20.0 and z < 56.0 and absf(x - 44.0 - 0.35 * (y - LEVEL1) + wob) < 0.3:
					cells[_idx(i, j, k)] = VEIN_A
				elif y < 5.5 and x > 36.0 and x < 62.0 and absf(z - 12.6 - 0.3 * y + wob) < 0.32:
					cells[_idx(i, j, k)] = VEIN_B


func _tunnel(a: Vector3, b: Vector3, hw: float, h: float) -> void:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := maxf(ab.length_squared(), 0.001)
	var i0 := floori((minf(a.x, b.x) - hw - 1.0) / CELL)
	var i1 := ceili((maxf(a.x, b.x) + hw + 1.0) / CELL)
	var k0 := floori((minf(a.z, b.z) - hw - 1.0) / CELL)
	var k1 := ceili((maxf(a.z, b.z) + hw + 1.0) / CELL)
	for k in range(k0, k1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2((i + 0.5) * CELL, (k + 0.5) * CELL)
			var t := clampf(((p.x - a.x) * ab.x + (p.y - a.z) * ab.y) / len2, 0.0, 1.0)
			var d := p.distance_to(Vector2(a.x, a.z) + ab * t)
			if d > hw:
				continue
			var floor_y := lerpf(a.y, b.y, t)
			for j in NY:
				var yy := (j + 0.5) * CELL - floor_y
				if yy < 0.0 or yy > h:
					continue
				# Straight walls up to 60% of the height, then an arched roof.
				var limit := hw
				if yy > h * 0.6:
					limit = hw * sqrt(maxf(0.0, 1.0 - pow((yy - h * 0.6) / (h * 0.4), 2.0)))
				if d < limit and _inside(Vector3i(i, j, k)):
					cells[_idx(i, j, k)] = OPEN


func _room(c: Vector3, half: Vector3) -> void:
	for j in NY:
		for k in range(floori((c.z - half.z) / CELL), ceili((c.z + half.z) / CELL) + 1):
			for i in range(floori((c.x - half.x) / CELL), ceili((c.x + half.x) / CELL) + 1):
				var dx := ((i + 0.5) * CELL - c.x) / half.x
				var dz := ((k + 0.5) * CELL - c.z) / half.z
				var yy := (j + 0.5) * CELL - c.y
				if yy < 0.0 or yy > half.y * 2.0:
					continue
				var dy := maxf(0.0, (yy - half.y) / half.y)
				if dx * dx + dz * dz + dy * dy < 1.0 and _inside(Vector3i(i, j, k)):
					cells[_idx(i, j, k)] = OPEN


# --- Meshing -------------------------------------------------------------------------------

## Where a grid corner sits. Corners are pulled toward the open space around them, which rounds
## off the square steps, then nudged by noise so the rock looks hewn.
func _vpos(v: Vector3i) -> Vector3:
	if _pos_cache.has(v):
		return _pos_cache[v]
	# Three rounds of averaging each surface corner with its neighbors on the surface
	# melts the square steps into slopes and arches. Floors stay flat because a flat
	# surface averages to itself.
	var p := _relaxed(v, 3)
	p += Vector3(_noise.get_noise_3d(p.x, p.y, p.z) * 0.1, _noise.get_noise_3d(p.x + 31.0, p.y, p.z) * 0.035,
		_noise.get_noise_3d(p.x, p.y + 57.0, p.z) * 0.1)
	_pos_cache[v] = p
	return p


func _on_surface(v: Vector3i) -> bool:
	var count := 0
	for dj in [-1, 0]:
		for dk in [-1, 0]:
			for di in [-1, 0]:
				if _open(v.x + di, v.y + dj, v.z + dk):
					count += 1
	return count > 0 and count < 8


func _relaxed(v: Vector3i, rounds: int) -> Vector3:
	if rounds == 0:
		return Vector3(v) * CELL
	var key := Vector4i(v.x, v.y, v.z, rounds)
	if _relax_cache.has(key):
		return _relax_cache[key]
	var sum := _relaxed(v, rounds - 1)
	var n := 1
	for d: Vector3i in DIRS:
		var w := v + d
		if _on_surface(w):
			sum += _relaxed(w, rounds - 1)
			n += 1
	var out := sum / n
	_relax_cache[key] = out
	return out


func _build_chunk(c: Vector3i) -> void:
	var quads := []                 # [v0, v1, v2, v3, normal, color]
	var normals := {}               # grid vertex -> summed normal
	for j in range(c.y * CH, mini((c.y + 1) * CH, NY)):
		for k in range(c.z * CH, mini((c.z + 1) * CH, NZ)):
			for i in range(c.x * CH, mini((c.x + 1) * CH, NX)):
				if cells[_idx(i, j, k)] != OPEN:
					continue
				for d: Vector3i in DIRS:
					var ni := i + d.x
					var nj := j + d.y
					var nk := k + d.z
					if _open(ni, nj, nk):
						continue
					var kind := ROCK
					if ni >= 0 and nj >= 0 and nk >= 0 and ni < NX and nj < NY and nk < NZ:
						kind = cells[_idx(ni, nj, nk)]
					var u := Vector3i(0, 1, 0) if d.x != 0 else Vector3i(1, 0, 0)
					var v := Vector3i(0, 0, 1) if d.z == 0 else Vector3i(0, 1, 0)
					var base := Vector3i(i, j, k) + Vector3i(maxi(d.x, 0), maxi(d.y, 0), maxi(d.z, 0))
					var corners := [base, base + u, base + u + v, base + v]
					var n := -Vector3(d)
					for cv: Vector3i in corners:
						normals[cv] = (normals.get(cv, Vector3.ZERO) as Vector3) + n
					# Wind every face so its front looks into the tunnel; otherwise half the
					# walls get lit as if they faced away.
					var order := [0, 2, 1, 0, 3, 2] if Vector3(u).cross(Vector3(v)).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
					quads.append([corners, QUARTZ_COLOR if kind != ROCK else ROCK_COLOR, order])
	var entry: Array = _chunks.get(c, [])
	if quads.is_empty():
		if not entry.is_empty():
			(entry[0] as Node).queue_free()
			(entry[1] as Node).queue_free()
			_chunks.erase(c)
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for q in quads:
		var cs: Array = q[0]
		for o: int in q[2]:
			var gv: Vector3i = cs[o]
			verts.append(_vpos(gv))
			norms.append((normals[gv] as Vector3).normalized())
			cols.append(q[1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	if entry.is_empty():
		var mi := MeshInstance3D.new()
		add_child(mi)
		var col := CollisionShape3D.new()
		_body.add_child(col)
		entry = [mi, col]
		_chunks[c] = entry
	(entry[0] as MeshInstance3D).mesh = mesh
	(entry[1] as CollisionShape3D).shape = shape


# --- Timbers, rails and the way out ----------------------------------------------------------

func _props() -> void:
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	var rail := Parts.mat("rail", Color(0.3, 0.2, 0.15), 0.7, 0.6)
	var z0 := 30.0
	var x := 3.0
	while x < 31.0:
		for s: float in [-1.0, 1.0]:
			Parts.box(self, Vector3(0.2, 2.2, 0.2), Vector3(x, LEVEL1 + 1.1, z0 + s * 0.95), timber)
		Parts.box(self, Vector3(0.24, 0.22, 2.3), Vector3(x, LEVEL1 + 2.25, z0), timber)
		x += 3.2
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(47.0, 0.06, 0.05), Vector3(25.5, LEVEL1 + 0.08, z0 + s * 0.35), rail)
	x = 2.5
	while x < 49.0:
		Parts.box(self, Vector3(0.16, 0.06, 1.0), Vector3(x, LEVEL1 + 0.04, z0), timber)
		x += 0.9
	# An ore cart left at the junction.
	var cart := Node3D.new()
	cart.position = Vector3(31.0, LEVEL1 + 0.1, z0)
	add_child(cart)
	Parts.box(cart, Vector3(1.3, 0.6, 0.75), Vector3(0, 0.55, 0), rail)
	for wx: float in [-0.4, 0.4]:
		for wz: float in [-0.35, 0.35]:
			Parts.cyl(cart, 0.15, 0.06, Vector3(wx, 0.15, wz), rail, Vector3(PI / 2.0, 0, 0))
	var cart_body := StaticBody3D.new()
	cart.add_child(cart_body)
	Parts.collider(cart_body, Vector3(1.3, 0.9, 0.75), Vector3(0, 0.45, 0))
	# A plank ramp down the incline (the rock under it is stepped).
	var a := Vector3(49.5, LEVEL1 + 0.05, z0)
	var b := Vector3(63.5, LEVEL2 + 0.05, z0)
	var ramp := StaticBody3D.new()
	ramp.position = (a + b) * 0.5
	ramp.rotation.z = atan2(b.y - a.y, b.x - a.x)
	add_child(ramp)
	var length := a.distance_to(b) + 0.6
	Parts.box(ramp, Vector3(length, 0.12, 1.9), Vector3.ZERO, timber)
	Parts.collider(ramp, Vector3(length, 0.12, 1.9), Vector3.ZERO)
	var steps := int(length / 0.8)
	for i in steps:
		Parts.box(ramp, Vector3(0.08, 0.05, 1.9), Vector3(-length * 0.5 + 0.4 + i * 0.8, 0.085, 0), timber)
	# The way out: daylight through the boards at the mouth of the adit.
	var door := MinePortal.new()
	door.is_exit = true
	door.position = Vector3(1.9, LEVEL1, z0)
	add_child(door)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.9, 0.9, 0.8)
	glow.emission_enabled = true
	glow.emission = Color(0.9, 0.88, 0.75)
	glow.emission_energy_multiplier = 1.2
	Parts.box(door, Vector3(0.05, 2.3, 2.1), Vector3(-0.1, 1.15, 0), glow)
	for i in 4:
		Parts.box(door, Vector3(0.06, 0.2, 2.2), Vector3(0, 0.4 + i * 0.5, 0), timber, Vector3(0.05 * (i % 2 * 2 - 1), 0, 0))
	Parts.collider(door, Vector3(0.4, 2.4, 2.3), Vector3(0, 1.2, 0))
	var light := OmniLight3D.new()
	light.position = Vector3(1.0, 1.4, 0)
	light.light_color = Color(0.9, 0.88, 0.75)
	light.light_energy = 0.6
	light.omni_range = 6.0
	door.add_child(light)
