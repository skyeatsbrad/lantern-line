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
const TRANSITION_DURATION: float = 2.5

var _run_state: RunState
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _train_pos: Vector2 = Vector2(360.0, 500.0)
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


func setup(run_state: RunState, view_size: Vector2, train_pos: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	_train_pos = train_pos
	set_process(false)
	visible = false


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
		_transition_timer = 3.0
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
	_apply_phase_speed()
	emit_signal("phase_changed", phase_name())
	queue_redraw()


func advance(delta: float, light_profile: LightProfile, stats: TrainStats) -> void:
	if not _active or _completed or _run_state.is_simulation_paused():
		return
	if _transition_timer > 0.0:
		_transition_timer = maxf(0.0, _transition_timer - delta)
		queue_redraw()
		return
	var scaled := delta * _run_state.speed_scale
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
			* scaled
		)
	var defense_damage := _defense_damage(stats) * scaled
	var total_damage := beam_damage + defense_damage
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


func phase_name() -> String:
	return PHASE_NAMES[_phase]


func health_ratio() -> float:
	return clampf(_health / maxf(1.0, _phase_max_health), 0.0, 1.0)


func status_text() -> String:
	if _transition_timer > 0.0:
		return "LONGSHADOW - %s: brace for %.1fs" % [phase_name(), _transition_timer]
	match _phase:
		Phase.VEIL:
			return "LONGSHADOW - VEIL: hold it in the beam"
		Phase.TETHER:
			return "LONGSHADOW - TETHER: follow the anchor"
		Phase.CHARGE:
			return "LONGSHADOW - CHARGE %.1fs" % _charge_timer
		_:
			return "LONGSHADOW"


func current_target_position() -> Vector2:
	var boss := _boss_position()
	if _phase != Phase.TETHER:
		return boss
	var band_offsets: Array[float] = [-150.0, -46.0, 72.0]
	return Vector2(boss.x - 85.0, _train_pos.y + band_offsets[_target_band])


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
		"completed": _completed
	}


func _update_target(delta: float) -> void:
	if _phase != Phase.TETHER:
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
	if _health <= 0.0 and _phase_elapsed >= PHASE_MIN_DURATIONS[_phase]:
		_advance_phase()
	queue_redraw()
	return maxf(0.0, before - _health)


func _perform_phase_attack() -> void:
	if _phase == Phase.VEIL:
		_run_state.power = maxf(0.0, _run_state.power - 1.5)
		_run_state.lumen = maxf(0.0, _run_state.lumen - 2.0)
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
	if _charge_stagger >= 18.0:
		_charge_stagger = 0.0
		_charge_timer = minf(12.0, _charge_timer + 4.0)
		(_run_state.run_history["boss_responses"] as Array).append("charge_interrupted")
		emit_signal("attack_landed", "Focus fractures the gathering charge.", 2.0)
	if _charge_timer > 0.0:
		return
	_run_state.damage_locomotive(18.0)
	_run_state.power = maxf(0.0, _run_state.power - 4.0)
	_run_state.supplies = maxf(0.0, _run_state.supplies - 4.0)
	_run_state.emit_signal("resources_changed")
	_charge_timer = 11.0
	_charge_stagger = 0.0
	(_run_state.run_history["boss_responses"] as Array).append("charge_landed")
	emit_signal("attack_landed", "The Longshadow's charge strikes the locomotive.", 9.0)


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
	_apply_phase_speed()
	(_run_state.run_history["boss_responses"] as Array).append(
		"entered_%s" % phase_name().to_lower()
	)
	emit_signal("phase_changed", phase_name())


func _apply_phase_speed() -> void:
	match _phase:
		Phase.VEIL:
			_run_state.external_speed_multiplier = 0.82
		Phase.TETHER:
			_run_state.external_speed_multiplier = 0.58
		Phase.CHARGE:
			_run_state.external_speed_multiplier = 0.74


func _boss_position() -> Vector2:
	return Vector2(
		minf(_view_size.x * 0.68, _train_pos.x + 380.0),
		_train_pos.y - 38.0 + sin(_elapsed * 0.8) * 24.0
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
	_health = maxf(next_health, _phase_max_health * minimum_ratio)


func _draw() -> void:
	if not is_active():
		return
	var boss := _boss_position()
	var pulse := 1.0 + sin(_elapsed * 3.0) * 0.08
	var shadow := Color(0.28, 0.06, 0.24, 0.92)
	draw_circle(boss, 50.0 * pulse, Color(0.08, 0.03, 0.1, 0.88))
	draw_circle(boss, 34.0 * pulse, shadow)
	for index in range(6):
		var angle := _elapsed * 0.35 + float(index) * TAU / 6.0
		var end := boss + Vector2(cos(angle), sin(angle)) * (62.0 + 8.0 * sin(_elapsed + index))
		draw_line(boss, end, Color(0.45, 0.12, 0.38, 0.55), 5.0)
	if _transition_timer > 0.0:
		var transition_ratio: float = 1.0 - _transition_timer / maxf(0.01, TRANSITION_DURATION)
		for ring in range(3):
			draw_arc(
				boss,
				72.0 + float(ring) * 18.0 + transition_ratio * 20.0,
				0.0,
				TAU,
				48,
				Color(0.82, 0.3, 0.62, 0.45 - float(ring) * 0.1),
				4.0
			)

	if _phase == Phase.VEIL:
		draw_arc(boss, 66.0, 0.0, TAU, 48, Color(0.62, 0.28, 0.58, 0.7), 6.0)
	elif _phase == Phase.TETHER:
		var anchor := current_target_position()
		draw_line(_train_pos + Vector2(38.0, -22.0), anchor, Color(0.72, 0.18, 0.3, 0.8), 5.0)
		draw_circle(anchor, 15.0, Color(0.92, 0.56, 0.25, 0.9))
		draw_circle(anchor, 6.0, Color(1.0, 0.9, 0.62, 0.95))
	elif _phase == Phase.CHARGE:
		var charge_ratio := 1.0 - clampf(_charge_timer / 11.0, 0.0, 1.0)
		draw_arc(
			boss,
			62.0 + charge_ratio * 32.0,
			0.0,
			TAU,
			48,
			Color(0.95, 0.25, 0.2, 0.35 + charge_ratio * 0.55),
			4.0 + charge_ratio * 5.0
		)

	var bar_pos := boss + Vector2(-70.0, -88.0)
	draw_rect(Rect2(bar_pos, Vector2(140.0, 7.0)), Color(0.04, 0.03, 0.05, 0.95))
	draw_rect(
		Rect2(bar_pos, Vector2(140.0 * health_ratio(), 7.0)),
		Color(0.9, 0.3, 0.24, 0.95)
	)
