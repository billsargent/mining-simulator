extends "res://scripts/machines/machine.gd"
## Water pump: set it at the creek's edge. Any high banker within 45 m hooks up to it on its own.

const REACH := 2.5

var _engine: Node3D
var _intake: MeshInstance3D
var _t := 0.0


func _init() -> void:
	kind = "pump"
	display_name = "Water pump"
	processes = false


func water_problem() -> String:
	if _water_point() == Vector3.INF:
		return "set it at the creek's edge"
	return ""


func info_text() -> String:
	return "The pump feeds any high banker within 45 m. The hose connects itself."


func outlet_point() -> Vector3:
	return to_global(Vector3(0.2, 0.36, 0.0))


## A spot in the creek the intake hose can reach, or Vector3.INF.
func _water_point() -> Vector3:
	if loaded_on != null:
		return Vector3.INF
	var p := global_position
	if terrain.water_depth(p.x, p.z) > 0.1:
		return Vector3(p.x, terrain.water_level(p.x, p.z) - 0.15, p.z)
	for ring: float in [1.2, REACH]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * ring
			if terrain.water_depth(q.x, q.z) > 0.1:
				return Vector3(q.x, terrain.water_level(q.x, q.z) - 0.15, q.z)
	return Vector3.INF


func _build() -> void:
	var red := Parts.paint("red", Color(0.62, 0.1, 0.07))
	var dark := Parts.mat("engine", Color(0.12, 0.12, 0.13), 0.55, 0.5)
	var alu := Parts.aluminum()
	var steel := Parts.steel()
	# Tubular roll frame: two bent loops joined by rails, on rubber feet.
	for z: float in [-0.2, 0.2]:
		var pts := PackedVector3Array()
		for k in 9:
			var a := PI * k / 8.0
			pts.append(Vector3(-0.27 * cos(a), 0.03 + 0.44 * sin(a), z))
		var loop := MeshInstance3D.new()
		loop.mesh = Parts.tube(pts, 0.014, 8)
		loop.material_override = red
		add_child(loop)
		Parts.cyl(self, 0.014, 0.56, Vector3(0, 0.03, z), red, Vector3(0, 0, PI / 2.0), -1.0, 8)
		for x: float in [-0.25, 0.25]:
			Parts.box(self, Vector3(0.05, 0.02, 0.05), Vector3(x, 0.01, z), Parts.hose())
	for x: float in [-0.2, 0.2]:
		Parts.cyl(self, 0.012, 0.4, Vector3(x, 0.03, 0), red, Vector3(PI / 2.0, 0, 0), -1.0, 8)
	Parts.box(self, Vector3(0.5, 0.012, 0.32), Vector3(0, 0.045, 0), steel)
	_engine = Node3D.new()
	add_child(_engine)
	# Engine: crankcase, finned cylinder, fuel tank, recoil starter, air filter, muffler.
	Parts.box(_engine, Vector3(0.24, 0.16, 0.24), Vector3(-0.08, 0.13, 0.0), dark)
	Parts.box(_engine, Vector3(0.14, 0.12, 0.14), Vector3(-0.1, 0.27, 0.04), dark, Vector3(0.35, 0, 0))
	for i in 4:
		Parts.box(_engine, Vector3(0.17, 0.006, 0.17), Vector3(-0.1, 0.235 + i * 0.022, 0.05 + i * 0.008), alu, Vector3(0.35, 0, 0))
	Parts.box(_engine, Vector3(0.22, 0.09, 0.26), Vector3(-0.1, 0.4, -0.02), red)
	Parts.cyl(_engine, 0.025, 0.03, Vector3(-0.1, 0.455, -0.02), dark)
	Parts.cyl(_engine, 0.09, 0.05, Vector3(-0.22, 0.17, 0.0), red, Vector3(0, 0, PI / 2.0), -1.0, 16)
	Parts.box(_engine, Vector3(0.025, 0.02, 0.06), Vector3(-0.25, 0.2, 0.0), dark)
	Parts.box(_engine, Vector3(0.08, 0.1, 0.07), Vector3(-0.12, 0.28, -0.12), dark)
	Parts.cyl(_engine, 0.035, 0.12, Vector3(-0.0, 0.3, 0.13), steel, Vector3(PI / 2.0, 0, 0), -1.0, 10)
	Parts.box(_engine, Vector3(0.1, 0.06, 0.006), Vector3(0.0, 0.3, 0.195), steel)
	# Pump end: round volute with intake on the side and outlet on top.
	Parts.cyl(_engine, 0.11, 0.1, Vector3(0.12, 0.16, 0.0), alu, Vector3(0, 0, PI / 2.0), -1.0, 18)
	Parts.cyl(_engine, 0.085, 0.03, Vector3(0.18, 0.16, 0.0), alu, Vector3(0, 0, PI / 2.0), -1.0, 18)
	Parts.cyl(_engine, 0.035, 0.1, Vector3(0.25, 0.16, 0.0), alu, Vector3(0, 0, PI / 2.0), -1.0, 10)
	Parts.cyl(_engine, 0.03, 0.12, Vector3(0.2, 0.3, 0.0), alu, Vector3.ZERO, -1.0, 10)
	Parts.cyl(_engine, 0.04, 0.02, Vector3(0.2, 0.35, 0.0), alu, Vector3.ZERO, -1.0, 10)
	Parts.cyl(_engine, 0.012, 0.03, Vector3(0.12, 0.28, 0.06), dark)
	Parts.collider(self, Vector3(0.6, 0.5, 0.45), Vector3(0, 0.25, 0))
	_intake = MeshInstance3D.new()
	_intake.top_level = true
	_intake.material_override = Parts.hose()
	_intake.visible = false
	add_child(_intake)


func _on_moved() -> void:
	var w := _water_point()
	if w == Vector3.INF or carried:
		_intake.visible = false
		return
	var a := to_global(Vector3(0.28, 0.16, 0.0))
	var mid := a.lerp(w, 0.5)
	mid.y = maxf(a.y, w.y) + 0.1
	_intake.mesh = Parts.tube(PackedVector3Array([a, a.lerp(mid, 0.5), mid, mid.lerp(w, 0.5), w]), 0.03)
	_intake.visible = true


func set_carried(c: bool) -> void:
	super(c)
	_on_moved()


func _update_visuals(delta: float) -> void:
	super(delta)
	_t += delta
	if is_running():
		_engine.position = Vector3(sin(_t * 90.0), 0.0, cos(_t * 77.0)) * 0.0015
