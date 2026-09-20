class_name RunSnapshot
extends RefCounted
## Versioned checkpoint envelope. RunState owns strategic migration details.

const VERSION: int = 2


static func build(run_state_data: Dictionary, world_state: Dictionary) -> Dictionary:
	return {
		"snapshot_version": VERSION,
		"run_state": run_state_data.duplicate(true),
		"world": world_state.duplicate(true)
	}


static func normalize(raw_snapshot: Dictionary) -> Dictionary:
	if raw_snapshot.is_empty():
		return {}
	if (
		int(raw_snapshot.get("snapshot_version", 0)) == VERSION
		and typeof(raw_snapshot.get("run_state", null)) == TYPE_DICTIONARY
	):
		var result: Dictionary = raw_snapshot.duplicate(true)
		if not _has_valid_run_state(result.get("run_state", {})):
			return {}
		if typeof(result.get("world", null)) != TYPE_DICTIONARY:
			result["world"] = {}
		return result
	if not _has_valid_run_state(raw_snapshot):
		return {}
	return migrate_v1(raw_snapshot)


static func migrate_v1(flat_run_state: Dictionary) -> Dictionary:
	return {
		"snapshot_version": VERSION,
		"migrated_from": 1,
		"run_state": flat_run_state.duplicate(true),
		"world": {
			"run_mode": "boss" if (
				bool(flat_run_state.get("boss_triggered", false))
				and not bool(flat_run_state.get("boss_defeated", false))
			) else "travel",
			"reveal_timer": 52.0,
			"enemy_state": {},
			"boss_state": {}
		}
	}


static func run_state_data(snapshot: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize(snapshot)
	return (normalized.get("run_state", {}) as Dictionary).duplicate(true)


static func world_state(snapshot: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize(snapshot)
	return (normalized.get("world", {}) as Dictionary).duplicate(true)


static func _has_valid_run_state(data: Variant) -> bool:
	return (
		data is Dictionary
		and int(data.get("run_seed", 0)) > 0
		and data.get("cars", null) is Array
	)
