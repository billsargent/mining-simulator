extends "res://scripts/machines/machine.gd"
## Sluice box: set it in the creek and it lines itself up with the current, which does the work.
## Feed it by digging right next to it.

const LENGTH := 1.3
const WIDTH := 0.3


func _init() -> void:
	kind = "sluice"
	display_name = "Sluice box"
	hopper_capacity = 4
	seconds_per_shovel = 1.6


func water_problem() -> String:
	var depth := terrain.water_depth(global_position.x, global_position.z)
	if depth < 0.08:
		return "set it in the creek"
	if depth > 0.9:
		return "the water's too deep here"
	return ""


func place_at(pos: Vector3, yaw: float) -> void:
	var ground := terrain.height_at(pos.x, pos.z)
	var level := terrain.water_level(pos.x, pos.z)
	if level - ground >= 0.08:
		# In the creek: line up with the current and sit just under the surface.
		var flow := terrain.world.flow_dir(pos.x, pos.z)
		rotation = Vector3(0.0, atan2(-flow.y, flow.x), 0.0)
		global_position = Vector3(pos.x, maxf(ground, level - 0.14), pos.z)
	else:
		rotation = Vector3(0.0, yaw + PI / 2.0, 0.0)
		global_position = Vector3(pos.x, ground, pos.z)
	_on_moved()


func _build() -> void:
	_tilt = Node3D.new()
	_tilt.position = Vector3(-LENGTH * 0.5, 0.02, 0.0)
	add_child(_tilt)
	_build_bed(_tilt, LENGTH, WIDTH)
	# Flared head that funnels water in: a sloped floor apron and two angled wings.
	var alu := Parts.aluminum()
	Parts.box(_tilt, Vector3(0.3, 0.008, WIDTH + 0.16), Vector3(-0.15, 0.004, 0.0), alu, Vector3(0, 0, 0.05))
	for s: float in [-1.0, 1.0]:
		Parts.box(_tilt, Vector3(0.32, 0.13, 0.008), Vector3(-0.15, 0.065, s * (WIDTH * 0.5 + 0.06)), alu, Vector3(0, s * 0.4, 0))
		Parts.cyl(_tilt, 0.008, 0.32, Vector3(-0.15, 0.13, s * (WIDTH * 0.5 + 0.06)), alu, Vector3(0, s * 0.4, PI / 2.0), -1.0, 6)
	# Adjustable legs: a crossbar and two screw feet at each end set the drop.
	var steel := Parts.steel()
	for x: float in [0.08, LENGTH - 0.12]:
		Parts.box(_tilt, Vector3(0.025, 0.025, WIDTH + 0.08), Vector3(x, -0.03, 0.0), steel)
		for s: float in [-1.0, 1.0]:
			var z := s * (WIDTH * 0.5 + 0.03)
			Parts.cyl(_tilt, 0.008, 0.1, Vector3(x, -0.08, z), steel, Vector3.ZERO, -1.0, 6)
			Parts.cyl(_tilt, 0.025, 0.012, Vector3(x, -0.13, z), steel, Vector3.ZERO, -1.0, 8)
	# Handles to carry it by.
	for x: float in [0.25, LENGTH - 0.25]:
		for s: float in [-1.0, 1.0]:
			Parts.box(_tilt, Vector3(0.1, 0.012, 0.03), Vector3(x, 0.115, s * (WIDTH * 0.5 + 0.018)), Parts.hose())
	Parts.collider(self, Vector3(LENGTH + 0.1, 0.2, 0.42), Vector3(0.0, 0.08, 0.0))
