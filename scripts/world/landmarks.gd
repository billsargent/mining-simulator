extends Node3D
## Landmarks on the level sites from the world generator: the abandoned camp up Last Chance
## Creek, and a boarded-up mine entrance above Rattlesnake Gulch (old mines open in M4).
## Local axes of each landmark: +Z faces the creek.

const Parts = preload("res://scripts/machines/parts.gd")
const MinePortal = preload("res://scripts/world/mine_portal.gd")


func build(terrain, sites: Dictionary) -> void:
	_camp(_anchor(terrain, sites["camp"]))
	_mine(_anchor(terrain, sites["mine"]))


func _anchor(terrain, site: Dictionary) -> Node3D:
	var pos: Vector2 = site["pos"]
	var facing: Vector2 = site["facing"]
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
	n.rotation.y = atan2(facing.x, facing.y)
	return n


## A collapsed cabin, an old rusty sluice and a fire ring.
func _camp(root: Node3D) -> void:
	var logs := Parts.wood("old_logs", Color(0.33, 0.27, 0.22))
	var rust := Parts.mat("rust", Color(0.42, 0.24, 0.14), 0.9, 0.3)
	var stone := Parts.mat("stone", Color(0.42, 0.4, 0.38), 0.95)
	var r := 0.13
	for i in 6:
		var y := r + i * r * 1.85
		Parts.cyl(root, r, 4.6, Vector3(0, y, -3.5), logs, Vector3(0, 0, PI / 2.0), -1.0, 8)
		if i < 4:
			Parts.cyl(root, r, 3.6, Vector3(-2.2, y + r, -1.8), logs, Vector3(PI / 2.0, 0, 0), -1.0, 8)
		if i < 2:
			Parts.cyl(root, r, 3.6, Vector3(2.2, y + r, -1.8), logs, Vector3(PI / 2.0, 0, 0), -1.0, 8)
	Parts.box(root, Vector3(4.4, 0.06, 2.6), Vector3(0.3, 0.7, -2.0), Parts.wood("old_roof", Color(0.28, 0.25, 0.22)), Vector3(0.5, 0.1, 0.35))
	Parts.cyl(root, r, 3.0, Vector3(1.0, 0.15, -0.5), logs, Vector3(PI / 2.0, 0.6, 0), -1.0, 8)
	# An old sluice left to rust.
	Parts.box(root, Vector3(1.8, 0.01, 0.32), Vector3(3.2, 0.25, 0.8), rust, Vector3(0, 0.3, 0.12))
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(1.8, 0.14, 0.01), Vector3(3.2, 0.31, 0.8 + s * 0.16), rust, Vector3(0, 0.3, 0.12))
	for k in 9:
		var a := TAU * k / 9.0
		Parts.box(root, Vector3(0.28, 0.2, 0.22), Vector3(-1.2 + cos(a) * 0.55, 0.1, 1.6 + sin(a) * 0.55), stone, Vector3(0, a, 0))
	Parts.box(root, Vector3(0.08, 1.4, 0.08), Vector3(-3.2, 0.7, 2.6), logs)
	Parts.box(root, Vector3(1.3, 0.4, 0.04), Vector3(-3.2, 1.35, 2.62), Parts.wood("sign", Color(0.62, 0.52, 0.38)))
	Parts.label(root, "LAST CHANCE\nCAMP", Vector3(-3.2, 1.35, 2.65), 26)
	var body := StaticBody3D.new()
	root.add_child(body)
	Parts.collider(body, Vector3(4.6, 1.2, 0.3), Vector3(0, 0.6, -3.5))
	Parts.collider(body, Vector3(0.3, 0.9, 3.6), Vector3(-2.2, 0.45, -1.8))
	# Inside: gappy floorboards, a rusted stove against the back wall and a bunk frame.
	var boards := Parts.wood("old_floor", Color(0.36, 0.3, 0.24))
	for i in 14:
		if i % 4 != 1:
			Parts.box(root, Vector3(0.26, 0.04, 3.2 - 0.4 * float(i % 2)), Vector3(-2.0 + i * 0.3, 0.03, -1.8), boards)
	Parts.box(root, Vector3(0.6, 0.5, 0.45), Vector3(1.2, 0.3, -3.05), rust)
	Parts.cyl(root, 0.06, 0.8, Vector3(1.25, 0.95, -3.1), rust, Vector3(0.3, 0, 0), -1.0, 8)
	Parts.collider(body, Vector3(0.6, 0.55, 0.45), Vector3(1.2, 0.28, -3.05))
	for p: Vector3 in [Vector3(-1.75, 0.25, -3.0), Vector3(-1.05, 0.25, -3.0), Vector3(-1.75, 0.25, -1.2), Vector3(-1.05, 0.25, -1.2)]:
		Parts.box(root, Vector3(0.08, 0.5, 0.08), p, logs)
	for x: float in [-1.75, -1.05]:
		Parts.box(root, Vector3(0.06, 0.12, 1.9), Vector3(x, 0.42, -2.1), logs)
	Parts.collider(body, Vector3(0.8, 0.5, 1.9), Vector3(-1.4, 0.25, -2.1))


## A timber portal in a rock face, boarded up.
func _mine(root: Node3D) -> void:
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	var rock := Parts.mat("rock_face", Color(0.4, 0.38, 0.36), 0.95)
	Parts.box(root, Vector3(7.0, 5.0, 3.0), Vector3(0, 2.0, -2.4), rock)
	Parts.box(root, Vector3(2.0, 2.4, 0.2), Vector3(0, 1.2, -0.95), Parts.mat("dark", Color(0.02, 0.02, 0.02), 1.0))
	for x: float in [-1.05, 1.05]:
		Parts.box(root, Vector3(0.25, 2.6, 0.25), Vector3(x, 1.3, -0.85), timber)
	Parts.box(root, Vector3(2.6, 0.28, 0.3), Vector3(0, 2.7, -0.85), timber)
	for k in 5:
		Parts.box(root, Vector3(2.2, 0.18, 0.05), Vector3(0, 0.4 + k * 0.45, -0.7), timber, Vector3(0, 0, 0.06 * (k % 2 * 2 - 1)))
	Parts.label(root, "DANGER\nKEEP OUT", Vector3(0, 1.35, -0.66), 30)
	var door := MinePortal.new()
	root.add_child(door)
	Parts.collider(door, Vector3(2.4, 2.8, 0.6), Vector3(0, 1.4, -0.85))
	var body := StaticBody3D.new()
	root.add_child(body)
	Parts.collider(body, Vector3(7.0, 5.0, 2.4), Vector3(0, 2.0, -2.7))
