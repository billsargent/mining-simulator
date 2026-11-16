extends Node3D
## Set dressing for the test valley: boulders (creek boulders also trap gold), conifers and
## grass. All meshes are generated in code as placeholders; real art assets come later.

const Valley = preload("res://scripts/world/valley.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const Tex = preload("res://scripts/util/tex.gd")

const CREEK_BOULDERS := 26
const HILL_BOULDERS := 90
const TREES := 420
const GRASS_STEP := 0.7
const GRASS_CELL := 4.0

var terrain: Terrain
var valley: Valley
var deposits: DepositField

var _rng := RandomNumberGenerator.new()
var _grass_mm: MultiMesh
var _grass_pos := PackedVector3Array()
var _grass_cells := {}          # Vector2i -> Array of instance indices
var _hidden := Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -50, 0))
var _exclude: Array[Vector4] = []   # x, z, radius for trees and rocks, radius for grass


## Keep trees, rocks and grass out of an area (e.g. around the cabin).
func exclude(c: Vector3, radius: float, grass_radius: float) -> void:
	_exclude.append(Vector4(c.x, c.z, radius, grass_radius))


func _excluded(x: float, z: float, grass: bool) -> bool:
	for e in _exclude:
		var r := e.w if grass else e.z
		if Vector2(x - e.x, z - e.y).length() < r:
			return true
	return false


## After loading a save: tear up the grass wherever the ground was dug.
func hide_dug_grass() -> void:
	for i in _grass_pos.size():
		var p := _grass_pos[i]
		if terrain.dug_at(p.x, p.z) > 0.3:
			_grass_mm.set_instance_transform(i, _hidden)


func build(world_seed: int) -> void:
	_rng.seed = world_seed
	_build_rocks()
	_build_trees()
	_build_grass()
	terrain.dug.connect(_on_dug)


# --- Boulders ----------------------------------------------------------------------

func _build_rocks() -> void:
	var meshes: Array[ArrayMesh] = []
	for v in 5:
		meshes.append(_rock_mesh(v))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.53, 0.5)
	mat.albedo_texture = Tex.noise(0.03, 70, 256)
	mat.normal_enabled = true
	mat.normal_texture = Tex.noise(0.05, 71, 256, true, 6.0)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.7, 0.7, 0.7)
	mat.roughness = 0.88
	var placed := 0
	while placed < CREEK_BOULDERS:
		var x := _rng.randf_range(6.0, Valley.SIZE - 6.0)
		var w := valley.half_width(x)
		var z := valley.center_z(x) + _rng.randf_range(-w * 1.1, w * 1.1)
		_place_rock(meshes, mat, x, z, _rng.randf_range(0.35, 0.85), true)
		placed += 1
	placed = 0
	var tries := 0
	while placed < HILL_BOULDERS and tries < 2000:
		tries += 1
		var x := _rng.randf_range(4.0, Valley.SIZE - 4.0)
		var z := _rng.randf_range(4.0, Valley.SIZE - 4.0)
		if valley.geometry(x, z).y < 10.0 or _excluded(x, z, false):
			continue
		_place_rock(meshes, mat, x, z, lerpf(0.4, 1.8, pow(_rng.randf(), 2.0)), false)
		placed += 1


func _place_rock(meshes: Array[ArrayMesh], mat: Material, x: float, z: float, radius: float, in_creek: bool) -> void:
	var y := terrain.height_at(x, z)
	var body := StaticBody3D.new()
	body.position = Vector3(x, y + radius * 0.12, z)
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[_rng.randi() % meshes.size()]
	mi.material_override = mat
	mi.scale = Vector3.ONE * radius
	mi.rotation.y = _rng.randf() * TAU
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.72
	cs.shape = sphere
	body.add_child(cs)
	add_child(body)
	if in_creek:
		deposits.boulders.append(Vector4(x, y, z, radius))


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


# --- Trees -------------------------------------------------------------------------

func _build_trees() -> void:
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
	var variants: Array[ArrayMesh] = []
	var transforms: Array = []
	for v in 3:
		variants.append(_conifer_mesh(bark, needles))
		transforms.append([])
	var density := FastNoiseLite.new()
	density.seed = 90
	density.frequency = 0.02
	var trunks := StaticBody3D.new()
	add_child(trunks)
	var count := 0
	var tries := 0
	while count < TREES and tries < 8000:
		tries += 1
		var x := _rng.randf_range(2.0, Valley.SIZE - 2.0)
		var z := _rng.randf_range(2.0, Valley.SIZE - 2.0)
		var g := valley.geometry(x, z)
		if g.y < 16.0 or _excluded(x, z, false):
			continue
		if g.x > 0.0 and valley.bench_mask(g.x) > 0.5 and _rng.randf() < 0.85:
			continue          # keep the old bench mostly open
		if density.get_noise_2d(x, z) < -0.15:
			continue
		if terrain.normal_at(x, z).y < 0.75:
			continue
		var y := terrain.height_at(x, z)
		var s := _rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
		(transforms[_rng.randi() % 3] as Array).append(Transform3D(basis, Vector3(x, y - 0.1, z)))
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.22 * s
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = Vector3(x, y + 2.0, z)
		trunks.add_child(cs)
		count += 1
	for v in 3:
		var list: Array = transforms[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


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
			# outer surface
			_vert(st, apex, Vector3.UP, 1.0)
			_vert(st, p0, Vector3(p0.x, radius * 0.9, p0.z).normalized(), 0.55)
			_vert(st, p1, Vector3(p1.x, radius * 0.9, p1.z).normalized(), 0.55)
			# underside
			_vert(st, under, Vector3.DOWN, 0.25)
			_vert(st, p1, Vector3(p1.x, -radius, p1.z).normalized(), 0.4)
			_vert(st, p0, Vector3(p0.x, -radius, p0.z).normalized(), 0.4)
	st.commit(mesh)
	mesh.surface_set_material(1, needles)
	return mesh


func _vert(st: SurfaceTool, p: Vector3, n: Vector3, shade: float) -> void:
	st.set_normal(n)
	st.set_color(Color(shade, shade, shade))
	st.add_vertex(p)


# --- Grass -------------------------------------------------------------------------

func _build_grass() -> void:
	var mesh := _grass_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mesh.surface_set_material(0, mat)
	var density := FastNoiseLite.new()
	density.seed = 91
	density.frequency = 0.04
	var xforms: Array[Transform3D] = []
	var x := 1.0
	while x < Valley.SIZE - 1.0:
		var z := 1.0
		while z < Valley.SIZE - 1.0:
			var px := x + _rng.randf_range(-0.4, 0.4)
			var pz := z + _rng.randf_range(-0.4, 0.4)
			z += GRASS_STEP
			if terrain.gravel_at(px, pz) > 0.25 or _excluded(px, pz, true):
				continue
			var y := terrain.height_at(px, pz)
			if y < Valley.WATER_LEVEL + 0.2:
				continue
			if terrain.normal_at(px, pz).y < 0.8:
				continue
			if density.get_noise_2d(px, pz) < -0.35:
				continue
			var s := _rng.randf_range(0.7, 1.25)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.15), s))
			var pos := Vector3(px, y - 0.02, pz)
			var idx := xforms.size()
			xforms.append(Transform3D(basis, pos))
			_grass_pos.append(pos)
			var cell := Vector2i(floori(px / GRASS_CELL), floori(pz / GRASS_CELL))
			if not _grass_cells.has(cell):
				_grass_cells[cell] = []
			(_grass_cells[cell] as Array).append(idx)
		x += GRASS_STEP
	_grass_mm = MultiMesh.new()
	_grass_mm.transform_format = MultiMesh.TRANSFORM_3D
	_grass_mm.mesh = mesh
	_grass_mm.instance_count = xforms.size()
	for i in xforms.size():
		_grass_mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _grass_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _grass_mesh() -> ArrayMesh:
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
		_gvert(st, tl, Vector2(0, 0))
		_gvert(st, tr, Vector2(1, 0))
		_gvert(st, bl, Vector2(0, 1))
		_gvert(st, tr, Vector2(1, 0))
		_gvert(st, br, Vector2(1, 1))
		_gvert(st, bl, Vector2(0, 1))
	return st.commit()


func _gvert(st: SurfaceTool, p: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(p)


## Digging tears up the grass around the hole.
func _on_dug(center: Vector3, radius: float) -> void:
	var reach := radius + 0.3
	var c0 := Vector2i(floori((center.x - reach) / GRASS_CELL), floori((center.z - reach) / GRASS_CELL))
	var c1 := Vector2i(floori((center.x + reach) / GRASS_CELL), floori((center.z + reach) / GRASS_CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			if not _grass_cells.has(cell):
				continue
			for idx in _grass_cells[cell]:
				var p := _grass_pos[idx]
				if Vector2(p.x - center.x, p.z - center.z).length() < reach:
					_grass_mm.set_instance_transform(idx, _hidden)
