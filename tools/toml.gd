class_name Toml
extends RefCounted

## Minimal TOML parser covering the subset /data actually uses: top-level and
## [section]/[section.sub] tables, quoted string keys, strings, integers,
## floats, booleans, arrays, and inline tables. Not a general TOML parser —
## no multi-line arrays, no dotted keys outside inline tables, no dates.

static func parse(text: String) -> Dictionary:
	var root := {}
	var current := root
	for raw_line in text.split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line == "":
			continue
		if line.begins_with("["):
			var header := line.substr(1, line.length() - 2).strip_edges()
			current = _ensure_path(root, header.split("."))
		else:
			var eq_idx := line.find("=")
			if eq_idx == -1:
				continue
			var key := _strip_quotes(line.substr(0, eq_idx).strip_edges())
			var value_str := line.substr(eq_idx + 1).strip_edges()
			current[key] = _parse_value(value_str)
	return root

static func _ensure_path(root: Dictionary, parts: PackedStringArray) -> Dictionary:
	var node := root
	for p in parts:
		var key := _strip_quotes(p.strip_edges())
		if not node.has(key):
			node[key] = {}
		node = node[key]
	return node

static func _strip_comment(line: String) -> String:
	var in_quotes := false
	for i in line.length():
		var c := line[i]
		if c == '"':
			in_quotes = not in_quotes
		elif c == "#" and not in_quotes:
			return line.substr(0, i)
	return line

static func _strip_quotes(s: String) -> String:
	if s.length() >= 2 and s.begins_with('"') and s.ends_with('"'):
		return s.substr(1, s.length() - 2)
	return s

static func _parse_value(raw: String):
	var s := raw.strip_edges()
	if s.begins_with('"'):
		return _strip_quotes(s)
	if s.begins_with("["):
		return _parse_array(s)
	if s.begins_with("{"):
		return _parse_inline_table(s)
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s

## Splits the comma-separated top-level items inside a bracketed/braced
## string, respecting nested brackets/braces and quoted strings.
static func _split_top_level(s: String) -> PackedStringArray:
	var inner := s.substr(1, s.length() - 2)
	var parts: PackedStringArray = []
	var depth := 0
	var in_quotes := false
	var current := ""
	for i in inner.length():
		var c := inner[i]
		if c == '"':
			in_quotes = not in_quotes
		if not in_quotes:
			if c == "[" or c == "{":
				depth += 1
			elif c == "]" or c == "}":
				depth -= 1
		if c == "," and depth == 0 and not in_quotes:
			parts.append(current)
			current = ""
		else:
			current += c
	if current.strip_edges() != "":
		parts.append(current)
	return parts

static func _parse_array(s: String) -> Array:
	var result := []
	for part in _split_top_level(s):
		result.append(_parse_value(part.strip_edges()))
	return result

static func _parse_inline_table(s: String) -> Dictionary:
	var result := {}
	for part in _split_top_level(s):
		var eq := part.find("=")
		var k := _strip_quotes(part.substr(0, eq).strip_edges())
		var v = _parse_value(part.substr(eq + 1).strip_edges())
		result[k] = v
	return result
