extends "res://scripts/machines/machine.gd"
## Dry washer: for gold where there is no water. A small engine blows puffs of air up through a
## cloth under a riffle tray; dry gravel shaken through the hopper screen walks down the tray and
## the heavy gold stays behind the riffles. Set it on dry ground and feed it by digging next to it.
## It loses more of the finest gold than a wet sluice.

const DRY_PENALTY := -0.1


func _init() -> void:
	kind = "dry_washer"
	display_name = "Dry washer"
	hopper_capacity = 6
	seconds_per_shovel = 1.4
	recovery_bonus = DRY_PENALTY
	angle = 7.0


func water_problem() -> String:
	if terrain.water_depth(global_position.x, global_position.z) > 0.0:
		return "it works dry: set it on dry ground"
	var wl: float = terrain.water_level(global_position.x, global_position.z)
	if wl > global_position.y - 0.3:
		return "the ground here is too wet: move it away from the water"
	return ""


func place_at(pos: Vector3, yaw: float) -> void:
	rotation = Vector3(0.0, yaw + PI / 2.0, 0.0)
	global_position = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	_on_moved()


func info_text() -> String:
	return "No water needed: it blows air up through the riffles."


func _status_bb() -> String:
	return super().replace("Running: feed it", "Running: dig next to it to feed it")


func _build() -> void:
	var steel := Parts.steel()
	var paint := Parts.paint("washer_green", Color(0.25, 0.32, 0.2))
	# Legs: taller at the hopper end, so the tray slopes down.
	for p: Vector3 in [Vector3(-0.6, 0.0, -0.25), Vector3(-0.6, 0.0, 0.25), Vector3(0.6, 0.0, -0.25), Vector3(0.6, 0.0, 0.25)]:
		var h := 0.95 if p.x < 0.0 else 0.6
		Parts.box(self, Vector3(0.04, h, 0.04), p + Vector3(0, h * 0.5, 0), steel)
	# The riffle tray, on the tilt node like every sluice, minus the water.
	_tilt = Node3D.new()
	_tilt.position = Vector3(-0.65, 0.88, 0.0)
	add_child(_tilt)
	_build_bed(_tilt, 1.3, 0.34)
	if _flow:
		_flow.queue_free()
		_flow = null
	# Bellows box under the tray, a hopper with a screen on top, and the blower engine.
	Parts.box(_tilt, Vector3(1.2, 0.12, 0.36), Vector3(0.65, -0.08, 0.0), paint)
	Parts.box(self, Vector3(0.4, 0.3, 0.42), Vector3(-0.62, 1.15, 0.0), paint)
	Parts.box(self, Vector3(0.38, 0.01, 0.4), Vector3(-0.62, 1.31, 0.0), Parts.mat("screen", Color(0.3, 0.3, 0.3), 0.6, 0.6))
	Parts.box(self, Vector3(0.3, 0.26, 0.26), Vector3(-0.2, 0.2, 0.42), Parts.paint("engine_red", Color(0.55, 0.14, 0.1)))
	var duct := MeshInstance3D.new()
	duct.mesh = Parts.tube(PackedVector3Array([Vector3(-0.2, 0.33, 0.42), Vector3(-0.1, 0.55, 0.3), Vector3(0.0, 0.75, 0.15)]), 0.05, 8)
	duct.material_override = Parts.hose()
	add_child(duct)
	Parts.collider(self, Vector3(1.4, 1.3, 0.6), Vector3(0, 0.65, 0.05))
