extends Control
## main.gd - Title screen and top-level scene switcher.

const GAME_WORLD_SCENE: String = "res://scenes/game_world.tscn"

@onready var _root: Control = self
var _game_world: Node = null
var _title_layer: Control


func _ready() -> void:
	theme = UITheme.build()
	set_process_input(true)
	print("[main] booting; cmdline_args=", OS.get_cmdline_args(), " user_args=", OS.get_cmdline_user_args())
	if _should_run_smoke_test():
		print("[main] running smoke test")
		# Watchdog: quit after 25s regardless in case a subsystem hangs.
		var t: Timer = Timer.new()
		t.wait_time = 25.0
		t.one_shot = true
		t.autostart = true
		t.timeout.connect(func() -> void:
			printerr("[main] smoke watchdog fired")
			get_tree().quit(3))
		add_child(t)
		call_deferred("_run_smoke_test")
		return
	if _should_run_runtime_probe():
		print("[main] running runtime probe")
		var t2: Timer = Timer.new()
		t2.wait_time = 20.0
		t2.one_shot = true
		t2.autostart = true
		t2.timeout.connect(func() -> void:
			printerr("[main] probe watchdog fired")
			get_tree().quit(7))
		add_child(t2)
		var probe: Node = load("res://scripts/run/runtime_probe.gd").new()
		add_child(probe)
		return
	_build_title()


func _should_run_smoke_test() -> bool:
	if OS.has_environment("LANTERN_SMOKE"):
		return true
	var args: PackedStringArray = OS.get_cmdline_args()
	for a in args:
		if a == "--smoke-test" or a == "smoke-test":
			return true
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for a in user_args:
		if a == "--smoke-test" or a == "smoke-test":
			return true
	return false


func _should_run_runtime_probe() -> bool:
	if OS.has_environment("LANTERN_PROBE"):
		return true
	var args: PackedStringArray = OS.get_cmdline_args()
	for a in args:
		if a == "--runtime-probe":
			return true
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for a in user_args:
		if a == "--runtime-probe":
			return true
	return false


func _build_title() -> void:
	_title_layer = Control.new()
	_title_layer.anchor_right = 1.0
	_title_layer.anchor_bottom = 1.0
	_title_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_title_layer)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_title_layer.add_child(bg)

	var draw_layer: TitleDrawLayer = TitleDrawLayer.new()
	draw_layer.anchor_right = 1.0
	draw_layer.anchor_bottom = 1.0
	_title_layer.add_child(draw_layer)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -240
	vbox.offset_top = -160
	vbox.offset_right = 240
	vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_title_layer.add_child(vbox)

	var title: Label = Label.new()
	title.text = "THE LANTERN LINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.58))
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "A fortress-train survival prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(subtitle)

	var brief: Label = Label.new()
	brief.text = "Aim the headlight. Choose the route. Manage power, cars, and crew.\nDetach the rear car when the darkness demands sacrifice. Reach the Dawn Beacon."
	brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(480, 60)
	brief.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	vbox.add_child(brief)

	var meta: Label = Label.new()
	var best: float = float(GameManager.meta.get("best_distance", 0.0))
	var wins: int = int(GameManager.meta.get("wins", 0))
	var runs: int = int(GameManager.meta.get("runs", 0))
	meta.text = "Best distance: %d m   |   Wins: %d   |   Runs: %d" % [int(best), wins, runs]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(meta)

	var new_run_button: Button = Button.new()
	new_run_button.text = "  New Run  "
	new_run_button.custom_minimum_size = Vector2(220, 40)
	new_run_button.pressed.connect(_on_new_run)
	vbox.add_child(new_run_button)

	if GameManager.has_continue():
		var continue_button: Button = Button.new()
		continue_button.text = "  Continue  "
		continue_button.custom_minimum_size = Vector2(220, 40)
		continue_button.pressed.connect(_on_continue)
		vbox.add_child(continue_button)

	var options_hint: Label = Label.new()
	options_hint.text = "Controls: Mouse aims light  |  1/2/3 lens  |  Q/W/E/R power priority\nSpace pause  |  T speed toggle  |  X detach rear  |  Up/Right/Down for route reveals"
	options_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_hint.custom_minimum_size = Vector2(480, 40)
	options_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	vbox.add_child(options_hint)

	var settings_row: HBoxContainer = HBoxContainer.new()
	settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	settings_row.add_theme_constant_override("separation", 12)
	vbox.add_child(settings_row)

	var vol_label: Label = Label.new()
	vol_label.text = "Volume"
	settings_row.add_child(vol_label)
	var vol_slider: HSlider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = float(GameManager.get_setting("master_volume", 0.8))
	vol_slider.custom_minimum_size = Vector2(120, 20)
	vol_slider.value_changed.connect(func(v: float) -> void:
		GameManager.set_setting("master_volume", v))
	settings_row.add_child(vol_slider)

	var shake_toggle: CheckBox = CheckBox.new()
	shake_toggle.text = "Screen shake"
	shake_toggle.button_pressed = bool(GameManager.get_setting("screen_shake", true))
	shake_toggle.toggled.connect(func(p: bool) -> void:
		GameManager.set_setting("screen_shake", p))
	settings_row.add_child(shake_toggle)

	var motion_toggle: CheckBox = CheckBox.new()
	motion_toggle.text = "Reduced motion"
	motion_toggle.button_pressed = bool(GameManager.get_setting("reduced_motion", false))
	motion_toggle.toggled.connect(func(p: bool) -> void:
		GameManager.set_setting("reduced_motion", p))
	settings_row.add_child(motion_toggle)


func _on_new_run() -> void:
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	GameManager.clear_run_checkpoint()
	_start_run(Time.get_ticks_msec(), {})


func _on_continue() -> void:
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	var snap: Dictionary = GameManager.peek_run_checkpoint()
	var seed: int = int(snap.get("run_seed", Time.get_ticks_msec()))
	_start_run(seed, snap)


func _start_run(run_seed: int, resume: Dictionary) -> void:
	if _title_layer:
		_title_layer.queue_free()
		_title_layer = null
	var scene: PackedScene = load(GAME_WORLD_SCENE)
	_game_world = scene.instantiate()
	add_child(_game_world)
	_game_world.call("bootstrap", run_seed, resume)
	if _game_world.has_signal("run_ended"):
		_game_world.connect("run_ended", _on_run_ended)


func _on_run_ended(_victory: bool) -> void:
	if _game_world:
		_game_world.queue_free()
		_game_world = null
	_build_title()


func _run_smoke_test() -> void:
	var smoke: Node = load("res://scripts/run/smoke_test.gd").new()
	add_child(smoke)
	smoke.call("run", self)


class TitleDrawLayer extends Control:
	var _t: float = 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s: Vector2 = size
		if s.x <= 0 or s.y <= 0:
			return
		# distant silhouette line
		var ridge: PackedVector2Array = PackedVector2Array()
		ridge.append(Vector2(0, s.y * 0.72))
		var steps: int = 24
		for i in range(steps + 1):
			var x: float = s.x * float(i) / float(steps)
			var y: float = s.y * 0.62 + sin(_t * 0.3 + i * 0.6) * 12.0 + cos(i * 1.3) * 20.0
			ridge.append(Vector2(x, y))
		ridge.append(Vector2(s.x, s.y * 0.72))
		ridge.append(Vector2(s.x, s.y))
		ridge.append(Vector2(0, s.y))
		draw_colored_polygon(ridge, Color(0.09, 0.10, 0.13))
		# rails
		draw_line(Vector2(0, s.y * 0.8), Vector2(s.x, s.y * 0.8), Color(0.16, 0.14, 0.12), 2.0)
		draw_line(Vector2(0, s.y * 0.85), Vector2(s.x, s.y * 0.85), Color(0.14, 0.12, 0.10), 2.0)
		# distant lantern
		var lx: float = s.x * 0.5 + sin(_t * 0.5) * 6.0
		var ly: float = s.y * 0.55
		draw_circle(Vector2(lx, ly), 3.0, Color(1.0, 0.85, 0.55, 0.85))
		for r in range(3):
			draw_circle(Vector2(lx, ly), 6.0 + r * 6.0, Color(1.0, 0.85, 0.55, 0.08 - r * 0.02))
