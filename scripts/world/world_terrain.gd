extends Node3D
## Terrain for the big world, streamed around a focus point (the player, or what they drive).
##
## Rendering uses a quadtree: 16 m pieces at 0.5 m detail close by, growing to 512 m pieces far
## away. Every piece is a 33×33 grid with skirts that hide the seams between detail levels.
## Collision exists only near the focus, as 32 m heightmap tiles. Digging is stored as height
## changes on 16 m dig tiles on top of the generated land, so only dug spots need saving.
## Pieces are built on worker threads.

signal dug(center: Vector3, radius: float)

const WorldGen = preload("res://scripts/world/world_gen.gd")
const Tex = preload("res://scripts/util/tex.gd")

const LEAF := 16.0
const N := 32
const MAX_LEVEL := 7
const SPLIT_K := 1.5
const TILE := 32.0
const TN := 64
const TILES := 64
const TILE_RADIUS := 2
const CELL := 0.5
const DIG_TILE := 16.0
const DN := 32
const MICRO := 0.1
const MAX_TASKS := 32

var world: WorldGen
var focus := Vector3(1024.0, 0.0, 1024.0)

var _material: ShaderMaterial
var _micro := FastNoiseLite.new()
var _indices := PackedInt32Array()
var _built := {}            # Vector3i(level, x, z) -> MeshInstance3D
var _wanted: Array[Vector3i] = []
var _settled := true        # the wanted set is fully built and shown
var _last_focus := Vector3(-1.0e9, 0.0, -1.0e9)
var _node_tasks := {}       # Vector3i -> task id
var _dirty := {}            # nodes whose in-flight build predates a dig
var _dirty_tiles := {}      # same for collision tiles
var _tile_tasks := {}       # Vector2i -> task id
var _tiles := {}            # Vector2i -> CollisionShape3D
var _node_done: Array = []
var _tile_done: Array = []
var _mutex := Mutex.new()
var _dig_h := {}            # Vector2i -> PackedFloat32Array, 33×33 height changes (≤ 0)
var _dig_m := {}            # Vector2i -> PackedFloat32Array, 33×33 dug marks (0..1)
var _body: StaticBody3D
var _refresh_t := 0.0


func setup(w: WorldGen) -> void:
	world = w
	_micro.seed = w.world_seed + 3
	_micro.frequency = 0.15
	_micro.fractal_octaves = 2
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/terrain.gdshader")
	_material.set_shader_parameter("noise_large", Tex.noise(0.01, 31, 512))
	_material.set_shader_parameter("noise_detail", Tex.noise(0.04, 32, 512))
	_body = StaticBody3D.new()
	_body.add_to_group("terrain")
	add_child(_body)
	_build_indices()


# --- Queries (main thread) ---------------------------------------------------------------

func height_undug(x: float, z: float) -> float:
	return world.surface(x, z) + _micro.get_noise_2d(x, z) * MICRO


func height_at(x: float, z: float) -> float:
	return height_undug(x, z) + _dig_delta(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var hl := height_at(x - 0.5, z)
	var hr := height_at(x + 0.5, z)
	var hd := height_at(x, z - 0.5)
	var hu := height_at(x, z + 0.5)
	return Vector3(hl - hr, 1.0, hd - hu).normalized()


## Depth of water over the ground here; negative on dry land (very negative away from rivers).
func water_depth(x: float, z: float) -> float:
	return world.water_level(x, z) - height_at(x, z)


func water_level(x: float, z: float) -> float:
	return world.water_level(x, z)


func dug_at(x: float, z: float) -> float:
	var gi := roundi(x / CELL)
	var gj := roundi(z / CELL)
	var t := Vector2i(floori(float(gi) / DN), floori(float(gj) / DN))
	if not _dig_m.has(t):
		return 0.0
	var m: PackedFloat32Array = _dig_m[t]
	return m[(gj - t.y * DN) * (DN + 1) + (gi - t.x * DN)]


func _dig_delta(x: float, z: float) -> float:
	var fx := x / CELL
	var fz := z / CELL
	var gi := floori(fx)
	var gj := floori(fz)
	var t := Vector2i(floori(float(gi) / DN), floori(float(gj) / DN))
	if not _dig_h.has(t):
		return 0.0
	var a: PackedFloat32Array = _dig_h[t]
	var li := gi - t.x * DN
	var lj := gj - t.y * DN
	var k := lj * (DN + 1) + li
	var tx := fx - gi
	var tz := fz - gj
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + DN + 1], a[k + DN + 2], tx), tz)


# --- Digging -------------------------------------------------------------------------------

## Dig a shovel-sized bowl at p. Returns what happened at the center of the hole.
func dig(p: Vector3, depth: float, radius: float) -> Dictionary:
	var gi := roundi(p.x / CELL)
	var gj := roundi(p.z / CELL)
	var cx := gi * CELL
	var cz := gj * CELL
	var top := height_at(cx, cz)
	var bedrock := height_undug(cx, cz) - world.sample(cx, cz).w
	var rc := ceili(radius / CELL)
	_mutex.lock()
	for dj in range(-rc, rc + 1):
		for di in range(-rc, rc + 1):
			var dist := Vector2(di, dj).length() * CELL
			if dist > radius:
				continue
			var i := gi + di
			var j := gj + dj
			if i < 1 or j < 1 or i >= TILES * TN or j >= TILES * TN:
				continue
			var f := 0.5 + 0.5 * cos(PI * dist / radius)
			var floor_d := -world.sample(i * CELL, j * CELL).w
			_set_vertex(i, j, maxf(floor_d, _vertex_delta(i, j) - depth * f), clampf(f * 1.5, 0.0, 1.0))
	_mutex.unlock()
	var bottom := height_at(cx, cz)
	_after_dig(cx, cz, radius)
	dug.emit(Vector3(cx, bottom, cz), radius)
	return {
		"x": cx, "z": cz, "top": top, "bottom": bottom, "bedrock": bedrock,
		"removed": top - bottom, "at_bedrock": bottom <= bedrock + 0.005,
	}


func _vertex_delta(i: int, j: int) -> float:
	var t := Vector2i(floori(float(i) / DN), floori(float(j) / DN))
	if not _dig_h.has(t):
		return 0.0
	var a: PackedFloat32Array = _dig_h[t]
	return a[(j - t.y * DN) * (DN + 1) + (i - t.x * DN)]


## Write one dig vertex into every dig tile that contains it (tiles share their borders).
func _set_vertex(i: int, j: int, delta: float, mark: float) -> void:
	var txs := [floori(float(i) / DN)]
	if i % DN == 0:
		txs.append(i / DN - 1)
	var tzs := [floori(float(j) / DN)]
	if j % DN == 0:
		tzs.append(j / DN - 1)
	for tx: int in txs:
		for tz: int in tzs:
			if tx < 0 or tz < 0:
				continue
			var t := Vector2i(tx, tz)
			if not _dig_h.has(t):
				var blank := PackedFloat32Array()
				blank.resize((DN + 1) * (DN + 1))
				blank.fill(0.0)
				_dig_h[t] = blank
				_dig_m[t] = blank.duplicate()
			var k := (j - tz * DN) * (DN + 1) + (i - tx * DN)
			var h: PackedFloat32Array = _dig_h[t]
			var m: PackedFloat32Array = _dig_m[t]
			h[k] = delta
			m[k] = maxf(m[k], mark)
			_dig_h[t] = h
			_dig_m[t] = m


func _after_dig(cx: float, cz: float, radius: float) -> void:
	var r := radius + 1.0
	for key: Vector3i in _built.keys():
		if key.x <= 1 and _node_overlaps(key, cx, cz, r):
			_make_node(key, _node_arrays(key))
	for key: Vector3i in _node_tasks.keys():
		if _node_overlaps(key, cx, cz, r):
			_dirty[key] = true
	for t: Vector2i in _tile_tasks.keys():
		_dirty_tiles[t] = true
	for t: Vector2i in _tiles.keys():
		var x0 := t.x * TILE
		var z0 := t.y * TILE
		if cx + r < x0 or cx - r > x0 + TILE or cz + r < z0 or cz - r > z0 + TILE:
			continue
		var cs: CollisionShape3D = _tiles[t]
		var shape := cs.shape as HeightMapShape3D
		var data := shape.map_data
		var i0 := clampi(floori((cx - r - x0) / CELL), 0, TN)
		var i1 := clampi(ceili((cx + r - x0) / CELL), 0, TN)
		var j0 := clampi(floori((cz - r - z0) / CELL), 0, TN)
		var j1 := clampi(ceili((cz + r - z0) / CELL), 0, TN)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				data[j * (TN + 1) + i] = height_at(x0 + i * CELL, z0 + j * CELL) / CELL
		shape.map_data = data


func _node_overlaps(key: Vector3i, cx: float, cz: float, r: float) -> bool:
	var size := LEAF * float(1 << key.x)
	var x0 := key.y * size
	var z0 := key.z * size
	return not (cx + r < x0 or cx - r > x0 + size or cz + r < z0 or cz - r > z0 + size)


## For saving: only the dug tiles.
func dig_data() -> Dictionary:
	return {"h": _dig_h, "m": _dig_m}


func restore_digs(d: Dictionary) -> void:
	_dig_h = d.get("h", {})
	_dig_m = d.get("m", {})


# --- Streaming -------------------------------------------------------------------------------

## Build everything around the focus right now (loading screen, or after a teleport).
func build_now() -> void:
	_wanted = _desired()
	_last_focus = focus
	var keys := _wanted.duplicate()
	var results := []
	results.resize(keys.size())
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var arrays := _node_arrays(keys[i])
		_mutex.lock()
		results[i] = arrays
		_mutex.unlock(), keys.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in keys.size():
		_make_node(keys[i], results[i])
	_swap()
	var tiles := _wanted_tiles()
	var tile_data := []
	tile_data.resize(tiles.size())
	var task2 := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var data := _tile_heights(tiles[i])
		_mutex.lock()
		tile_data[i] = data
		_mutex.unlock(), tiles.size())
	WorkerThreadPool.wait_for_group_task_completion(task2)
	for i in tiles.size():
		_make_tile(tiles[i], tile_data[i])


func _process(delta: float) -> void:
	_drain()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.12
		_refresh()


func _exit_tree() -> void:
	for id in _node_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	for id in _tile_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)


func _refresh() -> void:
	if _settled and focus.distance_to(_last_focus) > 6.0:
		_last_focus = focus
		_wanted = _desired()
		_settled = false
	if not _settled:
		var all_built := true
		for key in _wanted:
			if not _built.has(key):
				all_built = false
				if not _node_tasks.has(key) and _node_tasks.size() < MAX_TASKS:
					_node_tasks[key] = WorkerThreadPool.add_task(_task_node.bind(key))
		if all_built:
			_swap()
			_settled = true
	var want := {}
	for t in _wanted_tiles():
		want[t] = true
		if not _tiles.has(t) and not _tile_tasks.has(t):
			_tile_tasks[t] = WorkerThreadPool.add_task(_task_tile.bind(t))
	var ft := Vector2i(floori(focus.x / TILE), floori(focus.z / TILE))
	for t: Vector2i in _tiles.keys():
		if absi(t.x - ft.x) > TILE_RADIUS + 1 or absi(t.y - ft.y) > TILE_RADIUS + 1:
			(_tiles[t] as Node).queue_free()
			_tiles.erase(t)


func _drain() -> void:
	_mutex.lock()
	var nodes := _node_done
	var tiles := _tile_done
	_node_done = []
	_tile_done = []
	_mutex.unlock()
	for item in nodes:
		var key: Vector3i = item[0]
		if _node_tasks.has(key):
			WorkerThreadPool.wait_for_task_completion(_node_tasks[key])
			_node_tasks.erase(key)
		if _dirty.has(key):
			_dirty.erase(key)
			_make_node(key, _node_arrays(key))
		else:
			_make_node(key, item[1])
	for item in tiles:
		var t: Vector2i = item[0]
		if _tile_tasks.has(t):
			WorkerThreadPool.wait_for_task_completion(_tile_tasks[t])
			_tile_tasks.erase(t)
		var data: PackedFloat32Array = item[1]
		if _dirty_tiles.has(t):
			_dirty_tiles.erase(t)
			data = _tile_heights(t)
		if not _tiles.has(t):
			_make_tile(t, data)


func _task_node(key: Vector3i) -> void:
	var arrays := _node_arrays(key)
	_mutex.lock()
	_node_done.append([key, arrays])
	_mutex.unlock()


func _task_tile(t: Vector2i) -> void:
	var data := _tile_heights(t)
	_mutex.lock()
	_tile_done.append([t, data])
	_mutex.unlock()


func _swap() -> void:
	var want := {}
	for k in _wanted:
		want[k] = true
	for k: Vector3i in _built.keys():
		var mi: MeshInstance3D = _built[k]
		if want.has(k):
			mi.visible = true
		else:
			mi.queue_free()
			_built.erase(k)


func _desired() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	_collect(MAX_LEVEL, 0, 0, out)
	return out


func _collect(level: int, ix: int, iz: int, out: Array[Vector3i]) -> void:
	var size := LEAF * float(1 << level)
	var x0 := ix * size
	var z0 := iz * size
	var dx := maxf(maxf(x0 - focus.x, focus.x - (x0 + size)), 0.0)
	var dz := maxf(maxf(z0 - focus.z, focus.z - (z0 + size)), 0.0)
	if level > 0 and sqrt(dx * dx + dz * dz) < size * SPLIT_K:
		for c in 4:
			_collect(level - 1, ix * 2 + (c & 1), iz * 2 + (c >> 1), out)
	else:
		out.append(Vector3i(level, ix, iz))


func _wanted_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ft := Vector2i(floori(focus.x / TILE), floori(focus.z / TILE))
	for dz in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for dx in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var t := ft + Vector2i(dx, dz)
			if t.x >= 0 and t.y >= 0 and t.x < TILES and t.y < TILES:
				out.append(t)
	return out


# --- Building pieces (thread-safe) -----------------------------------------------------------

func _build_indices() -> void:
	var nv := N + 1
	_indices.clear()
	for j in N:
		for i in N:
			var a := j * nv + i
			_indices.append_array(PackedInt32Array([a, a + 1, a + nv, a + 1, a + nv + 1, a + nv]))
	# Skirts: a strip hanging down from the whole border.
	var loop := _border_loop()
	var base := nv * nv
	var count := loop.size()
	for e in count:
		var a := loop[e]
		var b := loop[(e + 1) % count]
		var sa := base + e
		var sb := base + (e + 1) % count
		_indices.append_array(PackedInt32Array([a, b, sb, a, sb, sa]))


func _border_loop() -> PackedInt32Array:
	var nv := N + 1
	var loop := PackedInt32Array()
	for i in N:
		loop.append(i)
	for j in N:
		loop.append(j * nv + N)
	for i in range(N, 0, -1):
		loop.append(N * nv + i)
	for j in range(N, 0, -1):
		loop.append(j * nv)
	return loop


func _fetch_digs(x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	var digs := {}
	_mutex.lock()
	if not _dig_h.is_empty():
		for tz in range(floori(z0 / DIG_TILE), floori(z1 / DIG_TILE) + 1):
			for tx in range(floori(x0 / DIG_TILE), floori(x1 / DIG_TILE) + 1):
				var t := Vector2i(tx, tz)
				if _dig_h.has(t):
					digs[t] = [_dig_h[t], _dig_m[t]]
	_mutex.unlock()
	return digs


## Height change and dug mark at a dig-grid point, from a fetched set of dig tiles.
func _dig_lookup(digs: Dictionary, x: float, z: float) -> Vector2:
	var gi := roundi(x / CELL)
	var gj := roundi(z / CELL)
	var t := Vector2i(floori(float(gi) / DN), floori(float(gj) / DN))
	if not digs.has(t):
		return Vector2.ZERO
	var pair: Array = digs[t]
	var k := (gj - t.y * DN) * (DN + 1) + (gi - t.x * DN)
	return Vector2((pair[0] as PackedFloat32Array)[k], (pair[1] as PackedFloat32Array)[k])


func _node_arrays(key: Vector3i) -> Array:
	var level := key.x
	var size := LEAF * float(1 << level)
	var step := size / N
	var x0 := key.y * size
	var z0 := key.z * size
	var fine := level <= 1
	var digs := _fetch_digs(x0 - step, z0 - step, x0 + size + step, z0 + size + step) if fine else {}
	var m := N + 3
	var nv := N + 1
	var hs := PackedFloat32Array()
	hs.resize(m * m)
	var cols := PackedColorArray()
	cols.resize(nv * nv)
	for j in m:
		var z := z0 + (j - 1) * step
		for i in m:
			var x := x0 + (i - 1) * step
			var s := world.sample(x, z)
			var h := s.x
			var dug := 0.0
			var exposed := 0.0
			if fine:
				h += _micro.get_noise_2d(x, z) * MICRO
				if not digs.is_empty():
					var dd := _dig_lookup(digs, x, z)
					h += dd.x
					dug = dd.y
					if dd.y > 0.0:
						exposed = 1.0 - smoothstep(0.03, 0.1, s.w + dd.x)
			hs[j * m + i] = h
			if i >= 1 and j >= 1 and i <= nv and j <= nv:
				var wet := 1.0 if s.z < -1.0e8 else clampf((h - s.z + 0.5) / 3.0, 0.0, 1.0)
				cols[(j - 1) * nv + (i - 1)] = Color(dug, exposed, s.y, wet)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(nv * nv)
	norms.resize(nv * nv)
	for j in nv:
		for i in nv:
			var hk := (j + 1) * m + (i + 1)
			verts[j * nv + i] = Vector3(x0 + i * step, hs[hk], z0 + j * step)
			norms[j * nv + i] = Vector3(hs[hk - 1] - hs[hk + 1], 2.0 * step, hs[hk - m] - hs[hk + m]).normalized()
	var skirt := step * 2.0 + 0.5
	for v in _border_loop():
		verts.append(verts[v] - Vector3(0.0, skirt, 0.0))
		norms.append(norms[v])
		cols.append(cols[v])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = _indices
	return arrays


func _tile_heights(t: Vector2i) -> PackedFloat32Array:
	var x0 := t.x * TILE
	var z0 := t.y * TILE
	var digs := _fetch_digs(x0, z0, x0 + TILE, z0 + TILE)
	var n := TN + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		var z := z0 + j * CELL
		for i in n:
			var x := x0 + i * CELL
			var h := world.surface(x, z) + _micro.get_noise_2d(x, z) * MICRO
			if not digs.is_empty():
				h += _dig_lookup(digs, x, z).x
			data[j * n + i] = h / CELL
	return data


func _make_node(key: Vector3i, arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	if _built.has(key):
		(_built[key] as MeshInstance3D).mesh = mesh
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visible = false
	add_child(mi)
	_built[key] = mi


func _make_tile(t: Vector2i, data: PackedFloat32Array) -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = TN + 1
	hm.map_depth = TN + 1
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(CELL, CELL, CELL)
	cs.position = Vector3((t.x + 0.5) * TILE, 0.0, (t.y + 0.5) * TILE)
	_body.add_child(cs)
	_tiles[t] = cs
