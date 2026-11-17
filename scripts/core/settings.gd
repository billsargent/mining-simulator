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
]
const QUALITY_NAMES := ["Low", "Medium", "High"]

static var hazards := true          # mine hazards: lamp batteries, bad air, rotten ground
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

static var _env: Environment
static var _sun: DirectionalLight3D


## Capture the mouse for looking around (skipped in test runs).
static func capture_mouse() -> void:
	if grab_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True while the game should treat the mouse as captured. Test runs always count as captured.
static func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not grab_mouse


static func _defaults() -> void:
	hazards = true
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


static func load_file() -> void:
	_defaults()
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	hazards = cfg.get_value("game", "hazards", true)
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


static func save_file() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hazards", hazards)
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "binds", binds)
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


## Put every rebindable action on its current key.
static func apply_binds() -> void:
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
	if binds.is_empty():
		return k
	for a in ACTIONS:
		if key_name(a[2]) == k:
			return key_name(key_for(a[0]))
	return k


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
	var k := func(a: String) -> String: return key_name(key_for(a))
	var move: String = k.call("move_forward") + k.call("move_left") + k.call("move_back") + k.call("move_right")
	if driving:
		return "%s/%s drive   %s/%s steer   %s brake   %s camera   %s flip upright   %s get out   %s map   Esc menu" % [
			k.call("move_forward"), k.call("move_back"), k.call("move_left"), k.call("move_right"), k.call("jump"),
			k.call("camera"), k.call("dump"), k.call("interact"), k.call("map")]
	return "%s move   %s sprint   %s jump   LMB dig   %s use / pan   %s carry   Wheel adjust   %s dump bucket   %s map   %s headlamp   Esc menu" % [
		move, k.call("sprint"), k.call("jump"), k.call("interact"), k.call("carry"), k.call("dump"), k.call("map"), k.call("headlamp")]
