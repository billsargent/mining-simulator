extends SceneTree
## Crash safety of the save file: a half-written or damaged save never loses the last good one.
## Run: godot --headless --path . --script res://tests/test_save.gd

const SaveGame = preload("res://scripts/core/save_game.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("SAVETEST %-48s %s" % [name, "ok" if ok else "FAIL"])
	if not ok:
		_fails += 1


func _garbage(p: String, n: int) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	for i in n:
		f.store_8(randi() % 256)
	f.close()


func _truncate(p: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length() / 2)
	f.close()
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _init() -> void:
	SaveGame.path = "user://test_crash_save.dat"
	SaveGame.delete()
	var big := PackedFloat32Array()
	big.resize(20000)
	_check("first save writes", SaveGame.write({"day": 1, "big": big}))
	_check("second save writes", SaveGame.write({"day": 2, "big": big}))
	_check("reads the newest", SaveGame.read().get("day") == 2)

	# A crash while writing leaves a half-written temporary file; the save is untouched.
	_garbage(SaveGame.path + ".tmp", 5000)
	_check("a half-written new save is ignored", SaveGame.read().get("day") == 2)

	# The save itself cut short (power cut while the disk was flushing): the backup answers.
	_truncate(SaveGame.path)
	_check("a cut-short save falls back to the last one", SaveGame.read().get("day") == 1)
	_garbage(SaveGame.path, 3000)
	_check("a garbled save falls back too", SaveGame.read().get("day") == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path))
	_check("a missing save falls back too", SaveGame.read().get("day") == 1 and SaveGame.exists())

	# Saving again after all that works and is read first.
	_check("saving again works", SaveGame.write({"day": 3}) and SaveGame.read().get("day") == 3)
	_check("no temporary file left behind", not FileAccess.file_exists(SaveGame.path + ".tmp"))
	SaveGame.delete()
	_check("delete removes save and backup", not SaveGame.exists())
	print("SAVETEST complete: %d failed" % _fails)
	quit(1 if _fails > 0 else 0)
