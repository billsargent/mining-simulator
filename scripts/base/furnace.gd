extends StaticBody3D
## Propane furnace and pouring table. E melts the gold from your vial, E pours it, E takes the bar.
## Nuggets are kept aside: collectors pay more for them than they're worth melted down.
const Sfx = preload("res://scripts/core/sfx.gd")

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

enum { IDLE, HEATING, MOLTEN, POURING, COOLING, READY }

const HEAT_TIME := 6.0
const POUR_TIME := 1.6
const COOL_TIME := 3.0
const MELT_LOSS := 0.015     # a little is lost to the crucible and flux
const PURITY := 0.86         # this creek's gold is about 86% gold; the rest is mostly silver
const MOLTEN_COLOR := Color(1.0, 0.45, 0.1)

var state := IDLE
var _t := 0.0
var _batch := 0.0
var _bar_grams := 0.0
var _glow: MeshInstance3D
var _light: OmniLight3D
var _crucible: Node3D
var _stream: MeshInstance3D
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D


func build() -> void:
	var steel := Parts.steel()
	var wood := Parts.wood()
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.18, 0.18]:
			Parts.box(self, Vector3(0.04, 0.6, 0.04), Vector3(x, 0.3, z), steel)
	Parts.cyl(self, 0.24, 0.45, Vector3(0, 0.82, 0), Parts.mat("furnace", Color(0.16, 0.16, 0.17), 0.7, 0.4), Vector3.ZERO, -1.0, 20)
	Parts.cyl(self, 0.25, 0.04, Vector3(0, 1.06, 0), steel, Vector3.ZERO, -1.0, 20)
	Parts.cyl(self, 0.15, 0.48, Vector3(0.6, 0.24, 0), Parts.paint("tank", Color(0.85, 0.85, 0.82)), Vector3.ZERO, -1.0, 14)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = MOLTEN_COLOR
	glow_mat.emission_enabled = true
	glow_mat.emission = MOLTEN_COLOR
	glow_mat.emission_energy_multiplier = 3.0
	_glow = Parts.cyl(self, 0.12, 0.01, Vector3(0, 1.085, 0), glow_mat, Vector3.ZERO, -1.0, 16)
	_glow.visible = false
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.4, 0)
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 0.0
	_light.omni_range = 3.0
	add_child(_light)
	# Pouring table with a bar mold.
	Parts.box(self, Vector3(1.0, 0.05, 0.6), Vector3(0, 0.8, 1.1), wood)
	for x: float in [-0.45, 0.45]:
		for z: float in [0.85, 1.35]:
			Parts.box(self, Vector3(0.05, 0.8, 0.05), Vector3(x, 0.4, z), wood)
	Parts.box(self, Vector3(0.18, 0.05, 0.11), Vector3(0, 0.85, 1.1), steel)
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.metallic = 0.8
	_bar_mat.roughness = 0.25
	_bar_mat.emission_enabled = true
	_bar = Parts.box(self, Vector3(0.12, 0.022, 0.06), Vector3(0, 0.884, 1.1), _bar_mat)
	_bar.visible = false
	_crucible = Node3D.new()
	_crucible.position = Vector3(0.1, 1.02, 1.1)
	add_child(_crucible)
	Parts.cyl(_crucible, 0.045, 0.09, Vector3.ZERO, Parts.mat("graphite", Color(0.2, 0.2, 0.22), 0.8), Vector3.ZERO, 0.055, 12)
	_crucible.visible = false
	_stream = Parts.cyl(self, 0.006, 0.13, Vector3(0.04, 0.95, 1.1), glow_mat, Vector3.ZERO, -1.0, 6)
	_stream.visible = false
	Parts.label(self, "FURNACE", Vector3(0, 1.25, 0.26), 32)
	Parts.collider(self, Vector3(0.6, 1.15, 0.6), Vector3(0, 0.575, 0))
	Parts.collider(self, Vector3(1.0, 0.85, 0.6), Vector3(0, 0.425, 1.1))


func is_molten() -> bool:
	return state == MOLTEN


func is_ready() -> bool:
	return state == READY


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	match state:
		HEATING:
			_t += delta
			if _t >= HEAT_TIME:
				state = MOLTEN
		POURING:
			_t += delta
			_crucible.rotation.z = lerpf(0.0, 1.9, clampf(_t / 0.5, 0.0, 1.0))
			_stream.visible = _t > 0.4 and _t < POUR_TIME - 0.2
			_bar.visible = _t > 0.6
			_set_bar_heat(1.0)
			if _t >= POUR_TIME:
				state = COOLING
				_t = 0.0
				_crucible.visible = false
				_stream.visible = false
		COOLING:
			_t += delta
			_set_bar_heat(1.0 - clampf(_t / COOL_TIME, 0.0, 1.0))
			if _t >= COOL_TIME:
				state = READY
	var hot := state == HEATING or state == MOLTEN or state == POURING
	_glow.visible = hot
	var target := 0.0
	if hot:
		target = 1.6 + 0.3 * sin(Time.get_ticks_msec() * 0.02)
	_light.light_energy = target


func _set_bar_heat(heat: float) -> void:
	var gold := Color(1.0, 0.8, 0.3)
	_bar_mat.albedo_color = gold.lerp(MOLTEN_COLOR, heat)
	_bar_mat.emission = gold.lerp(MOLTEN_COLOR, heat)
	_bar_mat.emission_energy_multiplier = 0.4 + 3.0 * heat


func prompt(player) -> String:
	var t := "[b]Furnace[/b]"
	match state:
		IDLE:
			var g: float = player.inv.vial_grams()
			if g > 0.0:
				t += "\n%s Melt %.3f g of gold into a bar" % [Hud.key("E"), g]
			else:
				t += "\nPan your concentrate first, then bring the gold here."
			if not player.inv.nuggets.is_empty():
				t += "\n(Nuggets stay aside: collectors pay more for them.)"
		HEATING:
			t += "\nMelting... %d%%" % roundi(100.0 * _t / HEAT_TIME)
		MOLTEN:
			t += "\n%s Pour it into the mold" % Hud.key("E")
		POURING, COOLING:
			t += "\nCooling..."
		READY:
			t += "\n%s Take the bar  (%.2f g)" % [Hud.key("E"), _bar_grams]
	return t


func interact(player) -> void:
	match state:
		IDLE:
			if player.inv.vial_grams() <= 0.0:
				player.hud.toast("No loose gold to melt yet. Pan your concentrate first.")
				return
			_batch = player.inv.take_vial()
			state = HEATING
			_t = 0.0
			Sfx.play("roar", global_position)
			player.hud.toast("Fired up the furnace: %.3f g of gold and a pinch of borax in the crucible." % _batch)
		MOLTEN:
			state = POURING
			_t = 0.0
			_bar_grams = _batch * (1.0 - MELT_LOSS)
			var s := clampf(pow(_bar_grams / 3.0, 1.0 / 3.0), 0.5, 2.0)
			_bar.scale = Vector3(s, s, s)
			_crucible.visible = true
			_crucible.rotation.z = 0.0
		READY:
			player.inv.bars.append({"grams": _bar_grams, "purity": PURITY})
			Sfx.play("clink", global_position, 0.0, 0.7)
			player.inv.complete_goal("smelted")
			player.hud.toast("A %.2f g bar, about %d%% pure. Ship it in the gold buyer's box." % [_bar_grams, roundi(PURITY * 100.0)], Color(1.0, 0.85, 0.4), 5.0)
			_bar.visible = false
			_batch = 0.0
			state = IDLE
		_:
			pass


func to_dict() -> Dictionary:
	return {"state": state, "t": _t, "batch": _batch, "bar_grams": _bar_grams}


func from_dict(d: Dictionary) -> void:
	_batch = d.get("batch", 0.0)
	_bar_grams = d.get("bar_grams", 0.0)
	var s: int = d.get("state", IDLE)
	# Anything mid-pour picks up where it's safe: molten stays molten, a poured bar is ready.
	if s == HEATING or s == MOLTEN:
		state = HEATING
		_t = d.get("t", 0.0) if s == HEATING else HEAT_TIME
	elif s == POURING or s == COOLING or s == READY:
		state = READY
		_bar.visible = true
		_set_bar_heat(0.0)
	else:
		state = IDLE
