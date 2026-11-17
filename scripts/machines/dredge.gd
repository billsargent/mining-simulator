extends "res://scripts/machines/machine.gd"
## Suction dredge: a small raft with an engine, a suction hose and a sluice on deck. Set it
## in water at least knee-deep and it vacuums the river bottom under it by itself, a shovelful
## every couple of seconds, down to bedrock. Clean out the riffles like any sluice.
## It comes with a dredging permit, and like every machine it only runs on your own claim.

const SUCK_SECONDS := 2.2
const SUCK_DEPTH := 0.15
const SUCK_RADIUS := 0.8

var deposits
var worked_out := false                # down to bedrock where it sits
var _suck_t := 0.0
var _hose: Node3D


func _init() -> void:
	kind = "dredge"
	display_name = "Suction dredge"
	hopper_capacity = 6
	seconds_per_shovel = 0.9
	recovery_bonus = 0.02


func water_problem() -> String:
	var depth := terrain.water_depth(global_position.x, global_position.z)
	if depth < 0.45:
		return "float it in deeper water, at least knee-deep"
	if depth > 4.0:
		return "the water's too deep for the hose here"
	return ""


func place_at(pos: Vector3, yaw: float) -> void:
	var ground := terrain.height_at(pos.x, pos.z)
	var level := terrain.water_level(pos.x, pos.z)
	rotation = Vector3(0.0, yaw + PI / 2.0, 0.0)
	global_position = Vector3(pos.x, maxf(ground, level - 0.12), pos.z)
	worked_out = false
	_on_moved()


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_running() or worked_out or hopper_space() <= 0:
		return
	_suck_t += delta
	if _suck_t < SUCK_SECONDS:
		return
	_suck_t = 0.0
	if deposits == null:
		var main = get_tree().get_first_node_in_group("game")
		deposits = main.deposits if main != null else null
		if deposits == null:
			return
	var p := global_position
	var res: Dictionary = terrain.dig(Vector3(p.x, terrain.height_at(p.x, p.z), p.z), SUCK_DEPTH, SUCK_RADIUS)
	if res["removed"] < 0.02:
		worked_out = true
		return
	feed(deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"]))


func _status_bb() -> String:
	if worked_out and problem() == "" and not carried and loaded_on == null:
		return "[color=#ffd080]Down to bedrock here: move it to fresh ground[/color]"
	var s := super()
	return s.replace("Running: feed it", "Running: sucking up the bottom")


func info_text() -> String:
	return "The dredge feeds itself from the river bottom."


func _build() -> void:
	var alu := Parts.aluminum()
	var paint := Parts.paint("dredge_yellow", Color(0.75, 0.6, 0.15))
	var deck := Parts.wood("dredge_deck", Color(0.5, 0.4, 0.28))
	# Two pontoons and a deck frame.
	for z: float in [-0.55, 0.55]:
		Parts.cyl(self, 0.2, 2.0, Vector3(0, 0.12, z), paint, Vector3(0, 0, PI / 2.0), -1.0, 14)
		Parts.cyl(self, 0.2, 0.01, Vector3(1.0, 0.12, z), paint, Vector3(0, 0, PI / 2.0), 0.05, 14)
	Parts.box(self, Vector3(1.9, 0.05, 1.3), Vector3(0, 0.34, 0), deck)
	# Engine and pump.
	Parts.box(self, Vector3(0.4, 0.3, 0.32), Vector3(-0.6, 0.52, 0.25), Parts.paint("engine_red", Color(0.55, 0.14, 0.1)))
	Parts.cyl(self, 0.09, 0.14, Vector3(-0.6, 0.73, 0.25), Parts.mat("iron", Color(0.18, 0.17, 0.17), 0.6, 0.7), Vector3.ZERO, -1.0, 10)
	Parts.cyl(self, 0.1, 0.18, Vector3(-0.3, 0.46, 0.25), alu, Vector3(PI / 2.0, 0, 0), -1.0, 12)
	# The sluice on deck, tilted with the angle knob.
	_tilt = Node3D.new()
	_tilt.position = Vector3(-0.75, 0.62, -0.25)
	add_child(_tilt)
	_build_bed(_tilt, 1.5, 0.3)
	# Suction hose down into the water, and the nozzle on the bottom.
	_hose = Node3D.new()
	add_child(_hose)
	var pts := PackedVector3Array([Vector3(-0.3, 0.46, 0.35), Vector3(-0.1, 0.5, 0.75), Vector3(0.2, 0.0, 0.95), Vector3(0.4, -0.6, 0.9)])
	var hose := MeshInstance3D.new()
	hose.mesh = Parts.tube(pts, 0.05, 8)
	hose.material_override = Parts.hose()
	_hose.add_child(hose)
	Parts.cyl(_hose, 0.07, 0.3, Vector3(0.45, -0.75, 0.9), alu, Vector3(0.3, 0, 0), -1.0, 10)
	Parts.collider(self, Vector3(2.0, 0.5, 1.5), Vector3(0, 0.25, 0))


func to_dict() -> Dictionary:
	var d := super()
	d["worked_out"] = worked_out
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	worked_out = d.get("worked_out", false)
