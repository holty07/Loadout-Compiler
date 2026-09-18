extends SceneTree

## godot --headless --script tools/lint.gd
## Scans sim/ for banned engine symbols. Exits non-zero on any hit.

const LintCore = preload("res://tools/lint_core.gd")

func _init() -> void:
	var violations := LintCore.scan("res://sim")
	for v in violations:
		print(v)
	print("lint: %d violation(s) in sim/" % violations.size())
	quit(1 if violations.size() > 0 else 0)
