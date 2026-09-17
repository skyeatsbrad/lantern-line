class_name EndScreen
extends Control
## EndScreen
##
## Victory/defeat overlay. Returns via signal 'closed'.

signal closed()

var _victory: bool = false


func show_end(victory: bool, run_state: RunState) -> void:
	theme = UITheme.build()
	_victory = victory
	for c in get_children():
		c.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = true

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var v: VBoxContainer = VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -280
	v.offset_right = 280
	v.offset_top = -160
	v.offset_bottom = 180
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)

	var title: Label = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	if victory:
		title.text = "DAWN BEACON REACHED"
		title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	else:
		title.text = "THE LINE ENDS HERE"
		title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	v.add_child(title)

	var body: Label = Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 100)
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	if victory:
		body.text = "The pale sky opens. Warm light finds the rails. Your cars roll into the beacon and stop, breathing steam like grateful animals."
	else:
		body.text = "The lantern falters. The train drifts. In the dark, the quiet is complete. Somebody remembers your distance mark and lifts a lantern for the next crew."
	v.add_child(body)

	var stat: Label = Label.new()
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.text = "Distance: %d m   |   Time: %02d:%02d   |   Seed: %d" % [
		int(run_state.distance),
		int(run_state.travel_time) / 60,
		int(run_state.travel_time) % 60,
		run_state.run_seed
	]
	stat.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	v.add_child(stat)

	var btn: Button = Button.new()
	btn.text = "  Return to Title  "
	btn.custom_minimum_size = Vector2(220, 40)
	btn.pressed.connect(func() -> void:
		AudioManager.play("click")
		emit_signal("closed"))
	v.add_child(btn)

	if victory:
		AudioManager.play("victory")
	else:
		AudioManager.play("defeat")
