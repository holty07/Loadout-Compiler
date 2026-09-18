class_name JsonSchema
extends RefCounted

## Minimal JSON Schema validator: type, enum, required, properties, items,
## minItems. Enough to cover tools/schema/*.json — not a general validator.
## Returns a list of error strings; empty means valid.

static func validate(data, schema: Dictionary, path: String = "$") -> Array:
	var errors: Array = []
	if schema.has("type"):
		if not _matches_type(data, schema["type"]):
			errors.append("%s: expected type %s" % [path, schema["type"]])
			return errors
	if schema.has("enum"):
		var allowed: Array = schema["enum"]
		if not allowed.has(data):
			errors.append("%s: value %s not in %s" % [path, str(data), str(allowed)])
	if data is Dictionary:
		if schema.has("required"):
			for key in schema["required"]:
				if not data.has(key):
					errors.append("%s: missing required field '%s'" % [path, key])
		if schema.has("properties"):
			var props: Dictionary = schema["properties"]
			for key in props.keys():
				if data.has(key):
					errors.append_array(validate(data[key], props[key], "%s.%s" % [path, key]))
	if data is Array:
		if schema.has("items"):
			for i in data.size():
				errors.append_array(validate(data[i], schema["items"], "%s[%d]" % [path, i]))
		if schema.has("minItems") and data.size() < int(schema["minItems"]):
			errors.append("%s: expected at least %d items" % [path, schema["minItems"]])
	return errors

static func _matches_type(data, t: String) -> bool:
	match t:
		"string":
			return data is String
		"integer":
			return data is int
		"number":
			return data is int or data is float
		"array":
			return data is Array
		"object":
			return data is Dictionary
		"boolean":
			return data is bool
		_:
			return true
