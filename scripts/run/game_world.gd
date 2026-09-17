extends Node
## game_world.gd
##
## Top-level run coordinator. The ONLY cross-system signal wiring point.
## Owns RunState and lifetime of all systems for a single run.

signal run_ended(victory: bool)

const DATA_CARS: String = "res://data/cars.json"
const DATA_LENSES: String = "res://data/lenses.json"
const DATA_ENEMIES: String = "res://data/enemies.json"
const DATA_CREW: String = "res://data/crew.json"
const DATA_ROUTES: String = "res://data/route_events.json"

const REVEAL_INTERVAL: float = 52.0

var run_state: RunState
var route_director: RouteDirector

# Systems
var _world_renderer: WorldRenderer
var _train_renderer: TrainRenderer
var _train_controller: TrainController
var _enemy_director: EnemyDirector
var _effects: EffectsLayer
var _hud: HUD
var _route_choice: RouteChoice
var _station_panel: StationPanel
var _end_screen: EndScreen

var _view_size: Vector2 = Vector2(1280, 720)
var _reveal_timer: float = REVEAL_INTERVAL
var _reveal_open: bool = false
var _station_open: bool = false
var _paused_before_modal: bool = false
var _last_autosave: float = 0.0
var _ended: bool = false
var _train_screen_pos: Vector2 = Vector2(360, 500)


func bootstrap(run_seed: int, resume: Dictionary) -> void:
	_view_size = get_viewport().get_visible_rect().size
	if _view_size.x < 100:
		_view_size = Vector2(1280, 720)

	# Load data JSON
	var configs: Dictionary = {
		"cars": _load_json(DATA_CARS).get("cars", {}),
		"lenses": _load_json(DATA_LENSES).get("lenses", {}),
		"enemies": _load_json(DATA_ENEMIES).get("enemies", {}),
		"crew": _load_json(DATA_CREW).get("crew", []),
		"events": _load_json(DATA_ROUTES).get("events", [])
	}

	run_state = RunState.new()
	run_state.setup(run_seed, configs)
	if not resume.is_empty():
		run_state.apply_dict(resume)

	route_director = RouteDirector.new()
	route_director.setup(run_seed, configs["events"], configs["lenses"])

	# Build scene tree
	var world_layer: Node2D = Node2D.new()
	world_layer.name = "WorldLayer"
	add_child(world_layer)

	_world_renderer = WorldRenderer.new()
	_world_renderer.setup(_view_size)
	world_layer.add_child(_world_renderer)

	_enemy_director = EnemyDirector.new()
	_enemy_director.setup(run_state, _view_size)
	world_layer.add_child(_enemy_director)

	_train_renderer = TrainRenderer.new()
	_train_renderer.setup(run_state)
	_train_screen_pos = Vector2(_view_size.x * 0.28, _view_size.y * 0.72)
	_train_renderer.set_position_hint(_train_screen_pos)
	world_layer.add_child(_train_renderer)

	_train_controller = TrainController.new()
	_train_controller.set_origin_screen(_train_screen_pos + Vector2(74, -24))
	add_child(_train_controller)

	_effects = EffectsLayer.new()
	world_layer.add_child(_effects)

	# UI layer (CanvasLayer so it's independent from world)
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

	_wire_signals()
	if not resume.is_empty() and run_state.boss_triggered and not run_state.boss_defeated:
		_enemy_director.spawn_boss()
	set_process(true)
	set_process_input(true)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _wire_signals() -> void:
	_hud.request_lens.connect(_on_lens)
	_hud.request_priority_cycle.connect(_on_priority)
	_hud.request_pause.connect(_on_pause)
	_hud.request_speed.connect(_on_speed)
	_hud.request_detach.connect(_on_detach)

	_route_choice.chosen.connect(_on_route_chosen)
	_route_choice.closed.connect(_on_reveal_closed)

	_station_panel.add_car.connect(_on_station_add)
	_station_panel.repair_all.connect(_on_station_repair)
	_station_panel.reorder_cars.connect(_on_station_reorder)
	_station_panel.closed.connect(_on_station_closed)

	_end_screen.closed.connect(_on_end_closed)
	_enemy_director.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	if _ended:
		return
	# tick state
	run_state.tick(delta)
	# reveal cadence
	if not _reveal_open and not _station_open and not run_state.paused and not run_state.victory and not run_state.defeat:
		_reveal_timer -= delta * run_state.speed_scale
		if _reveal_timer <= 0.0:
			_open_reveal()
	# Station trigger
	if not _reveal_open and not _station_open and not run_state.station_completed and run_state.distance >= RunState.STATION_DISTANCE:
		_open_station()
	# Boss trigger
	if not run_state.boss_triggered and run_state.distance >= RunState.BOSS_DISTANCE:
		run_state.boss_triggered = true
		_enemy_director.spawn_boss()
		_hud.flash("THE LONGSHADOW APPROACHES", 3.0)
		AudioManager.play("alarm")
	# Update audio wheel rhythm
	var speed_ratio: float = 0.0 if run_state.paused else run_state.current_speed() / 80.0
	AudioManager.set_wheel_rate(clampf(speed_ratio * 4.0, 0.2, 6.0))
	# Update world renderer
	var lens_col_arr: Array = run_state.lens_config.get(run_state.current_lens, {}).get("color", [1.0, 1.0, 1.0])
	var lens_col: Color = Color(float(lens_col_arr[0]), float(lens_col_arr[1]), float(lens_col_arr[2]))
	var lens_range: float = float(run_state.lens_config.get(run_state.current_lens, {}).get("reveal_range", 1.0))
	var power_factor: float = lerpf(0.35, 1.0, clampf(run_state.power / 6.0, 0.0, 1.0))
	var light_int: float = clampf((0.35 + float(run_state.priorities["light"]) * 0.22 + run_state.lumen * 0.008) * lens_range * power_factor, 0.16, 1.5)
	_world_renderer.update_state(run_state.distance, run_state.current_lens, lens_col, _train_controller.light_direction, light_int, _train_screen_pos)
	# Update enemy director light
	_enemy_director.set_train_pos(_train_screen_pos)
	_enemy_director.set_light(_train_controller.light_direction, light_int)
	# Aim from mouse
	var vp: Viewport = get_viewport()
	if vp:
		var mpos: Vector2 = vp.get_mouse_position()
		_train_controller.aim_towards(mpos)
		if _reveal_open:
			_route_choice.set_aim_band(_train_controller.current_band())
	# Dawn glow near end
	_effects.set_dawn_progress(clampf((run_state.distance - RunState.BOSS_DISTANCE) / (RunState.JOURNEY_TARGET - RunState.BOSS_DISTANCE), 0.0, 1.0))
	# camera shake (apply to world layer)
	var world_layer: Node = get_node_or_null("WorldLayer")
	if world_layer is Node2D:
		(world_layer as Node2D).position = _effects.shake_offset()
	# End conditions
	if run_state.boss_defeated and run_state.distance >= RunState.JOURNEY_TARGET:
		run_state.victory = true
	if run_state.victory:
		_finish(true)
		return
	elif run_state.defeat:
		_finish(false)
		return
	# autosave
	_last_autosave += delta
	if _last_autosave > 8.0:
		_last_autosave = 0.0
		GameManager.store_run_checkpoint(run_state.to_dict())


func _open_reveal() -> void:
	if _reveal_open:
		return
	_reveal_open = true
	run_state.reveal_index += 1
	_reveal_timer = REVEAL_INTERVAL
	var choices: Array = route_director.generate_choices(run_state.reveal_index, run_state.current_lens)
	_pause_for_modal()
	_route_choice.present(choices, run_state.current_lens, _train_controller.current_band())


func _open_station() -> void:
	if _station_open:
		return
	_station_open = true
	_pause_for_modal()
	_station_panel.present(run_state)
	_hud.flash("STATION AHEAD", 2.0)


func _on_route_chosen(event: Dictionary) -> void:
	run_state.apply_event_reward(event.get("rewards", {}))
	var danger: int = int(event.get("danger", 0))
	if danger > 0:
		_enemy_director.spawn_threat_waves(danger)
		_effects.request_shake(3.0)
	_hud.flash("Route chosen: %s" % String(event.get("title", "?")))


func _on_reveal_closed() -> void:
	_reveal_open = false
	_restore_modal_pause()


func _on_station_add(type_key: String) -> void:
	run_state.add_car(type_key)


func _on_station_repair() -> void:
	run_state.locomotive_hp = run_state.locomotive_max_hp
	for c in run_state.cars:
		c["hp"] = c["max_hp"]


func _on_station_reorder() -> void:
	run_state.rotate_rear_car_forward()


func _on_station_closed() -> void:
	_station_open = false
	run_state.station_completed = true
	_restore_modal_pause()


func _on_lens(name: String) -> void:
	if run_state.request_lens(name):
		AudioManager.play("click")
		_hud.flash("Lens: %s" % name, 1.5)


func _on_priority(role: String) -> void:
	run_state.cycle_priority(role)
	AudioManager.play("click")


func _on_pause() -> void:
	if _reveal_open or _station_open:
		return
	run_state.toggle_pause()
	AudioManager.play("click")


func _on_speed() -> void:
	run_state.toggle_speed()
	AudioManager.play("click")


func _on_detach() -> void:
	var rear: Dictionary = run_state.detach_rear_car()
	if rear.is_empty():
		AudioManager.play("alarm")
		return
	AudioManager.play("detach")
	_effects.request_shake(8.0)
	_enemy_director.on_detach(240.0)
	run_state.trigger_detach_boost()
	run_state.power = clampf(run_state.power + 2.0, 0.0, 12.0)
	_hud.flash("Rear car detached: %s" % String(rear.get("display", rear["type"])), 2.5)


func _on_enemy_killed(kind: String, value: int) -> void:
	_effects.add_hit(_train_screen_pos + Vector2(180, -20), Color(1.0, 0.6, 0.35))
	if value > 0:
		# minor scrap on killing enemies (except purged)
		run_state.scrap = clampf(run_state.scrap + float(value) * 0.5, 0.0, 200.0)
	if kind == "Boss":
		_hud.flash("THE LONGSHADOW FALLS", 3.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		AudioManager.notify_user_gesture()
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
	elif event.is_action_pressed("detach_car"):
		_on_detach()
	elif event.is_action_pressed("power_engine"):
		_on_priority("engine")
	elif event.is_action_pressed("power_light"):
		_on_priority("light")
	elif event.is_action_pressed("power_defense"):
		_on_priority("defense")
	elif event.is_action_pressed("power_repair"):
		_on_priority("repair")


func _finish(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	GameManager.record_run_end(run_state.distance, victory, run_state.run_seed)
	_end_screen.show_end(victory, run_state)


func _on_end_closed() -> void:
	emit_signal("run_ended", _ended and run_state.victory)


func _pause_for_modal() -> void:
	_paused_before_modal = run_state.paused
	run_state.paused = true


func _restore_modal_pause() -> void:
	run_state.paused = _paused_before_modal
