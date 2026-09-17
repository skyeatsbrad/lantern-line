class_name RouteChoice
extends Control
## RouteChoice
##
## Modal that presents three route signatures based on lens+seed.
## Player chooses by pressing Up/Middle/Down or clicking a card.
## Emits `chosen` with the picked event dictionary.

signal chosen(event: Dictionary)
signal closed()

var _choices: Array = []
var _lens_key: String = "Standard"
var _cards: Array = []
var _band_labels: Array = []
var _aim_index: int = 1
var _active: bool = false


func present(choices: Array, lens_key: String, initial_band: String = "middle") -> void:
	_choices = choices
	_lens_key = lens_key
	_aim_index = _band_to_index(initial_band)
	_build()
	_active = true
	visible = true
	set_process_input(true)
	AudioManager.play("reveal")


func _build() -> void:
	theme = UITheme.build()
	for c in get_children():
		c.queue_free()
	_cards.clear()
	_band_labels.clear()
	anchor_right = 1.0
	anchor_bottom = 1.0
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.y < 650.0
	# dim background
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	var half_width: float = minf(420.0, viewport_size.x * 0.46)
	vbox.offset_left = -half_width
	vbox.offset_right = half_width
	vbox.offset_top = 22 if compact else 48
	vbox.offset_bottom = viewport_size.y - 18
	vbox.add_theme_constant_override("separation", 7 if compact else 12)
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "ROUTE REVEAL   (%s Lens)" % _lens_key
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21 if compact else 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Move the headlight between the three bands, then commit the illuminated route."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12 if compact else 16)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(subtitle)

	for i in range(_choices.size()):
		var ev: Dictionary = _choices[i]
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(minf(760.0, viewport_size.x - 90.0), 80 if compact else 100)
		vbox.add_child(card)
		var inner: HBoxContainer = HBoxContainer.new()
		inner.add_theme_constant_override("separation", 12)
		card.add_child(inner)
		var pos_lbl: Label = Label.new()
		var pos_txt: String = String(ev.get("position", "middle")).to_upper()
		pos_lbl.text = "[%s]" % pos_txt
		pos_lbl.custom_minimum_size = Vector2(110, 54)
		pos_lbl.add_theme_font_size_override("font_size", 15 if compact else 18)
		pos_lbl.add_theme_color_override("font_color", _category_color(String(ev.get("category", "living"))))
		inner.add_child(pos_lbl)

		var body: VBoxContainer = VBoxContainer.new()
		inner.add_child(body)
		var t: Label = Label.new()
		t.text = String(ev.get("title", "?"))
		t.add_theme_font_size_override("font_size", 15 if compact else 18)
		t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		body.add_child(t)
		var d: Label = Label.new()
		d.text = String(ev.get("description", ""))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(390 if compact else 500, 18)
		d.add_theme_font_size_override("font_size", 11 if compact else 14)
		d.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		body.add_child(d)
		var reward_line: String = _format_rewards(ev)
		var r: Label = Label.new()
		r.text = reward_line
		r.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
		body.add_child(r)

		var choose: Button = Button.new()
		choose.text = "Commit beam"
		choose.custom_minimum_size = Vector2(105, 36)
		var idx_local: int = i
		choose.pressed.connect(func() -> void: _select(idx_local))
		inner.add_child(choose)

		_cards.append(card)
		_band_labels.append(pos_lbl)
	_refresh_aim_highlight()


func _format_rewards(ev: Dictionary) -> String:
	var parts: Array = []
	var rewards: Dictionary = ev.get("rewards", {})
	for k in rewards.keys():
		parts.append("%s %s%s" % [String(k).capitalize(), ("+" if float(rewards[k]) >= 0 else ""), str(rewards[k])])
	var d: int = int(ev.get("danger", 0))
	if d > 0:
		parts.append("Danger %s" % "★".repeat(d))
	return "  |  ".join(parts)


func _category_color(cat: String) -> Color:
	match cat:
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


func set_aim_band(band: String) -> void:
	var next_index: int = _band_to_index(band)
	if next_index == _aim_index:
		return
	_aim_index = next_index
	_refresh_aim_highlight()


func _band_to_index(band: String) -> int:
	match band:
		"upper":
			return 0
		"lower":
			return 2
		_:
			return 1


func _refresh_aim_highlight() -> void:
	for index in range(_cards.size()):
		var selected: bool = index == _aim_index
		(_cards[index] as CanvasItem).modulate = Color.WHITE if selected else Color(0.58, 0.58, 0.64)
		var label: Label = _band_labels[index] as Label
		var position_name: String = String(_choices[index].get("position", "middle")).to_upper()
		label.text = ("> %s  BEAM" % position_name) if selected else ("[%s]" % position_name)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("choose_upper"):
		set_aim_band("upper")
		_select(0)
	elif event.is_action_pressed("choose_middle"):
		set_aim_band("middle")
		_select(1)
	elif event.is_action_pressed("choose_lower"):
		set_aim_band("lower")
		_select(2)
	elif event.is_action_pressed("ui_accept"):
		_select(_aim_index)
