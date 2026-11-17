extends RefCounted
## Fast travel between places you own: the cabin and your camp tents. It costs time (about an
## hour per 1.5 km) and takes your vehicle along if you are standing next to it.

const METERS_PER_HOUR := 1500.0
const BRING_VEHICLE := 25.0


## [name, position] of every place you can travel to, except where you are now.
static func destinations(main, here: Vector3) -> Array:
	var out := []
	var home: Vector3 = main.base.spawn_point
	if home.distance_to(here) > 40.0:
		out.append(["Grandpa's cabin", home])
	var n := 0
	for m in main.get_tree().get_nodes_in_group("machines"):
		if m.kind != "camp" or m.carried or m.loaded_on != null:
			continue
		n += 1
		if m.global_position.distance_to(here) > 40.0:
			out.append([m.camp_name(), m.arrival_point()])
	return out


static func hours_for(from: Vector3, to: Vector3) -> float:
	return maxf(0.5, snappedf(Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)) / METERS_PER_HOUR, 0.25))


## The menu lines: the first is the "stay" action, then one per destination.
static func menu(main, here: Vector3, first: String, sel: int) -> String:
	var items := [first]
	for d in destinations(main, here):
		items.append("Travel to %s  (%.1f km, %s)" % [d[0], Vector2(here.x, here.z).distance_to(Vector2(d[1].x, d[1].z)) / 1000.0,
			_hours_text(hours_for(here, d[1]))])
	var t := ""
	for i in items.size():
		t += "\n" + ("[color=#ffd866]> %s[/color]" % items[i] if i == sel else "   " + str(items[i]))
	return t


static func _hours_text(h: float) -> String:
	if h < 1.0:
		return "%d min" % roundi(h * 60.0)
	return ("%.1f hours" % h).replace(".0 ", " ")


static func count(main, here: Vector3) -> int:
	return 1 + destinations(main, here).size()


## Go to destination i (1-based in the menu). Returns false if there is nowhere to go.
static func go(main, player, sel: int) -> bool:
	var dests := destinations(main, player.global_position)
	if sel < 1 or sel > dests.size():
		return false
	var d: Array = dests[sel - 1]
	main.fast_travel(d[1], d[0])
	return true
