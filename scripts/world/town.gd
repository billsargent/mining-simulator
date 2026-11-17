extends Node3D
## Sable Crossing: a few false-front buildings on the valley road. The general store sells
## gear, the assay office buys gold, and the claims office sells claims. The garage and the
## fuel pump are scenery.
## Local axes: +Z faces the road and the river.

const Parts = preload("res://scripts/machines/parts.gd")
const ShipBox = preload("res://scripts/base/ship_box.gd")
const OrderBoard = preload("res://scripts/base/order_board.gd")
const ClaimsOffice = preload("res://scripts/base/claims_office.gd")

const FRONT_Z := -3.0          # where the building fronts stand

var store
var assay
var claims_office
var street := Vector3.ZERO     # a spot in the street in front of the assay office


func build(terrain, site: Dictionary) -> void:
	var pos: Vector2 = site["pos"]
	var facing: Vector2 = site["facing"]
	position = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
	rotation.y = atan2(facing.x, facing.y)
	_building(-9.5, 7.5, 6.0, 3.4, "GENERAL STORE", Color(0.5, 0.4, 0.3))
	_building(0.0, 6.5, 5.5, 3.2, "ASSAY OFFICE", Color(0.56, 0.5, 0.42))
	_building(9.0, 6.5, 5.5, 3.2, "CLAIMS OFFICE", Color(0.42, 0.42, 0.36))
	store = _station(OrderBoard, Vector3(-7.9, 1.45, FRONT_Z + 0.24))
	assay = _station(ShipBox, Vector3(1.4, 0.0, FRONT_Z + 0.65))
	claims_office = _station(ClaimsOffice, Vector3(10.6, 1.45, FRONT_Z + 0.24))
	_garage()
	# The town sign by the road.
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	for x: float in [-1.5, 1.5]:
		Parts.box(self, Vector3(0.14, 2.6, 0.14), Vector3(x, 1.3, 16.0), timber)
	Parts.box(self, Vector3(3.4, 0.7, 0.06), Vector3(0, 2.2, 16.0), Parts.wood("sign", Color(0.62, 0.52, 0.38)))
	for z: float in [16.04, 15.96]:
		var l := Parts.label(self, "SABLE CROSSING", Vector3(0, 2.2, z), 44)
		l.rotation.y = 0.0 if z > 16.0 else PI
	street = to_global(Vector3(1.4, 0.1, FRONT_Z + 3.2))


func _station(script: GDScript, pos: Vector3) -> Node:
	var s = script.new()
	s.position = pos
	add_child(s)
	s.build()
	return s


## A plank building with a tall false front, a porch roof on posts, a door and a window.
func _building(x: float, w: float, d: float, h: float, title: String, color: Color) -> void:
	var key := title.to_lower().replace(" ", "_")
	var wall := Parts.wood("wall_" + key, color)
	var trim := Parts.wood("trim_" + key, color.darkened(0.35))
	var root := Node3D.new()
	root.position = Vector3(x, 0, FRONT_Z)
	add_child(root)
	Parts.box(root, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5), wall)
	Parts.box(root, Vector3(w + 0.3, 0.12, d + 0.3), Vector3(0, h + 0.06, -d * 0.5), trim)
	Parts.box(root, Vector3(w + 0.4, h + 1.5, 0.18), Vector3(0, (h + 1.5) * 0.5, 0.05), wall)
	Parts.box(root, Vector3(w + 0.6, 0.16, 0.3), Vector3(0, h + 1.5, 0.05), trim)
	Parts.label(root, title, Vector3(0, h + 0.75, 0.16), 64)
	# Door and window.
	Parts.box(root, Vector3(1.0, 2.05, 0.06), Vector3(-w * 0.22, 1.03, 0.14), Parts.wood("door_" + key, color.darkened(0.5)))
	Parts.box(root, Vector3(1.7, 1.1, 0.06), Vector3(w * 0.2, 1.55, 0.14), Parts.mat("window", Color(0.12, 0.16, 0.2), 0.15, 0.3))
	Parts.box(root, Vector3(1.86, 0.08, 0.1), Vector3(w * 0.2, 0.96, 0.16), trim)
	# Porch: a low deck, posts and a sloping roof.
	Parts.box(root, Vector3(w, 0.06, 2.2), Vector3(0, 0.03, 1.2), trim)
	for px: float in [-w * 0.5 + 0.2, 0.0, w * 0.5 - 0.2]:
		Parts.box(root, Vector3(0.12, 2.5, 0.12), Vector3(px, 1.25, 2.2), trim)
	Parts.box(root, Vector3(w + 0.2, 0.07, 2.5), Vector3(0, 2.62, 1.15), trim, Vector3(0.14, 0, 0))
	var body := StaticBody3D.new()
	root.add_child(body)
	Parts.collider(body, Vector3(w, h, d + 0.2), Vector3(0, h * 0.5, -d * 0.5 + 0.1))
	for px: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
		Parts.collider(body, Vector3(0.14, 2.5, 0.14), Vector3(px, 1.25, 2.2))


## An open-fronted garage with a fuel pump and a few drums: scenery.
func _garage() -> void:
	var tin := Parts.galvanized()
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	var root := Node3D.new()
	root.position = Vector3(-19.0, 0, FRONT_Z - 0.5)
	add_child(root)
	Parts.box(root, Vector3(6.0, 3.0, 0.1), Vector3(0, 1.5, -5.0), tin)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(0.1, 3.0, 5.0), Vector3(s * 3.0, 1.5, -2.5), tin)
		Parts.box(root, Vector3(0.16, 3.0, 0.16), Vector3(s * 2.9, 1.5, 0.0), timber)
	Parts.box(root, Vector3(6.4, 0.08, 5.6), Vector3(0, 3.1, -2.4), tin, Vector3(0.08, 0, 0))
	Parts.box(root, Vector3(2.4, 0.5, 0.05), Vector3(0, 3.3, 0.35), Parts.wood("sign", Color(0.62, 0.52, 0.38)))
	Parts.label(root, "MECHANIC", Vector3(0, 3.3, 0.39), 44)
	Parts.box(root, Vector3(1.8, 0.9, 0.7), Vector3(-1.6, 0.45, -4.4), timber)
	var red := Parts.paint("pump_red", Color(0.6, 0.12, 0.1))
	Parts.box(root, Vector3(0.5, 1.3, 0.4), Vector3(4.4, 0.65, 1.0), red)
	Parts.cyl(root, 0.2, 0.3, Vector3(4.4, 1.45, 1.0), Parts.mat("pump_glass", Color(0.9, 0.9, 0.82), 0.3), Vector3.ZERO, -1.0, 12)
	Parts.label(root, "GAS", Vector3(4.4, 0.95, 1.21), 30)
	var drum := Parts.paint("drum_blue", Color(0.16, 0.26, 0.4))
	for p: Vector3 in [Vector3(2.2, 0.45, -4.3), Vector3(1.5, 0.45, -4.5), Vector3(1.9, 0.45, -3.7)]:
		Parts.cyl(root, 0.29, 0.9, p, drum, Vector3.ZERO, -1.0, 14)
	var body := StaticBody3D.new()
	root.add_child(body)
	Parts.collider(body, Vector3(6.0, 3.0, 0.2), Vector3(0, 1.5, -5.0))
	for s: float in [-1.0, 1.0]:
		Parts.collider(body, Vector3(0.2, 3.0, 5.0), Vector3(s * 3.0, 1.5, -2.5))
	Parts.collider(body, Vector3(0.5, 1.6, 0.4), Vector3(4.4, 0.8, 1.0))
	Parts.collider(body, Vector3(1.6, 0.9, 1.4), Vector3(1.9, 0.45, -4.1))
