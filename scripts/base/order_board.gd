extends StaticBody3D
## The general store's catalog, on a board by its door. Mouse wheel picks an item, E buys it.
## Big things are delivered to the shed at your cabin; the rest goes in your pack.
const Sfx = preload("res://scripts/core/sfx.gd")

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
	["dredge", "Suction dredge, with permit", 2500, "floats in deeper water and sucks up the river bottom by itself"],
	["dry_washer", "Dry washer", 1100, "recovers gold with air instead of water, for the desert washes"],
	["trailer", "Flatbed trailer", 800, "the pickup tows it; room for two more machines"],
	["trommel", "Trommel", 3500, "washes and screens gravel by the ton; runs off the pump like the high banker"],
	["excavator", "Mini-excavator", 6000, "drive it beside a trommel or high banker and dig a bucket at a time (left mouse)"],
	["camp", "Camp tent", 300, "pitch it anywhere: sleep there, and fast travel between your camps and the cabin (up to 3)"],
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
	if id == "camp":
		return int(inv.gear.get("camps", 0)) >= 3
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
	Sfx.play("sell", null, -4.0)
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
		"trommel":
			inv.gear["trommel"] = true
			said = "A trommel, by the shed at your cabin. Set it up near a pump on your claim, like the high banker."
		"excavator":
			inv.gear["excavator"] = true
			said = "A mini-excavator, parked by the shed. Drive it beside the trommel and dig with left mouse."
		"camp":
			inv.gear["camps"] = int(inv.gear.get("camps", 0)) + 1
			said = "A camp tent, by the shed at your cabin. Carry it (F) wherever you want a camp and set it down."
		"trailer":
			inv.gear["trailer"] = true
			said = "A flatbed trailer, parked behind the pickup at your cabin. Back the pickup up to it and hitch it (E)."
		"dry_washer":
			inv.gear["dry_washer"] = true
			said = "A dry washer. It's waiting by the shed: carry it (F) to dry gravel on your claim and dig next to it."
		"dredge":
			inv.gear["dredge"] = true
			said = "A suction dredge and a dredging permit. It's waiting by the shed: carry it (F) to deep water on your claim."
		_:
			inv.gear[id] = true
			said = "%s: %s." % [it[1], it[3]]
	get_tree().call_group("game", "deliver", id)
	player.hud.toast(said, Color(0.6, 1.0, 0.6), 5.0)
