extends RefCounted

const JsonSchema = preload("res://tools/json_schema.gd")

func test_valid_object_passes() -> bool:
	var schema := {"type": "object", "required": ["id"], "properties": {"id": {"type": "string"}}}
	var errors := JsonSchema.validate({"id": "x"}, schema)
	return errors.size() == 0

func test_missing_required_fails() -> bool:
	var schema := {"type": "object", "required": ["id"]}
	var errors := JsonSchema.validate({}, schema)
	return errors.size() == 1

func test_enum_violation_fails() -> bool:
	var schema := {"type": "string", "enum": ["a", "b"]}
	var errors := JsonSchema.validate("c", schema)
	return errors.size() == 1

func test_nested_property_type_mismatch_fails() -> bool:
	var schema := {"type": "object", "properties": {"tier": {"type": "integer"}}}
	var errors := JsonSchema.validate({"tier": "two"}, schema)
	return errors.size() == 1

func test_array_items_validated() -> bool:
	var schema := {"type": "array", "items": {"type": "integer"}}
	var errors := JsonSchema.validate([1, 2, "x"], schema)
	return errors.size() == 1
