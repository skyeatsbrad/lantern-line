class_name SettingsPanel
extends Control
## Persistent accessibility and presentation settings.

signal closed()
signal guide_requested()

var _open: bool = false
var _first_focus: Control


func present() -> void:
	_open = true
	visible = true
	_build()
	set_process_input(true)


func is_open() -> bool:
	return _open


func hide_for_guide() -> void:
	_open = false
	visible = false


func _build() -> void:
	theme = UITheme.build()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.82)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var viewport_size := get_viewport_rect().size
	var frame_width := minf(760.0, viewport_size.x - 32.0)
	var frame_height := minf(660.0, viewport_size.y - 28.0)
	var frame := PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -frame_width * 0.5
	frame.offset_right = frame_width * 0.5
	frame.offset_top = -frame_height * 0.5
	frame.offset_bottom = frame_height * 0.5
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	frame.add_child(root)

	var title := Label.new()
	title.text = "ACCESSIBILITY & PRESENTATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.font_size(24))
	title.add_theme_color_override("font_color", UITheme.accent_color())
	root.add_child(title)

	var intro := Label.new()
	intro.text = "Changes save immediately. Use Tab to move, Enter to activate, and Escape to close."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", UITheme.muted_text_color())
	root.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(frame_width - 38.0, 0.0)
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var audio_card := _add_card(
		body,
		"AUDIO",
		"Adjust all ambient sound, warnings, and action cues."
	)
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	audio_card.add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Master volume"
	volume_label.custom_minimum_size = Vector2(150.0, 0.0)
	volume_row.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = float(GameManager.get_setting("master_volume", 0.8))
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(func(value: float) -> void:
		GameManager.set_setting("master_volume", value)
	)
	volume_row.add_child(volume_slider)
	_first_focus = volume_slider

	var reading_card := _add_card(
		body,
		"READABILITY",
		"Text values remain visible alongside every color-coded gauge or warning."
	)
	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 12)
	reading_card.add_child(text_row)
	var text_label := Label.new()
	text_label.text = "Interface text size"
	text_label.custom_minimum_size = Vector2(190.0, 0.0)
	text_row.add_child(text_label)
	var text_size := OptionButton.new()
	var scales: Array[float] = [1.0, 1.15, 1.3]
	var scale_names: Array[String] = ["100% - Standard", "115% - Large", "130% - Extra large"]
	var current_scale: float = UITheme.text_scale()
	for index in range(scales.size()):
		text_size.add_item(scale_names[index])
		text_size.set_item_metadata(index, scales[index])
		if is_equal_approx(scales[index], current_scale):
			text_size.select(index)
	text_size.item_selected.connect(func(index: int) -> void:
		GameManager.set_setting("text_scale", float(text_size.get_item_metadata(index)))
		call_deferred("_build")
	)
	text_row.add_child(text_size)

	var contrast_toggle := CheckBox.new()
	contrast_toggle.text = "High contrast UI and labeled enemy roles"
	contrast_toggle.button_pressed = bool(GameManager.get_setting("high_contrast", false))
	contrast_toggle.tooltip_text = "Uses brighter borders, stronger focus rings, and text labels above active threats."
	contrast_toggle.toggled.connect(func(enabled: bool) -> void:
		GameManager.set_setting("high_contrast", enabled)
		call_deferred("_build")
	)
	reading_card.add_child(contrast_toggle)

	var motion_card := _add_card(
		body,
		"MOTION & FLASHES",
		"These options reduce visual movement without removing combat information."
	)
	var shake_toggle := CheckBox.new()
	shake_toggle.text = "Screen shake"
	shake_toggle.button_pressed = bool(GameManager.get_setting("screen_shake", true))
	shake_toggle.toggled.connect(func(enabled: bool) -> void:
		GameManager.set_setting("screen_shake", enabled)
	)
	motion_card.add_child(shake_toggle)

	var motion_toggle := CheckBox.new()
	motion_toggle.text = "Reduced motion"
	motion_toggle.button_pressed = bool(GameManager.get_setting("reduced_motion", false))
	motion_toggle.tooltip_text = "Stops parallax drift, smoke, sparks, detached-car movement, and screen shake."
	motion_toggle.toggled.connect(func(enabled: bool) -> void:
		GameManager.set_setting("reduced_motion", enabled)
	)
	motion_card.add_child(motion_toggle)

	var flash_toggle := CheckBox.new()
	flash_toggle.text = "Reduced full-screen flashes"
	flash_toggle.button_pressed = bool(GameManager.get_setting("reduced_flashes", false))
	flash_toggle.tooltip_text = "Keeps hit markers and warning text while greatly reducing full-screen flash intensity."
	flash_toggle.toggled.connect(func(enabled: bool) -> void:
		GameManager.set_setting("reduced_flashes", enabled)
	)
	motion_card.add_child(flash_toggle)

	var input_card := _add_card(
		body,
		"INPUT",
		"All primary actions have both keyboard and clickable controls."
	)
	var holds_toggle := CheckBox.new()
	holds_toggle.text = "Shorter hold-to-detach confirmation"
	holds_toggle.button_pressed = bool(GameManager.get_setting("short_holds", false))
	holds_toggle.tooltip_text = "Reduces the rear-car detach hold from 0.85 seconds to 0.45 seconds."
	holds_toggle.toggled.connect(func(enabled: bool) -> void:
		GameManager.set_setting("short_holds", enabled)
	)
	input_card.add_child(holds_toggle)

	var guide_button := Button.new()
	guide_button.text = "Replay Conductor's Guide"
	guide_button.custom_minimum_size = Vector2(0.0, 42.0)
	guide_button.tooltip_text = "Review controls, power, combat responses, routes, and station decisions."
	guide_button.pressed.connect(_request_guide)
	body.add_child(guide_button)

	var close_button := Button.new()
	close_button.text = "Close Options"
	close_button.custom_minimum_size = Vector2(0.0, 44.0)
	close_button.pressed.connect(_close)
	root.add_child(close_button)
	call_deferred("_focus_first_control")


func _add_card(parent: VBoxContainer, heading: String, description: String) -> VBoxContainer:
	var card := PanelContainer.new()
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", UITheme.font_size(16))
	title.add_theme_color_override("font_color", UITheme.accent_color())
	content.add_child(title)
	var detail := Label.new()
	detail.text = description
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", UITheme.muted_text_color())
	content.add_child(detail)
	return content


func _focus_first_control() -> void:
	if is_instance_valid(_first_focus):
		_first_focus.grab_focus()


func _request_guide() -> void:
	if not _open:
		return
	_open = false
	visible = false
	AudioManager.play("click")
	emit_signal("guide_requested")


func _close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	AudioManager.play("click")
	emit_signal("closed")


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
