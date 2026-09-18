class_name DebugReplay
extends RefCounted

## Pure, engine-free replay logic for harness/debug_renderer.gd — kept
## separate from the actual Node-based renderer specifically so it can be
## tested headlessly (tests/test_debug_replay.gd), even though the renderer
## itself has no automated exit criterion (docs/M2.md). Foreshadows the
## real test at M4 ("render tick N by playing forward from zero, then again
## by jumping directly to N, assert identical view state") — state_at() is
## already a pure function of (records, tick) with nothing else to
## invalidate between calls, so that property holds here for free.

## Every record with tick <= up_to_tick, in log order.
static func records_up_to(records: Array, up_to_tick: int) -> Array:
	var result: Array = []
	for r in records:
		if int(r["tick"]) <= up_to_tick:
			result.append(r)
	return result

## Replays records up to a tick into a small summary a debug UI can show:
## depth reached, remaining integrity, kills so far, which modules have
## gone offline, and the outcome once run_end has been replayed.
static func state_at(records: Array, up_to_tick: int, integrity_max: int) -> Dictionary:
	var state := {
		"tick": up_to_tick,
		"depth": 0,
		"integrity": integrity_max,
		"kills": 0,
		"offline_modules": [],
		"outcome": "in_progress",
	}
	for r in records:
		if int(r["tick"]) > up_to_tick:
			break
		var payload: Dictionary = r["payload"]
		match String(r["kind"]):
			"room_enter":
				state["depth"] = int(payload.get("depth", state["depth"]))
			"kill":
				state["kills"] = int(state["kills"]) + 1
			"damage_taken":
				state["integrity"] = max(0, int(state["integrity"]) - int(payload.get("amount", 0)))
			"module_offline":
				var offline: Array = state["offline_modules"]
				var subject := String(r["subject"])
				if not offline.has(subject):
					offline.append(subject)
			"run_end":
				state["outcome"] = String(payload.get("outcome", "in_progress"))
	return state
