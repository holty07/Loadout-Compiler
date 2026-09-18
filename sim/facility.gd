class_name Facility
extends RefCounted

## Route generation: a straight line of tuning.facility.room_count rooms, one
## per depth, sampled uniformly by rng from whichever room defs cover that
## depth. Branching routes are an open question deferred to M3
## (docs/plan.md); this only has to produce *a* route.

const Rng = preload("res://sim/rng.gd")

static func generate_route(rng: Rng, room_defs: Array, tuning: Dictionary) -> Dictionary:
	var facility_tuning: Dictionary = tuning.get("facility", {})
	var room_count := int(facility_tuning.get("room_count", 0))
	if room_count <= 0:
		return {"ok": false, "errors": ["invalid_room_count"]}

	var route: Array = []
	for depth in range(1, room_count + 1):
		var candidates: Array = []
		for room in room_defs:
			var depth_range: Array = room.get("depth_range", [])
			if depth_range.size() < 2:
				continue
			if depth >= int(depth_range[0]) and depth <= int(depth_range[1]):
				candidates.append(room)
		if candidates.is_empty():
			return {"ok": false, "errors": ["no_room_for_depth:%d" % depth]}
		route.append(candidates[rng.next_below(candidates.size())])

	return {"ok": true, "errors": [], "route": route}
