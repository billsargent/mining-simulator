extends StaticBody3D
## The general store's catalog, on a board by its door. Mouse wheel picks an item, E buys it.
## Big things are delivered to the shed at your cabin; the rest goes in your pack.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

## id, name, price, what it does
const ITEMS = [
	["high_banker", "High banker and water pump", 900, "work the banks away from the water"],
	["pick", "Miner's pick", 400, "chips rock faster and deeper than the hammer and chisel"],
	["rotary", "Rotary hammer", 1500, "tears through rock; needs the miner's pick first"],
	["crusher", "Powered rock crusher", 1200, "frees all the gold in your ore; pounding by hand loses about a third"],
	["classifier", "Classifier screen", 80, "screens the big gravel out of every shovelful, so pans wash down faster"],
	["bucket", "Big bucket", 150, "holds 10 shovelfuls instead of 6"],
	["sack", "Big ore sack", 200, "holds 20 pieces of ore instead of 10"],
	["moss", "Miner's moss carpet", 300, "your sluice and high banker hold on to much more of the fine gold"],
	["detector", "Metal detector", 700, "shows how much gold is in the ground under your feet"],
]
const SHOWN := 5

var _sel := 0


func build() -> void:
	Parts.box(self, Vector3(0.9, 0.65, 0.04), Vector3.ZERO, Parts.wood("board", Color(0.55, 0.42, 0.28)))
	var paper := Parts.mat("paper", Color(0.92, 0.9, 0.84), 0.9)
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(-0.25, -0.05, 0.025), paper, Vector3(0, 0, 0.05))
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(0.05, -0.08, 0.025), paper, Vector3(0, 0, -0.04))
	Parts.box(self, Vector3(0.18, 0.22, 0.005), Vector3(0.3, -0.02, 0.025), paper, Vector3(0, 0, 0.08))
	Parts.label(self, "CATALOG", Vector3(0, 0.22, 0.03), 28)
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
	return inv.gear.has(id)


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]General store[/b]   you have $%d" % inv.money
	var first := clampi(_sel - SHOWN / 2, 0, ITEMS.size() - SHOWN)
	if first > 0:
		t += "\n[color=#909090]...[/color]"
	for i in range(first, first + SHOWN):
		var it: Array = ITEMS[i]
		var line := "%s  $%d" % [it[1], it[2]]
		if _owned(inv, it[0]):
			line = "[color=#80a080]%s  (owned)[/color]" % it[1]
		if i == _sel:
			line = "[color=#ffd866]> " + line + "[/color]  [color=#c0c0c0]" + str(it[3]) + "[/color]"
		t += "\n" + line
	if first + SHOWN < ITEMS.size():
		t += "\n[color=#909090]...[/color]"
	return t + "\n" + Hud.key("Wheel") + " Choose     " + Hud.key("E") + " Buy"


func scroll(_player, dir: int) -> void:
	_sel = posmod(_sel - dir, ITEMS.size())


## Put the marker on an item (used by tests).
func select(id: String) -> void:
	for i in ITEMS.size():
		if ITEMS[i][0] == id:
			_sel = i


func interact(player) -> void:
	var inv = player.inv
	var it: Array = ITEMS[_sel]
	var id: String = it[0]
	var price: int = it[2]
	if _owned(inv, id):
		player.hud.toast("You already have the %s." % str(it[1]).to_lower())
		return
	if id == "rotary" and inv.tool_tier < 1:
		player.hud.toast("Buy the miner's pick first.")
		return
	if inv.money < price:
		player.hud.toast("Not enough money yet: $%d more to go." % (price - inv.money))
		return
	inv.money -= price
	var said := ""
	match id:
		"high_banker":
			inv.high_banker_bought = true
			inv.complete_goal("high_banker")
			said = "Delivered to the shed at your cabin: a high banker and a water pump."
		"pick":
			inv.tool_tier = 1
			said = "A miner's pick. Rock chips faster and deeper now."
		"rotary":
			inv.tool_tier = 2
			said = "A rotary hammer. Hold left mouse on the rock and it tears through."
		"crusher":
			inv.crusher_powered = true
			said = "A powered rock crusher, set up by the wash tub at your cabin."
		_:
			inv.gear[id] = true
			said = "%s: %s." % [it[1], it[3]]
	get_tree().call_group("game", "deliver", id)
	player.hud.toast(said, Color(0.6, 1.0, 0.6), 5.0)
