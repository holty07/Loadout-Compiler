extends RefCounted

## A lint nobody has seen fail is a lint that silently stopped working three
## months ago — this test plants a real violation and asserts LintCore
## (the exact code tools/lint.gd runs) rejects it.

const LintCore = preload("res://tools/lint_core.gd")

func test_lint_catches_planted_randf() -> bool:
	var tmp_dir := "user://lint_test_violation"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var bad_path := tmp_dir + "/planted.gd"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc bad() -> float:\n\treturn randf()\n")
	f.close()

	var violations := LintCore.scan(tmp_dir)

	DirAccess.remove_absolute(bad_path)
	DirAccess.remove_absolute(tmp_dir)

	if violations.size() == 0:
		print("  lint failed to catch a planted randf()")
		return false
	return true

func test_lint_passes_clean_file() -> bool:
	var tmp_dir := "user://lint_test_clean"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var clean_path := tmp_dir + "/clean.gd"
	var f := FileAccess.open(clean_path, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc good() -> int:\n\treturn 1 + 1\n")
	f.close()

	var violations := LintCore.scan(tmp_dir)

	DirAccess.remove_absolute(clean_path)
	DirAccess.remove_absolute(tmp_dir)

	return violations.size() == 0
