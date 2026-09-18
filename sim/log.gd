class_name EventLog
extends RefCounted

## Append-only event log: the only interface between sim and everything else.
## Records are {tick, kind, subject, payload}. serialize() is canonical
## (payload keys sorted) so log_hash() is stable regardless of how a payload
## dictionary happened to be built.

var records: Array = []

func append(tick: int, kind: String, subject: String, payload: Dictionary = {}) -> void:
	records.append({"tick": tick, "kind": kind, "subject": subject, "payload": payload})

func serialize() -> String:
	var lines: PackedStringArray = []
	for r in records:
		var payload: Dictionary = r["payload"]
		var keys := payload.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%s=%s" % [k, str(payload[k])])
		lines.append("%d|%s|%s|%s" % [r["tick"], r["kind"], r["subject"], "&".join(parts)])
	return "\n".join(lines)

func log_hash() -> String:
	return serialize().sha256_text()

## Drops the kinds harness/report.gd never reads: fire/jam/hit (bounded by
## tick count, potentially hundreds per run) and spawn (harness/report.gd
## recovers archetype + spawn tick straight off a kill/damage_taken event's
## own "<archetype>@<spawn_tick>#<index>" subject, never from a spawn
## record). Keeps kill, damage_taken, module_offline, room_enter, run_end —
## everything outcome and attribution actually need. Per docs/plan.md's
## known-performance-limit mitigation: "strip event-log emission during
## sweeps (outcome and attribution only)." Never used for a real run whose
## log is inspected or hashed for determinism — only for harness/sweep.gd.
class SparseEventLog extends EventLog:
	const DROPPED_KINDS := ["fire", "jam", "hit", "spawn"]

	func append(tick: int, kind: String, subject: String, payload: Dictionary = {}) -> void:
		if DROPPED_KINDS.has(kind):
			return
		super.append(tick, kind, subject, payload)
