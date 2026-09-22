class_name PresentationDirector
extends Node

signal state_changed(state: Dictionary)

var _run_state: RunState
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _state: Dictionary = {}


func setup(run_state: RunState, view_size: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size


func set_view_size(view_size: Vector2) -> void:
	_view_size = view_size


func update_state(
	mode_name: String,
	active_threats: int,
	pressure_limit: int,
	boss_active: bool,
	boss_phase: String,
	dawn_progress: float
) -> void:
	if _run_state == null:
		return
	var locomotive_ratio: float = clampf(
		_run_state.locomotive_hp / maxf(1.0, _run_state.locomotive_max_hp),
		0.0,
		1.0
	)
	var pressure: float = clampf(
		float(active_threats) / maxf(1.0, float(pressure_limit)),
		0.0,
		1.0
	)
	var damage_pressure: float = 1.0 - locomotive_ratio
	var tension: float = maxf(pressure, damage_pressure * 0.85)
	if boss_active:
		tension = maxf(tension, 0.82)
	var quality_tier: int = (
		1 if _view_size.x < 1100.0 or _view_size.y < 620.0 else 2
	)
	var next_state: Dictionary = {
		"mode": mode_name,
		"tension": tension,
		"locomotive_ratio": locomotive_ratio,
		"active_threats": active_threats,
		"boss_active": boss_active,
		"boss_phase": boss_phase,
		"dawn_progress": clampf(dawn_progress, 0.0, 1.0),
		"paused": _run_state.is_simulation_paused(),
		"speed_scale": _run_state.effective_speed_scale(),
		"quality": "compact" if quality_tier == 1 else "standard",
		"quality_tier": quality_tier,
		"music_state": _music_state(mode_name, tension, boss_active, dawn_progress)
	}
	if next_state == _state:
		return
	_state = next_state
	AudioManager.set_presentation_state(_state)
	emit_signal("state_changed", _state.duplicate(true))


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func _music_state(
	mode_name: String,
	tension: float,
	boss_active: bool,
	dawn_progress: float
) -> String:
	if mode_name == "ending" or mode_name == "ended":
		return "dawn" if _run_state.victory else "silence"
	if dawn_progress > 0.0:
		return "dawn"
	if boss_active:
		return "longshadow"
	if mode_name == "station" or mode_name == "route":
		return "station"
	if mode_name == "travel" and tension >= 0.55:
		return "travel_tension"
	if mode_name == "travel":
		return "travel_calm"
	return "title"
