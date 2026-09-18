extends SceneTree

## godot --headless --script tools/dump_log.gd -- --seed <int> --loadout <path>
##
## Prints a run's full event log as readable lines, one event per line. This
## is the tool for docs/plan.md's M1 "legibility test": read a log as raw
## text and see whether you can reconstruct what happened. If you can't, the
## run report at M5 (derived from the same records) won't be legible either.

const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var seed_val := int(args.get("seed", "0"))
	var loadout_path: String = args.get("loadout", "")

	var module_ids: Array = []
	if loadout_path != "":
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(loadout_path)) == OK:
			var spec: Dictionary = json.data
			module_ids = spec.get("modules", [])

	var data := DataLoader.load_all()
	var result := Run.execute(seed_val, module_ids, [], data)
	if not result["ok"]:
		printerr("assembly failed: %s" % str(result["errors"]))
		quit(1)
		return

	print("seed=%d loadout=%s" % [seed_val, str(module_ids)])
	print("outcome=%s depth=%d integrity=%d" % [String(result["outcome"]), int(result["depth"]), int(result["player_integrity"])])
	print("---")

	var log = result["log"]
	for r in log.records:
		var payload: Dictionary = r["payload"]
		var keys := payload.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%s=%s" % [k, str(payload[k])])
		print("tick=%-6d kind=%-14s subject=%-22s %s" % [int(r["tick"]), String(r["kind"]), String(r["subject"]), "&".join(parts)])

	quit(0)

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < raw.size():
		var token: String = raw[i]
		if token.begins_with("--"):
			var key := token.substr(2)
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				result[key] = raw[i + 1]
				i += 2
			else:
				result[key] = true
				i += 1
		else:
			i += 1
	return result
