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
