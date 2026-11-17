extends "res://scripts/machines/high_banker.gd"
## Trommel: a turning screen drum over a long sluice, for volume work. Gravel goes in the hopper,
## the drum washes and screens it, and the fines run over the riffles. Like the high banker it
## takes water from the nearest pump (the hose connects itself). Feed it with the mini-excavator,
## or dig next to it by hand.

var _drum: Node3D


func _init() -> void:
	kind = "trommel"
	display_name = "Trommel"
	hopper_capacity = 24
	seconds_per_shovel = 0.45
	recovery_bonus = 0.06      # screened, washed feed catches best of all
	angle = 6.5


func info_text() -> String:
	return "Any pump within %d m feeds it. Load it with the mini-excavator." % int(HOSE_RANGE)


func _build() -> void:
	var frame := Parts.paint("trommel_frame", Color(0.6, 0.45, 0.12))
	var steel := Parts.steel()
	# Skid frame.
	for z: float in [-0.55, 0.55]:
		Parts.box(self, Vector3(3.6, 0.12, 0.12), Vector3(0.4, 0.1, z), frame)
	for x: float in [-1.2, 0.2, 1.8]:
		Parts.box(self, Vector3(0.1, 1.2, 1.2), Vector3(x, 0.65, 0.0), frame)
	# Hopper at the high end.
	Parts.box(self, Vector3(1.0, 0.06, 1.1), Vector3(-1.4, 1.7, 0.0), steel)
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(1.0, 0.55, 0.05), Vector3(-1.4, 1.95, s * 0.55), steel, Vector3(s * 0.3, 0, 0))
	Parts.box(self, Vector3(0.05, 0.55, 1.1), Vector3(-1.9, 1.95, 0.0), steel)
	# The drum: a perforated cylinder that turns while it runs.
	_drum = Node3D.new()
	_drum.position = Vector3(0.2, 1.35, 0.0)
	_drum.rotation.z = -0.08
	add_child(_drum)
	var screen := Parts.mat("trommel_screen", Color(0.35, 0.35, 0.36), 0.5, 0.7)
	Parts.cyl(_drum, 0.5, 2.6, Vector3.ZERO, screen, Vector3(0, 0, PI / 2.0), -1.0, 16, false)
	for x: float in [-1.2, 0.0, 1.2]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.49
		ring.outer_radius = 0.56
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = steel
		mi.position = Vector3(x, 0, 0)
		mi.rotation = Vector3(0, 0, PI / 2.0)
		_drum.add_child(mi)
	Parts.cyl(self, 0.03, 2.8, Vector3(0.2, 1.95, 0.0), Parts.paint("pvc", Color(0.9, 0.9, 0.88)), Vector3(0, 0, PI / 2.0), -1.0, 8)
	# The sluice under the drum, on the angle knob.
	_tilt = Node3D.new()
	_tilt.position = Vector3(-0.8, 0.75, 0.0)
	add_child(_tilt)
	_build_bed(_tilt, 2.4, 0.5)
	# A small engine turns the drum.
	Parts.box(self, Vector3(0.45, 0.4, 0.4), Vector3(1.9, 0.45, 0.45), Parts.paint("engine_red", Color(0.55, 0.14, 0.1)))
	Parts.label(self, "TROMMEL", Vector3(0.2, 2.2, 0.0), 30)
	Parts.collider(self, Vector3(3.6, 2.3, 1.3), Vector3(0.3, 1.15, 0.0))
	# Hose and tailings pile live in world space (as for the high banker).
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


func _update_visuals(delta: float) -> void:
	super(delta)
	if _drum != null and is_running() and not hopper.is_empty():
		_drum.rotate_object_local(Vector3.RIGHT, delta * 2.2)
