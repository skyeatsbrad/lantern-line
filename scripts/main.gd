extends Control
## main.gd - Title screen and top-level scene switcher.

const GAME_WORLD_SCENE: String = "res://scenes/game_world.tscn"

@onready var _root: Control = self
var _game_world: Node = null
var _title_layer: Control
var _settings_panel: SettingsPanel
var _guide_panel: GuidePanel
var _pending_new_run_seed: int = 0


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
	theme = UITheme.build()
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
	vbox.offset_left = -320
	vbox.offset_top = -250
	vbox.offset_right = 320
	vbox.offset_bottom = 250
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_title_layer.add_child(vbox)

	var title: Label = Label.new()
	title.text = "THE LANTERN LINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.font_size(48))
	title.add_theme_color_override("font_color", UITheme.accent_color())
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "A fortress-train survival strategy game - v0.5"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", UITheme.font_size(16))
	subtitle.add_theme_color_override("font_color", UITheme.muted_text_color())
	vbox.add_child(subtitle)

	var brief: Label = Label.new()
	brief.text = "Aim the headlight. Choose the route. Manage power, cars, and crew.\nDetach the rear car when the darkness demands sacrifice. Reach the Dawn Beacon."
	brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(620, 60)
	brief.add_theme_font_size_override("font_size", UITheme.font_size(14))
	brief.add_theme_color_override("font_color", UITheme.muted_text_color())
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
	options_hint.text = "Mouse aim  |  1/2/3 lens  |  F Focus  |  C Salvo  |  T pace  |  Space pause\nH Conductor's Guide  |  Escape Accessibility & Presentation"
	options_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_hint.custom_minimum_size = Vector2(620, 40)
	options_hint.add_theme_color_override("font_color", UITheme.muted_text_color())
	vbox.add_child(options_hint)

	var utility_row := HBoxContainer.new()
	utility_row.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_row.add_theme_constant_override("separation", 10)
	vbox.add_child(utility_row)
	var guide_button := Button.new()
	guide_button.text = "Conductor's Guide"
	guide_button.custom_minimum_size = Vector2(190.0, 40.0)
	guide_button.pressed.connect(func() -> void: _show_guide("Close Guide"))
	utility_row.add_child(guide_button)
	var settings_button := Button.new()
	settings_button.text = "Accessibility & Presentation"
	settings_button.custom_minimum_size = Vector2(230.0, 40.0)
	settings_button.pressed.connect(_show_settings)
	utility_row.add_child(settings_button)


func _on_new_run() -> void:
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	GameManager.clear_run_checkpoint()
	var seed := Time.get_ticks_msec()
	if not bool(GameManager.get_setting("tutorial_seen", false)):
		_pending_new_run_seed = seed
		_show_guide("Begin Run")
		return
	_start_run(seed, {})


func _on_continue() -> void:
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	var snap: Dictionary = GameManager.peek_run_checkpoint()
	var run_data: Dictionary = RunSnapshot.run_state_data(snap)
	var seed: int = int(run_data.get("run_seed", Time.get_ticks_msec()))
	_start_run(seed, snap)


func _start_run(run_seed: int, resume: Dictionary) -> void:
	_pending_new_run_seed = 0
	_close_title_overlays()
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


func _show_settings() -> void:
	AudioManager.notify_user_gesture()
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.guide_requested.connect(_on_title_settings_guide_requested)
	_settings_panel.present()


func _show_guide(completion_label: String = "Close Guide") -> void:
	AudioManager.notify_user_gesture()
	if is_instance_valid(_guide_panel):
		_guide_panel.queue_free()
	_guide_panel = GuidePanel.new()
	add_child(_guide_panel)
	_guide_panel.closed.connect(_on_guide_closed)
	_guide_panel.present(completion_label)


func _on_settings_closed() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
	_settings_panel = null
	_rebuild_title()


func _on_title_settings_guide_requested() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
	_show_guide("Close Guide")


func _on_guide_closed() -> void:
	if is_instance_valid(_guide_panel):
		_guide_panel.queue_free()
	_guide_panel = null
	if _pending_new_run_seed != 0:
		var seed := _pending_new_run_seed
		_pending_new_run_seed = 0
		_start_run(seed, {})


func _input(event: InputEvent) -> void:
	if _game_world != null:
		return
	if (
		is_instance_valid(_settings_panel)
		or is_instance_valid(_guide_panel)
	):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("open_guide"):
		get_viewport().set_input_as_handled()
		_show_guide("Close Guide")
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_show_settings()


func _rebuild_title() -> void:
	if _game_world != null:
		return
	if is_instance_valid(_title_layer):
		remove_child(_title_layer)
		_title_layer.queue_free()
		_title_layer = null
	_build_title()


func _close_title_overlays() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
	if is_instance_valid(_guide_panel):
		_guide_panel.queue_free()
		_guide_panel = null


func _run_smoke_test() -> void:
	var smoke: Node = load("res://scripts/run/smoke_test.gd").new()
	add_child(smoke)
	smoke.call("run", self)


class TitleDrawLayer extends Control:
	var _t: float = 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		if not bool(GameManager.get_setting("reduced_motion", false)):
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
