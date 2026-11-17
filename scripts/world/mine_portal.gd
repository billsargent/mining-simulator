extends StaticBody3D
## The boarded-up mine entrance. Old mines open up in milestone M4.

const Hud = preload("res://scripts/ui/hud.gd")


func prompt(_player) -> String:
	return "[b]Old mine entrance[/b]\nBoarded up. Someone carved a date into the timber: 1887."


func interact(player) -> void:
	player.hud.toast("The boards won't budge. You'll need proper tools and a lamp before going in there.")
