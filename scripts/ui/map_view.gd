extends CanvasLayer
## The map (M): shaded relief that fills in as you explore, with rivers, roads, landmarks, your
## vehicles, waypoints, and a dot for every test pan colored by how much gold it held.
## Left click drops a waypoint, right click removes the nearest one.

const Settings = preload("res://scripts/core/settings.gd")
const Claims = preload("res://scripts/core/claims.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")

const CELLS := 64                 # exploration grid (32 m cells)
const REVEAL := 170.0             # metres around you that get mapped
const MAX_WAYPOINTS := 20
const CURSOR_SPEED := 1600.0     # metres a second across the map at full stick

var cursor := Vector2.ZERO        # the controller's map cursor, in world metres
const FOG_SHADER := """
shader_type canvas_item;
uniform vec4 paper : source_color = vec4(0.86, 0.80, 0.66, 1.0);
void fragment() {
	float m = texture(TEXTURE, UV).r;
	float grain = fract(sin(dot(floor(UV * 600.0), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(paper.rgb * (0.94 + 0.06 * grain), 1.0 - smoothstep(0.25, 0.75, m));
}
"""

var world: WorldGen
var main
var waypoints: Array[Vector2] = []
var marks: Array = []                 # places learned from journals and old maps: [Vector2, label]
var explored := PackedByteArray()
var _mask_img: Image
var _mask_tex: ImageTexture
var _frame: Control
var _icons: Control
var _reveal_t := 0.0
var _taken: Array[Rect2] = []     # label boxes drawn this frame, so labels don't pile up

const PLACE_NAMES := {"ruin_cabin": "Ruined cabin", "wreck": "Old wreck", "graves": "Graves", "ore_cart": "Ore cart",
	"wagon": "Old wagon", "old_sluice": "Old sluice", "chimney": "Lone chimney", "prospect": "Prospect hole"}


class Icons extends Control:
	var view

	func _draw() -> void:
		view.draw_icons(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var mb := event as InputEventMouseButton
			var p := mb.position / size * WorldGen.SIZE
			if mb.button_index == MOUSE_BUTTON_LEFT:
				view.add_waypoint(p)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				view.remove_waypoint_near(p, 16.0 / size.x * WorldGen.SIZE)
			queue_redraw()


func setup(w: WorldGen, map_image: Image, main_ref) -> void:
	world = w
	main = main_ref
	explored.resize(CELLS * CELLS)
	explored.fill(0)
	_mask_img = Image.create_empty(CELLS, CELLS, false, Image.FORMAT_L8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_frame)
	var paper := ColorRect.new()
	paper.color = Color(0.86, 0.8, 0.66)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.offset_left = -10
	paper.offset_top = -10
	paper.offset_right = 10
	paper.offset_bottom = 10
	_frame.add_child(paper)
	var map_rect := TextureRect.new()
	map_rect.texture = ImageTexture.create_from_image(map_image)
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(map_rect)
	var fog := TextureRect.new()
	fog.texture = _mask_tex
	fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fog.stretch_mode = TextureRect.STRETCH_SCALE
	fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	fog_mat.shader = sh
	fog.material = fog_mat
	_frame.add_child(fog)
	_icons = Icons.new()
	_icons.view = self
	_icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_icons)
	var help := Label.new()
	help.text = "Left click: drop a waypoint      Right click: remove one      M: close"
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_constant_override("outline_size", 6)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.offset_top = -40
	help.offset_bottom = -12
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var side := minf(minf(vp.y - 110.0, vp.x - 80.0), 940.0)
	_frame.position = Vector2((vp.x - side) * 0.5, (vp.y - side) * 0.5 - 14.0)
	_frame.size = Vector2(side, side)


func toggle() -> void:
	visible = not visible
	main.player.map_open = visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var fp: Vector3 = main.focus_position()
		cursor = Vector2(fp.x, fp.z)
		_icons.queue_redraw()
	else:
		Settings.capture_mouse()
		main.player.grace()


func _process(delta: float) -> void:
	_reveal_t -= delta
	if _reveal_t <= 0.0:
		_reveal_t = 0.5
		reveal_around(main.focus_position())
	if visible:
		# Controller: the left stick moves a cursor over the map.
		var pd := Settings.pad_device()
		var st := Vector2(Input.get_joy_axis(pd, JOY_AXIS_LEFT_X), Input.get_joy_axis(pd, JOY_AXIS_LEFT_Y))
		if st.length() > 0.2:
			cursor = (cursor + st * st.length() * CURSOR_SPEED * delta).clamp(Vector2.ZERO, Vector2.ONE * WorldGen.SIZE)
		_icons.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventJoypadButton and event.pressed:
		# Controller: A drops a waypoint at the cursor, X removes the nearest one, B closes.
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A:
				add_waypoint(cursor)
			JOY_BUTTON_X:
				remove_waypoint_near(cursor, 120.0)
			JOY_BUTTON_B:
				toggle()
		get_viewport().set_input_as_handled()


func reveal_around(p: Vector3) -> void:
	var cell := WorldGen.SIZE / CELLS
	var r := ceili(REVEAL / cell)
	var ci := floori(p.x / cell)
	var cj := floori(p.z / cell)
	var changed := false
	for j in range(cj - r, cj + r + 1):
		for i in range(ci - r, ci + r + 1):
			if i < 0 or j < 0 or i >= CELLS or j >= CELLS:
				continue
			var k := j * CELLS + i
			if explored[k] > 0:
				continue
			if Vector2((i + 0.5) * cell - p.x, (j + 0.5) * cell - p.z).length() < REVEAL:
				explored[k] = 255
				_mask_img.set_pixel(i, j, Color(1, 1, 1))
				changed = true
	if changed:
		_mask_tex.update(_mask_img)


func is_explored(x: float, z: float) -> bool:
	var cell := WorldGen.SIZE / CELLS
	var i := clampi(floori(x / cell), 0, CELLS - 1)
	var j := clampi(floori(z / cell), 0, CELLS - 1)
	return explored[j * CELLS + i] > 0


func add_waypoint(p: Vector2) -> void:
	if waypoints.size() >= MAX_WAYPOINTS:
		waypoints.remove_at(0)
	waypoints.append(p)
	main.player.inv.complete_goal("map")


func remove_waypoint_near(p: Vector2, reach: float) -> void:
	var best := -1
	for i in waypoints.size():
		if waypoints[i].distance_to(p) < reach and (best < 0 or waypoints[i].distance_to(p) < waypoints[best].distance_to(p)):
			best = i
	if best >= 0:
		waypoints.remove_at(best)


## A place a journal or an old map told you about. It shows even where you haven't explored.
func add_mark(p: Vector2, label: String) -> void:
	for m in marks:
		if m[1] == label:
			return
	marks.append([p, label])


func load_state(d: Dictionary) -> void:
	var e: PackedByteArray = d.get("explored", PackedByteArray())
	if e.size() == CELLS * CELLS:
		explored = e
		for j in CELLS:
			for i in CELLS:
				_mask_img.set_pixel(i, j, Color(1, 1, 1) if explored[j * CELLS + i] > 0 else Color(0, 0, 0))
		_mask_tex.update(_mask_img)
	waypoints.clear()
	for w in d.get("waypoints", []):
		waypoints.append(w)
	marks = d.get("marks", [])


func save_state() -> Dictionary:
	return {"explored": explored, "waypoints": waypoints, "marks": marks}


# --- Drawing -------------------------------------------------------------------------------

func draw_icons(c: Control) -> void:
	var s := c.size.x / WorldGen.SIZE
	var font := c.get_theme_default_font()
	_taken.clear()
	if Settings.using_pad:
		var q := cursor * s
		for d: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
			c.draw_line(q - d * 12.0, q - d * 4.0, Color(1, 1, 1), 2.0)
			c.draw_line(q + d * 4.0, q + d * 12.0, Color(1, 1, 1), 2.0)
		_text(c, font, q + Vector2(14, -8), "A waypoint   X remove   B close", 12, Color(1, 1, 1))
	for smp in main.player.inv.samples:
		var g: float = smp.z
		var col := Color(0.35, 0.35, 0.35, 0.8) if g <= 0.0 else Color(1.0, 0.9, 0.3).lerp(Color(1.0, 0.35, 0.1), clampf(g / 0.25, 0.0, 1.0))
		c.draw_circle(Vector2(smp.x, smp.y) * s, 2.5 + minf(g * 16.0, 4.0), col)
	for reg in WorldGen.REGIONS:
		var rc: Vector2 = (reg[1] as Vector2) * WorldGen.LAYOUT
		_text(c, font, rc * s - Vector2(40, 0), str(reg[0]).to_upper(), 15, Color(0.3, 0.22, 0.12, 0.75))
	for r in world.rivers:
		var pts: PackedVector2Array = r["pts"]
		var mid := pts[pts.size() / 2]
		if is_explored(mid.x, mid.y):
			_text(c, font, mid * s + Vector2(6, -6), r["name"], 13, Color(0.12, 0.25, 0.4))
	for cl in Claims.list:
		var mine_now: bool = Claims.is_owned(cl["id"])
		var q: Vector2 = (cl["pos"] as Vector2) * s
		var ring := Color(0.1, 0.5, 0.15) if mine_now else Color(0.45, 0.35, 0.2)
		var fill := Color(0.2, 0.7, 0.25, 0.18) if mine_now else Color(0.85, 0.55, 0.15, 0.12)
		c.draw_circle(q, float(cl["radius"]) * s, fill)
		c.draw_arc(q, float(cl["radius"]) * s, 0.0, TAU, 48, ring, 2.5 if mine_now else 1.5)
		var tag: String = "%s (yours)" % cl["name"] if mine_now else "%s  $%d" % [cl["name"], cl["price"]]
		_label(c, font, q + Vector2(-30, float(cl["radius"]) * s + 13), tag, 12, ring.darkened(0.2))
	var places := [["base", "Grandpa's cabin", Color(0.75, 0.3, 0.1)], ["town", "Sable Crossing", Color(0.25, 0.2, 0.5)], ["camp", "Last Chance camp", Color(0.4, 0.3, 0.2)],
		["mine", "Old mine", Color(0.3, 0.3, 0.3)], ["garnet", "Garnet Beach", Color(0.6, 0.08, 0.15)]]
	for pl in places:
		if not world.sites.has(pl[0]):
			continue
		var site: Dictionary = world.sites[pl[0]]
		var pos: Vector2 = site["pos"]
		if pl[0] in ["base", "town", "garnet"] or is_explored(pos.x, pos.y):
			var q := pos * s
			c.draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), pl[2])
			_label(c, font, q + Vector2(8, 4), pl[1], 14, Color(0.15, 0.1, 0.05), true)
	var finds: Dictionary = main.player.inv.finds
	for rp in world.places:
		var rpos: Vector2 = rp["pos"]
		if rp["kind"] == "sign":
			if is_explored(rpos.x, rpos.y):
				c.draw_rect(Rect2(rpos * s - Vector2(2, 2), Vector2(4, 4)), Color(0.4, 0.28, 0.15, 0.8))
		elif finds.has(rp["id"]):
			var rq := rpos * s
			c.draw_circle(rq, 4.0, Color(0.35, 0.25, 0.15))
			c.draw_circle(rq, 2.5, Color(0.85, 0.75, 0.55))
			_label(c, font, rq + Vector2(7, 4), PLACE_NAMES.get(rp["kind"], "Old place"), 11, Color(0.3, 0.2, 0.1))
	for m in main.get_tree().get_nodes_in_group("machines"):
		if m.kind == "camp" and m.loaded_on == null:
			var cq := Vector2(m.global_position.x, m.global_position.z) * s
			c.draw_colored_polygon(PackedVector2Array([cq + Vector2(0, -7), cq + Vector2(6, 5), cq + Vector2(-6, 5)]), Color(0.2, 0.45, 0.15))
			_label(c, font, cq + Vector2(8, 4), m.camp_name(), 12, Color(0.15, 0.35, 0.1))
	for v in main.get_tree().get_nodes_in_group("vehicles"):
		var q := Vector2(v.global_position.x, v.global_position.z) * s
		c.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), Color(0.15, 0.35, 0.8))
		_label(c, font, q + Vector2(7, 4), v.display_name, 12, Color(0.1, 0.2, 0.5))
	for m in marks:
		var q: Vector2 = (m[0] as Vector2) * s
		var ink := Color(0.6, 0.08, 0.05)
		c.draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), ink, 3.0)
		c.draw_line(q + Vector2(-6, 6), q + Vector2(6, -6), ink, 3.0)
		_label(c, font, q + Vector2(9, 4), m[1], 14, ink, true)
	for i in waypoints.size():
		var q := waypoints[i] * s
		c.draw_circle(q, 7.0, Color(0.1, 0.1, 0.1))
		c.draw_circle(q, 5.5, Color(1.0, 0.85, 0.2))
		_text(c, font, q + Vector2(-3, 4), str(i + 1), 11, Color(0.1, 0.1, 0.1))
		_label(c, font, q + Vector2(9, 4), "Waypoint %d  %d m" % [i + 1, roundi(waypoints[i].distance_to(_here()))], 11, Color(0.15, 0.12, 0.02))
	var p: Vector3 = main.focus_position()
	var h: float = main.heading()
	var fwd := Vector2(sin(h), -cos(h))
	var side := Vector2(-fwd.y, fwd.x)
	var q0 := Vector2(p.x, p.z) * s
	c.draw_colored_polygon(PackedVector2Array([q0 + fwd * 11.0, q0 - fwd * 6.0 + side * 6.0, q0 - fwd * 6.0 - side * 6.0]), Color(0.85, 0.1, 0.1))


## A label that skips itself if it would sit on top of one already drawn (keeps the map tidy).
## Labels that must show (marks) are drawn anyway but still reserve their space.
func _label(c: Control, font: Font, pos: Vector2, text: String, size: int, col: Color, force: bool = false) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box := Rect2(pos - Vector2(0, size), Vector2(w, size + 2))
	if not force:
		for t in _taken:
			if t.intersects(box):
				return
	_taken.append(box)
	_text(c, font, pos, text, size, col)


func _here() -> Vector2:
	var p: Vector3 = main.focus_position()
	return Vector2(p.x, p.z)


func _text(c: Control, font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	c.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(1, 1, 1, 0.7))
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
