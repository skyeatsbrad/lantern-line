class_name UITheme
extends RefCounted


static func text_scale() -> float:
	return clampf(float(GameManager.get_setting("text_scale", 1.0)), 1.0, 1.3)


static func font_size(base_size: int) -> int:
	return maxi(10, int(round(float(base_size) * text_scale())))


static func high_contrast() -> bool:
	return bool(GameManager.get_setting("high_contrast", false))


static func accent_color() -> Color:
	return Color(1.0, 0.86, 0.42) if high_contrast() else Color(0.95, 0.82, 0.58)


static func muted_text_color() -> Color:
	return Color(0.82, 0.84, 0.9) if high_contrast() else Color(0.7, 0.72, 0.78)


static func success_color() -> Color:
	return Color(0.48, 1.0, 0.58) if high_contrast() else Color(0.55, 0.9, 0.58)


static func danger_color() -> Color:
	return Color(1.0, 0.42, 0.3) if high_contrast() else Color(0.95, 0.48, 0.38)


static func build() -> Theme:
	var result: Theme = Theme.new()
	var contrast: bool = high_contrast()
	var label_color := Color(1.0, 1.0, 1.0) if contrast else Color(0.86, 0.86, 0.89)
	var outline_color := Color(0.0, 0.0, 0.0, 1.0) if contrast else Color(0.02, 0.025, 0.035, 0.9)
	var panel_background := Color(0.01, 0.012, 0.018, 0.99) if contrast else Color(0.045, 0.05, 0.065, 0.94)
	var panel_border := Color(0.95, 0.76, 0.3) if contrast else Color(0.18, 0.17, 0.16)
	result.default_font_size = font_size(14)

	result.set_color("font_color", "Label", label_color)
	result.set_color("font_outline_color", "Label", outline_color)
	result.set_constant("outline_size", "Label", 2 if contrast else 1)

	for control_type in ["Button", "OptionButton", "MenuButton"]:
		result.set_color("font_color", control_type, Color(1.0, 0.96, 0.88) if contrast else Color(0.91, 0.88, 0.82))
		result.set_color("font_hover_color", control_type, Color(1.0, 0.9, 0.52))
		result.set_color("font_pressed_color", control_type, Color(0.08, 0.07, 0.06))
		result.set_color("font_focus_color", control_type, Color(1.0, 0.94, 0.68))
		result.set_color("font_disabled_color", control_type, Color(0.58, 0.6, 0.66) if contrast else Color(0.42, 0.43, 0.48))
		result.set_stylebox("normal", control_type, _box(
			Color(0.025, 0.03, 0.045, 1.0) if contrast else Color(0.08, 0.085, 0.105, 0.96),
			Color(0.72, 0.58, 0.28) if contrast else Color(0.28, 0.25, 0.21),
			2 if contrast else 1,
			5,
			8
		))
		result.set_stylebox("hover", control_type, _box(Color(0.14, 0.12, 0.105, 0.98), Color(1.0, 0.78, 0.3), 2 if contrast else 1, 5, 8))
		result.set_stylebox("pressed", control_type, _box(Color(0.9, 0.68, 0.36), Color(1.0, 0.9, 0.62), 1, 5, 8))
		result.set_stylebox("focus", control_type, _box(Color(0.08, 0.085, 0.105, 1.0), Color(1.0, 0.9, 0.42), 3 if contrast else 2, 5, 7))
		result.set_stylebox("disabled", control_type, _box(Color(0.04, 0.045, 0.06, 0.96), Color(0.3, 0.31, 0.36) if contrast else Color(0.16, 0.17, 0.2), 1, 5, 8))

	result.set_stylebox("panel", "PanelContainer", _box(panel_background, panel_border, 2 if contrast else 1, 5, 8))
	result.set_stylebox("background", "ProgressBar", _box(Color(0.12, 0.12, 0.14, 0.95), Color(0.2, 0.2, 0.22), 1, 4, 0))
	result.set_stylebox("fill", "ProgressBar", _box(Color(1.0, 0.72, 0.18, 1.0) if contrast else Color(0.84, 0.62, 0.31, 0.95), Color(0.98, 0.8, 0.5), 0, 4, 0))

	result.set_color("font_color", "CheckBox", label_color)
	result.set_color("font_hover_color", "CheckBox", Color(1.0, 0.88, 0.62))
	result.set_color("font_focus_color", "CheckBox", Color(1.0, 0.94, 0.68))
	result.set_color("font_selected_color", "TabBar", accent_color())
	result.set_color("font_unselected_color", "TabBar", muted_text_color())
	result.set_constant("outline_size", "Button", 1 if contrast else 0)
	return result


static func _box(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	padding: float
) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = padding
	box.content_margin_top = padding * 0.55
	box.content_margin_right = padding
	box.content_margin_bottom = padding * 0.55
	return box
