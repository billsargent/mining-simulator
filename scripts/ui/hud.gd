extends CanvasLayer
## Screen overlay: crosshair, action prompt, money and inventory, the next goal, messages,
## and the panning guide.

const PanSim = preload("res://scripts/panning/pan_sim.gd")
const Compass = preload("res://scripts/ui/compass.gd")

var compass: Compass
var _prompt: RichTextLabel
var _status: Label
var _goal: Label
var _toast: Label
var _toast_left := 0.0
var _pan_box: PanelContainer
var _pan_text: RichTextLabel
var _help: Label


## A key name formatted for prompts, e.g. key("E") -> [E] in yellow.
static func key(k: String) -> String:
	return "[color=#ffd866][lb]%s[rb][/color]" % k


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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

	_help = _label(16)
	_help.text = "WASD move   Shift sprint   Space jump   LMB dig   E use / pan   F carry   Wheel adjust   R dump bucket   M map   L headlamp   Esc menu"
	_help.modulate = Color(1, 1, 1, 0.75)
	_anchor(_help, Vector4(0, 1, 1, 1), Vector4(16, -36, -16, -10))
	root.add_child(_help)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)


## bbcode text; use key("E") for key names.
func set_prompt(bbcode: String) -> void:
	var t := "[center]%s[/center]" % bbcode if bbcode != "" else ""
	if _prompt.text != t:
		_prompt.text = t


func set_status(inv, bucket_capacity: int, clock: String = "") -> void:
	var lines := PackedStringArray()
	lines.append("$%d" % inv.money + ("      " + clock if clock != "" else ""))
	lines.append("Bucket   %d / %d" % [inv.bucket.size(), bucket_capacity])
	if not inv.cons.is_empty():
		lines.append("Concentrate   %d jar%s" % [inv.cons.size(), "" if inv.cons.size() == 1 else "s"])
	var gold := "Gold   %.3f g" % inv.vial_grams()
	if not inv.nuggets.is_empty():
		gold += "     Nuggets   %d  (%.2f g)" % [inv.nuggets.size(), inv.nugget_grams()]
	lines.append(gold)
	if not inv.bars.is_empty():
		lines.append("Bars   %d  (%.2f g)" % [inv.bars.size(), inv.bar_grams()])
	var t := "\n".join(lines)
	if _status.text != t:
		_status.text = t


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
