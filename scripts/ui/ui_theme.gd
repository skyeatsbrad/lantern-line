class_name UITheme
extends RefCounted

const BODY_FONT: FontFile = preload(
	"res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
)
const BOLD_FONT: FontFile = preload(
	"res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"
)
const DISPLAY_FONT_SOURCE: FontFile = preload("res://assets/fonts/Bitter-Variable.ttf")
const MODAL_EXIT_SECONDS := 0.26

static var _display_font: FontVariation


static func text_scale() -> float:
	return clampf(float(GameManager.get_setting("text_scale", 1.0)), 1.0, 1.3)


static func font_size(base_size: int) -> int:
	return maxi(10, int(round(float(base_size) * text_scale())))


static func high_contrast() -> bool:
	return bool(GameManager.get_setting("high_contrast", false))


static func compact_layout(viewport_size: Vector2) -> bool:
	return (
		viewport_size.x < 1100.0
		or viewport_size.y < 620.0
		or text_scale() > 1.15
	)


static func gameplay_hud_height(viewport_size: Vector2) -> float:
	var scale_growth: float = maxf(0.0, text_scale() - 1.0)
	return (
		164.0 + scale_growth * 105.0
		if compact_layout(viewport_size)
		else 190.0 + scale_growth * 90.0
	)


static func gameplay_safe_bottom(viewport_size: Vector2) -> float:
	return viewport_size.y - gameplay_hud_height(viewport_size) - 12.0


static func body_font() -> Font:
	return BODY_FONT


static func bold_font() -> Font:
	return BOLD_FONT


static func display_font() -> Font:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = DISPLAY_FONT_SOURCE
		var text_server := TextServerManager.get_primary_interface()
		_display_font.variation_opentype = {
			text_server.name_to_tag("wght"): 600.0
		}
	return _display_font


static func accent_color() -> Color:
	return PresentationPalette.color(&"brass", high_contrast())


static func muted_text_color() -> Color:
	var result: Color = PresentationPalette.color(&"bone", high_contrast())
	result.a = 0.9 if high_contrast() else 0.72
	return result


static func success_color() -> Color:
	return PresentationPalette.color(&"growth", high_contrast())


static func danger_color() -> Color:
	return PresentationPalette.color(&"danger", high_contrast())


static func animate_panel_in(
	panel: Control,
	backdrop: CanvasItem = null,
	travel: Vector2 = Vector2(0.0, 18.0)
) -> Tween:
	var reduced_motion: bool = bool(
		GameManager.get_setting("reduced_motion", false)
	)
	var duration: float = 0.12 if reduced_motion else 0.26
	var target_position: Vector2 = panel.position
	panel.modulate.a = 0.0
	if not reduced_motion:
		panel.position += travel
	if backdrop != null:
		backdrop.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, duration)
	if not reduced_motion and not travel.is_zero_approx():
		tween.tween_property(panel, "position", target_position, duration)
	if backdrop != null:
		tween.tween_property(backdrop, "modulate:a", 1.0, duration)
	return tween


static func animate_panel_out(
	panel: Control,
	backdrop: CanvasItem = null,
	travel: Vector2 = Vector2(0.0, 12.0),
	full_motion_duration: float = 0.18
) -> Tween:
	var reduced_motion: bool = bool(
		GameManager.get_setting("reduced_motion", false)
	)
	var duration: float = 0.1 if reduced_motion else full_motion_duration
	var target_position: Vector2 = (
		panel.position
		if reduced_motion
		else panel.position + travel
	)
	var tween := panel.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, duration)
	if not reduced_motion and not travel.is_zero_approx():
		tween.tween_property(panel, "position", target_position, duration)
	if backdrop != null:
		tween.tween_property(backdrop, "modulate:a", 0.0, duration)
	return tween


static func build() -> Theme:
	var result: Theme = Theme.new()
	var contrast: bool = high_contrast()
	var label_color := PresentationPalette.color(&"bone", contrast)
	var outline_color := (
		PresentationPalette.NIGHT_VOID
		if contrast
		else PresentationPalette.with_alpha(&"night_void", 0.9)
	)
	var panel_background := PresentationPalette.with_alpha(
		&"night_void",
		0.99 if contrast else 0.94,
		contrast
	)
	var panel_border := PresentationPalette.color(
		&"brass" if contrast else &"iron",
		contrast
	)
	result.default_font = BODY_FONT
	result.default_font_size = font_size(14)

	result.set_color("font_color", "Label", label_color)
	result.set_color("font_outline_color", "Label", outline_color)
	result.set_constant("outline_size", "Label", 2 if contrast else 1)

	for control_type in ["Button", "OptionButton", "MenuButton"]:
		result.set_font("font", control_type, BOLD_FONT)
		result.set_color("font_color", control_type, label_color)
		result.set_color(
			"font_hover_color",
			control_type,
			PresentationPalette.color(&"ember", true)
		)
		result.set_color("font_pressed_color", control_type, PresentationPalette.NIGHT_VOID)
		result.set_color(
			"font_focus_color",
			control_type,
			PresentationPalette.color(&"bone", true)
		)
		result.set_color(
			"font_disabled_color",
			control_type,
			PresentationPalette.with_alpha(&"slate", 0.9 if contrast else 0.72, contrast)
		)
		result.set_stylebox("normal", control_type, _box(
			PresentationPalette.with_alpha(&"coal", 1.0 if contrast else 0.96, contrast),
			PresentationPalette.color(&"brass" if contrast else &"iron", contrast),
			2 if contrast else 1,
			5,
			8
		))
		result.set_stylebox("hover", control_type, _box(
			PresentationPalette.with_alpha(&"iron", 0.98),
			PresentationPalette.color(&"ember", true),
			2 if contrast else 1,
			5,
			8
		))
		result.set_stylebox("pressed", control_type, _box(
			PresentationPalette.BRASS,
			PresentationPalette.color(&"bone", true),
			1,
			5,
			8
		))
		result.set_stylebox("focus", control_type, _box(
			PresentationPalette.COAL,
			PresentationPalette.color(&"ember", true),
			3 if contrast else 2,
			5,
			7
		))
		result.set_stylebox("disabled", control_type, _box(
			PresentationPalette.with_alpha(&"coal", 0.96),
			PresentationPalette.color(&"slate", contrast),
			1,
			5,
			8
		))

	result.set_stylebox("panel", "PanelContainer", _box(panel_background, panel_border, 2 if contrast else 1, 5, 8))
	result.set_stylebox("background", "ProgressBar", _box(
		PresentationPalette.with_alpha(&"coal", 0.95, contrast),
		PresentationPalette.color(&"iron", contrast),
		1,
		4,
		0
	))
	result.set_stylebox("fill", "ProgressBar", _box(
		PresentationPalette.color(&"ember", contrast),
		PresentationPalette.color(&"bone", contrast),
		0,
		4,
		0
	))

	result.set_font("font", "Label", BODY_FONT)
	result.set_font("font", "CheckBox", BODY_FONT)
	result.set_font("font", "TabBar", BOLD_FONT)
	result.set_color("font_color", "CheckBox", label_color)
	result.set_color(
		"font_hover_color",
		"CheckBox",
		PresentationPalette.color(&"ember", true)
	)
	result.set_color(
		"font_focus_color",
		"CheckBox",
		PresentationPalette.color(&"bone", true)
	)
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
