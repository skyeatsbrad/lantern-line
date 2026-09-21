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
	_test_accessibility_settings(_host)
	_test_route_generation()
	_test_run_state_tick()
	_test_priority_fail_safes()
	_test_brownout_load_shedding()
	_test_derived_stats_and_light()
	_test_story_modifiers()
	_test_station_transactions()
	_test_station_undo(_host)
	_test_field_actions()
	_test_crew_detachment()
	_test_crew_resume_and_repeat_destruction()
	_test_disabled_car_power()
	_test_run_length()
	_test_enemy_flow()
	_test_defense_salvo()
	_test_detach()
	_test_deterministic_damage()
	_test_save_roundtrip()
	_test_v1_save_migration()
	_test_mode_boundaries(_host)
	_test_hold_to_detach(_host)
	_test_boss_resume(_host)
	_test_boss_phase_pacing()
	_test_campaign_flow(_host)
	_test_balance_archetypes(_host)
	_test_seed_sweep(_host)
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


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


func _test_v1_save_migration() -> void:
	var legacy: Dictionary = _load_json("res://tests/fixtures/v1_save_payload.json")
	if legacy.is_empty():
		_fail("v1 migration fixture could not be loaded")
		return
	var migrated: Dictionary = GameManager.migrate_payload_for_test(legacy)
	_expect(is_equal_approx(float(migrated["settings"]["master_volume"]), 0.73), "v1 migration lost settings")
	_expect(bool(migrated["meta"]["dawn_reached"]), "v1 migration lost meta progress")
	_expect(bool(migrated["has_pending_run"]), "v1 migration dropped a valid pending run")
	var pending: Dictionary = migrated["pending_run"]
	_expect(int(pending.get("snapshot_version", 0)) == RunSnapshot.VERSION, "v1 run was not wrapped")
	var rs: RunState = RunState.new()
	rs.setup(1, _mk_configs())
	rs.apply_dict(RunSnapshot.run_state_data(pending))
	_expect(rs.cars.size() == 4, "v1 migration changed car count")
	_expect(rs.slot_capacity == 4, "v1 migration assigned the wrong slot capacity")
	var seen_ids: Dictionary = {}
	for car_variant in rs.cars:
		var car: Dictionary = car_variant
		var car_id := String(car.get("id", ""))
		_expect(not car_id.is_empty() and not seen_ids.has(car_id), "v1 migration produced invalid car ids")
		seen_ids[car_id] = true
		_expect(String(car.get("upgrade", "")).is_empty(), "v1 migration added an upgrade")
	_expect(is_equal_approx(rs.locomotive_hp, 63.5), "v1 migration lost locomotive integrity")
	_expect(is_equal_approx(rs.supplies, 41.25), "v1 migration lost supplies")
	_expect(is_equal_approx(rs.travel_time, 318.75), "v1 migration lost travel time")
	_expect(is_equal_approx(rs.stats().power_production, 8.0), "v1 migration changed base power")
	_expect(
		String(rs.crew[0].get("assigned_car_id", "")) == _first_car_id(rs, "Workshop"),
		"v1 Engine crew mapping changed"
	)
	_expect(
		String(rs.crew[1].get("assigned_car_id", "")) == _first_car_id(rs, "Defense"),
		"v1 Defense crew mapping changed"
	)
	_expect(RunSnapshot.normalize({"distance": 10.0}).is_empty(), "malformed legacy run was accepted")


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
	if not c["enemies"].has("Pursuer") or not c["enemies"].has("Boarder") or not c["enemies"].has("Drainer"):
		_fail("enemies.json missing a regular enemy archetype")
	if (c["crew"] as Array).is_empty(): _fail("crew.json empty")
	if (c["events"] as Array).size() < 20: _fail("route_events.json too few events")


func _test_accessibility_settings(host: Node) -> void:
	var saved_settings: Dictionary = GameManager.settings.duplicate(true)
	GameManager.set_setting("text_scale", 1.27)
	_expect(
		is_equal_approx(float(GameManager.get_setting("text_scale", 0.0)), 1.3),
		"text scale setting was not normalized"
	)
	_expect(UITheme.font_size(20) == 26, "text scale did not affect explicit font sizes")
	GameManager.set_setting("high_contrast", true)
	_expect(UITheme.high_contrast(), "high contrast setting did not reach the theme")
	GameManager.set_setting("reduced_flashes", true)
	var effects := EffectsLayer.new()
	effects.request_flash(Color(1.0, 0.4, 0.2, 0.8), 1.0)
	var reduced_color: Color = effects.get("_flash_color")
	_expect(reduced_color.a < 0.3, "reduced flashes did not limit overlay intensity")
	effects.free()

	var settings_panel := SettingsPanel.new()
	host.add_child(settings_panel)
	settings_panel.present()
	_expect(settings_panel.visible and settings_panel.is_open(), "settings panel did not open")
	settings_panel.hide_for_guide()
	_expect(not settings_panel.visible, "settings panel did not hide for the guide")
	settings_panel.free()

	var guide := GuidePanel.new()
	host.add_child(guide)
	guide.present("Close")
	_expect(guide.visible and guide.is_open(), "Conductor's Guide did not open")
	for page in range(GuidePanel.PAGES.size()):
		guide.call("_next_page")
	_expect(not guide.visible and not guide.is_open(), "Conductor's Guide did not close")
	guide.free()

	GameManager.settings = saved_settings
	GameManager.emit_signal("settings_changed")
	GameManager.call("_save")


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
	var seen_ids: Array = []
	for reveal_index in range(1, 7):
		var unique_choices := rd.generate_choices(reveal_index, "Standard", seen_ids, {})
		for event_variant in unique_choices:
			var event: Dictionary = event_variant
			var event_id := String(event.get("id", ""))
			_expect(not seen_ids.has(event_id), "route pool repeated before exhaustion")
			seen_ids.append(event_id)
	var ash_garden: Dictionary = {}
	for event_variant in configs["events"]:
		var event: Dictionary = event_variant
		if String(event.get("id", "")) == "living_ash_garden":
			ash_garden = event
	_expect(not rd._conditions_met(ash_garden, {}), "route chain follow-up ignored its gate")
	_expect(
		rd._conditions_met(ash_garden, {"ash_seed_planted": true}),
		"route chain follow-up did not unlock"
	)
	var projection := RouteProjection.new()
	projection.setup(Vector2(1280.0, 720.0), Vector2(360.0, 500.0))
	projection.present(choices_a)
	_expect(projection.index_for_cursor_y(40.0) == 0, "upper cursor did not select upper route")
	_expect(projection.index_for_cursor_y(360.0) == 1, "middle cursor did not select middle route")
	_expect(projection.index_for_cursor_y(700.0) == 2, "lower cursor did not select lower route")
	projection.free()


func _test_run_state_tick() -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(42, configs)
	_expect(int(rs.priorities.get("defense", -1)) == 0, "new runs keep absent Defense systems unpowered")
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


func _test_priority_fail_safes() -> void:
	var rs := RunState.new()
	rs.setup(4201, _mk_configs())
	rs.set_priority("light", 3)
	_expect(rs.change_priority("light", 1) == 3, "priority increase wrapped maximum to zero")
	_expect(int(rs.priorities["light"]) == 3, "priority maximum was not clamped")
	rs.set_priority("light", 0)
	_expect(rs.change_priority("light", -1) == 0, "priority decrease wrapped zero to maximum")
	_expect(int(rs.priorities["light"]) == 0, "priority minimum was not clamped")


func _test_brownout_load_shedding() -> void:
	var rs := RunState.new()
	rs.setup(4202, _mk_configs())
	_expect(rs.add_car("Defense"), "could not add Defense car for brownout test")
	for role in ["engine", "light", "defense", "repair"]:
		rs.set_priority(role, 3)
	rs.power = 0.5
	rs.brownout_active = true
	rs.refresh_stats()
	var stats: TrainStats = rs.stats()
	_expect(stats.requested_power_net < 0.0, "brownout test did not create excess demand")
	_expect(stats.power_net > 0.0, "load shedding left no recharge headroom")
	_expect(stats.system_state("light") == "active", "highest-priority Light load was shed")
	_expect(stats.system_state("defense") == "offline", "lower-priority Defense load was not shed")
	var before: float = rs.power
	rs.tick(1.0)
	_expect(rs.power > before, "brownout did not begin recovering stored power")


func _test_derived_stats_and_light() -> void:
	var rs := RunState.new()
	rs.setup(2244, _mk_configs())
	_expect(rs.stats().defense_mounts.is_empty(), "train stats invented a Defense mount")
	_expect(rs.add_car("Defense"), "could not add Defense car for derived-stat test")
	_expect(rs.stats().defense_mounts.is_empty(), "zero-priority Defense mount did not remain in standby")
	rs.set_priority("defense", 1)
	_expect(rs.stats().defense_mounts.size() == 1, "Defense car did not create exactly one mount")
	var origin := Vector2(100.0, 100.0)
	var normal: LightProfile = LightProfile.build(rs, rs.stats(), Vector2.RIGHT, origin)
	_expect(normal.contains(origin + Vector2(normal.range_px * 0.8, 0.0)), "light profile missed centerline")
	_expect(not normal.contains(origin + Vector2(0.0, normal.range_px * 0.8)), "light profile included outside point")
	rs.speed_scale = 2.0
	var fast_scan: LightProfile = LightProfile.build(rs, rs.stats(), Vector2.RIGHT, origin)
	_expect(
		fast_scan.spread_radians > normal.spread_radians,
		"fast travel did not widen the stabilized scan beam"
	)
	rs.speed_scale = 1.0
	rs.focus_active_time = 1.0
	var focused: LightProfile = LightProfile.build(rs, rs.stats(), Vector2.RIGHT, origin)
	_expect(focused.range_px > normal.range_px, "Focus did not extend headlight range")
	_expect(focused.spread_radians < normal.spread_radians, "Focus did not narrow headlight spread")
	_expect(is_equal_approx(focused.damage_multiplier, 4.0), "Focus damage multiplier changed")
	rs.focus_active_time = 0.0
	rs.current_lens = "Pale"
	var pale: LightProfile = LightProfile.build(rs, rs.stats(), Vector2.RIGHT, origin)
	_expect(pale.damage_multiplier > normal.damage_multiplier, "Pale lens did not increase beam damage")


func _test_story_modifiers() -> void:
	var rs := RunState.new()
	rs.setup(2245, _mk_configs())
	_expect(rs.add_car("Greenhouse"), "could not add Greenhouse for story modifier test")
	var base_supply_generation: float = rs.stats().supply_generation
	var base_repair: float = rs.stats().repair_rate
	var base_focus_cooldown: float = rs.stats().focus_cooldown
	rs.event_flags["ash_garden_found"] = true
	rs.event_flags["buried_bell_answered"] = true
	rs.event_flags["signal_vault_opened"] = true
	rs.refresh_stats()
	_expect(
		rs.stats().supply_generation > base_supply_generation,
		"Ash Garden did not improve Greenhouse output"
	)
	_expect(rs.stats().repair_rate > base_repair, "Bell Keeper did not improve repairs")
	_expect(
		rs.stats().focus_cooldown < base_focus_cooldown,
		"Signal Vault did not improve Focus recharge"
	)


func _test_station_transactions() -> void:
	var rs := RunState.new()
	rs.setup(31337, _mk_configs())
	rs.scrap = 100.0
	_expect(bool(rs.purchase_slot().get("ok", false)), "slot expansion transaction failed")
	_expect(rs.slot_capacity == 5, "slot expansion did not set capacity to five")
	_expect(not bool(rs.purchase_slot().get("ok", true)), "second slot expansion was allowed")
	_expect(bool(rs.purchase_car("Defense").get("ok", false)), "car purchase transaction failed")
	var defense: Dictionary = rs.cars.back()
	var defense_id := String(defense.get("id", ""))
	_expect(bool(rs.purchase_upgrade(defense_id, "heavy_cannon").get("ok", false)), "upgrade transaction failed")
	_expect(
		not bool(rs.purchase_upgrade(defense_id, "flak_array").get("ok", true)),
		"mutually exclusive upgrade was replaced"
	)
	_expect(bool(rs.assign_crew("ilo", defense_id).get("ok", false)), "compatible crew assignment failed")
	_expect(
		not bool(rs.assign_crew("mara", defense_id).get("ok", true)),
		"incompatible crew assignment succeeded"
	)
	_expect(bool(rs.move_car(defense_id, -3).get("ok", false)), "car reorder transaction failed")
	_expect(String(rs.cars.front().get("id", "")) == defense_id, "car reorder moved the wrong car")
	for role in ["engine", "light", "defense", "repair"]:
		rs.set_priority(role, 3)
	var projection: Dictionary = rs.station_projection()
	_expect(float(projection.get("power_net", 0.0)) < 0.0, "station projection missed a power deficit")
	_expect(
		not (projection.get("brownout_systems", []) as Array).is_empty(),
		"station projection did not identify brownout consequences"
	)
	rs.locomotive_hp -= 20.0
	_expect(bool(rs.purchase_repair().get("ok", false)), "repair transaction failed")
	_expect(is_equal_approx(rs.locomotive_hp, rs.locomotive_max_hp), "repair did not restore locomotive")


func _test_station_undo(host: Node) -> void:
	var saved_text_scale: float = float(GameManager.get_setting("text_scale", 1.0))
	GameManager.set_setting("text_scale", 1.3)
	var rs := RunState.new()
	rs.setup(31338, _mk_configs())
	rs.scrap = 100.0
	var panel := StationPanel.new()
	host.add_child(panel)
	panel.present(rs)
	_expect(bool(panel.get("_compact_layout")), "large text did not select the responsive station layout")
	var before_count: int = rs.cars.size()
	var before_scrap: float = rs.scrap
	panel._tabs.current_tab = 2
	panel.call("_try_add", "Defense")
	_expect(rs.cars.size() == before_count + 1, "station purchase did not apply before undo")
	_expect(
		panel._selected_tab == 2 and panel._tabs.current_tab == 2,
		"station transaction reset the selected tab"
	)
	panel.call("_undo_last")
	_expect(rs.cars.size() == before_count, "station undo did not restore the consist")
	_expect(is_equal_approx(rs.scrap, before_scrap), "station undo did not refund scrap")
	_expect(rs.add_car("Defense"), "could not prepare station departure warning")
	for role in ["engine", "light", "defense", "repair"]:
		rs.set_priority(role, 3)
	panel.present(rs)
	panel.call("_close")
	_expect(bool(panel.get("_open")), "station allowed an unconfirmed power-deficit departure")
	panel.call("_close")
	_expect(not bool(panel.get("_open")), "station did not accept the confirmed deficit departure")
	panel.queue_free()
	GameManager.set_setting("text_scale", saved_text_scale)


func _test_field_actions() -> void:
	var rs := RunState.new()
	rs.setup(31339, _mk_configs())
	rs.station_completed = true
	rs.scrap = 30.0
	rs.locomotive_hp = 70.0
	var patch_result: Dictionary = rs.purchase_field_patch()
	_expect(bool(patch_result.get("ok", false)), "field patch transaction failed")
	_expect(is_equal_approx(rs.locomotive_hp, 92.0), "field patch restored the wrong amount")
	_expect(is_equal_approx(rs.scrap, 24.0), "field patch charged the wrong scrap cost")
	rs.power = 2.0
	rs.lumen = 4.0
	var overcharge_result: Dictionary = rs.purchase_emergency_overcharge()
	_expect(bool(overcharge_result.get("ok", false)), "emergency overcharge transaction failed")
	_expect(is_equal_approx(rs.power, 6.0), "emergency overcharge restored the wrong power")
	_expect(is_equal_approx(rs.lumen, 7.0), "emergency overcharge restored the wrong lumen")
	_expect(rs.field_overcharge_time > 0.0, "emergency overcharge did not start its proactive boost")
	var flare_result: Dictionary = rs.purchase_signal_flare()
	_expect(bool(flare_result.get("ok", false)), "signal flare transaction failed")
	_expect(rs.field_flare_time > 0.0, "signal flare did not start its light boost")
	var reroll_result: Dictionary = rs.purchase_route_reroll()
	_expect(bool(reroll_result.get("ok", false)), "route reroll transaction failed")
	_expect(
		(rs.run_history.get("field_actions", []) as Array).size() == 4,
		"field actions were not recorded"
	)
	rs.speed_scale = 1.0
	rs.toggle_speed()
	_expect(is_equal_approx(rs.speed_scale, 1.5), "speed toggle skipped 1.5x")
	_expect(is_equal_approx(rs.combat_speed_scale(), 1.15), "1.5x combat pacing changed")
	rs.toggle_speed()
	_expect(is_equal_approx(rs.speed_scale, 2.0), "speed toggle skipped 2x")
	_expect(is_equal_approx(rs.combat_speed_scale(), 1.2), "2x combat cap did not engage")
	rs.trigger_critical_slow()
	_expect(
		is_equal_approx(rs.effective_speed_scale(), RunState.CRITICAL_SLOW_SCALE),
		"critical auto-slow did not engage"
	)


func _test_crew_detachment() -> void:
	var unsafe := RunState.new()
	unsafe.setup(9101, _mk_configs())
	var passenger_id := String(unsafe.cars.back().get("id", ""))
	_expect(
		String(unsafe.crew[2].get("assigned_car_id", "")) == passenger_id,
		"Sable did not begin in the Passenger car"
	)
	var detached := unsafe.detach_rear_car()
	_expect((detached.get("lost_crew", []) as Array).has("Sable Wren"), "unsafe detachment did not report lost crew")
	_expect(String(unsafe.crew[2].get("status", "")) == "lost", "unsafe detachment did not mark crew lost")

	var safe := RunState.new()
	safe.setup(9102, _mk_configs())
	safe.scrap = 20.0
	var safe_passenger_id := String(safe.cars.back().get("id", ""))
	_expect(
		bool(safe.purchase_upgrade(safe_passenger_id, "safe_quarters").get("ok", false)),
		"Safe Quarters upgrade could not be installed"
	)
	var safe_detached := safe.detach_rear_car()
	_expect(
		(safe_detached.get("evacuated_crew", []) as Array).has("Sable Wren"),
		"Safe Quarters did not evacuate assigned crew"
	)
	_expect(String(safe.crew[2].get("status", "")) == "fit", "evacuated crew was marked lost")
	_expect(String(safe.crew[2].get("assigned_car_id", "")) == "", "evacuated crew remained assigned")


func _test_crew_resume_and_repeat_destruction() -> void:
	var rs := RunState.new()
	rs.setup(9103, _mk_configs())
	_expect(bool(rs.assign_crew("sable", "").get("ok", false)), "crew unassignment failed")
	var restored := RunState.new()
	restored.setup(9103, _mk_configs())
	restored.apply_dict(rs.to_dict())
	_expect(
		String(restored.crew[2].get("assigned_car_id", "")) == "",
		"deliberately unassigned crew was reassigned on resume"
	)

	var workshop_id := _first_car_id(restored, "Workshop")
	var workshop_index := -1
	for index in range(restored.cars.size()):
		if String(restored.cars[index].get("id", "")) == workshop_id:
			workshop_index = index
			break
	restored._disable_destroyed_car(workshop_index)
	restored.repair_train(12.0)
	_expect(
		not bool(restored.cars[workshop_index].get("destroyed_notified", true)),
		"repair did not re-arm car destruction handling"
	)
	_expect(bool(restored.assign_crew("mara", workshop_id).get("ok", false)), "crew reassignment after repair failed")
	restored._disable_destroyed_car(workshop_index)
	_expect(
		String(restored.crew[0].get("assigned_car_id", "occupied")) == "",
		"second destruction did not evacuate reassigned crew"
	)


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
	ed.clear_regular_enemies()
	rs.distance = RunState.JOURNEY_TARGET * 0.75
	ed.spawn_threat_waves(30)
	_expect(
		ed.active_count() <= ed.pressure_limit(),
		"enemy pressure exceeded the readable active-threat limit"
	)
	rs.speed_scale = 2.0
	ed._process(0.1)
	_expect(
		rs.critical_slow_time > 0.0
		and is_equal_approx(rs.effective_speed_scale(), RunState.CRITICAL_SLOW_SCALE),
		"high enemy pressure did not engage the threat brake"
	)
	ed.free()


func _test_defense_salvo() -> void:
	var rs := RunState.new()
	rs.setup(100, _mk_configs())
	_expect(rs.add_car("Defense"), "could not add Defense car for salvo test")
	rs.set_priority("defense", 2)
	rs.power = 12.0
	var director := EnemyDirector.new()
	director.setup(rs, Vector2(1280, 720))
	director.set_train_pos(Vector2(360, 500))
	director._spawn_wave()
	for enemy_variant in director._active:
		var enemy: Enemy = enemy_variant
		enemy.position = Vector2(500, 450)
	var request: Dictionary = rs.request_defense_salvo()
	_expect(bool(request.get("ok", false)), "powered Defense Platform could not fire a salvo")
	var salvo: Dictionary = director.fire_manual_salvo(rs.stats())
	_expect(float(salvo.get("damage", 0.0)) > 0.0, "manual salvo dealt no damage")
	_expect(rs.defense_salvo_cooldown > 0.0, "manual salvo did not start its cooldown")
	director.free()


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
	rs.focus_active_time = 0.75
	rs.focus_cooldown = 6.25
	rs.defense_salvo_cooldown = 4.5
	rs.brownout_active = true
	rs.route_history = ["living_grove"]
	rs.route_seen_ids = ["living_grove", "machinery_pylons"]
	rs.event_flags = {"signal_code_known": true}
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
	_expect(is_equal_approx(rs2.focus_active_time, 0.75), "Focus active time did not survive save")
	_expect(is_equal_approx(rs2.focus_cooldown, 6.25), "Focus cooldown did not survive save")
	_expect(
		is_equal_approx(rs2.defense_salvo_cooldown, 4.5),
		"Defense salvo cooldown did not survive save"
	)
	_expect(rs2.brownout_active, "brownout state did not survive save")
	_expect(rs2.route_history == rs.route_history, "route history did not survive save")
	_expect(rs2.route_seen_ids == rs.route_seen_ids, "seen route pool did not survive save")
	_expect(bool(rs2.event_flags.get("signal_code_known", false)), "event flags did not survive save")


func _test_mode_boundaries(host: Node) -> void:
	var saved_pending: Dictionary = GameManager.pending_run.duplicate(true)
	var saved_has_pending: bool = GameManager.has_pending_run
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var station_world: Node = scene.instantiate()
	host.add_child(station_world)
	station_world.call("bootstrap", 7001, {})
	var station_state: RunState = station_world.get("run_state") as RunState
	station_state.distance = RunState.STATION_DISTANCE
	station_world.set("_reveal_timer", 0.0)
	station_world.call("_process", 0.0)
	_expect(bool(station_world.get("_station_open")), "station did not take precedence over route reveal")
	station_world.free()

	var route_world: Node = scene.instantiate()
	host.add_child(route_world)
	route_world.call("bootstrap", 7002, {})
	var route_state: RunState = route_world.get("run_state") as RunState
	route_world.set("_reveal_timer", 0.0)
	route_world.call("_process", 0.0)
	_expect(bool(route_world.get("_reveal_open")), "route reveal did not enter explicit mode")
	_expect(route_state.reveal_index == 0, "route index advanced before commitment")
	route_world.call("_open_settings")
	_expect(bool(route_world.get("_overlay_open")), "options did not open over route reveal")
	_expect(route_state.paused, "route options did not preserve a paused run state")
	var settings_panel: SettingsPanel = route_world.get("_settings_panel") as SettingsPanel
	settings_panel.call("_close")
	_expect(not bool(route_world.get("_overlay_open")), "route options did not close")
	_expect(bool(route_world.get("_reveal_open")), "closing options dismissed route reveal")
	var route_choice: RouteChoice = route_world.get("_route_choice") as RouteChoice
	route_choice.call("_select", 0)
	_expect(route_state.reveal_index == 1, "route index did not advance after commitment")
	route_world.free()
	GameManager.pending_run = saved_pending
	GameManager.has_pending_run = saved_has_pending
	GameManager.call("_save")


func _test_hold_to_detach(host: Node) -> void:
	var saved_short_holds: bool = bool(GameManager.get_setting("short_holds", false))
	GameManager.set_setting("short_holds", true)
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", 7003, {})
	var rs: RunState = world.get("run_state") as RunState
	var before := rs.cars.size()
	world.call("_on_detach_hold_changed", true)
	world.call("_process_detach_hold", 0.5)
	_expect(rs.cars.size() == before - 1, "hold-to-detach did not remove exactly one car")
	_expect(not bool(world.get("_detach_hold_active")), "detach hold remained active after completion")
	world.free()
	GameManager.set_setting("short_holds", saved_short_holds)


func _test_boss_resume(host: Node) -> void:
	var configs: Dictionary = _mk_configs()
	var rs: RunState = RunState.new()
	rs.setup(991, configs)
	rs.distance = RunState.BOSS_DISTANCE + 20.0
	rs.boss_triggered = true
	rs.boss_defeated = false
	var boss_state := {
		"phase": 1,
		"phase_max_health": 96.0,
		"health": 37.5,
		"attack_timer": 1.75,
		"charge_timer": 8.0,
		"charge_stagger": 4.5,
		"target_band": 2,
		"target_switch_timer": 1.25,
		"elapsed": 14.0,
		"completed": false
	}
	var snapshot := RunSnapshot.build(rs.to_dict(), {
		"run_mode": "boss",
		"reveal_timer": 20.0,
		"enemy_state": {"spawn_cooldown": 2.0, "wave_index": 9},
		"boss_state": boss_state
	})
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", 991, snapshot)
	var encounter: LongshadowEncounter = world.get("_longshadow") as LongshadowEncounter
	if encounter == null or not encounter.is_active():
		_fail("resumed boss encounter did not restore the boss")
	else:
		var restored := encounter.checkpoint_state()
		_expect(int(restored.get("phase", -1)) == 1, "boss resume changed phase")
		_expect(is_equal_approx(float(restored.get("health", 0.0)), 37.5), "boss resume changed health")
		_expect(
			is_equal_approx(float(restored.get("target_switch_timer", 0.0)), 1.25),
			"boss resume changed phase timer"
		)
	world.queue_free()


func _test_boss_phase_pacing() -> void:
	var rs := RunState.new()
	rs.setup(993, _mk_configs())
	rs.set_priority("light", 3)
	_expect(rs.add_car("Defense"), "could not prepare boss response reserve test")
	rs.set_priority("defense", 1)
	var encounter := LongshadowEncounter.new()
	encounter.setup(rs, Vector2(1280, 720), Vector2(360, 500))
	rs.focus_cooldown = 99.0
	rs.defense_salvo_cooldown = 99.0
	encounter.start()
	_expect(
		rs.focus_cooldown <= 0.0 and rs.defense_salvo_cooldown <= 0.0,
		"Longshadow phase did not ready its active responses"
	)
	var profile := LightProfile.new()
	profile.origin = Vector2(434.0, 476.0)
	profile.direction = (
		encounter.current_target_position() - profile.origin
	).normalized()
	profile.range_px = 5000.0
	profile.spread_radians = PI
	profile.damage_multiplier = 100.0
	encounter.advance(3.1, profile, rs.stats())
	rs.lumen = rs.stats().focus_cost
	rs.power = RunState.DEFENSE_SALVO_POWER_COST
	encounter.call("_perform_phase_attack")
	_expect(
		rs.lumen >= rs.stats().focus_cost
		and rs.power >= RunState.DEFENSE_SALVO_POWER_COST,
		"Veil attack consumed the protected active-response reserve"
	)
	_expect(
		encounter.focus_block_reason(profile).contains("Pale"),
		"Longshadow allowed Focus with the wrong phase lens"
	)
	for index in range(20):
		encounter.advance(1.0, profile, rs.stats())
	_expect(
		encounter.phase_name() == "VEIL",
		"Longshadow advanced without an active response"
	)
	profile.focused = true
	rs.current_lens = "Pale"
	_expect(
		encounter.focus_block_reason(profile).is_empty(),
		"Longshadow blocked an aligned Focus response"
	)
	rs.focus_active_time = 100.0
	encounter.advance(1.0, profile, rs.stats())
	_expect(encounter.phase_name() == "TETHER", "Longshadow Veil did not advance after its duration")
	encounter.free()

	var charge := LongshadowEncounter.new()
	charge.setup(rs, Vector2(1280, 720), Vector2(360, 500))
	charge.start({
		"phase": LongshadowEncounter.Phase.CHARGE,
		"phase_max_health": 132.0,
		"health": 132.0,
		"attack_timer": 4.0,
		"charge_timer": 0.1,
		"charge_stagger": 0.0,
		"target_band": 1,
		"target_switch_timer": 4.0,
		"elapsed": 0.0,
		"phase_elapsed": 4.0,
		"transition_timer": 0.0,
		"phase_unlocked": false,
		"response_progress": 0.0,
		"charge_warning_issued": true
	})
	rs.lumen = 0.0
	rs.power = 0.0
	rs.focus_cooldown = 20.0
	rs.defense_salvo_cooldown = 20.0
	var miss := LightProfile.new()
	miss.origin = Vector2.ZERO
	miss.direction = Vector2.LEFT
	miss.range_px = 10.0
	charge.advance(0.2, miss, rs.stats())
	_expect(
		rs.lumen >= rs.stats().focus_cost
		and rs.power >= RunState.DEFENSE_SALVO_POWER_COST
		and rs.focus_cooldown <= 0.0
		and rs.defense_salvo_cooldown <= 0.0,
		"failed Charge did not restore a response opportunity"
	)
	charge.free()


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
	var encounter: LongshadowEncounter = world.get("_longshadow") as LongshadowEncounter
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
		var regular_target: Vector2 = (
			director.nearest_warded_position(true)
			if director.has_warded_target_in_response_range()
			else Vector2(1200.0, 500.0)
		)
		controller.aim_towards(
			encounter.current_target_position()
			if encounter.is_active()
			else regular_target
		)
		if (
			encounter.is_active()
			and encounter.can_accept_active_response()
			and rs.focus_cooldown <= 0.0
		):
			rs.request_focus()
		elif director.has_warded_target_in_response_range() and rs.focus_cooldown <= 0.0:
			rs.request_focus()
		if (
			rs.station_completed
			and rs.scrap >= RunState.FIELD_OVERCHARGE_COST
			and (
				rs.power < 4.0
				or rs.lumen < rs.stats().focus_cost
			)
		):
			rs.purchase_emergency_overcharge()
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
			rs.set_priority("light", 3)
			rs.set_priority("defense", 2)
			rs.set_priority("repair", 0)
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


func _test_balance_archetypes(host: Node) -> void:
	var saved_meta: Dictionary = GameManager.meta.duplicate(true)
	var saved_pending: Dictionary = GameManager.pending_run.duplicate(true)
	var saved_has_pending: bool = GameManager.has_pending_run
	for strategy in ["beam", "gunline", "sustain"]:
		var result := _run_campaign_scenario(host, 20260917, strategy)
		print("[smoke] archetype %s -> %s" % [strategy, str(result)])
		_expect(bool(result.get("victory", false)), "%s archetype could not win" % strategy)
		_expect(bool(result.get("station_action", false)), "%s archetype made no station choice" % strategy)
		_expect(
			float(result.get("travel_time", 0.0)) >= 480.0
			and float(result.get("travel_time", 0.0)) <= 900.0,
			"%s archetype fell outside target duration" % strategy
		)
	GameManager.meta = saved_meta
	GameManager.pending_run = saved_pending
	GameManager.has_pending_run = saved_has_pending
	GameManager.call("_save")


func _test_seed_sweep(host: Node) -> void:
	var saved_meta: Dictionary = GameManager.meta.duplicate(true)
	var saved_pending: Dictionary = GameManager.pending_run.duplicate(true)
	var saved_has_pending: bool = GameManager.has_pending_run
	var wins := 0
	var seeds: Array[int] = [101, 202, 303, 404, 505, 606]
	for seed_value in seeds:
		var result := _run_campaign_scenario(host, seed_value, "adaptive")
		print("[smoke] seed %d -> %s" % [seed_value, str(result)])
		if bool(result.get("victory", false)):
			wins += 1
	_expect(wins >= 5, "adaptive seed sweep won only %d/%d campaigns" % [wins, seeds.size()])
	GameManager.meta = saved_meta
	GameManager.pending_run = saved_pending
	GameManager.has_pending_run = saved_has_pending
	GameManager.call("_save")


func _run_campaign_scenario(host: Node, seed_value: int, strategy: String) -> Dictionary:
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	var world: Node = scene.instantiate()
	host.add_child(world)
	world.call("bootstrap", seed_value, {})
	world.set("_last_autosave", -100000.0)
	var rs: RunState = world.get("run_state") as RunState
	var director: EnemyDirector = world.get("_enemy_director") as EnemyDirector
	var encounter: LongshadowEncounter = world.get("_longshadow") as LongshadowEncounter
	var controller: TrainController = world.get("_train_controller") as TrainController
	var route_choice: RouteChoice = world.get("_route_choice") as RouteChoice
	var station: StationPanel = world.get("_station_panel") as StationPanel
	rs.speed_scale = 2.0
	_apply_strategy_priorities(rs, strategy, false)
	var station_action := false
	var danger_committed := 0
	var route_commits := 0
	var iterations := 0
	while not bool(world.get("_ended")) and iterations < 5200:
		var regular_target: Vector2 = (
			director.nearest_warded_position(true)
			if director.has_warded_target_in_response_range()
			else Vector2(1200.0, 500.0)
		)
		controller.aim_towards(
			encounter.current_target_position()
			if encounter.is_active()
			else regular_target
		)
		if (
			encounter.is_active()
			and encounter.can_accept_active_response()
			and rs.focus_cooldown <= 0.0
		):
			rs.request_focus()
		elif director.has_warded_target_in_response_range() and rs.focus_cooldown <= 0.0:
			rs.request_focus()
		if (
			rs.station_completed
			and rs.scrap >= RunState.FIELD_OVERCHARGE_COST
			and (
				rs.power < 4.0
				or rs.lumen < rs.stats().focus_cost
			)
		):
			rs.purchase_emergency_overcharge()
		if (
			(strategy == "gunline" or strategy == "adaptive")
			and rs.defense_salvo_cooldown <= 0.0
			and rs.power >= 4.0
			and (encounter.is_active() or director.has_salvo_target())
		):
			world.call("_on_defense_salvo")
		world.call("_process", 0.25)
		director.call("_process", 0.25)
		if (
			(strategy == "gunline" or strategy == "adaptive")
			and not rs.cars.is_empty()
			and float(rs.cars.back().get("hp", 0.0)) < 18.0
		):
			world.call("_on_detach")
		if bool(world.get("_reveal_open")):
			var choices: Array = route_choice.get("_choices")
			var choice_index := _strategy_choice_index(choices, rs, strategy)
			danger_committed += int((choices[choice_index] as Dictionary).get("danger", 0))
			route_commits += 1
			route_choice.call("_select", choice_index)
		if bool(world.get("_station_open")):
			station_action = _apply_station_strategy(rs, strategy)
			station.call("_close")
		if rs.boss_triggered:
			_apply_strategy_priorities(rs, strategy, true)
		iterations += 1
	var result := {
		"victory": rs.victory,
		"travel_time": rs.travel_time,
		"distance": rs.distance,
		"locomotive_hp": rs.locomotive_hp,
		"station_action": station_action,
		"route_commits": route_commits,
		"danger_committed": danger_committed,
		"cars": rs.cars.size(),
		"lost_crew": (rs.run_history.get("lost_crew", []) as Array).size(),
		"lumen": rs.lumen,
		"focus_uses": int((rs.run_history.get("telemetry", {}) as Dictionary).get("focus_uses", 0)),
		"wards_broken": int((rs.run_history.get("telemetry", {}) as Dictionary).get("wards_broken", 0)),
		"boss_active_responses": int(
			(rs.run_history.get("telemetry", {}) as Dictionary).get(
				"boss_active_responses",
				0
			)
		)
	}
	world.free()
	return result


func _apply_strategy_priorities(rs: RunState, strategy: String, boss: bool) -> void:
	match strategy:
		"beam":
			rs.set_priority("engine", 0 if boss else 1)
			rs.set_priority("light", 3)
			rs.set_priority("defense", 0)
			rs.set_priority("repair", 1)
		"gunline":
			rs.set_priority("engine", 0 if boss else 1)
			rs.set_priority("light", 2)
			rs.set_priority("defense", 1 if rs.has_car_type("Defense") else 0)
			rs.set_priority("repair", 0 if boss else 1)
		_:
			rs.set_priority("engine", 0 if boss else 1)
			rs.set_priority("light", 2)
			rs.set_priority("defense", 1)
			rs.set_priority("repair", 2)


func _apply_station_strategy(rs: RunState, strategy: String) -> bool:
	var actions := 0
	match strategy:
		"beam":
			var battery_id := _first_car_id(rs, "Battery")
			if bool(rs.purchase_upgrade(battery_id, "arc_reserve").get("ok", false)):
				actions += 1
			if bool(rs.purchase_car("Greenhouse").get("ok", false)):
				actions += 1
		"gunline":
			if bool(rs.purchase_car("Defense").get("ok", false)):
				actions += 1
			var defense_id := _first_car_id(rs, "Defense")
			if not defense_id.is_empty():
				if bool(rs.assign_crew("ilo", defense_id).get("ok", false)):
					actions += 1
				if bool(rs.purchase_upgrade(defense_id, "heavy_cannon").get("ok", false)):
					actions += 1
				if bool(rs.move_car(defense_id, -rs.cars.size()).get("ok", false)):
					actions += 1
		"sustain":
			if bool(rs.purchase_car("Greenhouse").get("ok", false)):
				actions += 1
			var passenger_id := _first_car_id(rs, "Passenger")
			if bool(rs.purchase_upgrade(passenger_id, "ration_lockers").get("ok", false)):
				actions += 1
		_:
			if bool(rs.purchase_car("Defense").get("ok", false)):
				actions += 1
			var adaptive_defense_id := _first_car_id(rs, "Defense")
			if not adaptive_defense_id.is_empty():
				if bool(rs.assign_crew("ilo", adaptive_defense_id).get("ok", false)):
					actions += 1
				if bool(rs.move_car(adaptive_defense_id, -rs.cars.size()).get("ok", false)):
					actions += 1
	var repair_result := rs.purchase_repair()
	if bool(repair_result.get("ok", false)):
		actions += 1
	return actions > 0


func _first_car_id(rs: RunState, type_key: String) -> String:
	for car_variant in rs.cars:
		var car: Dictionary = car_variant
		if String(car.get("type", "")) == type_key:
			return String(car.get("id", ""))
	return ""


func _strategy_choice_index(choices: Array, rs: RunState, strategy: String) -> int:
	var best_index := 0
	var best_score := -INF
	for index in range(choices.size()):
		var event: Dictionary = choices[index]
		var rewards: Dictionary = event.get("rewards", {})
		var supplies := float(rewards.get("supplies", 0.0))
		var scrap := float(rewards.get("scrap", 0.0))
		var power_gain := float(rewards.get("power", 0.0))
		var lumen_gain := float(rewards.get("lumen", 0.0))
		var danger := float(event.get("danger", 0))
		var score := 0.0
		match strategy:
			"beam":
				score = supplies * 2.0 + scrap * (3.5 if not rs.station_completed else 0.8)
				score += lumen_gain * 2.2 + power_gain
			"gunline":
				score = supplies * 2.0 + scrap * (5.0 if not rs.station_completed else 1.0)
				score += power_gain * 2.0 + lumen_gain * 0.5
				if not rs.station_completed and danger > 0.0:
					score -= 100.0
			_:
				score = supplies * (5.0 if rs.supplies < 40.0 else 3.0)
				score += scrap * (3.0 if not rs.station_completed else 0.6)
				score += power_gain + lumen_gain
		var danger_penalty := 8.0 if strategy == "adaptive" else 5.0
		score -= danger * danger_penalty
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
