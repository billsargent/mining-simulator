extends "res://scripts/vehicles/vehicle.gd"
## Four-wheeler: quick and agile off-road, with a rack for one piece of equipment.


func _init() -> void:
	kind = "atv"
	display_name = "ATV"
	mass = 320.0
	wheel_mounts = [Vector3(-0.5, 0.32, -0.62), Vector3(0.5, 0.32, -0.62), Vector3(-0.5, 0.32, 0.62), Vector3(0.5, 0.32, 0.62)]
	wheel_radius = 0.3
	wheel_width = 0.24
	rest = 0.28
	spring = 5600.0
	damper = 600.0
	anti_roll = 2500.0
	engine_force = 2600.0
	top_speed = 15.0
	brake_force = 3600.0
	max_steer = 0.55
	com_y = 0.2
	seat = Vector3(0, 0.85, 0.1)
	head = Vector3(0, 1.55, 0.15)
	exit_offset = Vector3(-1.3, 0, 0.1)
	chase = Vector3(0, 2.6, 5.5)
	cargo_slots = [Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(0, 0.98, 0.85))]


func _build() -> void:
	var red := Parts.paint("atv", Color(0.55, 0.12, 0.08))
	var dark := Parts.mat("atv_dark", Color(0.1, 0.1, 0.11), 0.6, 0.3)
	var steel := Parts.steel()
	Parts.box(self, Vector3(0.7, 0.3, 1.5), Vector3(0, 0.55, 0), dark)                     # frame and engine
	Parts.box(self, Vector3(1.05, 0.08, 0.55), Vector3(0, 0.78, -0.62), red, Vector3(0.12, 0, 0))   # front fenders
	Parts.box(self, Vector3(1.05, 0.08, 0.6), Vector3(0, 0.78, 0.6), red, Vector3(-0.08, 0, 0))     # rear fenders
	Parts.box(self, Vector3(0.6, 0.22, 0.45), Vector3(0, 0.82, -0.35), red)                 # tank
	Parts.box(self, Vector3(0.42, 0.12, 0.62), Vector3(0, 0.88, 0.12), Parts.mat("seat", Color(0.05, 0.05, 0.05), 0.7))
	Parts.cyl(self, 0.02, 0.75, Vector3(0, 1.08, -0.55), steel, Vector3(0, 0, PI / 2.0))     # handlebar
	Parts.cyl(self, 0.025, 0.35, Vector3(0, 0.93, -0.5), steel, Vector3(0.4, 0, 0))
	for x: float in [-0.42, 0.42]:                                                       # racks
		Parts.box(self, Vector3(0.03, 0.03, 0.55), Vector3(x, 0.9, 0.82), steel)
		Parts.box(self, Vector3(0.03, 0.03, 0.4), Vector3(x, 0.9, -0.78), steel)
	for z: float in [0.62, 0.82, 1.02]:
		Parts.box(self, Vector3(0.87, 0.03, 0.03), Vector3(0, 0.9, z), steel)
	_add_headlight(Vector3(0, 0.82, -0.88))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.42, 1.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.68, 0)
	add_child(cs)
