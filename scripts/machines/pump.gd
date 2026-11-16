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
	Parts.box(self, Vector3(0.6, 0.03, 0.45), Vector3(0, 0.015, 0), red)
	for x: float in [-0.28, 0.28]:
		for z: float in [-0.2, 0.2]:
			Parts.box(self, Vector3(0.03, 0.48, 0.03), Vector3(x, 0.24, z), red)
	_engine = Node3D.new()
	add_child(_engine)
	Parts.box(_engine, Vector3(0.3, 0.28, 0.3), Vector3(-0.08, 0.2, 0.0), dark)
	Parts.cyl(_engine, 0.1, 0.24, Vector3(-0.08, 0.42, 0.0), red, Vector3(0, 0, PI / 2.0))
	Parts.cyl(_engine, 0.1, 0.12, Vector3(0.17, 0.16, 0.0), Parts.aluminum(), Vector3(0, 0, PI / 2.0))
	Parts.cyl(_engine, 0.03, 0.12, Vector3(0.2, 0.3, 0.0), Parts.aluminum())
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
