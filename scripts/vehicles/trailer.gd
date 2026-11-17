extends "res://scripts/vehicles/vehicle.gd"
## Flatbed trailer for the pickup: room for two big machines. Back the pickup up to it, then E
## on the trailer hitches it (one action); E again unhitches it. While hitched it rolls freely
## and swings on the ball; parked, it holds still like the other vehicles.

const HITCH_REACH := 4.5
const TONGUE := Vector3(0, 0.62, -3.05)       # the coupler at the front of the tongue (local)
const BALL := Vector3(0, 0.62, 2.95)          # the ball on the pickup's rear bumper (pickup local)

var towed_by = null                           # the pickup, while hitched
var want_hitch := false                       # from a save: hitch again once the pickup exists
var _joint: PinJoint3D


func _init() -> void:
	kind = "trailer"
	display_name = "Trailer"
	mass = 700.0
	wheel_mounts = [Vector3(-0.85, 0.42, 0.15), Vector3(0.85, 0.42, 0.15), Vector3(-0.85, 0.42, 0.95), Vector3(0.85, 0.42, 0.95)]
	wheel_radius = 0.34
	wheel_width = 0.22
	rest = 0.25
	spring = 16000.0
	damper = 1800.0
	anti_roll = 6000.0
	engine_force = 2000.0      # only sets its air drag; it has no engine
	top_speed = 30.0
	brake_force = 6000.0
	com_y = 0.5
	var rot := Basis(Vector3.UP, -PI / 2.0)
	cargo_slots = [Transform3D(rot, Vector3(0, 0.82, -0.75)), Transform3D(rot, Vector3(0, 0.82, 1.2))]


func setup(t) -> void:
	super(t)
	for w in _wheels:
		w["steer"] = false


func _build() -> void:
	var steel := Parts.paint("trailer", Color(0.18, 0.18, 0.19))
	var deck := Parts.wood("trailer_deck", Color(0.45, 0.35, 0.24))
	Parts.box(self, Vector3(2.0, 0.1, 4.2), Vector3(0, 0.72, 0.1), deck)
	for x: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(0.08, 0.16, 4.2), Vector3(x, 0.66, 0.1), steel)
		Parts.box(self, Vector3(0.3, 0.06, 1.2), Vector3(x * 0.95, 0.9, 0.55), steel)          # fenders
	Parts.box(self, Vector3(2.0, 0.16, 0.08), Vector3(0, 0.66, -2.0), steel)
	Parts.box(self, Vector3(2.0, 0.4, 0.06), Vector3(0, 0.95, 2.2), steel)                     # tail board
	# A-frame tongue to the coupler.
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(0.08, 0.1, 1.35), Vector3(s * 0.38, 0.64, -2.55), steel, Vector3(0, s * 0.42, 0))
	Parts.box(self, Vector3(0.12, 0.1, 0.35), TONGUE + Vector3(0, 0, 0.15), steel)
	Parts.cyl(self, 0.06, 0.5, Vector3(0.25, 0.4, -2.6), steel)                                # jack stand
	var body := BoxShape3D.new()
	body.size = Vector3(2.0, 0.3, 4.2)
	var cs := CollisionShape3D.new()
	cs.shape = body
	cs.position = Vector3(0, 0.72, 0.1)
	add_child(cs)


func _physics_process(delta: float) -> void:
	if towed_by != null:
		# Follow the pickup: awake whenever it is, and settle when it does.
		freeze = towed_by.freeze
		_settle = 1.0
	elif want_hitch:
		var truck = _find_truck(1.0e9)
		if truck != null:
			hitch(truck)
	super(delta)


## Rolling freely while hitched; holding still when parked.
func _hold_still() -> bool:
	return towed_by == null


func _find_truck(reach: float):
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.kind == "truck" and (v.to_global(BALL)).distance_to(to_global(TONGUE)) < reach:
			return v
	return null


func hitch(truck) -> void:
	want_hitch = false
	# Snap the coupler onto the ball, lined up behind the pickup.
	var b: Basis = truck.global_basis
	global_transform = Transform3D(b, truck.to_global(BALL) - b * TONGUE)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	towed_by = truck
	_joint = PinJoint3D.new()
	truck.add_child(_joint)
	_joint.position = BALL
	_joint.node_a = truck.get_path()
	_joint.node_b = get_path()
	freeze = truck.freeze


func unhitch() -> void:
	if _joint != null:
		_joint.queue_free()
		_joint = null
	towed_by = null
	_settle = SETTLE_TIME


func prompt(player) -> String:
	var t := "[b]Trailer[/b]"
	var names := PackedStringArray()
	for c in cargo:
		if c != null:
			names.append(str(c.display_name).to_lower())
	if not names.is_empty():
		t += "   carrying: " + ", ".join(names)
	if towed_by != null:
		return t + "\n" + Hud.key("E") + " Unhitch from the pickup"
	if _find_truck(HITCH_REACH) != null:
		return t + "\n" + Hud.key("E") + " Hitch to the pickup"
	return t + "\nBack the pickup up to the tongue to hitch it.   Carry gear onto it (F) to load."


func interact(player) -> void:
	if towed_by != null:
		unhitch()
		player.hud.toast("Unhitched the trailer.")
		return
	var truck = _find_truck(HITCH_REACH)
	if truck == null:
		player.hud.toast("Back the pickup up so its bumper is near the trailer's tongue, then hitch it.")
		return
	hitch(truck)
	player.hud.toast("Hitched. It follows the pickup now.", Color(0.6, 1.0, 0.6))


func enter(_player) -> void:
	pass


func to_dict() -> Dictionary:
	var d := super()
	d["hitched"] = towed_by != null
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	want_hitch = d.get("hitched", false)
