class_name HUD
extends Control
## HUD
##
## Railway-equipment styled interface. Not color-only: text + icons + bars.

signal request_lens(name: String)
signal request_priority_cycle(role: String)
signal request_pause()
signal request_speed()
signal request_detach()

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
var _prio_labels: Dictionary = {}
@onready var _notification_label: Label
@onready var _hint_label: Label
@onready var _loco_bar: ProgressBar


func setup(run_state: RunState, lens_config: Dictionary) -> void:
	_run_state = run_state
	_lens_config = lens_config
	_build_ui()
	_run_state.resources_changed.connect(_refresh)
	_run_state.power_changed.connect(_refresh)
	_run_state.locomotive_damaged.connect(func(_hp: float) -> void: _refresh())
	_refresh()
	set_process(true)


func _build_ui() -> void:
	theme = UITheme.build()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	var text_scale: float = float(GameManager.get_setting("text_scale", 1.0))
	var base_font_size: int = int(14 * text_scale)
	var viewport_size: Vector2 = get_viewport_rect().size
	_compact_layout = viewport_size.x < 1100.0 or viewport_size.y < 620.0
	if _compact_layout:
		base_font_size = mini(base_font_size, 12)
	var bottom_height: float = 142.0 if _compact_layout else 128.0

	# Top-left: distance and time
	var top: PanelContainer = PanelContainer.new()
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.offset_left = 12
	top.offset_top = 12
	top.offset_right = 280 if _compact_layout else 320
	top.offset_bottom = 84
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
	right.offset_left = -230 if _compact_layout else -260
	right.offset_top = 12
	right.offset_right = -12
	right.offset_bottom = 200
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	var rvbox: VBoxContainer = VBoxContainer.new()
	right.add_child(rvbox)
	rvbox.add_theme_constant_override("separation", 4)
	_bars["power"] = _make_bar(rvbox, "Power", Color(0.95, 0.85, 0.3), base_font_size)
	_bars["scrap"] = _make_bar(rvbox, "Scrap", Color(0.7, 0.6, 0.5), base_font_size)
	_bars["supplies"] = _make_bar(rvbox, "Supplies", Color(0.55, 0.85, 0.5), base_font_size)
	_bars["lumen"] = _make_bar(rvbox, "Lumen", Color(1.0, 0.86, 0.62), base_font_size)

	# Locomotive HP visible top center under title
	var mid: PanelContainer = PanelContainer.new()
	mid.anchor_left = 0.5
	mid.anchor_right = 0.5
	mid.offset_left = -110 if _compact_layout else -140
	mid.offset_right = 110 if _compact_layout else 140
	mid.offset_top = 12
	mid.offset_bottom = 56
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

	# Bottom-left: lens breaker panel
	var lens_panel: PanelContainer = PanelContainer.new()
	lens_panel.anchor_right = 0.26
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
		b.text = "%s" % [String(lens_key)]
		b.custom_minimum_size = Vector2(65 if _compact_layout else 90, 30)
		var lk: String = String(lens_key)
		b.pressed.connect(func() -> void: emit_signal("request_lens", lk))
		lens_row.add_child(b)
	_lens_label = Label.new()
	_lens_label.add_theme_font_size_override("font_size", base_font_size)
	lens_v.add_child(_lens_label)

	# Bottom-center: priorities (Q/W/E/R)
	var prio: PanelContainer = PanelContainer.new()
	prio.anchor_left = 0.26
	prio.anchor_right = 0.76
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
		var b: Button = Button.new()
		b.text = role.capitalize()
		b.custom_minimum_size = Vector2(82 if _compact_layout else 110, 30)
		var rk: String = role
		b.pressed.connect(func() -> void: emit_signal("request_priority_cycle", rk))
		col.add_child(b)
		var lbl: Label = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", base_font_size)
		col.add_child(lbl)
		_prio_labels[role] = lbl

	# Bottom-right: pause / speed / detach
	var ctrl: PanelContainer = PanelContainer.new()
	ctrl.anchor_left = 0.76
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
	ctrl_title.text = "CONTROL"
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
	var detach_btn: Button = Button.new()
	detach_btn.text = "Detach rear (X)"
	detach_btn.pressed.connect(func() -> void: emit_signal("request_detach"))
	ctrl_v.add_child(detach_btn)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", base_font_size - 2)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	ctrl_v.add_child(_hint_label)

	# Center notification
	_notification_label = Label.new()
	_notification_label.anchor_left = 0.5
	_notification_label.anchor_right = 0.5
	_notification_label.anchor_top = 0.2
	_notification_label.anchor_bottom = 0.2
	_notification_label.offset_left = -240
	_notification_label.offset_right = 240
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_font_size_override("font_size", base_font_size + 6)
	_notification_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	add_child(_notification_label)


func _make_bar(parent: Node, label: String, col: Color, font_size: int) -> Dictionary:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	row.add_theme_constant_override("separation", 6)
	var lbl: Label = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(70, 16)
	lbl.add_theme_font_size_override("font_size", font_size)
	row.add_child(lbl)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(94 if _compact_layout else 120, 12)
	bar.modulate = col
	row.add_child(bar)
	var val: Label = Label.new()
	val.custom_minimum_size = Vector2(46, 16)
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
	_time_label.text = "Time: %02d:%02d   %sx  %s" % [m, s, str(_run_state.speed_scale), ("[PAUSED]" if _run_state.paused else "")]
	_lens_label.text = "Active: %s   (cd %.1fs)" % [_run_state.current_lens, _run_state.lens_cooldown]
	_hint_label.text = ("Mouse aim | 1-3 lens | X detach" if _compact_layout else "Aim: mouse   1/2/3 lens   X detach") + "   [%s]" % ("2x" if _run_state.speed_scale >= 2.0 else "1x")
	_notification_timer = maxf(0.0, _notification_timer - delta)
	if _notification_timer <= 0.0:
		_notification_label.text = ""


func _refresh() -> void:
	if _run_state == null:
		return
	# Resource bars/values
	_bars["power"]["bar"].value = clampf(_run_state.power / 12.0, 0.0, 1.0) * 100.0
	_bars["power"]["value"].text = "%0.1f" % _run_state.power
	_bars["scrap"]["bar"].value = clampf(_run_state.scrap / 60.0, 0.0, 1.0) * 100.0
	_bars["scrap"]["value"].text = "%d" % int(_run_state.scrap)
	_bars["supplies"]["bar"].value = clampf(_run_state.supplies / 120.0, 0.0, 1.0) * 100.0
	_bars["supplies"]["value"].text = "%d" % int(_run_state.supplies)
	_bars["lumen"]["bar"].value = clampf(_run_state.lumen / 40.0, 0.0, 1.0) * 100.0
	_bars["lumen"]["value"].text = "%d" % int(_run_state.lumen)
	# priorities
	for role in ["engine", "light", "defense", "repair"]:
		var v: int = int(_run_state.priorities[role])
		_prio_labels[role].text = "Lv %d" % v
		var col: Color = Color(0.8, 0.8, 0.8)
		if v == 0:
			col = Color(0.5, 0.5, 0.5)
		elif v == 1:
			col = Color(0.95, 0.85, 0.5)
		elif v == 2:
			col = Color(0.95, 0.65, 0.35)
		elif v == 3:
			col = Color(0.95, 0.35, 0.35)
		_prio_labels[role].add_theme_color_override("font_color", col)
	# locomotive
	_loco_bar.value = _run_state.locomotive_hp / _run_state.locomotive_max_hp * 100.0


func flash(msg: String, duration: float = 2.0) -> void:
	_notification_label.text = msg
	_notification_timer = duration
