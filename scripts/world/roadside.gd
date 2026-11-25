extends Node3D
## Things along the roads, laid out by world_gen._make_places(): signposts with distances, and
## old places a little way off the road. Most old places hide something to search; a few notes
## lead to stashes hidden up the hillsides, away from any road. Local axes: +Z faces the road.

const Parts = preload("res://scripts/machines/parts.gd")
const Cache = preload("res://scripts/world/cache.gd")

## Where signposts point.
var _dests: Array = []          # [name, Vector2]
var world
var terrain
var stashes: Array = []         # the caches hidden away from roads
var caches: Array = []          # every cache, roadside ones first (for tests)
var trail: Array = []           # the lost mine trail, in order (first note to the mine)

var _logs: StandardMaterial3D
var _rust: StandardMaterial3D
var _stone: StandardMaterial3D
var _plank: StandardMaterial3D


## Notes found at the old places. Each [title, text, what it leads to]: "stash" points to a
## hidden stash (its spot is filled in), a creek name marks that creek's richest ground.
const NOTES := [
	["A letter, never sent", "Dear Ma,\n\nThe claim is no good and I am coming home. Before I go I have put my poke where nobody will think to look: up the hill behind the old place on the road, under a pile of rocks. If I don't come back for it, it was never mine anyway.\n\nYour loving son, Will", "stash"],
	["Page torn from a ledger", "Paid out to the Swede for his share, 2 oz.\nOwed to the store, $14.\n\nNotation in the margin, in pencil: \"Swede says the gravel on Granite Creek runs heavy right down to the slate. He would know.\"", "Granite Creek"],
	["A note in a tobacco tin", "Cached my gold above the road where the big pines stand, three stones high. Coming back in the spring with a mule.\n\n- J.T.", "stash"],
	["Assay slip, 1897", "Sample No. 12, Ptarmigan Creek. Fine gold, rusty, very pure.\nValue per ton of gravel: excellent.\n\nScrawled on the back: \"Told nobody. Snow came early.\"", "Ptarmigan Creek"],
	["Child's letter", "Papa,\n\nMa says you are rich now. I hid the shiny rock you sent where you showed me, under the stones up the hill so the boys from town don't get it. When you come home we will look at it together.\n\nLove, Ruth", "stash"],
	["Water-stained diary page", "Worked the canyon creek all summer. Red Rock Creek pays where the walls close in and the water runs fast over the bars. Too far to haul supplies. Leaving it to the next fool.", "Red Rock Creek"],
]

## What each kind of place hides, in turn: [what, money, grams, nugget, garnet, note?]
const LOOT := [
	["coins", 0], ["dust", 0], ["note", 0], ["nugget", 0], ["coins", 0], ["note", 0],
	["garnet", 0], ["empty", 0], ["dust", 0], ["note", 0], ["coins", 0], ["note", 0],
]


func build(world_ref, terrain_ref) -> void:
	world = world_ref
	terrain = terrain_ref
	_logs = Parts.wood("old_logs", Color(0.33, 0.27, 0.22))
	_rust = Parts.mat("rust", Color(0.42, 0.24, 0.14), 0.9, 0.3)
	_stone = Parts.mat("stone", Color(0.42, 0.4, 0.38), 0.95)
	_plank = Parts.wood("old_planks", Color(0.4, 0.33, 0.26))
	_dests = [["Sable Crossing", world.sites["town"]["pos"]], ["Grandpa's cabin", world.sites["base"]["pos"]],
		["Last Chance Creek", world.sites["camp"]["pos"]], ["Tamarack Creek", world.river_point("Tamarack Creek", 0.6, 0.0)],
		["Rattlesnake Gulch", world.river_point("Rattlesnake Gulch", 0.5, 0.0)]]
	if world.sites.has("garnet"):
		_dests.append(["Garnet Beach", world.sites["garnet"]["pos"]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var loot_i := 0
	var note_i := 0
	for pl in world.places:
		var root := _anchor(pl)
		if pl["kind"] == "sign":
			_sign(root, pl["pos"])
			continue
		var c := Cache.new()
		c.id = pl["id"]
		match pl["kind"]:
			"ruin_cabin": _ruin_cabin(root, c)
			"wreck": _wreck(root, c)
			"graves": _graves(root, c)
			"ore_cart": _ore_cart(root, c)
			"wagon": _wagon(root, c)
			"old_sluice": _old_sluice(root, c)
			"chimney": _chimney(root, c)
			_: _prospect(root, c)
		var loot: String = LOOT[loot_i % LOOT.size()][0]
		loot_i += 1
		match loot:
			"coins": c.money = rng.randi_range(30, 160)
			"dust": c.grams = snappedf(rng.randf_range(0.4, 1.6), 0.01)
			"nugget": c.nugget = snappedf(rng.randf_range(0.5, 2.0), 0.1)
			"garnet": c.garnet = snappedf(rng.randf_range(1.5, 5.0), 0.05)
			"note":
				var nt: Array = NOTES[note_i % NOTES.size()]
				note_i += 1
				c.title = nt[0]
				c.text = nt[1]
				if nt[2] == "stash":
					var sp := _stash_spot(pl, rng)
					if sp != Vector2.ZERO:
						c.mark_where = "pos:%f,%f" % [sp.x, sp.y]
						c.mark_label = "Hidden stash?"
						_stash(sp, rng, stashes.size())
				else:
					c.mark_where = nt[2]
					c.mark_label = nt[0]
		caches.append(c)
	caches.append_array(stashes)
	_lost_mine_trail()


func _anchor(pl: Dictionary) -> Node3D:
	var p: Vector2 = pl["pos"]
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	n.rotation.y = pl["yaw"]
	return n


## Meshes far away are not drawn: these places are small.
func _fade(root: Node3D, reach: float = 350.0) -> void:
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = reach
		(g as GeometryInstance3D).visibility_range_end_margin = 30.0


func _body(root: Node3D) -> StaticBody3D:
	var b := StaticBody3D.new()
	root.add_child(b)
	return b


func _put_cache(root: Node3D, c, pos: Vector3, size: Vector3, what: String) -> void:
	c.what = what
	root.add_child(c)
	c.position = pos
	c.shape(size, Vector3(0, size.y * 0.5, 0))


# --- Signposts ---------------------------------------------------------------------------------

func _sign(root: Node3D, at: Vector2) -> void:
	var post := Parts.wood("sign_post", Color(0.45, 0.35, 0.25))
	var board := Parts.wood("sign_board", Color(0.62, 0.52, 0.38))
	Parts.cyl(root, 0.06, 2.6, Vector3(0, 1.3, 0), post, Vector3.ZERO, -1.0, 8)
	# The three nearest places (not the one you're standing at), nearest at the top.
	var ds := []
	for d in _dests:
		var dist := (d[1] as Vector2).distance_to(at)
		if dist > 250.0:
			ds.append([dist, d[0], d[1]])
	ds.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(3, ds.size()):
		var target: Vector2 = ds[i][2]
		var arm := Node3D.new()
		arm.position = Vector3(0, 2.25 - i * 0.38, 0)
		root.add_child(arm)
		# Point the board at the place: world bearing, less the post's own turn.
		var bearing := atan2(target.x - at.x, target.y - at.y)
		arm.rotation.y = bearing - PI / 2.0 - root.rotation.y
		Parts.box(arm, Vector3(1.5, 0.3, 0.05), Vector3(0.8, 0, 0), board)
		Parts.box(arm, Vector3(0.22, 0.22, 0.05), Vector3(1.55, 0, 0), board, Vector3(0, 0, PI / 4.0))
		for s: float in [1.0, -1.0]:
			var l := Parts.label(arm, "%s  %.1f km" % [ds[i][1], float(ds[i][0]) / 1000.0], Vector3(0.8, 0, 0.03 * s), 22)
			l.modulate = Color(0.2, 0.13, 0.06)
			l.outline_size = 0
			if s < 0.0:
				l.rotation.y = PI
	var b := _body(root)
	Parts.collider(b, Vector3(0.15, 2.6, 0.15), Vector3(0, 1.3, 0))
	_fade(root, 250.0)


# --- Old places -------------------------------------------------------------------------------

func _ruin_cabin(root: Node3D, c) -> void:
	var r := 0.14
	# Log walls fallen to different heights; a doorway toward the road.
	var heights := [7, 5, 3, 6]
	for i in 8:
		var y := r + i * r * 1.85
		if i < heights[0]:
			Parts.cyl(root, r, 5.2, Vector3(0, y, -2.2), _logs, Vector3(0, 0, PI / 2.0), -1.0, 8)
		if i < heights[1]:
			Parts.cyl(root, r, 4.6, Vector3(-2.5, y + r, 0.0), _logs, Vector3(PI / 2.0, 0, 0), -1.0, 8)
		if i < heights[2]:
			Parts.cyl(root, r, 4.6, Vector3(2.5, y + r, 0.0), _logs, Vector3(PI / 2.0, 0, 0), -1.0, 8)
		if i < heights[3]:
			for s: float in [-1.0, 1.0]:
				Parts.cyl(root, r, 1.7, Vector3(s * 1.65, y, 2.2), _logs, Vector3(0, 0, PI / 2.0), -1.0, 8)
	# Half the roof caved in, resting on the floor.
	Parts.box(root, Vector3(5.4, 0.08, 2.8), Vector3(0, 1.5, -1.0), Parts.wood("old_roof", Color(0.28, 0.25, 0.22)), Vector3(0.45, 0, 0))
	Parts.box(root, Vector3(3.0, 0.08, 2.6), Vector3(0.8, 0.5, 1.0), Parts.wood("old_roof", Color(0.28, 0.25, 0.22)), Vector3(-0.3, 0.2, 0.15))
	# Stone chimney at the back corner.
	for i in 9:
		Parts.box(root, Vector3(0.9 - i * 0.03, 0.32, 0.8), Vector3(-2.0, 0.16 + i * 0.32, -2.6), _stone, Vector3(0, i * 0.07, 0))
	var b := _body(root)
	Parts.collider(b, Vector3(5.2, 1.6, 0.3), Vector3(0, 0.8, -2.2))
	Parts.collider(b, Vector3(0.3, 1.2, 4.6), Vector3(-2.5, 0.6, 0))
	Parts.collider(b, Vector3(0.3, 0.8, 4.6), Vector3(2.5, 0.4, 0))
	# An old trunk in the corner.
	var trunk := Node3D.new()
	root.add_child(trunk)
	Parts.box(trunk, Vector3(0.8, 0.45, 0.5), Vector3(1.6, 0.225, -1.6), Parts.wood("trunk", Color(0.35, 0.22, 0.14)))
	Parts.box(trunk, Vector3(0.82, 0.06, 0.52), Vector3(1.6, 0.42, -1.6), _rust)
	_put_cache(root, c, Vector3(1.6, 0, -1.6), Vector3(0.8, 0.5, 0.5), "the old trunk")
	_ruin_inside(root, Vector3(-2.3, 0, -2.0), 4.6, 4.0)
	_fade(root)


## What's left inside an abandoned cabin: floorboards with gaps, a bunk frame, a table on its
## side, a chair and a rusted stove. `corner` is the inside back-left corner.
func _ruin_inside(root: Node3D, corner: Vector3, w: float, d: float) -> void:
	var boards := Parts.wood("old_floor", Color(0.36, 0.3, 0.24))
	var n := int(w / 0.3)
	for i in n:
		if i % 4 == 2:
			continue
		Parts.box(root, Vector3(0.26, 0.04, d - 0.3 * float(i % 3)), corner + Vector3(0.15 + i * 0.3, 0.03, d * 0.5), boards)
	var b := _body(root)
	var bunk := corner + Vector3(0.45, 0, d - 1.1)
	for p: Vector3 in [Vector3(-0.35, 0.25, -0.9), Vector3(0.35, 0.25, -0.9), Vector3(-0.35, 0.25, 0.9), Vector3(0.35, 0.25, 0.9)]:
		Parts.box(root, Vector3(0.08, 0.5, 0.08), bunk + p, _logs)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(0.06, 0.12, 1.9), bunk + Vector3(s * 0.35, 0.42, 0), _logs)
	Parts.box(root, Vector3(0.7, 0.04, 0.9), bunk + Vector3(0, 0.44, 0.45), _logs, Vector3(0.12, 0, 0))
	Parts.collider(b, Vector3(0.8, 0.5, 1.9), bunk + Vector3(0, 0.25, 0))
	var table := corner + Vector3(w * 0.55, 0, d * 0.55)
	Parts.box(root, Vector3(1.0, 0.7, 0.05), table + Vector3(0, 0.35, 0), _logs, Vector3(0, 0.4, 0))
	for k in 2:
		Parts.box(root, Vector3(0.05, 0.05, 0.6), table + Vector3(-0.3 + k * 0.6, 0.6, 0.3), _logs, Vector3(0, 0.4, 0))
	Parts.collider(b, Vector3(1.0, 0.7, 0.2), table + Vector3(0, 0.35, 0), Vector3(0, 0.4, 0))
	Parts.box(root, Vector3(0.4, 0.04, 0.4), table + Vector3(0.8, 0.45, 0.6), _logs, Vector3(0.2, 0.5, 0.1))
	var stove := corner + Vector3(1.2, 0, 0.45)
	Parts.box(root, Vector3(0.6, 0.5, 0.45), stove + Vector3(0, 0.3, 0), _rust)
	Parts.cyl(root, 0.06, 0.9, stove + Vector3(0.05, 0.95, -0.05), _rust, Vector3(0.25, 0, 0), -1.0, 8)
	Parts.collider(b, Vector3(0.6, 0.55, 0.45), stove + Vector3(0, 0.28, 0))


func _wreck(root: Node3D, c) -> void:
	# A rusted-out truck, sunk to its axles, no wheels.
	var paint := Parts.mat("wreck", Color(0.36, 0.3, 0.22), 0.9, 0.35)
	var glass := Parts.mat("dirty_glass", Color(0.25, 0.28, 0.25), 0.3)
	Parts.box(root, Vector3(1.8, 0.25, 4.6), Vector3(0, 0.25, 0), _rust, Vector3(0.03, 0.2, 0.04))
	var body := Node3D.new()
	body.rotation = Vector3(0.03, 0.2, 0.04)
	root.add_child(body)
	Parts.box(body, Vector3(1.7, 0.7, 1.6), Vector3(0, 0.75, 1.3), paint)          # hood
	Parts.box(body, Vector3(1.8, 1.1, 1.2), Vector3(0, 1.0, 0.0), paint)           # cab
	Parts.box(body, Vector3(1.5, 0.45, 0.04), Vector3(0, 1.3, 0.62), glass, Vector3(-0.2, 0, 0))
	Parts.box(body, Vector3(1.8, 0.5, 2.0), Vector3(0, 0.6, -1.6), _rust)          # bed
	for s: float in [-1.0, 1.0]:
		Parts.box(body, Vector3(0.35, 0.5, 0.9), Vector3(s * 0.85, 0.5, 1.3), _rust)  # fenders
	var b := _body(root)
	Parts.collider(b, Vector3(1.9, 1.5, 4.6), Vector3(0, 0.75, 0), Vector3(0, 0.2, 0))
	_put_cache(root, c, Vector3(1.2, 0, 0.6), Vector3(0.5, 1.2, 0.8), "the cab")
	_fade(root)


func _graves(root: Node3D, c) -> void:
	var white := Parts.wood("grave", Color(0.65, 0.62, 0.55))
	var names := ["D. AMES  1891", "UNKNOWN", "M. KELLY  1888"]
	for i in 3:
		var x := -1.6 + i * 1.6
		Parts.box(root, Vector3(0.1, 1.1, 0.08), Vector3(x, 0.55, -0.8), white, Vector3(0, 0, (i - 1) * 0.08))
		Parts.box(root, Vector3(0.6, 0.1, 0.08), Vector3(x, 0.85, -0.8), white, Vector3(0, 0, (i - 1) * 0.08))
		Parts.box(root, Vector3(0.7, 0.12, 1.6), Vector3(x, 0.06, 0.1), _stone)
		var l := Parts.label(root, names[i], Vector3(x, 0.62, -0.75), 14)
		l.modulate = Color(0.2, 0.18, 0.15)
		l.outline_size = 0
	# A picket fence, a few pickets missing.
	for k in 22:
		if k % 7 == 3:
			continue
		var t := k / 21.0
		var p: Vector3
		if t < 0.5:
			p = Vector3(-2.8 + t * 2.0 * 5.6, 0.45, -1.6)
		else:
			p = Vector3(-2.8 + (t - 0.5) * 2.0 * 5.6, 0.45, 1.6)
		Parts.box(root, Vector3(0.07, 0.9, 0.03), p, white, Vector3(0, 0, sin(k) * 0.1))
	_put_cache(root, c, Vector3(1.6, 0, -0.95), Vector3(0.6, 0.4, 0.4), "the jar by the marker")
	Parts.cyl(root, 0.08, 0.2, Vector3(1.6, 0.1, -0.95), Parts.mat("jar_glass", Color(0.35, 0.45, 0.4), 0.2), Vector3.ZERO, -1.0, 8)
	_fade(root)


func _ore_cart(root: Node3D, c) -> void:
	# A stub of track and an ore cart tipped off it.
	for s: float in [-0.3, 0.3]:
		Parts.box(root, Vector3(0.05, 0.06, 5.0), Vector3(s, 0.13, 0), _rust)
	for k in 8:
		Parts.box(root, Vector3(0.95, 0.08, 0.16), Vector3(0, 0.06, -2.2 + k * 0.62), _logs)
	var cart := Node3D.new()
	cart.position = Vector3(1.0, 0.35, 0.8)
	cart.rotation = Vector3(0.1, 0.4, 0.5)
	root.add_child(cart)
	Parts.box(cart, Vector3(0.8, 0.55, 1.1), Vector3.ZERO, _rust)
	for s: float in [-1.0, 1.0]:
		Parts.cyl(cart, 0.14, 0.06, Vector3(s * 0.42, -0.3, 0.35), _rust, Vector3(0, 0, PI / 2.0))
		Parts.cyl(cart, 0.14, 0.06, Vector3(s * 0.42, -0.3, -0.35), _rust, Vector3(0, 0, PI / 2.0))
	var b := _body(root)
	Parts.collider(b, Vector3(1.0, 0.8, 1.2), Vector3(1.0, 0.4, 0.8), Vector3(0, 0.4, 0))
	_put_cache(root, c, Vector3(1.0, 0, 0.8), Vector3(0.9, 0.8, 1.2), "under the ore cart")
	_fade(root)


func _wagon(root: Node3D, c) -> void:
	var tilt := Node3D.new()
	tilt.rotation = Vector3(0, 0, 0.18)
	root.add_child(tilt)
	Parts.box(tilt, Vector3(1.4, 0.08, 3.2), Vector3(0, 0.75, 0), _plank)
	for s: float in [-1.0, 1.0]:
		Parts.box(tilt, Vector3(0.05, 0.4, 3.2), Vector3(s * 0.7, 0.95, 0), _plank)
	Parts.box(tilt, Vector3(0.08, 0.08, 2.0), Vector3(0, 0.55, 2.4), _logs, Vector3(-0.25, 0, 0))   # tongue
	# One wheel still on, one fallen flat beside it.
	Parts.cyl(tilt, 0.55, 0.08, Vector3(0.78, 0.55, -1.0), _logs, Vector3(0, 0, PI / 2.0), -1.0, 16)
	Parts.cyl(tilt, 0.55, 0.08, Vector3(0.78, 0.55, 1.0), _logs, Vector3(0, 0, PI / 2.0), -1.0, 16)
	Parts.cyl(root, 0.55, 0.08, Vector3(-1.6, 0.04, 0.6), _logs, Vector3.ZERO, -1.0, 16)
	var b := _body(root)
	Parts.collider(b, Vector3(1.5, 1.1, 3.3), Vector3(0, 0.6, 0))
	Parts.box(root, Vector3(0.5, 0.35, 0.4), Vector3(0.1, 0.97, -0.9), Parts.wood("crate", Color(0.5, 0.38, 0.25)), Vector3(0, 0.3, 0.18))
	_put_cache(root, c, Vector3(0.1, 0.8, -0.9), Vector3(0.5, 0.4, 0.4), "the crate in the wagon")
	_fade(root)


func _old_sluice(root: Node3D, c) -> void:
	# A long wooden sluice on trestles, broken in the middle.
	for half in [[-2.2, 0.12], [1.9, -0.25]]:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0.7, half[0])
		seg.rotation = Vector3(0.06, 0, half[1])
		root.add_child(seg)
		Parts.box(seg, Vector3(0.5, 0.04, 3.6), Vector3.ZERO, _plank)
		for s: float in [-1.0, 1.0]:
			Parts.box(seg, Vector3(0.04, 0.3, 3.6), Vector3(s * 0.25, 0.15, 0), _plank)
		for k in 8:
			Parts.box(seg, Vector3(0.46, 0.04, 0.04), Vector3(0, 0.04, -1.6 + k * 0.45), _rust)
		for s: float in [-1.0, 1.0]:
			Parts.box(seg, Vector3(0.06, 0.7, 0.06), Vector3(s * 0.3, -0.35, 1.2), _logs)
	var b := _body(root)
	Parts.collider(b, Vector3(0.6, 1.0, 8.0), Vector3(0, 0.5, 0))
	_put_cache(root, c, Vector3(0, 0.6, -2.2), Vector3(0.6, 0.4, 3.0), "the old riffles")
	_fade(root)


func _chimney(root: Node3D, c) -> void:
	# All that's left of a house: the stone chimney and the line of the foundation.
	for i in 14:
		Parts.box(root, Vector3(1.1 - i * 0.03, 0.36, 0.9), Vector3(0, 0.18 + i * 0.36, -2.0), _stone, Vector3(0, i * 0.05, 0))
	for k in 18:
		var t := k / 18.0
		var a := t * TAU
		Parts.box(root, Vector3(0.5, 0.25, 0.4), Vector3(cos(a) * 3.0, 0.1, sin(a) * 2.0 + 0.2), _stone, Vector3(0, a, 0))
	var b := _body(root)
	Parts.collider(b, Vector3(1.1, 5.0, 0.9), Vector3(0, 2.5, -2.0))
	_put_cache(root, c, Vector3(0, 0.5, -1.5), Vector3(0.6, 0.5, 0.2), "the loose stone in the hearth")
	_fade(root)


func _prospect(root: Node3D, c) -> void:
	# An old prospect hole: a mound of dug dirt, a claim post, tools left leaning.
	var dirt := Parts.mat("dirt_mound", Color(0.45, 0.36, 0.26), 0.95)
	var mound := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.6
	sp.height = 1.0
	mound.mesh = sp
	mound.material_override = dirt
	mound.position = Vector3(1.2, 0.0, -0.8)
	mound.scale = Vector3(1.0, 1.0, 0.7)
	root.add_child(mound)
	Parts.box(root, Vector3(0.12, 1.3, 0.12), Vector3(-1.0, 0.65, 0.8), _logs)
	var l := Parts.label(root, "CLAIM\nJ.T.  1898", Vector3(-1.0, 1.05, 0.87), 16)
	l.modulate = Color(0.2, 0.15, 0.1)
	l.outline_size = 0
	Parts.cyl(root, 0.02, 1.0, Vector3(-0.7, 0.45, 0.6), _logs, Vector3(0.2, 0, 0.3), -1.0, 6)
	Parts.box(root, Vector3(0.18, 0.03, 0.24), Vector3(-0.56, 0.06, 0.66), _rust, Vector3(0.1, 0, 0.3))
	Parts.cyl(root, 0.06, 0.12, Vector3(-1.0, 0.06, 1.1), _rust, Vector3.ZERO, -1.0, 8)  # a tin can
	_put_cache(root, c, Vector3(-1.0, 0, 1.1), Vector3(0.3, 0.3, 0.3), "the old tin can")
	_fade(root)


# --- Hidden stashes ---------------------------------------------------------------------------

## A spot up the hill behind a place, away from the road and the water.
func _stash_spot(pl: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var p: Vector2 = pl["pos"]
	var away: Vector2 = (p - (pl["road"] as Vector2)).normalized()
	for attempt in 12:
		var dir := away.rotated(rng.randf_range(-0.7, 0.7))
		var q := p + dir * rng.randf_range(70.0, 140.0)
		if q.x < 30.0 or q.y < 30.0 or q.x > world.SIZE - 30.0 or q.y > world.SIZE - 30.0:
			continue
		if world.river_info(q.x, q.y).x > 10.0 and world.road_weight(q.x, q.y) < 0.01 and not world.in_pad(q.x, q.y, 10.0):
			return q
	return Vector2.ZERO


## A cairn of stones with something under it.
func _stash(p: Vector2, rng: RandomNumberGenerator, k: int) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	for i in 7:
		var a := i * 2.1
		var y := 0.14 + (0.0 if i < 4 else 0.24) + (0.24 if i == 6 else 0.0)
		var rr := 0.0 if i == 6 else (0.32 if i < 4 else 0.16)
		Parts.box(root, Vector3(0.4, 0.26, 0.34), Vector3(cos(a) * rr, y, sin(a) * rr), _stone, Vector3(0.1 * i, a, 0.05 * i))
	var c := Cache.new()
	c.id = "stash_%d" % k
	match k % 3:
		0:
			c.nugget = snappedf(rng.randf_range(4.0, 8.0), 0.1)
		1:
			c.money = rng.randi_range(400, 700)
		_:
			c.grams = snappedf(rng.randf_range(5.0, 9.0), 0.1)
	_put_cache(root, c, Vector3.ZERO, Vector3(0.9, 0.7, 0.9), "under the cairn")
	stashes.append(c)
	_fade(root, 200.0)


# --- The lost mine trail ----------------------------------------------------------------------

## One chain of clues left by an old prospector, Silas Crane: a note at a roadside place, then a
## cairn, a blazed pine, his claim post, and last the fallen-in mouth of his mine with his gold.
## Each clue marks the next spot on the map, a little off (he wrote it from memory). A clue means
## nothing until the one before it is found. Fixed by the seed; progress is the ids in inv.finds.
const TRAIL := [
	["Oilskin packet, nailed up", "To whoever finds this,\n\nI am Silas Crane. I struck it rich in these hills in '99, then lost the way back after the fever took me. My eyes are going, so I have set the way down as best I recall it.\n\nFirst: a pile of stones I raised on open ground, a good walk from here. Start there.\n\n- S. Crane", "the tin box nailed to the stake"],
	["Note under the stones", "From the stones, go on till you find a big pine I marked with an axe, chest high. Further than you'd like.\n\n- S.C.", "under the cairn"],
	["Cut into the blaze", "Letters cut into the wood under the old blaze:\n\nCLAIM POST - ON - S.C.\n\nAn arrow, and below it the rough sketch of a hill.", "the blaze on the old pine"],
	["Tin nailed to the claim post", "NOTICE. I, Silas Crane, claim fifteen hundred feet along this lead.\n\nOn the back, in shaky pencil: \"The adit is in the hill past here. I timbered the mouth and left my poke inside. Whoever reads this, it's yours. I am not going back.\"", "the claim post"],
	["", "", "the rotted strongbox"],
]


func _lost_mine_trail() -> void:
	var home: Vector2 = world.sites["base"]["pos"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(home.x * 31.0 + home.y * 17.0) + 9090
	# It starts at the old place nearest the cabin (but not right next door).
	var start = null
	var best := INF
	for pl in world.places:
		var d := (pl["pos"] as Vector2).distance_to(home)
		if pl["kind"] != "sign" and d > 300.0 and d < best:
			best = d
			start = pl
	if start == null:
		return
	var spots: Array = [start["pos"] as Vector2]
	for i in TRAIL.size() - 1:
		var q := _trail_spot(spots[spots.size() - 1], rng, spots)
		if q == Vector2.ZERO:
			return
		spots.append(q)
	for i in TRAIL.size():
		var root: Node3D
		if i == 0:
			root = _anchor(start)
		else:
			root = Node3D.new()
			add_child(root)
			var p: Vector2 = spots[i]
			root.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
			root.rotation.y = rng.randf_range(0.0, TAU)
		var c := Cache.new()
		c.id = "trail_%d" % i
		c.title = TRAIL[i][0]
		c.text = TRAIL[i][1]
		if i > 0:
			c.needs = "trail_%d" % (i - 1)
			c.locked_hint = "Someone made this long ago. It means nothing to you yet."
		if i < TRAIL.size() - 1:
			# A vague mark: within 15 to 35 m of the real spot.
			var m: Vector2 = spots[i + 1] + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(15.0, 35.0)
			c.mark_where = "pos:%f,%f" % [m.x, m.y]
			c.mark_label = "Crane's lost mine?" if i == TRAIL.size() - 2 else "Crane's trail %d?" % (i + 1)
		match i:
			0: _trail_box(root, c)
			1: _trail_cairn(root, c)
			2: _trail_tree(root, c)
			3: _trail_post(root, c)
			_:
				c.grams = snappedf(rng.randf_range(18.0, 26.0), 0.1)
				c.nugget = snappedf(rng.randf_range(12.0, 20.0), 0.1)
				c.money = rng.randi_range(150, 300)
				c.locked_hint = "An old timbered hole in the hill, fallen in."
				_trail_adit(root, c)
		trail.append(c)


## Open, fairly level ground 1.1 to 1.7 km on from `from`: away from water, roads, pads, the
## sites and the trail's other spots.
func _trail_spot(from: Vector2, rng: RandomNumberGenerator, taken: Array) -> Vector2:
	for attempt in 80:
		var q := from + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(1100.0, 1700.0)
		if q.x < 200.0 or q.y < 200.0 or q.x > world.SIZE - 200.0 or q.y > world.SIZE - 200.0:
			continue
		if world.river_info(q.x, q.y).x < 25.0 or world.road_weight(q.x, q.y) > 0.01 or world.in_pad(q.x, q.y, 20.0):
			continue
		var ok := true
		for s in ["base", "town", "camp", "mine"]:
			if world.sites.has(s) and (world.sites[s]["pos"] as Vector2).distance_to(q) < 300.0:
				ok = false
		for t: Vector2 in taken:
			if t.distance_to(q) < 800.0:
				ok = false
		if not ok:
			continue
		var h: float = world.surface(q.x, q.y, false)
		for d: Vector2 in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			if absf(world.surface(q.x + d.x, q.y + d.y, false) - h) > 2.5:
				ok = false
		if ok:
			return q
	return Vector2.ZERO


func _trail_box(root: Node3D, c) -> void:
	# A stake by the road with a tin box nailed to it.
	Parts.box(root, Vector3(0.1, 1.2, 0.1), Vector3(-3.2, 0.6, 3.4), _logs)
	Parts.box(root, Vector3(0.22, 0.16, 0.1), Vector3(-3.2, 1.0, 3.48), _rust)
	_put_cache(root, c, Vector3(-3.2, 0, 3.4), Vector3(0.4, 1.2, 0.4), TRAIL[0][2])
	_fade(root)


func _trail_cairn(root: Node3D, c) -> void:
	for i in 9:
		var a := i * 2.3
		var y := 0.14 + 0.24 * floorf(i / 4.0)
		var rr := 0.0 if i == 8 else (0.36 if i < 4 else 0.2)
		Parts.box(root, Vector3(0.42, 0.26, 0.36), Vector3(cos(a) * rr, y, sin(a) * rr), _stone, Vector3(0.1 * i, a, 0.05 * i))
	_put_cache(root, c, Vector3.ZERO, Vector3(1.0, 0.9, 1.0), TRAIL[1][2])
	_fade(root, 250.0)


func _trail_tree(root: Node3D, c) -> void:
	# A big dead pine with an axe blaze.
	var bark := Parts.wood("old_logs", Color(0.3, 0.24, 0.19))
	Parts.cyl(root, 0.45, 14.0, Vector3(0, 7.0, 0), bark, Vector3.ZERO, 0.18, 10)
	Parts.box(root, Vector3(0.36, 0.6, 0.1), Vector3(0, 1.4, 0.42), Parts.wood("blaze", Color(0.72, 0.6, 0.42)))
	var b := _body(root)
	Parts.collider(b, Vector3(0.8, 14.0, 0.8), Vector3(0, 7.0, 0))
	_put_cache(root, c, Vector3(0, 1.0, 0.45), Vector3(0.5, 0.9, 0.2), TRAIL[2][2])
	_fade(root, 500.0)


func _trail_post(root: Node3D, c) -> void:
	Parts.box(root, Vector3(0.16, 1.4, 0.16), Vector3(0, 0.7, 0), _logs)
	Parts.box(root, Vector3(0.22, 0.28, 0.02), Vector3(0, 1.05, 0.09), _rust)
	var l := Parts.label(root, "S.C.\n1899", Vector3(0, 1.05, 0.11), 14)
	l.modulate = Color(0.2, 0.15, 0.1)
	l.outline_size = 0
	_put_cache(root, c, Vector3.ZERO, Vector3(0.4, 1.4, 0.4), TRAIL[3][2])
	_fade(root, 250.0)


func _trail_adit(root: Node3D, c) -> void:
	# The fallen-in mouth of a small mine: two timber legs and a cap against a heap of rock.
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(0.22, 1.9, 0.22), Vector3(s * 0.8, 0.95, 0), _logs, Vector3(0, 0, s * 0.06))
	Parts.box(root, Vector3(2.1, 0.24, 0.26), Vector3(0, 1.95, 0), _logs, Vector3(0, 0, 0.08))
	var heap := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 2.2
	sp.height = 2.6
	heap.mesh = sp
	heap.material_override = _stone
	heap.position = Vector3(0, 0.2, -1.6)
	root.add_child(heap)
	var b := _body(root)
	Parts.collider(b, Vector3(3.6, 2.2, 2.6), Vector3(0, 1.1, -1.7))
	Parts.box(root, Vector3(0.6, 0.35, 0.4), Vector3(0.2, 0.18, 0.3), Parts.wood("trunk", Color(0.3, 0.2, 0.13)), Vector3(0, 0.3, 0))
	_put_cache(root, c, Vector3(0.2, 0, 0.3), Vector3(0.7, 0.5, 0.5), TRAIL[4][2])
	_fade(root, 300.0)
