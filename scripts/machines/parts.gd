extends RefCounted
## Helpers for building simple props in code: shared materials, boxes, cylinders, hoses, signs.
## Materials wear CC0 photo textures (assets/textures) laid on by triplanar mapping, tinted to
## each material's chosen color.

const Tex = preload("res://scripts/util/tex.gd")

static var _mats := {}

## Materials that wear a photo texture: key -> [texture set, repeats per metre, normal strength].
const DRESS := {
	"roof": ["roof", 0.8, 1.0], "old_roof": ["planks", 0.6, 1.0], "iron": ["rust", 1.0, 0.6],
	"stone": ["boulder", 1.2, 1.0], "rock_face": ["rock", 0.5, 1.0], "rust": ["rust", 1.0, 1.0],
	"tire": ["rough_wood", 2.0, 0.4], "track": ["rust", 2.0, 0.8],
}


static func mat(key: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_mats[key] = m
	if DRESS.has(key):
		var d: Array = DRESS[key]
		Tex.dress_as(m, d[0], d[1], color, d[2])
		m.roughness = maxf(roughness, 0.6)
	return m


static func aluminum() -> StandardMaterial3D:
	return mat("aluminum", Color(0.74, 0.75, 0.77), 0.35, 0.85)


static func steel() -> StandardMaterial3D:
	if _mats.has("steel"):
		return _mats["steel"]
	var m := mat("steel", Color(0.22, 0.23, 0.24), 0.5, 0.7)
	Tex.dress_as(m, "rust", 1.2, Color(0.24, 0.23, 0.22), 0.7)
	m.metallic = 0.6
	return m


## Painted metal: the chosen color, with the dents and wear of old steel showing through.
static func paint(key: String, color: Color) -> StandardMaterial3D:
	if _mats.has("paint_" + key):
		return _mats["paint_" + key]
	var m := mat("paint_" + key, color, 0.45)
	if key != "pvc":
		m.normal_enabled = true
		m.normal_texture = Tex.photo("rust", "normal")
		m.normal_scale = 0.35
		m.roughness_texture = Tex.photo("rust", "rough")
		m.roughness = 0.75
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 1.2
	return m


static func galvanized() -> StandardMaterial3D:
	if _mats.has("galvanized"):
		return _mats["galvanized"]
	var m := mat("galvanized", Color(0.62, 0.64, 0.66), 0.45, 0.8)
	m.normal_enabled = true
	m.normal_texture = Tex.photo("iron", "normal")
	m.normal_scale = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.5
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
	Tex.dress_as(m, "gravel", 1.5, Color(0.5, 0.46, 0.4))
	if m.albedo_texture == null:
		m.albedo_texture = Tex.noise(0.2, 44, 128)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(3, 3, 3)
	return m


## Wood: sawn planks for boards, doors and furniture; rough hewn wood for logs, timbers and poles.
static func wood(key: String = "wood", color: Color = Color(0.46, 0.33, 0.21)) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := mat(key, color, 0.85)
	var rough := false
	for w in ["log", "timber", "pole", "skid", "stump", "post"]:
		if key.contains(w):
			rough = true
	Tex.dress_as(m, "rough_wood" if rough else "planks", 0.9 if rough else 0.7, color)
	if m.albedo_texture == null:
		m.albedo_texture = Tex.noise(0.08, 7, 256)
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


# --- Vehicle art ----------------------------------------------------------------------------

static func rubber() -> StandardMaterial3D:
	return mat("rubber", Color(0.06, 0.06, 0.065), 0.92)


static func chrome() -> StandardMaterial3D:
	return mat("chrome", Color(0.7, 0.7, 0.72), 0.25, 0.9)


static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.55, 0.6, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = m
	return m


## A lens that glows a little (tail lights, markers).
static func lens(key: String, color: Color, glow: float = 0.6) -> StandardMaterial3D:
	if _mats.has("lens_" + key):
		return _mats["lens_" + key]
	var m := mat("lens_" + key, color, 0.2)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = glow
	return m


## A side profile (points as (z, y), in order) pushed out to the given width along x and
## centred on x. Good for hoods, fenders, cabs and bevelled panels.
static func extrude(parent: Node3D, profile: PackedVector2Array, width: float, x: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var hw := width * 0.5
	var ccw := Geometry2D.is_polygon_clockwise(profile) == false
	var tris := Geometry2D.triangulate_polygon(profile)
	for side: float in [-1.0, 1.0]:
		var nrm := Vector3(side, 0, 0)
		for t in range(0, tris.size(), 3):
			var idx := [tris[t], tris[t + 1], tris[t + 2]]
			var v: Array = []
			for i: int in idx:
				v.append(Vector3(x + side * hw, profile[i].y, profile[i].x))
			_tris(st, v, nrm)
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var d := b - a
		var out := Vector2(d.y, -d.x).normalized() * (1.0 if ccw else -1.0)
		var nrm := Vector3(0, out.y, out.x)
		var l := Vector3(x - hw, a.y, a.x)
		var r := Vector3(x + hw, a.y, a.x)
		var l2 := Vector3(x - hw, b.y, b.x)
		var r2 := Vector3(x + hw, b.y, b.x)
		var quad := [l, r, r2, l, r2, l2]
		_tris(st, quad, nrm)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	parent.add_child(mi)
	return mi


## A box with chamfered edges along x (a bevelled panel), size and centre as for box().
static func bevel_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, bevel: float = 0.04) -> MeshInstance3D:
	var hz := size.z * 0.5
	var hy := size.y * 0.5
	var b := minf(bevel, minf(hz, hy) * 0.9)
	var p := PackedVector2Array([Vector2(-hz + b, -hy), Vector2(hz - b, -hy), Vector2(hz, -hy + b), Vector2(hz, hy - b),
			Vector2(hz - b, hy), Vector2(-hz + b, hy), Vector2(-hz, hy - b), Vector2(-hz, -hy + b)])
	for i in p.size():
		p[i] += Vector2(pos.z, pos.y)
	return extrude(parent, p, size.x, pos.x, material)


## A tyre with tread blocks round it, axle along x.
static func tire_mesh(radius: float, width: float, lugs: int = 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := lugs * 2
	var hw := width * 0.5
	var inner := radius * 0.62
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var r := radius if k % 2 == 0 else radius * 0.93
		var c0 := Vector3(0, cos(a0), sin(a0))
		var c1 := Vector3(0, cos(a1), sin(a1))
		var mid := (c0 + c1).normalized()
		# Tread face (shoulders rounded in a little).
		var sh := hw * 0.82
		for q in [[Vector3(-sh, 0, 0), Vector3(sh, 0, 0), r, r, mid], [Vector3(-hw, 0, 0), Vector3(-sh, 0, 0), r * 0.96, r, (mid + Vector3(-0.6, 0, 0)).normalized()],
				[Vector3(sh, 0, 0), Vector3(hw, 0, 0), r, r * 0.96, (mid + Vector3(0.6, 0, 0)).normalized()]]:
			var xa: Vector3 = q[0]
			var xb: Vector3 = q[1]
			var ra: float = q[2]
			var rb: float = q[3]
			var nrm: Vector3 = q[4]
			var v := [xa + c0 * ra, xb + c0 * rb, xb + c1 * rb, xa + c0 * ra, xb + c1 * rb, xa + c1 * ra]
			_tris(st, v, nrm)
		# Lug walls between high and low blocks.
		var nr := Vector3(0, -sin(a1), cos(a1)) * (1.0 if k % 2 == 0 else -1.0)
		var w := [Vector3(-hw, 0, 0) + c1 * radius * 0.93, Vector3(hw, 0, 0) + c1 * radius * 0.93, Vector3(hw, 0, 0) + c1 * radius,
				Vector3(-hw, 0, 0) + c1 * radius * 0.93, Vector3(hw, 0, 0) + c1 * radius, Vector3(-hw, 0, 0) + c1 * radius]
		_tris(st, w, nr)
		# Sidewalls.
		for s: float in [-1.0, 1.0]:
			var x := Vector3(s * hw, 0, 0)
			var x2 := Vector3(s * hw * 0.8, 0, 0)
			var ro := r * 0.96
			var sw := [x + c0 * ro, x + c1 * ro, x2 + c1 * inner, x + c0 * ro, x2 + c1 * inner, x2 + c0 * inner]
			_tris(st, sw, Vector3(s, 0, 0))
	return st.commit()


## Dresses a wheel holder (axle along x): tyre, dished rim, hub cap and lug nuts.
static func wheel(holder: Node3D, radius: float, width: float, rim_color: Color) -> void:
	var ti := MeshInstance3D.new()
	ti.mesh = tire_mesh(radius, width)
	ti.material_override = rubber()
	holder.add_child(ti)
	var rim := mat("rim_%s" % rim_color.to_html(false), rim_color, 0.35, 0.75)
	var rr := radius * 0.62
	cyl(holder, rr, width * 0.82, Vector3.ZERO, rim, Vector3(0, 0, PI / 2.0), -1.0, 16)
	for s: float in [-1.0, 1.0]:
		cyl(holder, rr * 0.55, 0.03, Vector3(s * width * 0.42, 0, 0), rim, Vector3(0, 0, PI / 2.0), rr * 0.42, 10)
		cyl(holder, rr * 0.2, 0.05, Vector3(s * width * 0.44, 0, 0), chrome(), Vector3(0, 0, PI / 2.0), -1.0, 8)
		for k in 5:
			var a := TAU * k / 5.0
			cyl(holder, 0.014, 0.03, Vector3(s * width * 0.44, cos(a) * rr * 0.34, sin(a) * rr * 0.34), chrome(),
					Vector3(0, 0, PI / 2.0), -1.0, 6)
		for k in 6:                                                   # spokes between holes
			var a := TAU * (k + 0.5) / 6.0
			box(holder, Vector3(0.02, rr * 0.5, 0.04), Vector3(s * width * 0.4, cos(a) * rr * 0.7, sin(a) * rr * 0.7), rim, Vector3(a, 0, 0))


## Adds triangles (three points each), wound so they face along nrm.
static func _tris(st: SurfaceTool, pts: Array, nrm: Vector3) -> void:
	for t in range(0, pts.size(), 3):
		var a: Vector3 = pts[t]
		var b: Vector3 = pts[t + 1]
		var c: Vector3 = pts[t + 2]
		if (b - a).cross(c - a).dot(nrm) > 0.0:     # Godot's front faces wind clockwise
			var tmp := b
			b = c
			c = tmp
		for q: Vector3 in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(q)


## Side profile of an arch (a fender) over a wheel at (z, y): a shell between two radii.
static func arch(zc: float, yc: float, r_in: float, r_out: float, a0: float = 0.15, a1: float = PI - 0.15, steps: int = 10) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		p.append(Vector2(zc + cos(a) * r_out, yc + sin(a) * r_out))
	for k in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(k) / steps)
		p.append(Vector2(zc + cos(a) * r_in, yc + sin(a) * r_in))
	return p
