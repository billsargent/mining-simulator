extends StaticBody3D
## Order board on the cabin wall: a short catalog. Mouse wheel picks an item, E orders it.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

## id, name, price, what it does
const ITEMS = [
	["high_banker", "High banker and water pump", 350, "work the banks away from the water"],
	["pick", "Miner's pick", 150, "chips rock faster and deeper than the hammer and chisel"],
	["rotary", "Rotary hammer", 600, "tears through rock; needs the miner's pick first"],
	["crusher", "Powered rock crusher", 400, "frees all the gold in your ore; pounding by hand loses about a third"],
]

var _sel := 0


func build() -> void:
	Parts.box(self, Vector3(0.9, 0.65, 0.04), Vector3.ZERO, Parts.wood("board", Color(0.55, 0.42, 0.28)))
	var paper := Parts.mat("paper", Color(0.92, 0.9, 0.84), 0.9)
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(-0.25, -0.05, 0.025), paper, Vector3(0, 0, 0.05))
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(0.05, -0.08, 0.025), paper, Vector3(0, 0, -0.04))
	Parts.box(self, Vector3(0.18, 0.22, 0.005), Vector3(0.3, -0.02, 0.025), paper, Vector3(0, 0, 0.08))
	Parts.label(self, "ORDERS", Vector3(0, 0.22, 0.03), 28)
	Parts.collider(self, Vector3(0.9, 0.65, 0.12), Vector3.ZERO)


func _owned(inv, id: String) -> bool:
	match id:
		"high_banker":
			return inv.high_banker_bought
		"pick":
			return inv.tool_tier >= 1
		"rotary":
			return inv.tool_tier >= 2
		"crusher":
			return inv.crusher_powered
	return false


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]Order board[/b]   you have $%d" % inv.money
	for i in ITEMS.size():
		var it: Array = ITEMS[i]
		var line := "%s  $%d" % [it[1], it[2]]
		if _owned(inv, it[0]):
			line = "[color=#80a080]%s  (owned)[/color]" % it[1]
		if i == _sel:
			line = "[color=#ffd866]> " + line + "[/color]  [color=#c0c0c0]" + str(it[3]) + "[/color]"
		t += "\n" + line
	return t + "\n" + Hud.key("Wheel") + " Choose     " + Hud.key("E") + " Order"


func scroll(_player, dir: int) -> void:
	_sel = posmod(_sel - dir, ITEMS.size())


func interact(player) -> void:
	var inv = player.inv
	var it: Array = ITEMS[_sel]
	var id: String = it[0]
	var price: int = it[2]
	if _owned(inv, id):
		player.hud.toast("You already have the %s." % str(it[1]).to_lower())
		return
	if id == "rotary" and inv.tool_tier < 1:
		player.hud.toast("Order the miner's pick first.")
		return
	if inv.money < price:
		player.hud.toast("Not enough money yet: $%d more to go." % (price - inv.money))
		return
	inv.money -= price
	match id:
		"high_banker":
			inv.high_banker_bought = true
			inv.complete_goal("high_banker")
			get_tree().call_group("game", "deliver", "high_banker")
			player.hud.toast("Delivered to the shed: a high banker and a water pump.", Color(0.6, 1.0, 0.6), 5.0)
		"pick":
			inv.tool_tier = 1
			player.hud.toast("A miner's pick. Rock chips faster and deeper now.", Color(0.6, 1.0, 0.6), 5.0)
		"crusher":
			inv.crusher_powered = true
			get_tree().call_group("game", "deliver", "crusher")
			player.hud.toast("A powered rock crusher, set up by the wash tub. It frees all the gold in your ore.", Color(0.6, 1.0, 0.6), 5.0)
		"rotary":
			inv.tool_tier = 2
			player.hud.toast("A rotary hammer. Hold left mouse on the rock and it tears through.", Color(0.6, 1.0, 0.6), 5.0)
