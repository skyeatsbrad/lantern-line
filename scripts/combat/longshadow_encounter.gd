class_name LongshadowEncounter
extends Node2D
## Three-phase finale: strip the Veil, sever the Tether, survive the Charge.

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


func setup(run_state: RunState, view_size: Vector2, train_pos: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	_train_pos = train_pos
	set_process(false)
	visible = false


func set_world_layout(
	view_size: Vector2,
	train_pos: Vector2,
	train_scale: float
) -> void:
	_view_size = view_size
	_train_pos = train_pos
	_train_scale = clampf(train_scale, 0.6, 1.0)
	queue_redraw()


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
	emit_signal("phase_changed", phase_name())
	queue_redraw()


func advance(delta: float, light_profile: LightProfile, stats: TrainStats) -> void:
	if not _active or _completed or _run_state.is_simulation_paused():
		return
	if _transition_timer > 0.0:
		_transition_timer = maxf(0.0, _transition_timer - delta)
		queue_redraw()
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
	queue_redraw()


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


func health_ratio() -> float:
	return clampf(_health / maxf(1.0, _phase_max_health), 0.0, 1.0)


func status_text() -> String:
	if _transition_timer > 0.0:
		return "LONGSHADOW - %s: brace for %.1fs" % [phase_name(), _transition_timer]
	match _phase:
		Phase.VEIL:
			return (
				"VEIL EXPOSED - finish it with %s light" % PHASE_LENSES[_phase]
				if _phase_unlocked
				else "VEIL LOCK %.0f%% - %s + FOCUS"
				% [_response_ratio() * 100.0, PHASE_LENSES[_phase]]
			)
		Phase.TETHER:
			return (
				"TETHER SEVERED - keep %s on the anchor" % PHASE_LENSES[_phase]
				if _phase_unlocked
				else "TETHER LOCK %.0f%% - %s + FOCUS/SALVO"
				% [_response_ratio() * 100.0, PHASE_LENSES[_phase]]
			)
		Phase.CHARGE:
			return (
				"CHARGE EXPOSED %.1fs - %s light" % [_charge_timer, PHASE_LENSES[_phase]]
				if _phase_unlocked
				else "CHARGE LOCK %.1fs - %s + FOCUS/SALVO %.0f%%"
				% [_charge_timer, PHASE_LENSES[_phase], _response_ratio() * 100.0]
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
	queue_redraw()
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
	elif _phase == Phase.TETHER:
		var result := _run_state.damage_rear_car(6.0)
		_attack_timer = 4.0
		if result.is_empty() and _run_state.cars.is_empty():
			_run_state.damage_locomotive(7.0)
		emit_signal("attack_landed", "The Tether tears at the rear coupling.", 5.0)
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
	if _charge_stagger >= RESPONSE_THRESHOLDS[_phase]:
		if not _phase_unlocked:
			_phase_unlocked = true
			_run_state.record_boss_active_response()
			(_run_state.run_history["boss_responses"] as Array).append(
				"charge_interrupted"
			)
			emit_signal("attack_landed", "The active response exposes the Charge.", 2.0)
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


func _response_ratio() -> float:
	return clampf(
		_response_progress / maxf(1.0, RESPONSE_THRESHOLDS[_phase]),
		0.0,
		1.0
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


func _draw() -> void:
	if not is_active():
		return
	var boss: Vector2 = _boss_position()
	var reduced_motion: bool = bool(
		GameManager.get_setting("reduced_motion", false)
	)
	var pulse: float = (
		1.0
		if reduced_motion
		else 1.0 + sin(_elapsed * 2.4) * 0.045
	)
	match _phase:
		Phase.VEIL:
			_draw_veil_body(boss, pulse)
		Phase.TETHER:
			_draw_tether_body(boss, pulse)
		Phase.CHARGE:
			_draw_charge_body(boss, pulse)
	_draw_transition_flourish(boss, reduced_motion)
	if _transition_timer > 0.0:
		_draw_boss_status(boss)
		return
	_draw_response_lock(boss)
	if _phase == Phase.VEIL:
		_draw_veil_mechanic(boss)
	elif _phase == Phase.TETHER:
		_draw_tether_mechanic(boss)
	elif _phase == Phase.CHARGE:
		_draw_charge_mechanic(boss)
	_draw_boss_status(boss)


func _draw_veil_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var left := _offset_points(center, [
		Vector2(-5.0, -52.0),
		Vector2(-42.0, -43.0),
		Vector2(-73.0, -12.0),
		Vector2(-61.0, 35.0),
		Vector2(-26.0, 57.0),
		Vector2(-8.0, 22.0)
	], scale)
	var right := _offset_points(center, [
		Vector2(7.0, -48.0),
		Vector2(36.0, -57.0),
		Vector2(68.0, -27.0),
		Vector2(73.0, 18.0),
		Vector2(34.0, 51.0),
		Vector2(10.0, 20.0)
	], scale)
	_draw_outlined_polygon(
		left,
		PresentationPalette.COAL,
		PresentationPalette.with_alpha(&"shadow_veil", 0.72),
		2.5
	)
	_draw_outlined_polygon(
		right,
		PresentationPalette.COAL.lerp(shadow, 0.18),
		PresentationPalette.with_alpha(&"shadow_veil", 0.72),
		2.5
	)
	draw_circle(center, 27.0 * scale, shadow.darkened(0.28))
	draw_circle(center + Vector2(-4.0, 2.0), 18.0 * scale, PresentationPalette.NIGHT_VOID)
	draw_arc(
		center,
		43.0 * scale,
		-2.72,
		-0.62,
		18,
		PresentationPalette.with_alpha(&"bone", 0.24),
		2.0
	)
	draw_arc(
		center,
		49.0 * scale,
		0.38,
		2.24,
		18,
		PresentationPalette.with_alpha(&"shadow_veil", 0.8),
		4.0
	)


func _draw_tether_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var upper := _offset_points(center, [
		Vector2(-45.0, -7.0),
		Vector2(-30.0, -52.0),
		Vector2(2.0, -68.0),
		Vector2(34.0, -43.0),
		Vector2(21.0, -8.0)
	], scale)
	var lower := _offset_points(center, [
		Vector2(-43.0, 8.0),
		Vector2(-24.0, 53.0),
		Vector2(8.0, 67.0),
		Vector2(39.0, 36.0),
		Vector2(20.0, 8.0)
	], scale)
	_draw_outlined_polygon(
		upper,
		PresentationPalette.COAL.lerp(shadow, 0.28),
		PresentationPalette.with_alpha(&"shadow_veil", 0.82),
		2.5
	)
	_draw_outlined_polygon(
		lower,
		PresentationPalette.COAL,
		PresentationPalette.with_alpha(&"shadow_veil", 0.82),
		2.5
	)
	draw_rect(
		Rect2(
			center + Vector2(-8.0, -48.0) * scale,
			Vector2(16.0, 96.0) * scale
		),
		PresentationPalette.NIGHT_VOID
	)
	draw_line(
		center + Vector2(-7.0, -30.0) * scale,
		center + Vector2(7.0, -7.0) * scale,
		PresentationPalette.with_alpha(&"bone", 0.38),
		2.0
	)
	draw_line(
		center + Vector2(-7.0, 30.0) * scale,
		center + Vector2(7.0, 7.0) * scale,
		PresentationPalette.with_alpha(&"bone", 0.38),
		2.0
	)


func _draw_charge_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var wedge := _offset_points(center, [
		Vector2(-66.0, 0.0),
		Vector2(-25.0, -47.0),
		Vector2(33.0, -39.0),
		Vector2(70.0, 0.0),
		Vector2(28.0, 43.0),
		Vector2(-27.0, 46.0)
	], scale)
	_draw_outlined_polygon(
		wedge,
		PresentationPalette.COAL.lerp(shadow, 0.34),
		PresentationPalette.with_alpha(&"danger", 0.82),
		3.0
	)
	var slit := _offset_points(center, [
		Vector2(-38.0, 0.0),
		Vector2(12.0, -15.0),
		Vector2(29.0, 0.0),
		Vector2(12.0, 15.0)
	], scale)
	draw_colored_polygon(slit, PresentationPalette.NIGHT_VOID)
	for spine in range(3):
		var y: float = float(spine - 1) * 22.0
		draw_line(
			center + Vector2(30.0, y) * scale,
			center + Vector2(58.0, y * 1.25) * scale,
			PresentationPalette.with_alpha(&"shadow_veil", 0.72),
			4.0
		)


func _draw_transition_flourish(center: Vector2, reduced_motion: bool) -> void:
	if _transition_timer <= 0.0:
		return
	var gate_duration: float = (
		ENTRANCE_DURATION
		if _phase == Phase.VEIL and _phase_elapsed <= 0.001
		else TRANSITION_DURATION
	)
	var flourish_duration: float = 1.1
	var elapsed: float = maxf(0.0, gate_duration - _transition_timer)
	if elapsed > flourish_duration:
		return
	var ratio: float = clampf(elapsed / flourish_duration, 0.0, 1.0)
	var visual_ratio: float = 1.0 if reduced_motion else ratio
	for ring in range(3):
		var radius: float = 70.0 + float(ring) * 15.0 + visual_ratio * 22.0
		var alpha: float = (0.48 - float(ring) * 0.1) * (1.0 - ratio * 0.7)
		for segment in range(3):
			var start: float = float(segment) * 2.12 + ratio * 0.6
			draw_arc(
				center,
				radius,
				start,
				start + 1.22,
				12,
				PresentationPalette.with_alpha(
					&"shadow_veil",
					alpha,
					UITheme.high_contrast()
				),
				3.5
			)


func _draw_response_lock(center: Vector2) -> void:
	var response_ratio: float = _response_ratio()
	if not _phase_unlocked:
		var base_color: Color = PresentationPalette.with_alpha(
			&"shadow_veil",
			0.46,
			UITheme.high_contrast()
		)
		for segment in range(3):
			var start: float = -PI * 0.5 + float(segment) * 2.14
			draw_arc(
				center,
				80.0,
				start,
				start + 1.36,
				14,
				base_color,
				4.0
			)
		draw_arc(
			center,
			80.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * response_ratio,
			42,
			PresentationPalette.color(&"brass", UITheme.high_contrast()),
			5.5
		)
	var response_text: String = (
		"EXPOSED"
		if _phase_unlocked
		else "%s + ACTIVE" % PHASE_LENSES[_phase].to_upper()
	)
	draw_string(
		UITheme.bold_font(),
		center + Vector2(-88.0, -124.0),
		response_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		176.0,
		UITheme.font_size(11),
		PresentationPalette.color(
			&"danger" if _phase_unlocked else &"brass",
			UITheme.high_contrast()
		)
	)


func _draw_veil_mechanic(center: Vector2) -> void:
	var rotation: float = (
		0.0
		if bool(GameManager.get_setting("reduced_motion", false))
		else _elapsed * 0.22
	)
	for segment in range(4):
		var start: float = rotation + float(segment) * 1.58
		draw_arc(
			center,
			64.0,
			start,
			start + 0.84,
			10,
			PresentationPalette.with_alpha(
				&"shadow_veil",
				0.66,
				UITheme.high_contrast()
			),
			5.0
		)


func _draw_tether_mechanic(center: Vector2) -> void:
	var anchor: Vector2 = current_target_position()
	var source: Vector2 = _train_pos + Vector2(38.0, -22.0) * _train_scale
	var bend := Vector2(lerpf(source.x, anchor.x, 0.52), anchor.y - 26.0)
	draw_polyline(
		PackedVector2Array([source, bend, anchor]),
		PresentationPalette.with_alpha(
			&"danger",
			0.78,
			UITheme.high_contrast()
		),
		4.0
	)
	for knot in range(1, 4):
		var t: float = float(knot) / 4.0
		var knot_pos: Vector2 = source.lerp(bend, minf(1.0, t * 1.7))
		if t > 0.58:
			knot_pos = bend.lerp(anchor, (t - 0.58) / 0.42)
		draw_rect(
			Rect2(knot_pos - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
			PresentationPalette.color(&"brass", UITheme.high_contrast())
		)
	var diamond := PackedVector2Array([
		anchor + Vector2(0.0, -17.0),
		anchor + Vector2(17.0, 0.0),
		anchor + Vector2(0.0, 17.0),
		anchor + Vector2(-17.0, 0.0)
	])
	_draw_outlined_polygon(
		diamond,
		PresentationPalette.COAL,
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		3.0
	)
	draw_string(
		UITheme.bold_font(),
		anchor + Vector2(-33.0, -23.0),
		"SEVER",
		HORIZONTAL_ALIGNMENT_CENTER,
		66.0,
		UITheme.font_size(10),
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _draw_charge_mechanic(center: Vector2) -> void:
	var charge_ratio: float = 1.0 - clampf(_charge_timer / 11.0, 0.0, 1.0)
	var warning_color: Color = PresentationPalette.with_alpha(
		&"danger",
		0.42 + charge_ratio * 0.5,
		UITheme.high_contrast()
	)
	for chevron in range(3):
		var x: float = lerpf(
			center.x - 84.0,
			_train_pos.x + 96.0 * _train_scale,
			float(chevron) / 3.0
		)
		var y: float = lerpf(
			center.y,
			_train_pos.y - 26.0 * _train_scale,
			float(chevron) / 3.0
		)
		var size: float = 14.0 + charge_ratio * 9.0
		draw_polyline(
			PackedVector2Array([
				Vector2(x + size, y - size),
				Vector2(x, y),
				Vector2(x + size, y + size)
			]),
			warning_color,
			3.0 + charge_ratio * 2.0
		)
	if _charge_timer <= 3.0:
		draw_string(
			UITheme.bold_font(),
			center + Vector2(-62.0, -148.0),
			"CHARGE %.1f" % _charge_timer,
			HORIZONTAL_ALIGNMENT_CENTER,
			124.0,
			UITheme.font_size(13),
			PresentationPalette.color(&"danger", UITheme.high_contrast())
		)


func _draw_boss_status(center: Vector2) -> void:
	var font_size: int = UITheme.font_size(11)
	var title: String = "LONGSHADOW // %s" % phase_name()
	draw_string(
		UITheme.bold_font(),
		center + Vector2(-88.0, -102.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		176.0,
		font_size,
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	var bar_pos: Vector2 = center + Vector2(-72.0, -88.0)
	draw_rect(
		Rect2(bar_pos, Vector2(144.0, 8.0)),
		PresentationPalette.color(&"night_void", UITheme.high_contrast())
	)
	draw_rect(
		Rect2(bar_pos, Vector2(144.0 * health_ratio(), 8.0)),
		PresentationPalette.color(
			&"danger" if health_ratio() <= 0.3 else &"shadow_veil",
			UITheme.high_contrast()
		)
	)
	draw_rect(
		Rect2(bar_pos, Vector2(144.0, 8.0)),
		PresentationPalette.with_alpha(&"bone", 0.54),
		false,
		1.0
	)


func _offset_points(
	center: Vector2,
	offsets: Array,
	scale: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for offset_variant in offsets:
		var offset: Vector2 = offset_variant
		points.append(center + offset * scale)
	return points


func _draw_outlined_polygon(
	points: PackedVector2Array,
	fill: Color,
	outline: Color,
	width: float
) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill)
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline, width, true)
