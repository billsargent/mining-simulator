extends StaticBody3D
## Hand crusher (an iron mortar and a heavy pestle): pounds a sack of quartz ore into a jar of
## crushed material you can pan like sluice concentrate. A powered crusher comes later.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")


func build() -> void:
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	Parts.cyl(self, 0.3, 0.5, Vector3(0, 0.25, 0), Parts.wood("stump", Color(0.4, 0.3, 0.2)), Vector3.ZERO, -1.0, 14)
	Parts.cyl(self, 0.14, 0.28, Vector3(0, 0.64, 0), iron, Vector3.ZERO, 0.19, 14)
	Parts.cyl(self, 0.035, 0.8, Vector3(0.05, 1.0, 0), iron, Vector3(0, 0, -0.15), -1.0, 8)
	Parts.label(self, "ORE CRUSHER", Vector3(0, 1.5, 0), 24)
	Parts.collider(self, Vector3(0.7, 1.4, 0.7), Vector3(0, 0.7, 0))


func prompt(player) -> String:
	var n: int = player.inv.ore.size()
	if n == 0:
		return "[b]Ore crusher[/b]\nBring quartz ore from the old mine."
	return "[b]Ore crusher[/b]\n%s Crush %d piece%s of ore into a jar to pan" % [Hud.key("E"), n, "" if n == 1 else "s"]


func interact(player) -> void:
	var inv = player.inv
	if inv.ore.is_empty():
		player.hud.toast("No ore to crush. Quartz veins in the old mine carry gold.")
		return
	var jar := Paydirt.new()
	jar.black_sand = 0.25
	jar.gravel = 0.5
	jar.sand = 1.0
	for o in inv.ore:
		for m in o.gold:
			jar.add_gold(m)
	inv.ore.clear()
	inv.cons.append(jar)
	inv.complete_goal("crushed")
	player.hud.toast("Pounded the ore to sand. Pan the jar at the wash tub.", Color(1.0, 0.9, 0.6), 5.0)
