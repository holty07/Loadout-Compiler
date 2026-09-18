extends SceneTree

## godot --headless --script harness/sim_cli.gd -- run --seed 1234 --loadout fixtures/basic.json
##
## M0 placeholder: no game rules exist yet (pipeline/encounter/facility land
## in M1). This still exercises Rng + EventLog + hashing end to end, so the
## CI determinism probe has a real, reproducible hash to compare across
## consecutive runs and across x86/ARM. Replaced by the real run loop at M1.

const Rng = preload("res://sim/rng.gd")
const EventLog = preload("res://sim/log.gd")

const SIM_VERSION := 1

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.get("command", "") != "run":
		printerr("usage: sim_cli.gd run --seed <int> --loadout <path>")
		quit(1)
		return

	var seed_val := int(args.get("seed", "0"))
	var loadout_path: String = args.get("loadout", "")
	var verbose: bool = args.has("verbose")

	var loadout := {}
	if loadout_path != "":
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(loadout_path)) == OK:
			loadout = json.data

	var rng := Rng.new(seed_val)
	var log := EventLog.new()
	for tick in range(100):
		log.append(tick, "placeholder_tick", "sim", {"draw": rng.next_below(1000)})

	print("sim_version=%d" % SIM_VERSION)
	print("seed=%d" % seed_val)
	print("log_hash=%s" % log.log_hash())
	print("outcome=none")
	print("depth=0")
	print("choke=none")

	if verbose:
		print("loadout=%s" % str(loadout))
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
