extends "res://scripts/machines/machine.gd"
## Lights for working at night, bought at the general store. No fuel or charging: E switches
## one on or off, F carries it like any other gear.
##   lantern  a kerosene lantern, a warm glow about 7 m around
##   flood    an LED work light on a tripod, about 25 m ahead; mouse wheel turns it
##   tower    a light tower: four lamps on a mast, about 50 m all round. Heavy to carry.

const SIZES := {
	"lantern": {"name": "Lantern", "range": 7.5, "energy": 1.6},
	"flood": {"name": "Work light", "range": 28.0, "energy": 16.0},
	"tower": {"name": "Light tower", "range": 60.0, "energy": 16.0},
}

var size := "lantern"
var on := true
var _lights: Array[Light3D] = []
var _glow: StandardMaterial3D
var _head: Node3D           # the part the work light's lamp turns on
var _aim := 0.0             # the work light's lamp, radians either side
var _t := 0.0


func _init() -> void:
	processes = false


## Call before adding to the tree.
func set_size(s: String) -> void:
	size = s
	kind = "light_" + s
	display_name = SIZES[s]["name"]


## Lights work anywhere, claim or not, wet or dry.
func problem() -> String:
	return ""


func water_problem() -> String:
	return ""


## How much slower the player walks carrying it.
func carry_factor() -> float:
	return 0.45 if size == "tower" else 1.0


func place_at(pos: Vector3, yaw: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	global_position = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	_on_moved()


func _build() -> void:
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.92, 0.75)
	_glow.emission_enabled = true
	match size:
		"lantern":
			_build_lantern()
		"flood":
			_build_flood()
		_:
			_build_tower()
	_apply_on()


func _build_lantern() -> void:
	var tin := Parts.paint("lantern", Color(0.55, 0.12, 0.08))
	var wire := Parts.steel()
	Parts.cyl(self, 0.075, 0.05, Vector3(0, 0.025, 0), tin)            # fount
	Parts.cyl(self, 0.05, 0.14, Vector3(0, 0.12, 0), _glow, Vector3.ZERO, -1.0, 12)   # globe
	Parts.cyl(self, 0.06, 0.03, Vector3(0, 0.205, 0), tin)             # cap
	for s: float in [-1.0, 1.0]:
		Parts.cyl(self, 0.004, 0.2, Vector3(s * 0.065, 0.12, 0), wire, Vector3.ZERO, -1.0, 4)
	Parts.cyl(self, 0.004, 0.13, Vector3(0, 0.26, 0), wire, Vector3(0, 0, PI / 2.0), -1.0, 4)  # bail
	var l := OmniLight3D.new()
	l.position = Vector3(0, 0.14, 0)
	l.omni_range = SIZES.lantern.range
	l.omni_attenuation = 1.2
	l.light_color = Color(1.0, 0.72, 0.42)
	_add_light(l)
	_glow.albedo_color = Color(1.0, 0.75, 0.45)
	Parts.collider(self, Vector3(0.18, 0.28, 0.18), Vector3(0, 0.14, 0))


func _build_flood() -> void:
	var leg := Parts.paint("work_light", Color(0.85, 0.65, 0.1))
	var black := Parts.mat("light_body", Color(0.08, 0.08, 0.08), 0.6, 0.3)
	for k in 3:
		var a := TAU * k / 3.0
		Parts.cyl(self, 0.012, 1.55, Vector3(cos(a) * 0.3, 0.72, sin(a) * 0.3), leg,
			Vector3(sin(a) * 0.38, 0, -cos(a) * 0.38), -1.0, 6)
	Parts.cyl(self, 0.016, 0.5, Vector3(0, 1.55, 0), leg, Vector3.ZERO, -1.0, 6)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.8, 0)
	add_child(_head)
	Parts.box(_head, Vector3(0.34, 0.24, 0.08), Vector3(0, 0, 0), black, Vector3(-0.35, 0, 0))
	Parts.box(_head, Vector3(0.29, 0.19, 0.01), Vector3(0, -0.015, 0.045), _glow, Vector3(-0.35, 0, 0))
	var l := SpotLight3D.new()
	l.position = Vector3(0, 0, 0.06)
	l.rotation = Vector3(0, PI, 0)      # spot lights shine down -Z; face it forward (+Z), tipped down
	l.rotate_object_local(Vector3.RIGHT, -0.35)
	l.spot_range = SIZES.flood.range
	l.spot_angle = 38.0
	l.spot_attenuation = 0.8
	l.light_color = Color(0.95, 0.97, 1.0)
	_head.add_child(l)
	_lights.append(l)
	_glow.albedo_color = Color(0.95, 0.97, 1.0)
	Parts.collider(self, Vector3(0.7, 1.9, 0.7), Vector3(0, 0.95, 0))


func _build_tower() -> void:
	var paint := Parts.paint("light_tower", Color(0.9, 0.62, 0.08))
	var black := Parts.mat("light_body", Color(0.08, 0.08, 0.08), 0.6, 0.3)
	# Trailer-mounted generator box on two wheels, with outriggers.
	Parts.box(self, Vector3(1.2, 0.8, 2.0), Vector3(0, 0.75, 0), paint)
	Parts.box(self, Vector3(1.22, 0.06, 2.02), Vector3(0, 1.17, 0), black)
	for s: float in [-1.0, 1.0]:
		Parts.cyl(self, 0.3, 0.18, Vector3(s * 0.7, 0.3, 0.2), Parts.mat("tire", Color(0.06, 0.06, 0.06), 0.9), Vector3(0, 0, PI / 2.0))
		Parts.box(self, Vector3(1.4, 0.08, 0.08), Vector3(s * 0.9, 0.12, -0.7), paint)
		Parts.box(self, Vector3(0.16, 0.24, 0.16), Vector3(s * 1.55, 0.12, -0.7), black)
	Parts.box(self, Vector3(0.08, 0.08, 1.0), Vector3(0, 0.45, 1.4), paint)   # tongue
	# Mast and lamp bar.
	Parts.box(self, Vector3(0.16, 6.5, 0.16), Vector3(0, 4.4, -0.6), Parts.galvanized())
	Parts.box(self, Vector3(1.5, 0.08, 0.1), Vector3(0, 7.6, -0.6), black)
	for i in 4:
		var x := -0.6 + 0.4 * i
		var lamp := Node3D.new()
		lamp.position = Vector3(x, 7.55, -0.55)
		lamp.rotation = Vector3(0.0, (i - 1.5) * 0.5 + PI, 0.0)
		add_child(lamp)
		Parts.box(lamp, Vector3(0.32, 0.36, 0.1), Vector3.ZERO, black, Vector3(0.6, 0, 0))
		Parts.box(lamp, Vector3(0.27, 0.3, 0.01), Vector3(0, -0.03, -0.055), _glow, Vector3(0.6, 0, 0))
	# One strong light for the whole site, high on the mast: four would cost four times as much.
	var l := OmniLight3D.new()
	l.position = Vector3(0, 7.3, -0.3)
	l.omni_range = SIZES.tower.range
	l.omni_attenuation = 0.5
	l.light_color = Color(1.0, 0.96, 0.88)
	_add_light(l)
	Parts.collider(self, Vector3(1.3, 1.2, 2.2), Vector3(0, 0.75, 0))
	Parts.collider(self, Vector3(0.3, 6.6, 0.3), Vector3(0, 4.4, -0.6))


func _add_light(l: Light3D) -> void:
	add_child(l)
	_lights.append(l)


func _apply_on() -> void:
	for l in _lights:
		l.visible = on
		l.shadow_enabled = false
		l.light_energy = SIZES[size].energy
	_glow.emission = _glow.albedo_color if on else Color.BLACK
	_glow.emission_energy_multiplier = 3.0 if on else 0.0


func _process(delta: float) -> void:
	# The lantern's flame flickers a little.
	if size == "lantern" and on and not _lights.is_empty():
		_t += delta
		_lights[0].light_energy = SIZES.lantern.energy * (0.92 + 0.05 * sin(_t * 9.0) + 0.03 * sin(_t * 23.0))


func prompt(player) -> String:
	if loaded_on != null:
		return "[b]%s[/b]\n%s Take it off the %s" % [display_name, Hud.key("F"), str(loaded_on.display_name).to_lower()]
	var t := "[b]%s[/b]   %s" % [display_name, "[color=#ffd866]on[/color]" if on else "[color=#a0a0a0]off[/color]"]
	t += "\n" + Hud.key("E") + (" Turn off" if on else " Turn on")
	if size == "flood":
		t += "     " + Hud.key("Wheel") + " Aim"
	t += "     " + Hud.key("F") + " Pick up"
	if size == "tower":
		t += "  (heavy: easier on the truck or trailer)"
	return t


func interact(_player) -> void:
	on = not on
	_apply_on()
	Sfx.play("click", global_position)


func scroll(_player, dir: int) -> void:
	if size == "flood":
		_aim = clampf(_aim + 0.2 * dir, -1.4, 1.4)
		_head.rotation.y = _aim


func to_dict() -> Dictionary:
	var d := super()
	d["on"] = on
	d["aim"] = _aim
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	on = d.get("on", true)
	_aim = d.get("aim", 0.0)
	if _head != null:
		_head.rotation.y = _aim
	_apply_on()
