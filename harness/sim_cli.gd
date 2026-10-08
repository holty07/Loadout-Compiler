extends SceneTree

## godot --headless --script harness/sim_cli.gd -- run --seed 1234 --loadout fixtures/basic.json
##
## Loads /data, assembles the loadout named in the fixture JSON
## ({"modules": [...]}), and runs it to completion via sim/run.gd.

const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")
const EventLog = preload("res://sim/log.gd")

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.get("command", "") != "run":
		printerr("usage: sim_cli.gd run --seed <int> --loadout <path>")
		quit(1)
		return

	var seed_val := int(args.get("seed", "0"))
	var loadout_path: String = args.get("loadout", "")
	var verbose: bool = args.has("verbose")

	var module_ids: Array = []
	if loadout_path != "":
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(loadout_path)) == OK:
			var spec: Dictionary = json.data
			module_ids = spec.get("modules", [])

	var data := DataLoader.load_all()
	var result := Run.execute(seed_val, module_ids, [], data)

	print("sim_version=%s" % FileAccess.get_file_as_string("res://sim/VERSION").strip_edges())
	print("seed=%d" % seed_val)
	if not result["ok"]:
		print("log_hash=none")
		print("outcome=error")
		print("depth=0")
		print("choke=none")
		if verbose:
			print("errors=%s" % str(result["errors"]))
		quit(0)
		return

	var log: EventLog = result["log"]
	print("log_hash=%s" % log.log_hash())
	print("outcome=%s" % String(result["outcome"]))
	print("depth=%d" % int(result["depth"]))
	print("choke=none")

	if verbose:
		print("loadout=%s" % str(module_ids))
		print("records=%d" % log.records.size())

	quit(0)

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	if raw.size() > 0 and not raw[0].begins_with("--"):
		result["command"] = raw[0]
		i = 1
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
