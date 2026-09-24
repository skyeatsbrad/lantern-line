class_name EnemyDirector
extends Node2D
## EnemyDirector
##
## Pooled deterministic enemy simulation owner. In v0.8 M2 this class holds no
## rendering responsibility: `EnemyViewPool` reads a reusable snapshot every
## presentation frame and performs all drawing. `EnemyDirector` remains a
## `Node2D` so existing runtime probes and QA can address it as a canvas item
## whose visibility gates the view pool, but it never overrides `_draw`.
##
## Requests damage on `RunState`, emits gameplay signals for compatibility,
## and emits `SimEvent`s on the `PresentationEventBus` for the M2 view
## boundary.

signal enemy_killed(kind: String, value: int)
signal threat_announced(kind: String, guidance: String)
signal defense_fired(target_position: Vector2, source_car_id: String, crewed: bool)
signal active_response(position: Vector2, message: String)
signal enemy_attack_landed(position: Vector2, kind: String)
signal pressure_brake_changed(active: bool)
signal simulation_tick_completed()

const POOL_SIZE: int = 40
const MAX_ACTIVE_DESKTOP: int = 12
const MAX_ACTIVE_COMPACT: int = 10
const WARD_SAFE_PRESSURE: int = 6
const PRODUCER_ID: String = "sim.enemy_director"

const EMITTED_TYPES: Array[StringName] = [
	SimEvent.TYPE_ENEMY_SPAWNED,
	SimEvent.TYPE_ENEMY_TELEGRAPHED,
	SimEvent.TYPE_ENEMY_ATTACKED,
	SimEvent.TYPE_ENEMY_HIT,
	SimEvent.TYPE_ENEMY_KILLED,
	SimEvent.TYPE_WARD_FORMED,
	SimEvent.TYPE_WARD_CRACKED,
	SimEvent.TYPE_WARD_SHATTERED,
	SimEvent.TYPE_DEFENSE_FIRED,
	SimEvent.TYPE_TRAIN_HIT,
	SimEvent.TYPE_CAR_HIT
]

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
var _announced_threats: Dictionary = {}
var _defense_fx_timer: float = 0.0
var _announced_ward: bool = false
var _ward_pending: bool = false
var _pressure_brake_active: bool = false
var _visual_id_counter: int = 0
var _event_bus: PresentationEventBus


func setup(run_state: RunState, view_size: Vector2) -> void:
	_run_state = run_state
	_view_size = view_size
	for i in range(POOL_SIZE):
		_pool.append(Enemy.new())
	_visual_id_counter = (run_state.run_seed & 0x0000FFFF) << 8
	set_process(true)


func attach_event_bus(bus: PresentationEventBus) -> void:
	_event_bus = bus
	if _event_bus != null:
		_event_bus.register_simulation_producer(PRODUCER_ID, EMITTED_TYPES)


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


func active_enemies() -> Array:
	return _active


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
	emit_signal("simulation_tick_completed")


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
		_assign_visual_id(e)
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
			_emit_sim(
				SimEvent.TYPE_WARD_FORMED,
				e.stable_id(),
				"",
				e.position,
				Vector2.LEFT,
				e.ward_max_hp,
				&"shadow_ward",
				{"kind": kind}
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
		_emit_sim(
			SimEvent.TYPE_ENEMY_SPAWNED,
			e.stable_id(),
			"",
			e.position,
			(e.target - e.position).normalized() if e.target != e.position else Vector2.LEFT,
			e.hp,
			_kind_material(kind),
			{"kind": kind, "role": e.role, "warded": e.warded}
		)
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


func _assign_visual_id(e: Enemy) -> void:
	_visual_id_counter += 1
	e.visual_id = _visual_id_counter


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
		var was_positive: bool = e.attack_timer > 0.0
		e.attack_timer -= delta
		if was_positive and e.attack_timer <= e.attack_warning_time:
			_emit_sim(
				SimEvent.TYPE_ENEMY_TELEGRAPHED,
				e.stable_id(),
				"",
				e.position,
				(e.target - e.position).normalized() if e.target != e.position else Vector2.LEFT,
				e.damage,
				_kind_material(e.kind),
				{"kind": e.kind, "role": e.role}
			)
		if e.attack_timer <= 0.0:
			_apply_attack(e)
			e.attack_timer = e.attack_interval
	if _light_profile != null and _light_profile.contains(e.position):
		var base_damage: float = 10.0 if e.kind == "Drainer" else 3.0
		if e.warded:
			if _light_profile.focused:
				var before_ward_hp: float = e.ward_hp
				e.ward_hp -= (
					18.0
					* delta
					* _run_state.effective_priority("light")
					* _light_profile.damage_multiplier
				)
				if before_ward_hp > e.ward_hp:
					_emit_sim(
						SimEvent.TYPE_WARD_CRACKED,
						e.stable_id(),
						"",
						e.position,
						_light_profile.direction,
						before_ward_hp - e.ward_hp,
						&"shadow_ward",
						{"ward_hp": e.ward_hp, "ward_max_hp": e.ward_max_hp}
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
			var damage_delta: float = (
				float(mount.get("damage", 0.0))
				* _run_state.effective_priority("defense")
				* delta
			)
			target.hp -= damage_delta
			if _defense_fx_timer <= 0.0:
				var source_car_id: String = String(mount.get("car_id", ""))
				emit_signal(
					"defense_fired",
					target.position,
					source_car_id,
					not _run_state.active_crew_for_car(source_car_id).is_empty()
				)
				_emit_sim(
					SimEvent.TYPE_DEFENSE_FIRED,
					VisualStateIds.defense_mount(source_car_id),
					target.stable_id(),
					target.position,
					(target.position - _train_pos).normalized() if target.position != _train_pos else Vector2.RIGHT,
					damage_delta,
					_mount_material(String(mount.get("mode", ""))),
					{
						"car_id": source_car_id,
						"mode": String(mount.get("mode", "")),
						"crewed": not _run_state.active_crew_for_car(source_car_id).is_empty(),
						"manual": false
					}
				)
				_defense_fx_timer = 0.32
			if target.hp <= 0.0:
				_kill_enemy(target)


func _kill_enemy(enemy: Enemy) -> void:
	if not enemy.alive:
		return
	enemy.alive = false
	emit_signal("enemy_killed", enemy.kind, enemy.value)
	_emit_sim(
		SimEvent.TYPE_ENEMY_KILLED,
		enemy.stable_id(),
		"",
		enemy.position,
		(_train_pos - enemy.position).normalized() if enemy.position != _train_pos else Vector2.LEFT,
		float(enemy.value),
		_kind_material(enemy.kind),
		{"kind": enemy.kind, "role": enemy.role}
	)


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
			var source_car_id: String = String(mount.get("car_id", ""))
			_emit_sim(
				SimEvent.TYPE_DEFENSE_FIRED,
				VisualStateIds.defense_mount(source_car_id),
				target.stable_id(),
				target.position,
				(target.position - _train_pos).normalized() if target.position != _train_pos else Vector2.RIGHT,
				damage,
				_mount_material(String(mount.get("mode", ""))),
				{
					"car_id": source_car_id,
					"mode": String(mount.get("mode", "")),
					"manual": true
				}
			)
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
	_emit_sim(
		SimEvent.TYPE_WARD_SHATTERED,
		enemy.stable_id(),
		"",
		enemy.position,
		(_train_pos - enemy.position).normalized() if enemy.position != _train_pos else Vector2.LEFT,
		enemy.ward_max_hp,
		&"shadow_ward",
		{"message": message}
	)


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
			_emit_sim(
				SimEvent.TYPE_ENEMY_ATTACKED,
				e.stable_id(),
				"train:rear",
				e.position,
				(_train_pos - e.position).normalized() if e.position != _train_pos else Vector2.LEFT,
				e.damage,
				_kind_material(e.kind),
				{"kind": e.kind, "against": "rear_car"}
			)
		"Boarder":
			if not _run_state.cars.is_empty() and e.boarder_car_index >= 0:
				var target_car_id: String = ""
				if e.boarder_car_index < _run_state.cars.size():
					target_car_id = String(
						(_run_state.cars[e.boarder_car_index] as Dictionary).get("id", "")
					)
				_run_state.damage_car_at(e.boarder_car_index, e.damage)
				_emit_sim(
					SimEvent.TYPE_ENEMY_ATTACKED,
					e.stable_id(),
					VisualStateIds.car(target_car_id),
					e.position,
					(_train_pos - e.position).normalized() if e.position != _train_pos else Vector2.LEFT,
					e.damage,
					_kind_material(e.kind),
					{"kind": e.kind, "against": "car", "car_index": e.boarder_car_index}
				)
				e.boarder_car_index -= 1
			else:
				_run_state.damage_locomotive(e.damage * 0.5)
				_emit_sim(
					SimEvent.TYPE_ENEMY_ATTACKED,
					e.stable_id(),
					VisualStateIds.TRAIN_LOCOMOTIVE,
					e.position,
					(_train_pos - e.position).normalized() if e.position != _train_pos else Vector2.LEFT,
					e.damage * 0.5,
					_kind_material(e.kind),
					{"kind": e.kind, "against": "locomotive"}
				)
				e.alive = false
		"Drainer":
			_run_state.lumen = maxf(0.0, _run_state.lumen - e.damage * 0.3)
			_emit_sim(
				SimEvent.TYPE_ENEMY_ATTACKED,
				e.stable_id(),
				VisualStateIds.TRAIN_LOCOMOTIVE,
				e.position,
				(_train_pos - e.position).normalized() if e.position != _train_pos else Vector2.LEFT,
				e.damage,
				_kind_material(e.kind),
				{"kind": e.kind, "against": "lumen"}
			)
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
				_emit_sim(
					SimEvent.TYPE_ENEMY_KILLED,
					e.stable_id(),
					"",
					e.position,
					Vector2.LEFT,
					0.0,
					_kind_material(e.kind),
					{"cause": "detach"}
				)
			else:
				e.position += Vector2(180, -40)


func checkpoint_state() -> Dictionary:
	return {
		"spawn_cooldown": _spawn_cooldown,
		"wave_index": _wave_index,
		"ward_pending": _ward_pending,
		"announced_ward": _announced_ward,
		"visual_id_counter": _visual_id_counter
	}


func apply_checkpoint_state(state: Dictionary) -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
	_spawn_cooldown = maxf(0.1, float(state.get("spawn_cooldown", 3.0)))
	_wave_index = maxi(0, int(state.get("wave_index", 0)))
	_ward_pending = bool(state.get("ward_pending", false))
	_announced_ward = bool(state.get("announced_ward", false))
	if state.has("visual_id_counter"):
		_visual_id_counter = maxi(_visual_id_counter, int(state.get("visual_id_counter", _visual_id_counter)))


func clear_regular_enemies() -> void:
	for enemy_variant in _active:
		_release(enemy_variant)
	_active.clear()
	if _pressure_brake_active:
		_pressure_brake_active = false
		emit_signal("pressure_brake_changed", false)


func write_snapshot(snapshot: PresentationSnapshot) -> void:
	for enemy_variant in _active:
		var enemy: Enemy = enemy_variant
		if not enemy.alive:
			continue
		var state: EnemyViewState = snapshot.acquire_enemy_state()
		state.visual_id = enemy.visual_id
		state.stable_id = enemy.stable_id()
		state.kind = enemy.kind
		state.role = enemy.role
		state.alive = true
		state.position = enemy.position
		state.target = enemy.target
		state.max_hp = enemy.max_hp
		state.hp_ratio = (
			clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
			if enemy.max_hp > 0.0
			else 0.0
		)
		state.attack_timer = enemy.attack_timer
		state.attack_warning_time = enemy.attack_warning_time
		if enemy.attack_warning_time > 0.0 and enemy.attack_timer <= enemy.attack_warning_time:
			state.attack_ratio = clampf(
				1.0 - enemy.attack_timer / enemy.attack_warning_time, 0.0, 1.0
			)
		else:
			state.attack_ratio = 0.0
		state.warded = enemy.warded
		state.ward_hp_ratio = (
			clampf(enemy.ward_hp / enemy.ward_max_hp, 0.0, 1.0)
			if enemy.warded and enemy.ward_max_hp > 0.0
			else 0.0
		)
		state.boarder_car_index = enemy.boarder_car_index


func elapsed_time() -> float:
	return _elapsed


func _emit_sim(
	type: StringName,
	source_id: String,
	target_id: String,
	position: Vector2,
	direction: Vector2,
	strength: float,
	material: StringName,
	payload: Dictionary
) -> void:
	if _event_bus == null:
		return
	_event_bus.emit_sim(
		PRODUCER_ID,
		type,
		source_id,
		target_id,
		_run_state.travel_time,
		position,
		direction,
		strength,
		material,
		payload
	)


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


static func _kind_material(kind: String) -> StringName:
	match kind:
		"Pursuer":
			return &"iron_hide"
		"Boarder":
			return &"canvas"
		"Drainer":
			return &"shadow_lumen"
		_:
			return &"unknown"


static func _mount_material(mode: String) -> StringName:
	match mode:
		"cannon":
			return &"heavy_shell"
		"flak":
			return &"flak_burst"
		_:
			return &"defense_bolt"
