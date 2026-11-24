extends CanvasLayer
## Esc menu: resume, save, settings, records, mine hazards on or off, start over, quit.

const Settings = preload("res://scripts/core/settings.gd")

var main
var _hazard_btn: Button
var _new_btn: Button
var _save_btn: Button
var _confirm_t := 0.0
var _saved_t := 0.0
var _main_panel: Control
var _opt_panel: Control
var _rec_panel: Control
var _rec_grid: GridContainer
var _key_btns := {}
var _waiting := ""         # action waiting for a new key
var _waiting_pad := ""     # action waiting for a new controller button
var _pad_btns := {}
var _quality_btn: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.07, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	_main_panel = panel
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	_button(box, "Resume", _resume)
	_save_btn = _button(box, "Save game", _save)
	_button(box, "Settings", _open_settings)
	_button(box, "Records", _open_records)
	_hazard_btn = _button(box, "", _toggle_hazards)
	_show_hazards()
	_new_btn = _button(box, "Start a new game", _new_game)
	_button(box, "Save and quit", _quit)
	var note := Label.new()
	note.text = "Mine hazards are lamp batteries, bad air and cave-ins. Turn them off to explore the mine in peace.\n\nThe game also saves itself every minute and when you quit."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	_build_settings(root, sb)
	_build_records(root, sb)
	visible = false


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	box.add_child(b)
	return b


func _input(event: InputEvent) -> void:
	# Prompts and the help line follow whichever the player is using: controller or keyboard.
	if Settings.note_input(event) and main != null and main.player != null:
		main.player.hud.set_help(Settings.help(main.player.driving != null))
		main.player.refresh_hud()
		if visible and Settings.using_pad and get_viewport().gui_get_focus_owner() == null:
			_focus_first()
	if _waiting_pad != "" and visible and event is InputEventJoypadButton and event.pressed:
		var b: int = (event as InputEventJoypadButton).button_index
		if b != JOY_BUTTON_START:
			Settings.rebind_pad(_waiting_pad, b)
		_waiting_pad = ""
		_show_keys()
		get_viewport().set_input_as_handled()
		return
	if _waiting == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode
		if code != KEY_ESCAPE:
			Settings.rebind(_waiting, code)
		_waiting = ""
		_show_keys()
		get_viewport().set_input_as_handled()


## Give the first button of the open page keyboard/controller focus, so the D-pad can move.
func _focus_first() -> void:
	var page: Control = _main_panel
	if _opt_panel.visible:
		page = _opt_panel
	elif _rec_panel.visible:
		page = _rec_panel
	for b in page.find_children("*", "BaseButton", true, false):
		if (b as Control).is_visible_in_tree():
			(b as Control).grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	var pad_back: bool = visible and event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")
	if event.is_action_pressed("toggle_mouse") or pad_back:
		if visible and _opt_panel.visible:
			_close_settings()
		elif visible and _rec_panel.visible:
			_close_records()
		elif not visible and main.map_view.visible:
			main.map_view.toggle()
		elif visible:
			_resume()
		else:
			open()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _confirm_t > 0.0:
		_confirm_t -= delta
		if _confirm_t <= 0.0:
			_new_btn.text = "Start a new game"
	if _saved_t > 0.0:
		_saved_t -= delta
		if _saved_t <= 0.0:
			_save_btn.text = "Save game"


func open() -> void:
	_close_settings()
	_close_records()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_first()


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Settings.capture_mouse()
	main.player.grace()
	main.player.hud.set_help(Settings.help(main.player.driving != null))


func _toggle_hazards() -> void:
	Settings.hazards = not Settings.hazards
	Settings.save_file()
	_show_hazards()


func _show_hazards() -> void:
	_hazard_btn.text = "Mine hazards: %s" % ("On" if Settings.hazards else "Off")


func _save() -> void:
	main.save_now()
	_save_btn.text = "Saved"
	_saved_t = 2.0


func _new_game() -> void:
	if _confirm_t <= 0.0:
		_new_btn.text = "Click again to start over"
		_confirm_t = 3.0
		return
	main.new_game()


func _quit() -> void:
	main.save_now()
	get_tree().quit()


# --- Settings -----------------------------------------------------------------------------------

func _build_settings(root: Control, sb: StyleBoxFlat) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	_opt_panel = panel
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_heading(box, "Graphics")
	_quality_btn = _row_button(box, "Quality", _cycle_quality)
	_slider(box, "Render scale", 50, 100, Settings.render_scale * 100.0, "%d%%", func(v: float) -> void:
		Settings.render_scale = v / 100.0)
	_check(box, "Full screen", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
	_check(box, "Vertical sync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on)
	_slider(box, "Field of view", 60, 100, Settings.fov, "%d", func(v: float) -> void: Settings.fov = v)
	_heading(box, "Sound")
	_slider(box, "Volume", 0, 100, Settings.volume * 100.0, "%d%%", func(v: float) -> void: Settings.volume = v / 100.0)
	_slider(box, "Music", 0, 100, Settings.music_volume * 100.0, "%d%%", func(v: float) -> void: Settings.music_volume = v / 100.0)
	_heading(box, "Mouse")
	_slider(box, "Sensitivity", 20, 300, Settings.mouse_sens * 100.0, "%d%%", func(v: float) -> void:
		Settings.mouse_sens = v / 100.0)
	_check(box, "Invert look up and down", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
	_heading(box, "Keys  (click one, then press the new key; Esc cancels)")
	for a in Settings.ACTIONS:
		var action: String = a[0]
		_key_btns[action] = _row_button(box, a[1], func() -> void:
			_waiting = action
			_show_keys())
	_button(box, "Reset keys", func() -> void:
		Settings.reset_binds()
		_show_keys())
	_heading(box, "Controller  (select one, then press the new button; Menu cancels)")
	for action in Settings.PAD_REBINDABLE:
		var label := ""
		for a in Settings.ACTIONS:
			if a[0] == action:
				label = a[1]
		_pad_btns[action] = _row_button(box, label, func() -> void:
			_waiting_pad = action
			_show_keys())
	_button(box, "Reset controller", func() -> void:
		Settings.reset_pad()
		_show_keys())
	_button(box, "Back", _close_settings)
	_show_quality()
	_show_keys()
	panel.visible = false


func _heading(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(1.0, 0.85, 0.4)
	box.add_child(l)


func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 16)
	row.add_child(l)
	box.add_child(row)
	return row


func _row_button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(action)
	_row(box, text).add_child(b)
	return b


func _slider(box: VBoxContainer, text: String, lo: float, hi: float, value: float, fmt: String, set_fn: Callable) -> void:
	var row := _row(box, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var l := Label.new()
	l.custom_minimum_size = Vector2(56, 0)
	l.text = fmt % value
	row.add_child(l)
	s.value_changed.connect(func(v: float) -> void:
		l.text = fmt % v
		set_fn.call(v)
		_apply())


func _check(box: VBoxContainer, text: String, on: bool, set_fn: Callable) -> void:
	var c := CheckBox.new()
	c.button_pressed = on
	c.text = "On" if on else "Off"
	c.toggled.connect(func(v: bool) -> void:
		c.text = "On" if v else "Off"
		set_fn.call(v)
		_apply())
	_row(box, text).add_child(c)


func _apply() -> void:
	Settings.apply_graphics(get_tree())
	Settings.apply_audio()
	Settings.save_file()


func _cycle_quality() -> void:
	Settings.quality = (Settings.quality + 1) % 3
	_show_quality()
	_apply()


func _show_quality() -> void:
	_quality_btn.text = Settings.QUALITY_NAMES[Settings.quality]


func _show_keys() -> void:
	for action in _key_btns:
		_key_btns[action].text = "Press a key..." if action == _waiting else Settings.key_name(Settings.key_for(action))
	for action in _pad_btns:
		_pad_btns[action].text = "Press a button..." if action == _waiting_pad else Settings.pad_name(action)


func _open_settings() -> void:
	_main_panel.visible = false
	_opt_panel.visible = true
	_focus_first()


func _close_settings() -> void:
	_waiting = ""
	_waiting_pad = ""
	if _opt_panel != null:
		_opt_panel.visible = false
		_main_panel.visible = true
		_show_keys()
		if visible:
			_focus_first()


# --- Records ------------------------------------------------------------------------------------

func _build_records(root: Control, sb: StyleBoxFlat) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	_rec_panel = panel
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Records"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	_rec_grid = GridContainer.new()
	_rec_grid.columns = 2
	_rec_grid.add_theme_constant_override("h_separation", 28)
	box.add_child(_rec_grid)
	_button(box, "Back", _close_records)
	panel.visible = false


## The lines of the Records page: [label, value].
static func record_lines(inv, days: int) -> Array:
	var best := "none yet" if inv.best_day <= 0 else "$%d  (day %d)" % [inv.best_day, inv.best_day_no]
	return [
		["Days on the claim", str(days)],
		["Gold found", "%.2f g" % inv.gold_found],
		["Biggest nugget", "none yet" if inv.biggest_nugget <= 0.0 else "%.2f g" % inv.biggest_nugget],
		["Pans washed", str(inv.pans)],
		["Garnets found", str(inv.garnets_found)],
		["Total earned", "$%d" % inv.earned],
		["Best day's sales", best],
		["Distance walked", "%.1f km" % (inv.walked / 1000.0)],
		["Distance driven", "%.1f km" % (inv.driven / 1000.0)],
	]


func _open_records() -> void:
	for c in _rec_grid.get_children():
		c.queue_free()
	for l in record_lines(main.player.inv, main.day_night.day):
		for i in 2:
			var t := Label.new()
			t.text = l[i]
			t.add_theme_font_size_override("font_size", 18)
			if i == 0:
				t.modulate = Color(1.0, 0.85, 0.4)
			_rec_grid.add_child(t)
	_main_panel.visible = false
	_rec_panel.visible = true
	_focus_first()


func _close_records() -> void:
	if _rec_panel != null and _rec_panel.visible:
		_rec_panel.visible = false
		_main_panel.visible = true
		if visible:
			_focus_first()
