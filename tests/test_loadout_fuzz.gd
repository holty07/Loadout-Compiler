extends RefCounted

const Loadout = preload("res://sim/loadout.gd")
const Rng = preload("res://sim/rng.gd")

var _tuning := {"loadout": {"power_budget": 50, "mass_budget": 50, "slot_budget": 8}}
var _modules := {
	"feed.ok": {"id": "feed.ok", "slot": "feed", "cost": {"power": 5, "mass": 5, "slots": 1}, "requires": {"power_min": 0}},
	"chamber.ok": {"id": "chamber.ok", "slot": "chamber", "cost": {"power": 5, "mass": 5, "slots": 1}, "requires": {"power_min": 0}},
	"cooling.ok": {"id": "cooling.ok", "slot": "cooling", "cost": {"power": 5, "mass": 5, "slots": 1}, "requires": {"power_min": 0}},
	"targeting.ok": {"id": "targeting.ok", "slot": "targeting", "cost": {"power": 5, "mass": 5, "slots": 1}, "requires": {"power_min": 0}},
	"chamber.greedy": {"id": "chamber.greedy", "slot": "chamber", "cost": {"power": 1000, "mass": 5, "slots": 1}, "requires": {"power_min": 0}},
	"targeting.needy": {"id": "targeting.needy", "slot": "targeting", "cost": {"power": 5, "mass": 5, "slots": 1}, "requires": {"power_min": 9999}},
}

func _legal() -> Array:
	return ["feed.ok", "chamber.ok", "cooling.ok", "targeting.ok"]

func test_legal_loadout_assembles() -> bool:
	var r := Loadout.assemble(_legal(), _modules, _tuning)
	return r["ok"] == true

func test_missing_slot_named_error() -> bool:
	var r := Loadout.assemble(["feed.ok", "chamber.ok", "cooling.ok"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("missing_slot:targeting")

func test_unknown_module_named_error() -> bool:
	var r := Loadout.assemble(["feed.ok", "chamber.ok", "cooling.ok", "not.a.module"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("unknown_module:not.a.module")

func test_duplicate_slot_named_error() -> bool:
	var r := Loadout.assemble(["feed.ok", "feed.ok", "chamber.ok", "cooling.ok", "targeting.ok"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("duplicate_slot:feed")

func test_power_budget_exceeded_named_error() -> bool:
	var r := Loadout.assemble(["feed.ok", "chamber.greedy", "cooling.ok", "targeting.ok"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("power_budget_exceeded")

func test_power_min_unmet_named_error() -> bool:
	var r := Loadout.assemble(["feed.ok", "chamber.ok", "cooling.ok", "targeting.needy"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("power_min_unmet:targeting.needy")

func test_non_string_module_id_fails_gracefully() -> bool:
	var r := Loadout.assemble([123, true, {}, "feed.ok"], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).has("module_id_not_string")

func test_empty_loadout_fails_gracefully() -> bool:
	var r := Loadout.assemble([], _modules, _tuning)
	return r["ok"] == false and (r["errors"] as Array).size() == 4

func test_random_fuzz_never_crashes_and_names_errors() -> bool:
	var rng := Rng.new(777)
	var pool := ["feed.ok", "chamber.ok", "cooling.ok", "targeting.ok", "chamber.greedy", "targeting.needy", "unknown.one", "unknown.two"]
	for i in 500:
		var n := rng.next_below(6)
		var ids: Array = []
		for j in n:
			ids.append(pool[rng.next_below(pool.size())])
		var r := Loadout.assemble(ids, _modules, _tuning)
		if not (r["ok"] is bool):
			return false
		if r["ok"] == false:
			for e in r["errors"]:
				if not (e is String) or e == "":
					return false
	return true
