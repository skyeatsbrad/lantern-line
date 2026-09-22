class_name HUD
extends Control
## HUD
##
## Railway-equipment styled interface. Not color-only: text + icons + bars.

signal request_lens(name: String)
signal request_priority(role: String, level: int)
signal request_pause()
signal request_speed()
signal request_focus()
signal request_defense_salvo()
signal request_field_action(action: String)
signal request_settings()
signal request_guide()
signal detach_hold_changed(active: bool)

var _run_state: RunState
var _lens_config: Dictionary
var _last_notification: String = ""
var _notification_timer: float = 0.0
var _compact_layout: bool = false

@onready var _title_label: Label
@onready var _dist_label: Label
@onready var _time_label: Label
@onready var _lens_label: Label
var _bars: Dictionary = {}
var _prio_buttons: Dictionary = {}
@onready var _notification_label: Label
@onready var _notification_panel: PanelContainer
@onready var _hint_label: Label
@onready var _loco_bar: ProgressBar
@onready var _focus_button: Button
@onready var _focus_label: Label
@onready var _salvo_button: Button
@onready var _patch_button: Button
@onready var _overcharge_button: Button
@onready var _flare_button: Button
@onready var _detach_button: Button
@onready var _detach_progress: ProgressBar
@onready var _boss_label: Label
@onready var _consist_label: Label
@onready var _power_status_label: Label
@onready var _crew_status_label: Label
@onready var _critical_label: Label
@onready var _critical_panel: PanelContainer
var _critical_timer: float = 0.0
var _cinematic_panel: PanelContainer
var _cinematic_kicker: Label
var _cinematic_title: Label
var _cinematic_body: Label
var _cinematic_timer: float = 0.0


func setup(run_state: RunState, lens_config: Dictionary) -> void:
	_run_state = run_state
	_lens_config = lens_config
	_build_ui()
	_run_state.resources_changed.connect(_refresh)
	_run_state.power_changed.connect(_refresh)
	_run_state.locomotive_damaged.connect(func(_hp: float) -> void: _refresh())
	_refresh()
	set_process(true)


func rebuild() -> void:
	if _run_state == null:
		return
	_build_ui()
	_refresh()


func _build_ui() -> void:
	theme = UITheme.build()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_bars.clear()
	_prio_buttons.clear()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	var text_scale: float = UITheme.effective_text_scale()
	var base_font_size: int = UITheme.font_size(14)
	var viewport_size: Vector2 = get_viewport_rect().size
	_compact_layout = UITheme.compact_layout(viewport_size)
	if _compact_layout:
		base_font_size = UITheme.font_size(13)
	var scale_growth: float = maxf(0.0, text_scale - 1.0)
	var bottom_height: float = UITheme.gameplay_hud_height(viewport_size)
	var notification_center: float = 0.42 if _compact_layout else 0.5
	var notification_width: float = minf(
		460.0 if _compact_layout else 620.0,
		viewport_size.x - 36.0
	)
	var mid_bottom: float = (
		122.0 + scale_growth * 72.0
		if _compact_layout
		else 132.0 + scale_growth * 64.0
	)
	if _compact_layout and _run_state.cars.size() > 3:
		mid_bottom += 24.0

	# Top-left: distance and time
	var top: PanelContainer = PanelContainer.new()
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.offset_left = 12
	top.offset_top = 12
	top.offset_right = 250 if _compact_layout else 320
	top.offset_bottom = (
		78.0 + scale_growth * 48.0
		if _compact_layout
		else 84.0 + scale_growth * 44.0
	)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var top_vbox: VBoxContainer = VBoxContainer.new()
	top.add_child(top_vbox)
	_title_label = Label.new()
	_title_label.text = "THE LANTERN LINE"
	_title_label.add_theme_font_size_override("font_size", base_font_size + 4)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.5))
	top_vbox.add_child(_title_label)
	_dist_label = Label.new()
	_dist_label.add_theme_font_size_override("font_size", base_font_size)
	top_vbox.add_child(_dist_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", base_font_size)
	top_vbox.add_child(_time_label)

	# Top-right: resources gauges
	var right: PanelContainer = PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	var resource_panel_width: float = (
		360.0 + scale_growth * 180.0
		if _compact_layout
		else 310.0
	)
	right.offset_left = -resource_panel_width
	right.offset_top = 12
	right.offset_right = -12
	right.offset_bottom = (
		180.0 + scale_growth * 120.0
		if _compact_layout
		else 226.0 + scale_growth * 96.0
	)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	var rvbox: VBoxContainer = VBoxContainer.new()
	right.add_child(rvbox)
	rvbox.add_theme_constant_override("separation", 4)
	var resource_parent: Node = rvbox
	if _compact_layout:
		var resource_grid := GridContainer.new()
		resource_grid.columns = 2
		resource_grid.add_theme_constant_override("h_separation", 6)
		resource_grid.add_theme_constant_override("v_separation", 2)
		rvbox.add_child(resource_grid)
		resource_parent = resource_grid
	_bars["power"] = _make_bar(resource_parent, "Power", Color(0.95, 0.85, 0.3), base_font_size)
	_bars["scrap"] = _make_bar(resource_parent, "Scrap", Color(0.7, 0.6, 0.5), base_font_size)
	_bars["supplies"] = _make_bar(resource_parent, "Supplies", Color(0.55, 0.85, 0.5), base_font_size)
	_bars["lumen"] = _make_bar(resource_parent, "Lumen", Color(1.0, 0.86, 0.62), base_font_size)
	_power_status_label = Label.new()
	_power_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_power_status_label.add_theme_font_size_override("font_size", base_font_size - 2)
	rvbox.add_child(_power_status_label)
	var field_row := HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 5)
	rvbox.add_child(field_row)
	_patch_button = Button.new()
	_patch_button.text = (
		"Patch %d" % RunState.FIELD_PATCH_COST
		if _compact_layout
		else "Patch -%d" % RunState.FIELD_PATCH_COST
	)
	_patch_button.tooltip_text = "After Waypost Five: repair the most damaged section by 22 integrity."
	_patch_button.pressed.connect(
		func() -> void: emit_signal("request_field_action", "patch")
	)
	field_row.add_child(_patch_button)
	_overcharge_button = Button.new()
	_overcharge_button.text = (
		"Boost %d" % RunState.FIELD_OVERCHARGE_COST
		if _compact_layout
		else "Overcharge -%d" % RunState.FIELD_OVERCHARGE_COST
	)
	_overcharge_button.tooltip_text = "After Waypost Five: gain +4 power, +3 lumen, and a 12-second systems boost."
	_overcharge_button.pressed.connect(
		func() -> void: emit_signal("request_field_action", "overcharge")
	)
	field_row.add_child(_overcharge_button)
	_flare_button = Button.new()
	_flare_button.text = (
		"Flare %d" % RunState.FIELD_FLARE_COST
		if _compact_layout
		else "Flare -%d" % RunState.FIELD_FLARE_COST
	)
	_flare_button.tooltip_text = "Burn a signal flare for wider, longer, stronger light."
	_flare_button.pressed.connect(
		func() -> void: emit_signal("request_field_action", "flare")
	)
	field_row.add_child(_flare_button)

	# Locomotive HP visible top center under title
	var mid: PanelContainer = PanelContainer.new()
	mid.anchor_left = 0.5
	mid.anchor_right = 0.5
	mid.offset_left = -145 if _compact_layout else -210
	mid.offset_right = 145 if _compact_layout else 210
	mid.offset_top = 12
	mid.offset_bottom = mid_bottom
	add_child(mid)
	var mid_v: VBoxContainer = VBoxContainer.new()
	mid.add_child(mid_v)
	var loco_label: Label = Label.new()
	loco_label.text = "LOCOMOTIVE"
	loco_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loco_label.add_theme_font_size_override("font_size", base_font_size)
	loco_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.35))
	mid_v.add_child(loco_label)
	_loco_bar = ProgressBar.new()
	_loco_bar.min_value = 0
	_loco_bar.max_value = 100
	_loco_bar.value = 100
	_loco_bar.show_percentage = false
	_loco_bar.custom_minimum_size = Vector2(240, 12)
	mid_v.add_child(_loco_bar)
	_boss_label = Label.new()
	_boss_label.visible = false
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boss_label.add_theme_font_size_override("font_size", base_font_size - 1)
	_boss_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.42))
	mid_v.add_child(_boss_label)
	_consist_label = Label.new()
	_consist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_consist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_consist_label.add_theme_font_size_override("font_size", base_font_size - 2)
	_consist_label.add_theme_color_override("font_color", Color(0.76, 0.78, 0.84))
	mid_v.add_child(_consist_label)
	_crew_status_label = Label.new()
	_crew_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crew_status_label.add_theme_font_size_override("font_size", base_font_size - 2)
	_crew_status_label.add_theme_color_override("font_color", Color(0.9, 0.72, 0.42))
	mid_v.add_child(_crew_status_label)

	# Bottom-left: lens breaker panel
	var lens_panel: PanelContainer = PanelContainer.new()
	lens_panel.anchor_right = 0.23 if _compact_layout else 0.26
	lens_panel.anchor_top = 1.0
	lens_panel.anchor_bottom = 1.0
	lens_panel.offset_top = -bottom_height
	lens_panel.offset_bottom = -12
	lens_panel.offset_left = 12
	lens_panel.offset_right = -4
	add_child(lens_panel)
	var lens_v: VBoxContainer = VBoxContainer.new()
	lens_panel.add_child(lens_v)
	var lens_title: Label = Label.new()
	lens_title.text = "HEADLIGHT LENS"
	lens_title.add_theme_font_size_override("font_size", base_font_size)
	lens_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	lens_v.add_child(lens_title)
	var lens_row: HBoxContainer = HBoxContainer.new()
	lens_row.add_theme_constant_override("separation", 6)
	lens_v.add_child(lens_row)
	for lens_key in _lens_config.keys():
		var b: Button = Button.new()
		b.text = String(lens_key).left(3) if _compact_layout else String(lens_key)
		b.custom_minimum_size = Vector2(52 if _compact_layout else 90, 34 if _compact_layout else 30)
		var lk: String = String(lens_key)
		b.pressed.connect(func() -> void: emit_signal("request_lens", lk))
		lens_row.add_child(b)
	_lens_label = Label.new()
	_lens_label.add_theme_font_size_override("font_size", base_font_size)
	_lens_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lens_v.add_child(_lens_label)

	# Bottom-center: priorities (Q/W/E/R)
	var prio: PanelContainer = PanelContainer.new()
	prio.anchor_left = 0.23 if _compact_layout else 0.26
	prio.anchor_right = 0.68 if _compact_layout else 0.73
	prio.anchor_top = 1.0
	prio.anchor_bottom = 1.0
	prio.offset_left = 4
	prio.offset_right = -4
	prio.offset_top = -bottom_height
	prio.offset_bottom = -12
	add_child(prio)
	var prio_v: VBoxContainer = VBoxContainer.new()
	prio.add_child(prio_v)
	var prio_title: Label = Label.new()
	prio_title.text = "POWER (Q W E R)" if _compact_layout else "POWER PRIORITIES  (Q W E R)"
	prio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prio_title.add_theme_font_size_override("font_size", base_font_size)
	prio_v.add_child(prio_title)
	var prio_row: HBoxContainer = HBoxContainer.new()
	prio_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prio_row.add_theme_constant_override("separation", 10)
	prio_v.add_child(prio_row)
	for role in ["engine", "light", "defense", "repair"]:
		var col: VBoxContainer = VBoxContainer.new()
		prio_row.add_child(col)
		var role_label: Label = Label.new()
		role_label.text = role.capitalize()
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_label.add_theme_font_size_override("font_size", base_font_size - 1)
		col.add_child(role_label)
		var levels := HBoxContainer.new()
		levels.add_theme_constant_override("separation", 2)
		col.add_child(levels)
		var buttons: Array = []
		for level in range(4):
			var level_button := Button.new()
			level_button.text = str(level)
			level_button.custom_minimum_size = Vector2(22 if _compact_layout else 30, 30)
			var role_key: String = role
			var requested_level: int = level
			level_button.pressed.connect(
				func() -> void: emit_signal("request_priority", role_key, requested_level)
			)
			levels.add_child(level_button)
			buttons.append(level_button)
		_prio_buttons[role] = buttons

	# Bottom-right: pause / speed / detach
	var ctrl: PanelContainer = PanelContainer.new()
	ctrl.anchor_left = 0.68 if _compact_layout else 0.73
	ctrl.anchor_right = 1.0
	ctrl.anchor_top = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = 4
	ctrl.offset_right = -12
	ctrl.offset_top = -bottom_height
	ctrl.offset_bottom = -12
	add_child(ctrl)
	var ctrl_v: VBoxContainer = VBoxContainer.new()
	ctrl.add_child(ctrl_v)
	var ctrl_title: Label = Label.new()
	ctrl_title.text = "CONTROL" if not _compact_layout else "DRIVE / RESPONSE"
	ctrl_title.visible = not _compact_layout
	ctrl_title.add_theme_font_size_override("font_size", base_font_size)
	ctrl_v.add_child(ctrl_title)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	ctrl_v.add_child(row)
	var pause_btn: Button = Button.new()
	pause_btn.text = "Pause" if _compact_layout else "Pause (Sp)"
	pause_btn.pressed.connect(func() -> void: emit_signal("request_pause"))
	row.add_child(pause_btn)
	var speed_btn: Button = Button.new()
	speed_btn.text = "Speed" if _compact_layout else "Speed (T)"
	speed_btn.pressed.connect(func() -> void: emit_signal("request_speed"))
	row.add_child(speed_btn)
	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 6)
	ctrl_v.add_child(utility_row)
	var guide_btn := Button.new()
	guide_btn.text = "Guide (H)" if not _compact_layout else "Guide"
	guide_btn.tooltip_text = "Open the Conductor's Guide. The run pauses while it is open."
	guide_btn.pressed.connect(func() -> void: emit_signal("request_guide"))
	utility_row.add_child(guide_btn)
	var settings_btn := Button.new()
	settings_btn.text = "Options (Esc)" if not _compact_layout else "Options"
	settings_btn.tooltip_text = "Open accessibility and presentation settings."
	settings_btn.pressed.connect(func() -> void: emit_signal("request_settings"))
	utility_row.add_child(settings_btn)
	var ability_row := HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", 6)
	ctrl_v.add_child(ability_row)
	_focus_button = Button.new()
	_focus_button.text = "Focus (F)"
	_focus_button.pressed.connect(func() -> void: emit_signal("request_focus"))
	ability_row.add_child(_focus_button)
	_salvo_button = Button.new()
	_salvo_button.text = "Salvo (C)"
	_salvo_button.pressed.connect(func() -> void: emit_signal("request_defense_salvo"))
	ability_row.add_child(_salvo_button)
	var ability_status := HBoxContainer.new()
	ability_status.add_theme_constant_override("separation", 6)
	ctrl_v.add_child(ability_status)
	_focus_label = Label.new()
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus_label.add_theme_font_size_override("font_size", base_font_size - 2)
	_focus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_status.add_child(_focus_label)
	_detach_button = Button.new()
	_detach_button.text = "Hold to detach rear (X)"
	_detach_button.button_down.connect(func() -> void: emit_signal("detach_hold_changed", true))
	_detach_button.button_up.connect(func() -> void: emit_signal("detach_hold_changed", false))
	ctrl_v.add_child(_detach_button)
	_detach_progress = ProgressBar.new()
	_detach_progress.min_value = 0.0
	_detach_progress.max_value = 1.0
	_detach_progress.value = 0.0
	_detach_progress.show_percentage = false
	_detach_progress.custom_minimum_size = Vector2(0.0, 5.0)
	ctrl_v.add_child(_detach_progress)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", base_font_size - 2)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_hint_label.visible = not _compact_layout
	ctrl_v.add_child(_hint_label)

	# Center notification
	_notification_panel = PanelContainer.new()
	_notification_panel.anchor_left = notification_center
	_notification_panel.anchor_right = notification_center
	_notification_panel.offset_left = -notification_width * 0.5
	_notification_panel.offset_right = notification_width * 0.5
	_notification_panel.offset_top = mid_bottom + 10.0
	_notification_panel.offset_bottom = mid_bottom + 62.0
	_notification_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_panel.visible = false
	add_child(_notification_panel)
	_notification_label = Label.new()
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notification_label.add_theme_font_size_override("font_size", base_font_size + 6)
	_notification_label.add_theme_color_override("font_color", UITheme.accent_color())
	_notification_panel.add_child(_notification_label)

	_critical_panel = PanelContainer.new()
	_critical_panel.anchor_left = notification_center
	_critical_panel.anchor_right = notification_center
	_critical_panel.offset_left = -notification_width * 0.5
	_critical_panel.offset_right = notification_width * 0.5
	_critical_panel.offset_top = mid_bottom + 70.0
	_critical_panel.offset_bottom = mid_bottom + 126.0
	_critical_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_critical_panel.visible = false
	add_child(_critical_panel)
	_critical_label = Label.new()
	_critical_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_critical_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_critical_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_critical_label.add_theme_font_size_override("font_size", base_font_size + 5)
	_critical_label.add_theme_color_override("font_color", UITheme.danger_color())
	_critical_panel.add_child(_critical_label)

	_cinematic_panel = PanelContainer.new()
	_cinematic_panel.anchor_left = 0.5
	_cinematic_panel.anchor_right = 0.5
	_cinematic_panel.anchor_top = 0.39 if _compact_layout else 0.37
	_cinematic_panel.anchor_bottom = (
		0.39 if _compact_layout else 0.37
	)
	var cinematic_width: float = minf(
		620.0 if _compact_layout else 760.0,
		viewport_size.x - 48.0
	)
	_cinematic_panel.offset_left = -cinematic_width * 0.5
	_cinematic_panel.offset_right = cinematic_width * 0.5
	_cinematic_panel.offset_top = -58.0
	_cinematic_panel.offset_bottom = 72.0
	_cinematic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinematic_panel.visible = false
	add_child(_cinematic_panel)
	var cinematic_vbox := VBoxContainer.new()
	cinematic_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cinematic_vbox.add_theme_constant_override("separation", 2)
	_cinematic_panel.add_child(cinematic_vbox)
	_cinematic_kicker = Label.new()
	_cinematic_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cinematic_kicker.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(11)
	)
	_cinematic_kicker.add_theme_color_override(
		"font_color",
		UITheme.muted_text_color()
	)
	cinematic_vbox.add_child(_cinematic_kicker)
	_cinematic_title = Label.new()
	_cinematic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cinematic_title.add_theme_font_override("font", UITheme.display_font())
	_cinematic_title.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(27 if _compact_layout else 32)
	)
	_cinematic_title.add_theme_color_override(
		"font_color",
		UITheme.accent_color()
	)
	cinematic_vbox.add_child(_cinematic_title)
	_cinematic_body = Label.new()
	_cinematic_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cinematic_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cinematic_body.custom_minimum_size = Vector2(
		cinematic_width - 36.0,
		0.0
	)
	_cinematic_body.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(12)
	)
	_cinematic_body.add_theme_color_override(
		"font_color",
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	cinematic_vbox.add_child(_cinematic_body)


func _make_bar(parent: Node, label: String, col: Color, font_size: int) -> Dictionary:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	row.add_theme_constant_override("separation", 6)
	var lbl: Label = Label.new()
	lbl.text = label
	lbl.text = (
		{"Power": "Pwr", "Scrap": "Scr", "Supplies": "Sup", "Lumen": "Lum"}.get(
			label,
			label
		)
		if _compact_layout
		else label
	)
	lbl.custom_minimum_size = Vector2(32 if _compact_layout else 70, 16)
	lbl.add_theme_font_size_override("font_size", font_size)
	row.add_child(lbl)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(48 if _compact_layout else 120, 12)
	bar.modulate = col
	row.add_child(bar)
	var val: Label = Label.new()
	val.custom_minimum_size = Vector2(62 if _compact_layout else 46, 16)
	val.add_theme_font_size_override("font_size", font_size)
	row.add_child(val)
	return {"bar": bar, "value": val}


func _process(delta: float) -> void:
	if _run_state == null:
		return
	# distance / time
	_dist_label.text = "Distance: %d / %d m" % [int(_run_state.distance), int(RunState.JOURNEY_TARGET)]
	var m: int = int(_run_state.travel_time) / 60
	var s: int = int(_run_state.travel_time) % 60
	var speed_text: String = str(_run_state.speed_scale).trim_suffix(".0")
	var effective_speed: float = _run_state.effective_speed_scale()
	var pace_status: String = ""
	if _run_state.paused:
		pace_status = "[PAUSED]"
	elif effective_speed < _run_state.speed_scale:
		pace_status = ">%sx AUTO" % str(effective_speed).trim_suffix(".0")
	_time_label.text = "Time: %02d:%02d   %sx %s" % [m, s, speed_text, pace_status]
	var lens: Dictionary = _lens_config.get(_run_state.current_lens, {})
	_lens_label.text = (
		"%s  %.1fs" % [_run_state.current_lens, _run_state.lens_cooldown]
		if _compact_layout
		else "%s (%.1fs)\n%s" % [
			_run_state.current_lens,
			_run_state.lens_cooldown,
			String(lens.get("description", ""))
		]
	)
	var focus_cost: float = _run_state.stats().focus_cost
	var focus_status: String
	if _run_state.focus_active_time > 0.0:
		focus_status = "F %.1fs ACTIVE" % _run_state.focus_active_time
	elif _run_state.focus_cooldown > 0.0:
		focus_status = "F %.1fs" % _run_state.focus_cooldown
	elif _run_state.lumen < focus_cost:
		focus_status = "F needs %.0fL" % focus_cost
	else:
		focus_status = "F ready %.0fL" % focus_cost
	_focus_button.disabled = (
		_run_state.focus_active_time > 0.0
		or _run_state.focus_cooldown > 0.0
		or _run_state.lumen < focus_cost
	)
	var salvo_status: String
	if _run_state.defense_salvo_cooldown > 0.0:
		salvo_status = "C %.1fs" % _run_state.defense_salvo_cooldown
	elif _run_state.stats().defense_mounts.is_empty():
		salvo_status = "C needs Defense"
	elif _run_state.power < RunState.DEFENSE_SALVO_POWER_COST:
		salvo_status = "C needs %.0fP" % RunState.DEFENSE_SALVO_POWER_COST
	else:
		salvo_status = "C ready %.0fP" % RunState.DEFENSE_SALVO_POWER_COST
	_focus_label.text = "%s  |  %s" % [focus_status, salvo_status]
	_salvo_button.disabled = (
		_run_state.defense_salvo_cooldown > 0.0
		or _run_state.stats().defense_mounts.is_empty()
		or _run_state.power < RunState.DEFENSE_SALVO_POWER_COST
	)
	_hint_label.text = (
		"Mouse aim | F focus | C salvo | hold X"
		if _compact_layout
		else "Aim: mouse   F focus   C salvo   V patch   B overcharge   G flare   hold X"
	) + "   [%sx]" % speed_text
	_notification_timer = maxf(0.0, _notification_timer - delta)
	if _notification_timer <= 0.0:
		_notification_label.text = ""
		_notification_panel.visible = false
	_critical_timer = maxf(0.0, _critical_timer - delta)
	if _critical_timer <= 0.0:
		_critical_label.text = ""
		_critical_panel.visible = false
	_cinematic_timer = maxf(0.0, _cinematic_timer - delta)
	if _cinematic_panel.visible:
		if _cinematic_timer <= 0.18:
			_cinematic_panel.modulate.a = clampf(
				_cinematic_timer / 0.18,
				0.0,
				1.0
			)
		if _cinematic_timer <= 0.0:
			_cinematic_panel.visible = false
			_cinematic_panel.modulate.a = 1.0


func _refresh() -> void:
	if _run_state == null:
		return
	# Resource bars/values
	_bars["power"]["bar"].value = clampf(_run_state.power / 12.0, 0.0, 1.0) * 100.0
	var stats: TrainStats = _run_state.stats()
	_bars["power"]["value"].text = "%0.1f (%+.1f)" % [_run_state.power, stats.power_net]
	_bars["scrap"]["bar"].value = clampf(_run_state.scrap / 60.0, 0.0, 1.0) * 100.0
	_bars["scrap"]["value"].text = "%d" % int(_run_state.scrap)
	_bars["supplies"]["bar"].value = clampf(_run_state.supplies / 120.0, 0.0, 1.0) * 100.0
	_bars["supplies"]["value"].text = "%d" % int(_run_state.supplies)
	_bars["lumen"]["bar"].value = clampf(_run_state.lumen / 40.0, 0.0, 1.0) * 100.0
	_bars["lumen"]["value"].text = "%d" % int(_run_state.lumen)
	# priorities
	for role in ["engine", "light", "defense", "repair"]:
		var v: int = int(_run_state.priorities[role])
		var buttons: Array = _prio_buttons.get(role, [])
		for level in range(buttons.size()):
			var button: Button = buttons[level]
			button.text = ("[%d]" % level) if level == v else str(level)
	# locomotive
	_loco_bar.value = _run_state.locomotive_hp / _run_state.locomotive_max_hp * 100.0
	_consist_label.text = _consist_status()
	_crew_status_label.text = _active_crew_status()
	_power_status_label.text = _power_status(stats)
	_power_status_label.add_theme_color_override(
		"font_color",
		UITheme.danger_color()
		if _run_state.brownout_active or stats.requested_power_net < 0.0
		else UITheme.success_color()
	)
	_patch_button.disabled = not _run_state.field_patch_available()
	_overcharge_button.disabled = (
		not _run_state.station_completed
		or
		_run_state.scrap < RunState.FIELD_OVERCHARGE_COST
	)
	_flare_button.disabled = not _run_state.field_flare_available()


func flash(msg: String, duration: float = 2.0) -> void:
	if _critical_timer > 0.0:
		return
	_notification_label.text = msg
	_notification_timer = duration
	_notification_panel.visible = true


func show_critical(msg: String, duration: float = 4.0) -> void:
	_notification_timer = 0.0
	_notification_panel.visible = false
	_cinematic_timer = 0.0
	_cinematic_panel.visible = false
	_critical_label.text = msg
	_critical_timer = maxf(_critical_timer, duration)
	_critical_panel.visible = true


func show_cinematic(
	kicker: String,
	title: String,
	body: String,
	duration: float = 1.4
) -> void:
	if _critical_timer > 0.0:
		return
	_notification_timer = 0.0
	_notification_panel.visible = false
	_cinematic_kicker.text = kicker.to_upper()
	_cinematic_title.text = title
	_cinematic_body.text = body
	_cinematic_timer = maxf(duration, 0.4)
	_cinematic_panel.visible = true
	UITheme.animate_panel_in(_cinematic_panel, null, Vector2.ZERO)


func cinematic_visible() -> bool:
	return is_instance_valid(_cinematic_panel) and _cinematic_panel.visible


func set_detach_hold(progress: float, preview: String = "") -> void:
	if _detach_progress == null:
		return
	_detach_progress.value = clampf(progress, 0.0, 1.0)
	_detach_button.text = (
		"Release to cancel: %s" % preview
		if progress > 0.0 and not preview.is_empty()
		else "Hold to detach rear (X)"
	)


func set_boss_status(text: String, ratio: float = -1.0) -> void:
	if _boss_label == null:
		return
	_boss_label.visible = not text.is_empty()
	var display_text: String = text.replace(" - ", "\n") if _compact_layout else text
	_boss_label.text = (
		display_text
		if ratio < 0.0
		else "%s  %d%%" % [
			display_text,
			int(clampf(ratio, 0.0, 1.0) * 100.0)
		]
	)


func _consist_status() -> String:
	var parts: Array[String] = []
	var compact_parts: Array[String] = []
	for car_variant in _run_state.cars:
		var car: Dictionary = car_variant
		var type_key: String = String(car.get("type", "Car"))
		var short_name: String = {
			"Battery": "BAT",
			"Workshop": "WRK",
			"Passenger": "PAS",
			"Greenhouse": "GRN",
			"Defense": "DEF",
			"Utility": "UTL"
		}.get(type_key, type_key.left(3).to_upper())
		var state: String = _run_state.car_power_state(car)
		var state_code: String = {
			"active": "ON",
			"throttled": "LOW",
			"offline": "OFF",
			"standby": "STBY",
			"producing": "GEN",
			"destroyed": "DEST",
			"passive": "PASS"
		}.get(state, state.to_upper())
		var compact_state_code: String = {
			"active": "ON",
			"throttled": "LOW",
			"offline": "OFF",
			"standby": "S",
			"producing": "G",
			"destroyed": "X",
			"passive": "P"
		}.get(state, state_code)
		parts.append("%s %d %s" % [short_name, int(car.get("hp", 0)), state_code])
		compact_parts.append(
			"%s%d %s" % [
				short_name,
				int(car.get("hp", 0)),
				compact_state_code
			]
		)
	if _compact_layout and compact_parts.size() > 2:
		return "CONSIST  %s\n%s" % [
			" | ".join(compact_parts.slice(0, 2)),
			" | ".join(compact_parts.slice(2))
		]
	return "CONSIST  " + (" | ".join(parts) if not parts.is_empty() else "LOCOMOTIVE ONLY")


func _active_crew_status() -> String:
	var active: Array[String] = []
	for member_variant in _run_state.crew:
		var member: Dictionary = member_variant
		if not _run_state.is_crew_active(member):
			continue
		match String(member.get("id", "")):
			"mara":
				active.append("Mara: speed")
			"ilo":
				active.append("Ilo: gunnery")
			"sable":
				active.append("Sable: rations")
			"orrin":
				active.append("Orrin: repairs")
	if active.is_empty():
		return "CREW BONUSES: none active"
	if _compact_layout:
		return "CREW  " + " | ".join(active.map(func(value: String) -> String:
			return value.get_slice(":", 0)
		))
	return "CREW BONUSES  " + " | ".join(active)


func _power_status(stats: TrainStats) -> String:
	if _run_state.brownout_active:
		var shed: Array[String] = []
		for role in ["engine", "light", "defense", "repair", "support"]:
			var state: String = stats.system_state(role)
			if state == "offline" or state == "throttled":
				shed.append(
					"%s %s" % [
						"greenhouse" if role == "support" else role,
						state
					]
				)
		return "BROWNOUT %+.1f recovery | full %+.1f | %s" % [
			stats.power_net,
			stats.requested_power_net,
			", ".join(shed) if not shed.is_empty() else "essential load only"
		]
	if stats.requested_power_net < 0.0:
		var seconds: int = maxi(
			0,
			int(ceil(_run_state.power / maxf(0.01, -stats.requested_power_net * 0.5)))
		)
		return "DRAINING - reserve about %d:%02d" % [seconds / 60, seconds % 60]
	return "POWER STABLE - full demand supplied"
