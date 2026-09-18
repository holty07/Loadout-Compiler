extends RefCounted

const Report = preload("res://harness/report.gd")
const EventLog = preload("res://sim/log.gd")

var _modules_by_id := {
	"chamber.rapid": {"id": "chamber.rapid", "slot": "chamber"},
	"cooling.fan": {"id": "cooling.fan", "slot": "cooling"},
}

func _make_log(records: Array) -> EventLog:
	var log := EventLog.new()
	for r in records:
		log.append(r[0], r[1], r[2], r[3] if r.size() > 3 else {})
	return log

func test_win_rate_and_clear_rate() -> bool:
	var acc := Report.new_accumulator()
	Report.ingest(acc, {"ok": true, "outcome": "win", "depth": 3, "log": _make_log([])}, _modules_by_id)
	Report.ingest(acc, {"ok": true, "outcome": "loss", "depth": 2, "log": _make_log([])}, _modules_by_id)
	var summary := Report.summarize(acc)
	if summary["runs"] != 2:
		return false
	if not is_equal_approx(float(summary["win_rate"]), 0.5):
		return false
	# win at depth 3 clears 1,2,3; loss at depth 2 clears only 1 (died in room 2).
	var clear: Dictionary = summary["clear_rate_by_depth"]
	if not is_equal_approx(float(clear["1"]), 1.0):
		return false
	if not is_equal_approx(float(clear["2"]), 0.5):
		return false
	if not is_equal_approx(float(clear["3"]), 0.5):
		return false
	return true

func test_ttk_parsed_from_instance_id() -> bool:
	var acc := Report.new_accumulator()
	var log := _make_log([
		[0, "spawn", "drone.swarm@0#0", {"archetype": "drone.swarm", "wave": 1}],
		[45, "kill", "drone.swarm@0#0", {}],
		[0, "spawn", "drone.swarm@0#1", {"archetype": "drone.swarm", "wave": 1}],
		[90, "kill", "drone.swarm@0#1", {}],
		[10, "run_end", "run", {"outcome": "win", "depth": 1}],
	])
	Report.ingest(acc, {"ok": true, "outcome": "win", "depth": 1, "log": log}, _modules_by_id)
	var summary := Report.summarize(acc)
	var ttk: Dictionary = summary["ttk_by_archetype"]["drone.swarm"]
	# samples are [45, 90]; p50 index = int(0.5 * 1) = 0 -> 45, p90 index = int(0.9*1)=0 -> 45
	if int(ttk["p10"]) != 45:
		return false
	return true

func test_first_choke_attributed_to_slot() -> bool:
	var acc := Report.new_accumulator()
	var log := _make_log([
		[20, "module_offline", "chamber.rapid", {"reason": "jam"}],
		[40, "module_offline", "cooling.fan", {"reason": "overheat"}],
	])
	Report.ingest(acc, {"ok": true, "outcome": "loss", "depth": 1, "log": log}, _modules_by_id)
	var summary := Report.summarize(acc)
	var choke: Dictionary = summary["first_choke"]
	# only the FIRST module_offline (chamber, tick 20) should count.
	if not is_equal_approx(float(choke.get("chamber", 0.0)), 1.0):
		return false
	if choke.has("cooling"):
		return false
	return true

func test_no_choke_when_no_module_offline() -> bool:
	var acc := Report.new_accumulator()
	Report.ingest(acc, {"ok": true, "outcome": "loss", "depth": 1, "log": _make_log([])}, _modules_by_id)
	var summary := Report.summarize(acc)
	return is_equal_approx(float(summary["first_choke"].get("none", 0.0)), 1.0)

func test_damage_taken_share_by_archetype() -> bool:
	var acc := Report.new_accumulator()
	var log := _make_log([
		[10, "damage_taken", "drone.swarm@0#0", {"amount": 6}],
		[20, "damage_taken", "drone.brute@0#0", {"amount": 18}],
	])
	Report.ingest(acc, {"ok": true, "outcome": "loss", "depth": 1, "log": log}, _modules_by_id)
	var summary := Report.summarize(acc)
	var share: Dictionary = summary["damage_taken_share"]
	return is_equal_approx(float(share["drone.swarm"]), 0.25) and is_equal_approx(float(share["drone.brute"]), 0.75)

func test_normalize_summary_recasts_json_floats_to_int() -> bool:
	var summary := {
		"runs": 20.0,
		"ttk_by_archetype": {"drone.swarm": {"p10": 29.0, "p50": 99.0, "p90": 288.0}},
	}
	var normalized := Report.normalize_summary(summary)
	if typeof(normalized["runs"]) != TYPE_INT:
		return false
	var p: Dictionary = normalized["ttk_by_archetype"]["drone.swarm"]
	return typeof(p["p10"]) == TYPE_INT and typeof(p["p50"]) == TYPE_INT and typeof(p["p90"]) == TYPE_INT

func test_failed_assembly_is_not_ingested() -> bool:
	var acc := Report.new_accumulator()
	Report.ingest(acc, {"ok": false, "errors": ["missing_slot:feed"]}, _modules_by_id)
	var summary := Report.summarize(acc)
	return int(summary["runs"]) == 0
