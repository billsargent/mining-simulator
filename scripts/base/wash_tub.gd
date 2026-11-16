extends StaticBody3D
## Galvanized wash tub on a stand: pan your concentrate here (or a bucket of dirt).

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")


func build() -> void:
	var wood := Parts.wood()
	Parts.box(self, Vector3(0.95, 0.05, 0.75), Vector3(0, 0.62, 0), wood)
	for x: float in [-0.4, 0.4]:
		for z: float in [-0.3, 0.3]:
			Parts.box(self, Vector3(0.06, 0.62, 0.06), Vector3(x, 0.31, z), wood)
	Parts.cyl(self, 0.34, 0.3, Vector3(0, 0.8, 0), Parts.galvanized(), Vector3.ZERO, 0.4, 28, false)
	Parts.cyl(self, 0.33, 0.02, Vector3(0, 0.66, 0), Parts.galvanized(), Vector3.ZERO, -1.0, 28)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.32, 0.3, 0.24, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	Parts.cyl(self, 0.38, 0.005, Vector3(0, 0.89, 0), water, Vector3.ZERO, -1.0, 28)
	Parts.collider(self, Vector3(0.95, 0.95, 0.8), Vector3(0, 0.475, 0))


func prompt(player) -> String:
	var t := "[b]Wash tub[/b]"
	var jars: int = player.inv.cons.size()
	if jars > 0:
		t += "\n%s Pan a jar of concentrate  (%d jar%s)" % [Hud.key("E"), jars, "" if jars == 1 else "s"]
	elif not player.inv.bucket.is_empty():
		t += "\n%s Pan a shovelful" % Hud.key("E")
	else:
		t += "\nClean out your sluice, then pan the concentrate here."
	return t


func interact(player) -> void:
	if not player.inv.cons.is_empty():
		player.start_panning(player.inv.cons.pop_front(), "cons")
	elif not player.inv.bucket.is_empty():
		player.start_panning(player.inv.bucket.pop_front(), "bucket")
	else:
		player.hud.toast("Nothing to pan. Clean out your sluice's riffles to get concentrate.")
