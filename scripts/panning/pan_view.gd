extends Node3D
## The gold pan held in front of the camera, and the panning controls.
##   Hold LMB         shake, so heavy gold sinks to the bottom
##   Hold RMB         tilt the pan and wash the top layer off
##   Mouse fwd/back   set how far the pan tilts while washing
##   Mouse sideways   swirl
##   E                collect the gold once only black sand and gold are left
##   Q                dump the pan

signal finished(kept: PackedFloat32Array, lost: PackedFloat32Array, black_sand: int)
signal cancelled

const Settings = preload("res://scripts/core/settings.gd")
const PanSim = preload("res://scripts/panning/pan_sim.gd")

const VIEW_ANGLE := 48.0      # how far the pan is tipped toward you so you can see in
const FLOOR_R := 0.115
const LIP_R := 0.19
const DEPTH := 0.055
const TILT_SENS := 0.08
const SWIRL_SENS := 0.006
const PAD_TILT := 40.0      # degrees a second at full stick
const PAD_SWIRL := 6.0
const GRAVEL_COLORS = [
	Color(0.55, 0.52, 0.47), Color(0.45, 0.40, 0.34), Color(0.70, 0.68, 0.64),
	Color(0.52, 0.37, 0.26), Color(0.36, 0.36, 0.37),
]

var sim: PanSim
var hud
var tilt := 0.0
var wash_target := 16.0
var scripted := false          # true when a test drives the pan instead of the mouse
var shaking := false
var washing := false

var _swirl := 0.0
var _t := 0.0
var _body: Node3D
var _grain_mm: MultiMesh
var _gold_mm: MultiMesh
var _slot := PackedInt32Array()
var _basis: Array[Basis] = []
var _water_mat: StandardMaterial3D
var _sediment: MeshInstance3D
var _sediment_mat: StandardMaterial3D
var _revealed := false
var _stall_t := 0.0
var _stall_mark := 1.0
var _rng := RandomNumberGenerator.new()
var _hidden := Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -5, 0))


func setup(dirt, hud_ref, rng_seed: int = 0) -> void:
	hud = hud_ref
	sim = PanSim.new()
	sim.setup(dirt, rng_seed)
	sim.gold_washed_out.connect(_on_gold_washed_out)
	position = Vector3(0.0, -0.13, -0.42)
	_body = Node3D.new()
	add_child(_body)
	_build_pan()
	_build_sediment()
	_build_water()
	_build_grains()
	_update_grains()


func _input(event: InputEvent) -> void:
	if scripted:
		return
	if event is InputEventMouseMotion and Settings.mouse_captured():
		var motion := event as InputEventMouseMotion
		if washing:
			wash_target = clampf(wash_target - motion.relative.y * TILT_SENS, 0.0, PanSim.MAX_TILT)
		_swirl += motion.relative.x * SWIRL_SENS
	elif event.is_action_pressed("interact"):
		if sim.done:
			finished.emit(sim.gold_kept(), sim.gold_lost, sim.black_sand_left())
	elif event.is_action_pressed("pan_dump"):
		cancelled.emit()


func _process(delta: float) -> void:
	_t += delta
	if not scripted:
		var captured := Settings.mouse_captured()
		shaking = captured and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("dig"))
		washing = captured and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_action_pressed("pan_wash"))
		# Controller: right stick up/down sets the tilt while washing, sideways swirls.
		var st := Settings.stick_look()
		if st != Vector2.ZERO:
			if washing:
				wash_target = clampf(wash_target - st.y * PAD_TILT * delta, 0.0, PanSim.MAX_TILT)
			_swirl += st.x * PAD_SWIRL * delta
	tilt = move_toward(tilt, wash_target if washing else 0.0, 50.0 * delta)
	sim.step(delta, shaking, tilt, _swirl)
	_swirl = 0.0
	if sim.done and not _revealed:
		_revealed = true
		sim.arrange_gold_tail(PI / 2.0)
	var off := Vector3(sin(_t * 0.9) * 0.002, sin(_t * 1.3) * 0.0015, 0.0)
	if shaking and not sim.done:
		off += Vector3(sin(_t * 52.0) * 0.005, sin(_t * 31.0) * 0.002, cos(_t * 44.0) * 0.004)
	_body.position = off
	_body.rotation = Vector3(deg_to_rad(VIEW_ANGLE - tilt), 0.0, 0.0)
	_update_grains()
	var murk := sim.material_left()
	_check_stall(delta, murk)
	_water_mat.albedo_color = Color(lerpf(0.30, 0.42, murk), lerpf(0.34, 0.33, murk), lerpf(0.33, 0.22, murk), 0.15 + 0.55 * murk)
	if hud:
		hud.set_pan_status(tilt, wash_target, washing, murk, sim.done, sim.gold_lost.size())


## Washing without shaking stalls: black sand blankets the top. Tell the player why.
func _check_stall(delta: float, left: float) -> void:
	if shaking or sim.done or tilt < PanSim.WASH_START:
		_stall_t = 0.0
		_stall_mark = left
		return
	if _stall_mark - left > 0.03:
		_stall_t = 0.0
		_stall_mark = left
		return
	_stall_t += delta
	if _stall_t > 3.5 and hud:
		hud.toast("Not much is washing off. Shake the pan (hold left mouse) to bring the light stuff to the top.", Color(1.0, 0.9, 0.6), 4.0)
		_stall_t = 0.0


func _on_gold_washed_out(_mass: float) -> void:
	if hud:
		hud.toast("A piece of gold washed out! Shake more before you wash.", Color(1.0, 0.5, 0.4), 2.5)


# --- Visuals -----------------------------------------------------------------------

func _build_pan() -> void:
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(FLOOR_R, 0.0), Vector2(LIP_R, DEPTH), Vector2(LIP_R + 0.012, DEPTH + 0.003),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		for p in prof.size() - 1:
			var q0 := prof[p]
			var q1 := prof[p + 1]
			var v00 := Vector3(cos(a0) * q0.x, q0.y, sin(a0) * q0.x)
			var v01 := Vector3(cos(a1) * q0.x, q0.y, sin(a1) * q0.x)
			var v10 := Vector3(cos(a0) * q1.x, q1.y, sin(a0) * q1.x)
			var v11 := Vector3(cos(a1) * q1.x, q1.y, sin(a1) * q1.x)
			if q0.x > 0.0:
				st.add_vertex(v00)
				st.add_vertex(v01)
				st.add_vertex(v10)
			st.add_vertex(v01)
			st.add_vertex(v11)
			st.add_vertex(v10)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.17, 0.09)
	mat.roughness = 0.38
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	# Rolled rim all the way round.
	var rim := TorusMesh.new()
	rim.inner_radius = LIP_R + 0.002
	rim.outer_radius = LIP_R + 0.016
	rim.rings = 64
	rim.ring_segments = 8
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim
	rmi.material_override = mat
	rmi.position.y = DEPTH + 0.002
	rmi.scale = Vector3(1.0, 0.6, 1.0)
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(rmi)
	_body.add_child(_riffles(mat))


## Three riffles moulded into the far half of the wall: sharp steps that catch gold as you wash.
func _riffles(mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var a_from := PI / 2.0 - 1.25
	var a_to := PI / 2.0 + 1.25
	for r in 3:
		var t := 0.35 + 0.2 * r                 # how far up the wall
		var rad := lerpf(FLOOR_R, LIP_R, t)
		var h := lerpf(0.0, DEPTH, t)
		var p := func(a: float, dr: float, dh: float) -> Vector3:
			return Vector3(cos(a) * (rad + dr), h + dh, sin(a) * (rad + dr))
		for s in segs:
			var a0 := lerpf(a_from, a_to, float(s) / segs)
			var a1 := lerpf(a_from, a_to, float(s + 1) / segs)
			# The step: a narrow ledge sticking in from the wall, then down to it.
			for q in [[0.0, 0.004, -0.006, 0.004], [-0.006, 0.004, -0.006, -0.002]]:
				var v00: Vector3 = p.call(a0, q[0], q[1])
				var v01: Vector3 = p.call(a1, q[0], q[1])
				var v10: Vector3 = p.call(a0, q[2], q[3])
				var v11: Vector3 = p.call(a1, q[2], q[3])
				for v in [v00, v01, v10, v01, v11, v10]:
					st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The mass of material in the pan. Grains below its surface are hidden, so gold
## stays out of sight until the light material is washed off above it.
func _build_sediment() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.134
	cyl.bottom_radius = FLOOR_R
	cyl.height = 1.0
	cyl.radial_segments = 40
	cyl.rings = 1
	_sediment_mat = StandardMaterial3D.new()
	_sediment_mat.roughness = 0.9
	_sediment_mat.albedo_texture = _grain_noise()
	_sediment_mat.uv1_triplanar = true
	_sediment_mat.uv1_scale = Vector3(40, 40, 40)
	_sediment = MeshInstance3D.new()
	_sediment.mesh = cyl
	_sediment.material_override = _sediment_mat
	_sediment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_sediment)


func _grain_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.25
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	var t := NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	t.noise = n
	return t


func _update_sediment(bed: float, left: float) -> void:
	var top := 0.003 + bed * 0.85
	_sediment.scale = Vector3(0.6 + 0.4 * left, top, 0.6 + 0.4 * left)
	_sediment.position.y = top * 0.5
	var black := Color(0.09, 0.09, 0.1)
	var mud := Color(0.46, 0.4, 0.31)
	_sediment_mat.albedo_color = black.lerp(mud, clampf(left * 1.3, 0.0, 1.0))


func _build_water() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.152
	cyl.bottom_radius = 0.152
	cyl.height = 0.001
	cyl.radial_segments = 40
	_water_mat = StandardMaterial3D.new()
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.05
	_water_mat.albedo_color = Color(0.42, 0.33, 0.22, 0.7)
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _water_mat
	mi.position.y = 0.028
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


func _build_grains() -> void:
	var n := sim.count()
	var n_gold := 0
	for i in n:
		if sim.kind[i] == PanSim.GOLD:
			n_gold += 1
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var grain_mat := StandardMaterial3D.new()
	grain_mat.vertex_color_use_as_albedo = true
	grain_mat.vertex_color_is_srgb = true
	grain_mat.roughness = 0.75
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.8, 0.3)
	gold_mat.metallic = 0.65
	gold_mat.roughness = 0.32
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(1.0, 0.72, 0.2)
	gold_mat.emission_energy_multiplier = 0.7
	_grain_mm = _make_multimesh(sphere, n - n_gold, true, grain_mat)
	_gold_mm = _make_multimesh(_flake_mesh(), n_gold, false, gold_mat)
	_slot.resize(n)
	_basis.resize(n)
	var gi := 0
	var ri := 0
	for i in n:
		var k: int = sim.kind[i]
		var s := 0.0
		var flat := 1.0
		var col := Color.WHITE
		if k == PanSim.GRAVEL:
			s = _rng.randf_range(0.004, 0.0075)
			flat = _rng.randf_range(0.55, 0.9)
			col = (GRAVEL_COLORS[_rng.randi() % GRAVEL_COLORS.size()] as Color) * _rng.randf_range(0.85, 1.15)
		elif k == PanSim.SAND:
			s = _rng.randf_range(0.0019, 0.0027)
			col = Color(0.64, 0.56, 0.42) * _rng.randf_range(0.85, 1.15)
		elif k == PanSim.BLACK_SAND:
			s = _rng.randf_range(0.0016, 0.0021)
			col = Color(0.07, 0.07, 0.08) * _rng.randf_range(0.8, 1.3)
		else:
			var m: float = sim.mass[i]
			s = 0.0018 + 0.0045 * pow(m / 0.01, 1.0 / 3.0)
			flat = 0.45 if m < 0.3 else 1.1
		_basis[i] = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * flat, s))
		if k == PanSim.GOLD:
			_slot[i] = gi
			gi += 1
		else:
			_slot[i] = ri
			col.a = 1.0
			_grain_mm.set_instance_color(ri, col)
			ri += 1


## An irregular, slightly domed flake (radius about 1, scaled per piece).
func _flake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 9
	var ring: Array[Vector3] = []
	for k in n:
		var a := TAU * k / n + _rng.randf_range(-0.2, 0.2)
		var rr := _rng.randf_range(0.6, 1.15)
		ring.append(Vector3(cos(a) * rr, _rng.randf_range(-0.15, 0.15), sin(a) * rr))
	var top := Vector3(0.0, 0.45, 0.0)
	var bottom := Vector3(0.0, -0.35, 0.0)
	for k in n:
		var p0 := ring[k]
		var p1 := ring[(k + 1) % n]
		st.add_vertex(top)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(bottom)
		st.add_vertex(p1)
		st.add_vertex(p0)
	st.generate_normals()
	return st.commit()


func _make_multimesh(mesh: Mesh, count: int, colors: bool, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mmi)
	return mm


func _update_grains() -> void:
	var n := sim.count()
	var lo := 1.0
	var hi := 0.0
	var alive := 0
	for i in n:
		if sim.state[i] == 0:
			alive += 1
			lo = minf(lo, sim.h[i])
			hi = maxf(hi, sim.h[i])
	var span := maxf(hi - lo, 0.04)
	var bed := 0.002 + 0.02 * float(alive) / float(maxi(n, 1))
	_update_sediment(bed, sim.material_left())
	for i in n:
		var is_gold := sim.kind[i] == PanSim.GOLD
		var mm := _gold_mm if is_gold else _grain_mm
		var st: int = sim.state[i]
		if st == 2:
			mm.set_instance_transform(_slot[i], _hidden)
			continue
		var hn := (sim.h[i] - lo) / span
		if _revealed and is_gold:
			hn = 1.1
		var p := _bed_pos(sim.r[i], sim.th[i], hn * bed)
		if st == 1:
			p = _wash_path(p, sim.out_t[i])
		mm.set_instance_transform(_slot[i], Transform3D(_basis[i], p))


func _bed_pos(rr: float, angle: float, lift: float) -> Vector3:
	var rad := 0.006 + rr * 0.128
	var y := 0.003 + maxf(0.0, rad - FLOOR_R) * (DEPTH / (LIP_R - FLOOR_R)) + lift
	return Vector3(cos(angle) * rad, y, sin(angle) * rad)


func _wash_path(p: Vector3, u: float) -> Vector3:
	var lip := Vector3(p.x * 0.4, DEPTH + 0.004, -LIP_R)
	if u < 0.6:
		return p.lerp(lip, u / 0.6)
	var v := (u - 0.6) / 0.4
	return lip + Vector3(0.0, -0.1 * v * v, -0.05 * v)
