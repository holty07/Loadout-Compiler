class_name Pipeline
extends RefCounted

## The weapon system: feed fills a buffer, chamber cycles it into heat and a
## fired round, cooling removes heat, targeting decides whether a fired round
## converts into hits. Each active module's own failure.mode/threshold drives
## its mechanical failure — nothing here is a hardcoded balance number, it is
## all read from the assembled loadout's module defs and from tuning.
##
## new_state() pre-extracts every scalar step() needs out of the (nested,
## string-keyed) module defs once per run, rather than re-deriving them from
## `modules.get("provides", {}).get(...)` on every one of the thousands of
## ticks in a run — that re-derivation, not event-log emission, is what made
## harness/sweep.gd's 50x2000 target too slow (see the M2 design notes in
## docs/M2.md). Behaviour is unchanged from the pre-optimisation version —
## verified byte-identical log hashes on the fixture seed before and after.
##
## Tick order within step() matches docs/plan.md exactly: dissipate heat,
## advance feed, attempt chamber cycle, then targeting resolves against the
## fired round (encounter.gd applies the actual hits, since that needs the
## live enemy list).

const Fx = preload("res://sim/fx.gd")
const EventLog = preload("res://sim/log.gd")

static func new_state(modules: Dictionary) -> Dictionary:
	var feed: Dictionary = modules["feed"]
	var chamber: Dictionary = modules["chamber"]
	var cooling: Dictionary = modules["cooling"]
	var targeting: Dictionary = modules["targeting"]

	return {
		"buffer_fx": 0,
		"heat": 0,
		"chamber_jam_streak": 0,
		"chamber_offline_until": -1,
		"cooling_offline_until": -1,
		"targeting_offline": false,

		"feed_id": String(feed.get("id", "feed")),
		"feed_supply_per_tick_fx": Fx.div(int(feed.get("provides", {}).get("supply_rate", 0)), Fx.from_int(100)),
		"feed_buffer_capacity_fx": Fx.from_int(int(feed.get("provides", {}).get("buffer", 0))),

		"chamber_id": String(chamber.get("id", "chamber")),
		"chamber_cycle_interval": max(1, int(chamber.get("provides", {}).get("cycle_interval", 1))),
		"chamber_damage_per_round": int(chamber.get("provides", {}).get("damage_per_round", 0)),
		"chamber_heat_generated": int(chamber.get("heat", {}).get("generated", 0)),
		"chamber_jam_threshold": int(chamber.get("failure", {}).get("threshold", 0)),
		"chamber_damage_tags": chamber.get("tags", {}).get("list", []),

		"cooling_id": String(cooling.get("id", "cooling")),
		"cooling_dissipation": int(cooling.get("provides", {}).get("dissipation", 0)),
		"cooling_overheat_threshold": int(cooling.get("failure", {}).get("threshold", -1)),

		"targeting_id": String(targeting.get("id", "targeting")),
		"targeting_targets_per_cycle": int(targeting.get("provides", {}).get("targets_per_cycle", 1)),
		"targeting_hit_chance_percent": int(targeting.get("provides", {}).get("hit_chance_percent", 100)),
		"targeting_offline_threshold": int(targeting.get("failure", {}).get("threshold", -1)),
	}

## Advances the weapon system by one tick. Returns whether a round fired and,
## if targeting is online, what encounter.gd needs to resolve it into hits.
static func step(state: Dictionary, tick: int, dissipation_modifier_percent: int, penalties: Dictionary, log: EventLog) -> Dictionary:
	# cooling
	var cooling_was_online: bool = tick >= int(state["cooling_offline_until"])
	if cooling_was_online:
		var dissipation: int = state["cooling_dissipation"]
		var adjusted := dissipation + (dissipation * dissipation_modifier_percent) / 100
		state["heat"] = max(0, int(state["heat"]) - adjusted)

	var cooling_threshold: int = state["cooling_overheat_threshold"]
	if cooling_threshold >= 0 and int(state["heat"]) >= cooling_threshold and cooling_was_online:
		state["cooling_offline_until"] = tick + int(penalties.get("cooling_offline_ticks", 0))
		log.append(tick, "module_offline", state["cooling_id"], {"reason": "overheat"})

	# feed
	state["buffer_fx"] = min(int(state["buffer_fx"]) + int(state["feed_supply_per_tick_fx"]), int(state["feed_buffer_capacity_fx"]))

	# chamber
	var fired := false
	var chamber_online: bool = tick >= int(state["chamber_offline_until"])
	if chamber_online and tick % int(state["chamber_cycle_interval"]) == 0:
		if int(state["buffer_fx"]) >= Fx.ONE:
			state["buffer_fx"] = int(state["buffer_fx"]) - Fx.ONE
			state["heat"] = int(state["heat"]) + int(state["chamber_heat_generated"])
			state["chamber_jam_streak"] = 0
			log.append(tick, "fire", state["chamber_id"], {})
			fired = true
		else:
			log.append(tick, "jam", state["feed_id"], {"chamber": state["chamber_id"]})
			state["chamber_jam_streak"] = int(state["chamber_jam_streak"]) + 1
			var jam_threshold: int = state["chamber_jam_threshold"]
			if jam_threshold > 0 and int(state["chamber_jam_streak"]) >= jam_threshold:
				state["chamber_offline_until"] = tick + int(penalties.get("jam_offline_ticks", 0))
				state["chamber_jam_streak"] = 0
				log.append(tick, "module_offline", state["chamber_id"], {"reason": "jam"})

	# targeting
	var targeting_threshold: int = state["targeting_offline_threshold"]
	var targeting_offline: bool = targeting_threshold >= 0 and int(state["heat"]) >= targeting_threshold
	if targeting_offline and not bool(state["targeting_offline"]):
		log.append(tick, "module_offline", state["targeting_id"], {"reason": "offline"})
	state["targeting_offline"] = targeting_offline

	var result := {"fired": false, "damage_per_round": 0, "targets_per_cycle": 0, "hit_chance_percent": 0, "damage_tags": []}
	if fired and not targeting_offline:
		result["fired"] = true
		result["damage_per_round"] = state["chamber_damage_per_round"]
		result["targets_per_cycle"] = state["targeting_targets_per_cycle"]
		result["hit_chance_percent"] = state["targeting_hit_chance_percent"]
		result["damage_tags"] = state["chamber_damage_tags"]
	return result
