class_name Encounter
extends RefCounted

## Per-room combat resolution: spawns waves against a threat budget, steps
## the pipeline each tick, converts a fired round into hits against the live
## enemy set, and resolves enemy attacks against the player. A room ends when
## every wave has spawned and every enemy from it is dead, when the player's
## integrity hits zero, or when tuning.sim.max_ticks_per_room is reached as a
## safety cutoff (docs/M1.md — the M1 data is tuned so real play never gets
## close to it).

const Rng = preload("res://sim/rng.gd")
const EventLog = preload("res://sim/log.gd")
const Pipeline = preload("res://sim/pipeline.gd")

## `room` must carry an injected "_depth" key (1-indexed) for threat scaling.
static func resolve_room(
	pipeline_state: Dictionary,
	room: Dictionary,
	enemies_by_id: Dictionary,
	tuning: Dictionary,
	rng: Rng,
	log: EventLog,
	start_tick: int,
	player_integrity: int,
	interventions_by_tick: Dictionary
) -> Dictionary:
	var depth := int(room.get("_depth", 0))
	var spawn: Dictionary = room.get("spawn", {})
	var waves_total: int = max(1, int(spawn.get("waves", 1)))
	var threat_step := int(tuning.get("threat", {}).get("depth_step", 0))
	var total_budget := int(spawn.get("budget_base", 0)) + threat_step * depth
	var per_wave_budget: int = max(1, total_budget / waves_total)
	var weights: Dictionary = spawn.get("archetype_weights", {})
	var dissipation_modifier := int(room.get("modifier", {}).get("heat_dissipation", 0))
	var max_ticks := int(tuning.get("sim", {}).get("max_ticks_per_room", 20000))

	var active_enemies: Array = []
	var waves_spawned := 0
	var tick := start_tick
	var end_tick := start_tick + max_ticks
	var died := false

	while true:
		if active_enemies.is_empty() and waves_spawned < waves_total:
			active_enemies = _spawn_wave(rng, enemies_by_id, weights, per_wave_budget, tick)
			waves_spawned += 1
			log.append(tick, "spawn", room.get("id", "room"), {"wave": waves_spawned, "count": active_enemies.size()})

		if active_enemies.is_empty() and waves_spawned >= waves_total:
			break

		if interventions_by_tick.has(tick):
			_apply_intervention(pipeline_state, String(interventions_by_tick[tick]), log, tick)

		var fire_result := Pipeline.step(pipeline_state, tick, dissipation_modifier, tuning, log)
		if fire_result.get("fired", false):
			_resolve_targeting(fire_result, active_enemies, rng, log, tick)
			active_enemies = active_enemies.filter(func(e): return int(e["hp"]) > 0)

		for enemy in active_enemies:
			if tick >= int(enemy["next_attack_tick"]):
				var dmg := int(enemy["def"].get("damage", {}).get("per_hit", 0))
				player_integrity = max(0, player_integrity - dmg)
				log.append(tick, "damage_taken", String(enemy["id"]), {"amount": dmg})
				var interval: int = max(1, int(enemy["def"].get("damage", {}).get("interval", 1)))
				enemy["next_attack_tick"] = tick + interval

		if player_integrity <= 0:
			died = true
			break

		tick += 1
		if tick >= end_tick:
			break

	return {"player_integrity": player_integrity, "died": died, "next_tick": tick}

static func _spawn_wave(rng: Rng, enemies_by_id: Dictionary, weights: Dictionary, budget: int, tick: int) -> Array:
	var result: Array = []
	if weights.is_empty():
		return result

	var ids: Array = weights.keys()
	ids.sort()
	var total_weight := 0
	for id in ids:
		total_weight += int(weights[id])
	if total_weight <= 0:
		return result

	var remaining := budget
	var guard := 0
	while remaining > 0 and guard < 64:
		guard += 1
		var roll := rng.next_below(total_weight)
		var acc := 0
		var chosen_id: String = ids[0]
		for id in ids:
			acc += int(weights[id])
			if roll < acc:
				chosen_id = id
				break
		if not enemies_by_id.has(chosen_id):
			break
		var def: Dictionary = enemies_by_id[chosen_id]
		var threat: int = max(1, int(def.get("threat", 1)))
		var interval: int = max(1, int(def.get("damage", {}).get("interval", 1)))
		result.append({
			"id": "%s#%d" % [chosen_id, result.size()],
			"def": def,
			"hp": int(def.get("hp", 1)),
			"next_attack_tick": tick + interval,
		})
		remaining -= threat
	return result

static func _resolve_targeting(fire_result: Dictionary, active_enemies: Array, rng: Rng, log: EventLog, tick: int) -> void:
	var targets: int = min(int(fire_result.get("targets_per_cycle", 1)), active_enemies.size())
	var hit_chance := int(fire_result.get("hit_chance_percent", 100))
	var base_damage := int(fire_result.get("damage_per_round", 0))
	var tags: Array = fire_result.get("damage_tags", [])
	var damage_type := "thermal" if tags.has("thermal") else "kinetic"

	for i in targets:
		var enemy: Dictionary = active_enemies[i]
		if int(enemy["hp"]) <= 0:
			continue
		var roll := rng.next_below(100)
		if roll >= hit_chance:
			continue
		var resist_percent := int(enemy["def"].get("resist", {}).get(damage_type, 0))
		var after_resist := base_damage - (base_damage * resist_percent) / 100
		var armour := int(enemy["def"].get("armour", 0))
		var final_damage: int = max(0, after_resist - armour)
		enemy["hp"] = int(enemy["hp"]) - final_damage
		log.append(tick, "hit", String(enemy["id"]), {"amount": final_damage})
		if int(enemy["hp"]) <= 0:
			enemy["hp"] = 0
			log.append(tick, "kill", String(enemy["id"]), {})

static func _apply_intervention(state: Dictionary, action: String, log: EventLog, tick: int) -> void:
	match action:
		"vent":
			state["heat"] = 0
			log.append(tick, "vent", "player", {})
		_:
			pass
