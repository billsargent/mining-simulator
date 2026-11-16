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
	# Flared head that funnels water in.
	var alu := Parts.aluminum()
	for s: float in [-1.0, 1.0]:
		Parts.box(_tilt, Vector3(0.26, 0.13, 0.008), Vector3(-0.11, 0.065, s * (WIDTH * 0.5 + 0.05)), alu, Vector3(0, s * 0.4, 0))
	Parts.collider(self, Vector3(LENGTH + 0.1, 0.2, 0.42), Vector3(0.0, 0.08, 0.0))
