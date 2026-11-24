extends StaticBody3D
## An old vertical shaft in the hills (world_gen.shafts): a timber collar round a dark hole, a
## headframe with its sheave wheel, and a ladder going down. E climbs down into its small mine.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

var index := 0


func build(i: int, data: Dictionary) -> void:
	index = i
	var p: Vector2 = data["pos"]
	position = Vector3(p.x, data["h"], p.y)
	rotation.y = data["yaw"]
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	var dark := Parts.mat("shaft_dark", Color(0.02, 0.02, 0.02), 1.0)
	var rust := Parts.mat("rust", Color(0.35, 0.2, 0.12), 0.7, 0.5)
	# The hole, and a collar of squared timbers round it.
	Parts.box(self, Vector3(2.2, 0.02, 2.2), Vector3(0, 0.03, 0), dark)
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(2.8, 0.3, 0.3), Vector3(0, 0.15, s * 1.25), timber)
		Parts.box(self, Vector3(0.3, 0.3, 2.2), Vector3(s * 1.25, 0.15, 0), timber)
	# Headframe: four legs leaning in to a cap with a sheave wheel.
	var top := 5.2
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var a := Vector3(sx * 1.6, 0.0, sz * 1.6)
			var b := Vector3(sx * 0.55, top, sz * 0.55)
			var leg := Parts.box(self, Vector3(0.22, a.distance_to(b), 0.22), (a + b) * 0.5, timber)
			var up := (b - a).normalized()
			var side := up.cross(Vector3(0, 0, 1)).normalized()
			leg.basis = Basis(side, up, side.cross(up))
		Parts.box(self, Vector3(0.22, 0.22, 2.4), Vector3(sx * 1.05, 2.4, 0), timber)
	Parts.box(self, Vector3(1.4, 0.25, 1.4), Vector3(0, top, 0), timber)
	Parts.cyl(self, 0.6, 0.1, Vector3(0, top + 0.55, 0), rust, Vector3(PI / 2.0, 0, 0))
	# Ladder top sticking out of the hole.
	for s: float in [-0.25, 0.25]:
		Parts.box(self, Vector3(0.07, 1.4, 0.07), Vector3(-0.9, 0.4, s), timber)
	for y: float in [0.1, 0.45, 0.8]:
		Parts.box(self, Vector3(0.05, 0.05, 0.5), Vector3(-0.9, y, 0), timber)
	Parts.collider(self, Vector3(2.8, 0.3, 2.8), Vector3(0, 0.15, 0))
	Parts.collider(self, Vector3(0.3, 1.4, 0.7), Vector3(-0.9, 0.7, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.collider(self, Vector3(0.3, 3.0, 0.3), Vector3(sx * 1.4, 1.5, sz * 1.4))


## Where you stand after climbing out, and which way you face (away from the hole).
func exit_point() -> Vector3:
	return to_global(Vector3(-2.6, 0.1, 0))


func exit_yaw() -> float:
	return rotation.y + PI / 2.0


func prompt(_player) -> String:
	return "[b]Old shaft[/b]   a ladder goes down into the dark\n%s Climb down" % Hud.key("E")


func interact(_player) -> void:
	get_tree().call_group("game", "enter_shaft", index)
