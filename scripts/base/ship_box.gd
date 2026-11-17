extends StaticBody3D
## The gold buyer's pickup box. Bars sell by their pure gold content; nuggets and specimens
## (gold in quartz, left whole) sell to collectors at a premium.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const PRICE_PER_GRAM := 95.0


static func bar_value(bar: Dictionary) -> int:
	return roundi(float(bar["grams"]) * float(bar["purity"]) * PRICE_PER_GRAM)


static func nugget_value(m: float) -> int:
	return roundi(m * PRICE_PER_GRAM * (1.5 + minf(m, 2.0) * 0.25))


static func specimen_value(grams: float) -> int:
	return roundi(grams * PRICE_PER_GRAM * 2.5)


func build() -> void:
	var wood := Parts.wood("crate", Color(0.5, 0.38, 0.25))
	Parts.box(self, Vector3(0.75, 0.5, 0.5), Vector3(0, 0.25, 0), wood)
	Parts.box(self, Vector3(0.8, 0.05, 0.55), Vector3(0, 0.525, 0), Parts.wood("dark_wood", Color(0.3, 0.22, 0.15)))
	Parts.box(self, Vector3(0.06, 1.3, 0.06), Vector3(0.45, 0.65, -0.2), wood)
	Parts.box(self, Vector3(0.7, 0.3, 0.03), Vector3(0.45, 1.3, -0.2), Parts.wood("sign", Color(0.62, 0.52, 0.38)))
	Parts.label(self, "GOLD BUYER\nPICKUP", Vector3(0.45, 1.3, -0.18), 26)
	Parts.collider(self, Vector3(0.8, 0.55, 0.55), Vector3(0, 0.275, 0))
	Parts.collider(self, Vector3(0.7, 0.4, 0.1), Vector3(0.45, 1.3, -0.2))


func _total(inv) -> int:
	var total := 0
	for b in inv.bars:
		total += bar_value(b)
	for m in inv.nuggets:
		total += nugget_value(m)
	for g in inv.specimens:
		total += specimen_value(g)
	return total


func _empty(inv) -> bool:
	return inv.bars.is_empty() and inv.nuggets.is_empty() and inv.specimens.is_empty()


func _list(inv) -> String:
	var parts := PackedStringArray()
	for item in [[inv.bars.size(), "bar"], [inv.nuggets.size(), "nugget"], [inv.specimens.size(), "specimen"]]:
		if item[0] > 0:
			parts.append("%d %s%s" % [item[0], item[1], "" if item[0] == 1 else "s"])
	return ", ".join(parts)


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]Gold buyer's box[/b]"
	if _empty(inv):
		t += "\nMelt your gold into bars at the furnace, then ship them here."
	else:
		t += "\n%s Ship %s for $%d" % [Hud.key("E"), _list(inv), _total(inv)]
	if inv.vial_grams() > 0.0:
		t += "\n(Loose gold has to be melted into a bar first.)"
	return t


func interact(player) -> void:
	var inv = player.inv
	if _empty(inv):
		player.hud.toast("Nothing to ship yet. Melt your gold into a bar at the furnace.")
		return
	var total := _total(inv)
	var msg := "Shipped " + _list(inv)
	inv.money += total
	inv.bars.clear()
	inv.nuggets = PackedFloat32Array()
	inv.specimens = PackedFloat32Array()
	inv.complete_goal("sold")
	player.hud.toast("%s:  +$%d" % [msg, total], Color(0.6, 1.0, 0.6), 5.0)
