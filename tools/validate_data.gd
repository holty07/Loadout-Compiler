extends SceneTree

## godot --headless --script tools/validate_data.gd
## Validates every /data/{modules,enemies,rooms}/*.toml file against its
## JSON Schema in tools/schema/. Exits non-zero on any validation error.

const Toml = preload("res://tools/toml.gd")
const JsonSchema = preload("res://tools/json_schema.gd")

func _init() -> void:
	var categories := {
		"modules": "res://tools/schema/module.json",
		"enemies": "res://tools/schema/enemy.json",
		"rooms": "res://tools/schema/room.json",
	}
	var total_files := 0
	var total_errors := 0
	for category in categories.keys():
		var schema := _load_schema(categories[category])
		var dir_path := "res://data/%s" % category
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".toml"):
				total_files += 1
				var full_path := "%s/%s" % [dir_path, file_name]
				var data := Toml.parse(FileAccess.get_file_as_string(full_path))
				var errors := JsonSchema.validate(data, schema)
				if errors.size() > 0:
					total_errors += errors.size()
					print("INVALID %s:" % full_path)
					for e in errors:
						print("  " + e)
			file_name = dir.get_next()
		dir.list_dir_end()
	print("validate_data: %d file(s) checked, %d error(s)" % [total_files, total_errors])
	quit(1 if total_errors > 0 else 0)

func _load_schema(path: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("failed to parse schema %s" % path)
		return {}
	return json.data
