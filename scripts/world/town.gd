extends Node3D
## Sable Crossing: a few false-front buildings on the valley road. The general store sells
## gear, the assay office buys gold, and the claims office sells claims. Each building is
## hollow with a door, a floor, furniture and a lamp; the station is inside. The garage and
## the fuel pump are scenery.
## Local axes: +Z faces the road and the river.

const Parts = preload("res://scripts/machines/parts.gd")
const ShipBox = preload("res://scripts/base/ship_box.gd")
const OrderBoard = preload("res://scripts/base/order_board.gd")
const ClaimsOffice = preload("res://scripts/base/claims_office.gd")
const CabinDoor = preload("res://scripts/base/cabin_door.gd")

const FRONT_Z := -3.0          # where the building fronts stand
const WALL := 0.15             # wall thickness
const DOOR_W := 1.0            # doorway width

var store
var assay
var claims_office
var doors := []
var street := Vector3.ZERO     # a spot in the street in front of the assay office


func build(terrain, site: Dictionary) -> void:
	var pos: Vector2 = site["pos"]
	var facing: Vector2 = site["facing"]
	position = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
	rotation.y = atan2(facing.x, facing.y)
	_building(-9.5, 7.5, 6.0, 3.4, "GENERAL STORE", Color(0.5, 0.4, 0.3))
	_building(0.0, 6.5, 5.5, 3.2, "ASSAY OFFICE", Color(0.56, 0.5, 0.42))
	_building(9.0, 6.5, 5.5, 3.2, "CLAIMS OFFICE", Color(0.42, 0.42, 0.36))
	# The stations are inside: the catalog and the plat board on the back walls, the assay
	# counter across the room.
	store = _station(OrderBoard, Vector3(-11.4, 1.45, FRONT_Z - 6.0 + WALL + 0.08))
	assay = _station(ShipBox, Vector3(0.6, 0.1, FRONT_Z - 2.9))
	claims_office = _station(ClaimsOffice, Vector3(9.6, 1.5, FRONT_Z - 5.5 + WALL + 0.08))
	_store_inside(-9.5, 7.5, 6.0)
	_assay_inside(0.0, 6.5, 5.5, 3.2)
	_claims_inside(9.0, 6.5, 5.5)
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
## Hollow: walls you walk between, a plank floor, a ceiling and a hanging lamp.
func _building(x: float, w: float, d: float, h: float, title: String, color: Color) -> void:
	var key := title.to_lower().replace(" ", "_")
	var wall := Parts.wood("wall_" + key, color)
	var trim := Parts.wood("trim_" + key, color.darkened(0.35))
	var root := Node3D.new()
	root.position = Vector3(x, 0, FRONT_Z)
	add_child(root)
	var body := StaticBody3D.new()
	root.add_child(body)
	# Back and side walls.
	var pieces := [[Vector3(w, h, WALL), Vector3(0, h * 0.5, -d + WALL * 0.5)]]
	for s: float in [-1.0, 1.0]:
		pieces.append([Vector3(WALL, h, d), Vector3(s * (w - WALL) * 0.5, h * 0.5, -d * 0.5)])
	# The false front, cut around the doorway.
	var fh := h + 1.5
	var fw := w + 0.4
	var dx := -w * 0.22
	var d0 := dx - DOOR_W * 0.5
	var d1 := dx + DOOR_W * 0.5
	pieces.append([Vector3(d0 + fw * 0.5, fh, 0.18), Vector3((d0 - fw * 0.5) * 0.5, fh * 0.5, 0.05)])
	pieces.append([Vector3(fw * 0.5 - d1, fh, 0.18), Vector3((d1 + fw * 0.5) * 0.5, fh * 0.5, 0.05)])
	pieces.append([Vector3(DOOR_W, fh - 2.15, 0.18), Vector3(dx, 2.15 + (fh - 2.15) * 0.5, 0.05)])
	for pc in pieces:
		Parts.box(root, pc[0], pc[1], wall)
		Parts.collider(body, pc[0], pc[1])
	Parts.box(root, Vector3(w + 0.3, 0.12, d + 0.3), Vector3(0, h + 0.06, -d * 0.5), trim)
	Parts.box(root, Vector3(w + 0.6, 0.16, 0.3), Vector3(0, h + 1.5, 0.05), trim)
	Parts.label(root, title, Vector3(0, h + 0.75, 0.16), 64)
	# Floor and ceiling.
	var in_w := w - WALL * 2.0
	var in_d := d - WALL
	var floor_pos := Vector3(0, 0.05, -WALL - in_d * 0.5 + 0.15)
	Parts.box(root, Vector3(in_w, 0.1, in_d), floor_pos, Parts.wood("floor_planks", Color(0.46, 0.34, 0.23)))
	Parts.collider(body, Vector3(in_w, 0.1, in_d), floor_pos)
	Parts.box(root, Vector3(in_w, 0.04, d - 0.1), Vector3(0, h - 0.02, -d * 0.5), Parts.wood("ceiling", Color(0.4, 0.3, 0.2)))
	# Door frame and a door that swings in. Open for business: it starts open.
	var frame := Parts.wood("frame_" + key, color.darkened(0.5))
	for fx: float in [d0 - 0.05, d1 + 0.05]:
		Parts.box(root, Vector3(0.1, 2.15, 0.24), Vector3(fx, 1.07, 0.05), frame)
	var door = CabinDoor.new()
	door.title = title.capitalize() + " door"
	door.position = Vector3(d1 - 0.02, 0.1, 0.05)
	root.add_child(door)
	door.build()
	door.set_open(true, true)
	doors.append(door)
	# Window, seen from both sides.
	var glass := Parts.mat("window", Color(0.12, 0.16, 0.2), 0.15, 0.3)
	for z: float in [0.15, -0.05]:
		Parts.box(root, Vector3(1.7, 1.1, 0.02), Vector3(w * 0.2, 1.55, z), glass)
	Parts.box(root, Vector3(1.86, 0.08, 0.1), Vector3(w * 0.2, 0.96, 0.16), trim)
	# Porch: a low deck, posts and a sloping roof.
	Parts.box(root, Vector3(w, 0.06, 2.2), Vector3(0, 0.03, 1.2), trim)
	for px: float in [-w * 0.5 + 0.2, 0.0, w * 0.5 - 0.2]:
		Parts.box(root, Vector3(0.12, 2.5, 0.12), Vector3(px, 1.25, 2.2), trim)
	Parts.box(root, Vector3(w + 0.2, 0.07, 2.5), Vector3(0, 2.62, 1.15), trim, Vector3(0.14, 0, 0))
	for px: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
		Parts.collider(body, Vector3(0.14, 2.5, 0.14), Vector3(px, 1.25, 2.2))
	# A hanging lamp, lit day and night.
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	var c := Vector3(0, h, -d * 0.5)
	Parts.cyl(root, 0.012, 0.5, c + Vector3(0, -0.27, 0), iron, Vector3.ZERO, -1.0, 6)
	Parts.cyl(root, 0.2, 0.12, c + Vector3(0, -0.56, 0), iron, Vector3.ZERO, 0.05, 12)
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1.0, 0.85, 0.5)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.8, 0.45)
	bulb.emission_energy_multiplier = 2.0
	Parts.cyl(root, 0.05, 0.1, c + Vector3(0, -0.66, 0), bulb, Vector3.ZERO, -1.0, 10)
	var lamp := OmniLight3D.new()
	lamp.position = c + Vector3(0, -0.8, 0)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.3
	lamp.omni_range = maxf(w, d) * 0.85
	root.add_child(lamp)


## A furniture piece you bump into: a box with its own collider.
func _solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := StaticBody3D.new()
	parent.add_child(b)
	Parts.box(b, size, pos, mat)
	Parts.collider(b, size, pos)


## A node on the floor of the building at `x`, for its furniture.
func _room(x: float) -> Node3D:
	var r := Node3D.new()
	r.position = Vector3(x, 0.1, FRONT_Z)
	add_child(r)
	return r


## The general store: a counter, shelves of goods behind it, pans on the wall, sacks, a barrel
## of shovels, and the catalog on the back wall.
func _store_inside(x: float, w: float, d: float) -> void:
	var r := _room(x)
	var wood := Parts.wood("furniture", Color(0.5, 0.36, 0.22))
	var back := -d + WALL
	_solid(r, Vector3(2.6, 1.0, 0.6), Vector3(1.6, 0.5, -d * 0.55), wood)
	Parts.box(r, Vector3(2.7, 0.05, 0.7), Vector3(1.6, 1.02, -d * 0.55), Parts.wood("dark_wood", Color(0.3, 0.22, 0.15)))
	var tin := Parts.galvanized()
	var jar := Parts.mat("jar", Color(0.75, 0.8, 0.75), 0.15, 0.1)
	var carton := Parts.mat("carton", Color(0.62, 0.5, 0.34), 0.9)
	for k in 3:
		var y := 0.6 + k * 0.6
		Parts.box(r, Vector3(3.0, 0.04, 0.4), Vector3(1.6, y, back + 0.2), wood)
		for j in 7:
			var px := 0.3 + j * 0.42
			match (j + k) % 3:
				0:
					Parts.cyl(r, 0.07, 0.2, Vector3(px, y + 0.12, back + 0.2), tin, Vector3.ZERO, -1.0, 10)
				1:
					Parts.cyl(r, 0.08, 0.24, Vector3(px, y + 0.14, back + 0.2), jar, Vector3.ZERO, -1.0, 10)
				_:
					Parts.box(r, Vector3(0.3, 0.25, 0.3), Vector3(px, y + 0.145, back + 0.2), carton)
	# Gold pans hung on the left wall.
	var steel := Parts.steel()
	for j in 3:
		Parts.cyl(r, 0.2, 0.05, Vector3(-w * 0.5 + WALL + 0.03, 1.5, -1.3 - j * 0.5), steel, Vector3(0, 0, -PI / 2.0), 0.13, 16)
	# Sacks of flour and a barrel of shovel handles.
	var sack := Parts.mat("sack", Color(0.6, 0.53, 0.38), 1.0)
	for p: Vector3 in [Vector3(-2.9, 0.28, -3.0), Vector3(-2.3, 0.28, -3.2), Vector3(-2.6, 0.83, -3.1)]:
		_solid(r, Vector3(0.5, 0.55, 0.4), p, sack)
	Parts.cyl(r, 0.3, 0.8, Vector3(-0.4, 0.4, back + 0.5), Parts.wood("barrel", Color(0.45, 0.32, 0.2)), Vector3.ZERO, -1.0, 14)
	for a: float in [-0.2, 0.0, 0.25]:
		Parts.box(r, Vector3(0.04, 1.2, 0.04), Vector3(-0.4 + a * 0.4, 1.0, back + 0.5), wood, Vector3(a, 0, a * 0.5))


## The assay office: the buying counter across the room, a safe, the assay furnace and a desk.
func _assay_inside(x: float, w: float, d: float, h: float) -> void:
	var r := _room(x)
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	var back := -d + WALL
	var sx := w * 0.5 - WALL - 0.55
	_solid(r, Vector3(0.9, 1.2, 0.7), Vector3(sx, 0.6, back + 0.45), Parts.paint("safe", Color(0.18, 0.24, 0.2)))
	Parts.cyl(r, 0.08, 0.03, Vector3(sx, 0.8, back + 0.81), Parts.mat("brass", Color(0.75, 0.6, 0.3), 0.3, 0.9), Vector3(PI / 2.0, 0, 0), -1.0, 14)
	var fx := -w * 0.5 + WALL + 0.5
	_solid(r, Vector3(0.8, 1.0, 0.7), Vector3(fx, 0.5, back + 0.45), Parts.mat("firebrick", Color(0.55, 0.3, 0.22), 0.95))
	Parts.cyl(r, 0.1, h - 1.1, Vector3(fx, 1.0 + (h - 1.1) * 0.5, back + 0.3), iron, Vector3.ZERO, -1.0, 10)
	# Desk with a ledger under the window.
	var wood := Parts.wood("furniture", Color(0.5, 0.36, 0.22))
	_solid(r, Vector3(1.3, 0.75, 0.6), Vector3(w * 0.2, 0.375, -0.7), wood)
	Parts.box(r, Vector3(0.4, 0.04, 0.3), Vector3(w * 0.2, 0.77, -0.7), Parts.mat("ledger", Color(0.35, 0.12, 0.1), 0.8))


## The claims office: the plat board on the back wall, a desk with papers, a map cabinet, a
## district map on the wall and a small stove.
func _claims_inside(x: float, w: float, d: float) -> void:
	var r := _room(x)
	var wood := Parts.wood("furniture", Color(0.5, 0.36, 0.22))
	var paper := Parts.mat("paper", Color(0.88, 0.85, 0.75), 0.9)
	var back := -d + WALL
	_solid(r, Vector3(1.6, 0.78, 0.8), Vector3(1.6, 0.39, -1.3), wood)
	for j in 3:
		Parts.box(r, Vector3(0.3, 0.01, 0.22), Vector3(1.2 + j * 0.35, 0.79, -1.3), paper, Vector3(0, 0.1 * j, 0))
	var cx := -w * 0.5 + WALL + 0.8
	_solid(r, Vector3(1.4, 0.9, 0.6), Vector3(cx, 0.45, back + 0.35), Parts.wood("dark_wood", Color(0.3, 0.22, 0.15)))
	for k in 4:
		Parts.box(r, Vector3(1.3, 0.02, 0.01), Vector3(cx, 0.15 + k * 0.2, back + 0.66), wood)
	Parts.box(r, Vector3(0.02, 0.9, 1.4), Vector3(-w * 0.5 + WALL + 0.01, 1.6, -2.4), paper)
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	var ix := w * 0.5 - WALL - 0.45
	_solid(r, Vector3(0.5, 0.6, 0.5), Vector3(ix, 0.3, back + 0.5), iron)
	Parts.cyl(r, 0.06, 2.5, Vector3(ix, 1.85, back + 0.5), iron, Vector3.ZERO, -1.0, 10)


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
