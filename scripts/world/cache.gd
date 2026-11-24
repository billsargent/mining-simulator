extends StaticBody3D
## Something to search at a roadside place or a hidden stash: an old trunk, a glovebox, a loose
## chimney stone. Searching it once gives what's there (money, gold, a garnet, a note that marks
## a place on the map); afterwards it's empty. Which ones you've searched is saved in inv.finds.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Sfx = preload("res://scripts/core/sfx.gd")

var id := ""
var what := "the trunk"          # "Search <what>"
var title := ""                  # note title, if it holds a note
var text := ""
var money := 0
var grams := 0.0                 # loose gold, into the vial
var nugget := 0.0
var garnet := 0.0
var mark_where := ""             # passed to mark_place on the "game" group
var mark_label := ""
var needs := ""                  # a find that must come first (a trail clue means nothing before)
var locked_hint := "Something old here, but it means nothing to you yet."


## A plain collider of `size` at `pos`, so the player can aim at it.
func shape(size: Vector3, pos: Vector3) -> void:
	Parts.collider(self, size, pos)


func prompt(player) -> String:
	if player.hud.note_open():
		return "[b]%s[/b]\n%s Put it down" % [title, Hud.key("E")]
	if needs != "" and not player.inv.finds.has(needs) and not player.inv.finds.has(id):
		return locked_hint
	if player.inv.finds.has(id):
		return "Searched: nothing more here." if text == "" else "%s Read the note again" % Hud.key("E")
	return "%s Search %s" % [Hud.key("E"), what]


func interact(player) -> void:
	var inv = player.inv
	if player.hud.note_open():
		player.hud.hide_note()
		return
	if needs != "" and not inv.finds.has(needs) and not inv.finds.has(id):
		return
	if inv.finds.has(id):
		if text != "":
			player.hud.show_note(title, text)
		return
	inv.finds[id] = true
	Sfx.play("creak", global_position, -6.0)
	var got := PackedStringArray()
	if money > 0:
		inv.money += money
		got.append("$%d in old coins" % money)
	if grams > 0.0:
		inv.add_gold(PackedFloat32Array([grams]))
		got.append("%.2f g of gold dust" % grams)
	if nugget > 0.0:
		inv.add_nugget(nugget)
		got.append("a %.1f g nugget" % nugget)
	if garnet > 0.0:
		if "garnets" in inv:
			inv.garnets.append(garnet)
			got.append("a %.1f carat garnet" % garnet)
	if text != "":
		player.hud.show_note(title, text)
	if mark_where != "":
		get_tree().call_group("game", "mark_place", mark_where, mark_label)
		got.append("a place marked on your map: " + mark_label)
	if got.is_empty():
		player.hud.toast("Nothing worth taking. Someone got here first.", Color(0.85, 0.85, 0.85), 3.0)
	else:
		player.hud.toast("Found " + ", ".join(got) + ".", Color(1.0, 0.9, 0.55), 6.0)
		Sfx.play("clink", null, -6.0)
	player.refresh_hud()
