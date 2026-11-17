extends Node3D
## What makes the old mine dangerous, all of it warned about before it can hurt you and none of
## it deadly: headlamp batteries that run down, bad air at the far end of the lower drift, and
## a stretch of rotten ground that caves in if you keep chipping under it.
## The whole lot can be switched off in the Esc menu (Settings.hazards).
## Positions are in the mine's local space.

const Parts = preload("res://scripts/machines/parts.gd")
const Settings = preload("res://scripts/core/settings.gd")

const LAMP_SECONDS := 720.0                     # a full battery lasts 12 minutes underground
const LAMP_LOW := 0.2
const AIR_SECONDS := 28.0                       # how long you last in bad air
const AIR_RECOVER := 6.0
const AIR_EDGE_X := 50.0                        # bad air lies west of this on the lower level
const AIR_WARN_X := 55.0
const AIR_TOP_Y := 5.5
const ROT_CENTER := Vector3(44.0, 9.2, 47.9)    # where the south drift crosses the vein
const ROT_RADIUS := 3.2
const ROT_WARN := 6.5
const ROT_BLOWS := 3
const ROT_SAFE := Vector3(37.4, 8.2, 44.0)      # where you end up when the roof comes down

var mine
var collapsed := false

var _stress := 0
var _stress_wait := 0.0
var _rot_warned := false
var _air_warned := false
var _lamp_warned := false
var _rot_props: Node3D


func setup(m, was_collapsed: bool) -> void:
	mine = m
	collapsed = was_collapsed
	var timber := Parts.wood("old_timber", Color(0.36, 0.28, 0.2))
	var board := Parts.wood("sign", Color(0.62, 0.52, 0.38))
	# Warning boards the old crew left.
	_sign("UNSAFE\nGROUND", Vector3(39.0, 8.0, 47.45), -PI / 2.0, board, timber)
	_sign("BAD AIR", Vector3(55.5, 1.5, 16.2), PI / 2.0, board, timber)
	if not collapsed:
		# Rotten timber sets: split, leaning, one already down.
		_rot_props = Node3D.new()
		add_child(_rot_props)
		var along := Vector3(15.0, 0.0, 4.0).normalized()
		var side := Vector3(-along.z, 0.0, along.x)
		var yaw := atan2(-along.z, along.x)
		for k in 4:
			var c := Vector3(41.0, 8.0, 47.07) + along * (k * 1.9)
			var lean := 0.12 + 0.06 * k
			Parts.box(_rot_props, Vector3(0.2, 2.2, 0.2), c + side * 0.9 + Vector3(0, 1.1, 0), timber, Vector3(lean, yaw, 0.0))
			Parts.box(_rot_props, Vector3(0.2, 2.2, 0.2), c - side * 0.9 + Vector3(0, 1.1, 0), timber, Vector3(-lean * 0.6, yaw, 0.05))
			Parts.box(_rot_props, Vector3(0.22, 0.2, 2.1), c + Vector3(0, 2.1 - 0.12 * k, 0), timber, Vector3(0.0, yaw, 0.1 + 0.07 * k))
		Parts.box(_rot_props, Vector3(0.2, 0.2, 2.0), Vector3(46.5, 8.15, 48.3), timber, Vector3(0.0, 0.5, 0.0))


## A board on a post, standing on the floor at pos and facing yaw.
func _sign(text: String, pos: Vector3, yaw: float, board: Material, timber: Material) -> void:
	var s := Node3D.new()
	s.position = pos
	s.rotation.y = yaw
	add_child(s)
	Parts.box(s, Vector3(0.09, 1.6, 0.09), Vector3(0, 0.8, 0), timber)
	Parts.box(s, Vector3(0.85, 0.48, 0.04), Vector3(0, 1.4, 0.06), board, Vector3(0, 0, 0.04))
	Parts.label(s, text, Vector3(0, 1.4, 0.09), 26)


func _process(delta: float) -> void:
	var main = get_tree().get_first_node_in_group("game")
	if main == null or main.player == null or main.player.mine != mine:
		return
	var player = main.player
	if not Settings.hazards:
		player.lamp_charge = 1.0
		player.air = 1.0
		player.apply_lamp()
		main.hud.set_shade(0.0)
		return
	var p: Vector3 = mine.to_local(player.global_position)
	_lamp(player, main.hud, delta)
	_air(player, main, p, delta)
	_rot(main.hud, p, delta)


func _lamp(player, hud, delta: float) -> void:
	if player.headlamp_on():
		player.lamp_charge = maxf(0.0, player.lamp_charge - delta / LAMP_SECONDS)
	if player.lamp_charge < LAMP_LOW and not _lamp_warned:
		_lamp_warned = true
		hud.toast("Your headlamp is getting dim. Fresh batteries are with your gear outside.", Color(1.0, 0.75, 0.4), 6.0)
	elif player.lamp_charge > 0.5:
		_lamp_warned = false
	player.apply_lamp()


func _air(player, main, p: Vector3, delta: float) -> void:
	var low: bool = p.y < AIR_TOP_Y
	if low and p.x < AIR_WARN_X and not _air_warned:
		_air_warned = true
		main.hud.toast("Your gas detector starts to chirp. Bad air ahead: go in, but don't stay long.", Color(1.0, 0.75, 0.4), 6.0)
	elif not low or p.x > AIR_WARN_X + 4.0:
		_air_warned = false
	if low and p.x < AIR_EDGE_X:
		player.air = maxf(0.0, player.air - delta / AIR_SECONDS)
	else:
		player.air = minf(1.0, player.air + delta / AIR_RECOVER)
	main.hud.set_shade(pow(1.0 - player.air, 1.6) * 0.92)
	if player.air <= 0.0:
		player.air = 1.0
		main.rescue_from_mine("You come to at the mouth of the adit with a pounding head. The bad air nearly had you.")


func _rot(hud, p: Vector3, delta: float) -> void:
	_stress_wait -= delta
	if collapsed:
		return
	var d := Vector2(p.x - ROT_CENTER.x, p.z - ROT_CENTER.z).length()
	if d < ROT_WARN and absf(p.y - ROT_CENTER.y) < 4.0 and not _rot_warned:
		_rot_warned = true
		hud.toast("These timbers are rotten through. Chipping under them could bring the roof down.", Color(1.0, 0.75, 0.4), 6.0)
	elif d > ROT_WARN + 4.0:
		_rot_warned = false


## Called for every blow on the rock. Returns true if this one brought the roof down.
func on_chip(world_pos: Vector3) -> bool:
	if collapsed or not Settings.hazards or _stress_wait > 0.0:
		return false
	var p: Vector3 = mine.to_local(world_pos)
	if p.distance_to(ROT_CENTER) > ROT_RADIUS + 0.8:
		return false
	_stress += 1
	_stress_wait = 1.5
	var main = get_tree().get_first_node_in_group("game")
	if _stress < ROT_BLOWS:
		main.hud.toast(["Dust sifts down from the roof.", "The timbers groan and crack. One more blow could bring it all down!"][mini(_stress - 1, 1)],
			Color(1.0, 0.6, 0.35), 4.0)
		return false
	collapse()
	main.player.global_position = mine.to_global(ROT_SAFE)
	main.player.velocity = Vector3.ZERO
	main.hud.blackout(2.5)
	main.hud.toast("The roof comes down! You scramble clear as the drift fills with broken rock. You can dig back through it.", Color(1.0, 0.6, 0.35), 8.0)
	return true


## Fill the rotten stretch with rock again.
func collapse() -> void:
	collapsed = true
	mine.fill(ROT_CENTER, ROT_RADIUS)
	if _rot_props != null:
		_rot_props.queue_free()
		_rot_props = null
