extends RefCounted
## Player options. Kept in their own small file, apart from the save, so they survive starting
## a new game. Test runs (any command-line flag) neither read nor write the file.

const PATH := "user://settings.cfg"

static var hazards := true          # mine hazards: lamp batteries, bad air, rotten ground
static var persist := true
static var grab_mouse := true       # off for test and screenshot runs, so they never take the mouse


## Capture the mouse for looking around (skipped in test runs).
static func capture_mouse() -> void:
	if grab_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True while the game should treat the mouse as captured. Test runs always count as captured.
static func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not grab_mouse


static func load_file() -> void:
	hazards = true
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		hazards = cfg.get_value("game", "hazards", true)


static func save_file() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hazards", hazards)
	cfg.save(PATH)
