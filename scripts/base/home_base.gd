extends Node3D
## Grandpa's place: a log cabin with a porch, wash tub, furnace and pouring table, Grandpa's
## journal, an ore crusher, and an open shed where equipment is kept.
## Local axes: +Z faces the creek.

const Parts = preload("res://scripts/machines/parts.gd")
const CabinDoor = preload("res://scripts/base/cabin_door.gd")
const WashTub = preload("res://scripts/base/wash_tub.gd")
const Furnace = preload("res://scripts/base/furnace.gd")
const Find = preload("res://scripts/mine/find.gd")
const Bed = preload("res://scripts/base/bed.gd")
const StorageChest = preload("res://scripts/base/storage_chest.gd")

const CABIN_W := 5.6
const CABIN_D := 4.4
const CABIN_Z := -1.6
const DOOR_X := 0.9
const LOG_R := 0.14
const LOGS := 9
const SLOTS = [Vector3(-5.6, 0, -1.2), Vector3(-8.5, 0, -1.3), Vector3(-6.9, 0, -0.1)]
const PARKING = [Vector3(-6.5, 0, 4.2), Vector3(9.0, 0, 3.5)]     # ATV by the shed, pickup by the furnace

var center := Vector3.ZERO
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var furnace
var wash_tub
var journal
var door
var chest
var bed
var crusher


## The site is already levelled by the world generator.
func build(terrain, site: Vector3, facing: Vector3) -> void:
	var h: float = terrain.height_at(site.x, site.z)
	center = Vector3(site.x, h, site.z)
	position = center
	var f := facing.normalized()
	rotation.y = atan2(f.x, f.z)
	_cabin()
	_porch()
	_shed()
	wash_tub = _station(WashTub, Vector3(-3.6, 0, 2.4))
	furnace = _station(Furnace, Vector3(4.4, 0, 0.4))
	journal = Find.new()
	journal.position = Vector3(-1.9, 0, 3.3)
	add_child(journal)
	journal.build("grandpa")
	crusher = _station(preload("res://scripts/base/crusher.gd"), Vector3(-4.6, 0, 1.6))
	spawn_point = to_global(Vector3(0.0, 0.1, 4.8))
	spawn_yaw = atan2(-f.x, -f.z)


func slot_position(i: int) -> Vector3:
	return to_global(SLOTS[i])


func slot_yaw() -> float:
	return rotation.y


## Where vehicle i parks, and which way it faces (nose toward the creek road).
func parking(i: int) -> Transform3D:
	var p := to_global(PARKING[i])
	return Transform3D(Basis(Vector3.UP, rotation.y + PI * 0.5), p)


func _station(script: GDScript, pos: Vector3) -> Node:
	var s = script.new()
	s.position = pos
	add_child(s)
	s.build()
	return s


func _cabin() -> void:
	var logs := Parts.wood("logs", Color(0.43, 0.31, 0.2))
	var front := CABIN_Z + CABIN_D * 0.5
	var back := CABIN_Z - CABIN_D * 0.5
	var step := LOG_R * 1.85
	var gap0 := DOOR_X - CabinDoor.WIDTH * 0.5 - 0.1
	var gap1 := DOOR_X + CabinDoor.WIDTH * 0.5 + 0.1
	var x0 := -CABIN_W * 0.5 - 0.2
	var x1 := CABIN_W * 0.5 + 0.2
	for i in LOGS:
		var y := LOG_R + i * step
		if y - LOG_R < 2.2:
			# The front wall is cut around the doorway.
			Parts.cyl(self, LOG_R, gap0 - x0, Vector3((x0 + gap0) * 0.5, y, front), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
			Parts.cyl(self, LOG_R, x1 - gap1, Vector3((x1 + gap1) * 0.5, y, front), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
		else:
			Parts.cyl(self, LOG_R, CABIN_W + 0.4, Vector3(0, y, front), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
		Parts.cyl(self, LOG_R, CABIN_W + 0.4, Vector3(0, y, back), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
		for s: float in [-1.0, 1.0]:
			Parts.cyl(self, LOG_R, CABIN_D + 0.4, Vector3(s * CABIN_W * 0.5, y + step * 0.5, CABIN_Z), logs, Vector3(PI / 2.0, 0, 0), -1.0, 10)
	var wall_h := LOG_R + LOGS * step
	# Door and window on the front wall.
	var dark := Parts.wood("door", Color(0.27, 0.19, 0.12))
	door = CabinDoor.new()
	door.position = Vector3(DOOR_X + CabinDoor.WIDTH * 0.5, 0.1, front)
	add_child(door)
	door.build()
	for x: float in [DOOR_X - CabinDoor.WIDTH * 0.5 - 0.05, DOOR_X + CabinDoor.WIDTH * 0.5 + 0.05]:
		Parts.box(self, Vector3(0.1, 2.15, LOG_R * 2.0 + 0.06), Vector3(x, 1.07, front), dark)
	Parts.box(self, Vector3(CabinDoor.WIDTH + 0.2, 0.1, LOG_R * 2.0 + 0.06), Vector3(DOOR_X, 2.15, front), dark)
	var glass := Parts.mat("glass", Color(0.07, 0.09, 0.11), 0.08, 0.3)
	Parts.box(self, Vector3(0.9, 0.7, 0.04), Vector3(-1.4, 1.45, front + LOG_R + 0.01), glass)
	for frame in [[Vector3(1.0, 0.07, 0.06), Vector3(-1.4, 1.83, 0)], [Vector3(1.0, 0.07, 0.06), Vector3(-1.4, 1.07, 0)],
			[Vector3(0.07, 0.8, 0.06), Vector3(-1.93, 1.45, 0)], [Vector3(0.07, 0.8, 0.06), Vector3(-0.87, 1.45, 0)],
			[Vector3(0.04, 0.7, 0.05), Vector3(-1.4, 1.45, 0)]]:
		Parts.box(self, frame[0], (frame[1] as Vector3) + Vector3(0, 0, front + LOG_R + 0.03), dark)
	# Roof: two pitched panels with gables, and a stone chimney.
	var pitch := deg_to_rad(28.0)
	var half := CABIN_D * 0.5 + 0.5
	var ridge := wall_h + CABIN_D * 0.5 * tan(pitch)
	var panel_len := half / cos(pitch) + 0.05
	var roof := Parts.mat("roof", Color(0.24, 0.22, 0.2), 0.75, 0.2)
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(CABIN_W + 1.0, 0.08, panel_len), Vector3(0, ridge - half * 0.5 * tan(pitch) + 0.06, CABIN_Z + s * half * 0.5), roof, Vector3(s * pitch, 0, 0))
	var gable_mesh := _gable(CABIN_D + 0.2, ridge - wall_h)
	for s: float in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		g.mesh = gable_mesh
		g.material_override = logs
		g.position = Vector3(s * CABIN_W * 0.5, wall_h, CABIN_Z)
		add_child(g)
	Parts.box(self, Vector3(0.6, 1.6, 0.6), Vector3(1.8, ridge - 0.2, CABIN_Z - 0.8), Parts.mat("stone", Color(0.42, 0.4, 0.38), 0.95))
	# Walls you can walk between, and a way in through the door.
	var body := StaticBody3D.new()
	add_child(body)
	var t := LOG_R * 2.0
	Parts.collider(body, Vector3(CABIN_W + 0.4, wall_h, t), Vector3(0, wall_h * 0.5, back))
	for s: float in [-1.0, 1.0]:
		Parts.collider(body, Vector3(t, wall_h, CABIN_D + 0.4), Vector3(s * CABIN_W * 0.5, wall_h * 0.5, CABIN_Z))
	Parts.collider(body, Vector3(gap0 - x0, wall_h, t), Vector3((x0 + gap0) * 0.5, wall_h * 0.5, front))
	Parts.collider(body, Vector3(x1 - gap1, wall_h, t), Vector3((x1 + gap1) * 0.5, wall_h * 0.5, front))
	Parts.collider(body, Vector3(gap1 - gap0, wall_h - 2.2, t), Vector3(DOOR_X, 2.2 + (wall_h - 2.2) * 0.5, front))
	_interior(front, back, wall_h)


## Inside: a plank floor, Grandpa's bunk, a wood stove, a table with a lantern, shelves, and the chest.
func _interior(front: float, back: float, wall_h: float) -> void:
	var planks := Parts.wood("floor_planks", Color(0.46, 0.34, 0.23))
	var in_w := CABIN_W - LOG_R * 2.0
	var in_d := CABIN_D - LOG_R * 2.0
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	Parts.box(floor_body, Vector3(in_w, 0.1, in_d), Vector3(0, 0.05, CABIN_Z), planks)
	Parts.collider(floor_body, Vector3(in_w, 0.1, in_d), Vector3(0, 0.05, CABIN_Z))
	Parts.box(self, Vector3(2.0, 0.015, 1.3), Vector3(0.1, 0.105, CABIN_Z + 0.2), Parts.mat("rug", Color(0.5, 0.2, 0.14), 1.0))
	# Ceiling boards under the roof, so the room feels closed.
	Parts.box(self, Vector3(in_w, 0.04, in_d), Vector3(0, wall_h - 0.02, CABIN_Z), Parts.wood("ceiling", Color(0.4, 0.3, 0.2)))
	var inner_back := back + LOG_R + 0.02
	var inner_left := -CABIN_W * 0.5 + LOG_R + 0.02
	var inner_right := CABIN_W * 0.5 - LOG_R - 0.02
	bed = Bed.new()
	bed.position = Vector3(inner_left + 0.5, 0.1, inner_back + 1.0)
	add_child(bed)
	bed.build()
	# Wood stove under the chimney, with its pipe.
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	var stove := StaticBody3D.new()
	stove.position = Vector3(1.8, 0.1, inner_back + 0.45)
	add_child(stove)
	Parts.box(stove, Vector3(0.7, 0.6, 0.55), Vector3(0, 0.42, 0), iron)
	for p: Vector3 in [Vector3(-0.3, 0.06, -0.22), Vector3(0.3, 0.06, -0.22), Vector3(-0.3, 0.06, 0.22), Vector3(0.3, 0.06, 0.22)]:
		Parts.box(stove, Vector3(0.05, 0.12, 0.05), p, iron)
	Parts.cyl(stove, 0.07, wall_h - 0.75, Vector3(0, 0.72 + (wall_h - 0.75) * 0.5, -0.05), iron, Vector3.ZERO, -1.0, 10)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.9, 0.35, 0.1)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.4, 0.1)
	ember.emission_energy_multiplier = 2.0
	Parts.box(stove, Vector3(0.3, 0.12, 0.01), Vector3(0, 0.36, 0.28), ember)
	var fire := OmniLight3D.new()
	fire.position = Vector3(0, 0.4, 0.5)
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 0.6
	fire.omni_range = 2.5
	stove.add_child(fire)
	Parts.collider(stove, Vector3(0.7, 0.72, 0.6), Vector3(0, 0.36, 0))
	# Table and two chairs, with a lantern that lights the room.
	var furniture := Parts.wood("furniture", Color(0.5, 0.36, 0.22))
	var table := StaticBody3D.new()
	table.position = Vector3(-0.1, 0.1, inner_back + 0.75)
	add_child(table)
	Parts.box(table, Vector3(1.2, 0.05, 0.75), Vector3(0, 0.74, 0), furniture)
	for p: Vector3 in [Vector3(-0.53, 0.36, -0.3), Vector3(0.53, 0.36, -0.3), Vector3(-0.53, 0.36, 0.3), Vector3(0.53, 0.36, 0.3)]:
		Parts.box(table, Vector3(0.06, 0.72, 0.06), p, furniture)
	Parts.collider(table, Vector3(1.2, 0.77, 0.75), Vector3(0, 0.385, 0))
	for cx: float in [-0.35, 0.4]:
		var chair := Node3D.new()
		chair.position = Vector3(cx, 0, 0.62)
		chair.rotation.y = 0.15 * cx
		table.add_child(chair)
		Parts.box(chair, Vector3(0.42, 0.04, 0.42), Vector3(0, 0.45, 0), furniture)
		Parts.box(chair, Vector3(0.42, 0.5, 0.04), Vector3(0, 0.72, 0.2), furniture)
		for p: Vector3 in [Vector3(-0.18, 0.22, -0.18), Vector3(0.18, 0.22, -0.18), Vector3(-0.18, 0.22, 0.18), Vector3(0.18, 0.22, 0.18)]:
			Parts.box(chair, Vector3(0.04, 0.45, 0.04), p, furniture)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.85, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.8, 0.45)
	glass.emission_energy_multiplier = 1.5
	Parts.cyl(table, 0.06, 0.04, Vector3(0.3, 0.79, 0.05), iron, Vector3.ZERO, -1.0, 10)
	Parts.cyl(table, 0.045, 0.14, Vector3(0.3, 0.88, 0.05), glass, Vector3.ZERO, -1.0, 10)
	Parts.cyl(table, 0.05, 0.03, Vector3(0.3, 0.965, 0.05), iron, Vector3.ZERO, -1.0, 10)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.3, 1.1, 0.05)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 5.5
	lamp.shadow_enabled = true
	table.add_child(lamp)
	# Shelves on the right wall, with jars and a few tins.
	var shelf := Node3D.new()
	shelf.position = Vector3(inner_right - 0.15, 0.1, CABIN_Z - 0.2)
	add_child(shelf)
	var jar := Parts.mat("jar", Color(0.75, 0.8, 0.75), 0.15, 0.1)
	var tin := Parts.galvanized()
	for k in 2:
		var y := 1.1 + k * 0.45
		Parts.box(shelf, Vector3(0.3, 0.03, 1.4), Vector3(0, y, 0), furniture)
		for j in 5:
			var mat_j: Material = jar if (j + k) % 2 == 0 else tin
			Parts.cyl(shelf, 0.06, 0.16 + 0.03 * (j % 2), Vector3(0, y + 0.1, -0.5 + j * 0.25), mat_j, Vector3.ZERO, -1.0, 10)
	# The storage chest, under the window.
	chest = StorageChest.new()
	chest.position = Vector3(-1.4, 0.1, front - LOG_R - 0.32)
	chest.rotation.y = PI
	add_child(chest)
	chest.build()


## Triangle filling the end of the roof, in the YZ plane.
func _gable(depth: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0, 0, -depth * 0.5)
	var b := Vector3(0, 0, depth * 0.5)
	var c := Vector3(0, height, 0)
	for v in [a, b, c]:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _porch() -> void:
	var front := CABIN_Z + CABIN_D * 0.5
	var planks := Parts.wood("planks", Color(0.5, 0.38, 0.26))
	Parts.box(self, Vector3(CABIN_W + 0.6, 0.1, 1.9), Vector3(0, 0.05, front + 0.95 + LOG_R), planks)
	for s: float in [-1.0, 1.0]:
		Parts.cyl(self, 0.07, 2.3, Vector3(s * (CABIN_W * 0.5), 1.15, front + 1.8), planks)
	Parts.box(self, Vector3(CABIN_W + 0.8, 0.06, 2.1), Vector3(0, 2.35, front + 1.0), Parts.mat("roof", Color(0.24, 0.22, 0.2), 0.75, 0.2), Vector3(0.12, 0, 0))


func _shed() -> void:
	var planks := Parts.wood("planks", Color(0.5, 0.38, 0.26))
	var roof := Parts.mat("roof", Color(0.24, 0.22, 0.2), 0.75, 0.2)
	for x: float in [-9.8, -4.6]:
		Parts.box(self, Vector3(0.12, 2.5, 0.12), Vector3(x, 1.25, 0.3), planks)
		Parts.box(self, Vector3(0.12, 2.0, 0.12), Vector3(x, 1.0, -3.0), planks)
	Parts.box(self, Vector3(5.8, 0.06, 3.8), Vector3(-7.2, 2.28, -1.35), roof, Vector3(-0.15, 0, 0))
	Parts.box(self, Vector3(5.2, 1.9, 0.05), Vector3(-7.2, 0.95, -3.0), planks)
	Parts.box(self, Vector3(0.05, 1.9, 3.3), Vector3(-9.8, 0.95, -1.35), planks)
	Parts.label(self, "SHED", Vector3(-7.2, 2.05, 0.36), 36)
	var body := StaticBody3D.new()
	add_child(body)
	Parts.collider(body, Vector3(5.2, 1.9, 0.1), Vector3(-7.2, 0.95, -3.0))
	Parts.collider(body, Vector3(0.1, 1.9, 3.3), Vector3(-9.8, 0.95, -1.35))
