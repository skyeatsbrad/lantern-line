class_name SettingsPanel
extends Control
## Persistent accessibility and presentation settings.

signal closed()
signal guide_requested()

var _open: bool = false
var _first_focus: Control
var _touch_layout: bool = false


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
	_touch_layout = UITheme.touch_layout(viewport_size)
	var comfort := UITheme.comfort_insets(viewport_size)
	var frame_width := (
		viewport_size.x - comfort.x - comfort.z
		if _touch_layout
		else minf(760.0, viewport_size.x - 32.0)
	)
	var frame_height := (
		viewport_size.y - comfort.y - comfort.w
		if _touch_layout
		else minf(660.0, viewport_size.y - 28.0)
	)
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
	intro.text = (
		"Changes save immediately. Every row is touch-ready."
		if _touch_layout
		else "Changes save immediately. Use Tab to move, Enter to activate, and Escape to close."
	)
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
		"Adjust the overall mix or tune music, train ambience, action cues, and UI separately."
	)
	_first_focus = _add_volume_slider(
		audio_card,
		"Master volume",
		"master_volume",
		0.8
	)
	_add_volume_slider(audio_card, "Music", "music_volume", 0.72)
	_add_volume_slider(audio_card, "Train & ambience", "ambience_volume", 0.72)
	_add_volume_slider(audio_card, "Combat & actions", "sfx_volume", 0.86)
	_add_volume_slider(audio_card, "Interface", "ui_volume", 0.82)

	var reading_card := _add_card(
		body,
		"READABILITY",
		"Text values remain visible alongside every color-coded gauge or warning."
	)
	var text_row: BoxContainer = (
		VBoxContainer.new() if _touch_layout else HBoxContainer.new()
	)
	text_row.add_theme_constant_override("separation", 12)
	reading_card.add_child(text_row)
	var text_label := Label.new()
	text_label.text = "Interface text size"
	text_label.custom_minimum_size = Vector2(
		0.0 if _touch_layout else 190.0,
		0.0
	)
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

	var presentation_card := _add_card(
		body,
		"VISUAL QUALITY",
		"Automatic chooses a safe profile for this device. Vector fallback is a recovery and comparison mode."
	)
	var profile_row: BoxContainer = (
		VBoxContainer.new() if _touch_layout else HBoxContainer.new()
	)
	profile_row.add_theme_constant_override("separation", 12)
	presentation_card.add_child(profile_row)
	var profile_label := Label.new()
	profile_label.text = "Presentation profile"
	profile_label.custom_minimum_size = Vector2(
		0.0 if _touch_layout else 190.0,
		0.0
	)
	profile_row.add_child(profile_label)
	var profile_select := OptionButton.new()
	var profile_values: Array[String] = [
		PresentationProfile.AUTO,
		PresentationProfile.HIGH,
		PresentationProfile.MEDIUM,
		PresentationProfile.LOW,
		PresentationProfile.VECTOR_FALLBACK
	]
	var profile_names: Array[String] = [
		"Automatic",
		"High",
		"Medium",
		"Low / battery saver",
		"Vector fallback"
	]
	var current_profile := PresentationProfile.normalize(
		GameManager.get_setting(
			"presentation_profile",
			PresentationProfile.AUTO
		)
	)
	for index in range(profile_values.size()):
		profile_select.add_item(profile_names[index])
		profile_select.set_item_metadata(index, profile_values[index])
		if profile_values[index] == current_profile:
			profile_select.select(index)
	profile_select.item_selected.connect(func(index: int) -> void:
		GameManager.set_setting(
			"presentation_profile",
			String(profile_select.get_item_metadata(index))
		)
		call_deferred("_build")
	)
	profile_row.add_child(profile_select)

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

	var touch_row: BoxContainer = (
		VBoxContainer.new() if _touch_layout else HBoxContainer.new()
	)
	touch_row.add_theme_constant_override("separation", 12)
	input_card.add_child(touch_row)
	var touch_label := Label.new()
	touch_label.text = "Touch target size"
	touch_label.custom_minimum_size = Vector2(
		0.0 if _touch_layout else 190.0,
		0.0
	)
	touch_row.add_child(touch_label)
	var touch_size := OptionButton.new()
	var touch_scales: Array[float] = [1.0, 1.15, 1.3]
	var touch_names: Array[String] = [
		"100% - Standard",
		"115% - Large",
		"130% - Extra large"
	]
	var current_touch_scale := UITheme.touch_target_scale()
	for index in range(touch_scales.size()):
		touch_size.add_item(touch_names[index])
		touch_size.set_item_metadata(index, touch_scales[index])
		if is_equal_approx(touch_scales[index], current_touch_scale):
			touch_size.select(index)
	touch_size.item_selected.connect(func(index: int) -> void:
		GameManager.set_setting(
			"touch_target_scale",
			float(touch_size.get_item_metadata(index))
		)
		call_deferred("_build")
	)
	touch_row.add_child(touch_size)

	var aim_row: BoxContainer = (
		VBoxContainer.new() if _touch_layout else HBoxContainer.new()
	)
	aim_row.add_theme_constant_override("separation", 12)
	input_card.add_child(aim_row)
	var aim_label := Label.new()
	aim_label.text = "Touch aiming"
	aim_label.custom_minimum_size = Vector2(
		0.0 if _touch_layout else 190.0,
		0.0
	)
	aim_row.add_child(aim_label)
	var aim_mode := OptionButton.new()
	aim_mode.add_item("Absolute - point at the target")
	aim_mode.set_item_metadata(0, "absolute")
	aim_mode.add_item("Relative - drag like a trackpad")
	aim_mode.set_item_metadata(1, "relative")
	aim_mode.select(
		1
		if String(GameManager.get_setting("touch_aim_mode", "absolute"))
			== "relative"
		else 0
	)
	aim_mode.item_selected.connect(func(index: int) -> void:
		GameManager.set_setting(
			"touch_aim_mode",
			String(aim_mode.get_item_metadata(index))
		)
	)
	aim_row.add_child(aim_mode)

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
	if _touch_layout:
		_apply_touch_targets(
			frame,
			UITheme.touch_target_size(viewport_size).y
		)
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


func _add_volume_slider(
	parent: VBoxContainer,
	label_text: String,
	setting_key: String,
	default_value: float
) -> HSlider:
	var row: BoxContainer = (
		VBoxContainer.new() if _touch_layout else HBoxContainer.new()
	)
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(
		0.0 if _touch_layout else 170.0,
		0.0
	)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameManager.get_setting(setting_key, default_value))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		GameManager.set_setting(setting_key, value)
	)
	row.add_child(slider)
	return slider


func _apply_touch_targets(node: Node, minimum_height: float) -> void:
	if node is BaseButton or node is HSlider:
		var control := node as Control
		control.custom_minimum_size.y = maxf(
			control.custom_minimum_size.y,
			minimum_height
		)
	if node is BoxContainer:
		var row := node as BoxContainer
		if row.get_child_count() > 1:
			row.custom_minimum_size.y = maxf(
				row.custom_minimum_size.y,
				minimum_height
			)
	for child in node.get_children():
		_apply_touch_targets(child, minimum_height)


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
