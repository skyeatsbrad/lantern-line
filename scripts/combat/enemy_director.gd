class_name EnemyDirector
extends Node2D
## EnemyDirector
##
## Pooled enemy spawn and simulation. Draws enemies with vector primitives.
## Requests damage to RunState (locomotive/cars) through callbacks.

signal enemy_killed(kind: String, value: int)

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
		# scale with difficulty
		e.hp = e.hp * (1.0 + difficulty * 0.6)
		e.max_hp = e.hp
		e.damage = e.damage * (1.0 + difficulty * 0.4)
		# spawn to the right of view; drainers can spawn higher/lower
		match kind:
			"Boarder":
				e.position = Vector2(_view_size.x + 40, _train_pos.y - 60)
				e.target = Vector2(_train_pos.x + 20, _train_pos.y - 60)
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
			* float(_run_state.priorities["light"])
			* _light_profile.damage_multiplier
		)
	if e.hp <= 0.0:
		_kill_enemy(e)


func _apply_defense_fire(delta: float) -> void:
	if delta <= 0.0 or int(_run_state.priorities.get("defense", 0)) <= 0:
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
				* float(_run_state.priorities["defense"])
				* delta
			)
			if target.hp <= 0.0:
				_kill_enemy(target)


func _kill_enemy(enemy: Enemy) -> void:
	if not enemy.alive:
		return
	enemy.alive = false
	emit_signal("enemy_killed", enemy.kind, enemy.value)
func _apply_attack(e: Enemy) -> void:
	if _run_state.resume_grace_time > 0.0:
		return
	match e.kind:
		"Pursuer":
			var res: Dictionary = _run_state.damage_rear_car(e.damage)
			if res.get("destroyed", false):
				AudioManager.play("impact")
		"Boarder":
			_run_state.damage_random_car(e.damage * 0.5)
			_run_state.damage_locomotive(e.damage * 0.3)
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
		_draw_hp(e)


func _draw_pursuer(e: Enemy) -> void:
	var p: Vector2 = e.position
	var body: PackedVector2Array = PackedVector2Array([
		p + Vector2(-14, 0), p + Vector2(-8, -10), p + Vector2(10, -12),
		p + Vector2(14, -4), p + Vector2(8, 6), p + Vector2(-10, 6)
	])
	draw_colored_polygon(body, e.color)
	draw_circle(p + Vector2(6, -4), 2.0, Color(1.0, 0.8, 0.4))


func _draw_boarder(e: Enemy) -> void:
	var p: Vector2 = e.position
	draw_circle(p, 6, e.color)
	draw_line(p + Vector2(0, 4), p + Vector2(0, 12), e.color, 3)
	draw_line(p + Vector2(0, 12), p + Vector2(-6, 20), e.color, 2)
	draw_line(p + Vector2(0, 12), p + Vector2(6, 20), e.color, 2)


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


func _draw_hp(e: Enemy) -> void:
	if e.max_hp <= 0.0:
		return
	var ratio: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
	var w: float = 20.0
	var pos: Vector2 = e.position + Vector2(-w * 0.5, -22)
	draw_rect(Rect2(pos, Vector2(w, 3)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(pos, Vector2(w * ratio, 3)), Color(0.9, 0.3, 0.25))
