extends RefCounted

const DebugReplay = preload("res://harness/debug_replay.gd")

var _records := [
	{"tick": 0, "kind": "room_enter", "subject": "room.intro", "payload": {"depth": 1}},
	{"tick": 5, "kind": "damage_taken", "subject": "drone.swarm@0#0", "payload": {"amount": 6}},
	{"tick": 10, "kind": "kill", "subject": "drone.swarm@0#0", "payload": {}},
	{"tick": 20, "kind": "module_offline", "subject": "chamber.rapid", "payload": {"reason": "jam"}},
	{"tick": 30, "kind": "run_end", "subject": "run", "payload": {"outcome": "loss", "depth": 1}},
]

func test_records_up_to_excludes_later_ticks() -> bool:
	var subset := DebugReplay.records_up_to(_records, 10)
	return subset.size() == 3

func test_state_at_before_anything_happens() -> bool:
	var state := DebugReplay.state_at(_records, -1, 100)
	return int(state["depth"]) == 0 and int(state["integrity"]) == 100 and int(state["kills"]) == 0

func test_state_at_partway_through() -> bool:
	var state := DebugReplay.state_at(_records, 15, 100)
	return int(state["depth"]) == 1 and int(state["integrity"]) == 94 and int(state["kills"]) == 1 and String(state["outcome"]) == "in_progress"

func test_state_at_end_reflects_outcome_and_offline_module() -> bool:
	var state := DebugReplay.state_at(_records, 30, 100)
	return String(state["outcome"]) == "loss" and (state["offline_modules"] as Array).has("chamber.rapid")

func test_state_at_is_a_pure_function_of_tick_not_call_order() -> bool:
	# Jumping straight to a late tick must match replaying forward through
	# every earlier tick first — the forward-vs-jump property M4 will test
	# for real, already true here since state_at() carries no state between
	# calls.
	var jumped := DebugReplay.state_at(_records, 25, 100)
	for t in [0, 5, 10, 15, 20]:
		DebugReplay.state_at(_records, t, 100)
	var after_forward_playback := DebugReplay.state_at(_records, 25, 100)
	return jumped["depth"] == after_forward_playback["depth"] \
		and jumped["integrity"] == after_forward_playback["integrity"] \
		and jumped["kills"] == after_forward_playback["kills"] \
		and jumped["outcome"] == after_forward_playback["outcome"]
