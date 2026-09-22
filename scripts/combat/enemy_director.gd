class_name EnemyDirector
extends Node2D
## EnemyDirector
##
## Pooled enemy spawn and simulation. Draws enemies with vector primitives.
## Requests damage to RunState (locomotive/cars) through callbacks.

signal enemy_killed(kind: String, value: int)
signal threat_announced(kind: String, guidance: String)
signal defense_fired(target_position: Vector2, source_car_id: String, crewed: bool)
signal active_response(position: Vector2, message: String)
signal enemy_attack_landed(position: Vector2, kind: String)
signal pressure_brake_changed(active: bool)

const POOL_SIZE: int = 40
const MAX_ACTIVE_DESKTOP: int = 12
const MAX_ACTIVE_COMPACT: int = 10
const WARD_SAFE_PRESSURE: int = 6

var _run_state: RunState
var _pool: Array = []
var _active: Array = []
var _elapsed: float = 0.0
var _spawn_cooldown: float = 3.0
var _wave_index: int = 0
var _view_size: Vector2 = Vector2(1280, 720)
var _train_pos: Vector2 = Vector2(320, 460)
var _train_scale: float = 1.0
var _light_profile: LightProfile = LightProfile.new()
var _reduced_motion: bool = false
var _announced_threats: Dictionary = {}
var _defense_fx_timer: float = 0.0
var _announced_ward: bool = false
var _ward_pending: bool = false
var _pressure_brake_active: bool = false


func setup(run_state: RunState, view_size: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	for i in range(POOL_SIZE):
		_pool.append(Enemy.new())
	set_process(true)


func set_train_pos(p: Vector2) -> void:
	_train_pos = p


func set_world_layout(
	view_size: Vector2,
	train_pos: Vector2,
	train_scale: float
) -> void:
	_view_size = view_size
	_train_pos = train_pos
	_train_scale = clampf(train_scale, 0.6, 1.0)


func set_light_profile(profile: LightProfile) -> void:
	_light_profile = profile


func active_count() -> int:
	return _active.size()


func pressure_limit() -> int:
	return MAX_ACTIVE_COMPACT if _view_size.x < 1100.0 else MAX_ACTIVE_DESKTOP


func pressure_brake_threshold() -> int:
	return maxi(4, pressure_limit() - 2)


func has_salvo_target() -> bool:
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if enemy.alive and enemy.position.distance_to(_train_pos) < 560.0:
			return true
	return false


func has_warded_target() -> bool:
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if enemy.alive and enemy.warded:
			return true
	return false


func has_warded_target_in_response_range() -> bool:
	var response_range: float = maxf(
		380.0,
		_light_profile.range_px * 1.12 if _light_profile != null else 430.0
	)
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if (
			enemy.alive
			and enemy.warded
			and enemy.position.x > _train_pos.x + 20.0
			and enemy.position.distance_to(_train_pos) < response_range
		):
			return true
	return false


func nearest_warded_position(response_range_only: bool = false) -> Vector2:
	var best_position: Vector2 = _train_pos + Vector2(400.0, -40.0)
	var best_distance: float = INF
	var response_range: float = maxf(
		380.0,
		_light_profile.range_px * 1.12 if _light_profile != null else 430.0
	)
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if not enemy.alive or not enemy.warded:
			continue
		if (
			response_range_only
			and (
				enemy.position.x <= _train_pos.x + 20.0
				or enemy.position.distance_to(_train_pos) >= response_range
			)
		):
			continue
		var distance_squared: float = enemy.position.distance_squared_to(_train_pos)
		if distance_squared < best_distance:
			best_distance = distance_squared
			best_position = enemy.position
	return best_position


func spawn_threat_waves(wave_count: int = 1) -> void:
	for index in range(maxi(0, wave_count)):
		if not _spawn_wave():
			break


func _process(delta: float) -> void:
	if _run_state == null:
		return
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	_update_pressure_brake()
	var scaled: float = (
		0.0
		if _run_state.is_simulation_paused()
		else delta * _run_state.combat_speed_scale()
	)
	_defense_fx_timer = maxf(0.0, _defense_fx_timer - delta)
	_elapsed += scaled
	# Spawn logic scales with distance
	if not _run_state.boss_triggered:
		if _run_state.resume_grace_time <= 0.0:
			_spawn_cooldown -= scaled
		if _spawn_cooldown <= 0.0 and _run_state.resume_grace_time <= 0.0:
			var spawned: bool = (
				_spawn_wave()
				if _active.size() < pressure_brake_threshold()
				else false
			)
			var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
			_spawn_cooldown = lerp(4.5, 1.7, difficulty) if spawned else 0.65
	# Update active
	for e in _active:
		_update_enemy(e, scaled)
	_apply_defense_fire(scaled)
	# Cleanup
	var new_active: Array = []
	for e in _active:
		if e.alive:
			new_active.append(e)
		else:
			_release(e)
	_active = new_active
	queue_redraw()


func _update_pressure_brake() -> void:
	if _run_state.is_simulation_paused():
		return
	var should_brake: bool = (
		_run_state.speed_scale > 1.0
		and _active.size() >= pressure_brake_threshold()
	)
	if should_brake:
		_run_state.trigger_critical_slow(0.8)
	if should_brake != _pressure_brake_active:
		_pressure_brake_active = should_brake
		emit_signal("pressure_brake_changed", should_brake)


func _spawn_wave() -> bool:
	var active_before: int = _active.size()
	var available_slots: int = pressure_limit() - active_before
	if available_slots <= 0:
		return false
	_wave_index += 1
	var wave_rng := RandomNumberGenerator.new()
	wave_rng.seed = _run_state.run_seed ^ (_wave_index * 0xC0FFEE)
	var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
	var count: int = mini(1 + int(difficulty * 2.0), available_slots)
	if difficulty >= 0.6 and _wave_index % 20 == 0:
		_ward_pending = true
	var kinds: Array[String] = ["Pursuer", "Boarder", "Drainer"]
	var kind_offset := posmod(_run_state.run_seed, kinds.size())
	for i in range(count):
		var kind: String = kinds[posmod(_wave_index - 1 + i + kind_offset, kinds.size())]
		var e: Enemy = _acquire()
		if e == null:
			return i > 0
		var cfg: Dictionary = _run_state.enemy_config.get(kind, {})
		e.init_from_config(kind, cfg)
		_announce_threat(kind)
		# scale with difficulty
		e.hp = e.hp * (1.0 + difficulty * 0.6)
		e.max_hp = e.hp
		e.damage = e.damage * (1.0 + difficulty * 0.4)
		if _ward_pending and active_before <= WARD_SAFE_PRESSURE and i == 0:
			_ward_pending = false
			e.warded = true
			e.ward_max_hp = 12.0 + difficulty * 16.0
			e.ward_hp = e.ward_max_hp
			e.speed *= 0.65
			if not _announced_ward:
				_announced_ward = true
				emit_signal(
					"threat_announced",
					"Ward",
					"SHADOW WARD - auto-slow engaged. Use Focus or a Defense Salvo."
				)
		# spawn to the right of view; drainers can spawn higher/lower
		match kind:
			"Boarder":
				e.boarder_car_index = maxi(0, _run_state.cars.size() - 1)
				e.target = _car_roof_target(e.boarder_car_index)
				e.position = Vector2(
					_view_size.x + 40.0,
					e.target.y - 90.0 * _train_scale
				)
				e.role = "roof"
			"Drainer":
				e.position = Vector2(_view_size.x + 40, _train_pos.y - 80 - wave_rng.randf() * 40)
				e.target = Vector2(_train_pos.x + 100, _train_pos.y - 60)
				e.role = "air"
			_:
				e.position = Vector2(_view_size.x + 40, _train_pos.y + 2)
				e.target = _rear_target()
				e.role = "ground"
	return true


func _rear_target() -> Vector2:
	var x: float = (
		_train_pos.x
		- (112.0 + float(_run_state.cars.size()) * 100.0) * _train_scale
	)
	var y: float = minf(
		_train_pos.y + 2.0,
		UITheme.gameplay_safe_bottom(_view_size) - 27.0
	)
	return Vector2(x, y)


func _car_roof_target(index: int) -> Vector2:
	if _run_state.cars.is_empty() or index < 0:
		return _train_pos + Vector2(-18.0, -70.0) * _train_scale
	var safe_index: int = clampi(index, 0, _run_state.cars.size() - 1)
	return Vector2(
		_train_pos.x - (110.0 + float(safe_index) * 100.0) * _train_scale,
		_train_pos.y - 68.0 * _train_scale
	)


func _acquire() -> Enemy:
	for e in _pool:
		if not e.alive:
			e.alive = true
			_active.append(e)
			return e
	return null


func _release(e: Enemy) -> void:
	e.alive = false


func _update_enemy(e: Enemy, delta: float) -> void:
	if not e.alive:
		return
	# Update target based on role
	if e.role == "ground":
		e.target = _rear_target()
	elif e.role == "roof":
		if _run_state.cars.is_empty() or e.boarder_car_index < 0:
			e.target = _train_pos + Vector2(-18.0, -70.0)
		else:
			e.boarder_car_index = mini(e.boarder_car_index, _run_state.cars.size() - 1)
			e.target = _car_roof_target(e.boarder_car_index)
	elif e.role == "air":
		e.target = _train_pos + Vector2(74.0, -24.0) * _train_scale
	# Move toward target
	var to_target: Vector2 = e.target - e.position
	if to_target.length() > 4.0:
		e.position += to_target.normalized() * e.speed * delta
	# Attack when close
	if to_target.length() < 40.0:
		e.attack_timer -= delta
		if e.attack_timer <= 0.0:
			_apply_attack(e)
			e.attack_timer = e.attack_interval
	if _light_profile != null and _light_profile.contains(e.position):
		var base_damage: float = 10.0 if e.kind == "Drainer" else 3.0
		if e.warded:
			if _light_profile.focused:
				e.ward_hp -= (
					18.0
					* delta
					* _run_state.effective_priority("light")
					* _light_profile.damage_multiplier
				)
				if e.ward_hp <= 0.0:
					_break_ward(e, "Focus shattered a shadow ward.")
		else:
			e.hp -= (
				base_damage
				* delta
				* _run_state.effective_priority("light")
				* _light_profile.damage_multiplier
				* _lens_damage_multiplier(e.kind)
			)
	if e.hp <= 0.0:
		_kill_enemy(e)


func _apply_defense_fire(delta: float) -> void:
	if delta <= 0.0 or _run_state.effective_priority("defense") <= 0.0:
		return
	var available: Array[Enemy] = []
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if enemy.alive and enemy.position.distance_to(_train_pos) < 400.0:
			available.append(enemy)
	available.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.position.distance_squared_to(_train_pos) < b.position.distance_squared_to(_train_pos)
	)
	for mount_variant in _run_state.stats().defense_mounts:
		var mount: Dictionary = mount_variant
		var target_count: int = maxi(1, int(mount.get("targets", 1)))
		var candidates: Array[Enemy] = available
		if String(mount.get("mode", "")) == "flak":
			candidates = available.filter(func(enemy: Enemy) -> bool: return enemy.role == "air")
			if candidates.is_empty():
				candidates = available
		for index in range(mini(target_count, candidates.size())):
			var target: Enemy = candidates[index]
			if not target.alive or target.warded:
				continue
			target.hp -= (
				float(mount.get("damage", 0.0))
				* _run_state.effective_priority("defense")
				* delta
			)
			if _defense_fx_timer <= 0.0:
				var source_car_id: String = String(mount.get("car_id", ""))
				emit_signal(
					"defense_fired",
					target.position,
					source_car_id,
					not _run_state.active_crew_for_car(source_car_id).is_empty()
				)
				_defense_fx_timer = 0.32
			if target.hp <= 0.0:
				_kill_enemy(target)


func _kill_enemy(enemy: Enemy) -> void:
	if not enemy.alive:
		return
	enemy.alive = false
	emit_signal("enemy_killed", enemy.kind, enemy.value)


func fire_manual_salvo(stats: TrainStats) -> Dictionary:
	var available: Array[Enemy] = []
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if enemy.alive and enemy.position.distance_to(_train_pos) < 560.0:
			available.append(enemy)
	available.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.position.distance_squared_to(_train_pos) < b.position.distance_squared_to(_train_pos)
	)
	var positions: Array = []
	var total_damage: float = 0.0
	var kills: int = 0
	for mount_variant in stats.defense_mounts:
		var mount: Dictionary = mount_variant
		var candidates: Array[Enemy] = available
		if String(mount.get("mode", "")) == "flak":
			candidates = available.filter(
				func(enemy: Enemy) -> bool: return enemy.role == "air" or enemy.role == "roof"
			)
			if candidates.is_empty():
				candidates = available
		var target_count: int = mini(maxi(1, int(mount.get("targets", 1))), candidates.size())
		for index in range(target_count):
			var target: Enemy = candidates[index]
			if not target.alive:
				continue
			if target.warded:
				_break_ward(target, "Defense Salvo broke a shadow ward.")
			var damage: float = float(mount.get("damage", 0.0)) * 4.0
			if String(mount.get("mode", "")) == "cannon":
				damage *= 1.25
			target.hp -= damage
			total_damage += damage
			positions.append(target.position)
			if target.hp <= 0.0:
				kills += 1
				_kill_enemy(target)
	return {
		"positions": positions,
		"damage": total_damage,
		"kills": kills
	}


func _break_ward(enemy: Enemy, message: String) -> void:
	if not enemy.warded:
		return
	enemy.warded = false
	enemy.ward_hp = 0.0
	enemy.hp = 0.0
	if _run_state.focus_active_time > 0.0:
		_run_state.focus_active_time = 0.0
	_run_state.lumen = minf(RunState.LUMEN_MAX, _run_state.lumen + 2.0)
	_run_state.record_ward_break()
	_run_state.emit_signal("resources_changed")
	emit_signal("active_response", enemy.position, message)


func _lens_damage_multiplier(kind: String) -> float:
	match _run_state.current_lens:
		"Hearth":
			return 1.5 if kind == "Pursuer" else (0.82 if kind == "Drainer" else 1.0)
		"Pale":
			return 1.55 if kind == "Drainer" else (0.88 if kind == "Pursuer" else 1.0)
		_:
			return 1.45 if kind == "Boarder" else 1.0


func _apply_attack(e: Enemy) -> void:
	if _run_state.resume_grace_time > 0.0:
		return
	match e.kind:
		"Pursuer":
			_run_state.damage_rear_car(e.damage)
		"Boarder":
			if not _run_state.cars.is_empty() and e.boarder_car_index >= 0:
				_run_state.damage_car_at(e.boarder_car_index, e.damage)
				e.boarder_car_index -= 1
			else:
				_run_state.damage_locomotive(e.damage * 0.5)
				e.alive = false
		"Drainer":
			_run_state.lumen = maxf(0.0, _run_state.lumen - e.damage * 0.3)
	emit_signal("enemy_attack_landed", e.position, e.kind)


func on_detach(nearby_purge: float) -> void:
	# destroy/delay any ground enemies close to the rear
	var rear: Vector2 = _rear_target()
	for e in _active:
		if not e.alive:
			continue
		if e.position.distance_to(rear) < nearby_purge:
			if e.role == "ground":
				e.alive = false
				emit_signal("enemy_killed", e.kind, 0)
			else:
				e.position += Vector2(180, -40)


func checkpoint_state() -> Dictionary:
	return {
		"spawn_cooldown": _spawn_cooldown,
		"wave_index": _wave_index,
		"ward_pending": _ward_pending,
		"announced_ward": _announced_ward
	}


func apply_checkpoint_state(state: Dictionary) -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
	_spawn_cooldown = maxf(0.1, float(state.get("spawn_cooldown", 3.0)))
	_wave_index = maxi(0, int(state.get("wave_index", 0)))
	_ward_pending = bool(state.get("ward_pending", false))
	_announced_ward = bool(state.get("announced_ward", false))


func clear_regular_enemies() -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
	if _pressure_brake_active:
		_pressure_brake_active = false
		emit_signal("pressure_brake_changed", false)
	queue_redraw()


func _draw() -> void:
	for e in _active:
		if not e.alive:
			continue
		match e.kind:
			"Pursuer":
				_draw_pursuer(e)
			"Boarder":
				_draw_boarder(e)
			"Drainer":
				_draw_drainer(e)
		if UITheme.high_contrast():
			_draw_accessibility_label(e)
		if e.warded:
			_draw_ward(e)
		_draw_attack_warning(e)
		_draw_hp(e)


func _draw_ward(e: Enemy) -> void:
	var ratio: float = clampf(e.ward_hp / maxf(1.0, e.ward_max_hp), 0.0, 1.0)
	var rotation: float = 0.0 if _reduced_motion else _elapsed * 0.65
	var radius: float = 27.0
	var ward_color: Color = PresentationPalette.with_alpha(
		&"shadow_veil",
		0.48 + ratio * 0.42,
		UITheme.high_contrast()
	)
	var segments := [
		Vector2(0.05, 1.2),
		Vector2(1.72, 3.1),
		Vector2(3.72, 5.56)
	]
	for segment_variant in segments:
		var segment: Vector2 = segment_variant
		draw_arc(
			e.position,
			radius,
			segment.x + rotation,
			segment.y + rotation,
			12,
			ward_color,
			3.0 + ratio
		)
	for shard_index in range(3):
		var shard_angle: float = rotation + 1.4 + float(shard_index) * 2.05
		var shard_center: Vector2 = (
			e.position
			+ Vector2.from_angle(shard_angle) * (radius + 4.0)
		)
		draw_colored_polygon(
			PackedVector2Array([
				shard_center + Vector2.from_angle(shard_angle) * 5.0,
				shard_center + Vector2.from_angle(shard_angle + 2.35) * 4.0,
				shard_center + Vector2.from_angle(shard_angle - 2.35) * 4.0
			]),
			ward_color
		)
	var ward_font_size: int = UITheme.font_size(9)
	draw_string(
		UITheme.bold_font(),
		e.position + Vector2(-42.0, -47.0),
		"FOCUS / SALVO",
		HORIZONTAL_ALIGNMENT_CENTER,
		84.0,
		ward_font_size,
		PresentationPalette.color(&"shadow_veil", UITheme.high_contrast())
	)


func _draw_pursuer(e: Enemy) -> void:
	var p: Vector2 = e.position
	var body_color: Color = _threat_color("Pursuer")
	var outline: Color = _threat_outline()
	var body: PackedVector2Array = PackedVector2Array([
		p + Vector2(-29.0, -1.0),
		p + Vector2(-15.0, -15.0),
		p + Vector2(8.0, -18.0),
		p + Vector2(25.0, -7.0),
		p + Vector2(17.0, 10.0),
		p + Vector2(-13.0, 12.0)
	])
	_draw_outlined_polygon(body, body_color, outline, 2.0)
	var leg_points := [
		[Vector2(-15.0, 9.0), Vector2(-27.0, 19.0), Vector2(-34.0, 16.0)],
		[Vector2(1.0, 11.0), Vector2(-6.0, 23.0), Vector2(-15.0, 22.0)],
		[Vector2(15.0, 7.0), Vector2(27.0, 17.0), Vector2(34.0, 14.0)]
	]
	for leg_variant in leg_points:
		var leg: Array = leg_variant
		draw_polyline(
			PackedVector2Array([
				p + leg[0],
				p + leg[1],
				p + leg[2]
			]),
			body_color,
			4.0
		)
	draw_line(
		p + Vector2(-11.0, -12.0),
		p + Vector2(11.0, 5.0),
		PresentationPalette.with_alpha(&"bone", 0.32),
		1.5
	)
	draw_circle(
		p + Vector2(-20.0, -4.0),
		4.0,
		PresentationPalette.color(&"ember", UITheme.high_contrast())
	)
	draw_circle(p + Vector2(-20.0, -4.0), 1.5, PresentationPalette.BONE)


func _draw_boarder(e: Enemy) -> void:
	var p: Vector2 = e.position
	var body_color: Color = _threat_color("Boarder")
	var outline: Color = _threat_outline()
	draw_circle(p + Vector2(0.0, -20.0), 7.0, body_color)
	draw_arc(
		p + Vector2(0.0, -20.0),
		7.0,
		0.0,
		TAU,
		16,
		outline,
		1.5
	)
	_draw_outlined_polygon(
		PackedVector2Array([
			p + Vector2(-6.0, -14.0),
			p + Vector2(6.0, -14.0),
			p + Vector2(8.0, 9.0),
			p + Vector2(0.0, 15.0),
			p + Vector2(-8.0, 9.0)
		]),
		body_color,
		outline,
		1.5
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(-4.0, -9.0),
			p + Vector2(-19.0, -2.0),
			p + Vector2(-29.0, 12.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(5.0, -8.0),
			p + Vector2(17.0, 1.0),
			p + Vector2(22.0, 17.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(-3.0, 12.0),
			p + Vector2(-12.0, 28.0),
			p + Vector2(-21.0, 31.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(3.0, 12.0),
			p + Vector2(11.0, 29.0),
			p + Vector2(20.0, 32.0)
		]),
		body_color,
		4.0
	)
	var hook_center := p + Vector2(-29.0, 12.0)
	draw_arc(
		hook_center,
		10.0,
		-PI * 0.65,
		PI * 0.65,
		16,
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		3.0
	)
	draw_line(
		p + Vector2(22.0, 17.0),
		p + Vector2(29.0, 24.0),
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		2.0
	)


func _draw_drainer(e: Enemy) -> void:
	var p: Vector2 = e.position
	var t: float = 0.0 if _reduced_motion else _elapsed * 1.8
	var body_color: Color = _threat_color("Drainer")
	var outline: Color = _threat_outline()
	var shell := PackedVector2Array()
	for i in range(9):
		var angle: float = float(i) * TAU / 9.0
		var radius: float = 12.0 + float((i * 7) % 5)
		shell.append(p + Vector2.from_angle(angle + t * 0.08) * radius)
	_draw_outlined_polygon(shell, PresentationPalette.COAL, body_color, 2.5)
	draw_circle(p, 7.0, PresentationPalette.NIGHT_VOID)
	draw_arc(p, 8.0, 0.0, TAU, 20, outline, 1.5)
	var tendril_angles := [-2.72, -0.62, 0.92, 2.18]
	var tendril_lengths := [24.0, 18.0, 29.0, 21.0]
	for i in range(tendril_angles.size()):
		var sway: float = 0.0 if _reduced_motion else sin(t + float(i) * 1.7) * 0.16
		var angle: float = float(tendril_angles[i]) + sway
		var length: float = float(tendril_lengths[i])
		var joint: Vector2 = p + Vector2.from_angle(angle) * length * 0.55
		var end: Vector2 = (
			joint
			+ Vector2.from_angle(angle + (0.38 if i % 2 == 0 else -0.42))
			* length
			* 0.55
		)
		draw_polyline(
			PackedVector2Array([p, joint, end]),
			body_color,
			2.5
		)
		draw_circle(end, 2.5, body_color)
	if e.position.distance_to(e.target) < 190.0:
		var bend := Vector2(lerpf(p.x, e.target.x, 0.55), minf(p.y, e.target.y) - 18.0)
		draw_polyline(
			PackedVector2Array([p, bend, e.target]),
			PresentationPalette.with_alpha(
				&"drainer_glow",
				0.68,
				UITheme.high_contrast()
			),
			2.5
		)
		draw_rect(
			Rect2(e.target - Vector2(6.0, 6.0), Vector2(12.0, 12.0)),
			PresentationPalette.with_alpha(
				&"drainer_glow",
				0.38,
				UITheme.high_contrast()
			),
			false,
			2.0
		)


func _draw_accessibility_label(e: Enemy) -> void:
	var text: String = {
		"Pursuer": "REAR / HEARTH [2]",
		"Boarder": "ROOF / STANDARD [1]",
		"Drainer": "AIR / PALE [3]"
	}.get(e.kind, "THREAT")
	var label_center := Vector2(
		clampf(e.position.x, 78.0, _view_size.x - 78.0),
		maxf(e.position.y, 84.0)
	)
	var font_size: int = UITheme.font_size(10)
	var rect_size := Vector2(152.0, float(font_size) + 8.0)
	var label_offset_y: float = -104.0 if e.warded else -78.0
	var rect := Rect2(
		label_center + Vector2(-rect_size.x * 0.5, label_offset_y),
		rect_size
	)
	draw_rect(
		rect,
		PresentationPalette.with_alpha(&"night_void", 0.94, true)
	)
	draw_rect(
		rect,
		PresentationPalette.color(&"brass", true),
		false,
		1.5
	)
	draw_string(
		UITheme.bold_font(),
		rect.position + Vector2(4.0, float(font_size) + 2.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8.0,
		font_size,
		PresentationPalette.color(&"bone", true)
	)


func _draw_attack_warning(e: Enemy) -> void:
	if e.position.distance_to(e.target) >= 44.0 or e.attack_timer > e.attack_warning_time:
		return
	var ratio: float = 1.0 - clampf(e.attack_timer / e.attack_warning_time, 0.0, 1.0)
	var visual_ratio: float = 1.0 if _reduced_motion else ratio
	var warning_color: Color = PresentationPalette.with_alpha(
		&"danger",
		0.7 + ratio * 0.3,
		UITheme.high_contrast()
	)
	var radius: float = (40.0 if e.warded else 31.0) + visual_ratio * 5.0
	for quadrant in range(4):
		var start: float = float(quadrant) * PI * 0.5 + 0.13
		draw_arc(
			e.position,
			radius,
			start,
			start + 0.72,
			8,
			warning_color,
			3.0
		)
	draw_line(
		e.position,
		e.target,
		PresentationPalette.with_alpha(
			&"danger",
			0.18 + ratio * 0.22,
			UITheme.high_contrast()
		),
		1.5
	)
	draw_line(
		e.target + Vector2(-7.0, 0.0),
		e.target + Vector2(7.0, 0.0),
		warning_color,
		2.0
	)
	draw_line(
		e.target + Vector2(0.0, -7.0),
		e.target + Vector2(0.0, 7.0),
		warning_color,
		2.0
	)
	var warning: String = {
		"Pursuer": "REAR",
		"Boarder": "BOARD",
		"Drainer": "LUMEN"
	}.get(e.kind, "THREAT")
	var warning_font_size: int = UITheme.font_size(10)
	var warning_offset_y: float = 52.0 if e.warded else -40.0
	draw_string(
		UITheme.bold_font(),
		e.position + Vector2(-34.0, warning_offset_y),
		warning,
		HORIZONTAL_ALIGNMENT_CENTER,
		68.0,
		warning_font_size,
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _draw_hp(e: Enemy) -> void:
	if e.max_hp <= 0.0:
		return
	var ratio: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
	var w: float = 28.0
	var pos: Vector2 = e.position + Vector2(-w * 0.5, -31.0)
	draw_rect(
		Rect2(pos, Vector2(w, 4.0)),
		PresentationPalette.color(&"night_void", UITheme.high_contrast())
	)
	draw_rect(
		Rect2(pos, Vector2(w * ratio, 4.0)),
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _threat_color(kind: String) -> Color:
	match kind:
		"Pursuer":
			return PresentationPalette.color(
				&"pursuer_rust",
				UITheme.high_contrast()
			)
		"Boarder":
			return PresentationPalette.color(
				&"boarder_ochre",
				UITheme.high_contrast()
			)
		"Drainer":
			return PresentationPalette.color(
				&"drainer_glow",
				UITheme.high_contrast()
			)
		_:
			return PresentationPalette.color(&"danger", UITheme.high_contrast())


func _threat_outline() -> Color:
	return PresentationPalette.with_alpha(
		&"bone",
		0.9 if UITheme.high_contrast() else 0.48,
		UITheme.high_contrast()
	)


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


func _announce_threat(kind: String) -> void:
	if bool(_announced_threats.get(kind, false)):
		return
	_announced_threats[kind] = true
	var guidance: String
	match kind:
		"Pursuer":
			guidance = "RAIL PURSUER - sweep behind the train; Hearth burns it fastest."
		"Boarder":
			guidance = "ROOF BOARDER - track the roof; Standard light exposes it fastest."
		"Drainer":
			guidance = "LUMEN DRAINER - break the tether; Pale light sears it fastest."
		_:
			guidance = "THREAT APPROACHING"
	emit_signal("threat_announced", kind, guidance)
