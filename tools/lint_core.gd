class_name LintCore
extends RefCounted

## Scan logic shared by tools/lint.gd and tests/test_lint.gd, so the test
## exercises the exact detection code the CI lint step runs.

const BANNED_WORDS := [
	"Node", "Engine", "Time", "OS", "Input",
	"randf", "randi", "randomize",
	"FileAccess", "DirAccess",
]
const BANNED_SUBSTRINGS := ["res://shell"]

static func scan(path: String) -> Array:
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
				results.append_array(scan(full))
			elif entry.ends_with(".gd"):
				results.append_array(_scan_file(full))
		entry = dir.get_next()
	dir.list_dir_end()
	return results

static func _scan_file(path: String) -> Array:
	var results: Array = []
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		for word in BANNED_WORDS:
			if _contains_word(line, word):
				results.append("%s:%d: banned symbol '%s'" % [path, i + 1, word])
		for sub in BANNED_SUBSTRINGS:
			if line.find(sub) != -1:
				results.append("%s:%d: banned path reference '%s'" % [path, i + 1, sub])
	return results

static func _contains_word(line: String, word: String) -> bool:
	var regex := RegEx.new()
	regex.compile("\\b%s\\b" % word)
	return regex.search(line) != null
