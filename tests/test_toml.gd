extends RefCounted

const Toml = preload("res://tools/toml.gd")

func test_simple_key_values() -> bool:
	var data := Toml.parse("id = \"feed.twin_belt\"\ntier = 2\n")
	return data.get("id") == "feed.twin_belt" and data.get("tier") == 2

func test_section_nesting() -> bool:
	var text := "id = \"x\"\n[cost]\npower = 14\nmass = 8\n"
	var data := Toml.parse(text)
	return data.get("id") == "x" and data["cost"]["power"] == 14 and data["cost"]["mass"] == 8

func test_array_of_strings() -> bool:
	var data := Toml.parse("list = [\"belt\", \"mechanical\"]\n")
	var list: Array = data["list"]
	return list.size() == 2 and list[0] == "belt" and list[1] == "mechanical"

func test_inline_table_with_quoted_key() -> bool:
	var text := "[spawn]\narchetype_weights = { \"drone.swarm\" = 60, \"drone.ranged\" = 40 }\n"
	var data := Toml.parse(text)
	var weights: Dictionary = data["spawn"]["archetype_weights"]
	return weights["drone.swarm"] == 60 and weights["drone.ranged"] == 40

func test_negative_integer() -> bool:
	var data := Toml.parse("thermal = -25\n")
	return data["thermal"] == -25

func test_comment_ignored() -> bool:
	var data := Toml.parse("# a comment\nid = \"x\" # trailing comment\n")
	return data["id"] == "x"
