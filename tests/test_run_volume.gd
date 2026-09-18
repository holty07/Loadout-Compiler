extends RefCounted

## M1 exit criterion: 1,000 randomly generated legal loadouts run to
## completion with no crashes, no non-terminating runs, no negative-resource
## states.

const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")
const Rng = preload("res://sim/rng.gd")

const SLOTS := ["feed", "chamber", "cooling", "targeting"]
const RUN_COUNT := 1000

func test_1000_random_legal_loadouts_complete_without_crash() -> bool:
	var data := DataLoader.load_all()

	var by_slot := {"feed": [], "chamber": [], "cooling": [], "targeting": []}
	for id in (data["modules"] as Dictionary).keys():
		var mod: Dictionary = data["modules"][id]
		(by_slot[mod["slot"]] as Array).append(id)
	for slot in SLOTS:
		if (by_slot[slot] as Array).is_empty():
			print("  no modules loaded for slot %s — is /data populated?" % slot)
			return false

	var gen_rng := Rng.new(20260918)
	var wins := 0
	var losses := 0

	for i in RUN_COUNT:
		var module_ids: Array = []
		for slot in SLOTS:
			var options: Array = by_slot[slot]
			module_ids.append(options[gen_rng.next_below(options.size())])
		var seed_val := gen_rng.next_below(2000000000)

		var result := Run.execute(seed_val, module_ids, [], data)
		if not result["ok"]:
			print("  run %d failed to assemble a supposedly-legal loadout %s: %s" % [i, str(module_ids), str(result["errors"])])
			return false
		if result["outcome"] != "win" and result["outcome"] != "loss":
			print("  run %d produced an unknown outcome: %s" % [i, str(result["outcome"])])
			return false
		if int(result["player_integrity"]) < 0:
			print("  run %d ended with negative player integrity" % i)
			return false
		if int(result["depth"]) < 1:
			print("  run %d never entered a room" % i)
			return false

		if result["outcome"] == "win":
			wins += 1
		else:
			losses += 1

	print("  %d/%d runs completed (%d wins, %d losses)" % [wins + losses, RUN_COUNT, wins, losses])
	return wins + losses == RUN_COUNT
