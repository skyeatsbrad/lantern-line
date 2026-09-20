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


func present(run_state: RunState) -> void:
	_run_state = run_state
	_message = "One stop. Make the consist count."
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
	_build_consist(body)
	_build_market(body)
	_build_crew(body)

	var leave_button := Button.new()
	leave_button.text = "Depart Waypost Five"
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
	var stats: TrainStats = _run_state.stats()
	var summary := Label.new()
	summary.text = (
		"Scrap %d  |  Slots %d/%d  |  Power net %+.1f  |  Speed %.1f  |  Repair %.1f/s"
		% [
			int(_run_state.scrap),
			_run_state.cars.size(),
			_run_state.slot_capacity,
			stats.power_net,
			stats.speed,
			stats.repair_rate
		]
	)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_color_override(
		"font_color",
		Color(0.55, 0.9, 0.58) if stats.power_net >= 0.0 else Color(0.95, 0.48, 0.38)
	)
	parent.add_child(summary)

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
		description.text = "%s  |  Power %+.1f / -%.1f  |  Crew %d/%d" % [
			String(cfg.get("description", "")),
			float(cfg.get("power_production", 0.0)),
			float(cfg.get("power_draw", 0.0)),
			_run_state.active_crew_for_car(String(car.get("id", ""))).size(),
			_run_state.crew_slots_for_car(car)
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
	choices.custom_minimum_size = Vector2(210.0, 0.0)
	parent.add_child(choices)
	for upgrade_key_variant in upgrades.keys():
		var upgrade_key := String(upgrade_key_variant)
		var upgrade: Dictionary = upgrades[upgrade_key]
		var cost := int(upgrade.get("cost", 0))
		var button := Button.new()
		button.text = "%s - %d" % [String(upgrade.get("display", upgrade_key)), cost]
		button.tooltip_text = String(upgrade.get("description", "Permanent refit"))
		button.disabled = _run_state.scrap < cost
		var car_id := String(car.get("id", ""))
		button.pressed.connect(func() -> void: _try_upgrade(car_id, upgrade_key))
		choices.add_child(button)


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
		var button := Button.new()
		button.text = "%s - %d scrap" % [String(cfg.get("display", type_key)), cost]
		button.tooltip_text = String(cfg.get("description", ""))
		button.custom_minimum_size = Vector2(
			(_content_width - 20.0) / float(grid.columns),
			36.0
		)
		button.disabled = _run_state.cars.size() >= _run_state.slot_capacity or _run_state.scrap < cost
		button.pressed.connect(func() -> void: _try_add(type_key))
		grid.add_child(button)


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


func _apply_transaction(result: Dictionary) -> void:
	_message = String(result.get("message", "No change."))
	if bool(result.get("ok", false)):
		AudioManager.play("click")
		emit_signal("state_changed")
	else:
		AudioManager.play("alarm")
	_build()


func _try_add(type_key: String) -> void:
	_apply_transaction(_run_state.purchase_car(type_key))


func _try_repair() -> void:
	_apply_transaction(_run_state.purchase_repair())


func _try_expand_slot() -> void:
	_apply_transaction(_run_state.purchase_slot())


func _try_upgrade(car_id: String, upgrade_key: String) -> void:
	_apply_transaction(_run_state.purchase_upgrade(car_id, upgrade_key))


func _try_move(car_id: String, offset: int) -> void:
	_apply_transaction(_run_state.move_car(car_id, offset))


func _try_reorder() -> void:
	if _run_state.cars.size() < 2:
		return
	var rear_id := String(_run_state.cars.back().get("id", ""))
	_apply_transaction(_run_state.move_car(rear_id, -(_run_state.cars.size() - 1)))


func _try_assign_crew(crew_id: String, car_id: String) -> void:
	_apply_transaction(_run_state.assign_crew(crew_id, car_id))


func _close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	AudioManager.play("click")
	emit_signal("closed")
