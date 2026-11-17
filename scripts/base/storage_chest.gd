extends StaticBody3D
## A sea chest in the cabin: somewhere safe to keep gold and goods between trips.
## Mouse wheel switches between putting everything in and taking everything out; E does it.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

var _take := false
var _lid: Node3D


func build() -> void:
	var wood := Parts.wood("chest", Color(0.42, 0.27, 0.15))
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	Parts.box(self, Vector3(1.0, 0.48, 0.55), Vector3(0, 0.24, 0), wood)
	for x: float in [-0.38, 0.38]:
		Parts.box(self, Vector3(0.05, 0.5, 0.57), Vector3(x, 0.24, 0), iron)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.48, -0.275)
	add_child(_lid)
	Parts.box(_lid, Vector3(1.02, 0.1, 0.57), Vector3(0, 0.05, 0.275), wood)
	Parts.box(_lid, Vector3(0.1, 0.08, 0.04), Vector3(0, 0.0, 0.57), iron)
	Parts.collider(self, Vector3(1.0, 0.6, 0.55), Vector3(0, 0.3, 0))


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]Storage chest[/b]\nIn the chest:  %s" % inv.describe_goods(inv.chest_goods())
	t += "\nYou carry:  %s" % inv.describe_goods(inv.carried_goods())
	var put := "Put everything in"
	var take := "Take everything out"
	if _take:
		t += "\n   %s      [color=#ffd866]> %s[/color]" % [put, take]
	else:
		t += "\n[color=#ffd866]> %s[/color]      %s" % [put, take]
	return t + "\n" + Hud.key("Wheel") + " Choose     " + Hud.key("E") + " Do it"


func scroll(_player, _dir: int) -> void:
	_take = not _take


func interact(player) -> void:
	var inv = player.inv
	var n: int = inv.take_from_chest() if _take else inv.store_in_chest()
	_flap()
	if n == 0:
		player.hud.toast("Nothing to take out." if _take else "Nothing to put away. Gold, jars, ore, bars, nuggets, specimens and garnets go in here.")
	elif _take:
		player.hud.toast("Took %d thing%s out of the chest." % [n, "" if n == 1 else "s"], Color(1.0, 0.9, 0.6))
	else:
		player.hud.toast("Put %d thing%s away in the chest." % [n, "" if n == 1 else "s"], Color(1.0, 0.9, 0.6))
	player.refresh_hud()


func _flap() -> void:
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.1, 0.25)
	tw.tween_interval(0.3)
	tw.tween_property(_lid, "rotation:x", 0.0, 0.25)
