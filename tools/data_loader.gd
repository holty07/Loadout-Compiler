class_name DataLoader
extends RefCounted

## Loads /data into the Dictionaries sim/ takes as arguments. Lives under
## tools/ (not sim/) because it does file I/O, which the lint forbids under
## sim/ — sim/ only ever receives already-parsed data.

const Toml = preload("res://tools/toml.gd")

static func load_all(base_path: String = "res://data") -> Dictionary:
	return {
		"modules": _load_indexed("%s/modules" % base_path),
		"enemies": _load_indexed("%s/enemies" % base_path),
		"rooms": _load_list("%s/rooms" % base_path),
		"tuning": _load_file("%s/tuning.toml" % base_path),
	}

static func _load_indexed(dir_path: String) -> Dictionary:
	var result := {}
	for path in _list_toml(dir_path):
		var def := Toml.parse(FileAccess.get_file_as_string(path))
		if def.has("id"):
			result[def["id"]] = def
	return result

static func _load_list(dir_path: String) -> Array:
	var result := []
	for path in _list_toml(dir_path):
		result.append(Toml.parse(FileAccess.get_file_as_string(path)))
	return result

static func _load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return Toml.parse(FileAccess.get_file_as_string(path))

## Sorted so load order never depends on filesystem iteration order.
static func _list_toml(dir_path: String) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".toml"):
			files.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files
