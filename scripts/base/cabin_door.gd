extends StaticBody3D
## The cabin door. E opens or closes it; it swings inward on its hinge.
## The node sits on the hinge; the door leaf extends toward -X from it.

const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const WIDTH := 0.95
const OPEN_ANGLE := -1.75          # radians: swung inward, against the wall

var is_open := false
var _tween: Tween


func build() -> void:
	var dark := Parts.wood("door", Color(0.27, 0.19, 0.12))
	Parts.box(self, Vector3(WIDTH, 2.0, 0.06), Vector3(-WIDTH * 0.5, 1.0, 0), dark)
	for y: float in [0.35, 1.65]:
		Parts.box(self, Vector3(WIDTH - 0.1, 0.12, 0.04), Vector3(-WIDTH * 0.5, y, 0.05), dark)
		Parts.box(self, Vector3(WIDTH - 0.1, 0.12, 0.04), Vector3(-WIDTH * 0.5, y, -0.05), dark)
	for z: float in [0.05, -0.05]:
		Parts.box(self, Vector3(0.06, 0.06, 0.04), Vector3(-WIDTH + 0.08, 1.0, z), Parts.steel())
	Parts.collider(self, Vector3(WIDTH, 2.0, 0.12), Vector3(-WIDTH * 0.5, 1.0, 0))


func prompt(_player) -> String:
	return "[b]Cabin door[/b]\n%s %s" % [Hud.key("E"), "Close the door" if is_open else "Open the door"]


func interact(_player) -> void:
	set_open(not is_open)


func set_open(o: bool, instant: bool = false) -> void:
	is_open = o
	if _tween != null:
		_tween.kill()
	var target := OPEN_ANGLE if o else 0.0
	if instant:
		rotation.y = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "rotation:y", target, 0.45).set_trans(Tween.TRANS_SINE)
