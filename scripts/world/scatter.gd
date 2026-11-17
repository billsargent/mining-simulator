extends Node3D
## Trees, boulders and grass for the big world.
## Trees and boulders are laid out once per 128 m region (deterministic from the seed) and drawn
## with cheap stand-ins far away. Grass and collision shapes only exist near the focus.
## Creek boulders come from the world generator, because they also trap gold.

const WorldGen = preload("res://scripts/world/world_gen.gd")
const Terrain = preload("res://scripts/world/world_terrain.gd")
const Tex = preload("res://scripts/util/tex.gd")

const REGION := 128.0
const RN := int(WorldGen.SIZE / REGION)
const TREE_STEP := 9.0
const ROCK_BLOCK := 512.0
const GRASS_CELL := 16.0
const GRASS_STEP := 0.7
const GRASS_RADIUS := 60.0
const COLLIDE_RADIUS := 72.0
const NEAR_TREES := 230.0
const MAX_GRASS_TASKS := 6
const BOULDER_RADIUS := 650.0   # creek boulders get their exact height (and appear) within this range

var world: WorldGen
var terrain: Terrain
var focus := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _trees := {}            # Vector2i region -> PackedFloat32Array [x, y, z, scale, yaw] per tree
var _rocks := {}            # Vector2i region -> PackedFloat32Array [x, y, z, radius, yaw, variant]
var _colliders := {}        # Vector2i region -> StaticBody3D
var _grass := {}            # Vector2i cell -> MultiMeshInstance3D
var _grass_pos := {}        # Vector2i cell -> PackedVector3Array
var _grass_tasks := {}
var _grass_done: Array = []
var _mutex := Mutex.new()
var _grass_mesh: ArrayMesh
var _hidden := Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -500, 0))
var _shapes := {}
var _stream_t := 0.0
var _boulder_regions := {}  # Vector2i region -> PackedFloat32Array [x, z, radius, yaw, variant], waiting
var _rock_meshes: Array[ArrayMesh] = []
var _rock_mat: StandardMaterial3D


# --- Layout (thread-safe, run during loading) --------------------------------------------

func layout() -> void:
	var task := WorkerThreadPool.add_group_task(_layout_region, RN * RN)
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Creek boulders sit in the channel, where only the detail tiles know the exact ground, so
	# they wait until you come near (_stream_boulders).
	for b in world.boulders:
		var r := Vector2i(clampi(floori(b.x / REGION), 0, RN - 1), clampi(floori(b.z / REGION), 0, RN - 1))
		var list: PackedFloat32Array = _boulder_regions.get(r, PackedFloat32Array())
		for v in [b.x, b.z, b.w, fposmod(b.x * 7.31, TAU), float(int(b.z) % 4)]:
			list.append(v)
		_boulder_regions[r] = list


func _layout_region(idx: int) -> void:
	var rx := idx % RN
	var rz := idx / RN
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(rx, rz, world.world_seed))
	var trees := PackedFloat32Array()
	var steps := int(REGION / TREE_STEP)
	for gj in steps:
		for gi in steps:
			var x := rx * REGION + (gi + rng.randf()) * TREE_STEP
			var z := rz * REGION + (gj + rng.randf()) * TREE_STEP
			var p := rng.randf()
			var s := rng.randf_range(0.75, 1.35)
			var yaw := rng.randf() * TAU
			if _tree_ok(x, z, p):
				for v in [x, _ground(x, z), z, s, yaw]:
					trees.append(v)
	var rocks := PackedFloat32Array()
	for k in 6:
		var x := rx * REGION + rng.randf() * REGION
		var z := rz * REGION + rng.randf() * REGION
		var r := lerpf(0.4, 1.8, pow(rng.randf(), 2.0))
		var yaw := rng.randf() * TAU
		var variant := float(rng.randi() % 4)
		if world.coarse_river_edge(x, z) > 12.0 and not world.near_band(x, z) and not world.in_pad(x, z, 3.0):
			for v in [x, world.coarse_surface(x, z), z, r, yaw, variant]:
				rocks.append(v)
	_mutex.lock()
	_trees[Vector2i(rx, rz)] = trees
	_rocks[Vector2i(rx, rz)] = rocks
	_mutex.unlock()


## Ground height for a tree: the detail tiles next to roads and the bench, the coarse estimate
## everywhere else (within a few centimeters on river banks).
func _ground(x: float, z: float) -> float:
	return world.surface(x, z) if world.near_band(x, z) else world.coarse_surface(x, z)


func _tree_ok(x: float, z: float, p: float) -> bool:
	if x < 2.0 or z < 2.0 or x > WorldGen.SIZE - 2.0 or z > WorldGen.SIZE - 2.0:
		return false
	if world.coarse_river_edge(x, z) < 10.0:
		return false
	if world.in_pad(x, z, 4.0):
		return false
	if p > smoothstep(0.35, 0.7, world.forest(x, z)) * 0.85 + 0.06 * (1.0 - world.bare(x, z)):
		return false
	# Only next to roads and the bench does placing a tree need the detail tiles.
	if world.near_band(x, z) and (world.road_weight(x, z) > 0.05 or (world.bench_weight(x, z) > 0.3 and p < 0.85)):
		return false
	var h := _ground(x, z)
	var n := Vector3(h - _ground(x + 1.5, z), 1.5, h - _ground(x, z + 1.5)).normalized()
	return n.y > 0.72


# --- Visuals (main thread) -------------------------------------------------------------------

func build_visuals() -> void:
	_rng.seed = world.world_seed
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.22, 0.16)
	bark.roughness = 0.95
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.22, 0.32, 0.16)
	needles.vertex_color_use_as_albedo = true
	needles.albedo_texture = Tex.noise(0.25, 80, 128)
	needles.uv1_triplanar = true
	needles.uv1_scale = Vector3(2.0, 2.0, 2.0)
	needles.cull_mode = BaseMaterial3D.CULL_DISABLED
	needles.roughness = 0.95
	var near_meshes: Array[ArrayMesh] = [_conifer_mesh(bark, needles), _conifer_mesh(bark, needles)]
	var far_mesh := _far_tree_mesh()
	for r: Vector2i in _trees:
		var data: PackedFloat32Array = _trees[r]
		var count := data.size() / 5
		if count == 0:
			continue
		var center := Vector3((r.x + 0.5) * REGION, 0.0, (r.y + 0.5) * REGION)
		var lists := [[], []]
		var all := []
		for i in count:
			var o := i * 5
			var s := data[o + 3]
			var xf := Transform3D(Basis(Vector3.UP, data[o + 4]).scaled(Vector3(s, s, s)),
				Vector3(data[o], data[o + 1] - 0.1, data[o + 2]) - center)
			(lists[i % 2] as Array).append(xf)
			all.append(xf)
		for v in 2:
			var mmi := _mmi(near_meshes[v], lists[v], center)
			mmi.visibility_range_end = NEAR_TREES
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var far := _mmi(far_mesh, all, center)
		far.visibility_range_begin = NEAR_TREES - 20.0
		far.visibility_range_begin_margin = 20.0
		far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Boulders, grouped in 512 m blocks per shape.
	var rock_meshes: Array[ArrayMesh] = []
	for v in 4:
		rock_meshes.append(_rock_mesh(v))
	_rock_meshes = rock_meshes
	var rock_mat := StandardMaterial3D.new()
	_rock_mat = rock_mat
	rock_mat.albedo_color = Color(0.55, 0.53, 0.5)
	rock_mat.albedo_texture = Tex.noise(0.03, 70, 256)
	rock_mat.normal_enabled = true
	rock_mat.normal_texture = Tex.noise(0.05, 71, 256, true, 6.0)
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_scale = Vector3(0.7, 0.7, 0.7)
	rock_mat.roughness = 0.88
	var blocks := {}
	for r: Vector2i in _rocks:
		var data: PackedFloat32Array = _rocks[r]
		for i in data.size() / 6:
			var o := i * 6
			var bk := Vector3i(floori(data[o] / ROCK_BLOCK), floori(data[o + 2] / ROCK_BLOCK), int(data[o + 5]))
			if not blocks.has(bk):
				blocks[bk] = []
			var rad := data[o + 3]
			var center := Vector3((bk.x + 0.5) * ROCK_BLOCK, 0.0, (bk.y + 0.5) * ROCK_BLOCK)
			(blocks[bk] as Array).append(Transform3D(Basis(Vector3.UP, data[o + 4]).scaled(Vector3.ONE * rad),
				Vector3(data[o], data[o + 1] + rad * 0.12, data[o + 2]) - center))
	for bk: Vector3i in blocks:
		var center := Vector3((bk.x + 0.5) * ROCK_BLOCK, 0.0, (bk.y + 0.5) * ROCK_BLOCK)
		var mmi := _mmi(rock_meshes[bk.z], blocks[bk], center)
		mmi.material_override = rock_mat
		mmi.visibility_range_end = 700.0
	_grass_mesh = _make_grass_mesh()
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/grass.gdshader")
	_grass_mesh.surface_set_material(0, gmat)
	terrain.dug.connect(_on_dug)


func _mmi(mesh: Mesh, xforms: Array, center: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	add_child(mmi)
	return mmi


# --- Streaming near the focus ----------------------------------------------------------------

func _process(delta: float) -> void:
	_drain_grass()
	_stream_t -= delta
	if _stream_t > 0.0:
		return
	_stream_t = 0.25
	_stream_colliders()
	_stream_grass()


## Build everything near the focus right away (loading screen, or after a teleport).
func build_near_now() -> void:
	_stream_colliders()
	var cells := _wanted_cells()
	var results := []
	results.resize(cells.size())
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var data := _grass_cell(cells[i])
		_mutex.lock()
		results[i] = data
		_mutex.unlock(), cells.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in cells.size():
		if not _grass.has(cells[i]):
			_make_grass(cells[i], results[i])


func _exit_tree() -> void:
	for id in _grass_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)


func _stream_colliders() -> void:
	_stream_boulders()
	for rz in RN:
		for rx in RN:
			var r := Vector2i(rx, rz)
			var x0 := rx * REGION
			var z0 := rz * REGION
			var dx := maxf(maxf(x0 - focus.x, focus.x - (x0 + REGION)), 0.0)
			var dz := maxf(maxf(z0 - focus.z, focus.z - (z0 + REGION)), 0.0)
			var dist := sqrt(dx * dx + dz * dz)
			if dist < COLLIDE_RADIUS and not _colliders.has(r):
				_colliders[r] = _make_colliders(r)
			elif dist > COLLIDE_RADIUS + 32.0 and _colliders.has(r):
				(_colliders[r] as Node).queue_free()
				_colliders.erase(r)


## Creek boulders near the focus: exact heights from the detail tiles, then drawn.
func _stream_boulders() -> void:
	if _rock_meshes.is_empty():
		return
	for r: Vector2i in _boulder_regions.keys():
		var center := Vector2((r.x + 0.5) * REGION, (r.y + 0.5) * REGION)
		if center.distance_to(Vector2(focus.x, focus.z)) > BOULDER_RADIUS:
			continue
		var data: PackedFloat32Array = _boulder_regions[r]
		_boulder_regions.erase(r)
		var rocks: PackedFloat32Array = _rocks.get(r, PackedFloat32Array())
		var lists := [[], [], [], []]
		var c3 := Vector3(center.x, 0.0, center.y)
		for i in data.size() / 5:
			var o := i * 5
			var x := data[o]
			var z := data[o + 1]
			var rad := data[o + 2]
			var y := world.surface(x, z)
			for v in [x, y, z, rad, data[o + 3], data[o + 4]]:
				rocks.append(v)
			(lists[int(data[o + 4])] as Array).append(Transform3D(Basis(Vector3.UP, data[o + 3]).scaled(Vector3.ONE * rad),
				Vector3(x, y + rad * 0.12, z) - c3))
		_rocks[r] = rocks
		for v in 4:
			if not (lists[v] as Array).is_empty():
				var mmi := _mmi(_rock_meshes[v], lists[v], c3)
				mmi.material_override = _rock_mat
				mmi.visibility_range_end = 700.0
		if _colliders.has(r):
			(_colliders[r] as Node).queue_free()
			_colliders.erase(r)


func _make_colliders(r: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child(body)
	var trees: PackedFloat32Array = _trees.get(r, PackedFloat32Array())
	for i in trees.size() / 5:
		var o := i * 5
		var cs := CollisionShape3D.new()
		cs.shape = _shape("tree", snappedf(0.22 * trees[o + 3], 0.05))
		cs.position = Vector3(trees[o], trees[o + 1] + 2.0, trees[o + 2])
		body.add_child(cs)
	var rocks: PackedFloat32Array = _rocks.get(r, PackedFloat32Array())
	for i in rocks.size() / 6:
		var o := i * 6
		var cs := CollisionShape3D.new()
		cs.shape = _shape("rock", snappedf(rocks[o + 3] * 0.72, 0.05))
		cs.position = Vector3(rocks[o], rocks[o + 1] + rocks[o + 3] * 0.12, rocks[o + 2])
		body.add_child(cs)
	return body


func _shape(kind: String, size: float) -> Shape3D:
	var key := "%s%.2f" % [kind, size]
	if not _shapes.has(key):
		if kind == "tree":
			var c := CylinderShape3D.new()
			c.radius = size
			c.height = 4.0
			_shapes[key] = c
		else:
			var s := SphereShape3D.new()
			s.radius = size
			_shapes[key] = s
	return _shapes[key]


func _wanted_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0 := Vector2i(floori((focus.x - GRASS_RADIUS) / GRASS_CELL), floori((focus.z - GRASS_RADIUS) / GRASS_CELL))
	var c1 := Vector2i(floori((focus.x + GRASS_RADIUS) / GRASS_CELL), floori((focus.z + GRASS_RADIUS) / GRASS_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var center := Vector2((cx + 0.5) * GRASS_CELL, (cz + 0.5) * GRASS_CELL)
			if center.distance_to(Vector2(focus.x, focus.z)) < GRASS_RADIUS and cx >= 0 and cz >= 0:
				out.append(Vector2i(cx, cz))
	return out


func _stream_grass() -> void:
	var want := {}
	for c in _wanted_cells():
		want[c] = true
		if not _grass.has(c) and not _grass_tasks.has(c) and _grass_tasks.size() < MAX_GRASS_TASKS:
			_grass_tasks[c] = WorkerThreadPool.add_task(_task_grass.bind(c))
	for c: Vector2i in _grass.keys():
		var center := Vector2((c.x + 0.5) * GRASS_CELL, (c.y + 0.5) * GRASS_CELL)
		if center.distance_to(Vector2(focus.x, focus.z)) > GRASS_RADIUS + 24.0:
			(_grass[c] as Node).queue_free()
			_grass.erase(c)
			_grass_pos.erase(c)


func _task_grass(c: Vector2i) -> void:
	var data := _grass_cell(c)
	_mutex.lock()
	_grass_done.append([c, data])
	_mutex.unlock()


func _drain_grass() -> void:
	_mutex.lock()
	var done := _grass_done
	_grass_done = []
	_mutex.unlock()
	for item in done:
		var c: Vector2i = item[0]
		if _grass_tasks.has(c):
			WorkerThreadPool.wait_for_task_completion(_grass_tasks[c])
			_grass_tasks.erase(c)
		if not _grass.has(c):
			_make_grass(c, item[1])


## Grass clumps for one cell: [x, y, z, scale, stretch, yaw] each. Thread-safe.
func _grass_cell(c: Vector2i) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, world.world_seed + 5))
	var out := PackedFloat32Array()
	var steps := int(GRASS_CELL / GRASS_STEP)
	for gj in steps:
		for gi in steps:
			var x := c.x * GRASS_CELL + (gi + rng.randf()) * GRASS_STEP
			var z := c.y * GRASS_CELL + (gj + rng.randf()) * GRASS_STEP
			var s := rng.randf_range(0.7, 1.25)
			var stretch := rng.randf_range(0.7, 1.15)
			var yaw := rng.randf() * TAU
			var skip := rng.randf()
			var smp := world.sample(x, z)
			if smp.y > 0.25 or (smp.z > -1.0e8 and smp.x - smp.z < 0.2):
				continue
			if skip > (0.55 + 0.45 * (1.0 - world.forest(x, z))) * (1.0 - world.bare(x, z)) or world.in_pad(x, z, -4.0):
				continue
			var h := terrain.height_undug(x, z)
			if absf(world.surface(x + 0.7, z) - smp.x) > 0.45 or absf(world.surface(x, z + 0.7) - smp.x) > 0.45:
				continue
			for v in [x, h - 0.02, z, s, stretch, yaw]:
				out.append(v)
	return out


func _make_grass(c: Vector2i, data: PackedFloat32Array) -> void:
	var origin := Vector3(c.x * GRASS_CELL, 0.0, c.y * GRASS_CELL)
	var xforms := []
	var pos := PackedVector3Array()
	for i in data.size() / 6:
		var o := i * 6
		if terrain.dug_at(data[o], data[o + 2]) > 0.3:
			continue
		var s := data[o + 3]
		var p := Vector3(data[o], data[o + 1], data[o + 2])
		xforms.append(Transform3D(Basis(Vector3.UP, data[o + 5]).scaled(Vector3(s, s * data[o + 4], s)), p - origin))
		pos.append(p)
	var mmi := _mmi(_grass_mesh, xforms, origin)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass[c] = mmi
	_grass_pos[c] = pos


## Digging tears up the grass around the hole.
func _on_dug(center: Vector3, radius: float) -> void:
	var reach := radius + 0.3
	for c: Vector2i in _grass_pos:
		var pos: PackedVector3Array = _grass_pos[c]
		var mm := (_grass[c] as MultiMeshInstance3D).multimesh
		for i in pos.size():
			if Vector2(pos[i].x - center.x, pos[i].z - center.z).length() < reach:
				mm.set_instance_transform(i, _hidden)


# --- Meshes --------------------------------------------------------------------------------

func _rock_mesh(variant: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.seed = 500 + variant
	n.frequency = 0.9
	n.fractal_octaves = 3
	var flat := _rng.randf_range(0.55, 0.8)
	for i in verts.size():
		var v := verts[i]
		v *= 1.0 + 0.32 * n.get_noise_3dv(v)
		v.y *= flat
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _conifer_mesh(bark: Material, needles: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.06
	trunk.bottom_radius = 0.2
	trunk.height = 7.5
	trunk.radial_segments = 8
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 3.75, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, bark)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := 7
	for t in tiers:
		var f := float(t) / float(tiers - 1)
		var base_y := lerpf(1.4, 7.0, f)
		var tier_h := lerpf(2.6, 1.5, f)
		var radius := lerpf(2.2, 0.5, f) * _rng.randf_range(0.9, 1.1)
		var apex := Vector3(0, base_y + tier_h, 0)
		var under := Vector3(0, base_y + tier_h * 0.3, 0)
		var n := 13
		var ring: Array[Vector3] = []
		var off := _rng.randf() * TAU
		for k in n:
			var a := off + TAU * k / n + _rng.randf_range(-0.12, 0.12)
			var rr := radius * _rng.randf_range(0.75, 1.15)
			ring.append(Vector3(cos(a) * rr, base_y - _rng.randf_range(0.0, 0.35), sin(a) * rr))
		for k in n:
			var p0 := ring[k]
			var p1 := ring[(k + 1) % n]
			_vert(st, apex, Vector3.UP, 1.0)
			_vert(st, p0, Vector3(p0.x, radius * 0.9, p0.z).normalized(), 0.55)
			_vert(st, p1, Vector3(p1.x, radius * 0.9, p1.z).normalized(), 0.55)
			_vert(st, under, Vector3.DOWN, 0.25)
			_vert(st, p1, Vector3(p1.x, -radius, p1.z).normalized(), 0.4)
			_vert(st, p0, Vector3(p0.x, -radius, p0.z).normalized(), 0.4)
	st.commit(mesh)
	mesh.surface_set_material(1, needles)
	return mesh


## A cheap stand-in for distant trees: one dark cone on a short trunk.
func _far_tree_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.9
	cone.height = 7.2
	cone.radial_segments = 6
	cone.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 5.0, 0)))
	st.commit(mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.18, 0.1)
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	return mesh


func _vert(st: SurfaceTool, p: Vector3, n: Vector3, shade: float) -> void:
	st.set_normal(n)
	st.set_color(Color(shade, shade, shade))
	st.add_vertex(p)


func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.75
	var ht := 0.5
	for q in 3:
		var a := PI * q / 3.0
		var dir := Vector3(cos(a), 0.0, sin(a)) * (w * 0.5)
		var bl := -dir
		var br := dir
		var tl := bl + Vector3(0, ht, 0)
		var tr := br + Vector3(0, ht, 0)
		for pair in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [bl, Vector2(0, 1)],
				[tr, Vector2(1, 0)], [br, Vector2(1, 1)], [bl, Vector2(0, 1)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(pair[1])
			st.add_vertex(pair[0])
	return st.commit()
