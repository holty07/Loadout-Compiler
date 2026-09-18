extends SceneTree

## godot --headless --script tools/run_tests.gd
## Discovers every tests/test_*.gd file, instantiates it, and calls every
## method named test_*. A test passes by returning true. Exits non-zero if
## any test fails.

func _init() -> void:
	var files := _find_test_files("res://tests")
	files.sort()
	var total := 0
	var failed := 0
	for file_path in files:
		var script := load(file_path)
		var instance = script.new()
		var method_names: Array = []
		for m in instance.get_method_list():
			var name: String = m["name"]
			if name.begins_with("test_"):
				method_names.append(name)
		method_names.sort()
		for method_name in method_names:
			total += 1
			var ok = instance.call(method_name)
			if ok:
				print("PASS %s::%s" % [file_path, method_name])
			else:
				failed += 1
				print("FAIL %s::%s" % [file_path, method_name])
	print("run_tests: %d passed, %d failed, %d total" % [total - failed, failed, total])
	quit(1 if failed > 0 else 0)

func _find_test_files(path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				results.append_array(_find_test_files(full))
			elif entry.begins_with("test_") and entry.ends_with(".gd"):
				results.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return results
