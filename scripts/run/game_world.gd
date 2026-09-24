extends Node
## Top-level run coordinator and the only cross-system signal wiring point.

signal run_ended(victory: bool)

enum RunMode {
	TRAVEL,
	ROUTE_REVEAL,
	STATION,
	BOSS,
	ENDING,
	ENDED
}

const DATA_CARS: String = "res://data/cars.json"
const DATA_LENSES: String = "res://data/lenses.json"
const DATA_ENEMIES: String = "res://data/enemies.json"
const DATA_CREW: String = "res://data/crew.json"
const DATA_ROUTES: String = "res://data/route_events.json"
const REVEAL_INTERVAL: float = 52.0
const DETACH_HOLD_SECONDS: float = 0.85
const ACCESSIBLE_DETACH_HOLD_SECONDS: float = 0.45
const VICTORY_REVEAL_SECONDS: float = 4.5
const DEFEAT_REVEAL_SECONDS: float = 1.6
const EVENT_PRODUCER_ID: String = "sim.game_world"

var run_state: RunState
var route_director: RouteDirector

var _world_renderer: WorldRenderer
var _world_sprite_view: WorldSpriteView
var _route_projection: RouteProjection
var _train_renderer: TrainRenderer
var _train_sprite_view: TrainSpriteView
var _train_controller: TrainController
var _pointer_router: PointerRouter
var _enemy_director: EnemyDirector
var _enemy_view_pool: EnemyViewPool
var _longshadow: LongshadowEncounter
var _longshadow_view: LongshadowView
var _effects: EffectsLayer
var _vfx_pool: VfxPool
var _hud: HUD
var _route_choice: RouteChoice
var _station_panel: StationPanel
var _end_screen: EndScreen
var _settings_panel: SettingsPanel
var _guide_panel: GuidePanel
var _presentation_director: PresentationDirector
var _presentation_metrics: PresentationMetrics
var _presentation_snapshot: PresentationSnapshot
var _event_bus: PresentationEventBus
var _presentation_router: PresentationRouter

var _view_size: Vector2 = Vector2(1280, 720)
var _mode: RunMode = RunMode.TRAVEL
var _reveal_timer: float = REVEAL_INTERVAL
var _last_autosave: float = 0.0
var _train_screen_pos: Vector2 = Vector2(360, 500)
var _train_visual_scale: float = 1.0
var _route_commit_pending: bool = false
var _route_reroll_index: int = 0
var _end_committed: bool = false
var _end_screen_shown: bool = false
var _ending_timer: float = 0.0
var _ending_victory: bool = false
var _detach_hold_active: bool = false
var _detach_hold_time: float = 0.0
var _light_profile: LightProfile
var _locomotive_critical_notified: bool = false
var _overlay_open: bool = false
var _overlay_was_paused: bool = false
var _route_events: Array = []
var _route_context: Dictionary = {
	"category": "neutral",
	"event_id": "",
	"danger": 0
}
var _contextual_tutorial_active: bool = false
var _contextual_tutorial_stage: int = 0
var _boss_defeat_emitted: bool = false
var _dawn_arrival_emitted: bool = false
var _last_route_reveal_sequence: int = 0
var _last_route_context_id: String = ""
var _startup_audit_issues: Array[String] = []
var _current_dawn_progress: float = 0.0
var _reference_scenario_id: String = ""
var _reference_frame_label: String = ""
var _reference_frame_time: float = 0.0
var _reference_frame_index: int = 0

# Compatibility read-only properties for the v0.1 probes.
var _reveal_open: bool:
	get:
		return _mode == RunMode.ROUTE_REVEAL
var _station_open: bool:
	get:
		return _mode == RunMode.STATION
var _ended: bool:
	get:
		return _mode == RunMode.ENDING or _mode == RunMode.ENDED


func bootstrap(run_seed: int, resume: Dictionary) -> void:
	_view_size = get_viewport().get_visible_rect().size
	if _view_size.x < 100.0:
		_view_size = Vector2(1280, 720)

	var configs: Dictionary = {
		"cars": _load_json(DATA_CARS).get("cars", {}),
		"lenses": _load_json(DATA_LENSES).get("lenses", {}),
		"enemies": _load_json(DATA_ENEMIES).get("enemies", {}),
		"crew": _load_json(DATA_CREW).get("crew", []),
		"events": _load_json(DATA_ROUTES).get("events", [])
	}
	_route_events = configs["events"]
	var normalized_resume: Dictionary = RunSnapshot.normalize(resume)
	var run_resume: Dictionary = (
		RunSnapshot.run_state_data(normalized_resume)
		if not normalized_resume.is_empty()
		else {}
	)
	var world_resume: Dictionary = (
		RunSnapshot.world_state(normalized_resume)
		if not normalized_resume.is_empty()
		else {}
	)
	_contextual_tutorial_active = (
		normalized_resume.is_empty()
		and not bool(
			GameManager.get_setting("contextual_tutorial_seen", false)
		)
		and not _automation_run()
	)

	run_state = RunState.new()
	run_state.setup(run_seed, configs)
	if not run_resume.is_empty():
		run_state.apply_dict(run_resume)
		run_state.resume_grace_time = 3.0
	_refresh_route_context()
	_compute_world_layout()

	route_director = RouteDirector.new()
	route_director.setup(run_state.run_seed, configs["events"], configs["lenses"])

	_presentation_snapshot = PresentationSnapshot.new()

	_event_bus = PresentationEventBus.new()
	_event_bus.name = "PresentationEventBus"
	add_child(_event_bus)
	_event_bus.register_simulation_producer(
		EVENT_PRODUCER_ID,
		[
			SimEvent.TYPE_TRAIN_HIT,
			SimEvent.TYPE_CAR_HIT,
			SimEvent.TYPE_CAR_CRITICAL,
			SimEvent.TYPE_CAR_DESTROYED,
			SimEvent.TYPE_ROUTE_REVEAL,
			SimEvent.TYPE_ROUTE_COMMIT,
			SimEvent.TYPE_STATION_ARRIVAL,
			SimEvent.TYPE_STATION_DEPARTURE,
			SimEvent.TYPE_DETACH_RELEASED,
			SimEvent.TYPE_DAWN_ARRIVAL
		]
	)

	_presentation_router = PresentationRouter.new(
		GameManager.resolved_presentation_profile(),
		GameManager.presentation_features()
	)

	_presentation_metrics = PresentationMetrics.new()
	_presentation_metrics.name = "PresentationMetrics"
	add_child(_presentation_metrics)

	_presentation_director = PresentationDirector.new()
	_presentation_director.name = "PresentationDirector"
	_presentation_director.setup(run_state, _view_size)
	add_child(_presentation_director)

	var world_layer: Node2D = Node2D.new()
	world_layer.name = "WorldLayer"
	add_child(world_layer)

	_world_renderer = WorldRenderer.new()
	_world_renderer.setup(_view_size)
	_world_renderer.set_route_context(_route_context)
	world_layer.add_child(_world_renderer)

	_world_sprite_view = WorldSpriteView.new()
	_world_sprite_view.name = "WorldSpriteView"
	world_layer.add_child(_world_sprite_view)

	_route_projection = RouteProjection.new()
	_route_projection.setup(
		_view_size,
		_train_screen_pos,
		_train_visual_scale
	)
	world_layer.add_child(_route_projection)

	_enemy_director = EnemyDirector.new()
	_enemy_director.setup(run_state, _view_size)
	_enemy_director.attach_event_bus(_event_bus)
	_enemy_director.set_world_layout(
		_view_size,
		_train_screen_pos,
		_train_visual_scale
	)
	_enemy_director.apply_checkpoint_state(world_resume.get("enemy_state", {}))
	world_layer.add_child(_enemy_director)

	_enemy_view_pool = EnemyViewPool.new()
	_enemy_view_pool.name = "EnemyViewPool"
	world_layer.add_child(_enemy_view_pool)

	_train_renderer = TrainRenderer.new()
	_train_renderer.setup(run_state)
	_train_renderer.set_layout(_train_screen_pos, _train_visual_scale)
	world_layer.add_child(_train_renderer)

	_train_sprite_view = TrainSpriteView.new()
	_train_sprite_view.name = "TrainSpriteView"
	world_layer.add_child(_train_sprite_view)

	_longshadow = LongshadowEncounter.new()
	_longshadow.setup(run_state, _view_size, _train_screen_pos)
	_longshadow.attach_event_bus(_event_bus)
	_longshadow.set_world_layout(
		_view_size,
		_train_screen_pos,
		_train_visual_scale
	)
	world_layer.add_child(_longshadow)

	_longshadow_view = LongshadowView.new()
	_longshadow_view.name = "LongshadowView"
	world_layer.add_child(_longshadow_view)

	_train_controller = TrainController.new()
	_train_controller.set_origin_screen(_train_lamp_position())
	add_child(_train_controller)

	_pointer_router = PointerRouter.new()
	_pointer_router.name = "PointerRouter"
	add_child(_pointer_router)

	_effects = EffectsLayer.new()
	_effects.setup(run_state.run_seed)
	world_layer.add_child(_effects)

	_vfx_pool = VfxPool.new()
	_vfx_pool.name = "VfxPool"
	world_layer.add_child(_vfx_pool)
	_presentation_director.state_changed.connect(
		_world_renderer.set_presentation_state
	)
	_presentation_director.state_changed.connect(
		_train_renderer.set_presentation_state
	)

	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	_hud = HUD.new()
	ui_layer.add_child(_hud)
	_hud.setup(run_state, configs["lenses"])

	_route_choice = RouteChoice.new()
	_route_choice.visible = false
	_route_choice.anchor_right = 1.0
	_route_choice.anchor_bottom = 1.0
	ui_layer.add_child(_route_choice)

	_station_panel = StationPanel.new()
	_station_panel.visible = false
	_station_panel.anchor_right = 1.0
	_station_panel.anchor_bottom = 1.0
	ui_layer.add_child(_station_panel)

	_end_screen = EndScreen.new()
	_end_screen.visible = false
	_end_screen.anchor_right = 1.0
	_end_screen.anchor_bottom = 1.0
	ui_layer.add_child(_end_screen)

	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.anchor_right = 1.0
	_settings_panel.anchor_bottom = 1.0
	ui_layer.add_child(_settings_panel)

	_guide_panel = GuidePanel.new()
	_guide_panel.visible = false
	_guide_panel.anchor_right = 1.0
	_guide_panel.anchor_bottom = 1.0
	ui_layer.add_child(_guide_panel)

	_register_presentation_consumers()
	_wire_signals()
	_apply_presentation_router()
	_startup_audit_issues = _event_bus.run_startup_audit()
	if not _startup_audit_issues.is_empty():
		for issue in _startup_audit_issues:
			push_error("[event_bus] audit: %s" % issue)
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not GameManager.settings_changed.is_connected(_on_layout_settings_changed):
		GameManager.settings_changed.connect(_on_layout_settings_changed)
	if not GameManager.settings_changed.is_connected(_apply_presentation_router):
		GameManager.settings_changed.connect(_apply_presentation_router)
	_reveal_timer = maxf(0.0, float(world_resume.get("reveal_timer", REVEAL_INTERVAL)))
	if run_state.boss_triggered and not run_state.boss_defeated:
		run_state.distance = minf(run_state.distance, RunState.BOSS_GATE_DISTANCE)
		_enemy_director.clear_regular_enemies()
		_longshadow.start(world_resume.get("boss_state", {}))
		_set_mode(RunMode.BOSS)
	elif String(world_resume.get("run_mode", "travel")) == "station" and not run_state.station_completed:
		_set_mode(RunMode.STATION)
		_station_panel.present(run_state)
	else:
		_set_mode(RunMode.TRAVEL)
	refresh_presentation_now()
	set_process(true)
	set_process_input(true)
	if _contextual_tutorial_active:
		call_deferred("_begin_contextual_tutorial")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _refresh_route_context() -> void:
	_route_context = {
		"category": "neutral",
		"event_id": "",
		"danger": 0
	}
	if run_state == null or run_state.route_history.is_empty():
		return
	var event_id: String = String(run_state.route_history.back())
	for event_variant in _route_events:
		var event: Dictionary = event_variant
		if String(event.get("id", "")) != event_id:
			continue
		_route_context = {
			"category": String(event.get("category", "neutral")),
			"event_id": event_id,
			"danger": int(event.get("danger", 0))
		}
		return


func _register_presentation_consumers() -> void:
	_event_bus.register_presentation_consumer(
		EnemyViewPool.CONSUMER_ID,
		[
			SimEvent.TYPE_ENEMY_SPAWNED,
			SimEvent.TYPE_ENEMY_TELEGRAPHED,
			SimEvent.TYPE_ENEMY_ATTACKED,
			SimEvent.TYPE_ENEMY_HIT,
			SimEvent.TYPE_ENEMY_KILLED,
			SimEvent.TYPE_WARD_FORMED,
			SimEvent.TYPE_WARD_CRACKED,
			SimEvent.TYPE_WARD_SHATTERED
		],
		_enemy_view_pool.on_sim_event
	)
	_event_bus.register_presentation_consumer(
		"view.longshadow_view",
		[
			SimEvent.TYPE_BOSS_PHASE_ENTRY,
			SimEvent.TYPE_BOSS_RESPONSE,
			SimEvent.TYPE_BOSS_ATTACK,
			SimEvent.TYPE_BOSS_DEFEAT
		],
		_longshadow_view.on_sim_event
	)
	_event_bus.register_presentation_consumer(
		"view.train_sprite_view",
		[
			SimEvent.TYPE_TRAIN_HIT,
			SimEvent.TYPE_CAR_HIT,
			SimEvent.TYPE_CAR_CRITICAL,
			SimEvent.TYPE_CAR_DESTROYED,
			SimEvent.TYPE_DEFENSE_FIRED,
			SimEvent.TYPE_DETACH_RELEASED
		],
		_train_sprite_view.on_sim_event
	)
	_event_bus.register_presentation_consumer(
		"view.world_sprite_view",
		[
			SimEvent.TYPE_ROUTE_REVEAL,
			SimEvent.TYPE_ROUTE_COMMIT,
			SimEvent.TYPE_STATION_ARRIVAL,
			SimEvent.TYPE_STATION_DEPARTURE,
			SimEvent.TYPE_DAWN_ARRIVAL
		],
		_world_sprite_view.on_sim_event
	)
	_event_bus.register_presentation_consumer(
		VfxPool.CONSUMER_ID,
		[
			SimEvent.TYPE_TRAIN_HIT,
			SimEvent.TYPE_CAR_HIT,
			SimEvent.TYPE_CAR_CRITICAL,
			SimEvent.TYPE_CAR_DESTROYED,
			SimEvent.TYPE_DEFENSE_FIRED,
			SimEvent.TYPE_ENEMY_ATTACKED,
			SimEvent.TYPE_ENEMY_HIT,
			SimEvent.TYPE_ENEMY_KILLED,
			SimEvent.TYPE_WARD_CRACKED,
			SimEvent.TYPE_WARD_SHATTERED,
			SimEvent.TYPE_DETACH_RELEASED,
			SimEvent.TYPE_BOSS_PHASE_ENTRY,
			SimEvent.TYPE_BOSS_RESPONSE,
			SimEvent.TYPE_BOSS_ATTACK,
			SimEvent.TYPE_BOSS_DEFEAT,
			SimEvent.TYPE_DAWN_ARRIVAL,
			PresentationEvent.TYPE_CAMERA_IMPULSE,
			PresentationEvent.TYPE_PARTICLE_BURST,
			PresentationEvent.TYPE_UI_EMPHASIS
		],
		_vfx_pool.on_event
	)


func _wire_signals() -> void:
	_hud.request_lens.connect(_on_lens)
	_hud.request_priority.connect(_on_priority_level)
	_hud.request_pause.connect(_on_pause)
	_hud.request_speed.connect(_on_speed)
	_hud.request_focus.connect(_on_focus)
	_hud.request_defense_salvo.connect(_on_defense_salvo)
	_hud.request_field_action.connect(_on_field_action)
	_hud.request_settings.connect(_open_settings)
	_hud.request_guide.connect(_open_guide)
	_hud.detach_hold_changed.connect(_on_detach_hold_changed)
	_pointer_router.held_actions_cancelled.connect(
		_on_pointer_holds_cancelled
	)

	_route_choice.chosen.connect(_on_route_chosen)
	_route_choice.closed.connect(_on_reveal_closed)
	_route_choice.reroll_requested.connect(_on_route_reroll)

	_station_panel.state_changed.connect(_save_checkpoint)
	_station_panel.closed.connect(_on_station_closed)

	_end_screen.closed.connect(_on_end_closed)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.guide_requested.connect(_on_settings_guide_requested)
	_guide_panel.closed.connect(_on_guide_closed)
	_enemy_director.enemy_killed.connect(_on_enemy_killed)
	_enemy_director.threat_announced.connect(_on_threat_announced)
	_enemy_director.defense_fired.connect(_on_defense_fired)
	_enemy_director.active_response.connect(_on_active_response)
	_enemy_director.enemy_attack_landed.connect(_on_enemy_attack_landed)
	_enemy_director.pressure_brake_changed.connect(_on_pressure_brake_changed)
	_enemy_director.simulation_tick_completed.connect(
		_on_enemy_simulation_tick_completed
	)
	_longshadow.phase_changed.connect(_on_boss_phase_changed)
	_longshadow.attack_landed.connect(_on_boss_attack)
	_longshadow.defeated.connect(_on_boss_defeated)
	run_state.car_destroyed.connect(_on_car_destroyed)
	run_state.car_damaged.connect(_on_car_damaged)
	run_state.car_critical.connect(_on_car_critical)
	run_state.locomotive_damaged.connect(_on_locomotive_damaged)


func _process(delta: float) -> void:
	if _mode == RunMode.ENDED:
		return
	if _mode == RunMode.ENDING:
		_process_ending(delta)
		return

	run_state.distance_cap = (
		RunState.BOSS_GATE_DISTANCE
		if _mode == RunMode.BOSS
		else RunState.JOURNEY_TARGET
	)
	run_state.tick(delta)
	_process_detach_hold(delta)
	_process_contextual_tutorial()

	if _mode == RunMode.TRAVEL and not run_state.is_simulation_paused():
		if not run_state.boss_triggered:
			_reveal_timer -= delta * run_state.effective_speed_scale()

	_update_presentational_state()
	if _mode == RunMode.BOSS:
		_longshadow.advance(delta, _light_profile, run_state.stats())
	_update_aim()

	if run_state.defeat:
		_begin_end(false)
		return
	if _mode == RunMode.TRAVEL:
		if run_state.boss_defeated and run_state.distance >= RunState.JOURNEY_TARGET:
			run_state.victory = true
			_begin_end(true)
			return
		if not run_state.boss_triggered and run_state.distance >= RunState.BOSS_DISTANCE:
			_start_boss()
		elif not run_state.station_completed and run_state.distance >= RunState.STATION_DISTANCE:
			_open_station()
		elif not run_state.boss_triggered and _reveal_timer <= 0.0:
			_open_reveal()

	if _mode == RunMode.TRAVEL or _mode == RunMode.BOSS:
		_last_autosave += delta
		if _last_autosave >= 8.0:
			_last_autosave = 0.0
			_save_checkpoint()


func _update_aim() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var mouse_position: Vector2 = viewport.get_mouse_position()
	if _mode == RunMode.ROUTE_REVEAL:
		var route_index := _route_projection.index_for_cursor_y(mouse_position.y)
		_route_projection.set_selected_index(route_index)
		_route_choice.set_selected_index(route_index)
		_train_controller.aim_towards(_route_projection.endpoint_for_index(route_index))
	else:
		var aim_position := (
			_pointer_router.current_aim(mouse_position)
			if is_instance_valid(_pointer_router)
			else mouse_position
		)
		_train_controller.aim_towards(aim_position)


func _on_enemy_simulation_tick_completed() -> void:
	_update_presentation_snapshot(_current_dawn_progress)


func _update_presentational_state() -> void:
	_refresh_world_layout()
	if (
		run_state.locomotive_hp / maxf(1.0, run_state.locomotive_max_hp) > 0.45
	):
		_locomotive_critical_notified = false
	var current_stats: TrainStats = run_state.stats()
	_light_profile = LightProfile.build(
		run_state,
		current_stats,
		_train_controller.light_direction,
		_train_lamp_position()
	)
	_world_renderer.update_state(
		run_state.distance,
		_light_profile,
		_train_screen_pos
	)
	_enemy_director.set_train_pos(_train_screen_pos)
	_enemy_director.set_light_profile(_light_profile)
	var speed_ratio: float = (
		0.0
		if run_state.is_simulation_paused()
		else current_stats.speed / 80.0
	)
	AudioManager.set_wheel_rate(clampf(speed_ratio * 4.0, 0.2, 6.0))
	var dawn_progress: float = (
		clampf(
			(run_state.distance - RunState.BOSS_GATE_DISTANCE)
			/ (RunState.JOURNEY_TARGET - RunState.BOSS_GATE_DISTANCE),
			0.0,
			1.0
		)
		if run_state.boss_defeated
		else 0.0
	)
	_current_dawn_progress = dawn_progress
	_effects.set_dawn_progress(dawn_progress)
	if (
		run_state.boss_defeated
		and not _dawn_arrival_emitted
		and dawn_progress > 0.0
	):
		_dawn_arrival_emitted = true
		_emit_sim_event(
			SimEvent.TYPE_DAWN_ARRIVAL,
			"sim.game_world",
			VisualStateIds.TRAIN_LOCOMOTIVE,
			_train_screen_pos,
			Vector2.RIGHT,
			dawn_progress,
			&"dawn",
			{"distance": run_state.distance}
		)
	_presentation_director.update_state(
		_mode_name(),
		_enemy_director.active_count(),
		_enemy_director.pressure_limit(),
		_longshadow.is_active(),
		_longshadow.phase_name() if _longshadow.is_active() else "",
		dawn_progress
	)
	var world_layer: Node = get_node_or_null("WorldLayer")
	if world_layer is Node2D:
		(world_layer as Node2D).position = _effects.shake_offset()
	if _mode == RunMode.BOSS and _longshadow.is_active():
		_hud.set_boss_status(_longshadow.status_text(), _longshadow.health_ratio())
	else:
		_hud.set_boss_status("")


func _update_presentation_snapshot(dawn_progress: float) -> void:
	if _presentation_snapshot == null:
		return
	_presentation_snapshot.begin_frame()
	_presentation_snapshot.elapsed = run_state.travel_time
	_presentation_snapshot.simulation_time = run_state.travel_time
	_presentation_snapshot.enemy_elapsed = _enemy_director.elapsed_time()
	_presentation_snapshot.view_size = _view_size
	_presentation_snapshot.train_position = _train_screen_pos
	_presentation_snapshot.train_scale = _train_visual_scale
	_presentation_snapshot.train_stable_id = VisualStateIds.TRAIN_LOCOMOTIVE
	_presentation_snapshot.train_max_hp = run_state.locomotive_max_hp
	_presentation_snapshot.train_hp_ratio = clampf(
		run_state.locomotive_hp / maxf(1.0, run_state.locomotive_max_hp),
		0.0,
		1.0
	)
	_presentation_snapshot.distance = run_state.distance
	_presentation_snapshot.distance_ratio = clampf(
		run_state.distance / RunState.JOURNEY_TARGET, 0.0, 1.0
	)
	_presentation_snapshot.current_lens = run_state.current_lens
	_presentation_snapshot.dawn_progress = dawn_progress
	_presentation_snapshot.tension = float(
		_presentation_director.snapshot().get("tension", 0.0)
	)
	_presentation_snapshot.mode_name = _mode_name()
	_presentation_snapshot.boss_phase_name = (
		_longshadow.phase_name() if _longshadow.is_active() else ""
	)
	_presentation_snapshot.reduced_motion = bool(
		GameManager.get_setting("reduced_motion", false)
	)
	_presentation_snapshot.reduced_flashes = bool(
		GameManager.get_setting("reduced_flashes", false)
	)
	_presentation_snapshot.high_contrast = bool(
		GameManager.get_setting("high_contrast", false)
	)
	_presentation_snapshot.simulation_paused = run_state.is_simulation_paused()
	_presentation_snapshot.reference_scenario_id = _reference_scenario_id
	_presentation_snapshot.reference_frame_label = _reference_frame_label
	_presentation_snapshot.reference_frame_time = _reference_frame_time
	_presentation_snapshot.reference_frame_index = _reference_frame_index
	_presentation_snapshot.set_route_context(_route_context)
	for car_variant in run_state.cars:
		var car: Dictionary = car_variant
		var car_state: CarViewState = _presentation_snapshot.acquire_car_state()
		car_state.populate(car)
	if _light_profile != null:
		_presentation_snapshot.light_origin = _light_profile.origin
		_presentation_snapshot.light_direction = _light_profile.direction
		_presentation_snapshot.light_range = _light_profile.range_px
		_presentation_snapshot.light_spread = _light_profile.spread_radians
		_presentation_snapshot.light_focused = _light_profile.focused
		_presentation_snapshot.light_intensity = _light_profile.intensity
		_presentation_snapshot.light_damage_multiplier = _light_profile.damage_multiplier
	_enemy_director.write_snapshot(_presentation_snapshot)
	_longshadow.write_snapshot(_presentation_snapshot)
	if _enemy_view_pool != null:
		_enemy_view_pool.update_snapshot(_presentation_snapshot)
	if _longshadow_view != null:
		_longshadow_view.update_snapshot(_presentation_snapshot)
	if _train_sprite_view != null:
		_train_sprite_view.update_snapshot(_presentation_snapshot)
	if _world_sprite_view != null:
		_world_sprite_view.update_snapshot(_presentation_snapshot)
	if _vfx_pool != null:
		_vfx_pool.update_snapshot(_presentation_snapshot)


func _apply_presentation_router() -> void:
	if _presentation_router == null:
		return
	var profile: String = GameManager.resolved_presentation_profile()
	var features: Dictionary = GameManager.presentation_features()
	_presentation_router.apply_profile(profile, features)
	var vector_fallback: bool = _presentation_router.is_vector_fallback()
	var effects_baked: bool = _presentation_router.is_category_baked(
		PresentationRouter.CATEGORY_EFFECTS
	)
	# Fallback renderers stay visible unless a category is toggled to baked.
	if is_instance_valid(_world_renderer):
		_world_renderer.visible = not _presentation_router.is_category_baked(
			PresentationRouter.CATEGORY_WORLD
		)
	if is_instance_valid(_train_renderer):
		_train_renderer.visible = not _presentation_router.is_category_baked(
			PresentationRouter.CATEGORY_TRAIN
		)
	# Enemy and Longshadow vector paths always route through the view pool;
	# the pool switches its own draw path when baked is on.
	if is_instance_valid(_enemy_view_pool):
		_enemy_view_pool.apply_profile(profile, features)
		_enemy_view_pool.set_baked_enabled(
			_presentation_router.is_category_baked(
				PresentationRouter.CATEGORY_ENEMIES
			)
		)
	if is_instance_valid(_longshadow_view):
		_longshadow_view.apply_profile(profile, features)
		_longshadow_view.set_baked_enabled(
			_presentation_router.is_category_baked(
				PresentationRouter.CATEGORY_LONGSHADOW
			)
		)
	if is_instance_valid(_train_sprite_view):
		_train_sprite_view.apply_profile(profile, features)
		_train_sprite_view.set_baked_enabled(
			_presentation_router.is_category_baked(
				PresentationRouter.CATEGORY_TRAIN
			)
		)
	if is_instance_valid(_world_sprite_view):
		_world_sprite_view.apply_profile(profile, features)
		_world_sprite_view.set_baked_enabled(
			_presentation_router.is_category_baked(
				PresentationRouter.CATEGORY_WORLD
			)
		)
	if is_instance_valid(_effects):
		_effects.visible = not effects_baked
	if is_instance_valid(_vfx_pool):
		_vfx_pool.apply_profile(profile, features)
		_vfx_pool.set_baked_enabled(effects_baked)
	if vector_fallback:
		# Vector fallback is a hard rollback: force all baked flags off.
		if is_instance_valid(_world_renderer):
			_world_renderer.visible = true
		if is_instance_valid(_train_renderer):
			_train_renderer.visible = true
		if is_instance_valid(_effects):
			_effects.visible = true
		if is_instance_valid(_vfx_pool):
			_vfx_pool.set_baked_enabled(false)


func presentation_snapshot() -> PresentationSnapshot:
	return _presentation_snapshot


func presentation_router() -> PresentationRouter:
	return _presentation_router


func event_bus() -> PresentationEventBus:
	return _event_bus


func _emit_sim_event(
	type: StringName,
	source_id: String,
	target_id: String,
	position: Vector2,
	direction: Vector2,
	strength: float,
	material: StringName,
	payload: Dictionary
) -> int:
	if _event_bus == null or run_state == null:
		return 0
	return _event_bus.emit_sim(
		EVENT_PRODUCER_ID,
		type,
		source_id,
		target_id,
		run_state.travel_time,
		position,
		direction,
		strength,
		material,
		payload
	)


func startup_audit_issues() -> Array[String]:
	return _startup_audit_issues.duplicate()


func refresh_presentation_now() -> void:
	# Public entry point used by runtime probes and QA tooling that stop the
	# game world tick after preparing a scenario but still need one snapshot
	# update so views can draw.
	if run_state == null:
		return
	_refresh_world_layout()
	_light_profile = LightProfile.build(
		run_state,
		run_state.stats(),
		_train_controller.light_direction if is_instance_valid(_train_controller) else Vector2.RIGHT,
		_train_lamp_position()
	)
	if is_instance_valid(_world_renderer):
		_world_renderer.update_state(
			run_state.distance,
			_light_profile,
			_train_screen_pos
		)
	if is_instance_valid(_enemy_director):
		_enemy_director.set_light_profile(_light_profile)
	var dawn_progress: float = 0.0
	if run_state.boss_defeated:
		dawn_progress = clampf(
			(run_state.distance - RunState.BOSS_GATE_DISTANCE)
			/ (RunState.JOURNEY_TARGET - RunState.BOSS_GATE_DISTANCE),
			0.0,
			1.0
		)
	_current_dawn_progress = dawn_progress
	_update_presentation_snapshot(dawn_progress)


func set_reference_capture_frame(
	scenario_id: String,
	frame_label: String,
	frame_time: float,
	frame_index: int
) -> void:
	_reference_scenario_id = scenario_id
	_reference_frame_label = frame_label
	_reference_frame_time = maxf(0.0, frame_time)
	_reference_frame_index = maxi(0, frame_index)
	set_reference_capture_state(true, _reference_frame_time)
	refresh_presentation_now()


func set_reference_capture_state(enabled: bool, frame_time: float) -> void:
	if is_instance_valid(_world_renderer):
		_world_renderer.set_reference_capture_state(enabled, frame_time)
	if is_instance_valid(_train_renderer):
		_train_renderer.set_reference_capture_state(enabled, frame_time)
	if is_instance_valid(_hud):
		_hud.set_reference_capture_state(enabled, frame_time)
	if is_instance_valid(_effects):
		_effects.set_reference_capture_state(enabled, frame_time)
	if is_instance_valid(_vfx_pool):
		_vfx_pool.set_reference_capture_state(enabled, frame_time)


func _compute_world_layout() -> void:
	_view_size = get_viewport().get_visible_rect().size
	if _view_size.x < 100.0:
		_view_size = Vector2(1280.0, 720.0)
	var visual_slots: int = RunState.START_SLOT_CAPACITY
	if run_state != null:
		visual_slots = maxi(run_state.slot_capacity, run_state.cars.size())
	var layout: Dictionary = calculate_world_layout(_view_size, visual_slots)
	_train_screen_pos = layout.get("train_position", Vector2(360.0, 500.0))
	_train_visual_scale = float(layout.get("train_scale", 1.0))


func calculate_world_layout(
	viewport_size: Vector2,
	visual_slots: int
) -> Dictionary:
	var safe_view := viewport_size
	if safe_view.x < 100.0:
		safe_view = Vector2(1280.0, 720.0)
	var compact: bool = UITheme.compact_layout(safe_view)
	var anchor_ratio: float = 0.46 if compact else 0.40
	var anchor_x: float = safe_view.x * anchor_ratio
	var fitted_slots: int = clampi(
		visual_slots,
		RunState.START_SLOT_CAPACITY,
		RunState.MAX_SLOT_CAPACITY
	)
	var rear_extent: float = (
		TrainRenderer.LOCO_WIDTH * 0.5
		+ float(fitted_slots) * (TrainRenderer.CAR_WIDTH + 8.0)
	)
	var train_scale: float = clampf(
		(anchor_x - 18.0) / maxf(1.0, rear_extent),
		0.68,
		1.0
	)
	var safe_bottom: float = UITheme.gameplay_safe_bottom(safe_view)
	var train_position := Vector2(
		anchor_x,
		minf(
			safe_view.y * 0.72,
			safe_bottom - 40.0
		)
	)
	return {
		"train_position": train_position,
		"train_scale": train_scale,
		"rear_left": train_position.x - rear_extent * train_scale,
		"train_floor": train_position.y + 24.0 * train_scale,
		"safe_bottom": safe_bottom
	}


func _refresh_world_layout(force: bool = false) -> void:
	var previous_view := _view_size
	var previous_position := _train_screen_pos
	var previous_scale := _train_visual_scale
	_compute_world_layout()
	if (
		not force
		and previous_view.is_equal_approx(_view_size)
		and previous_position.is_equal_approx(_train_screen_pos)
		and is_equal_approx(previous_scale, _train_visual_scale)
	):
		return
	if is_instance_valid(_world_renderer):
		_world_renderer.set_view_size(_view_size)
	if is_instance_valid(_presentation_director):
		_presentation_director.set_view_size(_view_size)
	if is_instance_valid(_route_projection):
		_route_projection.set_world_layout(
			_view_size,
			_train_screen_pos,
			_train_visual_scale
		)
	if is_instance_valid(_enemy_director):
		_enemy_director.set_world_layout(
			_view_size,
			_train_screen_pos,
			_train_visual_scale
		)
	if is_instance_valid(_train_renderer):
		_train_renderer.set_layout(_train_screen_pos, _train_visual_scale)
	if is_instance_valid(_longshadow):
		_longshadow.set_world_layout(
			_view_size,
			_train_screen_pos,
			_train_visual_scale
		)
	if is_instance_valid(_train_controller):
		_train_controller.set_origin_screen(_train_lamp_position())


func _on_viewport_size_changed() -> void:
	_refresh_world_layout(true)
	if is_instance_valid(_hud):
		_hud.rebuild()
	if is_instance_valid(_route_choice) and _route_choice.visible:
		_route_choice.rebuild()
	if is_instance_valid(_station_panel) and _station_panel.visible:
		_station_panel.rebuild()
	if is_instance_valid(_end_screen) and _end_screen.visible:
		_end_screen.rebuild()


func _on_layout_settings_changed() -> void:
	_refresh_world_layout(true)


func _train_lamp_position() -> Vector2:
	return (
		_train_screen_pos
		+ Vector2(74.0, -24.0) * _train_visual_scale
	)


func _mode_name() -> String:
	return {
		RunMode.TRAVEL: "travel",
		RunMode.ROUTE_REVEAL: "route",
		RunMode.STATION: "station",
		RunMode.BOSS: "boss",
		RunMode.ENDING: "ending",
		RunMode.ENDED: "ended"
	}.get(_mode, "travel")


func _open_reveal() -> void:
	if _mode != RunMode.TRAVEL or run_state.boss_triggered:
		return
	_save_checkpoint()
	_route_commit_pending = false
	_route_reroll_index = 0
	var choices: Array = _generate_route_choices()
	run_state.record_offered_routes(choices)
	_set_mode(RunMode.ROUTE_REVEAL)
	var selected_index := _route_projection.index_for_cursor_y(get_viewport().get_mouse_position().y)
	_route_projection.present(choices, selected_index)
	_route_choice.present(
		choices,
		run_state.current_lens,
		_train_controller.current_band(),
		run_state.lens_config.get(run_state.current_lens, {}),
		run_state.station_completed,
		RunState.ROUTE_REROLL_COST,
		int(run_state.scrap)
	)
	_route_choice.set_selected_index(selected_index)
	if _event_bus != null:
		var reveal_payload: Dictionary = {
			"reveal_index": run_state.reveal_index,
			"reroll_index": _route_reroll_index,
			"choice_ids": []
		}
		for choice_variant in choices:
			var choice: Dictionary = choice_variant
			(reveal_payload["choice_ids"] as Array).append(
				String(choice.get("id", ""))
			)
		var reveal_sequence: int = _emit_sim_event(
			SimEvent.TYPE_ROUTE_REVEAL,
			"sim.game_world",
			"",
			_train_screen_pos,
			Vector2.RIGHT,
			float(choices.size()),
			&"route",
			reveal_payload
		)
		if reveal_sequence > 0:
			_last_route_reveal_sequence = reveal_sequence


func _generate_route_choices() -> Array:
	var deterministic_index: int = (
		run_state.reveal_index + 1 + _route_reroll_index * 997
	)
	return route_director.generate_choices(
		deterministic_index,
		run_state.current_lens,
		run_state.route_seen_ids,
		run_state.event_flags
	)


func _open_station() -> void:
	if _mode != RunMode.TRAVEL:
		return
	_save_checkpoint()
	_set_mode(RunMode.STATION)
	_station_panel.present(run_state)
	_hud.flash("STATION AHEAD", 2.0)
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_STATION_ARRIVAL,
			"sim.game_world",
			"",
			_train_screen_pos,
			Vector2.RIGHT,
			run_state.distance,
			&"station",
			{"distance": run_state.distance}
		)


func _start_boss() -> void:
	if _mode != RunMode.TRAVEL or run_state.boss_triggered:
		return
	run_state.boss_triggered = true
	run_state.distance = minf(run_state.distance, RunState.BOSS_GATE_DISTANCE)
	run_state.speed_scale = 1.0
	_enemy_director.clear_regular_enemies()
	_longshadow.start()
	_set_mode(RunMode.BOSS)
	_effects.request_flash(Color(0.32, 0.08, 0.28, 0.65), 1.2)
	_save_checkpoint()


func _on_route_chosen(event: Dictionary) -> void:
	run_state.apply_route_event(event)
	AudioManager.play("route_commit")
	_refresh_route_context()
	_world_renderer.set_route_context(_route_context)
	var danger: int = int(event.get("danger", 0))
	if danger > 0:
		_enemy_director.spawn_threat_waves(danger)
		_effects.request_shake(3.0)
	run_state.reveal_index += 1
	_reveal_timer = REVEAL_INTERVAL
	_route_commit_pending = true
	_hud.flash("Route chosen: %s" % String(event.get("title", "?")))
	if _event_bus != null:
		var event_id: String = String(event.get("id", ""))
		_emit_sim_event(
			SimEvent.TYPE_ROUTE_COMMIT,
			"sim.game_world",
			VisualStateIds.world_context(String(event.get("category", "neutral"))),
			_train_screen_pos,
			Vector2.RIGHT,
			float(danger),
			&"route",
			{
				"event_id": event_id,
				"category": String(event.get("category", "neutral")),
				"danger": danger,
				"title": String(event.get("title", ""))
			}
		)


func _on_route_reroll() -> void:
	if _mode != RunMode.ROUTE_REVEAL:
		return
	var result: Dictionary = run_state.purchase_route_reroll()
	if not bool(result.get("ok", false)):
		_hud.flash(String(result.get("message", "Route reroll unavailable.")), 2.0)
		AudioManager.play("ui_reject")
		return
	_route_reroll_index += 1
	var choices: Array = _generate_route_choices()
	run_state.record_offered_routes(choices)
	var selected_index: int = _route_projection.index_for_cursor_y(
		get_viewport().get_mouse_position().y
	)
	_route_projection.present(choices, selected_index)
	_route_choice.replace_choices(choices, selected_index)
	_route_choice.set_reroll_state(
		run_state.scrap >= RunState.ROUTE_REROLL_COST,
		RunState.ROUTE_REROLL_COST,
		int(run_state.scrap)
	)
	_hud.flash(String(result.get("message", "New routes projected.")), 2.0)
	AudioManager.play("reveal")


func _on_reveal_closed() -> void:
	if _mode != RunMode.ROUTE_REVEAL:
		return
	_route_projection.hide_routes()
	_set_mode(RunMode.TRAVEL)
	if _route_commit_pending:
		_save_checkpoint()
		if _contextual_tutorial_active:
			_hud.show_cinematic(
				"KEEP THE LINE POWERED",
				"POWER PRIORITIES",
				"Q, W, E, and R raise Engine, Light, Defense, and Repair. "
				+ "Hold Shift with a key to lower it; low priorities shed first.",
				5.2
			)
			GameManager.set_setting("contextual_tutorial_seen", true)
			_contextual_tutorial_active = false
	_route_commit_pending = false


func _on_station_closed() -> void:
	if _mode != RunMode.STATION:
		return
	run_state.station_completed = true
	_set_mode(RunMode.TRAVEL)
	_save_checkpoint()
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_STATION_DEPARTURE,
			"sim.game_world",
			"",
			_train_screen_pos,
			Vector2.RIGHT,
			run_state.scrap,
			&"station",
			{"cars": run_state.cars.size()}
		)


func _on_lens(name: String) -> void:
	if not _gameplay_controls_enabled():
		return
	if run_state.request_lens(name):
		AudioManager.play("click")
		_hud.flash("Lens: %s" % name, 1.5)


func _on_priority(role: String, delta: int = 1) -> void:
	if not _gameplay_controls_enabled():
		return
	var before: int = int(run_state.priorities.get(role, 0))
	var after: int = run_state.change_priority(role, delta)
	AudioManager.play("click")
	var boundary: String = " (limit)" if before == after else ""
	_hud.flash("%s priority %d%s | full-load net %+.1f" % [
		role.capitalize(),
		after,
		boundary,
		run_state.stats().requested_power_net
	], 1.4)


func _on_priority_level(role: String, level: int) -> void:
	if not _gameplay_controls_enabled():
		return
	run_state.set_priority(role, level)
	AudioManager.play("click")
	_hud.flash("%s priority %d | full-load net %+.1f" % [
		role.capitalize(),
		int(run_state.priorities.get(role, 0)),
		run_state.stats().requested_power_net
	], 1.4)


func _on_focus() -> void:
	if not _gameplay_controls_enabled():
		return
	if _longshadow.is_active():
		var block_reason: String = _longshadow.focus_block_reason(_light_profile)
		if not block_reason.is_empty():
			_hud.flash(block_reason, 1.8)
			AudioManager.play("ui_reject")
			return
	if run_state.request_focus():
		AudioManager.play("focus")
		_hud.flash("FOCUS BEAM", 1.0)
	else:
		AudioManager.play("ui_reject")


func _on_defense_salvo() -> void:
	if not _gameplay_controls_enabled():
		return
	if not _longshadow.is_active() and not _enemy_director.has_salvo_target():
		_hud.flash("Defense salvo: no target in range.", 1.5)
		AudioManager.play("ui_reject")
		return
	if _longshadow.is_active() and not _longshadow.can_accept_active_response():
		_hud.flash("Defense salvo held - target lock is still forming.", 1.5)
		AudioManager.play("ui_reject")
		return
	var salvo_stats: TrainStats = run_state.stats()
	var request: Dictionary = run_state.request_defense_salvo()
	if not bool(request.get("ok", false)):
		_hud.flash(String(request.get("message", "Defense salvo unavailable.")), 1.8)
		AudioManager.play("ui_reject")
		return
	var hit_positions: Array = []
	var damage: float = 0.0
	if _longshadow.is_active():
		damage = _longshadow.apply_defense_salvo(salvo_stats)
		hit_positions.append(_longshadow.current_target_position())
	else:
		var salvo_result: Dictionary = _enemy_director.fire_manual_salvo(salvo_stats)
		hit_positions = salvo_result.get("positions", [])
		damage = float(salvo_result.get("damage", 0.0))
	for position_variant in hit_positions:
		var target_position: Vector2 = position_variant
		_effects.add_tracer(
			_train_screen_pos
			+ Vector2(-20.0, -68.0) * _train_visual_scale,
			target_position,
			Color(1.0, 0.58, 0.24)
		)
		_effects.add_hit(target_position, Color(1.0, 0.58, 0.24))
	_effects.request_shake(7.0)
	_effects.request_flash(Color(1.0, 0.5, 0.2, 0.28), 0.22)
	AudioManager.play_spatial("salvo", -0.35)
	_hud.flash("DEFENSE SALVO - %.0f damage" % damage, 1.5)


func _on_field_action(action: String) -> void:
	if not _gameplay_controls_enabled():
		return
	var result: Dictionary
	match action:
		"patch":
			result = run_state.purchase_field_patch()
		"overcharge":
			result = run_state.purchase_emergency_overcharge()
		"flare":
			result = run_state.purchase_signal_flare()
		_:
			return
	_hud.flash(String(result.get("message", "No change.")), 2.0)
	if bool(result.get("ok", false)):
		AudioManager.play({
			"patch": "repair",
			"overcharge": "overcharge",
			"flare": "flare"
		}.get(action, "reveal"))
		_effects.request_flash(
			Color(0.36, 0.78, 0.48, 0.2)
			if action == "patch"
			else (
				Color(0.72, 0.86, 1.0, 0.26)
				if action == "flare"
				else Color(1.0, 0.78, 0.3, 0.24)
			),
			0.35
		)
		_save_checkpoint()
	else:
		AudioManager.play("ui_reject")


func _on_detach_hold_changed(active: bool) -> void:
	_detach_hold_active = active and _gameplay_controls_enabled()
	if not _detach_hold_active:
		_detach_hold_time = 0.0
		_hud.set_detach_hold(0.0)


func _process_detach_hold(delta: float) -> void:
	if not _detach_hold_active or not _gameplay_controls_enabled():
		if _detach_hold_time > 0.0:
			_on_detach_hold_changed(false)
		return
	_detach_hold_time += delta
	var preview_data: Dictionary = run_state.detach_preview()
	var preview := String(preview_data.get("display", "rear car"))
	var crew_names: Array = preview_data.get("crew_names", [])
	if not crew_names.is_empty():
		preview += (
			" (crew evacuate)"
			if bool(preview_data.get("crew_protected", false))
			else " (LOSE %s)" % ", ".join(PackedStringArray(crew_names))
		)
	var required_hold: float = _detach_hold_seconds()
	_hud.set_detach_hold(_detach_hold_time / required_hold, preview)
	if _detach_hold_time >= required_hold:
		_detach_hold_active = false
		_detach_hold_time = 0.0
		_hud.set_detach_hold(0.0)
		_on_detach()


func _on_pause() -> void:
	if not _gameplay_controls_enabled():
		return
	run_state.toggle_pause()
	AudioManager.play("click")


func _on_speed() -> void:
	if not _gameplay_controls_enabled():
		return
	run_state.toggle_speed()
	AudioManager.play("click")
	_hud.flash("Travel speed: %sx" % str(run_state.speed_scale), 1.2)


func _detach_hold_seconds() -> float:
	return (
		ACCESSIBLE_DETACH_HOLD_SECONDS
		if bool(GameManager.get_setting("short_holds", false))
		else DETACH_HOLD_SECONDS
	)


func _open_settings() -> void:
	if not _begin_overlay():
		return
	_settings_panel.present()


func _open_guide() -> void:
	if not _begin_overlay():
		return
	_guide_panel.present("Return to Run")


func _begin_overlay() -> bool:
	if (
		_overlay_open
		or _mode == RunMode.ENDING
		or _mode == RunMode.ENDED
	):
		return false
	_on_detach_hold_changed(false)
	if is_instance_valid(_pointer_router):
		_pointer_router.set_blocked(true, &"modal_opened")
	_overlay_was_paused = run_state.paused
	run_state.paused = true
	_overlay_open = true
	AudioManager.play("click")
	return true


func _on_settings_closed() -> void:
	_close_overlay()


func _on_settings_guide_requested() -> void:
	if not _overlay_open:
		return
	_guide_panel.present("Return to Run")


func _on_guide_closed() -> void:
	_close_overlay()


func _close_overlay() -> void:
	if not _overlay_open:
		return
	_overlay_open = false
	run_state.paused = _overlay_was_paused
	if is_instance_valid(_pointer_router):
		_pointer_router.set_blocked(
			not _gameplay_controls_enabled(),
			&"modal_closed"
		)
	_hud.rebuild()
	if _mode == RunMode.ROUTE_REVEAL:
		_route_choice.rebuild()
	elif _mode == RunMode.STATION:
		_station_panel.rebuild()


func _on_detach() -> void:
	if not _gameplay_controls_enabled():
		return
	var detach_stats: TrainStats = run_state.stats()
	var detached_position: Vector2 = _train_renderer.car_screen_center(run_state.cars.size() - 1)
	var rear: Dictionary = run_state.detach_rear_car()
	if rear.is_empty():
		AudioManager.play("ui_reject")
		return
	AudioManager.play_spatial("detach", -0.72)
	_effects.request_shake(8.0)
	_effects.add_detached_car(detached_position)
	_enemy_director.on_detach(detach_stats.detach_purge_radius)
	run_state.trigger_detach_boost(detach_stats.detach_boost_duration)
	run_state.power = clampf(
		run_state.power + detach_stats.detach_power_gain,
		0.0,
		12.0
	)
	var message: String = "Rear car detached: %s" % String(
		rear.get("display", rear.get("type", "car"))
	)
	var lost_crew: Array = rear.get("lost_crew", [])
	if not lost_crew.is_empty():
		message += " | Lost: %s" % ", ".join(PackedStringArray(lost_crew))
	_hud.flash(message, 3.0)
	if _event_bus != null:
		var car_id: String = String(rear.get("car_id", rear.get("id", "")))
		_emit_sim_event(
			SimEvent.TYPE_DETACH_RELEASED,
			"sim.game_world",
			VisualStateIds.car(car_id),
			detached_position,
			Vector2.LEFT,
			detach_stats.detach_boost_duration,
			&"coupling",
			{
				"car_id": car_id,
				"display": String(rear.get("display", rear.get("type", "car"))),
				"lost_crew": lost_crew.duplicate()
			}
		)


func _on_enemy_killed(kind: String, _value: int) -> void:
	_effects.add_hit(
		_train_screen_pos + Vector2(180, -20),
		Color(1.0, 0.6, 0.35)
	)


func _on_boss_phase_changed(phase_name: String) -> void:
	if _longshadow != null and _longshadow.can_accept_active_response():
		return
	var instruction: String
	match phase_name:
		"VEIL":
			instruction = "Switch to Pale, then Focus to expose it."
		"TETHER":
			instruction = "Track it with Hearth; Focus or Salvo severs the lock."
		"CHARGE":
			instruction = "Use Standard and interrupt with Focus or Salvo."
		_:
			instruction = "Keep the lantern trained."
	_hud.show_cinematic(
		"FINAL APPROACH" if phase_name == "VEIL" else "PHASE SHIFT",
		"THE LONGSHADOW" if phase_name == "VEIL" else phase_name,
		instruction,
		1.35
	)
	_effects.request_shake(4.0)
	_effects.request_flash(Color(0.52, 0.12, 0.42, 0.34), 0.65)
	AudioManager.play("boss_%s" % phase_name.to_lower())


func _on_boss_attack(message: String, severity: float) -> void:
	_hud.flash(message, 2.2)
	_effects.request_shake(severity)
	var impact_position: Vector2 = (
		_longshadow.current_target_position()
		if _longshadow.phase_name() == "TETHER"
		else (
			_train_screen_pos
			+ Vector2(38.0, -24.0) * _train_visual_scale
		)
	)
	_effects.add_hit(
		impact_position,
		PresentationPalette.color(&"shadow_veil", UITheme.high_contrast()),
		"shadow"
	)
	var cue: String
	if message.contains("CHARGE IMMINENT"):
		cue = "boss_charge"
	elif severity >= 7.0:
		cue = "boss_impact"
	elif severity <= 2.0:
		cue = "ward_break"
	else:
		cue = "boss_%s" % _longshadow.phase_name().to_lower()
	AudioManager.play_spatial(cue, _audio_pan(impact_position.x))


func _on_boss_defeated() -> void:
	run_state.boss_defeated = true
	run_state.external_speed_multiplier = 1.0
	_set_mode(RunMode.TRAVEL)
	_hud.set_boss_status("")
	_hud.show_cinematic(
		"THE SHADOW BREAKS",
		"FINAL 300 METERS",
		"Keep the lantern burning. Ride the line into dawn.",
		3.4
	)
	_effects.request_flash(Color(1.0, 0.82, 0.46, 0.42), 1.4)
	AudioManager.play("ward_break")
	_save_checkpoint()


func _on_car_destroyed(display_name: String, evacuated_names: Array) -> void:
	var message: String = "%s destroyed | full-load net %+.1f" % [
		display_name,
		run_state.stats().requested_power_net
	]
	if run_state.brownout_active:
		message += " | LOAD SHEDDING ACTIVE"
	if not evacuated_names.is_empty():
		message += " | Evacuated: %s" % ", ".join(PackedStringArray(evacuated_names))
	run_state.trigger_critical_slow(3.0)
	_hud.flash(message, 3.5)
	_hud.show_critical("CAR LOST - %s" % message, 6.0)
	_effects.request_shake(9.0)
	_effects.request_flash(Color(0.95, 0.18, 0.12, 0.34), 0.6)
	AudioManager.play_spatial("detach", -0.58)
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_CAR_DESTROYED,
			"sim.run_state",
			"",
			_train_screen_pos,
			Vector2.LEFT,
			0.0,
			&"steel",
			{"display": display_name, "evacuated": evacuated_names.duplicate()}
		)


func _on_car_damaged(
	car_id: String,
	_display_name: String,
	hp: float,
	max_hp: float,
	index: int
) -> void:
	_train_renderer.flash_car(car_id)
	_effects.add_hit(
		_train_renderer.car_screen_center(index),
		PresentationPalette.color(&"flame", UITheme.high_contrast())
	)
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_CAR_HIT,
			"sim.run_state",
			VisualStateIds.car(car_id),
			_train_renderer.car_screen_center(index),
			Vector2.LEFT,
			maxf(0.0, max_hp - hp),
			&"steel",
			{"car_id": car_id, "hp": hp, "max_hp": max_hp, "index": index}
		)


func _on_car_critical(car_id: String, display_name: String, index: int) -> void:
	run_state.trigger_critical_slow()
	_train_renderer.flash_car(car_id, 1.2)
	var guidance: String = (
		" - hold X to detach the rear if necessary"
		if index == run_state.cars.size() - 1
		else " - auto-slow engaged"
	)
	_hud.show_critical(
		"%s CRITICAL%s" % [display_name.to_upper(), guidance],
		4.5
	)
	_effects.add_hit(
		_train_renderer.car_screen_center(index),
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)
	_effects.request_shake(7.0)
	AudioManager.play("alarm")
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_CAR_CRITICAL,
			"sim.run_state",
			VisualStateIds.car(car_id),
			_train_renderer.car_screen_center(index),
			Vector2.LEFT,
			0.0,
			&"steel",
			{"car_id": car_id, "display": display_name, "index": index}
		)


func _on_locomotive_damaged(hp: float) -> void:
	var ratio: float = hp / maxf(1.0, run_state.locomotive_max_hp)
	if _event_bus != null:
		_emit_sim_event(
			SimEvent.TYPE_TRAIN_HIT,
			"sim.run_state",
			VisualStateIds.TRAIN_LOCOMOTIVE,
			_train_screen_pos,
			Vector2.LEFT,
			maxf(0.0, run_state.locomotive_max_hp - hp),
			&"steel",
			{"hp": hp, "hp_ratio": ratio}
		)
	if ratio > 0.3 or _locomotive_critical_notified:
		return
	_locomotive_critical_notified = true
	run_state.trigger_critical_slow(3.0)
	_hud.show_critical("LOCOMOTIVE CRITICAL - protect the line", 5.0)
	_effects.request_flash(Color(1.0, 0.16, 0.1, 0.32), 0.55)
	_effects.request_shake(8.0)
	AudioManager.play("alarm")


func _on_defense_fired(
	target_position: Vector2,
	source_car_id: String,
	crewed: bool
) -> void:
	var source: Vector2 = _train_renderer.car_screen_center_by_id(source_car_id)
	var color: Color = (
		PresentationPalette.color(&"ember", UITheme.high_contrast())
		if crewed
		else PresentationPalette.color(&"bone", UITheme.high_contrast()).darkened(0.28)
	)
	_effects.add_tracer(source + Vector2(0.0, -28.0), target_position, color)
	AudioManager.play_spatial("defense_fire", _audio_pan(source.x))


func _on_active_response(position: Vector2, message: String) -> void:
	_effects.add_hit(
		position,
		PresentationPalette.color(&"shadow_veil", UITheme.high_contrast()),
		"ward"
	)
	_effects.request_flash(Color(0.65, 0.42, 1.0, 0.18), 0.3)
	_hud.flash(message, 2.2)
	AudioManager.play_spatial("ward_break", _audio_pan(position.x))


func _on_enemy_attack_landed(position: Vector2, _kind: String) -> void:
	_effects.add_hit(
		position,
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)
	AudioManager.play_spatial("impact", _audio_pan(position.x))


func _on_pressure_brake_changed(active: bool) -> void:
	if active:
		_hud.show_critical(
			"THREAT BRAKE - combat held at %.1fx until the field clears"
			% RunState.CRITICAL_SLOW_SCALE,
			3.2
		)


func _on_threat_announced(kind: String, guidance: String) -> void:
	if kind == "Ward":
		run_state.trigger_critical_slow(5.0)
		_hud.show_critical(guidance, 5.0)
		AudioManager.play_spatial("ward_warning", 0.82)
	else:
		_hud.flash(guidance, 2.5)
		AudioManager.play_spatial(
			"threat_%s" % kind.to_lower(),
			0.82
		)


func _begin_contextual_tutorial() -> void:
	if not _contextual_tutorial_active or not is_instance_valid(_hud):
		return
	_contextual_tutorial_stage = 1


func _process_contextual_tutorial() -> void:
	if (
		not _contextual_tutorial_active
		or _contextual_tutorial_stage != 1
		or run_state.distance < 360.0
		or _hud.cinematic_visible()
	):
		return
	_contextual_tutorial_stage = 2
	_hud.flash(
		"PACE: press T for 1x, 1.5x, or 2x. "
		+ "Threat Brake slows crowded combat automatically.",
		4.8
	)


func _automation_run() -> bool:
	return (
		OS.has_environment("LANTERN_SMOKE")
		or OS.has_environment("LANTERN_PROBE")
		or OS.has_environment("LANTERN_PROBE_DENSE_COMBAT")
		or OS.has_environment("LANTERN_PROBE_AUDIO")
		or not OS.get_environment("LANTERN_CAPTURE_GAMEPLAY").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_TRAIN_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_ROUTE_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_COMBAT_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_BOSS_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_UI_SHOWCASE").is_empty()
	)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		or event is InputEventKey
		or event is InputEventScreenTouch
	):
		AudioManager.notify_user_gesture()
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _overlay_open:
		return
	if event.is_action_released("detach_car"):
		_on_detach_hold_changed(false)
	if event.is_action_pressed("ui_cancel"):
		_open_settings()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_guide"):
		_open_guide()
		get_viewport().set_input_as_handled()
		return
	if not _gameplay_controls_enabled():
		return
	var priority_delta: int = -1 if (
		event is InputEventKey and (event as InputEventKey).shift_pressed
	) else 1
	if event.is_action_pressed("toggle_pause"):
		_on_pause()
	elif event.is_action_pressed("speed_toggle"):
		_on_speed()
	elif event.is_action_pressed("lens_standard"):
		_on_lens("Standard")
	elif event.is_action_pressed("lens_hearth"):
		_on_lens("Hearth")
	elif event.is_action_pressed("lens_pale"):
		_on_lens("Pale")
	elif event.is_action_pressed("focus_beam"):
		_on_focus()
	elif event.is_action_pressed("defense_salvo"):
		_on_defense_salvo()
	elif event.is_action_pressed("field_patch"):
		_on_field_action("patch")
	elif event.is_action_pressed("field_overcharge"):
		_on_field_action("overcharge")
	elif event.is_action_pressed("field_flare"):
		_on_field_action("flare")
	elif event.is_action_pressed("detach_car"):
		_on_detach_hold_changed(true)
	elif event.is_action_pressed("power_engine"):
		_on_priority("engine", priority_delta)
	elif event.is_action_pressed("power_light"):
		_on_priority("light", priority_delta)
	elif event.is_action_pressed("power_defense"):
		_on_priority("defense", priority_delta)
	elif event.is_action_pressed("power_repair"):
		_on_priority("repair", priority_delta)


func _begin_end(victory_value: bool) -> void:
	if _end_committed:
		return
	_end_committed = true
	_ending_victory = victory_value
	_ending_timer = (
		VICTORY_REVEAL_SECONDS
		if victory_value
		else DEFEAT_REVEAL_SECONDS
	)
	run_state.victory = victory_value
	run_state.defeat = not victory_value
	_set_mode(RunMode.ENDING)
	_update_presentational_state()
	if victory_value:
		_hud.show_cinematic(
			"JOURNEY COMPLETE",
			"DAWN BEACON",
			"The Lantern Line endures. The ledger is being written.",
			VICTORY_REVEAL_SECONDS - 0.2
		)
	else:
		_hud.show_cinematic(
			"JOURNEY ENDED",
			"THE LANTERN FAILS",
			"The distance is marked. The ledger remembers.",
			DEFEAT_REVEAL_SECONDS - 0.1
		)
	GameManager.record_run_end(run_state.distance, victory_value, run_state.run_seed)


func _finish(victory_value: bool) -> void:
	_begin_end(victory_value)


func _process_ending(delta: float) -> void:
	if _end_screen_shown:
		return
	_ending_timer = maxf(0.0, _ending_timer - delta)
	if _ending_victory:
		_effects.set_dawn_progress(1.0 - _ending_timer / VICTORY_REVEAL_SECONDS)
	if _ending_timer <= 0.0:
		_end_screen_shown = true
		_end_screen.show_end(_ending_victory, run_state)


func _on_end_closed() -> void:
	_set_mode(RunMode.ENDED)
	emit_signal("run_ended", _ending_victory)


func _set_mode(next_mode: RunMode) -> void:
	_mode = next_mode
	if is_instance_valid(_pointer_router):
		_pointer_router.set_blocked(
			next_mode != RunMode.TRAVEL and next_mode != RunMode.BOSS,
			&"mode_transition"
		)
	if run_state != null:
		run_state.simulation_enabled = (
			next_mode == RunMode.TRAVEL
			or next_mode == RunMode.BOSS
		)


func _gameplay_controls_enabled() -> bool:
	return (
		(_mode == RunMode.TRAVEL or _mode == RunMode.BOSS)
		and not _overlay_open
	)


func _on_pointer_holds_cancelled(_reason: StringName) -> void:
	_on_detach_hold_changed(false)


func _notification(what: int) -> void:
	if (
		what != NOTIFICATION_APPLICATION_FOCUS_OUT
		and what != NOTIFICATION_APPLICATION_PAUSED
	):
		return
	if is_instance_valid(_pointer_router):
		_pointer_router.cancel_all(&"application_suspended")
	if run_state == null:
		return
	_on_detach_hold_changed(false)
	if _mode == RunMode.TRAVEL or _mode == RunMode.BOSS:
		run_state.paused = true
		_save_checkpoint()


func _audio_pan(screen_x: float) -> float:
	return clampf(screen_x / maxf(1.0, _view_size.x) * 2.0 - 1.0, -1.0, 1.0)


func _save_checkpoint() -> void:
	if _end_committed or run_state.victory or run_state.defeat:
		return
	if _mode == RunMode.ROUTE_REVEAL:
		return
	var world_state: Dictionary = {
		"run_mode": _run_mode_name(),
		"reveal_timer": _reveal_timer,
		"enemy_state": _enemy_director.checkpoint_state(),
		"boss_state": _longshadow.checkpoint_state()
	}
	GameManager.store_run_checkpoint(RunSnapshot.build(run_state.to_dict(), world_state))


func _run_mode_name() -> String:
	match _mode:
		RunMode.STATION:
			return "station"
		RunMode.BOSS:
			return "boss"
		_:
			return "travel"
