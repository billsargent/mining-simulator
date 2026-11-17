extends RefCounted
## Helpers for building simple props in code: shared materials, boxes, cylinders, hoses, signs.
## Placeholder art until real models arrive.

const Tex = preload("res://scripts/util/tex.gd")

static var _mats := {}


static func mat(key: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_mats[key] = m
	return m


static func aluminum() -> StandardMaterial3D:
	return mat("aluminum", Color(0.74, 0.75, 0.77), 0.35, 0.85)


static func steel() -> StandardMaterial3D:
	return mat("steel", Color(0.22, 0.23, 0.24), 0.5, 0.7)


static func paint(key: String, color: Color) -> StandardMaterial3D:
	return mat("paint_" + key, color, 0.45)


static func galvanized() -> StandardMaterial3D:
	if _mats.has("galvanized"):
		return _mats["galvanized"]
	var m := mat("galvanized", Color(0.62, 0.64, 0.66), 0.45, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func hose() -> StandardMaterial3D:
	if _mats.has("hose"):
		return _mats["hose"]
	var m := mat("hose", Color(0.08, 0.09, 0.1), 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func gold() -> StandardMaterial3D:
	if _mats.has("gold"):
		return _mats["gold"]
	var m := mat("gold", Color(1.0, 0.8, 0.3), 0.3, 0.65)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.2)
	m.emission_energy_multiplier = 0.6
	return m


static func gravel() -> StandardMaterial3D:
	if _mats.has("gravel"):
		return _mats["gravel"]
	var m := mat("gravel", Color(0.5, 0.46, 0.4), 0.95)
	m.albedo_texture = Tex.noise(0.2, 44, 128)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3, 3, 3)
	return m


static func wood(key: String = "wood", color: Color = Color(0.46, 0.33, 0.21)) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := mat(key, color, 0.85)
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.08
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	m.albedo_texture = t
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.5, 0.3, 1.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func flow_material() -> ShaderMaterial:
	if _mats.has("flow"):
		return _mats["flow"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/flow.gdshader")
	m.set_shader_parameter("ripple", Tex.noise(0.06, 21, 128, true, 3.0))
	_mats["flow"] = m
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _instance(parent, b, pos, material, rot)


static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material,
		rot: Vector3 = Vector3.ZERO, top_radius: float = -1.0, segments: int = 12, caps: bool = true) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return _instance(parent, c, pos, material, rot)


static func _instance(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func collider(body: CollisionObject3D, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)
	return cs


static func label(parent: Node3D, text: String, pos: Vector3, size: int = 40) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.position = pos
	l.modulate = Color(0.95, 0.92, 0.85)
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.shaded = true
	parent.add_child(l)
	return l


## A round tube through the given points (used for hoses).
static func tube(points: PackedVector3Array, radius: float, sides: int = 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var rings: Array = []
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.01:
			side = t.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(t).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var dir := side * cos(a) + up * sin(a)
			ring.append([points[i] + dir * radius, dir])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			for e in [rings[i][k], rings[i][k2], rings[i + 1][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]]:
				st.set_normal(e[1])
				st.add_vertex(e[0])
	return st.commit()
