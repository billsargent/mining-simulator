extends "res://scripts/machines/machine.gd"
## High banker: a sluice on legs with a hopper, fed by a pump. Set it up on the bank, even well
## away from the water. The hose to the nearest pump connects itself.

const HOSE_RANGE := 45.0
const HOPPER_X := -0.55
const HOPPER_Y := 1.05

var pump = null
var _hose: MeshInstance3D
var _hose_key := ""
var _check_t := 0.0
var _tailings: MeshInstance3D


func _init() -> void:
	kind = "high_banker"
	display_name = "High banker"
	hopper_capacity = 8
	seconds_per_shovel = 1.2
	recovery_bonus = 0.04      # classified feed through the grizzly bars catches a little better
	angle = 7.0


func water_problem() -> String:
	if terrain.water_depth(global_position.x, global_position.z) > 0.0:
		return "set it up on dry ground"
	if pump == null:
		return "no water: set the pump at the creek's edge within %d m" % int(HOSE_RANGE)
	return ""


func info_text() -> String:
	return "Any pump within %d m feeds it; the hose connects itself." % int(HOSE_RANGE)


func refresh_pump() -> void:
	pump = _find_pump()
	_rebuild_hose()


func _find_pump():
	var best = null
	var best_d := HOSE_RANGE
	if loaded_on != null:
		return null
	for m in get_tree().get_nodes_in_group("machines"):
		if m.kind != "pump" or m.carried or m.loaded_on != null or m.water_problem() != "":
			continue
		var d := global_position.distance_to(m.global_position)
		if d < best_d:
			best = m
			best_d = d
	return best


func _on_moved() -> void:
	refresh_pump()
	_update_tailings()


func _update_visuals(delta: float) -> void:
	super(delta)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		pump = null if loaded_on != null else _find_pump()
		_rebuild_hose()


func _on_processed() -> void:
	super()
	_update_tailings()


func _build() -> void:
	var frame := Parts.steel()
	var alu := Parts.aluminum()
	for z: float in [-0.24, 0.24]:
		Parts.box(self, Vector3(0.05, HOPPER_Y, 0.05), Vector3(HOPPER_X, HOPPER_Y * 0.5, z), frame)
		Parts.box(self, Vector3(0.05, 0.75, 0.05), Vector3(1.0, 0.375, z), frame)
		Parts.box(self, Vector3(1.6, 0.04, 0.04), Vector3(0.22, 0.45, z), frame)
	# Hopper with grizzly bars on top and a spray bar to wash material through.
	Parts.box(self, Vector3(0.6, 0.02, 0.5), Vector3(HOPPER_X, HOPPER_Y, 0.0), alu)
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(0.6, 0.3, 0.02), Vector3(HOPPER_X, HOPPER_Y + 0.15, s * 0.25), alu)
	Parts.box(self, Vector3(0.02, 0.3, 0.5), Vector3(HOPPER_X - 0.3, HOPPER_Y + 0.15, 0.0), alu)
	for i in 6:
		Parts.cyl(self, 0.008, 0.62, Vector3(HOPPER_X, HOPPER_Y + 0.31, -0.2 + i * 0.08), frame, Vector3(0, 0, PI / 2.0), -1.0, 6)
	Parts.cyl(self, 0.015, 0.5, Vector3(HOPPER_X - 0.25, HOPPER_Y + 0.36, 0.0), Parts.paint("pvc", Color(0.9, 0.9, 0.88)), Vector3(PI / 2.0, 0, 0), -1.0, 8)
	# The sluice section tilts with the angle knob.
	_tilt = Node3D.new()
	_tilt.position = Vector3(HOPPER_X + 0.3, HOPPER_Y - 0.02, 0.0)
	add_child(_tilt)
	_build_bed(_tilt, 1.4, 0.3)
	Parts.collider(self, Vector3(2.0, 1.4, 0.6), Vector3(0.25, 0.7, 0.0))
	# Hose and tailings pile live in world space.
	_hose = MeshInstance3D.new()
	_hose.top_level = true
	_hose.material_override = Parts.hose()
	_hose.visible = false
	add_child(_hose)
	var pile := SphereMesh.new()
	pile.radius = 1.0
	pile.height = 2.0
	pile.radial_segments = 16
	pile.rings = 8
	_tailings = MeshInstance3D.new()
	_tailings.top_level = true
	_tailings.mesh = pile
	_tailings.material_override = Parts.gravel()
	_tailings.visible = false
	add_child(_tailings)


func _rebuild_hose() -> void:
	if pump == null or carried or loaded_on != null:
		_hose.visible = false
		_hose_key = ""
		return
	var a := to_global(Vector3(HOPPER_X - 0.25, HOPPER_Y + 0.36, 0.0))
	var b: Vector3 = pump.outlet_point()
	var key := "%s|%s" % [a.snapped(Vector3.ONE * 0.01), b.snapped(Vector3.ONE * 0.01)]
	if key == _hose_key:
		_hose.visible = true
		return
	_hose_key = key
	# Lay the hose along the ground between the two machines.
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(4, ceili(flat / 0.8))
	var pts := PackedVector3Array()
	for i in steps + 1:
		var f := float(i) / steps
		var p := a.lerp(b, f)
		var ground := maxf(terrain.height_at(p.x, p.z), terrain.water_level(p.x, p.z) - 0.05) + 0.05
		var to_end := minf(f, 1.0 - f) * flat
		p.y = lerpf(p.y, ground, clampf(to_end / 1.0, 0.0, 1.0))
		pts.append(p)
	_hose.mesh = Parts.tube(pts, 0.025)
	_hose.visible = true


func _update_tailings() -> void:
	if _tailings == null or _tilt == null or not is_inside_tree():
		return
	_tailings.visible = processed_total > 0 and not carried and loaded_on == null
	var outlet := _tilt.to_global(Vector3(1.55, 0.0, 0.0))
	var s := clampf(0.15 + 0.05 * sqrt(float(processed_total)), 0.15, 1.1)
	_tailings.global_position = Vector3(outlet.x, terrain.height_at(outlet.x, outlet.z), outlet.z)
	_tailings.scale = Vector3(s, s * 0.45, s)
