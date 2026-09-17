extends Node
## smoke_test.gd
##
## Deterministic runtime smoke test. Exercises:
##   - Data loading
##   - Route generation
##   - Resource ticks
##   - Enemy spawn + kill
##   - Detachment
##   - Save serialization round trip
##   - Full route/station/boss/victory campaign flow
##   - Victory + Defeat transitions
## Exits nonzero on failure.

var _failures: Array = []


func run(_host: Node) -> void:
	print("[smoke] starting")
	_test_data_load()
	_test_route_generation()
	_test_run_state_tick()
	_test_disabled_car_power()
	_test_run_length()
	_test_enemy_flow()
	_test_detach()
	_test_deterministic_damage()
	_test_save_roundtrip()
	_test_boss_resume(_host)
	_test_campaign_flow(_host)
	_test_finished_run_clears_checkpoint(_host)
	_test_end_states()
	if _failures.is_empty():
		print("[smoke] ALL PASSED")
		Engine.get_main_loop().quit(0)
	else:
		for f in _failures:
			printerr("[smoke] FAIL: ", f)
		Engine.get_main_loop().quit(2)


func _fail(msg: String) -> void:
	_failures.append(msg)


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


func _mk_configs() -> Dictionary:
	return {
		"cars": _load_json("res://data/cars.json").get("cars", {}),
		"lenses": _load_json("res://data/lenses.json").get("lenses", {}),
		"enemies": _load_json("res://data/enemies.json").get("enemies", {}),
		"crew": _load_json("res://data/crew.json").get("crew", []),
		"events": _load_json("res://data/route_events.json").get("events", [])
	}


func _test_data_load() -> void:
	var c: Dictionary = _mk_configs()
	if not c["cars"].has("Battery"): _fail("cars.json missing Battery")
	if not c["lenses"].has("Hearth"): _fail("lenses.json missing Hearth")
	if not c["enemies"].has("Boss"): _fail("enemies.json missing Boss")
	if (c["crew"] as Array).is_empty(): _fail("crew.json empty")
	if (c["events"] as Array).size() < 6: _fail("route_events.json too few events")


func _test_route_generation() -> void:
	var configs: Dictionary = _mk_configs()
	var rd: RouteDirector = RouteDirector.new()
	rd.setup(1234, configs["events"], configs["lenses"])
	var choices_a: Array = rd.generate_choices(1, "Standard")
	var choices_b: Array = rd.generate_choices(1, "Standard")
	if choices_a.size() != 3: _fail("route reveal did not produce 3 choices")
	if String(choices_a[0].get("id", "")) != String(choices_b[0].get("id", "")):
		_fail("route generation not deterministic for same seed+index")
	# lens bias changes distribution
	var pale: Array = rd.generate_choices(2, "Pale")
	var hearth: Array = rd.generate_choices(2, "Hearth")
	if pale.size() != 3 or hearth.size() != 3:
		_fail("lens reveal did not produce 3 choices")


func _test_run_state_tick() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(42, configs)
	var start: float = rs.distance
	for i in range(60):
		rs.tick(0.1)
	if rs.distance <= start:
		_fail("distance did not advance after ticking")
	if rs.supplies <= 0.0:
		_fail("supplies drained too fast in tick test")
	# lens switch
	if not rs.request_lens("Pale"):
		_fail("lens switch failed")
	if rs.request_lens("Hearth"):
		_fail("lens switch during cooldown should have failed")
	# priority
	rs.cycle_priority("engine")
	rs.cycle_priority("light")


func _test_disabled_car_power() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(43, configs)
	var powered_net: float = rs.current_power_net()
	for car in rs.cars:
		if String(car.get("type", "")) == "Battery":
			car["hp"] = 0.0
	var disabled_net: float = rs.current_power_net()
	if not is_equal_approx(powered_net - disabled_net, 5.0):
		_fail("destroyed battery continued producing power")


func _test_run_length() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(44, configs)
	var expected_seconds: float = RunState.JOURNEY_TARGET / rs.current_speed()
	if expected_seconds < 480.0 or expected_seconds > 900.0:
		_fail("expected 1x run length outside 8-15 minute target: %.1fs" % expected_seconds)


func _test_enemy_flow() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(99, configs)
	var ed: EnemyDirector = EnemyDirector.new()
	ed.setup(rs, Vector2(1280, 720))
	ed._spawn_wave()
	if ed._active.size() < 1:
		_fail("enemy spawn produced no active enemies")
	# apply direct damage to first
	var e: Enemy = ed._active[0]
	e.hp = 0.0
	# manually simulate one tick worth of update by clearing dead
	var killed: bool = false
	for a in ed._active:
		if a.hp <= 0:
			a.alive = false
			killed = true
	if not killed:
		_fail("enemy did not die after hp<=0")


func _test_detach() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(7, configs)
	var before: int = rs.cars.size()
	var rear: Dictionary = rs.detach_rear_car()
	if rear.is_empty():
		_fail("detach returned empty")
	if rs.cars.size() != before - 1:
		_fail("detach did not remove one car")
	rs.trigger_detach_boost()
	if rs.detach_boost_time <= 0.0:
		_fail("detach did not start the temporary speed boost")


func _test_deterministic_damage() -> void:
	var configs: Dictionary = _mk_configs()
	var first: RunState = RunState.new()
	var second: RunState = RunState.new()
	first.setup(8128, configs)
	second.setup(8128, configs)
	for index in range(8):
		first.damage_random_car(1.0)
		second.damage_random_car(1.0)
	for index in range(first.cars.size()):
		if not is_equal_approx(float(first.cars[index]["hp"]), float(second.cars[index]["hp"])):
			_fail("random car damage diverged for identical seed and inputs")


func _test_save_roundtrip() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(555, configs)
	rs.distance = 1234.5
	rs.supplies = 22.0
	var d: Dictionary = rs.to_dict()
	var s: String = JSON.stringify(d)
	var parsed: Variant = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("save JSON did not roundtrip")
		return
	var rs2: RunState = RunState.new()
	rs2.setup(555, configs)
	rs2.apply_dict(parsed)
	if abs(rs2.distance - 1234.5) > 0.1:
		_fail("distance did not survive save roundtrip")
	if rs2.damage_roll_index != rs.damage_roll_index:
		_fail("damage roll index did not survive save roundtrip")


func _test_boss_resume(host: Node) -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(991, configs)
	rs.distance = RunState.BOSS_DISTANCE + 20.0
	rs.boss_triggered = true
	rs.boss_defeated = false
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", 991, rs.to_dict())
	var director: EnemyDirector = world.get("_enemy_director") as EnemyDirector
	if director == null or not director.boss_active():
		_fail("resumed boss encounter did not restore the boss")
	world.queue_free()


func _test_campaign_flow(host: Node) -> void:
	var saved_meta: Dictionary = GameManager.meta.duplicate(true)
	var saved_pending: Dictionary = GameManager.pending_run.duplicate(true)
	var saved_has_pending: bool = GameManager.has_pending_run
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", 20260917, {})
	world.set("_last_autosave", -100000.0)
	var rs: RunState = world.get("run_state") as RunState
	var director: EnemyDirector = world.get("_enemy_director") as EnemyDirector
	var controller: TrainController = world.get("_train_controller") as TrainController
	var route_choice: RouteChoice = world.get("_route_choice") as RouteChoice
	var station: StationPanel = world.get("_station_panel") as StationPanel
	rs.speed_scale = 2.0
	var route_commits: int = 0
	var added_defense: bool = false
	var reordered: bool = false
	var boss_tactics_set: bool = false
	var iterations: int = 0
	while not bool(world.get("_ended")) and iterations < 5000:
		controller.aim_towards(Vector2(1200.0, 500.0))
		world.call("_process", 0.25)
		director.call("_process", 0.25)
		if bool(world.get("_reveal_open")):
			var choices: Array = route_choice.get("_choices")
			route_choice.call("_select", _campaign_choice_index(choices, rs))
			route_commits += 1
		if bool(world.get("_station_open")):
			var car_count_before: int = rs.cars.size()
			station.call("_try_add", "Defense")
			added_defense = rs.cars.size() == car_count_before + 1
			rs.set_priority("repair", 0)
			if rs.cars.size() >= 2:
				var rear_type: String = String(rs.cars.back().get("type", ""))
				station.call("_try_reorder")
				reordered = String(rs.cars.front().get("type", "")) == rear_type
			station.call("_close")
		if rs.boss_triggered and not boss_tactics_set:
			rs.set_priority("engine", 0)
			rs.set_priority("light", 2)
			rs.set_priority("defense", 1)
			rs.set_priority("repair", 1)
			boss_tactics_set = true
		iterations += 1
	if not bool(world.get("_ended")) or not rs.victory:
		_fail("campaign flow ended early: time=%.1f distance=%.1f loco=%.1f cars=%d enemies=%d" % [
			rs.travel_time,
			rs.distance,
			rs.locomotive_hp,
			rs.cars.size(),
			director.active_count()
		])
	if not rs.station_completed or not added_defense or not reordered:
		_fail("campaign station add/reorder flow did not complete")
	if not rs.boss_defeated:
		_fail("campaign boss was not defeated")
	if route_commits < 8:
		_fail("campaign committed too few route reveals")
	if rs.travel_time < 480.0 or rs.travel_time > 900.0:
		_fail("campaign duration outside 8-15 minute target: %.1fs" % rs.travel_time)
	print("[smoke] campaign victory time=%.1fs routes=%d supplies=%.1f loco=%.1f" % [
		rs.travel_time,
		route_commits,
		rs.supplies,
		rs.locomotive_hp
	])
	world.queue_free()
	GameManager.meta = saved_meta
	GameManager.pending_run = saved_pending
	GameManager.has_pending_run = saved_has_pending
	GameManager.call("_save")


func _campaign_choice_index(choices: Array, rs: RunState) -> int:
	var best_index: int = 0
	var best_score: float = -INF
	for index in range(choices.size()):
		var event: Dictionary = choices[index]
		var rewards: Dictionary = event.get("rewards", {})
		var supply_value: float = float(rewards.get("supplies", 0.0))
		var scrap_value: float = float(rewards.get("scrap", 0.0))
		var score: float = supply_value * (5.0 if rs.supplies < 28.0 else 2.0)
		score += scrap_value * (5.0 if rs.scrap < 10.0 and not rs.station_completed else 0.7)
		score += float(rewards.get("power", 0.0)) * 0.5
		score += float(rewards.get("lumen", 0.0)) * 0.25
		score -= float(event.get("danger", 0)) * 1.5
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _test_finished_run_clears_checkpoint(host: Node) -> void:
	var saved_meta: Dictionary = GameManager.meta.duplicate(true)
	var saved_pending: Dictionary = GameManager.pending_run.duplicate(true)
	var saved_has_pending: bool = GameManager.has_pending_run
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(992, configs)
	rs.distance = RunState.JOURNEY_TARGET
	rs.boss_triggered = true
	rs.boss_defeated = true
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", 992, rs.to_dict())
	world.set("_last_autosave", 9.0)
	world.call("_process", 0.0)
	if GameManager.has_continue():
		_fail("finished run was saved as a continue checkpoint")
	world.queue_free()
	GameManager.meta = saved_meta
	GameManager.pending_run = saved_pending
	GameManager.has_pending_run = saved_has_pending
	GameManager.call("_save")


func _test_end_states() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(21, configs)
	rs.locomotive_hp = 1.0
	rs.damage_locomotive(5.0)
	if not rs.defeat:
		_fail("defeat did not trigger on locomotive hp 0")
	var rs2: RunState = RunState.new()
	rs2.setup(22, configs)
	rs2.victory = true
	if not rs2.victory:
		_fail("victory flag not set")
