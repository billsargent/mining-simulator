extends StaticBody3D
## Grandpa's bunk: sleep until morning (the game saves).

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")


func build() -> void:
	var frame := Parts.wood("bunk", Color(0.38, 0.27, 0.17))
	Parts.box(self, Vector3(0.95, 0.3, 1.95), Vector3(0, 0.2, 0), frame)
	for p: Vector3 in [Vector3(-0.42, 0, -0.92), Vector3(0.42, 0, -0.92), Vector3(-0.42, 0, 0.92), Vector3(0.42, 0, 0.92)]:
		Parts.box(self, Vector3(0.08, 0.5, 0.08), p + Vector3(0, 0.25, 0), frame)
	Parts.box(self, Vector3(0.95, 0.4, 0.06), Vector3(0, 0.55, -0.95), frame)
	Parts.box(self, Vector3(0.85, 0.12, 1.85), Vector3(0, 0.41, 0.02), Parts.mat("mattress", Color(0.62, 0.58, 0.48), 0.95))
	Parts.box(self, Vector3(0.87, 0.06, 1.25), Vector3(0, 0.49, 0.32), Parts.mat("blanket", Color(0.45, 0.13, 0.1), 0.95))
	Parts.box(self, Vector3(0.55, 0.1, 0.32), Vector3(0, 0.5, -0.7), Parts.mat("pillow", Color(0.85, 0.83, 0.76), 0.95))
	Parts.collider(self, Vector3(0.95, 0.55, 1.95), Vector3(0, 0.275, 0))


func prompt(_player) -> String:
	return "[b]Grandpa's bunk[/b]\n%s Sleep until morning (saves the game)" % Hud.key("E")


func interact(_player) -> void:
	get_tree().call_group("game", "sleep")
