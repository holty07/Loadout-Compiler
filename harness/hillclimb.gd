extends SceneTree

## godot --headless --script harness/hillclimb.gd -- --seeds 300 --out reports/hillclimb.json \
##     [--start-seed 1] [--max-iterations 20]
##
## Greedy hill-climb over the loadout space: from a random starting
## loadout, try swapping one slot at a time to every other option in that
## slot, move to whichever single swap most improves win rate, repeat until
## no swap improves on the current loadout (or --max-iterations is hit).
## docs/plan.md: "the fastest way to surface a degenerate combination."
##
## Not gated by an exit criterion of its own — a diagnostic tool for
## docs/plan.md's "How the agent uses it" balance loop, not a tested
## deliverable. Runs single-process (unlike sweep.gd): its candidate
## evaluations are cheap (a few hundred seeds, not 2,000) and sequential by
## nature — each swap decision depends on the last, so there's nothing to
## fan out across cores the way the main sweep's independent loadouts are.

const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")
const Rng = preload("res://sim/rng.gd")
const Report = preload("res://harness/report.gd")

const SLOTS := ["feed", "chamber", "cooling", "targeting"]

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var seeds := int(args.get("seeds", "300"))
	var out_path: String = args.get("out", "reports/hillclimb.json")
	var start_seed := int(args.get("start-seed", "1"))
	var max_iterations := int(args.get("max-iterations", "20"))

	var data := DataLoader.load_all()
	var modules_by_id: Dictionary = data["modules"]
	var by_slot := {}
	for slot in SLOTS:
		by_slot[slot] = []
	for id in modules_by_id.keys():
		var mod: Dictionary = modules_by_id[id]
		(by_slot[String(mod.get("slot", ""))] as Array).append(id)
	for slot in SLOTS:
		(by_slot[slot] as Array).sort()

	var rng := Rng.new(start_seed)
	var current: Array = []
	for slot in SLOTS:
		var opts: Array = by_slot[slot]
		current.append(opts[rng.next_below(opts.size())])

	var current_rate := _evaluate(current, seeds, data, modules_by_id)
	var history: Array = [{"modules": current.duplicate(), "win_rate": current_rate}]

	for iter in max_iterations:
		var best_candidate: Array = []
		var best_rate := current_rate
		for slot_idx in SLOTS.size():
			for option in (by_slot[SLOTS[slot_idx]] as Array):
				if option == current[slot_idx]:
					continue
				var candidate: Array = current.duplicate()
				candidate[slot_idx] = option
				var rate := _evaluate(candidate, seeds, data, modules_by_id)
				if rate > best_rate:
					best_rate = rate
					best_candidate = candidate
		if best_candidate.is_empty():
			break
		current = best_candidate
		current_rate = best_rate
		history.append({"modules": current.duplicate(), "win_rate": current_rate})

	var result := {
		"seeds_per_candidate": seeds,
		"iterations": history.size() - 1,
		"final_modules": current,
		"final_win_rate": current_rate,
		"history": history,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	print("hillclimb: %d iteration(s), final win_rate=%f, modules=%s" % [history.size() - 1, current_rate, str(current)])
	quit(0)

func _evaluate(modules: Array, seeds: int, data: Dictionary, modules_by_id: Dictionary) -> float:
	var acc := Report.new_accumulator()
	var rng := Rng.new(",".join(modules).hash())
	for s in seeds:
		var seed_val := rng.next_below(2000000000)
		var result := Run.execute(seed_val, modules, [], data, true)
		Report.ingest(acc, result, modules_by_id)
	return float(Report.summarize(acc)["win_rate"])

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
