extends "res://scripts/vehicles/vehicle.gd"
## Mini-excavator: slow, heavy, and digs a big bucket of ground at a time. Drive it next to a
## running trommel or high banker and press left mouse: the bucket scoops the ground in front
## and swings it straight into the hopper.

const SCOOP_DEPTH := 0.3
const SCOOP_RADIUS := 1.4
const SCOOP_SHOVELS := 4            # one bucket is about four shovelfuls
const REACH := 9.0                  # how far it can swing a load to a hopper
const DIG_AHEAD := Vector3(0, 0, -3.4)

var _boom: Node3D
var _stick: Node3D
var _cool := 0.0


func _init() -> void:
	kind = "excavator"
	display_name = "Mini-excavator"
	mass = 3500.0
	wheel_mounts = [Vector3(-0.75, 0.32, -0.9), Vector3(0.75, 0.32, -0.9), Vector3(-0.75, 0.32, 0.9), Vector3(0.75, 0.32, 0.9)]
	wheel_radius = 0.3
	wheel_width = 0.35
	rest = 0.22
	spring = 70000.0
	damper = 7000.0
	anti_roll = 40000.0
	engine_force = 26000.0
	top_speed = 4.5
	brake_force = 40000.0
	max_steer = 0.75
	com_y = 0.35
	seat = Vector3(-0.2, 1.05, 0.3)
	head = Vector3(-0.2, 1.75, 0.35)
	exit_offset = Vector3(-1.6, 0, 0.3)
	chase = Vector3(0, 3.8, 7.0)


func _build() -> void:
	var yellow := Parts.paint("excavator", Color(0.85, 0.62, 0.1))
	var dark := Parts.mat("track", Color(0.08, 0.08, 0.08), 0.9)
	var glass := Parts.mat("cab_glass", Color(0.1, 0.13, 0.15), 0.1, 0.3)
	for x: float in [-0.75, 0.75]:
		Parts.box(self, Vector3(0.4, 0.45, 2.3), Vector3(x, 0.3, 0.0), dark)                  # tracks
	Parts.box(self, Vector3(1.6, 0.35, 1.8), Vector3(0, 0.7, 0.2), yellow)                     # house
	Parts.box(self, Vector3(1.6, 0.5, 0.6), Vector3(0, 1.05, 0.85), yellow)                    # counterweight
	# Open cab with a roof on posts.
	for p: Vector3 in [Vector3(-0.7, 0, -0.35), Vector3(0.3, 0, -0.35), Vector3(-0.7, 0, 0.6), Vector3(0.3, 0, 0.6)]:
		Parts.box(self, Vector3(0.06, 1.2, 0.06), p + Vector3(0, 1.45, 0), yellow)
	Parts.box(self, Vector3(1.15, 0.06, 1.1), Vector3(-0.2, 2.07, 0.12), yellow)
	Parts.box(self, Vector3(0.95, 0.6, 0.02), Vector3(-0.2, 1.6, -0.37), glass)
	Parts.box(self, Vector3(0.5, 0.1, 0.5), Vector3(-0.2, 1.0, 0.3), dark)                      # seat
	# Boom, stick and bucket, swinging from the front of the house.
	_boom = Node3D.new()
	_boom.position = Vector3(0.45, 0.95, -0.6)
	_boom.rotation.x = 0.5
	add_child(_boom)
	Parts.box(_boom, Vector3(0.22, 0.25, 1.9), Vector3(0, 0, -0.95), yellow)
	_stick = Node3D.new()
	_stick.position = Vector3(0, 0, -1.9)
	_stick.rotation.x = -1.4
	_boom.add_child(_stick)
	Parts.box(_stick, Vector3(0.18, 0.2, 1.3), Vector3(0, 0, -0.65), yellow)
	var bucket := Node3D.new()
	bucket.position = Vector3(0, 0, -1.3)
	_stick.add_child(bucket)
	Parts.box(bucket, Vector3(0.6, 0.4, 0.45), Vector3(0, -0.1, -0.15), dark)
	var body := BoxShape3D.new()
	body.size = Vector3(1.9, 0.9, 2.3)
	var cs := CollisionShape3D.new()
	cs.shape = body
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)


func _physics_process(delta: float) -> void:
	_cool -= delta
	super(delta)


## The nearest running machine within reach that has room in its hopper.
func _target():
	var best = null
	var best_d := REACH
	for m in get_tree().get_nodes_in_group("machines"):
		if not m.processes or not m.is_running() or m.hopper_space() <= 0:
			continue
		var d := Vector2(global_position.x, global_position.z).distance_to(Vector2(m.global_position.x, m.global_position.z))
		if d < best_d:
			best = m
			best_d = d
	return best


func drive_hint() -> String:
	var t = _target()
	if t == null:
		return "Park within %d m of a running trommel or high banker to dig into it" % int(REACH)
	return "%s Dig a bucket into the %s  (%d/%d)" % [Hud.key("Left mouse"), str(t.display_name).to_lower(), t.hopper.size(), t.hopper_capacity]


## Left mouse while driving: scoop the ground in front and swing it into the hopper.
func action(player) -> void:
	if _cool > 0.0:
		return
	var target = _target()
	if target == null:
		player.hud.toast("Nowhere to put it. Park within %d m of a running trommel or high banker." % int(REACH))
		return
	var p := to_global(DIG_AHEAD)
	p.y = terrain.height_at(p.x, p.z)
	var res: Dictionary = terrain.dig(p, SCOOP_DEPTH, SCOOP_RADIUS)
	if res["removed"] < 0.02:
		player.hud.toast("Bedrock here. Move the excavator to fresh ground.")
		_cool = 0.5
		return
	_cool = 1.6
	var deposits = get_tree().get_first_node_in_group("game").deposits
	var n := 0
	for i in SCOOP_SHOVELS:
		if target.hopper_space() <= 0:
			break
		target.feed(deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"]))
		n += 1
	player.on_machine_fed(target)
	Sfx.play("dig", p, 2.0, 0.8)
	Sfx.play("dump", target.global_position, 0.0)
	var tw := create_tween()
	tw.tween_property(_boom, "rotation:x", 0.1, 0.4)
	tw.parallel().tween_property(_stick, "rotation:x", -0.6, 0.4)
	tw.tween_property(_boom, "rotation:x", 0.75, 0.5)
	tw.parallel().tween_property(_stick, "rotation:x", -1.9, 0.5)
	tw.tween_property(_boom, "rotation:x", 0.5, 0.5)
	tw.parallel().tween_property(_stick, "rotation:x", -1.4, 0.5)
	player.hud.toast("Bucket into the %s  (%d/%d)" % [str(target.display_name).to_lower(), target.hopper.size(), target.hopper_capacity],
		Color(0.75, 0.9, 1.0), 1.2)
