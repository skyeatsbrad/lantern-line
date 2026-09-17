extends Node
## GameManager
##
## Persistence and settings only. Not a runtime state owner.
## The active run stores its own state in the game_world scene tree.

const SAVE_PATH: String = "user://lantern_line.save"
const SAVE_VERSION: int = 1

signal settings_changed()

var settings: Dictionary = {
	"master_volume": 0.8,
	"screen_shake": true,
	"reduced_motion": false,
	"text_scale": 1.0
}

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
	pending_run = run_snapshot.duplicate(true)
	has_pending_run = true
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
	settings[key] = value
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
	var ver: int = int(data.get("version", 0))
	if ver != SAVE_VERSION:
		return
	if data.has("settings") and typeof(data["settings"]) == TYPE_DICTIONARY:
		for k in data["settings"].keys():
			settings[k] = data["settings"][k]
	if data.has("meta") and typeof(data["meta"]) == TYPE_DICTIONARY:
		for k in data["meta"].keys():
			meta[k] = data["meta"][k]
	if data.has("pending_run") and typeof(data["pending_run"]) == TYPE_DICTIONARY:
		pending_run = data["pending_run"]
	has_pending_run = bool(data.get("has_pending_run", false)) and not pending_run.is_empty()
