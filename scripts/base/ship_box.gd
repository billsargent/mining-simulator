extends StaticBody3D
## The gold buyer's counter at the assay office in town. Bars sell by their pure gold content
## at the day's price; nuggets and specimens (gold in quartz, left whole) sell to collectors
## at a premium.
const Sfx = preload("res://scripts/core/sfx.gd")

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Market = preload("res://scripts/core/market.gd")


func build() -> void:
	var wood := Parts.wood("counter", Color(0.45, 0.33, 0.22))
	var brass := Parts.mat("brass", Color(0.78, 0.6, 0.25), 0.35, 0.9)
	Parts.box(self, Vector3(1.6, 0.95, 0.55), Vector3(0, 0.475, 0), wood)
	Parts.box(self, Vector3(1.7, 0.05, 0.65), Vector3(0, 0.975, 0), Parts.wood("dark_wood", Color(0.3, 0.22, 0.15)))
	# A balance scale on the counter.
	Parts.cyl(self, 0.02, 0.4, Vector3(0.35, 1.2, 0), brass, Vector3.ZERO, -1.0, 8)
	Parts.box(self, Vector3(0.5, 0.02, 0.02), Vector3(0.35, 1.38, 0), brass)
	for s: float in [-1.0, 1.0]:
		Parts.cyl(self, 0.09, 0.015, Vector3(0.35 + s * 0.23, 1.24, 0), brass, Vector3.ZERO, -1.0, 12)
	Parts.label(self, "GOLD BUYER", Vector3(-0.3, 1.25, 0.05), 24)
	Parts.collider(self, Vector3(1.7, 1.0, 0.65), Vector3(0, 0.5, 0))

const Garnets = preload("res://scripts/gold/garnets.gd")


func _total(inv) -> int:
	var total := 0
	for b in inv.bars:
		total += Market.bar_value(b)
	for m in inv.nuggets:
		total += Market.nugget_value(m)
	for g in inv.specimens:
		total += Market.specimen_value(g)
	for ct in inv.garnets:
		total += Garnets.value(ct)
	return total


func _empty(inv) -> bool:
	return inv.bars.is_empty() and inv.nuggets.is_empty() and inv.specimens.is_empty() and inv.garnets.is_empty()


func _list(inv) -> String:
	var parts := PackedStringArray()
	for item in [[inv.bars.size(), "bar"], [inv.nuggets.size(), "nugget"], [inv.specimens.size(), "specimen"], [inv.garnets.size(), "garnet"]]:
		if item[0] > 0:
			parts.append("%d %s%s" % [item[0], item[1], "" if item[0] == 1 else "s"])
	return ", ".join(parts)


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]Assay office[/b]   gold today: $%.2f a gram  (%s on yesterday)" % [Market.price(), Market.trend()]
	if Market.news() != "":
		t += "
[color=#f0d080]%s[/color]" % Market.news()
	if _empty(inv):
		t += "\nBring bars from your furnace, or nuggets, specimens and garnets."
	else:
		t += "\n%s Sell %s for $%d" % [Hud.key("E"), _list(inv), _total(inv)]
	if inv.vial_grams() > 0.0:
		t += "\n(Loose gold has to be melted into a bar first.)"
	return t


func interact(player) -> void:
	var inv = player.inv
	if _empty(inv):
		player.hud.toast("Nothing to sell yet. Melt your gold into a bar at the furnace by your cabin.")
		return
	var total := _total(inv)
	var msg := "Sold " + _list(inv)
	inv.money += total
	inv.record_sale(total, Market.day)
	Sfx.play("sell", null, -4.0)
	inv.bars.clear()
	inv.nuggets = PackedFloat32Array()
	inv.specimens = PackedFloat32Array()
	inv.garnets = PackedFloat32Array()
	inv.watch_garnets()
	inv.complete_goal("sold")
	player.hud.toast("%s:  +$%d" % [msg, total], Color(0.6, 1.0, 0.6), 5.0)
