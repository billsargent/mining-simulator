extends StaticBody3D
## Order board on the cabin wall. For now it sells one thing: a high banker with a water pump.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const HIGH_BANKER_PRICE := 350


func build() -> void:
	Parts.box(self, Vector3(0.9, 0.65, 0.04), Vector3.ZERO, Parts.wood("board", Color(0.55, 0.42, 0.28)))
	var paper := Parts.mat("paper", Color(0.92, 0.9, 0.84), 0.9)
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(-0.25, -0.05, 0.025), paper, Vector3(0, 0, 0.05))
	Parts.box(self, Vector3(0.22, 0.28, 0.005), Vector3(0.05, -0.08, 0.025), paper, Vector3(0, 0, -0.04))
	Parts.box(self, Vector3(0.18, 0.22, 0.005), Vector3(0.3, -0.02, 0.025), paper, Vector3(0, 0, 0.08))
	Parts.label(self, "ORDERS", Vector3(0, 0.22, 0.03), 28)
	Parts.collider(self, Vector3(0.9, 0.65, 0.12), Vector3.ZERO)


func prompt(player) -> String:
	var inv = player.inv
	var t := "[b]Order board[/b]"
	if inv.high_banker_bought:
		t += "\nMore gear is coming in the next build."
		return t
	t += "\n%s Order a high banker and water pump: $%d   (you have $%d)" % [Hud.key("E"), HIGH_BANKER_PRICE, inv.money]
	if inv.money < HIGH_BANKER_PRICE:
		t += "\n[color=#ffa060]$%d more to go[/color]" % (HIGH_BANKER_PRICE - inv.money)
	return t


func interact(player) -> void:
	var inv = player.inv
	if inv.high_banker_bought:
		player.hud.toast("You already have the high banker. More gear is coming in the next build.")
		return
	if inv.money < HIGH_BANKER_PRICE:
		player.hud.toast("Not enough money yet: $%d more to go." % (HIGH_BANKER_PRICE - inv.money))
		return
	inv.money -= HIGH_BANKER_PRICE
	inv.high_banker_bought = true
	inv.complete_goal("high_banker")
	get_tree().call_group("game", "deliver", "high_banker")
	player.hud.toast("Delivered to the shed: a high banker and a water pump.", Color(0.6, 1.0, 0.6), 5.0)
