class_name Loadout
extends RefCounted

## Module assembly and validation. A legal loadout has exactly one module in
## each required slot, within the chassis' power/mass/slot budgets. Every
## failure path returns a named string error instead of throwing, so a
## malformed loadout (unknown id, duplicate slot, missing slot, over budget)
## fails gracefully rather than crashing the run.

const REQUIRED_SLOTS := ["feed", "chamber", "cooling", "targeting"]

static func assemble(module_ids: Array, modules_by_id: Dictionary, tuning: Dictionary) -> Dictionary:
	var errors: Array = []
	var by_slot: Dictionary = {}

	for raw_id in module_ids:
		if not (raw_id is String):
			errors.append("module_id_not_string")
			continue
		if not modules_by_id.has(raw_id):
			errors.append("unknown_module:%s" % raw_id)
			continue
		var mod: Dictionary = modules_by_id[raw_id]
		var slot: String = mod.get("slot", "")
		if by_slot.has(slot):
			errors.append("duplicate_slot:%s" % slot)
			continue
		by_slot[slot] = mod

	for slot in REQUIRED_SLOTS:
		if not by_slot.has(slot):
			errors.append("missing_slot:%s" % slot)

	if errors.size() > 0:
		return {"ok": false, "errors": errors}

	var total_power := 0
	var total_mass := 0
	var total_slots := 0
	for slot in REQUIRED_SLOTS:
		var cost: Dictionary = (by_slot[slot] as Dictionary).get("cost", {})
		total_power += int(cost.get("power", 0))
		total_mass += int(cost.get("mass", 0))
		total_slots += int(cost.get("slots", 0))

	var loadout_tuning: Dictionary = tuning.get("loadout", {})
	var power_budget := int(loadout_tuning.get("power_budget", 0))
	var mass_budget := int(loadout_tuning.get("mass_budget", 0))
	var slot_budget := int(loadout_tuning.get("slot_budget", 0))

	if total_power > power_budget:
		errors.append("power_budget_exceeded")
	if total_mass > mass_budget:
		errors.append("mass_budget_exceeded")
	if total_slots > slot_budget:
		errors.append("slot_budget_exceeded")

	for slot in REQUIRED_SLOTS:
		var mod: Dictionary = by_slot[slot]
		var requires: Dictionary = mod.get("requires", {})
		var power_min := int(requires.get("power_min", 0))
		if power_budget < power_min:
			errors.append("power_min_unmet:%s" % mod.get("id", slot))

	if errors.size() > 0:
		return {"ok": false, "errors": errors}

	return {
		"ok": true,
		"errors": [],
		"modules": by_slot,
		"totals": {"power": total_power, "mass": total_mass, "slots": total_slots},
	}
