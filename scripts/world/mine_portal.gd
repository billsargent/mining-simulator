extends StaticBody3D
## The mine entrance. Outside it leads in; the same script, marked as an exit, leads back out.

const Hud = preload("res://scripts/ui/hud.gd")

var is_exit := false


func prompt(_player) -> String:
	if is_exit:
		return "[b]Daylight[/b]\n%s Leave the mine" % Hud.key("E")
	return "[b]Old mine entrance[/b]   carved in the timber: 1887\n%s Squeeze through the boards" % Hud.key("E")


func interact(_player) -> void:
	get_tree().call_group("game", "exit_mine" if is_exit else "enter_mine")
