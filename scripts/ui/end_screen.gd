class_name EndScreen
extends Control
## Responsive victory/defeat ledger. Returns via signal 'closed'.

signal closed()

var _victory: bool = false
var _run_state: RunState
var _backdrop: ColorRect
var _frame: PanelContainer
var _return_button: Button
var _closing: bool = false


func show_end(victory: bool, run_state: RunState) -> void:
	_victory = victory
	_run_state = run_state
	_closing = false
	_build(true)


func rebuild() -> void:
	if _run_state == null:
		return
	_build(false)


func _build(play_audio: bool) -> void:
	theme = UITheme.build()
	for child in get_children():
		child.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = true

	_backdrop = ColorRect.new()
	_backdrop.color = PresentationPalette.with_alpha(
		&"night_void",
		0.9 if UITheme.high_contrast() else 0.78,
		UITheme.high_contrast()
	)
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var viewport_size := get_viewport_rect().size
	var touch_layout := UITheme.touch_layout(viewport_size)
	var compact: bool = UITheme.compact_layout(viewport_size)
	var comfort := UITheme.comfort_insets(viewport_size)
	var frame_width := (
		viewport_size.x - comfort.x - comfort.z
		if touch_layout
		else minf(720.0, viewport_size.x - 28.0)
	)
	var frame_height := (
		viewport_size.y - comfort.y - comfort.w
		if touch_layout
		else minf(670.0, viewport_size.y - 28.0)
	)
	_frame = PanelContainer.new()
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -frame_width * 0.5
	_frame.offset_right = frame_width * 0.5
	_frame.offset_top = -frame_height * 0.5
	_frame.offset_bottom = frame_height * 0.5
	add_child(_frame)

	var frame_root := VBoxContainer.new()
	frame_root.add_theme_constant_override("separation", 10)
	_frame.add_child(frame_root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_root.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(frame_width - 36.0, 0.0)
	content.add_theme_constant_override("separation", 12)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(content)

	var eyebrow := Label.new()
	eyebrow.text = "RUN COMPLETE" if _victory else "RUN ENDED"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", UITheme.font_size(11))
	eyebrow.add_theme_color_override("font_color", UITheme.muted_text_color())
	content.add_child(eyebrow)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(32 if compact else 40)
	)
	if _victory:
		title.text = "DAWN BEACON REACHED"
		title.add_theme_color_override("font_color", UITheme.accent_color())
	else:
		title.text = "THE LINE ENDS HERE"
		title.add_theme_color_override("font_color", UITheme.danger_color())
	content.add_child(title)

	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(frame_width - 58.0, 72.0)
	body.add_theme_font_size_override("font_size", UITheme.font_size(14))
	body.add_theme_color_override(
		"font_color",
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	body.text = (
		"The pale sky opens. Warm light finds the rails. The surviving cars "
		+ "roll into the beacon and stop, breathing steam like grateful animals."
		if _victory
		else (
			"The lantern falters. The train drifts. Somebody marks the final "
			+ "distance and lifts a light for the next crew."
		)
	)
	content.add_child(body)

	var metrics := GridContainer.new()
	metrics.columns = 1 if viewport_size.x < 700.0 else 3
	metrics.add_theme_constant_override("h_separation", 8)
	metrics.add_theme_constant_override("v_separation", 8)
	content.add_child(metrics)
	_add_metric(metrics, "DISTANCE", "%d m" % int(_run_state.distance))
	_add_metric(
		metrics,
		"TIME",
		"%02d:%02d" % [
			int(_run_state.travel_time) / 60,
			int(_run_state.travel_time) % 60
		]
	)
	_add_metric(metrics, "SEED", str(_run_state.run_seed))

	var ledger_title := Label.new()
	ledger_title.text = "DAWN LEDGER" if _victory else "LAST LIGHT LEDGER"
	ledger_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ledger_title.add_theme_font_override("font", UITheme.display_font())
	ledger_title.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(22)
	)
	ledger_title.add_theme_color_override("font_color", UITheme.accent_color())
	content.add_child(ledger_title)

	for section_variant in _ledger_sections():
		var section: Dictionary = section_variant
		_add_ledger_section(
			content,
			String(section.get("title", "")),
			String(section.get("body", ""))
		)

	_return_button = Button.new()
	_return_button.text = "Return to Title"
	_return_button.custom_minimum_size = Vector2(
		240.0,
		UITheme.touch_target_size(viewport_size).y
		if touch_layout
		else 44.0
	)
	_return_button.pressed.connect(_close)
	frame_root.add_child(_return_button)
	_return_button.call_deferred("grab_focus")

	UITheme.animate_panel_in(_frame, _backdrop)
	if play_audio:
		AudioManager.play("victory" if _victory else "defeat")


func _add_metric(parent: GridContainer, heading: String, value: String) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(190.0, 58.0)
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(stack)
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_label.add_theme_font_size_override("font_size", UITheme.font_size(10))
	heading_label.add_theme_color_override(
		"font_color",
		UITheme.muted_text_color()
	)
	stack.add_child(heading_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", UITheme.font_size(17))
	value_label.add_theme_color_override("font_color", UITheme.accent_color())
	stack.add_child(value_label)


func _add_ledger_section(
	parent: VBoxContainer,
	heading: String,
	body: String
) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	card.add_child(stack)
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_font_size_override("font_size", UITheme.font_size(14))
	heading_label.add_theme_color_override("font_color", UITheme.accent_color())
	stack.add_child(heading_label)
	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", UITheme.font_size(13))
	body_label.add_theme_color_override(
		"font_color",
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	stack.add_child(body_label)


func _ledger_sections() -> Array[Dictionary]:
	var fit_names: Array[String] = []
	var lost_names: Array[String] = []
	for member_variant in _run_state.crew:
		var member: Dictionary = member_variant
		if String(member.get("status", "fit")) == "fit":
			fit_names.append(String(member.get("name", "Crew")))
		else:
			lost_names.append(String(member.get("name", "Crew")))

	var car_names: Array[String] = []
	var intact_count: int = 0
	for car_variant in _run_state.cars:
		var car: Dictionary = car_variant
		var car_name := String(car.get("display", car.get("type", "Car")))
		if float(car.get("hp", 0.0)) > 0.0:
			intact_count += 1
		else:
			car_name += " [destroyed]"
		var upgrade_key := String(car.get("upgrade", ""))
		if not upgrade_key.is_empty():
			var config: Dictionary = _run_state.cars_config.get(
				String(car.get("type", "")),
				{}
			)
			car_name += " [%s]" % String(
				(config.get("upgrades", {}) as Dictionary).get(
					upgrade_key,
					{}
				).get("display", upgrade_key)
			)
		car_names.append(car_name)

	var history: Dictionary = _run_state.run_history
	var telemetry: Dictionary = history.get("telemetry", {})
	var detached_count: int = (
		history.get("detached_cars", []) as Array
	).size()
	var upgrade_count: int = (history.get("upgrades", []) as Array).size()
	var purchased_count: int = (
		history.get("purchased_cars", []) as Array
	).size()
	var field_action_count: int = (
		history.get("field_actions", []) as Array
	).size()
	var crew_line: String = (
		"Through the dark: %s" % ", ".join(fit_names)
		if not fit_names.is_empty()
		else "Through the dark: none"
	)
	if not lost_names.is_empty():
		crew_line += "\nRemembered: %s" % ", ".join(lost_names)
	elif _victory:
		crew_line += "\nNo crew were left behind."

	return [
		{
			"title": "JOURNEY",
			"body": (
				"Routes committed: %d  |  Cars intact: %d/%d\n"
				+ "Cars added: %d  |  Refits: %d  |  Field actions: %d"
			) % [
				_run_state.route_history.size(),
				intact_count,
				_run_state.slot_capacity,
				purchased_count,
				upgrade_count,
				field_action_count
			]
		},
		{
			"title": "POWER AND COMBAT",
			"body": (
				"Lowest power: %.1f  |  Brownout: %.1fs  |  Scrap banked: %d\n"
				+ "Focus: %d  |  Salvos: %d  |  Wards: %d  |  Boss responses: %d"
			) % [
				float(telemetry.get("min_power", _run_state.power)),
				float(telemetry.get("brownout_time", 0.0)),
				int(_run_state.scrap),
				int(telemetry.get("focus_uses", 0)),
				int(telemetry.get("defense_salvos", 0)),
				int(telemetry.get("wards_broken", 0)),
				int(telemetry.get("boss_active_responses", 0))
			]
		},
		{
			"title": "CONSIST",
			"body": (
				" > ".join(car_names)
				if not car_names.is_empty()
				else "Locomotive only"
			)
		},
		{
			"title": "CREW",
			"body": "%s\nCars deliberately cut loose: %d" % [
				crew_line,
				detached_count
			]
		}
	]


func _close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play("click")
	var tween: Tween = UITheme.animate_panel_out(_frame, _backdrop)
	await tween.finished
	visible = false
	emit_signal("closed")
