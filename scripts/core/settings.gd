extends RefCounted
## Player options. Kept in their own small file, apart from the save, so they survive starting
## a new game. Test runs (any command-line flag) neither read nor write the file.

const PATH := "user://settings.cfg"

## Rebindable actions, in menu order: [action, label, default key].
const ACTIONS := [
	["move_forward", "Walk forward", KEY_W], ["move_back", "Walk back", KEY_S],
	["move_left", "Step left", KEY_A], ["move_right", "Step right", KEY_D],
	["sprint", "Run", KEY_SHIFT], ["jump", "Jump", KEY_SPACE],
	["interact", "Use", KEY_E], ["carry", "Carry / pick up", KEY_F],
	["dump", "Dump bucket", KEY_R], ["pan_dump", "Tip the pan", KEY_Q],
	["camera", "Camera view", KEY_V], ["map", "Map", KEY_M], ["headlamp", "Headlamp", KEY_L],
	["inventory", "Inventory", KEY_TAB],
]
const QUALITY_NAMES := ["Low", "Medium", "High"]

static var hazards := true          # mine hazards: lamp batteries, bad air, rotten ground
static var check_updates := true   # ask GitHub once at start for a newer release
static var persist := true
static var grab_mouse := true       # off for test and screenshot runs, so they never take the mouse
static var mouse_sens := 1.0        # multiplier on the base look speed
static var invert_y := false
static var fov := 75.0
static var quality := 2             # 0 low, 1 medium, 2 high
static var render_scale := 1.0
static var fullscreen := false
static var vsync := true
static var volume := 0.8
static var music_volume := 0.6
static var binds := {}              # action -> physical keycode, only where changed
static var pad_binds := {}          # action -> controller button, only where changed

static var _env: Environment
static var _sun: DirectionalLight3D


## Capture the mouse for looking around (skipped in test runs).
static func capture_mouse() -> void:
	if grab_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True while the game should treat the mouse as captured. Test runs always count as captured.
static func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not grab_mouse or using_pad


static func _defaults() -> void:
	hazards = true
	check_updates = true
	mouse_sens = 1.0
	invert_y = false
	fov = 75.0
	quality = 2
	render_scale = 1.0
	fullscreen = false
	vsync = true
	volume = 0.8
	music_volume = 0.6
	binds = {}
	pad_binds = {}


static func load_file() -> void:
	_defaults()
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	hazards = cfg.get_value("game", "hazards", true)
	check_updates = cfg.get_value("game", "check_updates", true)
	mouse_sens = clampf(cfg.get_value("controls", "mouse_sens", 1.0), 0.2, 3.0)
	invert_y = cfg.get_value("controls", "invert_y", false)
	fov = clampf(cfg.get_value("graphics", "fov", 75.0), 60.0, 100.0)
	quality = clampi(cfg.get_value("graphics", "quality", 2), 0, 2)
	render_scale = clampf(cfg.get_value("graphics", "render_scale", 1.0), 0.5, 1.0)
	fullscreen = cfg.get_value("graphics", "fullscreen", false)
	vsync = cfg.get_value("graphics", "vsync", true)
	volume = clampf(cfg.get_value("audio", "volume", 0.8), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", 0.6), 0.0, 1.0)
	var b = cfg.get_value("controls", "binds", {})
	binds = b if b is Dictionary else {}
	var pb = cfg.get_value("controls", "pad_binds", {})
	pad_binds = pb if pb is Dictionary else {}


static func save_file() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hazards", hazards)
	cfg.set_value("game", "check_updates", check_updates)
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "binds", binds)
	cfg.set_value("controls", "pad_binds", pad_binds)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.save(PATH)


# --- Keys ---------------------------------------------------------------------------------------

static func default_key(action: String) -> int:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return KEY_NONE


static func key_for(action: String) -> int:
	return int(binds.get(action, default_key(action)))


static func key_name(code: int) -> String:
	return OS.get_keycode_string(code)


## Xbox-layout controller buttons: action -> [event, label]. Fixed; not rebindable.
## An event is a JoyButton, or [axis, direction] for a stick or trigger.
static func _pad_map() -> Dictionary:
	return {
		"move_forward": [[JOY_AXIS_LEFT_Y, -1.0], "Left stick"], "move_back": [[JOY_AXIS_LEFT_Y, 1.0], "Left stick"],
		"move_left": [[JOY_AXIS_LEFT_X, -1.0], "Left stick"], "move_right": [[JOY_AXIS_LEFT_X, 1.0], "Left stick"],
		"sprint": [JOY_BUTTON_LEFT_STICK, "LS"], "jump": [JOY_BUTTON_A, "A"],
		"interact": [JOY_BUTTON_X, "X"], "carry": [JOY_BUTTON_Y, "Y"],
		"dump": [JOY_BUTTON_B, "B"], "pan_dump": [JOY_BUTTON_B, "B"],
		"camera": [JOY_BUTTON_RIGHT_STICK, "RS"], "map": [JOY_BUTTON_BACK, "View"],
		"headlamp": [JOY_BUTTON_DPAD_UP, "D-pad up"], "toggle_mouse": [JOY_BUTTON_START, "Menu"],
		"dig": [[JOY_AXIS_TRIGGER_RIGHT, 1.0], "RT"], "pan_wash": [[JOY_AXIS_TRIGGER_LEFT, 1.0], "LT"],
		"scroll_up": [JOY_BUTTON_DPAD_RIGHT, "D-pad"], "scroll_down": [JOY_BUTTON_DPAD_LEFT, "D-pad"],
		# Driving: left trigger forward, right trigger reverse; Y works the excavator.
		"drive_gas": [[JOY_AXIS_TRIGGER_LEFT, 1.0], "LT"], "drive_reverse": [[JOY_AXIS_TRIGGER_RIGHT, 1.0], "RT"],
		"scoop": [JOY_BUTTON_Y, "Y"],
		# Tools: LB and RB step through the hotbar; D-pad down shows what you carry.
		"tool_prev": [JOY_BUTTON_LEFT_SHOULDER, "LB"], "tool_next": [JOY_BUTTON_RIGHT_SHOULDER, "RB"],
		"inventory": [JOY_BUTTON_DPAD_DOWN, "D-pad down"],
	}


## True while the player is using a controller (the last input came from one). Prompts and the
## help line then show controller buttons.
static var using_pad := false
const PAD_LOOK := 2.8           # right stick look speed, radians a second at full tilt
const STICK_DEAD := 0.18


## Watch each input to tell whether the player is on the controller or the keyboard and mouse.
## Returns true when that changed.
static func note_input(event: InputEvent) -> bool:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		pad = false
	if pad == using_pad:
		return false
	using_pad = pad
	return true


## The controller to read sticks from: the first one connected (Windows may not number it 0).
static func pad_device() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else 0


## The right stick, with a dead zone, curved for fine aim; zero when no controller is in use.
static func stick_look() -> Vector2:
	var d := pad_device()
	var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
	var l := v.length()
	if l < STICK_DEAD:
		return Vector2.ZERO
	var m := minf((l - STICK_DEAD) / (1.0 - STICK_DEAD), 1.0)
	return v / l * m * m


## Radians to turn this frame from the right stick.
static func pad_look(delta: float) -> Vector2:
	var s := stick_look() * PAD_LOOK * mouse_sens * delta
	if invert_y:
		s.y = -s.y
	return s


## Controller actions the player may move to another button, in menu order. The pan's dump
## follows the bucket's dump; the sticks, triggers, D-pad and Menu stay put.
const PAD_REBINDABLE := ["jump", "interact", "carry", "dump", "sprint", "camera", "map", "headlamp", "inventory"]
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func button_name(b: int) -> String:
	return BUTTON_NAMES.get(b, "Button %d" % b)


## The controller button an action is on now (-1 for a stick or trigger).
static func pad_button_for(action: String) -> int:
	if action == "pan_dump":
		action = "dump"
	if pad_binds.has(action):
		return int(pad_binds[action])
	var m := _pad_map()
	if m.has(action) and not (m[action][0] is Array):
		return int(m[action][0])
	return -1


static func pad_name(action: String) -> String:
	var b := pad_button_for(action)
	if b >= 0:
		return button_name(b)
	var m := _pad_map()
	return m[action][1] if m.has(action) else ""


## Move a controller action to another button. A button another action uses is swapped onto it.
static func rebind_pad(action: String, button: int) -> void:
	var old := pad_button_for(action)
	for a in PAD_REBINDABLE:
		if a != action and pad_button_for(a) == button:
			_set_pad_bind(a, old)
	_set_pad_bind(action, button)
	apply_binds()
	save_file()


static func _set_pad_bind(action: String, button: int) -> void:
	var m := _pad_map()
	if int(m[action][0]) == button:
		pad_binds.erase(action)
	else:
		pad_binds[action] = button


static func reset_pad() -> void:
	pad_binds = {}
	apply_binds()
	save_file()


## Throttle while driving, -1 (full reverse) to 1: the move keys or left stick, plus the triggers.
static func drive_input() -> float:
	var t := Input.get_axis("move_back", "move_forward")
	t += Input.get_action_strength("drive_gas") - Input.get_action_strength("drive_reverse")
	return clampf(t, -1.0, 1.0)


## Put every rebindable action on its current key, and every action on its controller button.
static func apply_binds() -> void:
	_apply_keys()
	# Godot's own menu actions only know the keyboard: A presses a menu button, B goes back.
	for ui in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		if not InputMap.action_get_events(ui[0]).any(func(e): return e is InputEventJoypadButton):
			var ub := InputEventJoypadButton.new()
			ub.device = -1
			ub.button_index = ui[1]
			InputMap.action_add_event(ui[0], ub)
	var m := _pad_map()
	for action in m:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
		var spec = m[action][0]
		if not (spec is Array):
			spec = pad_button_for(action)
		if spec is Array:
			var jm := InputEventJoypadMotion.new()
			jm.device = -1          # any controller, whichever slot Windows gives it
			jm.axis = spec[0]
			jm.axis_value = spec[1]
			InputMap.action_add_event(action, jm)
		else:
			var jb := InputEventJoypadButton.new()
			jb.device = -1
			jb.button_index = spec
			InputMap.action_add_event(action, jb)
		InputMap.action_set_deadzone(action, 0.25)


static func _apply_keys() -> void:
	for a in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var ev := InputEventKey.new()
		ev.physical_keycode = key_for(action) as Key
		InputMap.action_add_event(action, ev)


## Rebind an action. A key already used by another action is swapped onto it.
static func rebind(action: String, code: int) -> void:
	var old := key_for(action)
	for a in ACTIONS:
		if a[0] != action and key_for(a[0]) == code:
			_set_bind(a[0], old)
	_set_bind(action, code)
	apply_binds()
	save_file()


static func _set_bind(action: String, code: int) -> void:
	if code == default_key(action):
		binds.erase(action)
	else:
		binds[action] = code


static func reset_binds() -> void:
	binds = {}
	apply_binds()
	save_file()


## The label for a prompt key. Prompts are written with the default key ("E"); this shows the
## key the player actually has it on.
static func prompt_key(k: String) -> String:
	if using_pad:
		match k:
			"Left mouse": return "RT"
			"Right mouse": return "LT"
			"Wheel": return "D-pad left/right"
		for a in ACTIONS:
			if key_name(a[2]) == k:
				return pad_name(a[0])
		return k
	if binds.is_empty():
		return k
	for a in ACTIONS:
		if key_name(a[2]) == k:
			return key_name(key_for(a[0]))
	return k


## Free text (toasts, goals, notes, catalog lines) names mouse buttons and keys in words; on the
## controller this swaps them for the pad buttons from `_pad_map()`.
static func pad_words(text: String) -> String:
	if not using_pad:
		return text
	for w in ["left mouse", "Left mouse"]:
		text = text.replace(w, pad_name("dig"))
	for w in ["right mouse", "Right mouse"]:
		text = text.replace(w, pad_name("pan_wash"))
	for n in range(1, 9):
		text = text.replace("(%d)" % n, "(LB/RB)")      # hotbar slots
	for a in ACTIONS:
		var k := key_name(a[2])
		text = text.replace("(%s)" % k, "(%s)" % pad_name(a[0]))
		if k.length() == 1:
			text = text.replace("%s or walk away" % k, "%s or walk away" % pad_name(a[0]))
	return text.replace("(left click)", "(A)")      # the map drops a waypoint with A


# --- Graphics -----------------------------------------------------------------------------------

## Remember the environment and sun so quality changes can reach them.
static func attach(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun


static func apply_graphics(tree: SceneTree) -> void:
	if _env != null:
		_env.ssao_enabled = quality >= 2
		_env.glow_enabled = quality >= 1
	if _sun != null:
		_sun.shadow_enabled = quality >= 1
		_sun.directional_shadow_max_distance = 160.0 if quality >= 2 else 80.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality >= 2 else 2048, true)
	var vp := tree.root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED
	if not persist:
		return     # test runs keep their window as given
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	for cam in tree.get_nodes_in_group("fov_camera"):
		cam.fov = fov


## How far around you grass grows: the biggest cost after shadows.
static func grass_radius() -> float:
	return [32.0, 45.0, 60.0][quality]


static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.0001)))


static func look_speed() -> float:
	return 0.0022 * mouse_sens


## The key help line at the bottom of the screen, on the player's current keys.
static func help(driving: bool) -> String:
	if using_pad:
		var n := func(a: String) -> String: return pad_name(a)
		if driving:
			return "LT forward   RT reverse   Left stick steer   %s brake   %s camera   %s flip upright   %s get out   %s map   Menu pause" % [
				n.call("jump"), n.call("camera"), n.call("dump"), n.call("interact"), n.call("map")]
		return "Left stick move   Right stick look   %s sprint   %s jump   RT use tool   LB/RB tools   %s use / pan   %s carry   D-pad adjust   %s dump bucket   %s map   %s headlamp   %s inventory   Menu pause" % [
			n.call("sprint"), n.call("jump"), n.call("interact"), n.call("carry"), n.call("dump"), n.call("map"), n.call("headlamp"), n.call("inventory")]
	var k := func(a: String) -> String: return key_name(key_for(a))
	var move: String = k.call("move_forward") + k.call("move_left") + k.call("move_back") + k.call("move_right")
	if driving:
		return "%s/%s drive   %s/%s steer   %s brake   %s camera   %s flip upright   %s get out   %s map   Esc menu" % [
			k.call("move_forward"), k.call("move_back"), k.call("move_left"), k.call("move_right"), k.call("jump"),
			k.call("camera"), k.call("dump"), k.call("interact"), k.call("map")]
	return "%s move   %s sprint   %s jump   LMB use tool   1-8 tools   %s use / pan   %s carry   %s dump bucket   %s map   %s headlamp   %s inventory   Esc menu" % [
		move, k.call("sprint"), k.call("jump"), k.call("interact"), k.call("carry"), k.call("dump"), k.call("map"), k.call("headlamp"), k.call("inventory")]
