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
	var chrome := Parts.mat("chrome", Color(0.7, 0.7, 0.72), 0.25, 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.65, 0.7, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	Parts.box(self, Vector3(1.75, 0.35, 4.7), Vector3(0, 0.75, 0.0), dark)                   # chassis
	Parts.box(self, Vector3(1.85, 0.62, 1.35), Vector3(0, 1.22, -1.75), paint)               # hood
	# Cab: door panels below the window line, pillars and roof above, so you can see out.
	for x: float in [-0.9, 0.9]:
		Parts.box(self, Vector3(0.06, 0.55, 1.5), Vector3(x, 1.2, -0.45), paint)              # doors
		Parts.box(self, Vector3(0.06, 0.68, 0.08), Vector3(x, 1.81, -1.15), paint, Vector3(-0.35, 0, 0))   # A pillars
		Parts.box(self, Vector3(0.06, 0.7, 0.1), Vector3(x, 1.8, 0.27), paint)                # rear pillars
		Parts.box(self, Vector3(0.02, 0.6, 1.25), Vector3(x, 1.78, -0.45), glass)             # side windows
	Parts.box(self, Vector3(1.85, 0.07, 1.5), Vector3(0, 2.16, -0.42), paint)                 # roof
	Parts.box(self, Vector3(1.8, 0.55, 0.06), Vector3(0, 1.2, 0.3), paint)                    # back wall
	Parts.box(self, Vector3(1.7, 0.62, 0.02), Vector3(0, 1.8, -1.15), glass, Vector3(-0.35, 0, 0))   # windshield
	Parts.box(self, Vector3(1.7, 0.6, 0.02), Vector3(0, 1.8, 0.3), glass)                     # rear window
	Parts.box(self, Vector3(1.75, 0.18, 0.4), Vector3(0, 1.45, -1.0), dark)                   # dashboard
	Parts.box(self, Vector3(1.6, 0.12, 0.5), Vector3(0, 1.06, -0.2), dark)                    # bench seat
	var wheel := TorusMesh.new()                                                              # steering wheel
	wheel.inner_radius = 0.15
	wheel.outer_radius = 0.18
	var sw := MeshInstance3D.new()
	sw.mesh = wheel
	sw.material_override = dark
	sw.position = Vector3(-0.4, 1.52, -0.78)
	sw.rotation = Vector3(1.2, 0, 0)
	add_child(sw)
	Parts.box(self, Vector3(1.85, 0.06, 2.2), Vector3(0, 0.98, 1.4), dark)                    # bed floor
	for x: float in [-0.9, 0.9]:
		Parts.box(self, Vector3(0.06, 0.5, 2.2), Vector3(x, 1.2, 1.4), paint)                 # bed sides
	Parts.box(self, Vector3(1.85, 0.5, 0.06), Vector3(0, 1.2, 2.48), paint)                   # tailgate
	Parts.box(self, Vector3(1.95, 0.18, 0.12), Vector3(0, 0.85, -2.42), chrome)               # bumpers
	Parts.box(self, Vector3(1.95, 0.15, 0.12), Vector3(0, 0.85, 2.52), chrome)
	Parts.box(self, Vector3(1.2, 0.3, 0.04), Vector3(0, 1.2, -2.43), dark)                    # grille
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
