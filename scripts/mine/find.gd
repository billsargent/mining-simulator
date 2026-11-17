extends StaticBody3D
## Something the old crew left in the mine: a journal, a map, a last note. Reading it shows the
## page, and the first time it marks the place it talks about on your map.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

## kind -> [name, title on the page, text, river the place is on ("" = none), label on the map]
const FINDS = {
	"journal": ["Miner's journal", "Journal of E. Hendricks, 1889",
		"Sept 3.  The vein pinches and swells but she holds her values. Foreman says the lower level runs richer and I believe him, bad air or no.\n\n"
		+ "Sept 19.  Sundays I take the pan down the gulch. There is a bar below the second bend where the creek drops its load. Took near half an ounce off it in a morning and told no one.\n\n"
		+ "Oct 2.  Dutch swears there is a ledge up north that makes this hole look like a gravel pit. He has a piece of it in his coat. I have seen it. It is more gold than rock.",
		"Rattlesnake Gulch", "Hendricks' bar"],
	"map": ["Old map in a tin", "A hand-drawn map, stained and folded",
		"Pencil on oilcloth. The big river runs across the middle, and the creeks are drawn in with care.\n\n"
		+ "On a creek to the north-east someone has inked a heavy cross and written beside it:\n\n"
		+ "\"Good pay on bedrock. Worked two weeks, snowed out. Coming back in spring.\"\n\n"
		+ "Nothing on the map says they ever did.",
		"Tamarack Creek", "Cross on the old map"],
	"note": ["Folded note", "A note, weighted down with a drill steel",
		"To whoever comes down here after us.\n\n"
		+ "The air is gone bad past the last set and the company will not pay to fix it, so we are pulled out. The best of the vein is still in the wall. Take it quick and get out.\n\n"
		+ "Dutch has gone north to find his ledge again. He drew me the way and I have put it where the\n\n"
		+ "(the bottom of the page is torn away)",
		"", ""],
}

var kind := "journal"


func build(k: String) -> void:
	kind = k
	var crate := Parts.wood("crate", Color(0.5, 0.38, 0.25))
	var paper := Parts.mat("paper", Color(0.92, 0.9, 0.84), 0.9)
	Parts.box(self, Vector3(0.6, 0.45, 0.45), Vector3(0, 0.225, 0), crate)
	match kind:
		"journal":
			Parts.box(self, Vector3(0.24, 0.05, 0.32), Vector3(0.05, 0.475, 0), Parts.mat("leather", Color(0.3, 0.16, 0.1), 0.7), Vector3(0, 0.3, 0))
			Parts.box(self, Vector3(0.22, 0.03, 0.3), Vector3(0.05, 0.48, 0), paper, Vector3(0, 0.3, 0))
		"map":
			Parts.box(self, Vector3(0.34, 0.07, 0.24), Vector3(0, 0.485, 0), Parts.galvanized(), Vector3(0, -0.2, 0))
			Parts.cyl(self, 0.03, 0.4, Vector3(0.02, 0.55, 0.02), paper, Vector3(PI / 2.0, 0.6, 0), -1.0, 8)
		_:
			Parts.box(self, Vector3(0.2, 0.006, 0.26), Vector3(0, 0.455, 0), paper, Vector3(0, 0.2, 0))
			Parts.cyl(self, 0.014, 0.5, Vector3(0.02, 0.47, 0.0), Parts.steel(), Vector3(PI / 2.0, 1.1, 0), -1.0, 6)
	Parts.collider(self, Vector3(0.6, 0.65, 0.45), Vector3(0, 0.325, 0))


func prompt(player) -> String:
	if player.hud.note_open():
		return "[b]%s[/b]\n%s Put it down" % [FINDS[kind][0], Hud.key("E")]
	return "[b]%s[/b]\n%s Read" % [FINDS[kind][0], Hud.key("E")]


func interact(player) -> void:
	if player.hud.note_open():
		player.hud.hide_note()
		return
	var f: Array = FINDS[kind]
	player.hud.show_note(f[1], f[2])
	if player.inv.finds.has(kind):
		return
	player.inv.finds[kind] = true
	player.inv.complete_goal("find")
	if f[3] != "":
		get_tree().call_group("game", "mark_place", f[3], f[4])
		player.hud.toast("Marked on your map: %s, on %s." % [f[4], f[3]], Color(0.6, 1.0, 0.6), 6.0)
