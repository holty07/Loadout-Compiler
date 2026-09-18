extends SceneTree

## godot --headless --script harness/sweep_worker.gd -- --matrix <path> --seeds <int> \
##     --shard-index <int> --shard-count <int> --out <partial.json>
##
## Runs one shard of the loadout matrix (every Nth loadout, round-robin by
## --shard-count) across --seeds seeds each, sparse-logged for speed (see
## sim/log.gd's SparseEventLog and the M2 design notes in docs/M2.md), and
## writes one partial report as JSON. harness/sweep.gd spawns one of these
## per core and merges the partials — not meant to be run by hand, though
## nothing stops you pointing it at a single shard (--shard-count 1) to
## debug one loadout in isolation.

const Toml = preload("res://tools/toml.gd")
const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")
const Rng = preload("res://sim/rng.gd")
const Report = preload("res://harness/report.gd")

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var matrix_path: String = args.get("matrix", "harness/loadouts.toml")
	var seeds := int(args.get("seeds", "2000"))
	var shard_index := int(args.get("shard-index", "0"))
	var shard_count: int = max(1, int(args.get("shard-count", "1")))
	var out_path: String = args.get("out", "")

	var data := DataLoader.load_all()
	var modules_by_id: Dictionary = data["modules"]

	var parsed := Toml.parse(FileAccess.get_file_as_string(matrix_path))
	var loadouts: Dictionary = parsed.get("loadout", {})
	var keys: Array = loadouts.keys()
	keys.sort()

	var results: Array = []
	var shard_acc := Report.new_accumulator()

	for i in keys.size():
		if i % shard_count != shard_index:
			continue
		var key: String = keys[i]
		var modules: Array = (loadouts[key] as Dictionary)["modules"]

		var acc := Report.new_accumulator()
		var rng := Rng.new(key.hash())
		for s in seeds:
			var seed_val := rng.next_below(2000000000)
			var result := Run.execute(seed_val, modules, [], data, true)
			Report.ingest(acc, result, modules_by_id)
			Report.ingest(shard_acc, result, modules_by_id)

		var summary := Report.summarize(acc)
		summary["id"] = key
		summary["modules"] = modules
		results.append(summary)

	var out := {"results": results, "shard_accumulator": shard_acc}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
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
