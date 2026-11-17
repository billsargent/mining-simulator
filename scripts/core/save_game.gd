extends RefCounted
## Reads and writes the save file. main.gd decides what goes in it.
## Version 3: the 8 km world. Saves from the earlier, smaller worlds are not carried over:
## reading one returns nothing, so the game starts fresh.

const VERSION := 3

static var path := "user://save.dat"


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func write(data: Dictionary) -> bool:
	data["version"] = VERSION
	# Write to a temporary file first, so a crash mid-write never ruins the last good save.
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("Could not save the game: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_var(data)
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return true


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	if v is Dictionary and int((v as Dictionary).get("version", 0)) == VERSION:
		return v
	return {}
