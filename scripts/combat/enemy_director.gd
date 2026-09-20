class_name EnemyDirector
extends Node2D
## EnemyDirector
##
## Pooled enemy spawn and simulation. Draws enemies with vector primitives.
## Requests damage to RunState (locomotive/cars) through callbacks.

signal enemy_killed(kind: String, value: int)
signal threat_announced(kind: String, guidance: String)

const POOL_SIZE: int = 40

var _run_state: RunState
var _pool: Array = []
var _active: Array = []
var _elapsed: float = 0.0
var _spawn_cooldown: float = 3.0
var _wave_index: int = 0
var _view_size: Vector2 = Vector2(1280, 720)
var _train_pos: Vector2 = Vector2(320, 460)
var _light_profile: LightProfile = LightProfile.new()
var _reduced_motion: bool = false
var _announced_threats: Dictionary = {}


func setup(run_state: RunState, view_size: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	for i in range(POOL_SIZE):
		_pool.append(Enemy.new())
	set_process(true)


func set_train_pos(p: Vector2) -> void:
	_train_pos = p


func set_light_profile(profile: LightProfile) -> void:
	_light_profile = profile


func active_count() -> int:
	return _active.size()


func has_salvo_target() -> bool:
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if enemy.alive and enemy.position.distance_to(_train_pos) < 560.0:
			return true
	return false


func spawn_threat_waves(wave_count: int = 1) -> void:
	for index in range(maxi(0, wave_count)):
		_spawn_wave()


func _process(delta: float) -> void:
	if _run_state == null:
		return
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	var scaled: float = delta * (0.0 if _run_state.is_simulation_paused() else _run_state.speed_scale)
	_elapsed += scaled
	# Spawn logic scales with distance
	if not _run_state.boss_triggered:
		if _run_state.resume_grace_time <= 0.0:
			_spawn_cooldown -= scaled
		if _spawn_cooldown <= 0.0 and _run_state.resume_grace_time <= 0.0:
			_spawn_wave()
			var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
			_spawn_cooldown = lerp(4.5, 1.7, difficulty)
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


func _spawn_wave() -> void:
	_wave_index += 1
	var wave_rng := RandomNumberGenerator.new()
	wave_rng.seed = _run_state.run_seed ^ (_wave_index * 0xC0FFEE)
	var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
	var count: int = 1 + int(difficulty * 2.0)
	var kinds: Array[String] = ["Pursuer", "Boarder", "Drainer"]
	var kind_offset := posmod(_run_state.run_seed, kinds.size())
	for i in range(count):
		var kind: String = kinds[posmod(_wave_index - 1 + i + kind_offset, kinds.size())]
		var e: Enemy = _acquire()
		if e == null:
			return
		var cfg: Dictionary = _run_state.enemy_config.get(kind, {})
		e.init_from_config(kind, cfg)
		_announce_threat(kind)
		# scale with difficulty
		e.hp = e.hp * (1.0 + difficulty * 0.6)
		e.max_hp = e.hp
		e.damage = e.damage * (1.0 + difficulty * 0.4)
		# spawn to the right of view; drainers can spawn higher/lower
		match kind:
			"Boarder":
				e.boarder_car_index = maxi(0, _run_state.cars.size() - 1)
				e.target = _car_roof_target(e.boarder_car_index)
				e.position = Vector2(_view_size.x + 40.0, e.target.y - 90.0)
				e.role = "roof"
			"Drainer":
				e.position = Vector2(_view_size.x + 40, _train_pos.y - 80 - wave_rng.randf() * 40)
				e.target = Vector2(_train_pos.x + 100, _train_pos.y - 60)
				e.role = "air"
			_:
				e.position = Vector2(_view_size.x + 40, _train_pos.y + 2)
				e.target = _rear_target()
				e.role = "ground"


func _rear_target() -> Vector2:
	var x: float = _train_pos.x - 112.0 - float(_run_state.cars.size()) * 100.0
	return Vector2(x, _train_pos.y + 2)


func _car_roof_target(index: int) -> Vector2:
	if _run_state.cars.is_empty() or index < 0:
		return _train_pos + Vector2(-18.0, -70.0)
	var safe_index: int = clampi(index, 0, _run_state.cars.size() - 1)
	return Vector2(
		_train_pos.x - 110.0 - float(safe_index) * 100.0,
		_train_pos.y - 68.0
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
		e.target = Vector2(_train_pos.x + 74, _train_pos.y - 24)
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
		e.hp -= (
			base_damage
			* delta
			* _run_state.effective_priority("light")
			* _light_profile.damage_multiplier
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
			if not target.alive:
				continue
			target.hp -= (
				float(mount.get("damage", 0.0))
				* _run_state.effective_priority("defense")
				* delta
			)
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


func _apply_attack(e: Enemy) -> void:
	if _run_state.resume_grace_time > 0.0:
		return
	match e.kind:
		"Pursuer":
			var res: Dictionary = _run_state.damage_rear_car(e.damage)
			if res.get("destroyed", false):
				AudioManager.play("impact")
		"Boarder":
			if not _run_state.cars.is_empty() and e.boarder_car_index >= 0:
				_run_state.damage_car_at(e.boarder_car_index, e.damage)
				e.boarder_car_index -= 1
			else:
				_run_state.damage_locomotive(e.damage * 0.5)
				e.alive = false
			AudioManager.play("impact")
		"Drainer":
			_run_state.lumen = maxf(0.0, _run_state.lumen - e.damage * 0.3)
			AudioManager.play("impact")
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
		"wave_index": _wave_index
	}


func apply_checkpoint_state(state: Dictionary) -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
	_spawn_cooldown = maxf(0.1, float(state.get("spawn_cooldown", 3.0)))
	_wave_index = maxi(0, int(state.get("wave_index", 0)))


func clear_regular_enemies() -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
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
		_draw_attack_warning(e)
		_draw_hp(e)


func _draw_pursuer(e: Enemy) -> void:
	var p: Vector2 = e.position
	var body: PackedVector2Array = PackedVector2Array([
		p + Vector2(-20, 2), p + Vector2(-13, -13), p + Vector2(12, -16),
		p + Vector2(20, -5), p + Vector2(12, 9), p + Vector2(-14, 9)
	])
	draw_colored_polygon(body, e.color)
	draw_circle(p + Vector2(6, -4), 2.0, Color(1.0, 0.8, 0.4))
	draw_line(p + Vector2(-17, 10), p + Vector2(-27, 18), e.color, 4.0)
	draw_line(p + Vector2(10, 10), p + Vector2(22, 18), e.color, 4.0)


func _draw_boarder(e: Enemy) -> void:
	var p: Vector2 = e.position
	draw_circle(p, 7, e.color)
	draw_line(p + Vector2(0, 5), p + Vector2(0, 16), e.color, 4)
	draw_line(p + Vector2(0, 10), p + Vector2(-10, 3), e.color, 3)
	draw_line(p + Vector2(0, 10), p + Vector2(10, 3), e.color, 3)
	draw_line(p + Vector2(0, 16), p + Vector2(-8, 25), e.color, 3)
	draw_line(p + Vector2(0, 16), p + Vector2(8, 25), e.color, 3)
	draw_arc(p + Vector2(12, 2), 8.0, -PI * 0.5, PI * 0.5, 10, Color(1.0, 0.78, 0.32), 2.0)


func _draw_drainer(e: Enemy) -> void:
	var p: Vector2 = e.position
	var t: float = _elapsed * 4.0
	var r: float = 6.0 + sin(t) * 1.5
	draw_circle(p, r, e.color)
	draw_circle(p, r * 1.6, Color(e.color.r, e.color.g, e.color.b, 0.2))
	# tendrils
	for i in range(4):
		var a: float = i * PI * 0.5 + t
		draw_line(p, p + Vector2(cos(a), sin(a)) * 12.0, e.color, 1.5)
	if e.position.distance_to(e.target) < 190.0:
		draw_line(p, e.target, Color(e.color.r, e.color.g, e.color.b, 0.6), 2.5)
		draw_circle(e.target, 8.0 + sin(t) * 2.0, Color(e.color.r, e.color.g, e.color.b, 0.35))


func _draw_attack_warning(e: Enemy) -> void:
	if e.position.distance_to(e.target) >= 44.0 or e.attack_timer > e.attack_warning_time:
		return
	var ratio: float = 1.0 - clampf(e.attack_timer / e.attack_warning_time, 0.0, 1.0)
	draw_arc(
		e.position,
		28.0 + ratio * 8.0,
		0.0,
		TAU,
		28,
		Color(1.0, 0.72, 0.24, 0.45 + ratio * 0.5),
		3.0
	)
	var warning: String = {
		"Pursuer": "REAR",
		"Boarder": "BOARD",
		"Drainer": "LUMEN"
	}.get(e.kind, "THREAT")
	draw_string(
		ThemeDB.fallback_font,
		e.position + Vector2(-24.0, -34.0),
		warning,
		HORIZONTAL_ALIGNMENT_CENTER,
		48.0,
		10,
		Color(1.0, 0.86, 0.5)
	)


func _draw_hp(e: Enemy) -> void:
	if e.max_hp <= 0.0:
		return
	var ratio: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
	var w: float = 20.0
	var pos: Vector2 = e.position + Vector2(-w * 0.5, -22)
	draw_rect(Rect2(pos, Vector2(w, 3)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(pos, Vector2(w * ratio, 3)), Color(0.9, 0.3, 0.25))


func _announce_threat(kind: String) -> void:
	if bool(_announced_threats.get(kind, false)):
		return
	_announced_threats[kind] = true
	var guidance: String
	match kind:
		"Pursuer":
			guidance = "RAIL PURSUER - sweep the beam behind the train."
		"Boarder":
			guidance = "ROOF BOARDER - track it as it crosses the consist."
		"Drainer":
			guidance = "LUMEN DRAINER - break the tether before it drinks the lamp."
		_:
			guidance = "THREAT APPROACHING"
	emit_signal("threat_announced", kind, guidance)
