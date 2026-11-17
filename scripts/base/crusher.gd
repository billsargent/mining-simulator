extends StaticBody3D
## Ore crusher: turns a sack of quartz ore into a jar of crushed material you can pan like
## sluice concentrate. It starts as an iron mortar and a heavy pestle, which leaves about a
## third of the gold locked in the grit. The powered crusher from the order board frees it all.
const Sfx = preload("res://scripts/core/sfx.gd")

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")

const HAND_RECOVERY := 0.65

var powered := false
var _hand: Node3D
var _engine: Node3D


func build() -> void:
	var iron := Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7)
	_hand = Node3D.new()
	add_child(_hand)
	Parts.cyl(_hand, 0.3, 0.5, Vector3(0, 0.25, 0), Parts.wood("stump", Color(0.4, 0.3, 0.2)), Vector3.ZERO, -1.0, 14)
	Parts.cyl(_hand, 0.14, 0.28, Vector3(0, 0.64, 0), iron, Vector3.ZERO, 0.19, 14)
	Parts.cyl(_hand, 0.035, 0.8, Vector3(0.05, 1.0, 0), iron, Vector3(0, 0, -0.15), -1.0, 8)
	# The powered one: a jaw crusher on a skid, belt-driven by a small engine.
	_engine = Node3D.new()
	_engine.visible = false
	_engine.position.x = -0.25
	_engine.rotation.y = PI / 2.0
	add_child(_engine)
	var green := Parts.paint("crusher_green", Color(0.2, 0.36, 0.26))
	var steel := Parts.steel()
	for z: float in [-0.28, 0.28]:
		Parts.box(_engine, Vector3(1.5, 0.1, 0.1), Vector3(0.15, 0.05, z), Parts.wood("skid", Color(0.42, 0.32, 0.22)))
	Parts.box(_engine, Vector3(0.55, 0.6, 0.5), Vector3(-0.2, 0.42, 0), green)
	Parts.box(_engine, Vector3(0.5, 0.3, 0.46), Vector3(-0.2, 0.86, 0), steel, Vector3(0, 0, 0.0))
	Parts.box(_engine, Vector3(0.62, 0.04, 0.58), Vector3(-0.2, 1.02, 0), steel)
	Parts.box(_engine, Vector3(0.3, 0.05, 0.3), Vector3(-0.62, 0.2, 0), steel, Vector3(0, 0, -0.5))
	for z: float in [-0.3, 0.3]:
		Parts.cyl(_engine, 0.26, 0.05, Vector3(-0.2, 0.55, z), iron, Vector3(PI / 2.0, 0, 0), -1.0, 18)
	Parts.box(_engine, Vector3(0.4, 0.32, 0.34), Vector3(0.62, 0.28, 0), Parts.paint("engine_red", Color(0.55, 0.14, 0.1)))
	Parts.cyl(_engine, 0.1, 0.16, Vector3(0.62, 0.52, 0), iron, Vector3.ZERO, -1.0, 10)
	Parts.cyl(_engine, 0.08, 0.05, Vector3(0.62, 0.3, 0.3), iron, Vector3(PI / 2.0, 0, 0), -1.0, 12)
	Parts.box(_engine, Vector3(0.8, 0.03, 0.04), Vector3(0.21, 0.44, 0.3), Parts.hose(), Vector3(0, 0, -0.3))
	Parts.label(self, "ORE CRUSHER", Vector3(0, 1.5, 0), 24)
	Parts.collider(self, Vector3(0.7, 1.4, 0.7), Vector3(0, 0.7, 0))


func set_powered(on: bool) -> void:
	powered = on
	_hand.visible = not on
	_engine.visible = on


func prompt(player) -> String:
	var title := "[b]Powered ore crusher[/b]" if powered else "[b]Ore crusher[/b]  (by hand: about a third of the gold stays in the grit)"
	var n: int = player.inv.ore.size()
	if n == 0:
		return title + "\nBring quartz ore from the old mine."
	return title + "\n%s Crush %d piece%s of ore into a jar to pan" % [Hud.key("E"), n, "" if n == 1 else "s"]


func interact(player) -> void:
	var inv = player.inv
	if inv.ore.is_empty():
		player.hud.toast("No ore to crush. Quartz veins in the old mine carry gold.")
		return
	var jar := Paydirt.new()
	jar.black_sand = 0.25
	Sfx.play("thud", global_position)
	jar.gravel = 0.5
	jar.sand = 1.0
	var total := 0
	var freed := 0
	for o in inv.ore:
		for m in o.gold:
			total += 1
			if powered or randf() < HAND_RECOVERY:
				jar.add_gold(m)
				freed += 1
	if freed == 0 and total > 0:
		jar.add_gold(inv.ore[0].gold[0])
	inv.ore.clear()
	inv.cons.append(jar)
	inv.complete_goal("crushed")
	if powered:
		player.hud.toast("The crusher chews the ore to fine sand. Pan the jar at the wash tub.", Color(1.0, 0.9, 0.6), 5.0)
	else:
		player.hud.toast("Pounded the ore to coarse sand. Pan the jar at the wash tub.", Color(1.0, 0.9, 0.6), 5.0)
