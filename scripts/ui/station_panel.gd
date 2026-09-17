class_name StationPanel
extends Control
## StationPanel
##
## Modal for the one station in this prototype: add, repair, or dismiss.

signal add_car(type_key: String)
signal repair_all()
signal reorder_cars()
signal closed()

var _run_state: RunState
var _open: bool = false


func present(run_state: RunState) -> void:
	_run_state = run_state
	_build()
	visible = true
	_open = true
	AudioManager.play("reveal")


func _build() -> void:
	theme = UITheme.build()
	for c in get_children():
		c.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var box: PanelContainer = PanelContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -360
	box.offset_right = 360
	box.offset_top = -220
	box.offset_bottom = 220
	add_child(box)
	var v: VBoxContainer = VBoxContainer.new()
	box.add_child(v)
	v.add_theme_constant_override("separation", 8)

	var t: Label = Label.new()
	t.text = "STATION: WAYPOST FIVE"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	v.add_child(t)

	var d: Label = Label.new()
	var order_names: PackedStringArray = PackedStringArray()
	for car in _run_state.cars:
		order_names.append(String(car.get("display", car.get("type", "?"))))
	d.text = "A lit platform in the ink. A quartermaster studies your consist.\nScrap: %d   Supplies: %d   Cars: %d/5\nLoco > %s > Rear" % [int(_run_state.scrap), int(_run_state.supplies), _run_state.cars.size(), " > ".join(order_names)]
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	v.add_child(d)

	# Add car row
	var add_title: Label = Label.new()
	add_title.text = "Add a car   (10 scrap each; max 5)"
	add_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	v.add_child(add_title)
	var row: GridContainer = GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	for key in _run_state.cars_config.keys():
		var b: Button = Button.new()
		var display: String = String(_run_state.cars_config[key].get("display", key))
		b.text = display
		b.custom_minimum_size = Vector2(190, 38)
		b.disabled = _run_state.scrap < 10.0 or _run_state.cars.size() >= 5
		var kk: String = String(key)
		b.pressed.connect(func() -> void: _try_add(kk))
		row.add_child(b)

	var repair_btn: Button = Button.new()
	repair_btn.text = "Full Repair (12 scrap)"
	repair_btn.disabled = _run_state.scrap < 12.0
	repair_btn.pressed.connect(_try_repair)
	v.add_child(repair_btn)

	var reorder_btn: Button = Button.new()
	reorder_btn.text = "Move rear car next to locomotive (free)"
	reorder_btn.disabled = _run_state.cars.size() < 2
	reorder_btn.pressed.connect(_try_reorder)
	v.add_child(reorder_btn)

	var crew_text: PackedStringArray = PackedStringArray()
	for member in _run_state.crew:
		crew_text.append("%s: %s" % [String(member.get("name", "?")), String(member.get("assigned_role", "?")).capitalize()])
	var crew_label: Label = Label.new()
	crew_label.text = "Crew posts: " + "  |  ".join(crew_text)
	crew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crew_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	v.add_child(crew_label)

	var leave_btn: Button = Button.new()
	leave_btn.text = "Leave Station"
	leave_btn.pressed.connect(_close)
	v.add_child(leave_btn)


func _try_add(type_key: String) -> void:
	if _run_state.scrap < 10.0:
		AudioManager.play("alarm")
		return
	if _run_state.cars.size() >= 5:
		AudioManager.play("alarm")
		return
	_run_state.scrap -= 10.0
	emit_signal("add_car", type_key)
	AudioManager.play("click")
	_build()


func _try_repair() -> void:
	if _run_state.scrap < 12.0:
		AudioManager.play("alarm")
		return
	_run_state.scrap -= 12.0
	emit_signal("repair_all")
	AudioManager.play("click")
	_build()


func _try_reorder() -> void:
	if _run_state.cars.size() < 2:
		return
	emit_signal("reorder_cars")
	AudioManager.play("click")
	_build()


func _close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	AudioManager.play("click")
	emit_signal("closed")
