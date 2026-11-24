extends StaticBody3D
## The claims board at the claims office in town. Mouse wheel picks a claim, E buys it.
## Every claim is drawn on your map, so you can go and test-pan it before you pay.
const Sfx = preload("res://scripts/core/sfx.gd")

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Claims = preload("res://scripts/core/claims.gd")

var _sel := 1


func build() -> void:
	Parts.box(self, Vector3(1.1, 0.75, 0.04), Vector3.ZERO, Parts.wood("board", Color(0.55, 0.42, 0.28)))
	Parts.box(self, Vector3(0.9, 0.45, 0.005), Vector3(0, -0.08, 0.025), Parts.mat("plat", Color(0.86, 0.84, 0.72), 0.9))
	Parts.label(self, "CLAIMS", Vector3(0, 0.27, 0.03), 28)
	Parts.collider(self, Vector3(1.1, 0.75, 0.12), Vector3.ZERO)


func prompt(player) -> String:
	var t := "[b]Claims office[/b]   you have $%d\nMachines only run on a claim you own. Pan a claim first to see if it pays." % player.inv.money
	for i in Claims.list.size():
		var c: Dictionary = Claims.list[i]
		if not Claims.known(c):
			continue
		var line := "%s, %s  $%d" % [c["name"], c["river"], c["price"]]
		if Claims.is_owned(c["id"]):
			line = "[color=#80a080]%s, %s  (yours)[/color]" % [c["name"], c["river"]]
		if i == _sel:
			line = "[color=#ffd866]> " + line + "[/color]"
		t += "\n" + line
	return t + "\n" + Hud.key("Wheel") + " Choose     " + Hud.key("E") + " Buy the claim"


func scroll(_player, dir: int) -> void:
	for _i in Claims.list.size():
		_sel = posmod(_sel - dir, Claims.list.size())
		if Claims.known(Claims.list[_sel]):
			return


func select(id: String) -> void:
	for i in Claims.list.size():
		if Claims.list[i]["id"] == id:
			_sel = i


func interact(player) -> void:
	var inv = player.inv
	var c: Dictionary = Claims.list[_sel]
	if not Claims.known(c):
		return
	if Claims.is_owned(c["id"]):
		player.hud.toast("%s is already yours." % c["name"])
		return
	var price: int = c["price"]
	if inv.money < price:
		player.hud.toast("Not enough money yet: $%d more to go." % (price - inv.money))
		return
	inv.money -= price
	Sfx.play("sell", null, -4.0)
	inv.claims[c["id"]] = true
	if c["id"] == "ledge":
		inv.complete_goal("claim")
		inv.complete_goal("ledge")
		player.hud.toast("Dutch's Ledge is yours: Grandpa's lost ground, bought back. Go up Granite Creek and pan it.", Color(1.0, 0.85, 0.35), 8.0)
		return
	inv.complete_goal("claim")
	player.hud.toast("%s on %s is yours. Your machines will run there now." % [c["name"], c["river"]], Color(0.6, 1.0, 0.6), 6.0)
