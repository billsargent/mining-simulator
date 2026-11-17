extends "res://scripts/machines/machine.gd"
## A camp tent: carry it anywhere (F) and set it down. At a tent you can sleep until morning
## (the game saves) or travel to the cabin or another of your camps (mouse wheel to choose).

const Travel = preload("res://scripts/core/travel.gd")

var number := 1
var _sel := 0


func _init() -> void:
	kind = "camp"
	display_name = "Camp tent"
	processes = false


func camp_name() -> String:
	return "Camp %d" % number


func arrival_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 2.4))


func water_problem() -> String:
	if terrain.water_depth(global_position.x, global_position.z) > 0.0:
		return "pitch it on dry ground"
	return ""


## A tent works anywhere, claim or not.
func problem() -> String:
	return water_problem()


func place_at(pos: Vector3, yaw: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	global_position = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	_on_moved()


func _build() -> void:
	var canvas := Parts.mat("canvas", Color(0.6, 0.55, 0.38), 0.95)
	var pole := Parts.wood("tent_pole", Color(0.42, 0.32, 0.22))
	# An A-frame wall tent: two sloped panels, a back wall, and a ridge pole.
	for s: float in [-1.0, 1.0]:
		Parts.box(self, Vector3(0.04, 1.75, 2.6), Vector3(s * 0.62, 0.72, 0.0), canvas, Vector3(0, 0, s * 0.62))
	var back := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-1.2, 0, -1.3), Vector3(1.2, 0, -1.3), Vector3(0, 1.45, -1.3)]:
		st.add_vertex(v)
	st.generate_normals()
	back.mesh = st.commit()
	back.material_override = canvas
	add_child(back)
	Parts.cyl(self, 0.03, 2.8, Vector3(0, 1.45, 0), pole, Vector3(PI / 2.0, 0, 0), -1.0, 8)
	for z: float in [-1.3, 1.3]:
		Parts.cyl(self, 0.03, 1.45, Vector3(0, 0.72, z), pole, Vector3.ZERO, -1.0, 8)
	# A fire ring and a crate in front.
	var stone := Parts.mat("stone", Color(0.42, 0.4, 0.38), 0.95)
	for k in 7:
		var a := TAU * k / 7.0
		Parts.box(self, Vector3(0.2, 0.14, 0.16), Vector3(0.9 + cos(a) * 0.35, 0.07, 2.0 + sin(a) * 0.35), stone, Vector3(0, a, 0))
	Parts.box(self, Vector3(0.45, 0.35, 0.35), Vector3(-0.9, 0.17, 1.8), Parts.wood("crate", Color(0.5, 0.38, 0.25)))
	Parts.collider(self, Vector3(2.3, 1.4, 2.6), Vector3(0, 0.7, 0))


func prompt(player) -> String:
	if loaded_on != null:
		return "[b]%s[/b]\n%s Take it off the %s" % [display_name, Hud.key("F"), str(loaded_on.display_name).to_lower()]
	var main = get_tree().get_first_node_in_group("game")
	_sel = clampi(_sel, 0, Travel.count(main, global_position) - 1)
	var t := "[b]%s[/b]" % camp_name()
	t += Travel.menu(main, global_position, "Sleep until morning (saves the game)", _sel)
	return t + "\n" + Hud.key("Wheel") + " Choose     " + Hud.key("E") + " Go     " + Hud.key("F") + " Pack up"


func scroll(_player, dir: int) -> void:
	var main = get_tree().get_first_node_in_group("game")
	_sel = posmod(_sel - dir, Travel.count(main, global_position))


func interact(player) -> void:
	var main = get_tree().get_first_node_in_group("game")
	if _sel == 0:
		main.sleep()
	else:
		Travel.go(main, player, _sel)
		_sel = 0


func to_dict() -> Dictionary:
	var d := super()
	d["number"] = number
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	number = d.get("number", 1)
