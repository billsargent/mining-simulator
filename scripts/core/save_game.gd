extends RefCounted
## Reads and writes the save file. main.gd decides what goes in it.
## Version 3: the 8 km world. Saves from the earlier, smaller worlds are not carried over:
## reading one returns nothing, so the game starts fresh.
##
## Crash safety: a save is written to a temporary file and read back before it replaces
## anything. The save it replaces is kept as a backup, and if the main file is ever damaged
## (a crash or power cut at the wrong moment), reading falls back to the backup.

const VERSION := 3

static var path := "user://save.dat"


static func _bak() -> String:
	return path + ".bak"


static func _tmp() -> String:
	return path + ".tmp"


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


static func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(_bak())


static func delete() -> void:
	for p in [path, _bak(), _tmp()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(_abs(p))


static func write(data: Dictionary) -> bool:
	data["version"] = VERSION
	var tmp := _tmp()
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("Could not save the game: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_var(data)
	var err := f.get_error()
	f.close()
	# Only a file that reads back whole may replace the last good save.
	if err != OK or _load(tmp).is_empty():
		push_warning("Could not save the game: the new save did not read back.")
		DirAccess.remove_absolute(_abs(tmp))
		return false
	# The current save becomes the backup, unless it is damaged: then the old backup stays.
	if FileAccess.file_exists(path) and _load(path).is_empty():
		DirAccess.remove_absolute(_abs(path))
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(_bak()):
			DirAccess.remove_absolute(_abs(_bak()))
		DirAccess.rename_absolute(_abs(path), _abs(_bak()))
	if DirAccess.rename_absolute(_abs(tmp), _abs(path)) != OK:
		push_warning("Could not save the game: could not move the new save into place.")
		return false
	return true


## The save, or the backup if the save is missing or damaged; {} if neither is usable.
static func read() -> Dictionary:
	var d := _load(path)
	if d.is_empty():
		d = _load(_bak())
	return d


static func _load(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	if v is Dictionary and int((v as Dictionary).get("version", 0)) == VERSION:
		return v
	return {}
