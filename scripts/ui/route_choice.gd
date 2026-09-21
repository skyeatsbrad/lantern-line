class_name RouteChoice
extends Control
## Compact route readout paired with the world-space RouteProjection.

signal chosen(event: Dictionary)
signal closed()
signal reroll_requested()

var _choices: Array = []
var _lens_key: String = "Standard"
var _lens_data: Dictionary = {}
var _selected_index: int = 1
var _active: bool = false
var _band_buttons: Array = []
var _position_label: Label
var _title_label: Label
var _description_label: Label
var _outcome_label: Label
var _commit_button: Button
var _reroll_button: Button
var _compact_layout: bool = false
var _reroll_allowed: bool = false
var _reroll_cost: int = 0
var _scrap_available: int = 0
var _input_guard_time: float = 0.0
var _input_blocker: Control


func present(
	choices: Array,
	lens_key: String,
	initial_band: String = "middle",
	lens_data: Dictionary = {},
	reroll_allowed: bool = false,
	reroll_cost: int = 0,
	scrap_available: int = 0
) -> void:
	_choices = choices
	_lens_key = lens_key
	_lens_data = lens_data
	_reroll_allowed = reroll_allowed
	_reroll_cost = reroll_cost
	_scrap_available = scrap_available
	_selected_index = _band_to_index(initial_band)
	_input_guard_time = 0.22
	_build()
	_active = true
	visible = true
	set_process(true)
	set_process_input(true)
	AudioManager.play("reveal")


func _build() -> void:
	theme = UITheme.build()
	for child in get_children():
		child.queue_free()
	_band_buttons.clear()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	var viewport_size: Vector2 = get_viewport_rect().size
	_compact_layout = viewport_size.x < 1100.0 or viewport_size.y < 620.0

	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -350.0 if _compact_layout else -410.0
	frame.offset_right = -12.0 if _compact_layout else -24.0
	frame.offset_top = -152.0 if _compact_layout else -170.0
	frame.offset_bottom = 152.0 if _compact_layout else 170.0
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6 if _compact_layout else 10)
	frame.add_child(root)

	var heading := Label.new()
	heading.text = "ROUTE PROJECTION - %s LENS" % _lens_key.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 17 if _compact_layout else 19)
	heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	root.add_child(heading)

	var instruction := Label.new()
	instruction.text = (
		"Aim vertically, inspect the forecast, then commit."
		if _compact_layout
		else "%s\nAim vertically across the junction, then commit the lit rail." % String(
			_lens_data.get(
				"description",
				"The selected lens changes which signatures are easiest to find."
			)
		)
	)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 12)
	instruction.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	root.add_child(instruction)

	var bands := HBoxContainer.new()
	bands.alignment = BoxContainer.ALIGNMENT_CENTER
	bands.add_theme_constant_override("separation", 6)
	root.add_child(bands)
	for index in range(_choices.size()):
		var event: Dictionary = _choices[index]
		var button := Button.new()
		button.text = String(event.get("position", "middle")).to_upper()
		button.custom_minimum_size = Vector2(92.0 if _compact_layout else 110.0, 34.0)
		var selected := index
		button.pressed.connect(func() -> void: set_selected_index(selected))
		bands.add_child(button)
		_band_buttons.append(button)

	_position_label = Label.new()
	_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position_label.add_theme_font_size_override("font_size", 13)
	root.add_child(_position_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18 if _compact_layout else 21)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	root.add_child(_title_label)

	_description_label = Label.new()
	_description_label.custom_minimum_size = Vector2(
		300.0 if _compact_layout else 350.0,
		58.0 if _compact_layout else 76.0
	)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description_label.add_theme_color_override("font_color", Color(0.84, 0.84, 0.88))
	root.add_child(_description_label)

	_outcome_label = Label.new()
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_outcome_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root.add_child(action_row)
	_reroll_button = Button.new()
	_reroll_button.custom_minimum_size = Vector2(118.0, 42.0)
	_reroll_button.pressed.connect(func() -> void: emit_signal("reroll_requested"))
	action_row.add_child(_reroll_button)
	_commit_button = Button.new()
	_commit_button.text = "Commit illuminated route"
	_commit_button.custom_minimum_size = Vector2(0.0, 42.0)
	_commit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commit_button.pressed.connect(func() -> void: _select(_selected_index))
	action_row.add_child(_commit_button)
	set_reroll_state(_reroll_allowed, _reroll_cost, _scrap_available)
	_add_input_blocker()
	_refresh_selection()


func _add_input_blocker() -> void:
	_input_blocker = ColorRect.new()
	(_input_blocker as ColorRect).color = Color(0.0, 0.0, 0.0, 0.0)
	_input_blocker.anchor_right = 1.0
	_input_blocker.anchor_bottom = 1.0
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_input_blocker)


func _process(delta: float) -> void:
	if _input_guard_time <= 0.0:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_input_guard_time = maxf(0.0, _input_guard_time - delta)
	if _input_guard_time <= 0.0 and is_instance_valid(_input_blocker):
		_input_blocker.queue_free()


func replace_choices(choices: Array, selected_index: int = 1) -> void:
	_choices = choices
	_selected_index = clampi(selected_index, 0, maxi(0, _choices.size() - 1))
	_refresh_selection()


func set_reroll_state(allowed: bool, cost: int, scrap_available: int) -> void:
	_reroll_allowed = allowed
	_reroll_cost = cost
	_scrap_available = scrap_available
	if _reroll_button == null:
		return
	_reroll_button.text = "Reroll -%d" % cost
	_reroll_button.tooltip_text = "Spend scrap to project three different route signatures."
	_reroll_button.disabled = not allowed or scrap_available < cost


func set_selected_index(index: int) -> void:
	var next_index := clampi(index, 0, maxi(0, _choices.size() - 1))
	if next_index == _selected_index and _title_label != null:
		return
	_selected_index = next_index
	_refresh_selection()


func set_aim_band(band: String) -> void:
	set_selected_index(_band_to_index(band))


func _refresh_selection() -> void:
	if _choices.is_empty() or _title_label == null:
		return
	var event: Dictionary = _choices[_selected_index]
	for index in range(_band_buttons.size()):
		var button: Button = _band_buttons[index]
		button.text = (
			"> %s" % String(_choices[index].get("position", "middle")).to_upper()
			if index == _selected_index
			else String(_choices[index].get("position", "middle")).to_upper()
		)
	_position_label.text = "%s SIGNATURE" % String(event.get("category", "unknown")).to_upper()
	_position_label.add_theme_color_override(
		"font_color",
		_category_color(String(event.get("category", "living")))
	)
	_title_label.text = String(event.get("title", "Unknown route"))
	_description_label.text = String(event.get("description", ""))
	_outcome_label.text = _format_outcome(event)
	_outcome_label.add_theme_color_override(
		"font_color",
		Color(0.95, 0.55, 0.42)
		if int(event.get("danger", 0)) >= 2
		else Color(0.62, 0.9, 0.62)
	)


func _format_outcome(event: Dictionary) -> String:
	var summary := String(event.get("summary", ""))
	var parts: Array[String] = []
	if not summary.is_empty():
		parts.append(summary)
	else:
		var rewards: Dictionary = event.get("rewards", {})
		for key_variant in rewards.keys():
			var key := String(key_variant)
			var amount := float(rewards[key])
			parts.append(
				"%s %s%s"
				% [key.capitalize(), "+" if amount >= 0.0 else "", str(amount)]
			)
	var danger := int(event.get("danger", 0))
	var pressure: String = (
		"quiet recovery"
		if danger <= 0
		else "%d immediate threat wave%s" % [danger, "" if danger == 1 else "s"]
	)
	var trail: String = ""
	if not (event.get("requires_flags", []) as Array).is_empty():
		trail = "story follow-up"
	elif _starts_story_trail(event):
		trail = "opens a future route"
	parts.append(
		"Forecast: %s%s"
		% [pressure, " | %s" % trail if not trail.is_empty() else ""]
	)
	return "\n".join(parts)


func _starts_story_trail(event: Dictionary) -> bool:
	for effect_variant in event.get("effects", []):
		var effect: Dictionary = effect_variant
		if String(effect.get("op", "")) == "set_flag":
			return true
	return false


func _category_color(category: String) -> Color:
	match category:
		"living":
			return Color(0.55, 0.85, 0.5)
		"machinery":
			return Color(0.7, 0.85, 1.0)
		"danger":
			return Color(0.9, 0.4, 0.35)
		_:
			return Color(0.9, 0.9, 0.9)


func _select(index: int) -> void:
	if not _active or index < 0 or index >= _choices.size():
		return
	_active = false
	visible = false
	AudioManager.play("click")
	emit_signal("chosen", _choices[index])
	emit_signal("closed")


func _band_to_index(band: String) -> int:
	match band:
		"upper":
			return 0
		"lower":
			return 2
		_:
			return 1


func _input(event: InputEvent) -> void:
	if not _active or _input_guard_time > 0.0:
		return
	if event.is_action_pressed("choose_upper"):
		set_selected_index(0)
		_select(0)
	elif event.is_action_pressed("choose_middle"):
		set_selected_index(1)
		_select(1)
	elif event.is_action_pressed("choose_lower"):
		set_selected_index(2)
		_select(2)
	elif event.is_action_pressed("ui_accept"):
		_select(_selected_index)
