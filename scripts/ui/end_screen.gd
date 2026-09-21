class_name EndScreen
extends Control
## EndScreen
##
## Victory/defeat overlay. Returns via signal 'closed'.

signal closed()

var _victory: bool = false


func show_end(victory: bool, run_state: RunState) -> void:
	theme = UITheme.build()
	_victory = victory
	for c in get_children():
		c.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = true

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var v: VBoxContainer = VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -280
	v.offset_right = 280
	v.offset_top = -240
	v.offset_bottom = 240
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)

	var title: Label = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	if victory:
		title.text = "DAWN BEACON REACHED"
		title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	else:
		title.text = "THE LINE ENDS HERE"
		title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	v.add_child(title)

	var body: Label = Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 100)
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	if victory:
		body.text = "The pale sky opens. Warm light finds the rails. The surviving cars roll into the beacon and stop, breathing steam like grateful animals."
	else:
		body.text = "The lantern falters. The train drifts. In the dark, the quiet is complete. Somebody remembers your distance mark and lifts a lantern for the next crew."
	v.add_child(body)

	var stat: Label = Label.new()
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.text = "Distance: %d m   |   Time: %02d:%02d   |   Seed: %d" % [
		int(run_state.distance),
		int(run_state.travel_time) / 60,
		int(run_state.travel_time) % 60,
		run_state.run_seed
	]
	stat.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	v.add_child(stat)

	var ledger := Label.new()
	ledger.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ledger.custom_minimum_size = Vector2(540, 150)
	ledger.text = _build_ledger(run_state)
	ledger.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68))
	v.add_child(ledger)

	var btn: Button = Button.new()
	btn.text = "  Return to Title  "
	btn.custom_minimum_size = Vector2(220, 40)
	btn.pressed.connect(func() -> void:
		AudioManager.play("click")
		emit_signal("closed"))
	v.add_child(btn)

	if victory:
		AudioManager.play("victory")
	else:
		AudioManager.play("defeat")


func _build_ledger(run_state: RunState) -> String:
	var fit_names: Array[String] = []
	var lost_names: Array[String] = []
	for member_variant in run_state.crew:
		var member: Dictionary = member_variant
		if String(member.get("status", "fit")) == "fit":
			fit_names.append(String(member.get("name", "Crew")))
		else:
			lost_names.append(String(member.get("name", "Crew")))
	var car_names: Array[String] = []
	var intact_count: int = 0
	for car_variant in run_state.cars:
		var car: Dictionary = car_variant
		var name := String(car.get("display", car.get("type", "Car")))
		if float(car.get("hp", 0.0)) > 0.0:
			intact_count += 1
		else:
			name += " [destroyed]"
		var upgrade_key := String(car.get("upgrade", ""))
		if not upgrade_key.is_empty():
			var cfg: Dictionary = run_state.cars_config.get(String(car.get("type", "")), {})
			name += " [%s]" % String(
				(cfg.get("upgrades", {}) as Dictionary).get(upgrade_key, {}).get(
					"display",
					upgrade_key
				)
			)
		car_names.append(name)
	var detached_count := (run_state.run_history.get("detached_cars", []) as Array).size()
	var upgrade_count := (run_state.run_history.get("upgrades", []) as Array).size()
	var purchased_count := (run_state.run_history.get("purchased_cars", []) as Array).size()
	var field_action_count := (run_state.run_history.get("field_actions", []) as Array).size()
	var telemetry: Dictionary = run_state.run_history.get("telemetry", {})
	var lines: Array[String] = [
		"DAWN LEDGER",
		"Routes committed: %d  |  Cars intact: %d/%d"
		% [run_state.route_history.size(), intact_count, run_state.slot_capacity],
		"Cars added: %d  |  Upgrades installed: %d  |  Field actions: %d"
		% [purchased_count, upgrade_count, field_action_count],
		"Lowest power: %.1f  |  Brownout: %.1fs  |  Scrap banked: %d"
		% [
			float(telemetry.get("min_power", run_state.power)),
			float(telemetry.get("brownout_time", 0.0)),
			int(run_state.scrap)
		],
		"Focus: %d  |  Salvos: %d  |  Wards broken: %d  |  Boss responses: %d"
		% [
			int(telemetry.get("focus_uses", 0)),
			int(telemetry.get("defense_salvos", 0)),
			int(telemetry.get("wards_broken", 0)),
			int(telemetry.get("boss_active_responses", 0))
		],
		"Consist: %s" % (" > ".join(car_names) if not car_names.is_empty() else "Locomotive only"),
		"Crew through: %s" % (", ".join(fit_names) if not fit_names.is_empty() else "None"),
		"Cars deliberately cut loose: %d" % detached_count
	]
	if not lost_names.is_empty():
		lines.append("Remembered in the dark: %s" % ", ".join(lost_names))
	elif _victory:
		lines.append("No crew were left behind.")
	return "\n".join(lines)
