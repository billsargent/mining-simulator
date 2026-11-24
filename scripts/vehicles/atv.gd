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
	var chrome := Parts.chrome()
	rim_color = Color(0.2, 0.2, 0.21)
	# Frame rails, engine with cooling fins, skid plate.
	for x: float in [-0.22, 0.22]:
		Parts.cyl(self, 0.03, 1.5, Vector3(x, 0.45, 0), steel, Vector3(PI / 2.0, 0, 0), -1.0, 8)
	Parts.bevel_box(self, Vector3(0.4, 0.32, 0.5), Vector3(0, 0.55, 0.05), dark, 0.06)
	for k in 5:
		Parts.box(self, Vector3(0.46, 0.015, 0.4), Vector3(0, 0.62 + k * 0.035, -0.02), steel)
	Parts.bevel_box(self, Vector3(0.55, 0.04, 1.2), Vector3(0, 0.3, 0), steel, 0.02)
	# Plastics: a shaped nose and arched fenders over each wheel.
	var nose := PackedVector2Array([Vector2(-0.86, 0.6), Vector2(-0.84, 0.8), Vector2(-0.55, 0.88), Vector2(-0.3, 0.85),
			Vector2(-0.3, 0.6), Vector2(-0.7, 0.52)])
	Parts.extrude(self, nose, 0.62, 0, red)
	Parts.extrude(self, PackedVector2Array([Vector2(0.3, 0.82), Vector2(0.55, 0.88), Vector2(1.05, 0.86), Vector2(1.12, 0.7),
			Vector2(0.95, 0.6), Vector2(0.3, 0.6)]), 0.5, 0, red)
	for z: float in [-0.62, 0.62]:
		for x: float in [-0.5, 0.5]:
			Parts.extrude(self, Parts.arch(z, 0.32, 0.36, 0.42, 0.0, PI), 0.34, x, red)
	for x: float in [-0.32, 0.32]:                                                          # footwells
		Parts.bevel_box(self, Vector3(0.2, 0.04, 0.6), Vector3(x, 0.46, 0.02), dark, 0.015)
	# Tank, seat, handlebars with grips and hand guards.
	Parts.bevel_box(self, Vector3(0.42, 0.2, 0.42), Vector3(0, 0.86, -0.32), red, 0.07)
	Parts.cyl(self, 0.05, 0.04, Vector3(0, 0.97, -0.3), chrome, Vector3.ZERO, -1.0, 10)
	var seat_mat := Parts.mat("seat", Color(0.05, 0.05, 0.05), 0.7)
	Parts.extrude(self, PackedVector2Array([Vector2(-0.14, 0.82), Vector2(-0.12, 0.93), Vector2(0.0, 0.96), Vector2(0.38, 0.95),
			Vector2(0.45, 0.88), Vector2(0.45, 0.82)]), 0.4, 0, seat_mat)
	Parts.cyl(self, 0.025, 0.35, Vector3(0, 0.93, -0.5), steel, Vector3(0.4, 0, 0))
	Parts.cyl(self, 0.02, 0.75, Vector3(0, 1.08, -0.55), steel, Vector3(0, 0, PI / 2.0))     # handlebar
	for x: float in [-1.0, 1.0]:
		Parts.cyl(self, 0.03, 0.13, Vector3(x * 0.32, 1.08, -0.55), Parts.rubber(), Vector3(0, 0, PI / 2.0), -1.0, 8)
		Parts.bevel_box(self, Vector3(0.04, 0.08, 0.14), Vector3(x * 0.33, 1.1, -0.64), dark, 0.03)
		Parts.box(self, Vector3(0.1, 0.01, 0.02), Vector3(x * 0.22, 1.1, -0.6), steel)     # levers
	Parts.bevel_box(self, Vector3(0.16, 0.06, 0.1), Vector3(0, 1.12, -0.57), dark, 0.02)   # gauge pod
	# Lamps: headlight pod in the nose (the light itself is the base class's), tail light.
	Parts.bevel_box(self, Vector3(0.3, 0.12, 0.06), Vector3(0, 0.82, -0.86), dark, 0.03)
	Parts.box(self, Vector3(0.14, 0.05, 0.02), Vector3(0, 0.74, 1.13), Parts.lens("red", Color(0.8, 0.05, 0.03)))
	# Exhaust along the right side.
	Parts.cyl(self, 0.03, 0.5, Vector3(0.24, 0.62, 0.55), steel, Vector3(PI / 2.0, 0, 0), -1.0, 8)
	Parts.cyl(self, 0.06, 0.28, Vector3(0.24, 0.66, 0.9), chrome, Vector3(PI / 2.0, 0, 0), -1.0, 10)
	# Tube racks front and back.
	for x: float in [-0.42, 0.42]:
		Parts.cyl(self, 0.016, 0.55, Vector3(x, 0.9, 0.82), steel, Vector3(PI / 2.0, 0, 0), -1.0, 6)
		Parts.cyl(self, 0.016, 0.4, Vector3(x, 0.9, -0.78), steel, Vector3(PI / 2.0, 0, 0), -1.0, 6)
		Parts.cyl(self, 0.014, 0.12, Vector3(x, 0.84, 0.6), steel, Vector3.ZERO, -1.0, 6)
	for z: float in [0.56, 0.72, 0.88, 1.08, -0.6, -0.78, -0.96]:
		Parts.cyl(self, 0.014, 0.87, Vector3(0, 0.9, z), steel, Vector3(0, 0, PI / 2.0), -1.0, 6)
	Parts.bevel_box(self, Vector3(0.8, 0.05, 0.08), Vector3(0, 0.42, -1.05), steel, 0.02)  # bumper
	_add_headlight(Vector3(0, 0.82, -0.88))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.42, 1.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.68, 0)
	add_child(cs)
