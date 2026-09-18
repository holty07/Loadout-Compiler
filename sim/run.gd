class_name Run
extends RefCounted

## Top-level run loop: (seed, loadout, interventions) -> event log. A pure
## function of its arguments — no shared state between calls, per the
## determinism test in tests/test_determinism.gd. Interventions are plumbed
## through per the recommendation in docs/plan.md's open-questions section
## even though the spending UI doesn't land until M5.

const Rng = preload("res://sim/rng.gd")
const EventLog = preload("res://sim/log.gd")
const Loadout = preload("res://sim/loadout.gd")
const Facility = preload("res://sim/facility.gd")
const Pipeline = preload("res://sim/pipeline.gd")
const Encounter = preload("res://sim/encounter.gd")

static func execute(seed_val: int, module_ids: Array, interventions: Array, data: Dictionary) -> Dictionary:
	var tuning: Dictionary = data.get("tuning", {})
	var modules_by_id: Dictionary = data.get("modules", {})
	var enemies_by_id: Dictionary = data.get("enemies", {})
	var room_defs: Array = data.get("rooms", [])

	var assembled := Loadout.assemble(module_ids, modules_by_id, tuning)
	if not assembled["ok"]:
		return {"ok": false, "errors": assembled["errors"]}

	var iv := _validate_interventions(interventions, tuning)
	if not iv["ok"]:
		return {"ok": false, "errors": iv["errors"]}

	var rng := Rng.new(seed_val)
	var route := Facility.generate_route(rng, room_defs, tuning)
	if not route["ok"]:
		return {"ok": false, "errors": route["errors"]}

	var log := EventLog.new()
	var pipeline_state := Pipeline.new_state(assembled["modules"])
	var player_integrity := int(tuning.get("player", {}).get("integrity_max", 1))
	var interventions_by_tick: Dictionary = iv["by_tick"]

	var tick := 0
	var died := false
	var depth_reached := 0
	var rooms: Array = route["route"]

	for i in rooms.size():
		var room: Dictionary = (rooms[i] as Dictionary).duplicate(true)
		var depth := i + 1
		room["_depth"] = depth
		log.append(tick, "room_enter", room.get("id", "room"), {"depth": depth})

		var res := Encounter.resolve_room(
			pipeline_state, room, enemies_by_id, tuning, rng, log, tick, player_integrity, interventions_by_tick
		)
		player_integrity = int(res["player_integrity"])
		tick = int(res["next_tick"])
		depth_reached = depth

		if res["died"]:
			died = true
			break

	var outcome := "loss" if died else "win"
	log.append(tick, "run_end", "run", {"outcome": outcome, "depth": depth_reached})

	return {
		"ok": true,
		"errors": [],
		"log": log,
		"outcome": outcome,
		"depth": depth_reached,
		"player_integrity": player_integrity,
	}

static func _validate_interventions(interventions: Array, tuning: Dictionary) -> Dictionary:
	var errors: Array = []
	var by_tick: Dictionary = {}
	var budget := int(tuning.get("interventions", {}).get("budget", 0))

	if interventions.size() > budget:
		errors.append("intervention_budget_exceeded")

	for entry in interventions:
		if not (entry is Dictionary) or not entry.has("tick") or not entry.has("action"):
			errors.append("malformed_intervention")
			continue
		if not (entry["tick"] is int) or int(entry["tick"]) < 0:
			errors.append("invalid_intervention_tick")
			continue
		if not (entry["action"] is String):
			errors.append("invalid_intervention_action")
			continue
		by_tick[entry["tick"]] = entry["action"]

	if errors.size() > 0:
		return {"ok": false, "errors": errors, "by_tick": {}}
	return {"ok": true, "errors": [], "by_tick": by_tick}
