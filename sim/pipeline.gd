class_name Pipeline
extends RefCounted

## The weapon system: feed fills a buffer, chamber cycles it into heat and a
## fired round, cooling removes heat, targeting decides whether a fired round
## converts into hits. Each active module's own failure.mode/threshold drives
## its mechanical failure — nothing here is a hardcoded balance number, it is
## all read from the assembled loadout's module defs and from tuning.
##
## Tick order within step() matches docs/plan.md exactly: dissipate heat,
## advance feed, attempt chamber cycle, then targeting resolves against the
## fired round (encounter.gd applies the actual hits, since that needs the
## live enemy list).

const Fx = preload("res://sim/fx.gd")
const EventLog = preload("res://sim/log.gd")

static func new_state(modules: Dictionary) -> Dictionary:
	return {
		"modules": modules,
		"buffer_fx": 0,
		"heat": 0,
		"chamber_jam_streak": 0,
		"chamber_offline_until": -1,
		"cooling_offline_until": -1,
		"targeting_offline": false,
	}

## Advances the weapon system by one tick. Returns whether a round fired and,
## if targeting is online, what encounter.gd needs to resolve it into hits.
static func step(state: Dictionary, tick: int, dissipation_modifier_percent: int, tuning: Dictionary, log: EventLog) -> Dictionary:
	var modules: Dictionary = state["modules"]
	var penalties: Dictionary = tuning.get("penalties", {})

	_step_cooling(state, modules["cooling"], tick, dissipation_modifier_percent, penalties, log)
	_step_feed(state, modules["feed"])
	var fired := _step_chamber(state, modules["chamber"], modules["feed"], tick, penalties, log)
	var targeting_online := _step_targeting(state, modules["targeting"], tick, log)

	var result := {"fired": false, "damage_per_round": 0, "targets_per_cycle": 0, "hit_chance_percent": 0, "damage_tags": []}
	if fired and targeting_online:
		var chamber: Dictionary = modules["chamber"]
		var targeting: Dictionary = modules["targeting"]
		result["fired"] = true
		result["damage_per_round"] = int(chamber.get("provides", {}).get("damage_per_round", 0))
		result["targets_per_cycle"] = int(targeting.get("provides", {}).get("targets_per_cycle", 1))
		result["hit_chance_percent"] = int(targeting.get("provides", {}).get("hit_chance_percent", 100))
		result["damage_tags"] = chamber.get("tags", {}).get("list", [])
	return result

static func _step_cooling(state: Dictionary, cooling: Dictionary, tick: int, modifier_percent: int, penalties: Dictionary, log: EventLog) -> void:
	var was_online: bool = tick >= int(state["cooling_offline_until"])
	if was_online:
		var dissipation := int(cooling.get("provides", {}).get("dissipation", 0))
		var adjusted := dissipation + (dissipation * modifier_percent) / 100
		state["heat"] = max(0, int(state["heat"]) - adjusted)

	var threshold := int(cooling.get("failure", {}).get("threshold", -1))
	if threshold >= 0 and int(state["heat"]) >= threshold and was_online:
		var penalty := int(penalties.get("cooling_offline_ticks", 0))
		state["cooling_offline_until"] = tick + penalty
		log.append(tick, "module_offline", cooling.get("id", "cooling"), {"reason": "overheat"})

static func _step_feed(state: Dictionary, feed: Dictionary) -> void:
	var provides: Dictionary = feed.get("provides", {})
	var supply_rate := int(provides.get("supply_rate", 0))
	var per_tick := Fx.div(supply_rate, Fx.from_int(100))
	var capacity := Fx.from_int(int(provides.get("buffer", 0)))
	state["buffer_fx"] = min(int(state["buffer_fx"]) + per_tick, capacity)

static func _step_chamber(state: Dictionary, chamber: Dictionary, feed: Dictionary, tick: int, penalties: Dictionary, log: EventLog) -> bool:
	var online: bool = tick >= int(state["chamber_offline_until"])
	if not online:
		return false

	var interval: int = max(1, int(chamber.get("provides", {}).get("cycle_interval", 1)))
	if tick % interval != 0:
		return false

	if int(state["buffer_fx"]) >= Fx.ONE:
		state["buffer_fx"] = int(state["buffer_fx"]) - Fx.ONE
		state["heat"] = int(state["heat"]) + int(chamber.get("heat", {}).get("generated", 0))
		state["chamber_jam_streak"] = 0
		log.append(tick, "fire", chamber.get("id", "chamber"), {})
		return true

	log.append(tick, "jam", feed.get("id", "feed"), {"chamber": chamber.get("id", "chamber")})
	state["chamber_jam_streak"] = int(state["chamber_jam_streak"]) + 1
	var jam_threshold := int(chamber.get("failure", {}).get("threshold", 0))
	if jam_threshold > 0 and int(state["chamber_jam_streak"]) >= jam_threshold:
		var penalty := int(penalties.get("jam_offline_ticks", 0))
		state["chamber_offline_until"] = tick + penalty
		state["chamber_jam_streak"] = 0
		log.append(tick, "module_offline", chamber.get("id", "chamber"), {"reason": "jam"})
	return false

static func _step_targeting(state: Dictionary, targeting: Dictionary, tick: int, log: EventLog) -> bool:
	var threshold := int(targeting.get("failure", {}).get("threshold", -1))
	var offline: bool = threshold >= 0 and int(state["heat"]) >= threshold
	if offline and not bool(state["targeting_offline"]):
		log.append(tick, "module_offline", targeting.get("id", "targeting"), {"reason": "offline"})
	state["targeting_offline"] = offline
	return not offline
