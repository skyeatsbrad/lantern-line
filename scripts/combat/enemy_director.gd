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
var _boss_active: bool = false
var _view_size: Vector2 = Vector2(1280, 720)
var _train_pos: Vector2 = Vector2(320, 460)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _light_dir: Vector2 = Vector2.RIGHT
var _light_intensity: float = 1.0
var _reduced_motion: bool = false


func setup(run_state: RunState, view_size: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	_rng.seed = run_state.run_seed ^ 0xC0FFEE
	for i in range(POOL_SIZE):
		_pool.append(Enemy.new())
	set_process(true)


func set_train_pos(p: Vector2) -> void:
	_train_pos = p


func set_light(dir: Vector2, intensity: float) -> void:
	_light_dir = dir
	_light_intensity = intensity


func active_count() -> int:
	return _active.size()


func boss_active() -> bool:
	return _boss_active


func spawn_boss() -> void:
	if _boss_active:
		return
	var boss: Enemy = _acquire()
	if boss == null:
		return
	var cfg: Dictionary = _run_state.enemy_config.get("Boss", {})
	boss.init_from_config("Boss", cfg)
	boss.position = Vector2(_view_size.x + 40, _train_pos.y - 8)
	boss.target = Vector2(_train_pos.x + 80, _train_pos.y - 8)
	_boss_active = true


func spawn_threat_waves(wave_count: int = 1) -> void:
	for index in range(maxi(0, wave_count)):
		_spawn_wave()


func _process(delta: float) -> void:
	if _run_state == null:
		return
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	var scaled: float = delta * (0.0 if _run_state.paused else _run_state.speed_scale)
	_elapsed += scaled
	# Spawn logic scales with distance
	if not _boss_active and not _run_state.boss_triggered:
		_spawn_cooldown -= scaled
		if _spawn_cooldown <= 0.0:
			_spawn_wave()
			var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
			_spawn_cooldown = lerp(4.5, 1.7, difficulty)
	# Update active
	for e in _active:
		_update_enemy(e, scaled)
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
	var difficulty: float = clampf(_run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0)
	var count: int = 1 + int(difficulty * 2.0)
	for i in range(count):
		var kinds: Array = ["Pursuer", "Boarder", "Drainer"]
		var kind: String = kinds[_rng.randi() % kinds.size()]
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
				e.position = Vector2(_view_size.x + 40, _train_pos.y - 80 - _rng.randf() * 40)
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
		e.target = _rear_target() if e.kind != "Boss" else Vector2(_train_pos.x + 60, _train_pos.y - 8)
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
	# Damage from light cone (Drainer weak to light; others gently)
	if _light_intensity > 0.05:
		var origin: Vector2 = Vector2(_train_pos.x + 74, _train_pos.y - 24)
		var to_e: Vector2 = e.position - origin
		var dist: float = to_e.length()
		if dist < 500.0 * _light_intensity:
			var d: Vector2 = to_e.normalized()
			var dot: float = d.dot(_light_dir.normalized())
			if dot > 0.75:
				var dmg: float = (10.0 if e.kind == "Drainer" else 3.0) * delta * _run_state.priorities["light"]
				e.hp -= dmg
	# Turret damage from Defense car
	if _run_state._has_car_type("Defense") and _run_state._car_powered("Defense") and _run_state.priorities["defense"] > 0:
		var tur_dmg: float = 4.0 * float(_run_state.priorities["defense"]) * delta
		for c in _run_state.crew:
			if c.get("id") == "ilo":
				tur_dmg *= 1.0 + float(c["bonus"].get("turret_damage", 0.0))
		# only target closest; simplified: apply to all in range gently
		if e.position.distance_to(_train_pos) < 400.0:
			e.hp -= tur_dmg
	if e.hp <= 0.0:
		e.alive = false
		emit_signal("enemy_killed", e.kind, e.value)
		if e.kind == "Boss":
			_boss_active = false
			_run_state.boss_defeated = true
			# reward
			_run_state.scrap = clampf(_run_state.scrap + 12, 0, 200)
			_run_state.supplies = clampf(_run_state.supplies + 10, 0, 200)


func _apply_attack(e: Enemy) -> void:
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
		"Boss":
			_run_state.damage_locomotive(e.damage)
			AudioManager.play("alarm")


func on_detach(nearby_purge: float) -> void:
	# destroy/delay any ground enemies close to the rear
	var rear: Vector2 = _rear_target()
	for e in _active:
		if not e.alive:
			continue
		if e.position.distance_to(rear) < nearby_purge:
			if e.role == "ground" and e.kind != "Boss":
				e.alive = false
				emit_signal("enemy_killed", e.kind, 0)
			else:
				e.position += Vector2(180, -40)


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
			"Boss":
				_draw_boss(e)
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


func _draw_boss(e: Enemy) -> void:
	var p: Vector2 = e.position
	var body: PackedVector2Array = PackedVector2Array([
		p + Vector2(-40, 0), p + Vector2(-30, -30), p + Vector2(20, -36),
		p + Vector2(40, -14), p + Vector2(30, 12), p + Vector2(-30, 12)
	])
	draw_colored_polygon(body, e.color)
	# glowing eyes
	draw_circle(p + Vector2(-10, -18), 3, Color(1.0, 0.85, 0.4))
	draw_circle(p + Vector2(10, -18), 3, Color(1.0, 0.85, 0.4))


func _draw_hp(e: Enemy) -> void:
	if e.max_hp <= 0.0:
		return
	var ratio: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
	var w: float = 20.0 if e.kind != "Boss" else 60.0
	var pos: Vector2 = e.position + Vector2(-w * 0.5, -22)
	draw_rect(Rect2(pos, Vector2(w, 3)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(pos, Vector2(w * ratio, 3)), Color(0.9, 0.3, 0.25))
