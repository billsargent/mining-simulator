extends Node3D
## Grandpa's place: a log cabin with a porch, wash tub, furnace and pouring table, the gold
## buyer's box, an order board, and an open shed where equipment is kept.
## Local axes: +Z faces the creek.

const Parts = preload("res://scripts/machines/parts.gd")
const CabinDoor = preload("res://scripts/base/cabin_door.gd")
const WashTub = preload("res://scripts/base/wash_tub.gd")
const Furnace = preload("res://scripts/base/furnace.gd")
const ShipBox = preload("res://scripts/base/ship_box.gd")
const OrderBoard = preload("res://scripts/base/order_board.gd")

const CABIN_W := 5.6
const CABIN_D := 4.4
const CABIN_Z := -1.6
const LOG_R := 0.14
const LOGS := 9
const SLOTS = [Vector3(-5.6, 0, -1.2), Vector3(-8.5, 0, -1.3), Vector3(-6.9, 0, -0.1)]
const PARKING = [Vector3(-6.5, 0, 4.2), Vector3(9.0, 0, 3.5)]     # ATV by the shed, pickup by the furnace

var center := Vector3.ZERO
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var furnace
var wash_tub
var ship_box
var order_board
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
	ship_box = _station(ShipBox, Vector3(-1.9, 0, 3.3))
	crusher = _station(preload("res://scripts/base/crusher.gd"), Vector3(-4.6, 0, 1.6))
	order_board = _station(OrderBoard, Vector3(2.0, 1.3, CABIN_Z + CABIN_D * 0.5 + LOG_R + 0.04))
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
	for i in LOGS:
		var y := LOG_R + i * step
		Parts.cyl(self, LOG_R, CABIN_W + 0.4, Vector3(0, y, front), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
		Parts.cyl(self, LOG_R, CABIN_W + 0.4, Vector3(0, y, back), logs, Vector3(0, 0, PI / 2.0), -1.0, 10)
		for s: float in [-1.0, 1.0]:
			Parts.cyl(self, LOG_R, CABIN_D + 0.4, Vector3(s * CABIN_W * 0.5, y + step * 0.5, CABIN_Z), logs, Vector3(PI / 2.0, 0, 0), -1.0, 10)
	var wall_h := LOG_R + LOGS * step
	# Door and window on the front wall.
	var dark := Parts.wood("door", Color(0.27, 0.19, 0.12))
	var door := CabinDoor.new()
	door.position = Vector3(0.9, 0.0, front + LOG_R + 0.02)
	add_child(door)
	Parts.box(door, Vector3(0.95, 2.0, 0.06), Vector3(0, 1.0, 0), dark)
	Parts.box(door, Vector3(0.06, 0.06, 0.04), Vector3(-0.38, 1.0, 0.05), Parts.steel())
	Parts.collider(door, Vector3(0.95, 2.0, 0.2), Vector3(0, 1.0, 0.05))
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
	var body := StaticBody3D.new()
	add_child(body)
	Parts.collider(body, Vector3(CABIN_W + 0.4, wall_h, CABIN_D + 0.4), Vector3(0, wall_h * 0.5, CABIN_Z))


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
