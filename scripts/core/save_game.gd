extends RefCounted
## Reads and writes the save file. main.gd decides what goes in it.

const VERSION := 1

static var path := "user://save.dat"


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func write(data: Dictionary) -> bool:
	data["version"] = VERSION
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("Could not save the game: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_var(data)
	f.close()
	return true


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	if v is Dictionary and (v as Dictionary).get("version", 0) == VERSION:
		return v
	return {}
