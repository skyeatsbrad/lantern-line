class_name LongshadowEncounter
extends Node2D
## Three-phase finale: strip the Veil, sever the Tether, survive the Charge.
##
## In v0.8 M2 this class holds only the deterministic simulation. All body,
## mechanic, transition, and status drawing is owned by `LongshadowView`,
## which reads a snapshot produced by `write_snapshot()` after each tick.
## `LongshadowEncounter` remains a `Node2D` so existing runtime probes can
## still cast it as a `CanvasItem`, but it never overrides `_draw`.

signal phase_changed(name: String)
signal attack_landed(message: String, severity: float)
signal defeated()

enum Phase {
	VEIL,
	TETHER,
	CHARGE
}

const PHASE_NAMES: Array[String] = ["VEIL", "TETHER", "CHARGE"]
const PHASE_HEALTH: Array[float] = [78.0, 96.0, 132.0]
const PHASE_MIN_DURATIONS: Array[float] = [16.0, 18.0, 24.0]
const PHASE_LENSES: Array[String] = ["Pale", "Hearth", "Standard"]
const RESPONSE_THRESHOLDS: Array[float] = [14.0, 16.0, 12.0]
const RESPONSE_HEALTH_FLOOR: float = 0.28
const ENTRANCE_DURATION: float = 3.0
const TRANSITION_DURATION: float = 2.5
const PRODUCER_ID: String = "sim.longshadow_encounter"

const EMITTED_TYPES: Array[StringName] = [
	SimEvent.TYPE_BOSS_PHASE_ENTRY,
	SimEvent.TYPE_BOSS_ATTACK,
	SimEvent.TYPE_BOSS_RESPONSE,
	SimEvent.TYPE_BOSS_DEFEAT,
	SimEvent.TYPE_TRAIN_HIT,
	SimEvent.TYPE_CAR_HIT
]

var _run_state: RunState
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _train_pos: Vector2 = Vector2(360.0, 500.0)
var _train_scale: float = 1.0
var _active: bool = false
var _completed: bool = false
var _phase: int = Phase.VEIL
var _health: float = PHASE_HEALTH[Phase.VEIL]
var _phase_max_health: float = PHASE_HEALTH[Phase.VEIL]
var _attack_timer: float = 4.5
var _charge_timer: float = 11.0
var _charge_stagger: float = 0.0
var _target_band: int = 1
var _target_switch_timer: float = 3.0
var _elapsed: float = 0.0
var _phase_elapsed: float = 0.0
var _transition_timer: float = 0.0
var _phase_unlocked: bool = false
var _response_progress: float = 0.0
var _charge_warning_issued: bool = false
var _event_bus: PresentationEventBus


func setup(run_state: RunState, view_size: Vector2, train_pos: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	_train_pos = train_pos
	set_process(false)
	visible = false


func attach_event_bus(bus: PresentationEventBus) -> void:
	_event_bus = bus
	if _event_bus != null:
		_event_bus.register_simulation_producer(PRODUCER_ID, EMITTED_TYPES)


func set_world_layout(
	view_size: Vector2,
	train_pos: Vector2,
	train_scale: float
) -> void:
	_view_size = view_size
	_train_pos = train_pos
	_train_scale = clampf(train_scale, 0.6, 1.0)


func start(snapshot: Dictionary = {}) -> void:
	_active = true
	_completed = false
	visible = true
	if snapshot.is_empty():
		_phase = Phase.VEIL
		_phase_max_health = PHASE_HEALTH[_phase]
		_health = _phase_max_health
		_attack_timer = 4.5
		_charge_timer = 11.0
		_charge_stagger = 0.0
		_target_band = 1
		_target_switch_timer = 3.0
		_elapsed = 0.0
		_phase_elapsed = 0.0
		_transition_timer = ENTRANCE_DURATION
		_phase_unlocked = false
		_response_progress = 0.0
		_charge_warning_issued = false
	else:
		_phase = clampi(int(snapshot.get("phase", Phase.VEIL)), Phase.VEIL, Phase.CHARGE)
		_phase_max_health = float(snapshot.get("phase_max_health", PHASE_HEALTH[_phase]))
		_health = clampf(
			float(snapshot.get("health", _phase_max_health)),
			0.01,
			_phase_max_health
		)
		_attack_timer = maxf(0.01, float(snapshot.get("attack_timer", 4.5)))
		_charge_timer = maxf(0.01, float(snapshot.get("charge_timer", 11.0)))
		_charge_stagger = maxf(0.0, float(snapshot.get("charge_stagger", 0.0)))
		_target_band = clampi(int(snapshot.get("target_band", 1)), 0, 2)
		_target_switch_timer = maxf(0.01, float(snapshot.get("target_switch_timer", 3.0)))
		_elapsed = maxf(0.0, float(snapshot.get("elapsed", 0.0)))
		_phase_elapsed = maxf(0.0, float(snapshot.get("phase_elapsed", 0.0)))
		_transition_timer = maxf(0.0, float(snapshot.get("transition_timer", 0.0)))
		_phase_unlocked = bool(snapshot.get("phase_unlocked", false))
		_response_progress = maxf(0.0, float(snapshot.get("response_progress", 0.0)))
		_charge_warning_issued = bool(snapshot.get("charge_warning_issued", false))
	_apply_phase_speed()
	_prime_active_response()
	_emit_boss(
		SimEvent.TYPE_BOSS_PHASE_ENTRY,
		phase_name(),
		{
			"phase": _phase,
			"phase_max_health": _phase_max_health,
			"transition_timer": _transition_timer,
			"resume": not snapshot.is_empty()
		}
	)
	emit_signal("phase_changed", phase_name())


func advance(delta: float, light_profile: LightProfile, stats: TrainStats) -> void:
	if not _active or _completed or _run_state.is_simulation_paused():
		return
	if _transition_timer > 0.0:
		_transition_timer = maxf(0.0, _transition_timer - delta)
		return
	var scaled := delta * _run_state.combat_speed_scale()
	_elapsed += scaled
	_phase_elapsed += scaled
	_update_target(scaled)
	var target := current_target_position()
	var beam_damage := 0.0
	if light_profile != null and light_profile.contains(target):
		var base_rate: float = [4.0, 4.4, 3.2][_phase]
		beam_damage = (
			base_rate
			* stats.effective_priority("light")
			* light_profile.damage_multiplier
			* _phase_lens_multiplier()
			* scaled
		)
	var defense_damage := (
		_defense_damage(stats)
		* scaled
		* (1.0 if _phase_unlocked else 0.45)
	)
	var total_damage := beam_damage + defense_damage
	if (
		_phase != Phase.CHARGE
		and light_profile != null
		and light_profile.focused
		and beam_damage > 0.0
	):
		_register_active_response(
			beam_damage * 0.55,
			"Focus exposes the %s." % phase_name().to_lower()
		)
	_apply_phase_damage(total_damage)

	if _phase == Phase.CHARGE:
		_process_charge(scaled, beam_damage)
	else:
		_attack_timer -= scaled
		if _attack_timer <= 0.0:
			_perform_phase_attack()

	if _health <= 0.0:
		_advance_phase()


func is_active() -> bool:
	return _active and not _completed


func is_completed() -> bool:
	return _completed


func can_accept_active_response() -> bool:
	return is_active() and _transition_timer <= 0.0


func recommended_lens() -> String:
	return PHASE_LENSES[_phase]


func focus_block_reason(light_profile: LightProfile) -> String:
	if not is_active():
		return ""
	if _transition_timer > 0.0:
		return "Focus held - wait for the Longshadow phase to form."
	if _run_state.current_lens != recommended_lens():
		return "Focus held - switch to %s for the %s." % [
			recommended_lens(),
			phase_name().to_lower()
		]
	if light_profile == null:
		return "Focus held - center the Longshadow in the beam."
	var to_target: Vector2 = current_target_position() - light_profile.origin
	if (
		to_target.length() > light_profile.range_px * 1.16
		or to_target.normalized().dot(light_profile.direction.normalized()) < cos(0.22)
	):
		return "Focus held - center the Longshadow in the beam."
	return ""


func phase_name() -> String:
	return PHASE_NAMES[_phase]


func phase_index() -> int:
	return _phase


func health_ratio() -> float:
	return clampf(_health / maxf(1.0, _phase_max_health), 0.0, 1.0)


func response_ratio() -> float:
	return clampf(
		_response_progress / maxf(1.0, RESPONSE_THRESHOLDS[_phase]),
		0.0,
		1.0
	)


func response_threshold() -> float:
	return RESPONSE_THRESHOLDS[_phase]


func response_progress() -> float:
	return _response_progress


func transition_timer() -> float:
	return _transition_timer


func transition_total() -> float:
	if _phase == Phase.VEIL and _phase_elapsed <= 0.001:
		return ENTRANCE_DURATION
	return TRANSITION_DURATION


func phase_unlocked() -> bool:
	return _phase_unlocked


func charge_timer() -> float:
	return _charge_timer


func charge_stagger() -> float:
	return _charge_stagger


func charge_warning_issued() -> bool:
	return _charge_warning_issued


func target_band() -> int:
	return _target_band


func phase_elapsed() -> float:
	return _phase_elapsed


func elapsed_time() -> float:
	return _elapsed


func attack_timer() -> float:
	return _attack_timer


func status_text() -> String:
	if _transition_timer > 0.0:
		return "LONGSHADOW - %s: brace for %.1fs" % [phase_name(), _transition_timer]
	match _phase:
		Phase.VEIL:
			return (
				"VEIL EXPOSED - finish it with %s light" % PHASE_LENSES[_phase]
				if _phase_unlocked
				else "VEIL LOCK %.0f%% - %s + FOCUS"
				% [response_ratio() * 100.0, PHASE_LENSES[_phase]]
			)
		Phase.TETHER:
			return (
				"TETHER SEVERED - keep %s on the anchor" % PHASE_LENSES[_phase]
				if _phase_unlocked
				else "TETHER LOCK %.0f%% - %s + FOCUS/SALVO"
				% [response_ratio() * 100.0, PHASE_LENSES[_phase]]
			)
		Phase.CHARGE:
			return (
				"CHARGE EXPOSED %.1fs - %s light" % [_charge_timer, PHASE_LENSES[_phase]]
				if _phase_unlocked
				else "CHARGE LOCK %.1fs - %s + FOCUS/SALVO %.0f%%"
				% [_charge_timer, PHASE_LENSES[_phase], response_ratio() * 100.0]
			)
		_:
			return "LONGSHADOW"


func current_target_position() -> Vector2:
	var boss := _boss_position()
	if _phase != Phase.TETHER:
		return boss
	var band_positions: Array[float] = [
		maxf(106.0, _train_pos.y - 150.0),
		_train_pos.y - 46.0,
		minf(
			_train_pos.y + 72.0,
			UITheme.gameplay_safe_bottom(_view_size) - 48.0
		)
	]
	return Vector2(boss.x - 85.0, band_positions[_target_band])


func boss_screen_position() -> Vector2:
	return _boss_position()


func train_position() -> Vector2:
	return _train_pos


func train_scale() -> float:
	return _train_scale


func view_size() -> Vector2:
	return _view_size


func checkpoint_state() -> Dictionary:
	if not _active and not _completed:
		return {}
	return {
		"phase": _phase,
		"phase_max_health": _phase_max_health,
		"health": _health,
		"attack_timer": _attack_timer,
		"charge_timer": _charge_timer,
		"charge_stagger": _charge_stagger,
		"target_band": _target_band,
		"target_switch_timer": _target_switch_timer,
		"elapsed": _elapsed,
		"phase_elapsed": _phase_elapsed,
		"transition_timer": _transition_timer,
		"phase_unlocked": _phase_unlocked,
		"response_progress": _response_progress,
		"charge_warning_issued": _charge_warning_issued,
		"completed": _completed
	}


func write_snapshot(snapshot: PresentationSnapshot) -> void:
	snapshot.longshadow_active = is_active()
	snapshot.longshadow_completed = _completed
	snapshot.longshadow_phase = _phase
	snapshot.longshadow_phase_id = VisualStateIds.longshadow_phase(_phase)
	snapshot.longshadow_stable_id = VisualStateIds.LONGSHADOW_ROOT
	snapshot.longshadow_position = _boss_position()
	snapshot.longshadow_target_position = current_target_position()
	snapshot.longshadow_health_ratio = health_ratio()
	snapshot.longshadow_phase_max_health = _phase_max_health
	snapshot.longshadow_transition_timer = _transition_timer
	snapshot.longshadow_transition_total = transition_total()
	snapshot.longshadow_transition_ratio = clampf(
		1.0 - _transition_timer / maxf(0.001, transition_total()), 0.0, 1.0
	)
	snapshot.longshadow_response_progress = _response_progress
	snapshot.longshadow_response_threshold = RESPONSE_THRESHOLDS[_phase]
	snapshot.longshadow_response_ratio = response_ratio()
	snapshot.longshadow_phase_unlocked = _phase_unlocked
	snapshot.longshadow_charge_timer = _charge_timer
	snapshot.longshadow_charge_stagger = _charge_stagger
	snapshot.longshadow_charge_warning_issued = _charge_warning_issued
	snapshot.longshadow_attack_timer = _attack_timer
	snapshot.longshadow_target_band = _target_band
	snapshot.longshadow_phase_elapsed = _phase_elapsed
	snapshot.longshadow_elapsed = _elapsed
	snapshot.longshadow_status_text = status_text()


func _update_target(delta: float) -> void:
	if _phase != Phase.TETHER:
		return
	if _run_state.focus_active_time > 0.0:
		return
	_target_switch_timer -= delta
	if _target_switch_timer <= 0.0:
		_target_band = (_target_band + 2) % 3
		_target_switch_timer += 4.0


func _defense_damage(stats: TrainStats) -> float:
	var total := 0.0
	for mount_variant in stats.defense_mounts:
		var mount: Dictionary = mount_variant
		var damage := float(mount.get("damage", 0.0))
		if _phase == Phase.VEIL:
			damage *= 0.15
		elif _phase == Phase.CHARGE and String(mount.get("mode", "")) == "cannon":
			damage *= 1.4
		total += damage * stats.effective_priority("defense")
	return total


func apply_defense_salvo(stats: TrainStats) -> float:
	if not is_active() or _transition_timer > 0.0:
		return 0.0
	var requested_damage: float = 0.0
	for mount_variant in stats.defense_mounts:
		var mount: Dictionary = mount_variant
		var damage: float = (
			float(mount.get("damage", 0.0))
			* stats.effective_priority("defense")
			* 3.2
		)
		if _phase == Phase.VEIL:
			damage *= 0.2
		elif _phase == Phase.CHARGE and String(mount.get("mode", "")) == "cannon":
			damage *= 1.5
		requested_damage += damage
	var before: float = _health
	_apply_phase_damage(requested_damage)
	if _phase == Phase.TETHER:
		_register_active_response(
			requested_damage * 0.6,
			"Defense Salvo severs the Tether lock."
		)
	elif _phase == Phase.CHARGE:
		_charge_stagger += requested_damage * 0.45
		_response_progress = _charge_stagger
	elif _phase == Phase.VEIL:
		_register_active_response(
			requested_damage * 0.18,
			"Defense Salvo tears a gap in the Veil."
		)
	if _health <= 0.0 and _phase_elapsed >= PHASE_MIN_DURATIONS[_phase]:
		_advance_phase()
	return maxf(0.0, before - _health)


func _perform_phase_attack() -> void:
	if _phase == Phase.VEIL:
		var response_lumen_floor: float = (
			_run_state.stats().focus_cost
			if not _phase_unlocked
			else 0.0
		)
		var response_power_floor: float = (
			RunState.DEFENSE_SALVO_POWER_COST
			if (
				not _phase_unlocked
				and _run_state.effective_priority("defense") > 0.0
				and not _run_state.stats().defense_mounts.is_empty()
			)
			else 0.0
		)
		_run_state.power = maxf(response_power_floor, _run_state.power - 1.5)
		_run_state.lumen = maxf(response_lumen_floor, _run_state.lumen - 2.0)
		_run_state.damage_locomotive(3.0)
		_attack_timer = 4.5
		emit_signal("attack_landed", "The Veil drinks power and lumen.", 3.0)
		_emit_boss(
			SimEvent.TYPE_BOSS_ATTACK,
			"veil",
			{"damage": 3.0, "target": "locomotive"}
		)
	elif _phase == Phase.TETHER:
		var result := _run_state.damage_rear_car(6.0)
		_attack_timer = 4.0
		if result.is_empty() and _run_state.cars.is_empty():
			_run_state.damage_locomotive(7.0)
		emit_signal("attack_landed", "The Tether tears at the rear coupling.", 5.0)
		_emit_boss(
			SimEvent.TYPE_BOSS_ATTACK,
			"tether",
			{"damage": 6.0, "target": "rear_car"}
		)
	_run_state.emit_signal("resources_changed")


func _process_charge(delta: float, beam_damage: float) -> void:
	_charge_timer -= delta
	if _run_state.focus_active_time > 0.0:
		_charge_stagger += beam_damage * 0.72
		_response_progress = _charge_stagger
	if _charge_timer <= 3.0 and not _charge_warning_issued:
		_charge_warning_issued = true
		_run_state.trigger_critical_slow(2.2)
		emit_signal("attack_landed", "CHARGE IMMINENT - Focus or Salvo now.", 6.0)
		_emit_boss(
			SimEvent.TYPE_BOSS_ATTACK,
			"charge_warning",
			{"charge_timer": _charge_timer}
		)
	if _charge_stagger >= RESPONSE_THRESHOLDS[_phase]:
		if not _phase_unlocked:
			_phase_unlocked = true
			_run_state.record_boss_active_response()
			(_run_state.run_history["boss_responses"] as Array).append(
				"charge_interrupted"
			)
			emit_signal("attack_landed", "The active response exposes the Charge.", 2.0)
			_emit_boss(
				SimEvent.TYPE_BOSS_RESPONSE,
				"charge_interrupted",
				{"progress": _response_progress}
			)
		_charge_stagger = 0.0
		_response_progress = RESPONSE_THRESHOLDS[_phase]
		_charge_timer = minf(12.0, _charge_timer + 4.0)
		_charge_warning_issued = false
	if _charge_timer > 0.0:
		return
	_run_state.damage_locomotive(18.0)
	_run_state.power = maxf(0.0, _run_state.power - 4.0)
	_run_state.supplies = maxf(0.0, _run_state.supplies - 4.0)
	_run_state.emit_signal("resources_changed")
	_charge_timer = 11.0
	_charge_stagger = 0.0
	_response_progress = 0.0 if not _phase_unlocked else RESPONSE_THRESHOLDS[_phase]
	_charge_warning_issued = false
	(_run_state.run_history["boss_responses"] as Array).append("charge_landed")
	if not _phase_unlocked:
		_prime_active_response()
	emit_signal("attack_landed", "The Longshadow's charge strikes the locomotive.", 9.0)
	_emit_boss(
		SimEvent.TYPE_BOSS_ATTACK,
		"charge_landed",
		{"damage": 18.0, "target": "locomotive"}
	)


func _register_active_response(amount: float, message: String) -> void:
	if _phase_unlocked or amount <= 0.0:
		return
	_response_progress += amount
	if _response_progress < RESPONSE_THRESHOLDS[_phase]:
		return
	_response_progress = RESPONSE_THRESHOLDS[_phase]
	_phase_unlocked = true
	_run_state.record_boss_active_response()
	(_run_state.run_history["boss_responses"] as Array).append(
		"%s_exposed" % phase_name().to_lower()
	)
	emit_signal("attack_landed", message, 2.0)
	_emit_boss(
		SimEvent.TYPE_BOSS_RESPONSE,
		"%s_exposed" % phase_name().to_lower(),
		{"message": message}
	)


func _phase_lens_multiplier() -> float:
	return 1.45 if _run_state.current_lens == PHASE_LENSES[_phase] else 0.78


func _advance_phase() -> void:
	_run_state.record_boss_phase_time(phase_name(), _phase_elapsed)
	if _phase >= Phase.CHARGE:
		_completed = true
		_active = false
		visible = false
		_run_state.external_speed_multiplier = 1.0
		_run_state.scrap = minf(RunState.SCRAP_MAX, _run_state.scrap + 12.0)
		_run_state.supplies = minf(RunState.SUPPLIES_MAX, _run_state.supplies + 10.0)
		_run_state.emit_signal("resources_changed")
		emit_signal("defeated")
		_emit_boss(
			SimEvent.TYPE_BOSS_DEFEAT,
			"defeated",
			{}
		)
		return
	_phase += 1
	_phase_max_health = PHASE_HEALTH[_phase]
	_health = _phase_max_health
	_attack_timer = 4.0
	_charge_timer = 11.0
	_charge_stagger = 0.0
	_target_switch_timer = 4.0
	_phase_elapsed = 0.0
	_transition_timer = TRANSITION_DURATION
	_phase_unlocked = false
	_response_progress = 0.0
	_charge_warning_issued = false
	_apply_phase_speed()
	_prime_active_response()
	(_run_state.run_history["boss_responses"] as Array).append(
		"entered_%s" % phase_name().to_lower()
	)
	emit_signal("phase_changed", phase_name())
	_emit_boss(
		SimEvent.TYPE_BOSS_PHASE_ENTRY,
		phase_name(),
		{
			"phase": _phase,
			"transition_timer": _transition_timer,
			"phase_max_health": _phase_max_health
		}
	)


func _prime_active_response() -> void:
	var focus_reserve: float = minf(
		RunState.LUMEN_MAX,
		_run_state.stats().focus_cost + 1.0
	)
	_run_state.lumen = maxf(_run_state.lumen, focus_reserve)
	_run_state.power = maxf(_run_state.power, RunState.DEFENSE_SALVO_POWER_COST)
	_run_state.focus_cooldown = 0.0
	_run_state.defense_salvo_cooldown = 0.0
	_run_state.emit_signal("resources_changed")


func _apply_phase_speed() -> void:
	match _phase:
		Phase.VEIL:
			_run_state.external_speed_multiplier = 0.82
		Phase.TETHER:
			_run_state.external_speed_multiplier = 0.58
		Phase.CHARGE:
			_run_state.external_speed_multiplier = 0.74


func _boss_position() -> Vector2:
	var bob: float = (
		0.0
		if bool(GameManager.get_setting("reduced_motion", false))
		else sin(_elapsed * 0.8) * 24.0
	)
	return Vector2(
		minf(_view_size.x * 0.68, _train_pos.x + 380.0),
		minf(
			_train_pos.y - 38.0,
			UITheme.gameplay_safe_bottom(_view_size) - 88.0
		) + bob
	)


func _apply_phase_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var next_health: float = maxf(0.0, _health - amount)
	var minimum_ratio: float = clampf(
		1.0 - _phase_elapsed / PHASE_MIN_DURATIONS[_phase],
		0.0,
		1.0
	)
	var response_floor: float = (
		0.0
		if _phase_unlocked
		else _phase_max_health * RESPONSE_HEALTH_FLOOR
	)
	_health = maxf(
		maxf(next_health, _phase_max_health * minimum_ratio),
		response_floor
	)


func _emit_boss(
	type: StringName,
	label: String,
	extra: Dictionary
) -> void:
	if _event_bus == null:
		return
	var payload: Dictionary = extra.duplicate()
	payload["phase"] = _phase
	payload["phase_name"] = phase_name()
	payload["label"] = label
	_event_bus.emit_sim(
		PRODUCER_ID,
		type,
		VisualStateIds.LONGSHADOW_ROOT,
		"",
		_run_state.travel_time,
		_boss_position(),
		Vector2.LEFT,
		float(payload.get("damage", 0.0)),
		&"shadow_ink",
		payload
	)
