extends StaticBody3D
## The cabin door: sleep until morning (the game saves).

const Hud = preload("res://scripts/ui/hud.gd")


func prompt(_player) -> String:
	return "[b]Grandpa's cabin[/b]\n%s Sleep until morning (saves the game)" % Hud.key("E")


func interact(_player) -> void:
	get_tree().call_group("game", "sleep")
