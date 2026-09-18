extends SceneTree

## godot --headless --script harness/sweep.gd -- --matrix harness/loadouts.toml --seeds 2000 --out reports/ [--workers N]
##
## Fans the sweep across one worker process per core — docs/plan.md's
## documented mitigation for GDScript's per-run cost ("Fan the sweep across
## processes — one headless instance per core") — then merges every
## worker's raw accumulator into one grand total and summarizes it once for
## the "overall" numbers, alongside each worker's per-loadout summaries.
## See docs/M2.md for why this shape (and not in-process threads): process
## isolation avoids any GDScript/Thread interaction this project has not
## had reason to characterize.
##
## Exit criterion (docs/M2.md): 50 loadouts x 2,000 seeds in under two
## minutes on 8 cores, committing this report under reports/.

const Toml = preload("res://tools/toml.gd")
const Report = preload("res://harness/report.gd")

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var matrix_path: String = args.get("matrix", "harness/loadouts.toml")
	var seeds := int(args.get("seeds", "2000"))
	var out_dir: String = args.get("out", "reports/")
	var workers := int(args.get("workers", str(min(8, OS.get_processor_count()))))

	if not FileAccess.file_exists(matrix_path):
		printerr("matrix file not found: %s" % matrix_path)
		quit(1)
		return

	var start_ms := Time.get_ticks_msec()

	var tmp_dir := out_dir.path_join("_partial")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp_dir))

	var pids: Array = []
	var partial_paths: Array = []
	for i in workers:
		var partial_path: String = tmp_dir.path_join("shard_%d.json" % i)
		partial_paths.append(partial_path)
		var pid := OS.create_process(OS.get_executable_path(), [
			"--headless", "--script", "harness/sweep_worker.gd", "--",
			"--matrix", matrix_path, "--seeds", str(seeds),
			"--shard-index", str(i), "--shard-count", str(workers),
			"--out", partial_path,
		])
		if pid == -1:
			printerr("failed to spawn worker %d" % i)
			quit(1)
			return
		pids.append(pid)

	for pid in pids:
		while OS.is_process_running(pid):
			OS.delay_msec(50)

	var per_loadout: Array = []
	var grand_acc := Report.new_accumulator()
	for path in partial_paths:
		if not FileAccess.file_exists(path):
			printerr("missing partial report: %s" % path)
			quit(1)
			return
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			printerr("failed to parse partial report: %s" % path)
			quit(1)
			return
		var partial: Dictionary = json.data
		for r in (partial.get("results", []) as Array):
			per_loadout.append(Report.normalize_summary(r))
		Report.merge_into(grand_acc, partial.get("shard_accumulator", Report.new_accumulator()))

	var elapsed_sec := float(Time.get_ticks_msec() - start_ms) / 1000.0

	per_loadout.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))

	var report := {
		"meta": {
			"loadout_count": per_loadout.size(),
			"seeds_per_loadout": seeds,
			"total_runs": per_loadout.size() * seeds,
			"workers": workers,
			"elapsed_seconds": elapsed_sec,
		},
		"overall": Report.summarize(grand_acc),
		"per_loadout": per_loadout,
	}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out_path := out_dir.path_join("sweep_report.json")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))

	_cleanup(tmp_dir, partial_paths)

	print("wrote %s — %d loadouts x %d seeds (%d total runs) in %.1fs on %d workers" % [
		out_path, per_loadout.size(), seeds, per_loadout.size() * seeds, elapsed_sec, workers,
	])
	quit(0)

func _cleanup(tmp_dir: String, partial_paths: Array) -> void:
	for path in partial_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_dir))

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
