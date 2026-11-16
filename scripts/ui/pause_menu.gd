extends CanvasLayer
## Esc menu: resume, save, start over, quit.

var main
var _new_btn: Button
var _save_btn: Button
var _confirm_t := 0.0
var _saved_t := 0.0


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
	_new_btn = _button(box, "Start a new game", _new_game)
	_button(box, "Save and quit", _quit)
	var note := Label.new()
	note.text = "The game also saves itself every minute and when you quit."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	visible = false


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	box.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		if visible:
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
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.player.grace()


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
