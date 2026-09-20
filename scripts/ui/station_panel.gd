class_name StationPanel
extends Control
## One-stop station refit screen. Every mutation goes through RunState transactions.

signal state_changed()
signal closed()

var _run_state: RunState
var _open: bool = false
var _message: String = "One stop. Make the consist count."
var _compact_layout: bool = false
var _content_width: float = 1010.0
var _undo_stack: Array[Dictionary] = []
var _departure_armed: bool = false


func present(run_state: RunState) -> void:
	_run_state = run_state
	_message = "One stop. Make the consist count."
	_undo_stack.clear()
	_departure_armed = false
	_build()
	visible = true
	_open = true
	AudioManager.play("reveal")


func _build() -> void:
	theme = UITheme.build()
	for child in get_children():
		child.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.68)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var viewport_size := get_viewport_rect().size
	_compact_layout = viewport_size.x < 1100.0 or viewport_size.y < 650.0
	var half_width := minf(530.0, viewport_size.x * 0.48)
	var half_height := minf(330.0, viewport_size.y * 0.46)
	_content_width = half_width * 2.0 - 24.0
	var frame := PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -half_width
	frame.offset_right = half_width
	frame.offset_top = -half_height
	frame.offset_bottom = half_height
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	frame.add_child(root)
	_build_header(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(_content_width, 0.0)
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_build_train_summary(body)
	_build_crew(body)
	_build_consist(body)
	_build_market(body)

	var leave_button := Button.new()
	leave_button.text = (
		"Confirm departure with power deficit"
		if _departure_armed
		else "Depart Waypost Five"
	)
	leave_button.custom_minimum_size = Vector2(0.0, 38.0)
	leave_button.pressed.connect(_close)
	root.add_child(leave_button)


func _build_header(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "WAYPOST FIVE - FINAL REFIT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	parent.add_child(title)

	var message := Label.new()
	message.text = _message
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	parent.add_child(message)


func _build_train_summary(parent: VBoxContainer) -> void:
	var projection: Dictionary = _run_state.station_projection()
	var summary := Label.new()
	summary.text = (
		"Scrap %d  |  Slots %d/%d  |  Power net %+.1f  |  Speed %.1f  |  Repair %.1f/s"
		% [
			int(_run_state.scrap),
			_run_state.cars.size(),
			_run_state.slot_capacity,
			float(projection.get("power_net", 0.0)),
			float(projection.get("speed", 0.0)),
			float(projection.get("repair_rate", 0.0))
		]
	)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_color_override(
		"font_color",
		Color(0.55, 0.9, 0.58)
		if float(projection.get("power_net", 0.0)) >= 0.0
		else Color(0.95, 0.48, 0.38)
	)
	parent.add_child(summary)

	var power_detail := Label.new()
	power_detail.text = _projection_status(projection)
	power_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_detail.add_theme_font_size_override("font_size", 12)
	power_detail.add_theme_color_override("font_color", Color(0.76, 0.78, 0.84))
	parent.add_child(power_detail)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	parent.add_child(actions)

	var repair_cost: int = _run_state.repair_quote()
	var repair_button := Button.new()
	repair_button.text = (
		"Train fully repaired"
		if repair_cost <= 0
		else "Full repair - %d scrap" % repair_cost
	)
	repair_button.disabled = repair_cost <= 0 or _run_state.scrap < repair_cost
	repair_button.pressed.connect(_try_repair)
	actions.add_child(repair_button)

	var slot_button := Button.new()
	slot_button.text = (
		"All 5 slots fitted"
		if _run_state.slot_capacity >= RunState.MAX_SLOT_CAPACITY
		else "Fit fifth slot - %d scrap" % RunState.SLOT_EXPANSION_COST
	)
	slot_button.disabled = (
		_run_state.slot_capacity >= RunState.MAX_SLOT_CAPACITY
		or _run_state.scrap < RunState.SLOT_EXPANSION_COST
	)
	slot_button.pressed.connect(_try_expand_slot)
	actions.add_child(slot_button)

	var undo_button := Button.new()
	undo_button.text = "Undo last change"
	undo_button.disabled = _undo_stack.is_empty()
	undo_button.pressed.connect(_undo_last)
	actions.add_child(undo_button)


func _build_consist(parent: VBoxContainer) -> void:
	_add_section_title(parent, "CONSIST - LOCOMOTIVE TO REAR")
	for index in range(_run_state.cars.size()):
		var car: Dictionary = _run_state.cars[index]
		var cfg: Dictionary = _run_state.cars_config.get(String(car.get("type", "")), {})
		var card := PanelContainer.new()
		parent.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)

		var order := Label.new()
		order.text = "%d" % (index + 1)
		order.custom_minimum_size = Vector2(24.0, 0.0)
		order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(order)

		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var title := Label.new()
		title.text = "%s  HP %d/%d" % [
			String(car.get("display", car.get("type", "Car"))),
			int(car.get("hp", 0)),
			int(car.get("max_hp", 0))
		]
		title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.58))
		details.add_child(title)
		var description := Label.new()
		description.text = "%s  |  Power %+.1f / -%.1f  |  Crew %d/%d  |  %s" % [
			String(cfg.get("description", "")),
			float(cfg.get("power_production", 0.0)),
			float(cfg.get("power_draw", 0.0)),
			_run_state.active_crew_for_car(String(car.get("id", ""))).size(),
			_run_state.crew_slots_for_car(car),
			_run_state.car_power_state(car).to_upper()
		]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 12)
		description.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
		details.add_child(description)

		var move_left := Button.new()
		move_left.text = "<"
		move_left.tooltip_text = "Move toward locomotive"
		move_left.disabled = index == 0
		var left_id := String(car.get("id", ""))
		move_left.pressed.connect(func() -> void: _try_move(left_id, -1))
		row.add_child(move_left)

		var move_right := Button.new()
		move_right.text = ">"
		move_right.tooltip_text = "Move toward rear"
		move_right.disabled = index == _run_state.cars.size() - 1
		var right_id := String(car.get("id", ""))
		move_right.pressed.connect(func() -> void: _try_move(right_id, 1))
		row.add_child(move_right)

		_build_upgrade_controls(row, car, cfg)


func _build_upgrade_controls(parent: HBoxContainer, car: Dictionary, cfg: Dictionary) -> void:
	var installed_key := String(car.get("upgrade", ""))
	var upgrades: Dictionary = cfg.get("upgrades", {})
	if not installed_key.is_empty():
		var installed := Label.new()
		installed.text = "REFIT: %s" % String(upgrades.get(installed_key, {}).get("display", installed_key))
		installed.custom_minimum_size = Vector2(170.0, 0.0)
		installed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		installed.add_theme_color_override("font_color", Color(0.55, 0.9, 0.58))
		parent.add_child(installed)
		return
	var choices := VBoxContainer.new()
	choices.custom_minimum_size = Vector2(240.0, 0.0)
	parent.add_child(choices)
	for upgrade_key_variant in upgrades.keys():
		var upgrade_key := String(upgrade_key_variant)
		var upgrade: Dictionary = upgrades[upgrade_key]
		var cost := int(upgrade.get("cost", 0))
		var button := Button.new()
		button.text = "%s - %d" % [String(upgrade.get("display", upgrade_key)), cost]
		button.disabled = _run_state.scrap < cost
		var car_id := String(car.get("id", ""))
		button.pressed.connect(func() -> void: _try_upgrade(car_id, upgrade_key))
		choices.add_child(button)
		var description := Label.new()
		description.text = "%s\n%s" % [
			String(upgrade.get("description", "Permanent refit")),
			_projection_delta(_run_state.preview_upgrade(car_id, upgrade_key))
		]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 11)
		description.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
		choices.add_child(description)


func _build_market(parent: VBoxContainer) -> void:
	_add_section_title(parent, "COUPLE A CAR")
	var grid := GridContainer.new()
	grid.columns = 2 if _compact_layout else 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	var keys: Array = _run_state.cars_config.keys()
	keys.sort()
	for key_variant in keys:
		var type_key := String(key_variant)
		var cfg: Dictionary = _run_state.cars_config[type_key]
		var cost := _run_state.car_purchase_cost(type_key)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(
			(_content_width - 20.0) / float(grid.columns),
			112.0
		)
		grid.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 3)
		card.add_child(content)
		var button := Button.new()
		button.text = "%s - %d scrap" % [String(cfg.get("display", type_key)), cost]
		button.custom_minimum_size = Vector2(0.0, 34.0)
		button.disabled = _run_state.cars.size() >= _run_state.slot_capacity or _run_state.scrap < cost
		button.pressed.connect(func() -> void: _try_add(type_key))
		content.add_child(button)
		var description := Label.new()
		description.text = "%s\n%s" % [
			String(cfg.get("description", "")),
			_projection_delta(_run_state.preview_car_purchase(type_key))
		]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 11)
		description.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
		content.add_child(description)


func _build_crew(parent: VBoxContainer) -> void:
	_add_section_title(parent, "CREW POSTS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for member_variant in _run_state.crew:
		var member: Dictionary = member_variant
		var label := Label.new()
		label.text = "%s - %s" % [
			String(member.get("name", "Crew")),
			String(member.get("trait", member.get("role", "")))
		]
		label.custom_minimum_size = Vector2(_content_width * 0.57, 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override(
			"font_color",
			Color(0.5, 0.5, 0.55)
			if String(member.get("status", "fit")) != "fit"
			else Color(0.82, 0.82, 0.86)
		)
		grid.add_child(label)

		var selector := OptionButton.new()
		selector.custom_minimum_size = Vector2(_content_width * 0.38, 32.0)
		selector.add_item("Unassigned")
		selector.set_item_metadata(0, "")
		var selected_index := 0
		for car_variant in _run_state.cars:
			var car: Dictionary = car_variant
			var compatible: Array = member.get("compatible_cars", [])
			if not compatible.is_empty() and not compatible.has(String(car.get("type", ""))):
				continue
			var car_id := String(car.get("id", ""))
			var occupants := _run_state.active_crew_for_car(car_id).size()
			var slots := _run_state.crew_slots_for_car(car)
			selector.add_item("%s (%d/%d)" % [
				String(car.get("display", car.get("type", "Car"))),
				occupants,
				slots
			])
			var item_index := selector.item_count - 1
			selector.set_item_metadata(item_index, car_id)
			if String(member.get("assigned_car_id", "")) == car_id:
				selected_index = item_index
		selector.select(selected_index)
		selector.disabled = String(member.get("status", "fit")) != "fit"
		var crew_id := String(member.get("id", ""))
		selector.item_selected.connect(func(index: int) -> void:
			_try_assign_crew(crew_id, String(selector.get_item_metadata(index)))
		)
		grid.add_child(selector)


func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.72, 0.42))
	parent.add_child(title)


func _apply_transaction(result: Dictionary, before: Dictionary) -> void:
	_message = String(result.get("message", "No change."))
	if bool(result.get("ok", false)):
		_undo_stack.append(before)
		_departure_armed = false
		AudioManager.play("click")
		emit_signal("state_changed")
	else:
		AudioManager.play("alarm")
	_build()


func _try_add(type_key: String) -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.purchase_car(type_key), before)


func _try_repair() -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.purchase_repair(), before)


func _try_expand_slot() -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.purchase_slot(), before)


func _try_upgrade(car_id: String, upgrade_key: String) -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.purchase_upgrade(car_id, upgrade_key), before)


func _try_move(car_id: String, offset: int) -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.move_car(car_id, offset), before)


func _try_reorder() -> void:
	if _run_state.cars.size() < 2:
		return
	var rear_id := String(_run_state.cars.back().get("id", ""))
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(
		_run_state.move_car(rear_id, -(_run_state.cars.size() - 1)),
		before
	)


func _try_assign_crew(crew_id: String, car_id: String) -> void:
	var before: Dictionary = _run_state.to_dict()
	_apply_transaction(_run_state.assign_crew(crew_id, car_id), before)


func _undo_last() -> void:
	if _undo_stack.is_empty():
		return
	var snapshot: Dictionary = _undo_stack.pop_back()
	_run_state.apply_dict(snapshot)
	_run_state.emit_signal("resources_changed")
	_run_state.emit_signal("power_changed")
	_run_state.emit_signal("crew_changed")
	_message = "Last station change undone."
	_departure_armed = false
	AudioManager.play("click")
	emit_signal("state_changed")
	_build()


func _close() -> void:
	if not _open:
		return
	var projection: Dictionary = _run_state.station_projection()
	if float(projection.get("power_net", 0.0)) < 0.0 and not _departure_armed:
		_departure_armed = true
		_message = (
			"WARNING: reserves drain in %s. Brownout will shed %s. "
			+ "Review, undo, or confirm departure."
		) % [
			_format_duration(float(projection.get("endurance_seconds", 0.0))),
			_join_or_none(projection.get("brownout_systems", []))
		]
		AudioManager.play("alarm")
		_build()
		return
	_open = false
	visible = false
	AudioManager.play("click")
	emit_signal("closed")


func _projection_delta(projection: Dictionary) -> String:
	if projection.is_empty():
		return "No valid projection."
	var current: Dictionary = _run_state.station_projection()
	var net: float = float(projection.get("power_net", 0.0))
	var speed_delta: float = (
		float(projection.get("speed", 0.0))
		- float(current.get("speed", 0.0))
	)
	var text := "After: net %+.1f | speed %+.1f" % [net, speed_delta]
	var assumption: String = String(projection.get("assumption", ""))
	if not assumption.is_empty():
		text += " (%s)" % assumption
	if net < 0.0:
		text += " | reserve %s | sheds %s" % [
			_format_duration(float(projection.get("endurance_seconds", 0.0))),
			_join_or_none(projection.get("brownout_systems", []))
		]
	return text


func _projection_status(projection: Dictionary) -> String:
	var net: float = float(projection.get("power_net", 0.0))
	if net >= 0.0:
		return "Power stable at full demand. Brownout load shedding is not expected."
	return "Reserve lasts about %s at full demand. Brownout priority: %s." % [
		_format_duration(float(projection.get("endurance_seconds", 0.0))),
		_join_or_none(projection.get("brownout_systems", []))
	]


func _format_duration(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


func _join_or_none(values: Array) -> String:
	if values.is_empty():
		return "no optional systems"
	return ", ".join(PackedStringArray(values))
