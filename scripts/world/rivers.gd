extends Node3D
## Water surfaces: one ribbon per river that follows it downhill. The ribbon is wider than the
## channel; the banks hide the extra. Creeks stop just inside the main river so the two
## surfaces don't fight.

const WorldGen = preload("res://scripts/world/world_gen.gd")
const Tex = preload("res://scripts/util/tex.gd")

const MARGIN := 4.0


func build(world: WorldGen) -> void:
	var shader: Shader = load("res://shaders/water.gdshader")
	var wave_a := Tex.noise(0.02, 11, 256, true, 3.0)
	var wave_b := Tex.noise(0.035, 12, 256, true, 2.0)
	var main_hw: float = (world.rivers[0]["hw"] as PackedFloat32Array)[0]
	for r in world.rivers:
		var pts: PackedVector2Array = r["pts"]
		var wl: PackedFloat32Array = r["wl"]
		var hw: PackedFloat32Array = r["hw"]
		var n := pts.size()
		var stop := n
		if not r["main"]:
			while stop > 3 and pts[stop - 1].distance_to(pts[n - 1]) < main_hw - 1.0:
				stop -= 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var along := 0.0
		for i in stop:
			if i > 0:
				along += pts[i].distance_to(pts[i - 1])
			var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var w := hw[i] + MARGIN
			var left := pts[i] + side * w
			var right := pts[i] - side * w
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(along, -w))
			st.add_vertex(Vector3(left.x, wl[i], left.y))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(along, w))
			st.add_vertex(Vector3(right.x, wl[i], right.y))
		for i in stop - 1:
			var a := i * 2
			# Two triangles per section, wound so the top faces up.
			for k in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
				st.add_index(k)
		st.generate_tangents()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("wave_a", wave_a)
		mat.set_shader_parameter("wave_b", wave_b)
		mat.set_shader_parameter("flow_speed", 0.7 if r["main"] else 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
