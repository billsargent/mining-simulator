extends "res://scripts/vehicles/vehicle.gd"
## Pickup truck: fast on roads, heavier off-road, with room for three pieces of equipment.


func _init() -> void:
	kind = "truck"
	display_name = "Pickup"
	mass = 1800.0
	wheel_mounts = [Vector3(-0.82, 0.45, -1.45), Vector3(0.82, 0.45, -1.45), Vector3(-0.82, 0.45, 1.4), Vector3(0.82, 0.45, 1.4)]
	wheel_radius = 0.42
	wheel_width = 0.3
	rest = 0.3
	spring = 29000.0
	damper = 3300.0
	anti_roll = 14000.0
	engine_force = 9500.0
	top_speed = 24.0
	brake_force = 16000.0
	max_steer = 0.5
	com_y = 0.45
	seat = Vector3(-0.4, 1.2, -0.45)
	head = Vector3(-0.4, 1.86, -0.3)
	exit_offset = Vector3(-1.7, 0, -0.45)
	chase = Vector3(0, 3.6, 8.5)
	var rot := Basis(Vector3.UP, -PI / 2.0)
	cargo_slots = [Transform3D(rot, Vector3(0, 1.12, 0.55)), Transform3D(rot, Vector3(-0.42, 1.12, 1.75)), Transform3D(rot, Vector3(0.42, 1.12, 1.75))]


func _build() -> void:
	var paint := Parts.paint("truck", Color(0.2, 0.3, 0.26))
	var dark := Parts.mat("truck_dark", Color(0.09, 0.09, 0.1), 0.6, 0.3)
	var chrome := Parts.chrome()
	var glass := Parts.glass()
	var steel := Parts.steel()
	rim_color = Color(0.72, 0.72, 0.74)
	Parts.box(self, Vector3(1.4, 0.3, 4.6), Vector3(0, 0.72, 0.0), dark)                      # chassis
	for x: float in [-0.55, 0.55]:
		Parts.box(self, Vector3(0.12, 0.18, 4.8), Vector3(x, 0.62, 0.0), steel)                # frame rails
	# Hood and front clip: a sloped profile, fender flares over the wheels.
	Parts.extrude(self, PackedVector2Array([Vector2(-2.4, 0.92), Vector2(-2.42, 1.36), Vector2(-2.3, 1.47),
			Vector2(-1.6, 1.52), Vector2(-1.08, 1.55), Vector2(-1.08, 0.92)]), 1.84, 0, paint)
	for z: float in [-1.45, 1.4]:
		for x: float in [-0.94, 0.94]:
			Parts.extrude(self, Parts.arch(z, 0.45, 0.5, 0.57, 0.25, PI - 0.25), 0.1, x, dark)
	# Cab: door panels below the window line, pillars and roof above, so you can see out.
	for x: float in [-0.9, 0.9]:
		Parts.bevel_box(self, Vector3(0.06, 0.55, 1.5), Vector3(x, 1.2, -0.45), paint, 0.05)  # doors
		Parts.box(self, Vector3(0.01, 0.5, 0.01), Vector3(x * 1.02, 1.2, -0.3), dark)          # door seam
		Parts.box(self, Vector3(0.03, 0.03, 0.14), Vector3(x * 1.04, 1.38, -0.15), chrome)     # handle
		Parts.box(self, Vector3(0.06, 0.68, 0.08), Vector3(x, 1.81, -1.15), paint, Vector3(-0.35, 0, 0))   # A pillars
		Parts.box(self, Vector3(0.06, 0.7, 0.1), Vector3(x, 1.8, 0.27), paint)                # rear pillars
		Parts.box(self, Vector3(0.02, 0.6, 1.25), Vector3(x, 1.78, -0.45), glass)             # side windows
		Parts.bevel_box(self, Vector3(0.22, 0.06, 2.2), Vector3(x * 1.02, 0.78, -0.45), dark, 0.02)   # running boards
		# Mirrors on arms by the A pillars.
		Parts.cyl(self, 0.015, 0.16, Vector3(x * 1.0, 1.55, -1.02), chrome, Vector3(0, 0, PI / 2.0), -1.0, 6)
		Parts.bevel_box(self, Vector3(0.05, 0.2, 0.14), Vector3(x * 1.1, 1.6, -1.02), dark, 0.03)
		Parts.box(self, Vector3(0.01, 0.17, 0.11), Vector3(x * 1.1, 1.6, -0.95), chrome)
	Parts.bevel_box(self, Vector3(1.85, 0.07, 1.5), Vector3(0, 2.16, -0.42), paint, 0.03)    # roof
	for x: float in [-0.5, 0.0, 0.5]:                                                         # cab markers
		Parts.box(self, Vector3(0.08, 0.03, 0.04), Vector3(x, 2.2, -1.12), Parts.lens("amber", Color(0.95, 0.55, 0.1), 0.4))
	Parts.box(self, Vector3(1.8, 0.55, 0.06), Vector3(0, 1.2, 0.3), paint)                    # back wall
	Parts.box(self, Vector3(1.7, 0.62, 0.02), Vector3(0, 1.8, -1.15), glass, Vector3(-0.35, 0, 0))   # windshield
	Parts.box(self, Vector3(0.6, 0.015, 0.02), Vector3(-0.3, 1.52, -1.27), dark, Vector3(-0.35, 0, 0.1))   # wipers
	Parts.box(self, Vector3(0.6, 0.015, 0.02), Vector3(0.4, 1.52, -1.27), dark, Vector3(-0.35, 0, 0.1))
	Parts.box(self, Vector3(1.7, 0.6, 0.02), Vector3(0, 1.8, 0.3), glass)                     # rear window
	Parts.bevel_box(self, Vector3(1.75, 0.18, 0.4), Vector3(0, 1.45, -1.0), dark, 0.06)      # dashboard
	Parts.bevel_box(self, Vector3(1.6, 0.12, 0.5), Vector3(0, 1.06, -0.2), dark, 0.04)       # bench seat
	Parts.extrude(self, PackedVector2Array([Vector2(0.0, 1.1), Vector2(0.12, 1.12), Vector2(0.2, 1.6),
			Vector2(0.1, 1.62), Vector2(-0.02, 1.15)]), 1.6, 0, dark)                       # seat back
	var wheel := TorusMesh.new()                                                              # steering wheel
	wheel.inner_radius = 0.15
	wheel.outer_radius = 0.18
	var sw := MeshInstance3D.new()
	sw.mesh = wheel
	sw.material_override = dark
	sw.position = Vector3(-0.4, 1.52, -0.78)
	sw.rotation = Vector3(1.2, 0, 0)
	add_child(sw)
	# Bed: floor with ribs, sides cut round the rear wheels, rail caps, tailgate.
	Parts.box(self, Vector3(1.85, 0.06, 2.2), Vector3(0, 0.98, 1.4), dark)                    # bed floor
	for x: float in [-0.6, -0.2, 0.2, 0.6]:
		Parts.box(self, Vector3(0.05, 0.02, 2.15), Vector3(x, 1.02, 1.4), dark)
	var side := PackedVector2Array([Vector2(0.3, 0.85)])
	var a_hi := asin(0.4 / 0.57)
	for k in 9:
		var a := lerpf(PI - a_hi, a_hi, k / 8.0)
		side.append(Vector2(1.4 + cos(a) * 0.57, 0.45 + sin(a) * 0.57))
	side.append_array(PackedVector2Array([Vector2(2.5, 0.85), Vector2(2.5, 1.45), Vector2(0.3, 1.45)]))
	for x: float in [-0.9, 0.9]:
		Parts.extrude(self, side, 0.06, x, paint)                                             # bed sides
		Parts.bevel_box(self, Vector3(0.12, 0.04, 2.2), Vector3(x, 1.47, 1.4), dark, 0.015)   # rail caps
		Parts.box(self, Vector3(0.08, 0.16, 0.03), Vector3(x * 0.82, 1.25, 2.53), Parts.lens("red", Color(0.8, 0.05, 0.03)))
	Parts.bevel_box(self, Vector3(1.85, 0.5, 0.06), Vector3(0, 1.2, 2.48), paint, 0.03)       # tailgate
	Parts.box(self, Vector3(0.25, 0.05, 0.02), Vector3(0, 1.36, 2.52), dark)
	# Bumpers, grille, lamp bezels.
	Parts.bevel_box(self, Vector3(1.95, 0.18, 0.14), Vector3(0, 0.85, -2.42), chrome, 0.05)
	Parts.bevel_box(self, Vector3(1.95, 0.15, 0.14), Vector3(0, 0.85, 2.52), chrome, 0.05)
	Parts.box(self, Vector3(0.3, 0.05, 0.04), Vector3(0, 0.98, 2.55), dark)                  # step
	Parts.bevel_box(self, Vector3(1.0, 0.36, 0.05), Vector3(0, 1.2, -2.43), chrome, 0.05)    # grille surround
	Parts.box(self, Vector3(0.9, 0.28, 0.04), Vector3(0, 1.2, -2.44), dark)
	for y: float in [1.1, 1.2, 1.3]:
		Parts.box(self, Vector3(0.9, 0.025, 0.03), Vector3(0, y, -2.46), chrome)
	Parts.box(self, Vector3(0.025, 0.28, 0.03), Vector3(0, 1.2, -2.46), chrome)
	for x: float in [-0.68, 0.68]:
		Parts.cyl(self, 0.1, 0.03, Vector3(x, 1.18, -2.43), chrome, Vector3(PI / 2.0, 0, 0), 0.085, 14)
		Parts.box(self, Vector3(0.1, 0.05, 0.02), Vector3(x * 1.25, 1.18, -2.42), Parts.lens("amber", Color(0.95, 0.55, 0.1), 0.4))
	_add_headlight(Vector3(-0.68, 1.18, -2.44))
	_add_headlight(Vector3(0.68, 1.18, -2.44))
	var body := BoxShape3D.new()
	body.size = Vector3(1.85, 0.75, 4.9)
	var cs := CollisionShape3D.new()
	cs.shape = body
	cs.position = Vector3(0, 1.15, 0)
	add_child(cs)
	var cab := BoxShape3D.new()
	cab.size = Vector3(1.8, 0.7, 1.5)
	var cs2 := CollisionShape3D.new()
	cs2.shape = cab
	cs2.position = Vector3(0, 1.75, -0.45)
	add_child(cs2)
