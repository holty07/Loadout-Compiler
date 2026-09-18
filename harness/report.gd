class_name Report
extends RefCounted

## Pure stat accumulation for harness/sweep.gd. Consumes one Run.execute()
## result at a time — streamed, so memory stays bounded across thousands of
## seeds — and produces the win rate / clear-rate / TTK / first-choke /
## damage-share numbers docs/M2.md's exit criterion asks for.
##
## Reads only the event log's records, never sim internals: the same
## contract the (not-yet-built) M5 run report must follow. Enemy instance
## ids are "<archetype>@<spawn_tick>#<index>" (sim/encounter.gd), which is
## what makes time-to-kill recoverable straight from a "kill" event's own
## subject, with no need to correlate a separate spawn record.

static func new_accumulator() -> Dictionary:
	return {
		"total": 0,
		"wins": 0,
		"cleared_depth_counts": {},
		"ttk_by_archetype": {},
		"choke_counts": {},
		"damage_by_archetype": {},
		"damage_total": 0,
	}

## `modules_by_id` resolves a module_offline event's subject (a module id)
## to the slot it chokes — feed/chamber/cooling/targeting.
static func ingest(acc: Dictionary, result: Dictionary, modules_by_id: Dictionary) -> void:
	if not result.get("ok", false):
		return

	acc["total"] = int(acc["total"]) + 1
	var outcome := String(result.get("outcome", ""))
	var depth := int(result.get("depth", 0))
	if outcome == "win":
		acc["wins"] = int(acc["wins"]) + 1

	var cleared_through := depth - 1 if outcome == "loss" else depth
	var cleared: Dictionary = acc["cleared_depth_counts"]
	for d in range(1, cleared_through + 1):
		var key := str(d)
		cleared[key] = int(cleared.get(key, 0)) + 1

	var log = result.get("log")
	if log == null:
		return

	var first_choke_module := ""
	var first_choke_tick := -1

	for r in log.records:
		var kind := String(r["kind"])
		var subject := String(r["subject"])
		var tick := int(r["tick"])
		if kind == "kill":
			var archetype := _archetype_of(subject)
			var ttk_list: Array = acc["ttk_by_archetype"].get(archetype, [])
			ttk_list.append(tick - _spawn_tick_from_id(subject))
			acc["ttk_by_archetype"][archetype] = ttk_list
		elif kind == "damage_taken":
			var archetype := _archetype_of(subject)
			var amount := int(r["payload"].get("amount", 0))
			acc["damage_total"] = int(acc["damage_total"]) + amount
			var dmg_by: Dictionary = acc["damage_by_archetype"]
			dmg_by[archetype] = int(dmg_by.get(archetype, 0)) + amount
		elif kind == "module_offline" and first_choke_tick == -1:
			first_choke_tick = tick
			first_choke_module = subject

	var choke_key := "none"
	if first_choke_module != "" and modules_by_id.has(first_choke_module):
		choke_key = String((modules_by_id[first_choke_module] as Dictionary).get("slot", "none"))
	var choke_counts: Dictionary = acc["choke_counts"]
	choke_counts[choke_key] = int(choke_counts.get(choke_key, 0)) + 1

## Combines `source` into `target` in place. Used to pool several workers'
## raw accumulators into one grand total before summarizing "overall" —
## averaging each worker's already-summarized *percentiles* would be
## statistically wrong (percentile-of-percentiles isn't the pooled
## percentile), so sweep.gd merges raw counts/samples, then calls
## summarize() exactly once on the merged result.
static func merge_into(target: Dictionary, source: Dictionary) -> void:
	target["total"] = int(target["total"]) + int(source["total"])
	target["wins"] = int(target["wins"]) + int(source["wins"])
	target["damage_total"] = int(target["damage_total"]) + int(source["damage_total"])
	_merge_int_dict(target["cleared_depth_counts"], source["cleared_depth_counts"])
	_merge_int_dict(target["choke_counts"], source["choke_counts"])
	_merge_int_dict(target["damage_by_archetype"], source["damage_by_archetype"])

	var t_ttk: Dictionary = target["ttk_by_archetype"]
	for k in (source["ttk_by_archetype"] as Dictionary).keys():
		var existing: Array = t_ttk.get(k, [])
		existing.append_array(source["ttk_by_archetype"][k])
		t_ttk[k] = existing

static func _merge_int_dict(target: Dictionary, source: Dictionary) -> void:
	for k in source.keys():
		target[k] = int(target.get(k, 0)) + int(source[k])

static func summarize(acc: Dictionary) -> Dictionary:
	var total := int(acc["total"])

	var cleared_depth_counts: Dictionary = acc["cleared_depth_counts"]
	var clear_rate_by_depth := {}
	for d in cleared_depth_counts.keys():
		clear_rate_by_depth[d] = _rate(int(cleared_depth_counts[d]), total)

	var ttk_by_archetype := {}
	for archetype in (acc["ttk_by_archetype"] as Dictionary).keys():
		ttk_by_archetype[archetype] = _percentiles(acc["ttk_by_archetype"][archetype])

	var choke_dist := {}
	for k in (acc["choke_counts"] as Dictionary).keys():
		choke_dist[k] = _rate(int(acc["choke_counts"][k]), total)

	var damage_total := int(acc["damage_total"])
	var damage_share := {}
	for archetype in (acc["damage_by_archetype"] as Dictionary).keys():
		damage_share[archetype] = _rate(int(acc["damage_by_archetype"][archetype]), damage_total)

	return {
		"runs": total,
		"win_rate": _rate(int(acc["wins"]), total),
		"clear_rate_by_depth": clear_rate_by_depth,
		"ttk_by_archetype": ttk_by_archetype,
		"first_choke": choke_dist,
		"damage_taken_share": damage_share,
	}

## Godot's JSON parser returns float for every JSON number regardless of
## whether the source text had a decimal point, so a summary dict that has
## round-tripped through JSON.parse() (as every per_loadout entry does,
## worker -> orchestrator) needs its known-integer fields re-cast before
## being embedded in the final report — otherwise "runs" and the TTK
## percentiles print as "20.0" / "203.0" in a file meant to be read by a
## human.
static func normalize_summary(summary: Dictionary) -> Dictionary:
	summary["runs"] = int(summary["runs"])
	var ttk: Dictionary = summary.get("ttk_by_archetype", {})
	for k in ttk.keys():
		var percentiles: Dictionary = ttk[k]
		for p in ["p10", "p50", "p90"]:
			percentiles[p] = int(percentiles[p])
	return summary

static func _rate(count: int, total: int) -> float:
	return float(count) / total if total > 0 else 0.0

static func _archetype_of(subject: String) -> String:
	var at := subject.find("@")
	return subject.substr(0, at) if at != -1 else subject

static func _spawn_tick_from_id(subject: String) -> int:
	var at := subject.find("@")
	if at == -1:
		return 0
	var hash_idx := subject.find("#", at)
	if hash_idx == -1:
		return 0
	return int(subject.substr(at + 1, hash_idx - at - 1))

static func _percentiles(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"p10": 0, "p50": 0, "p90": 0}
	var sorted_samples: Array = samples.duplicate()
	sorted_samples.sort()
	return {
		"p10": _percentile(sorted_samples, 0.10),
		"p50": _percentile(sorted_samples, 0.50),
		"p90": _percentile(sorted_samples, 0.90),
	}

static func _percentile(sorted_samples: Array, p: float) -> int:
	var idx := int(p * (sorted_samples.size() - 1))
	return int(sorted_samples[idx])
