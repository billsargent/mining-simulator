extends Node3D
## Deformable heightmap terrain for the test valley.
## Heights live in one array; the mesh is split into chunks so a dig only rebuilds the
## chunks it touches. Each vertex also knows where bedrock is, so you can't dig through it.

signal dug(center: Vector3, radius: float)

const Valley = preload("res://scripts/world/valley.gd")
const Tex = preload("res://scripts/util/tex.gd")

const CELL := 0.5           # metres between vertices
const GRID := 512           # cells per side (256 m)
const CHUNK := 32           # cells per chunk side
const VERTS := GRID + 1

var valley: Valley
var heights := PackedFloat32Array()
var bedrock := PackedFloat32Array()
var gravel := PackedFloat32Array()        # 0..1 bare-gravel look, for the shader
var dug_amount := PackedFloat32Array()    # 0..1 disturbed ground, for the shader

var _material: ShaderMaterial
var _chunks := {}                          # Vector2i -> {"mesh": MeshInstance3D, "shape": CollisionShape3D}
var _indices := PackedInt32Array()


func generate() -> void:
	var total := VERTS * VERTS
	heights.resize(total)
	bedrock.resize(total)
	gravel.resize(total)
	dug_amount.resize(total)
	dug_amount.fill(0.0)
	for j in VERTS:
		for i in VERTS:
			var s := valley.sample(i * CELL, j * CELL)
			var k := j * VERTS + i
			heights[k] = s.x
			bedrock[k] = s.x - s.y
			gravel[k] = s.z
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/terrain.gdshader")
	_material.set_shader_parameter("noise_large", Tex.noise(0.01, 31, 512))
	_material.set_shader_parameter("noise_detail", Tex.noise(0.04, 32, 512))
	_material.set_shader_parameter("water_level", Valley.WATER_LEVEL)
	_build_indices()
	var n := GRID / CHUNK
	for cz in n:
		for cx in n:
			_build_chunk(Vector2i(cx, cz))


func height_at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, GRID - 0.001)
	var fz := clampf(z / CELL, 0.0, GRID - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * VERTS + i
	var a := lerpf(heights[k], heights[k + 1], tx)
	var b := lerpf(heights[k + VERTS], heights[k + VERTS + 1], tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	return _normal(clampi(roundi(x / CELL), 0, GRID), clampi(roundi(z / CELL), 0, GRID))


func gravel_at(x: float, z: float) -> float:
	var i := clampi(roundi(x / CELL), 0, GRID)
	var j := clampi(roundi(z / CELL), 0, GRID)
	return gravel[j * VERTS + i]


func dug_at(x: float, z: float) -> float:
	var i := clampi(roundi(x / CELL), 0, GRID)
	var j := clampi(roundi(z / CELL), 0, GRID)
	return dug_amount[j * VERTS + i]


## Level a round area to height h0 (for building on), blending into the land around it.
func flatten(c: Vector3, radius: float, h0: float) -> void:
	var ci := roundi(c.x / CELL)
	var cj := roundi(c.z / CELL)
	var rc := ceili(radius / CELL)
	for dj in range(-rc, rc + 1):
		for di in range(-rc, rc + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i > GRID or j > GRID:
				continue
			var dist := Vector2(di, dj).length() * CELL
			if dist > radius:
				continue
			var w := 1.0 - smoothstep(radius - 4.0, radius, dist)
			var k := j * VERTS + i
			heights[k] = lerpf(heights[k], h0, w)
			if w > 0.5:
				gravel[k] = 0.0
			bedrock[k] = minf(bedrock[k], heights[k] - 0.5)
	_rebuild_around(ci, cj, rc)


## Put back heights and dug marks from a save.
func restore(saved_heights: PackedFloat32Array, saved_dug: PackedFloat32Array) -> void:
	heights = saved_heights
	if saved_dug.size() == heights.size():
		dug_amount = saved_dug
	var n := GRID / CHUNK
	for cz in n:
		for cx in n:
			_build_chunk(Vector2i(cx, cz))


func _rebuild_around(ci: int, cj: int, rc: int) -> void:
	var last := GRID / CHUNK - 1
	var cx0 := clampi(floori(float(ci - rc - 2) / CHUNK), 0, last)
	var cx1 := clampi(floori(float(ci + rc + 1) / CHUNK), 0, last)
	var cz0 := clampi(floori(float(cj - rc - 2) / CHUNK), 0, last)
	var cz1 := clampi(floori(float(cj + rc + 1) / CHUNK), 0, last)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_build_chunk(Vector2i(cx, cz))


## Dig a shovel-sized bowl at p. Returns what happened at the center of the hole.
func dig(p: Vector3, depth: float, radius: float) -> Dictionary:
	var ci := clampi(roundi(p.x / CELL), 1, GRID - 1)
	var cj := clampi(roundi(p.z / CELL), 1, GRID - 1)
	var k0 := cj * VERTS + ci
	var top := heights[k0]
	var rc := ceili(radius / CELL)
	for dj in range(-rc, rc + 1):
		for di in range(-rc, rc + 1):
			var i := ci + di
			var j := cj + dj
			if i < 1 or j < 1 or i > GRID - 1 or j > GRID - 1:
				continue
			var dist := Vector2(di, dj).length() * CELL
			if dist > radius:
				continue
			var f := 0.5 + 0.5 * cos(PI * dist / radius)
			var k := j * VERTS + i
			heights[k] = maxf(bedrock[k], heights[k] - depth * f)
			dug_amount[k] = maxf(dug_amount[k], clampf(f * 1.5, 0.0, 1.0))
	var bottom := heights[k0]
	_rebuild_around(ci, cj, rc)
	var center := Vector3(ci * CELL, bottom, cj * CELL)
	dug.emit(center, radius)
	return {
		"x": center.x,
		"z": center.z,
		"top": top,
		"bottom": bottom,
		"bedrock": bedrock[k0],
		"removed": top - bottom,
		"at_bedrock": bottom <= bedrock[k0] + 0.005,
	}


func _build_indices() -> void:
	var n := CHUNK + 1
	_indices.clear()
	for lj in CHUNK:
		for li in CHUNK:
			var a := lj * n + li
			var b := a + 1
			var c := a + n
			var d := c + 1
			_indices.append(a)
			_indices.append(b)
			_indices.append(c)
			_indices.append(b)
			_indices.append(d)
			_indices.append(c)


func _normal(i: int, j: int) -> Vector3:
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, GRID)
	var jd := maxi(j - 1, 0)
	var ju := mini(j + 1, GRID)
	var hl := heights[j * VERTS + il]
	var hr := heights[j * VERTS + ir]
	var hd := heights[jd * VERTS + i]
	var hu := heights[ju * VERTS + i]
	return Vector3((hl - hr) / ((ir - il) * CELL), 1.0, (hd - hu) / ((ju - jd) * CELL)).normalized()


func _build_chunk(c: Vector2i) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	var i0 := c.x * CHUNK
	var j0 := c.y * CHUNK
	for lj in n:
		for li in n:
			var i := i0 + li
			var j := j0 + lj
			var k := j * VERTS + i
			var h := heights[k]
			var v := lj * n + li
			verts[v] = Vector3(i * CELL, h, j * CELL)
			norms[v] = _normal(i, j)
			var exposed := 1.0 - smoothstep(0.03, 0.1, h - bedrock[k])
			cols[v] = Color(dug_amount[k], exposed, gravel[k], 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var faces := PackedVector3Array()
	faces.resize(_indices.size())
	for t in _indices.size():
		faces[t] = verts[_indices[t]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	if _chunks.has(c):
		var entry: Dictionary = _chunks[c]
		(entry["mesh"] as MeshInstance3D).mesh = mesh
		(entry["shape"] as CollisionShape3D).shape = shape
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		var body := StaticBody3D.new()
		body.add_to_group("terrain")
		add_child(body)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		_chunks[c] = {"mesh": mi, "shape": cs}
