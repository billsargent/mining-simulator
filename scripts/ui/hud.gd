extends CanvasLayer
## Screen overlay: crosshair, action prompt, money and inventory, the next goal, messages,
## and the panning guide.

const PanSim = preload("res://scripts/panning/pan_sim.gd")
const Compass = preload("res://scripts/ui/compass.gd")
const Settings = preload("res://scripts/core/settings.gd")

var compass: Compass
var _prompt: RichTextLabel
var _status: Label
var _goal: Label
var _guide: Control
var _guide_pos := Vector2.ZERO
var _guide_dist := -1.0
var _toast: Label
var _toast_left := 0.0
var _pan_box: PanelContainer
var _pan_text: RichTextLabel
var _help: Label
var _shade: ColorRect
var _shade_level := 0.0
var _blackout := 0.0
var _blackout_time := 1.0
var _note_box: PanelContainer
var _note_text: RichTextLabel


## A key name formatted for prompts, e.g. key("E") -> [E] in yellow.
static func key(k: String) -> String:
	return "[color=#ffd866][lb]%s[rb][/color]" % Settings.prompt_key(k)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_shade)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(dot, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-2, -2, 2, 2))
	root.add_child(dot)

	compass = Compass.new()
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(compass, Vector4(0.5, 0, 0.5, 0), Vector4(-320, 8, 320, 64))
	root.add_child(compass)

	var status_box := _panel()
	_anchor(status_box, Vector4(0, 0, 0, 0), Vector4(16, 16, 16, 16))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	status_box.add_child(col)
	_status = _label(19)
	col.add_child(_status)
	# The guide: a green diamond over the next goal's place, with its distance.
	_guide = Control.new()
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_guide.draw.connect(_draw_guide)
	root.add_child(_guide)
	_goal = _label(16)
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.custom_minimum_size = Vector2(380, 0)
	_goal.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	col.add_child(_goal)
	root.add_child(status_box)

	_prompt = RichTextLabel.new()
	_prompt.bbcode_enabled = true
	_prompt.fit_content = true
	_prompt.scroll_active = false
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("normal_font_size", 21)
	_prompt.add_theme_font_size_override("bold_font_size", 22)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_anchor(_prompt, Vector4(0.15, 1, 0.85, 1), Vector4(0, -100, 0, -60))
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_prompt)

	_toast = _label(24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor(_toast, Vector4(0.3, 0.12, 0.85, 0.12), Vector4(0, 0, 0, 80))
	root.add_child(_toast)

	_pan_box = _panel()
	_anchor(_pan_box, Vector4(1, 0.5, 1, 0.5), Vector4(-430, -180, -16, 180))
	_pan_text = RichTextLabel.new()
	_pan_text.bbcode_enabled = true
	_pan_text.fit_content = true
	_pan_text.scroll_active = false
	_pan_text.custom_minimum_size = Vector2(390, 0)
	_pan_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_text.add_theme_font_size_override("normal_font_size", 18)
	_pan_text.add_theme_font_size_override("bold_font_size", 18)
	_pan_box.add_child(_pan_text)
	_pan_box.visible = false
	root.add_child(_pan_box)

	_note_box = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.9, 0.86, 0.74, 0.97)
	paper.set_corner_radius_all(4)
	paper.set_content_margin_all(28)
	_note_box.add_theme_stylebox_override("panel", paper)
	_note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_note_box, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-330, -40, 330, 40))
	_note_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_note_text = RichTextLabel.new()
	_note_text.bbcode_enabled = true
	_note_text.fit_content = true
	_note_text.scroll_active = false
	_note_text.custom_minimum_size = Vector2(600, 0)
	_note_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_text.add_theme_font_size_override("normal_font_size", 20)
	_note_text.add_theme_font_size_override("bold_font_size", 23)
	_note_text.add_theme_font_size_override("italics_font_size", 16)
	_note_text.add_theme_color_override("default_color", Color(0.16, 0.11, 0.07))
	_note_box.add_child(_note_text)
	_note_box.visible = false
	root.add_child(_note_box)

	_help = _label(16)
	_help.text = Settings.help(false)
	_help.modulate = Color(1, 1, 1, 0.75)
	_anchor(_help, Vector4(0, 1, 1, 1), Vector4(16, -36, -16, -10))
	root.add_child(_help)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)
	if _blackout > 0.0:
		_blackout = maxf(0.0, _blackout - delta / _blackout_time)
	_shade.color.a = maxf(_shade_level, _blackout)


## Darken the whole view (0 = clear). Used when the air is bad.
func set_shade(a: float) -> void:
	_shade_level = clampf(a, 0.0, 1.0)


## Go black, then fade back in over the given time.
func blackout(seconds: float) -> void:
	_blackout = 1.0
	_blackout_time = maxf(seconds, 0.1)


## A page to read, in the middle of the screen.
func show_note(title: String, body: String) -> void:
	_note_text.text = "[b]%s[/b]\n\n%s\n\n[i]E or walk away to put it down[/i]" % [title, body]
	_note_box.visible = true


func hide_note() -> void:
	_note_box.visible = false


func note_open() -> bool:
	return _note_box.visible


## bbcode text; use key("E") for key names.
func set_prompt(bbcode: String) -> void:
	var t := "[center]%s[/center]" % bbcode if bbcode != "" else ""
	if _prompt.text != t:
		_prompt.text = t


func set_status(inv, bucket_capacity: int, clock: String = "", extra: PackedStringArray = PackedStringArray()) -> void:
	var lines := PackedStringArray()
	lines.append("$%d" % inv.money + ("      " + clock if clock != "" else ""))
	lines.append("Bucket   %d / %d" % [inv.bucket.size(), bucket_capacity])
	if not inv.cons.is_empty():
		lines.append("Concentrate   %d jar%s" % [inv.cons.size(), "" if inv.cons.size() == 1 else "s"])
	if not inv.ore.is_empty():
		lines.append("Ore sack   %d / %d" % [inv.ore.size(), inv.ore_capacity()])
	var gold := "Gold   %.3f g" % inv.vial_grams()
	if not inv.nuggets.is_empty():
		gold += "     Nuggets   %d  (%.2f g)" % [inv.nuggets.size(), inv.nugget_grams()]
	lines.append(gold)
	if not inv.specimens.is_empty():
		lines.append("Specimens   %d  (gold in quartz)" % inv.specimens.size())
	if not inv.garnets.is_empty():
		var ct := 0.0
		for g in inv.garnets:
			ct += g
		lines.append("Garnets   %d  (%.1f carats)" % [inv.garnets.size(), ct])
	if not inv.bars.is_empty():
		lines.append("Bars   %d  (%.2f g)" % [inv.bars.size(), inv.bar_grams()])
	lines.append_array(extra)
	var t := "\n".join(lines)
	if _status.text != t:
		_status.text = t


## Point the guide at a world position (or hide it with null).
func set_guide(target, cam: Camera3D) -> void:
	_guide_dist = -1.0
	if target != null and cam != null:
		var p: Vector3 = target + Vector3(0, 1.6, 0)
		var d := cam.global_position.distance_to(p)
		# Only near goals get the on-screen marker; far ones are on the compass.
		if d > 6.0 and d < 600.0 and not cam.is_position_behind(p):
			_guide_pos = cam.unproject_position(p)
			_guide_dist = d
	_guide.queue_redraw()


func _draw_guide() -> void:
	if _guide_dist < 0.0:
		return
	var c := _guide_pos
	var col := Color(0.45, 1.0, 0.5, 0.9)
	var pts := PackedVector2Array([c + Vector2(0, -11), c + Vector2(9, 0), c + Vector2(0, 11), c + Vector2(-9, 0)])
	_guide.draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
	pts.append(pts[0])
	_guide.draw_polyline(pts, col, 2.5, true)
	var font := _guide.get_theme_default_font()
	var text := "%d m" % roundi(_guide_dist)
	var at := c + Vector2(-4.0 * text.length(), 30)
	_guide.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
	_guide.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


func set_goal(text: String) -> void:
	var t := "Next: " + text
	if _goal.text != t:
		_goal.text = t


func toast(text: String, color: Color = Color(1, 1, 1), seconds: float = 3.5) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast_left = seconds


func show_pan(on: bool) -> void:
	_pan_box.visible = on
	_help.visible = not on


func set_help(text: String) -> void:
	if _help.text != text:
		_help.text = text


func set_pan_status(tilt: float, target: float, washing: bool, left: float, done: bool, lost: int) -> void:
	var t := "[b]Panning[/b]\n"
	t += "Hold [b]Left mouse[/b]   shake (gold sinks)\n"
	t += "Hold [b]Right mouse[/b]   tilt and wash\n"
	t += "Mouse forward/back   set the tilt\n"
	t += "Mouse sideways   swirl\n"
	t += "[b]Q[/b]   dump the pan\n\n"
	var zone: String
	if tilt < PanSim.WASH_START:
		zone = "[color=#a0aaaa]level[/color]"
	elif tilt <= PanSim.SAFE_TILT:
		zone = "[color=#80dd80]washing[/color]"
	else:
		zone = "[color=#ff6a6a]too steep, gold at risk![/color]"
	t += "Tilt   %d°  (set to %d°)   %s\n" % [roundi(tilt), roundi(target), zone]
	t += "Material left   %d%%\n" % roundi(left * 100.0)
	if lost > 0:
		t += "[color=#ff8a8a]Gold washed out: %d[/color]\n" % lost
	if done:
		t += "\n[color=#ffd866][b]Clean! Only black sand and gold left.\nPress E to collect the gold.[/b][/color]"
	if _pan_text.text != t:
		_pan_text.text = t


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.05, 0.55)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## anchors and offsets are (left, top, right, bottom)
func _anchor(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w
