class_name RouteChoice
extends Control
## Compact route readout paired with the world-space RouteProjection.

signal chosen(event: Dictionary)
signal closed()

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


func present(
	choices: Array,
	lens_key: String,
	initial_band: String = "middle",
	lens_data: Dictionary = {}
) -> void:
	_choices = choices
	_lens_key = lens_key
	_lens_data = lens_data
	_selected_index = _band_to_index(initial_band)
	_build()
	_active = true
	visible = true
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

	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -410.0
	frame.offset_right = -24.0
	frame.offset_top = -170.0
	frame.offset_bottom = 170.0
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	frame.add_child(root)

	var heading := Label.new()
	heading.text = "ROUTE PROJECTION - %s LENS" % _lens_key.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	root.add_child(heading)

	var instruction := Label.new()
	instruction.text = "%s\nAim vertically across the junction, then commit the lit rail." % String(
		_lens_data.get("description", "The selected lens changes which signatures are easiest to find.")
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
		button.custom_minimum_size = Vector2(110.0, 32.0)
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
	_title_label.add_theme_font_size_override("font_size", 21)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	root.add_child(_title_label)

	_description_label = Label.new()
	_description_label.custom_minimum_size = Vector2(350.0, 76.0)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description_label.add_theme_color_override("font_color", Color(0.84, 0.84, 0.88))
	root.add_child(_description_label)

	_outcome_label = Label.new()
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_outcome_label)

	_commit_button = Button.new()
	_commit_button.text = "Commit illuminated route"
	_commit_button.custom_minimum_size = Vector2(0.0, 42.0)
	_commit_button.pressed.connect(func() -> void: _select(_selected_index))
	root.add_child(_commit_button)
	_refresh_selection()


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
	if not summary.is_empty():
		return summary
	var parts: Array[String] = []
	var rewards: Dictionary = event.get("rewards", {})
	for key_variant in rewards.keys():
		var key := String(key_variant)
		var amount := float(rewards[key])
		parts.append("%s %s%s" % [key.capitalize(), "+" if amount >= 0.0 else "", str(amount)])
	var danger := int(event.get("danger", 0))
	if danger > 0:
		parts.append("Danger %d/3" % danger)
	return "  |  ".join(parts)


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
	if not _active:
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
