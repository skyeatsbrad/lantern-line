extends Node
## GameManager
##
## Persistence and settings only. Not a runtime state owner.
## The active run stores its own state in the game_world scene tree.

const SAVE_PATH: String = "user://lantern_line.save"
const SAVE_VERSION: int = 2

signal settings_changed()

const DEFAULT_SETTINGS: Dictionary = {
	"master_volume": 0.8,
	"music_volume": 0.72,
	"ambience_volume": 0.72,
	"sfx_volume": 0.86,
	"ui_volume": 0.82,
	"screen_shake": true,
	"reduced_motion": false,
	"reduced_flashes": false,
	"high_contrast": false,
	"short_holds": false,
	"text_scale": 1.0,
	"tutorial_seen": false,
	"contextual_tutorial_seen": false
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)

var meta: Dictionary = {
	"best_distance": 0.0,
	"wins": 0,
	"runs": 0,
	"last_seed": 0
}

var pending_run: Dictionary = {}
var has_pending_run: bool = false


func _ready() -> void:
	_load()


func has_continue() -> bool:
	return has_pending_run


func store_run_checkpoint(run_snapshot: Dictionary) -> void:
	pending_run = RunSnapshot.normalize(run_snapshot)
	has_pending_run = not pending_run.is_empty()
	_save()


func consume_run_checkpoint() -> Dictionary:
	var snap: Dictionary = pending_run.duplicate(true)
	pending_run = {}
	has_pending_run = false
	_save()
	return snap


func peek_run_checkpoint() -> Dictionary:
	return pending_run.duplicate(true)


func clear_run_checkpoint() -> void:
	pending_run = {}
	has_pending_run = false
	_save()


func record_run_end(final_distance: float, victory: bool, run_seed: int) -> void:
	meta["runs"] = int(meta.get("runs", 0)) + 1
	if final_distance > float(meta.get("best_distance", 0.0)):
		meta["best_distance"] = final_distance
	if victory:
		meta["wins"] = int(meta.get("wins", 0)) + 1
	meta["last_seed"] = run_seed
	pending_run = {}
	has_pending_run = false
	_save()


func set_setting(key: String, value: Variant) -> void:
	if not DEFAULT_SETTINGS.has(key):
		return
	var normalized: Variant = _normalize_setting(key, value)
	if settings.get(key) == normalized:
		return
	settings[key] = normalized
	emit_signal("settings_changed")
	_save()


func get_setting(key: String, default_value: Variant = null) -> Variant:
	return settings.get(key, default_value)


func _save() -> void:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"settings": settings,
		"meta": meta,
		"pending_run": pending_run,
		"has_pending_run": has_pending_run
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload))
	f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	if data.has("settings") and typeof(data["settings"]) == TYPE_DICTIONARY:
		for k in data["settings"].keys():
			if DEFAULT_SETTINGS.has(k):
				settings[k] = _normalize_setting(String(k), data["settings"][k])
	_normalize_settings()
	if data.has("meta") and typeof(data["meta"]) == TYPE_DICTIONARY:
		for k in data["meta"].keys():
			meta[k] = data["meta"][k]
	var ver: int = int(data.get("version", 0))
	if ver <= SAVE_VERSION and data.has("pending_run") and typeof(data["pending_run"]) == TYPE_DICTIONARY:
		pending_run = RunSnapshot.normalize(data["pending_run"])
	has_pending_run = (
		ver <= SAVE_VERSION
		and bool(data.get("has_pending_run", false))
		and not pending_run.is_empty()
	)
	if ver == 1:
		_save()


func migrate_payload_for_test(data: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"version": SAVE_VERSION,
		"settings": settings.duplicate(true),
		"meta": meta.duplicate(true),
		"pending_run": {},
		"has_pending_run": false
	}
	if data.has("settings") and typeof(data["settings"]) == TYPE_DICTIONARY:
		for key in data["settings"].keys():
			if DEFAULT_SETTINGS.has(key):
				result["settings"][key] = _normalize_setting(
					String(key),
					data["settings"][key]
				)
	if data.has("meta") and typeof(data["meta"]) == TYPE_DICTIONARY:
		for key in data["meta"].keys():
			result["meta"][key] = data["meta"][key]
	if data.has("pending_run") and typeof(data["pending_run"]) == TYPE_DICTIONARY:
		result["pending_run"] = RunSnapshot.normalize(data["pending_run"])
		result["has_pending_run"] = (
			bool(data.get("has_pending_run", false))
			and not (result["pending_run"] as Dictionary).is_empty()
		)
	return result


func _normalize_settings() -> void:
	for key_variant in DEFAULT_SETTINGS.keys():
		var key: String = String(key_variant)
		settings[key] = _normalize_setting(
			key,
			settings.get(key, DEFAULT_SETTINGS[key])
		)


func _normalize_setting(key: String, value: Variant) -> Variant:
	match key:
		"master_volume", "music_volume", "ambience_volume", "sfx_volume", \
		"ui_volume":
			return clampf(float(value), 0.0, 1.0)
		"text_scale":
			var requested: float = clampf(float(value), 1.0, 1.3)
			var options: Array[float] = [1.0, 1.15, 1.3]
			var nearest: float = options[0]
			for option in options:
				if absf(option - requested) < absf(nearest - requested):
					nearest = option
			return nearest
		"screen_shake", "reduced_motion", "reduced_flashes", \
		"high_contrast", "short_holds", "tutorial_seen", \
		"contextual_tutorial_seen":
			return bool(value)
		_:
			return DEFAULT_SETTINGS.get(key, value)
