extends Node
## runtime_probe.gd
##
## Boots into a real game_world for ~8 seconds, then quits.
## Exercises the actual scene tree, tick loop, spawn, aim, HUD wiring.

const REFERENCE_SIM_PRODUCER_ID: String = "qa.reference_scenario.sim"
const REFERENCE_PRESENTATION_PRODUCER_ID: String = (
	"qa.reference_scenario.presentation"
)

var _elapsed: float = 0.0
var _duration: float = 8.0
var _saw_enemies: bool = false
var _detached: bool = false
var _detach_hold_started: bool = false
var _focused: bool = false
var _distance_start: float = 0.0
var _detach_target_count: int = 2
var _game_world: Node
var _bootstrapped: bool = false
var _saved_meta: Dictionary
var _saved_settings: Dictionary
var _saved_pending: Dictionary
var _saved_has_pending: bool
var _capture_requested: bool = false
var _capture_complete: bool = false
var _capture_result: Error = ERR_BUSY
var _capture_path: String = ""
var _showcase_mode: String = ""
var _benchmark_mode: String = ""
var _visual_benchmark_mode: String = ""
var _visual_benchmark_enemies: int = 12
var _visual_benchmark_boss: bool = false
var _visual_benchmark_layer: VisualArchitectureBenchmark
var _finished: bool = false
var _audio_stage: int = 0
var _audio_max_voices: int = 0
var _audio_max_music_players: int = 0
var _audio_saw_crossfade: bool = false
var _reference_scenario_id: String = ""
var _reference_scenario_prepared: bool = false
var _reference_scenario_receipt: Dictionary = {}
var _reference_scenario_a_b: String = "vector"
var _reference_capture_points: Array[Dictionary] = []
var _reference_scenario_started_at: float = 0.0
var _reference_capture_index: int = 0
var _reference_capture_busy: bool = false
var _reference_capture_paths: Array[String] = []
var _reference_capture_pixel_hashes: Array[String] = []
var _reference_capture_error: Error = OK


func _ready() -> void:
	_saved_meta = GameManager.meta.duplicate(true)
	_saved_settings = GameManager.settings.duplicate(true)
	_saved_pending = GameManager.pending_run.duplicate(true)
	_saved_has_pending = GameManager.has_pending_run
	var requested_profile := OS.get_environment(
		"LANTERN_PRESENTATION_PROFILE"
	)
	if not requested_profile.is_empty():
		GameManager.settings["presentation_profile"] = (
			PresentationProfile.normalize(requested_profile)
		)
		GameManager.emit_signal("settings_changed")
	var requested_scenario: String = OS.get_environment(
		"LANTERN_REFERENCE_SCENARIO"
	).strip_edges().to_lower()
	if requested_scenario.is_empty():
		requested_scenario = WebRuntimeQuery.environment_or_benchmark_parameter(
			"LANTERN_REFERENCE_SCENARIO",
			"scenario"
		).to_lower()
	if not requested_scenario.is_empty() and ReferenceScenarios.is_valid(requested_scenario):
		_reference_scenario_id = requested_scenario
		var ab: String = OS.get_environment(
			"LANTERN_REFERENCE_SCENARIO_AB"
		).strip_edges().to_lower()
		if ab.is_empty():
			ab = WebRuntimeQuery.environment_or_benchmark_parameter(
				"LANTERN_REFERENCE_SCENARIO_AB",
				"ab"
			).to_lower()
		_reference_scenario_a_b = "baked" if ab == "baked" else "vector"
		_duration = 3.2
	if not OS.get_environment("LANTERN_CAPTURE_TRAIN_SHOWCASE").is_empty():
		_showcase_mode = "train"
	elif not OS.get_environment("LANTERN_CAPTURE_ROUTE_SHOWCASE").is_empty():
		_showcase_mode = "route"
	elif not OS.get_environment("LANTERN_CAPTURE_COMBAT_SHOWCASE").is_empty():
		_showcase_mode = "combat"
	elif not OS.get_environment("LANTERN_CAPTURE_BOSS_SHOWCASE").is_empty():
		_showcase_mode = "boss"
	elif not OS.get_environment("LANTERN_CAPTURE_UI_SHOWCASE").is_empty():
		var ui_showcase: String = OS.get_environment(
			"LANTERN_UI_SHOWCASE"
		).to_lower()
		_showcase_mode = "ui_%s" % (
			ui_showcase
			if ui_showcase in [
				"max_consist",
				"route",
				"station",
				"victory",
				"defeat",
				"boss_banner"
			]
			else "max_consist"
		)
	if OS.has_environment("LANTERN_PROBE_DENSE_COMBAT"):
		_benchmark_mode = "dense_combat"
	elif OS.has_environment("LANTERN_PROBE_AUDIO"):
		_benchmark_mode = "audio"
		_duration = 11.0
	else:
		var requested_visual_mode := (
			WebRuntimeQuery.environment_or_benchmark_parameter(
				"LANTERN_VISUAL_BENCHMARK",
				"benchmark"
			).to_lower()
		)
		if not requested_visual_mode.is_empty():
			_configure_visual_benchmark(requested_visual_mode)
	if OS.has_environment("LANTERN_CAPTURE_ACCESSIBLE"):
		GameManager.settings["text_scale"] = 1.3
		GameManager.settings["high_contrast"] = true
		GameManager.settings["reduced_motion"] = true
		GameManager.settings["reduced_flashes"] = true
		GameManager.settings["screen_shake"] = false
		GameManager.emit_signal("settings_changed")
	elif (
		not OS.get_environment("LANTERN_CAPTURE_GAMEPLAY").is_empty()
		or not _showcase_mode.is_empty()
	):
		GameManager.settings["text_scale"] = 1.0
		GameManager.settings["high_contrast"] = false
		GameManager.settings["reduced_motion"] = false
		GameManager.settings["reduced_flashes"] = false
		GameManager.settings["screen_shake"] = true
		GameManager.emit_signal("settings_changed")
	set_process(true)
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	_game_world = scene.instantiate()
	get_tree().root.add_child.call_deferred(_game_world)
	# defer bootstrap until it's in tree
	get_tree().process_frame.connect(_maybe_bootstrap)


func _configure_visual_benchmark(requested_mode: String) -> void:
	_benchmark_mode = "visual"
	_visual_benchmark_mode = (
		requested_mode
		if requested_mode in VisualArchitectureBenchmark.VALID_MODES
		else VisualArchitectureBenchmark.MODE_SPRITE
	)
	var requested_enemies := WebRuntimeQuery.environment_or_benchmark_parameter(
		"LANTERN_VISUAL_BENCHMARK_ENEMIES",
		"benchmark_enemies"
	)
	_visual_benchmark_enemies = clampi(
		int(requested_enemies)
			if requested_enemies.is_valid_int()
			else 12,
		0,
		16
	)
	var requested_boss := WebRuntimeQuery.environment_or_benchmark_parameter(
		"LANTERN_VISUAL_BENCHMARK_BOSS",
		"benchmark_boss"
	)
	_visual_benchmark_boss = requested_boss == "1"
	var requested_duration := WebRuntimeQuery.environment_or_benchmark_parameter(
		"LANTERN_VISUAL_BENCHMARK_SECONDS",
		"benchmark_seconds"
	)
	_duration = (
		maxf(4.0, float(requested_duration))
		if requested_duration.is_valid_float()
		else 32.0
	)
	GameManager.settings["presentation_profile"] = "high"
	GameManager.emit_signal("settings_changed")


func _maybe_bootstrap() -> void:
	if _bootstrapped:
		return
	if _game_world.is_inside_tree():
		_game_world.call("bootstrap", 42, {})
		_bootstrapped = true
		if OS.has_feature("qa_visual_benchmark"):
			WebRuntimeQuery.publish(
				"__lanternRuntimeInfo",
				{
					"layout_class": String(
						UITheme.layout_class(
							get_viewport().get_visible_rect().size
						)
					),
					"touch_available": WebPlatformBridge.touch_available()
				}
			)
		var metrics: PresentationMetrics = (
			_game_world.get("_presentation_metrics") as PresentationMetrics
		)
		if metrics != null:
			var requested_warmup := OS.get_environment(
				"LANTERN_METRICS_WARMUP"
			)
			metrics.reset_measurement(
				float(requested_warmup)
				if requested_warmup.is_valid_float()
				else PresentationMetrics.DEFAULT_WARMUP_SECONDS
			)
		if OS.has_environment("LANTERN_PROBE_HIDE_WORLD"):
			var world_renderer: CanvasItem = (
				_game_world.get("_world_renderer") as CanvasItem
			)
			if world_renderer != null:
				world_renderer.visible = false
		if OS.has_environment("LANTERN_PROBE_HIDE_TRAIN"):
			var train_renderer: CanvasItem = (
				_game_world.get("_train_renderer") as CanvasItem
			)
			if train_renderer != null:
				train_renderer.visible = false
		if "run_state" in _game_world:
			var rs: Object = _game_world.get("run_state")
			if rs:
				_distance_start = float(rs.distance)
		if _showcase_mode == "train":
			_prepare_train_showcase()
		elif _showcase_mode == "route":
			_prepare_route_showcase()
		elif _showcase_mode == "combat":
			_prepare_combat_showcase()
		elif _showcase_mode == "boss":
			_prepare_boss_showcase()
		elif _showcase_mode == "ui_max_consist":
			_prepare_max_consist_showcase()
		elif _showcase_mode == "ui_route":
			_prepare_route_ui_showcase()
		elif _showcase_mode == "ui_station":
			_prepare_station_ui_showcase()
		elif _showcase_mode == "ui_victory":
			_prepare_ending_showcase(true)
		elif _showcase_mode == "ui_defeat":
			_prepare_ending_showcase(false)
		elif _showcase_mode == "ui_boss_banner":
			_prepare_boss_banner_showcase()
		elif _benchmark_mode == "dense_combat":
			_prepare_dense_combat_benchmark()
		elif _benchmark_mode == "audio":
			_prepare_audio_benchmark()
		elif _benchmark_mode == "visual":
			_prepare_visual_benchmark()
		if not _reference_scenario_id.is_empty():
			_prepare_reference_scenario()
		if "run_state" in _game_world:
			var prepared_state: RunState = _game_world.get("run_state") as RunState
			if prepared_state != null:
				_detach_target_count = maxi(0, prepared_state.cars.size() - 1)


func _process(delta: float) -> void:
	if not _bootstrapped:
		return
	_elapsed += delta
	if not _reference_scenario_id.is_empty():
		_process_reference_scenario()
		return
	if not _showcase_mode.is_empty():
		var showcase_path: String = _showcase_path()
		if not _capture_requested and _elapsed > 0.8:
			_request_capture(showcase_path)
		if _capture_complete:
			_finish_capture("[probe] %s showcase captured" % _showcase_mode)
		elif _capture_requested and _elapsed > 5.0:
			_finish(
				10,
				"[probe] %s showcase capture timed out" % _showcase_mode,
				true
			)
		return
	if _benchmark_mode == "audio":
		_process_audio_benchmark()
		return
	if _benchmark_mode == "visual":
		_process_visual_benchmark()
		return
	if _game_world and "run_state" in _game_world:
		var rs: Object = _game_world.get("run_state")
		if rs:
			var ed: Object = _game_world.get("_enemy_director") if "_enemy_director" in _game_world else null
			# poke aim + priority etc
			if _elapsed > 2.0 and int(rs.priorities.get("light", 0)) < 2:
				rs.cycle_priority("light")
			if _elapsed > 3.0 and rs.lens_cooldown == 0.0 and rs.current_lens == "Standard":
				rs.request_lens("Pale")
			if _elapsed > 4.0 and ed != null and not _saw_enemies:
				ed._spawn_wave()
				_saw_enemies = ed.active_count() > 0
			if _elapsed > 4.2 and not _focused:
				_focused = bool(rs.request_focus())
			var capture_path: String = OS.get_environment("LANTERN_CAPTURE_GAMEPLAY")
			if (
				not capture_path.is_empty()
				and not _capture_requested
				and _elapsed > 4.6
			):
				_request_capture(capture_path)
			if _elapsed > 5.0 and not _detach_hold_started:
				_detach_hold_started = true
				_game_world.call("_on_detach_hold_changed", true)
			if (
				_detach_hold_started
				and int(rs.cars.size()) <= _detach_target_count
			):
				_detached = true
	if _elapsed >= _duration:
		if _capture_requested:
			if not _capture_complete:
				_finish(10, "[probe] gameplay capture timed out", true)
				return
			if _capture_result != OK or not FileAccess.file_exists(_capture_path):
				_finish(
					10,
					"[probe] gameplay capture failed error=%s" % _capture_result,
					true
				)
				return
		var rs2: Object = _game_world.get("run_state") if _game_world else null
		if rs2 == null:
			_finish(4, "[probe] no run_state after run", true)
			return
		var dist: float = float(rs2.distance)
		if dist <= _distance_start:
			_finish(5, "[probe] distance did not advance: %s" % dist, true)
			return
		if not _saw_enemies:
			_finish(6, "[probe] enemy spawn not observed", true)
			return
		if not _detached:
			_finish(8, "[probe] detach not observed", true)
			return
		if not _focused:
			_finish(9, "[probe] focus activation not observed", true)
			return
		_finish(0, "[probe] OK distance=%s" % dist)


func _request_capture(path: String) -> void:
	_capture_requested = true
	_capture_complete = false
	_capture_result = ERR_BUSY
	_capture_path = path
	call_deferred("_capture_frame", path)


func _showcase_path() -> String:
	match _showcase_mode:
		"train":
			return OS.get_environment("LANTERN_CAPTURE_TRAIN_SHOWCASE")
		"route":
			return OS.get_environment("LANTERN_CAPTURE_ROUTE_SHOWCASE")
		"combat":
			return OS.get_environment("LANTERN_CAPTURE_COMBAT_SHOWCASE")
		"boss":
			return OS.get_environment("LANTERN_CAPTURE_BOSS_SHOWCASE")
		_:
			return (
				OS.get_environment("LANTERN_CAPTURE_UI_SHOWCASE")
				if _showcase_mode.begins_with("ui_")
				else ""
			)


func _finish_capture(success_message: String) -> void:
	if _capture_result != OK or not FileAccess.file_exists(_capture_path):
		_finish(
			10,
			"[probe] capture failed error=%s path=%s" % [
				_capture_result,
				_capture_path
			],
			true
		)
		return
	_finish(0, success_message)


func _prepare_train_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.slot_capacity = RunState.MAX_SLOT_CAPACITY
	for type_key in ["Greenhouse", "Defense"]:
		rs.add_car(type_key)
	var variant_b: bool = OS.get_environment("LANTERN_SHOWCASE_VARIANT") == "B"
	var upgrades_a := [
		"deep_cells",
		"field_foundry",
		"ration_lockers",
		"hydroponics",
		"heavy_cannon"
	]
	var upgrades_b := [
		"arc_reserve",
		"salvage_rig",
		"safe_quarters",
		"glowbeds",
		"flak_array"
	]
	var ratios := [1.0, 0.72, 0.44, 0.24, 0.84]
	var upgrades: Array = upgrades_b if variant_b else upgrades_a
	for index in range(rs.cars.size()):
		var car: Dictionary = rs.cars[index]
		car["upgrade"] = upgrades[index]
		car["hp"] = float(car.get("max_hp", 1.0)) * float(ratios[index])
	rs.locomotive_hp = rs.locomotive_max_hp * 0.74
	rs.refresh_stats()
	var hud: HUD = _game_world.get("_hud") as HUD
	if hud != null:
		hud.rebuild()
	var projection: CanvasItem = _game_world.get("_route_projection") as CanvasItem
	if projection != null:
		projection.visible = false
	var director: CanvasItem = _game_world.get("_enemy_director") as CanvasItem
	if director != null:
		director.visible = false
	var effects: CanvasItem = _game_world.get("_effects") as CanvasItem
	if effects != null:
		effects.visible = false
	var world: WorldRenderer = _game_world.get("_world_renderer") as WorldRenderer
	if world != null:
		world.set_route_context({
			"category": "machinery" if variant_b else "living",
			"event_id": "machine_graveyard" if variant_b else "lantern_grove",
			"danger": 1
		})
	_game_world.call("_refresh_world_layout", true)
	var train: TrainRenderer = _game_world.get("_train_renderer") as TrainRenderer
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var controller: TrainController = (
		_game_world.get("_train_controller") as TrainController
	)
	if controller != null:
		var train_pos: Vector2 = _game_world.get("_train_screen_pos")
		var train_scale: float = float(_game_world.get("_train_visual_scale"))
		controller.set_origin_screen(
			train_pos + Vector2(74.0, -24.0) * train_scale
		)
		controller.aim_towards(Vector2(view_size.x, train_pos.y - 20.0))
	if train != null:
		train.queue_redraw()
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_max_consist_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.slot_capacity = RunState.MAX_SLOT_CAPACITY
	for type_key in ["Greenhouse", "Defense"]:
		rs.add_car(type_key)
	var upgrades := [
		"deep_cells",
		"field_foundry",
		"ration_lockers",
		"hydroponics",
		"heavy_cannon"
	]
	var ratios := [0.92, 0.76, 0.61, 0.84, 0.69]
	for index in range(rs.cars.size()):
		var car: Dictionary = rs.cars[index]
		car["upgrade"] = upgrades[index]
		car["hp"] = float(car.get("max_hp", 1.0)) * float(ratios[index])
	rs.distance = RunState.STATION_DISTANCE + 1650.0
	rs.travel_time = 487.0
	rs.scrap = 32.0
	rs.supplies = 74.0
	rs.lumen = 28.0
	rs.refresh_stats()
	var hud: HUD = _game_world.get("_hud") as HUD
	if hud != null:
		hud.rebuild()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		director.visible = false
	var projection: CanvasItem = _game_world.get("_route_projection") as CanvasItem
	if projection != null:
		projection.visible = false
	var longshadow: CanvasItem = _game_world.get("_longshadow") as CanvasItem
	if longshadow != null:
		longshadow.visible = false
	var world: WorldRenderer = _game_world.get("_world_renderer") as WorldRenderer
	if world != null:
		world.set_route_context({
			"category": "living",
			"event_id": "living_ash_garden",
			"danger": 0
		})
	_game_world.call("_refresh_world_layout", true)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_route_ui_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.current_lens = "Hearth"
	rs.scrap = 24.0
	var choices: Array = [
		{
			"id": "living_ash_garden",
			"title": "The Ash Garden",
			"position": "upper",
			"category": "living",
			"description": "The marked siding blooms gold around a greenhouse built from carriage glass.",
			"summary": "Supplies +13, lumen +6; Greenhouse output +25%",
			"requires_flags": ["ash_seed_planted"],
			"danger": 0
		},
		{
			"id": "machinery_signal",
			"title": "Broken Signal Yard",
			"position": "middle",
			"category": "machinery",
			"description": "Tangled rails, tangled dispatchers. Something keeps changing the points.",
			"summary": "Scrap +8, lumen +3",
			"danger": 2
		},
		{
			"id": "danger_black_rain",
			"title": "Black Rain Cut",
			"position": "lower",
			"category": "danger",
			"description": "The cutting channels oily rain and every shape beyond the beam moves with it.",
			"summary": "Scrap +14, power +4",
			"danger": 3
		}
	]
	var projection: RouteProjection = (
		_game_world.get("_route_projection") as RouteProjection
	)
	if projection != null:
		projection.present(choices, 1)
	var choice: RouteChoice = _game_world.get("_route_choice") as RouteChoice
	if choice != null:
		choice.present(
			choices,
			"Hearth",
			"middle",
			{
				"description": "Warm signatures reveal survivors and living routes."
			},
			true,
			RunState.ROUTE_REROLL_COST,
			int(rs.scrap)
		)
	var director: CanvasItem = _game_world.get("_enemy_director") as CanvasItem
	if director != null:
		director.visible = false
	var longshadow: CanvasItem = _game_world.get("_longshadow") as CanvasItem
	if longshadow != null:
		longshadow.visible = false
	_game_world.call("_set_mode", 1)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_station_ui_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.distance = RunState.STATION_DISTANCE
	rs.scrap = 48.0
	rs.supplies = 63.0
	rs.lumen = 21.0
	rs.locomotive_hp = rs.locomotive_max_hp * 0.72
	rs.cars[1]["hp"] = float(rs.cars[1].get("max_hp", 1.0)) * 0.58
	rs.refresh_stats()
	var panel: StationPanel = _game_world.get("_station_panel") as StationPanel
	if panel != null:
		panel.present(rs)
	_game_world.call("_set_mode", 2)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_ending_showcase(victory: bool) -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.distance = RunState.JOURNEY_TARGET if victory else 12840.0
	rs.travel_time = 734.0 if victory else 621.0
	rs.slot_capacity = RunState.MAX_SLOT_CAPACITY
	for type_key in ["Greenhouse", "Defense"]:
		rs.add_car(type_key)
	var upgrades := [
		"deep_cells",
		"field_foundry",
		"ration_lockers",
		"hydroponics",
		"heavy_cannon"
	]
	for index in range(rs.cars.size()):
		(rs.cars[index] as Dictionary)["upgrade"] = upgrades[index]
	rs.route_history = [
		"living_grove",
		"machinery_signal",
		"living_ash_garden",
		"danger_black_rain"
	]
	rs.run_history["purchased_cars"] = ["Greenhouse", "Defense"]
	rs.run_history["upgrades"] = upgrades.duplicate()
	rs.run_history["field_actions"] = ["patch", "flare", "overcharge"]
	rs.run_history["detached_cars"] = [] if victory else ["Utility"]
	rs.run_history["boss_responses"] = ["veil", "tether", "charge"] if victory else ["veil"]
	rs.run_history["telemetry"] = {
		"focus_uses": 9,
		"defense_salvos": 6,
		"route_rerolls": 1,
		"wards_broken": 5,
		"boss_active_responses": 3 if victory else 1,
		"min_power": 1.8,
		"brownout_time": 12.4,
		"boss_phase_times": {}
	}
	rs.scrap = 17.0
	rs.victory = victory
	rs.defeat = not victory
	if not victory:
		rs.locomotive_hp = 0.0
		(rs.crew.back() as Dictionary)["status"] = "lost"
	rs.refresh_stats()
	var end_screen: EndScreen = _game_world.get("_end_screen") as EndScreen
	if end_screen != null:
		end_screen.show_end(victory, rs)
	var effects: EffectsLayer = _game_world.get("_effects") as EffectsLayer
	if effects != null:
		effects.set_dawn_progress(1.0 if victory else 0.0)
	_game_world.call("_set_mode", 4)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_boss_banner_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	var longshadow: LongshadowEncounter = (
		_game_world.get("_longshadow") as LongshadowEncounter
	)
	if rs == null or longshadow == null:
		return
	rs.simulation_enabled = false
	rs.boss_triggered = true
	rs.distance = RunState.BOSS_GATE_DISTANCE
	rs.current_lens = "Standard"
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		director.visible = false
	var projection: CanvasItem = _game_world.get("_route_projection") as CanvasItem
	if projection != null:
		projection.visible = false
	longshadow.start({
		"phase": LongshadowEncounter.Phase.CHARGE,
		"phase_max_health": 132.0,
		"health": 94.0,
		"attack_timer": 4.0,
		"charge_timer": 11.0,
		"charge_stagger": 0.0,
		"target_band": 1,
		"target_switch_timer": 4.0,
		"elapsed": 24.0,
		"phase_elapsed": 0.0,
		"transition_timer": LongshadowEncounter.TRANSITION_DURATION,
		"phase_unlocked": false,
		"response_progress": 0.0,
		"charge_warning_issued": false,
		"completed": false
	})
	_game_world.call("_set_mode", 3)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)
	longshadow.queue_redraw()


func _prepare_route_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs != null:
		rs.simulation_enabled = false
	var hud: CanvasItem = _game_world.get("_hud") as CanvasItem
	if hud != null:
		hud.visible = false
	var projection: RouteProjection = (
		_game_world.get("_route_projection") as RouteProjection
	)
	if projection != null:
		projection.present([
			{
				"id": "lantern_grove",
				"title": "Lantern Grove",
				"category": "living",
				"danger": 0
			},
			{
				"id": "signal_works",
				"title": "Signal Works",
				"category": "machinery",
				"danger": 1
			},
			{
				"id": "danger_black_rain",
				"title": "Black Rain Cut",
				"category": "danger",
				"danger": 2
			}
		], 2)
	var world: WorldRenderer = _game_world.get("_world_renderer") as WorldRenderer
	if world != null:
		world.set_route_context({
			"category": "danger",
			"event_id": "danger_black_rain",
			"danger": 2
		})


func _prepare_combat_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if rs == null or director == null:
		return
	rs.simulation_enabled = false
	rs.distance = RunState.JOURNEY_TARGET * 0.74
	rs.power = 10.0
	rs.lumen = 12.0
	var projection: CanvasItem = _game_world.get("_route_projection") as CanvasItem
	if projection != null:
		projection.visible = false
	var longshadow: CanvasItem = _game_world.get("_longshadow") as CanvasItem
	if longshadow != null:
		longshadow.visible = false
	director.clear_regular_enemies()
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var train_pos: Vector2 = _game_world.get("_train_screen_pos")
	var kinds := [
		"Pursuer",
		"Boarder",
		"Drainer",
		"Pursuer",
		"Boarder",
		"Drainer",
		"Pursuer"
	]
	var positions := [
		Vector2(view_size.x * 0.48, train_pos.y + 3.0),
		Vector2(view_size.x * 0.56, train_pos.y - 88.0),
		Vector2(view_size.x * 0.63, train_pos.y - 165.0),
		Vector2(view_size.x * 0.69, train_pos.y + 3.0),
		Vector2(view_size.x * 0.76, train_pos.y - 104.0),
		Vector2(view_size.x * 0.82, train_pos.y - 205.0),
		Vector2(view_size.x * 0.88, train_pos.y + 3.0)
	]
	for index in range(kinds.size()):
		var enemy: Enemy = director.call("_acquire") as Enemy
		if enemy == null:
			continue
		var kind: String = kinds[index]
		enemy.init_from_config(kind, rs.enemy_config.get(kind, {}))
		enemy.position = positions[index]
		enemy.hp *= 0.42 + float(index % 4) * 0.14
		if kind == "Pursuer":
			enemy.role = "ground"
			enemy.target = enemy.position + Vector2(-33.0, 0.0)
		elif kind == "Boarder":
			enemy.role = "roof"
			enemy.boarder_car_index = mini(index, rs.cars.size() - 1)
			enemy.target = enemy.position + Vector2(-24.0, 22.0)
		else:
			enemy.role = "air"
			enemy.target = enemy.position + Vector2(-28.0, 18.0)
		enemy.attack_timer = 0.28 if index < 3 else enemy.attack_interval
		if index == 2:
			enemy.warded = true
			enemy.ward_max_hp = 24.0
			enemy.ward_hp = 17.0
	director.set_process(false)
	director.queue_redraw()
	var world: WorldRenderer = _game_world.get("_world_renderer") as WorldRenderer
	if world != null:
		world.set_route_context({
			"category": "danger",
			"event_id": "danger_black_rain",
			"danger": 2
		})
	var effects: EffectsLayer = _game_world.get("_effects") as EffectsLayer
	if effects != null:
		effects.add_tracer(
			train_pos + Vector2(-10.0, -70.0),
			positions[4],
			PresentationPalette.color(&"ember", UITheme.high_contrast())
		)
		effects.add_hit(
			positions[1],
			PresentationPalette.color(&"danger", UITheme.high_contrast())
		)
		effects.add_hit(
			positions[2],
			PresentationPalette.color(
				&"shadow_veil",
				UITheme.high_contrast()
			),
			"ward"
		)
		effects.set_process(false)
		effects.queue_redraw()
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)


func _prepare_dense_combat_benchmark() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if rs == null or director == null:
		return
	rs.distance = RunState.JOURNEY_TARGET * 0.74
	rs.station_completed = true
	rs.slot_capacity = maxi(rs.slot_capacity, 4)
	if not rs.has_car_type("Defense"):
		rs.add_car("Defense")
	rs.set_priority("defense", 2)
	rs.power = 12.0
	rs.lumen = 12.0
	director.spawn_threat_waves(5)
	var active: Array = director.get("_active")
	if not active.is_empty():
		var warded: Enemy = active[0] as Enemy
		warded.warded = true
		warded.ward_max_hp = 26.0
		warded.ward_hp = 26.0


func _prepare_visual_benchmark() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	rs.slot_capacity = RunState.MAX_SLOT_CAPACITY
	for type_key in ["Greenhouse", "Defense"]:
		if not rs.has_car_type(type_key):
			rs.add_car(type_key)
	rs.distance = RunState.JOURNEY_TARGET * 0.78
	rs.station_completed = true
	rs.power = 12.0
	rs.lumen = 14.0
	rs.refresh_stats()
	var hud: HUD = _game_world.get("_hud") as HUD
	if hud != null:
		hud.rebuild()
	for property_name in [
		"_world_renderer",
		"_route_projection",
		"_enemy_director",
		"_train_renderer",
		"_longshadow",
		"_effects"
	]:
		var canvas_item: CanvasItem = _game_world.get(property_name) as CanvasItem
		if canvas_item != null:
			canvas_item.visible = false
	var world_layer := _game_world.get_node_or_null("WorldLayer") as Node2D
	if world_layer == null:
		return
	_visual_benchmark_layer = VisualArchitectureBenchmark.new()
	_visual_benchmark_layer.name = "VisualArchitectureBenchmark"
	world_layer.add_child(_visual_benchmark_layer)
	_visual_benchmark_layer.setup(
		get_viewport().get_visible_rect().size,
		_visual_benchmark_mode,
		_visual_benchmark_enemies,
		_visual_benchmark_boss
	)
	_game_world.set_process(false)


func _process_visual_benchmark() -> void:
	var capture_path := OS.get_environment(
		"LANTERN_VISUAL_BENCHMARK_CAPTURE"
	)
	if (
		not capture_path.is_empty()
		and not _capture_requested
		and _elapsed >= 0.5
	):
		_request_capture(capture_path)
	if _elapsed < _duration:
		return
	if _capture_requested and not _capture_complete:
		return
	if (
		_capture_requested
		and (
			_capture_result != OK
			or not FileAccess.file_exists(_capture_path)
		)
	):
		_finish(18, "[probe] visual benchmark capture failed", true)
		return
	_finish(0, "[probe] visual benchmark OK")


func _prepare_audio_benchmark() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs != null:
		rs.simulation_enabled = false
	_game_world.set_process(false)
	AudioManager.set_wheel_rate(3.6)
	AudioManager.set_presentation_state({
		"mode": "travel",
		"music_state": "travel_calm",
		"tension": 0.18,
		"paused": false
	})
	AudioManager.notify_user_gesture()


func _process_audio_benchmark() -> void:
	var snapshot: Dictionary = AudioManager.debug_snapshot()
	_audio_max_voices = maxi(
		_audio_max_voices,
		int(snapshot.get("active_voices", 0))
	)
	_audio_max_music_players = maxi(
		_audio_max_music_players,
		int(snapshot.get("active_music_players", 0))
	)
	_audio_saw_crossfade = (
		_audio_saw_crossfade
		or bool(snapshot.get("crossfading", false))
	)
	if _audio_stage == 0 and _elapsed >= 0.8:
		for cue in [
			"click",
			"reveal",
			"ui_reject",
			"threat_pursuer",
			"threat_boarder",
			"threat_drainer",
			"impact",
			"defense_fire",
			"focus",
			"ward_break",
			"ward_warning"
		]:
			var pan: float = float((_audio_stage + cue.length()) % 3 - 1)
			AudioManager.play_spatial(cue, pan)
		_audio_stage = 1
	elif _audio_stage == 1 and _elapsed >= 2.4:
		AudioManager.set_presentation_state({
			"mode": "travel",
			"music_state": "travel_tension",
			"tension": 0.86,
			"paused": false
		})
		_audio_stage = 2
	elif _audio_stage == 2 and _elapsed >= 4.5:
		AudioManager.set_presentation_state({
			"mode": "station",
			"music_state": "station",
			"tension": 0.0,
			"paused": true
		})
		AudioManager.play("station_enter")
		_audio_stage = 3
	elif _audio_stage == 3 and _elapsed >= 6.6:
		AudioManager.set_presentation_state({
			"mode": "boss",
			"music_state": "longshadow",
			"tension": 1.0,
			"paused": false
		})
		AudioManager.play("boss_veil")
		AudioManager.play("boss_tether")
		AudioManager.play("boss_charge")
		_audio_stage = 4
	elif _audio_stage == 4 and _elapsed >= 8.7:
		AudioManager.set_presentation_state({
			"mode": "ending",
			"music_state": "dawn",
			"tension": 0.0,
			"paused": false
		})
		AudioManager.play("victory")
		_audio_stage = 5
	if _elapsed < _duration:
		return
	snapshot = AudioManager.debug_snapshot()
	if not bool(snapshot.get("user_gestured", false)):
		_finish(12, "[probe] audio started without gesture state", true)
		return
	if not bool(snapshot.get("ambient_playing", false)):
		_finish(13, "[probe] procedural ambience did not start", true)
		return
	if String(snapshot.get("music_state", "")) != "dawn":
		_finish(14, "[probe] music state did not reach dawn", true)
		return
	if _audio_max_music_players > 2:
		_finish(15, "[probe] music crossfade exceeded two players", true)
		return
	if _audio_max_voices > AudioManager.voice_capacity():
		_finish(16, "[probe] audio exceeded the voice ceiling", true)
		return
	if not _audio_saw_crossfade:
		_finish(17, "[probe] music crossfade was not observed", true)
		return
	print(
		"[probe] audio max_voices=%d max_music=%d final=%s"
		% [
			_audio_max_voices,
			_audio_max_music_players,
			str(snapshot)
		]
	)
	_finish(0, "[probe] audio OK")


func _prepare_boss_showcase() -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	var longshadow: LongshadowEncounter = (
		_game_world.get("_longshadow") as LongshadowEncounter
	)
	if rs == null or longshadow == null:
		return
	var phase_name: String = OS.get_environment("LANTERN_BOSS_PHASE").to_upper()
	var phase: int = {
		"VEIL": 0,
		"TETHER": 1,
		"CHARGE": 2
	}.get(phase_name, 0)
	var max_health: float = [78.0, 96.0, 132.0][phase]
	var lens: String = ["Pale", "Hearth", "Standard"][phase]
	var thresholds: Array[float] = [14.0, 16.0, 12.0]
	rs.simulation_enabled = false
	rs.boss_triggered = true
	rs.distance = RunState.BOSS_GATE_DISTANCE
	rs.current_lens = lens
	_game_world.set("_mode", 3)
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		director.visible = false
	var projection: CanvasItem = _game_world.get("_route_projection") as CanvasItem
	if projection != null:
		projection.visible = false
	longshadow.start({
		"phase": phase,
		"phase_max_health": max_health,
		"health": max_health * 0.72,
		"attack_timer": 2.0,
		"charge_timer": 2.4 if phase == 2 else 11.0,
		"charge_stagger": float(thresholds[phase]) * 0.58,
		"target_band": 1,
		"target_switch_timer": 3.0,
		"elapsed": 24.0,
		"phase_elapsed": 12.0,
		"transition_timer": 0.0,
		"phase_unlocked": false,
		"response_progress": float(thresholds[phase]) * 0.58,
		"charge_warning_issued": phase == 2,
		"completed": false
	})
	var controller: TrainController = (
		_game_world.get("_train_controller") as TrainController
	)
	if controller != null:
		controller.aim_towards(longshadow.current_target_position())
	var hud: HUD = _game_world.get("_hud") as HUD
	if hud != null:
		hud.set_boss_status(longshadow.status_text(), longshadow.health_ratio())
	var world: WorldRenderer = _game_world.get("_world_renderer") as WorldRenderer
	if world != null:
		world.set_route_context({
			"category": "danger",
			"event_id": "danger_black_rain",
			"danger": 2
		})
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_game_world.set_process(false)
	longshadow.queue_redraw()


func _prepare_reference_scenario() -> void:
	if _game_world == null:
		return
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	rs.simulation_enabled = false
	# A/B routing: honour the requested renderer.
	var router: PresentationRouter = (
		_game_world.call("presentation_router") as PresentationRouter
	)
	if router != null:
		for category in PresentationRouter.ALL_CATEGORIES:
			router.set_category_enabled(category, _reference_scenario_a_b == "baked")
		_game_world.call("_apply_presentation_router")
	_game_world.call("set_reference_capture_state", true, 0.0)
	_register_reference_event_producers()
	match _reference_scenario_id:
		ReferenceScenarios.SCENARIO_HEADLIGHT_REVEAL:
			_prepare_scenario_headlight_reveal(rs)
		ReferenceScenarios.SCENARIO_STANDARD_DEFENSE:
			_prepare_scenario_standard_defense(rs)
		ReferenceScenarios.SCENARIO_HEAVY_CANNON:
			_prepare_scenario_heavy_cannon(rs)
		ReferenceScenarios.SCENARIO_FLAK:
			_prepare_scenario_flak(rs)
		ReferenceScenarios.SCENARIO_FOCUS:
			_prepare_scenario_focus(rs)
		ReferenceScenarios.SCENARIO_WARD_SHATTER:
			_prepare_scenario_ward_shatter(rs)
		ReferenceScenarios.SCENARIO_REPAIR:
			_prepare_scenario_repair(rs)
		ReferenceScenarios.SCENARIO_DETACHMENT:
			_prepare_scenario_detachment(rs)
		ReferenceScenarios.SCENARIO_LONGSHADOW_VEIL:
			_prepare_scenario_longshadow_phase(rs, LongshadowEncounter.Phase.VEIL)
		ReferenceScenarios.SCENARIO_LONGSHADOW_TETHER:
			_prepare_scenario_longshadow_phase(rs, LongshadowEncounter.Phase.TETHER)
		ReferenceScenarios.SCENARIO_LONGSHADOW_CHARGE:
			_prepare_scenario_longshadow_phase(rs, LongshadowEncounter.Phase.CHARGE)
		ReferenceScenarios.SCENARIO_DAWN:
			_prepare_scenario_dawn(rs)
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")
	_reference_capture_points = ReferenceScenarios.capture_points(
		_reference_scenario_id
	)
	_reference_scenario_started_at = _elapsed
	_reference_capture_index = 0
	_reference_capture_busy = false
	_reference_capture_paths.clear()
	_reference_capture_pixel_hashes.clear()
	_reference_capture_error = OK
	if not _reference_capture_points.is_empty():
		var first_point: Dictionary = _reference_capture_points[0]
		_game_world.call(
			"set_reference_capture_frame",
			_reference_scenario_id,
			String(first_point.get("label", "start")),
			float(first_point.get("time", 0.0)),
			0
		)
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.set_process(false)
	_game_world.set_process(false)
	_reference_scenario_prepared = true
	_reference_scenario_receipt = _build_scenario_receipt(rs)
	print(
		"[scenario] scenario_json ",
		JSON.stringify(_reference_scenario_receipt)
	)


func _process_reference_scenario() -> void:
	var capture_path: String = OS.get_environment(
		"LANTERN_REFERENCE_SCENARIO_CAPTURE"
	)
	if not capture_path.is_empty():
		_capture_requested = true
		if _reference_capture_error != OK:
			_finish(
				10,
				"[probe] scenario %s frame sequence failed error=%s" % [
					_reference_scenario_id,
					_reference_capture_error
				],
				true
			)
			return
		if (
			not _reference_capture_busy
			and _reference_capture_index < _reference_capture_points.size()
		):
			var point: Dictionary = _reference_capture_points[
				_reference_capture_index
			]
			var point_time: float = float(point.get("time", 0.0))
			if _elapsed - _reference_scenario_started_at >= point_time:
				var label: String = String(
					point.get("label", "frame")
				)
				_apply_reference_capture_point(
					_reference_capture_index,
					point
				)
				_game_world.call(
					"set_reference_capture_frame",
					_reference_scenario_id,
					label,
					point_time,
					_reference_capture_index
				)
				var frame_path: String = _reference_capture_path(
					capture_path,
					_reference_capture_index,
					label
				)
				_reference_capture_busy = true
				call_deferred(
					"_capture_reference_frame",
					frame_path,
					_reference_capture_index,
					label
				)
				return
		if (
			not _reference_capture_busy
			and _reference_capture_index >= _reference_capture_points.size()
		):
			_capture_complete = true
			var final_rs: RunState = (
				_game_world.get("run_state") as RunState
			)
			print(
				"[scenario] capture_json ",
				JSON.stringify({
					"id": _reference_scenario_id,
					"ab_variant": _reference_scenario_a_b,
					"paths": _reference_capture_paths,
					"pixel_hashes": _reference_capture_pixel_hashes,
					"capture_points": _reference_capture_points,
					"final_receipt": (
						_build_scenario_receipt(final_rs)
						if final_rs != null
						else {}
					)
				})
			)
			_finish(
				0,
				"[probe] scenario %s frame sequence captured"
				% _reference_scenario_id
			)
			return
		var last_time: float = (
			float(
				_reference_capture_points[
					_reference_capture_points.size() - 1
				].get("time", 0.0)
			)
			if not _reference_capture_points.is_empty()
			else 0.0
		)
		if _elapsed - _reference_scenario_started_at > last_time + 5.0:
			_finish(
				10,
				"[probe] scenario %s frame sequence timed out"
				% _reference_scenario_id,
				true
			)
			return
		return
	if _elapsed - _reference_scenario_started_at >= _duration:
		_finish(0, "[probe] scenario %s ok" % _reference_scenario_id)


func _build_scenario_receipt(rs: RunState) -> Dictionary:
	var receipt: Dictionary = {
		"id": _reference_scenario_id,
		"title": ReferenceScenarios.title(_reference_scenario_id),
		"category": ReferenceScenarios.category(_reference_scenario_id),
		"ab_variant": _reference_scenario_a_b,
		"profile": GameManager.resolved_presentation_profile(),
		"capture_points": ReferenceScenarios.capture_points(
			_reference_scenario_id
		),
		"train_hp_ratio": (
			rs.locomotive_hp / maxf(1.0, rs.locomotive_max_hp)
		),
		"cars": rs.cars.size(),
		"stable_ids": {}
	}
	var stable_ids: Dictionary = receipt["stable_ids"]
	stable_ids["train"] = VisualStateIds.TRAIN_LOCOMOTIVE
	stable_ids["world_root"] = VisualStateIds.WORLD_ROOT
	stable_ids["longshadow_root"] = VisualStateIds.LONGSHADOW_ROOT
	var car_ids: Array = []
	for car_variant in rs.cars:
		var car: Dictionary = car_variant
		car_ids.append(VisualStateIds.car(String(car.get("id", ""))))
	stable_ids["cars"] = car_ids
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		var enemy_ids: Array = []
		for enemy_variant in director.active_enemies():
			var enemy: Enemy = enemy_variant
			enemy_ids.append(enemy.stable_id())
		stable_ids["enemies"] = enemy_ids
	var longshadow: LongshadowEncounter = (
		_game_world.get("_longshadow") as LongshadowEncounter
	)
	if longshadow != null and longshadow.is_active():
		stable_ids["longshadow_phase"] = VisualStateIds.longshadow_phase(
			longshadow.phase_index()
		)
	var router: PresentationRouter = (
		_game_world.call("presentation_router") as PresentationRouter
	)
	if router != null:
		receipt["router"] = router.category_snapshot()
	var world_renderer: WorldRenderer = (
		_game_world.get("_world_renderer") as WorldRenderer
	)
	var world_view: WorldSpriteView = (
		_game_world.get("_world_sprite_view") as WorldSpriteView
	)
	var train_renderer: TrainRenderer = (
		_game_world.get("_train_renderer") as TrainRenderer
	)
	var train_view: TrainSpriteView = (
		_game_world.get("_train_sprite_view") as TrainSpriteView
	)
	var enemy_view: EnemyViewPool = (
		_game_world.get("_enemy_view_pool") as EnemyViewPool
	)
	var boss_view: LongshadowView = (
		_game_world.get("_longshadow_view") as LongshadowView
	)
	var effects: EffectsLayer = (
		_game_world.get("_effects") as EffectsLayer
	)
	var vfx: VfxPool = _game_world.get("_vfx_pool") as VfxPool
	receipt["view_routes"] = {
		"world_vector": world_renderer != null and world_renderer.visible,
		"world_baked": world_view != null and world_view.baked_enabled(),
		"train_vector": train_renderer != null and train_renderer.visible,
		"train_baked": train_view != null and train_view.baked_enabled(),
		"enemies_baked": enemy_view != null and enemy_view.baked_enabled(),
		"longshadow_baked": boss_view != null and boss_view.baked_enabled(),
		"effects_vector": effects != null and effects.visible,
		"effects_baked": vfx != null and vfx.baked_enabled()
	}
	return receipt


func reference_scenario_receipt() -> Dictionary:
	return _reference_scenario_receipt.duplicate(true)


func _register_reference_event_producers() -> void:
	var bus: PresentationEventBus = (
		_game_world.call("event_bus") as PresentationEventBus
	)
	if bus == null:
		return
	bus.register_simulation_producer(
		REFERENCE_SIM_PRODUCER_ID,
		[
			SimEvent.TYPE_ENEMY_TELEGRAPHED,
			SimEvent.TYPE_DEFENSE_FIRED,
			SimEvent.TYPE_ENEMY_HIT,
			SimEvent.TYPE_WARD_CRACKED,
			SimEvent.TYPE_WARD_SHATTERED,
			SimEvent.TYPE_BOSS_RESPONSE,
			SimEvent.TYPE_DAWN_ARRIVAL
		]
	)
	bus.register_presentation_producer(
		REFERENCE_PRESENTATION_PRODUCER_ID,
		[
			PresentationEvent.TYPE_PARTICLE_BURST,
			PresentationEvent.TYPE_UI_EMPHASIS
		]
	)
	var issues: Array[String] = bus.run_startup_audit()
	for issue in issues:
		push_error("[scenario] event audit: %s" % issue)


func _apply_reference_capture_point(
	frame_index: int,
	point: Dictionary
) -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	if rs == null:
		return
	var progress: float = float(frame_index) / 3.0
	var point_time: float = float(point.get("time", 0.0))
	var train_pos: Vector2 = _place_train_at_reference()
	var effects: EffectsLayer = _game_world.get("_effects") as EffectsLayer
	var enemy: Enemy = _reference_enemy()
	match _reference_scenario_id:
		ReferenceScenarios.SCENARIO_HEADLIGHT_REVEAL:
			if enemy != null:
				var view_size: Vector2 = get_viewport().get_visible_rect().size
				enemy.position = Vector2(
					lerpf(view_size.x * 0.8, view_size.x * 0.58, progress),
					train_pos.y + lerpf(120.0, -8.0, progress)
				)
				var controller: TrainController = (
					_game_world.get("_train_controller") as TrainController
				)
				if controller != null:
					controller.aim_towards(
						train_pos
						+ Vector2(620.0, lerpf(-170.0, -8.0, progress))
					)
				if frame_index > 0:
					_emit_reference_sim(
						SimEvent.TYPE_ENEMY_TELEGRAPHED,
						enemy.stable_id(),
						"",
						point_time,
						enemy.position,
						Vector2.LEFT,
						4.0 + float(frame_index),
						&"light"
					)
		ReferenceScenarios.SCENARIO_STANDARD_DEFENSE, \
		ReferenceScenarios.SCENARIO_HEAVY_CANNON, \
		ReferenceScenarios.SCENARIO_FLAK:
			if enemy != null:
				enemy.hp = maxf(
					1.0,
					enemy.max_hp * (1.0 - progress * 0.78)
				)
				enemy.position.x += float(frame_index) * 4.0
				var source: Vector2 = _defense_source_position(rs)
				if frame_index == 1:
					if effects != null:
						effects.add_tracer(source, enemy.position)
					_emit_reference_sim(
						SimEvent.TYPE_DEFENSE_FIRED,
						"defense:reference",
						enemy.stable_id(),
						point_time,
						source,
						(enemy.position - source).normalized(),
						8.0 + float(frame_index) * 3.0,
						&"muzzle"
					)
				elif frame_index >= 2:
					if effects != null:
						effects.add_hit(
							enemy.position,
							PresentationPalette.color(&"ember")
						)
					_emit_reference_sim(
						SimEvent.TYPE_ENEMY_HIT,
						"defense:reference",
						enemy.stable_id(),
						point_time,
						enemy.position,
						Vector2.RIGHT,
						12.0 + float(frame_index) * 4.0,
						&"impact"
					)
		ReferenceScenarios.SCENARIO_FOCUS:
			rs.focus_active_time = (
				0.0
				if frame_index == 0 or frame_index == 3
				else 1.8 - float(frame_index - 1) * 0.6
			)
			if enemy != null:
				enemy.position.x = lerpf(
					get_viewport().get_visible_rect().size.x * 0.7,
					get_viewport().get_visible_rect().size.x * 0.58,
					progress
				)
				enemy.hp = maxf(
					1.0,
					enemy.max_hp * (1.0 - progress * 0.5)
				)
			if frame_index > 0:
				_emit_reference_presentation(
					point_time,
					enemy.position if enemy != null else train_pos,
					6.0 + float(frame_index) * 4.0
				)
		ReferenceScenarios.SCENARIO_WARD_SHATTER:
			if enemy != null:
				enemy.ward_max_hp = 24.0
				enemy.ward_hp = [24.0, 12.0, 0.0, 0.0][frame_index]
				enemy.warded = frame_index < 2
				if frame_index > 0:
					if effects != null:
						effects.add_hit(
							enemy.position,
							PresentationPalette.color(&"shadow_veil"),
							"ward"
						)
					_emit_reference_sim(
						SimEvent.TYPE_WARD_CRACKED
						if frame_index == 1
						else SimEvent.TYPE_WARD_SHATTERED,
						enemy.stable_id(),
						"",
						point_time,
						enemy.position,
						Vector2.RIGHT,
						10.0 + float(frame_index) * 5.0,
						&"shadow_ink"
					)
		ReferenceScenarios.SCENARIO_REPAIR:
			rs.locomotive_hp = rs.locomotive_max_hp * [
				0.55, 0.64, 0.79, 0.92
			][frame_index]
			if frame_index > 0:
				_emit_reference_presentation(
					point_time,
					train_pos + Vector2(-20.0 + frame_index * 12.0, -30.0),
					5.0 + float(frame_index) * 3.0
				)
		ReferenceScenarios.SCENARIO_DETACHMENT:
			if frame_index == 1 and rs.cars.size() >= 3:
				_game_world.call("_on_detach")
			elif frame_index >= 2:
				_emit_reference_presentation(
					point_time,
					train_pos + Vector2(
						-180.0 - float(frame_index) * 45.0,
						20.0 + float(frame_index) * 12.0
					),
					8.0 + float(frame_index) * 4.0
				)
		ReferenceScenarios.SCENARIO_LONGSHADOW_VEIL, \
		ReferenceScenarios.SCENARIO_LONGSHADOW_TETHER, \
		ReferenceScenarios.SCENARIO_LONGSHADOW_CHARGE:
			_apply_longshadow_reference_point(point_time)
		ReferenceScenarios.SCENARIO_DAWN:
			rs.boss_defeated = true
			rs.distance = lerpf(
				RunState.BOSS_GATE_DISTANCE,
				RunState.JOURNEY_TARGET,
				progress
			)
			rs.victory = frame_index == 3
			if effects != null:
				effects.set_dawn_progress(progress)
			if frame_index > 0:
				_emit_reference_sim(
					SimEvent.TYPE_DAWN_ARRIVAL,
					"world:dawn",
					VisualStateIds.TRAIN_LOCOMOTIVE,
					point_time,
					train_pos,
					Vector2.RIGHT,
					progress,
					&"dawn"
				)
	rs.refresh_stats()
	_game_world.call("_update_presentational_state")
	_game_world.call("refresh_presentation_now")


func _apply_longshadow_reference_point(point_time: float) -> void:
	var rs: RunState = _game_world.get("run_state") as RunState
	var longshadow: LongshadowEncounter = (
		_game_world.get("_longshadow") as LongshadowEncounter
	)
	if rs == null or longshadow == null:
		return
	var phase: int = LongshadowEncounter.Phase.VEIL
	if _reference_scenario_id == ReferenceScenarios.SCENARIO_LONGSHADOW_TETHER:
		phase = LongshadowEncounter.Phase.TETHER
	elif (
		_reference_scenario_id
		== ReferenceScenarios.SCENARIO_LONGSHADOW_CHARGE
	):
		phase = LongshadowEncounter.Phase.CHARGE
	var transition_total: float = (
		LongshadowEncounter.ENTRANCE_DURATION
		if phase == LongshadowEncounter.Phase.VEIL
		else LongshadowEncounter.TRANSITION_DURATION
	)
	longshadow.start({
		"phase": phase,
		"phase_max_health": LongshadowEncounter.PHASE_HEALTH[phase],
		"health": LongshadowEncounter.PHASE_HEALTH[phase] * 0.72,
		"attack_timer": 2.0,
		"charge_timer": 2.4
		if phase == LongshadowEncounter.Phase.CHARGE
		else 11.0,
		"charge_stagger": 0.0,
		"target_band": 1,
		"target_switch_timer": 3.0,
		"elapsed": 24.0 + point_time,
		"phase_elapsed": 0.0
		if phase == LongshadowEncounter.Phase.VEIL
		else 12.0,
		"transition_timer": maxf(0.0, transition_total - point_time),
		"phase_unlocked": false,
		"response_progress": 0.0,
		"charge_warning_issued": (
			phase == LongshadowEncounter.Phase.CHARGE
		),
		"completed": false
	})
	if point_time > 0.0:
		_emit_reference_sim(
			SimEvent.TYPE_BOSS_RESPONSE,
			VisualStateIds.LONGSHADOW_ROOT,
			VisualStateIds.TRAIN_LOCOMOTIVE,
			point_time,
			longshadow.current_target_position(),
			Vector2.LEFT,
			8.0 + point_time * 3.0,
			&"shadow_ink"
		)


func _emit_reference_sim(
	type: StringName,
	source_id: String,
	target_id: String,
	timestamp: float,
	position: Vector2,
	direction: Vector2,
	strength: float,
	material: StringName
) -> void:
	var bus: PresentationEventBus = (
		_game_world.call("event_bus") as PresentationEventBus
	)
	if bus == null:
		return
	bus.emit_sim(
		REFERENCE_SIM_PRODUCER_ID,
		type,
		source_id,
		target_id,
		timestamp,
		position,
		direction,
		strength,
		material,
		{"scenario": _reference_scenario_id}
	)


func _emit_reference_presentation(
	timestamp: float,
	position: Vector2,
	strength: float
) -> void:
	var bus: PresentationEventBus = (
		_game_world.call("event_bus") as PresentationEventBus
	)
	if bus == null:
		return
	bus.emit_presentation(
		REFERENCE_PRESENTATION_PRODUCER_ID,
		PresentationEvent.TYPE_PARTICLE_BURST,
		"scenario:%s" % _reference_scenario_id,
		timestamp,
		position,
		Vector2.UP,
		strength,
		&"repair_spark",
		{"scenario": _reference_scenario_id}
	)


func _reference_enemy() -> Enemy:
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director == null or director.active_enemies().is_empty():
		return null
	return director.active_enemies()[0] as Enemy


func _defense_source_position(rs: RunState) -> Vector2:
	var renderer: TrainRenderer = (
		_game_world.get("_train_renderer") as TrainRenderer
	)
	if renderer == null:
		return _place_train_at_reference()
	for index in range(rs.cars.size()):
		if String(rs.cars[index].get("type", "")) == "Defense":
			return renderer.car_screen_center(index)
	return _place_train_at_reference()


func _spawn_scenario_enemy(
	director: EnemyDirector,
	kind: String,
	position: Vector2,
	target: Vector2,
	role: String
) -> Enemy:
	var rs: RunState = _game_world.get("run_state") as RunState
	if director == null or rs == null:
		return null
	var enemy: Enemy = director.call("_acquire") as Enemy
	if enemy == null:
		return null
	enemy.init_from_config(kind, rs.enemy_config.get(kind, {}))
	director.call("_assign_visual_id", enemy)
	enemy.position = position
	enemy.target = target
	enemy.role = role
	if role == "roof":
		enemy.boarder_car_index = maxi(0, rs.cars.size() - 1)
	return enemy


func _place_train_at_reference() -> Vector2:
	return Vector2(_game_world.get("_train_screen_pos"))


func _prepare_scenario_headlight_reveal(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.set_priority("light", 2)
	rs.power = 8.0
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_spawn_scenario_enemy(
			director,
			"Pursuer",
			Vector2(view_size.x * 0.72, train_pos.y + 2.0),
			train_pos + Vector2(-140.0, 0.0),
			"ground"
		)
		director.set_process(false)
	var controller: TrainController = (
		_game_world.get("_train_controller") as TrainController
	)
	if controller != null:
		controller.aim_towards(
			_place_train_at_reference()
			+ Vector2(600.0, -10.0)
		)


func _prepare_scenario_standard_defense(rs: RunState) -> void:
	rs.current_lens = "Standard"
	if not rs.has_car_type("Defense"):
		rs.add_car("Defense")
	rs.set_priority("defense", 2)
	rs.power = 12.0
	rs.refresh_stats()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_spawn_scenario_enemy(
			director,
			"Pursuer",
			Vector2(view_size.x * 0.55, train_pos.y - 20.0),
			train_pos + Vector2(-60.0, 0.0),
			"ground"
		)
		director.set_process(false)


func _prepare_scenario_heavy_cannon(rs: RunState) -> void:
	rs.current_lens = "Standard"
	if not rs.has_car_type("Defense"):
		rs.add_car("Defense")
	for car in rs.cars:
		if String((car as Dictionary).get("type", "")) == "Defense":
			(car as Dictionary)["upgrade"] = "heavy_cannon"
			break
	rs.set_priority("defense", 2)
	rs.power = 12.0
	rs.refresh_stats()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_spawn_scenario_enemy(
			director,
			"Pursuer",
			Vector2(view_size.x * 0.6, train_pos.y),
			train_pos + Vector2(-60.0, 0.0),
			"ground"
		)
		director.set_process(false)


func _prepare_scenario_flak(rs: RunState) -> void:
	rs.current_lens = "Standard"
	if not rs.has_car_type("Defense"):
		rs.add_car("Defense")
	for car in rs.cars:
		if String((car as Dictionary).get("type", "")) == "Defense":
			(car as Dictionary)["upgrade"] = "flak_array"
			break
	rs.set_priority("defense", 2)
	rs.power = 12.0
	rs.refresh_stats()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_spawn_scenario_enemy(
			director,
			"Drainer",
			Vector2(view_size.x * 0.7, train_pos.y - 130.0),
			train_pos + Vector2(60.0, -40.0),
			"air"
		)
		director.set_process(false)


func _prepare_scenario_focus(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.set_priority("light", 2)
	rs.lumen = 24.0
	rs.power = 10.0
	rs.focus_active_time = 3.0
	rs.refresh_stats()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_spawn_scenario_enemy(
			director,
			"Pursuer",
			Vector2(view_size.x * 0.65, train_pos.y),
			train_pos + Vector2(-60.0, 0.0),
			"ground"
		)
		director.set_process(false)


func _prepare_scenario_ward_shatter(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.set_priority("light", 2)
	rs.power = 10.0
	rs.focus_active_time = 2.0
	rs.refresh_stats()
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
		var train_pos: Vector2 = _place_train_at_reference()
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		var enemy: Enemy = _spawn_scenario_enemy(
			director,
			"Pursuer",
			Vector2(view_size.x * 0.6, train_pos.y - 30.0),
			train_pos + Vector2(-60.0, 0.0),
			"ground"
		)
		if enemy != null:
			enemy.warded = true
			enemy.ward_max_hp = 24.0
			enemy.ward_hp = 4.0
		director.set_process(false)


func _prepare_scenario_repair(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.set_priority("repair", 2)
	rs.power = 10.0
	rs.locomotive_hp = rs.locomotive_max_hp * 0.55
	rs.refresh_stats()


func _prepare_scenario_detachment(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.set_priority("engine", 2)
	rs.power = 10.0
	# Aim the last car for the visible split
	rs.cars[rs.cars.size() - 1]["hp"] = 4.0
	rs.refresh_stats()


func _prepare_scenario_longshadow_phase(rs: RunState, phase: int) -> void:
	var longshadow: LongshadowEncounter = (
		_game_world.get("_longshadow") as LongshadowEncounter
	)
	if longshadow == null:
		return
	rs.boss_triggered = true
	rs.distance = RunState.BOSS_GATE_DISTANCE
	rs.current_lens = LongshadowEncounter.PHASE_LENSES[phase]
	var director: EnemyDirector = (
		_game_world.get("_enemy_director") as EnemyDirector
	)
	if director != null:
		director.clear_regular_enemies()
	longshadow.start({
		"phase": phase,
		"phase_max_health": LongshadowEncounter.PHASE_HEALTH[phase],
		"health": LongshadowEncounter.PHASE_HEALTH[phase] * 0.72,
		"attack_timer": 2.0,
		"charge_timer": 2.4 if phase == LongshadowEncounter.Phase.CHARGE else 11.0,
		"charge_stagger": 0.0,
		"target_band": 1,
		"target_switch_timer": 3.0,
		"elapsed": 24.0,
		"phase_elapsed": 0.0
		if phase == LongshadowEncounter.Phase.VEIL
		else 12.0,
		"transition_timer": (
			LongshadowEncounter.ENTRANCE_DURATION
			if phase == LongshadowEncounter.Phase.VEIL
			else LongshadowEncounter.TRANSITION_DURATION
		),
		"phase_unlocked": false,
		"response_progress": 0.0,
		"charge_warning_issued": phase == LongshadowEncounter.Phase.CHARGE,
		"completed": false
	})
	_game_world.call("_set_mode", 3)


func _prepare_scenario_dawn(rs: RunState) -> void:
	rs.current_lens = "Standard"
	rs.boss_defeated = true
	rs.distance = RunState.BOSS_GATE_DISTANCE
	rs.victory = false
	rs.refresh_stats()
	var effects: EffectsLayer = _game_world.get("_effects") as EffectsLayer
	if effects != null:
		effects.set_dawn_progress(0.0)


func _capture_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = get_viewport().get_texture().get_image().save_png(path)
	_capture_result = result
	_capture_complete = true
	if result == OK:
		print("[capture] gameplay=", path)
	else:
		printerr("[capture] gameplay failed error=", result)


func _capture_reference_frame(
	path: String,
	frame_index: int,
	label: String
) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(
		path.get_base_dir()
	)
	var image: Image = get_viewport().get_texture().get_image()
	var hashing := HashingContext.new()
	var hash_result: Error = hashing.start(HashingContext.HASH_SHA256)
	var pixel_hash: String = ""
	if hash_result == OK:
		hashing.update(image.get_data())
		pixel_hash = hashing.finish().hex_encode()
	if result == OK:
		result = image.save_png(path)
	_reference_capture_error = result
	_capture_result = result
	_capture_path = path
	_reference_capture_busy = false
	if result == OK:
		_reference_capture_paths.append(path)
		_reference_capture_pixel_hashes.append(pixel_hash)
		_reference_capture_index = frame_index + 1
		print(
			"[capture] scenario_frame=%s index=%d label=%s path=%s" % [
				_reference_scenario_id,
				frame_index,
				label,
				path
			]
		)
	else:
		printerr(
			"[capture] scenario frame failed error=%s path=%s" % [
				result,
				path
			]
		)


func _reference_capture_path(
	base_path: String,
	frame_index: int,
	label: String
) -> String:
	var safe_label: String = label.to_lower().replace(" ", "_")
	var frame_token: String = "%02d-%s" % [frame_index, safe_label]
	if base_path.contains("{frame}") or base_path.contains("{label}"):
		return (
			base_path.replace("{frame}", frame_token)
			.replace("{label}", safe_label)
		)
	if base_path.get_extension().is_empty():
		return base_path.path_join(
			"%s-%s.png" % [_reference_scenario_id, frame_token]
		)
	if frame_index == 1:
		return base_path
	return "%s-%s.%s" % [
		base_path.get_basename(),
		frame_token,
		base_path.get_extension()
	]


func _finish(exit_code: int, message: String, is_error: bool = false) -> void:
	if _finished:
		return
	_finished = true
	var metrics_snapshot: Dictionary = {}
	if _game_world != null and "_presentation_metrics" in _game_world:
		var metrics: PresentationMetrics = (
			_game_world.get("_presentation_metrics") as PresentationMetrics
		)
		if metrics != null:
			metrics.sample_now()
			metrics_snapshot = metrics.snapshot()
			print("[probe] presentation ", metrics.summary_text())
			print("[probe] presentation_json ", metrics.summary_json())
	if _benchmark_mode == "visual":
		var benchmark_record := {
			"mode": _visual_benchmark_mode,
			"enemy_count": _visual_benchmark_enemies,
			"boss_active": _visual_benchmark_boss,
			"duration_seconds": _duration,
			"metrics": metrics_snapshot
		}
		print(
			"[probe] visual_benchmark_json ",
			JSON.stringify(benchmark_record)
		)
		WebRuntimeQuery.publish(
			"__lanternBenchmarkResult",
			benchmark_record
		)
	if _benchmark_mode == "audio":
		AudioManager.stop_all_for_probe()
	GameManager.meta = _saved_meta
	GameManager.settings = _saved_settings
	GameManager.pending_run = _saved_pending
	GameManager.has_pending_run = _saved_has_pending
	GameManager.emit_signal("settings_changed")
	GameManager.call("_save")
	if is_error:
		printerr(message)
	else:
		print(message)
	get_tree().quit(exit_code)
