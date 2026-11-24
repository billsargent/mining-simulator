extends StaticBody3D
## A sea chest in the cabin: somewhere safe to keep gold and goods between trips.
## E stores everything valuable you carry, or takes it all back (the wheel picks which;
## it picks the side that has something on its own).

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
	var inside: Array = inv.chest_goods()
	var carried: Array = inv.carried_goods()
	_pick_sensible(inv, inside, carried)
	var t := "[b]Storage chest[/b]
In the chest:  %s" % inv.describe_goods(inside)
	t += "
You carry:  %s" % inv.describe_goods(carried)
	if inv.goods_empty(inside) and inv.goods_empty(carried):
		return t + "
[color=#aaaaaa]Gold, jars, ore, bars, nuggets, specimens and garnets go in here.[/color]"
	var put := "Store all"
	var take := "Take all"
	if _take:
		t += "
   %s      [color=#ffd866]> %s[/color]" % [put, take]
	else:
		t += "
[color=#ffd866]> %s[/color]      %s" % [put, take]
	if _take and int(inside[1]) > 0 and inv.ore.size() + int(inside[1]) > inv.ore_capacity():
		t += "
[color=#ff9966]Your ore sack holds %d more; the rest stays here.[/color]" % maxi(0, inv.ore_capacity() - inv.ore.size())
	return t + "
" + Hud.key("Wheel") + " Store / take     " + Hud.key("E") + " Do it"


## If the chosen side has nothing to move but the other does, choose the other.
func _pick_sensible(inv, inside: Array, carried: Array) -> void:
	if _take and inv.goods_empty(inside) and not inv.goods_empty(carried):
		_take = false
	elif not _take and inv.goods_empty(carried) and not inv.goods_empty(inside):
		_take = true


func scroll(_player, _dir: int) -> void:
	_take = not _take


func interact(player) -> void:
	var inv = player.inv
	_pick_sensible(inv, inv.chest_goods(), inv.carried_goods())
	var left: int = inv.chest_ore.size()
	var moved: Array = inv.take_from_chest() if _take else inv.store_in_chest()
	_flap()
	if inv.goods_empty(moved):
		if _take and left > 0:
			player.hud.toast("Your ore sack is full. %d piece%s of ore stay in the chest." % [left, "" if left == 1 else "s"], Color(1.0, 0.6, 0.4))
		else:
			player.hud.toast("Nothing to move. Gold, jars, ore, bars, nuggets, specimens and garnets go in here.")
	else:
		var msg: String = ("Took out: " if _take else "Stored: ") + inv.describe_goods(moved)
		var still: int = inv.chest_ore.size() if _take else 0
		if still > 0:
			msg += "
Ore sack full: %d piece%s of ore left in the chest." % [still, "" if still == 1 else "s"]
		player.hud.toast(msg, Color(1.0, 0.9, 0.6))
	player.refresh_hud()


func _flap() -> void:
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.1, 0.25)
	tw.tween_interval(0.3)
	tw.tween_property(_lid, "rotation:x", 0.0, 0.25)
