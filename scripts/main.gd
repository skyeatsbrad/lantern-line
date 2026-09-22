extends Control
## main.gd - Title screen and top-level scene switcher.

const GAME_WORLD_SCENE: String = "res://scenes/game_world.tscn"
const SCENE_FADE_SECONDS: float = 0.28
const REDUCED_SCENE_FADE_SECONDS: float = 0.12

@onready var _root: Control = self
var _game_world: Node = null
var _title_layer: Control
var _settings_panel: SettingsPanel
var _guide_panel: GuidePanel
var _pending_new_run_seed: int = 0
var _capture_saved_settings: Dictionary = {}
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _scene_transitioning: bool = false


func _ready() -> void:
	var capture_path: String = OS.get_environment("LANTERN_CAPTURE_TITLE")
	if not capture_path.is_empty():
		_prepare_title_capture()
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
	if not get_viewport().size_changed.is_connected(_on_title_viewport_changed):
		get_viewport().size_changed.connect(_on_title_viewport_changed)
	_build_title()
	if not capture_path.is_empty():
		var capture_watchdog := Timer.new()
		capture_watchdog.wait_time = 6.0
		capture_watchdog.one_shot = true
		capture_watchdog.autostart = true
		capture_watchdog.timeout.connect(_on_title_capture_timeout)
		add_child(capture_watchdog)
		call_deferred("_capture_title", capture_path)


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
	if (
		OS.has_environment("LANTERN_PROBE")
		or not OS.get_environment("LANTERN_CAPTURE_GAMEPLAY").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_TRAIN_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_ROUTE_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_COMBAT_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_BOSS_SHOWCASE").is_empty()
		or not OS.get_environment("LANTERN_CAPTURE_UI_SHOWCASE").is_empty()
		or OS.has_environment("LANTERN_PROBE_DENSE_COMBAT")
		or OS.has_environment("LANTERN_PROBE_AUDIO")
	):
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
	AudioManager.set_presentation_state({
		"mode": "title",
		"music_state": "title",
		"tension": 0.0
	})
	_title_layer = Control.new()
	_title_layer.anchor_right = 1.0
	_title_layer.anchor_bottom = 1.0
	_title_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_title_layer)

	var bg: ColorRect = ColorRect.new()
	bg.color = PresentationPalette.NIGHT_VOID
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_title_layer.add_child(bg)

	var draw_layer: TitleDrawLayer = TitleDrawLayer.new()
	draw_layer.anchor_right = 1.0
	draw_layer.anchor_bottom = 1.0
	_title_layer.add_child(draw_layer)

	var vbox: VBoxContainer = VBoxContainer.new()
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = UITheme.compact_layout(viewport_size)
	var half_width: float = minf(360.0, viewport_size.x * 0.46)
	var half_height: float = minf(
		310.0 if compact else 250.0,
		viewport_size.y * 0.47
	)
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -half_width
	vbox.offset_top = -half_height
	vbox.offset_right = half_width
	vbox.offset_bottom = half_height
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 7 if compact else 12)
	_title_layer.add_child(vbox)

	var title: Label = Label.new()
	title.text = "THE LANTERN LINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(36 if compact else 48)
	)
	title.add_theme_color_override("font_color", UITheme.accent_color())
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "A fortress-train survival strategy game - v0.7"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", UITheme.bold_font())
	subtitle.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(13 if compact else 16)
	)
	subtitle.add_theme_color_override("font_color", UITheme.muted_text_color())
	vbox.add_child(subtitle)

	var brief: Label = Label.new()
	brief.text = "Aim the headlight. Choose the route. Manage power, cars, and crew.\nDetach the rear car when the darkness demands sacrifice. Reach the Dawn Beacon."
	brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(half_width * 1.9, 46 if compact else 60)
	brief.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(12 if compact else 14)
	)
	brief.add_theme_color_override("font_color", UITheme.muted_text_color())
	vbox.add_child(brief)

	var meta: Label = Label.new()
	var best: float = float(GameManager.meta.get("best_distance", 0.0))
	var wins: int = int(GameManager.meta.get("wins", 0))
	var runs: int = int(GameManager.meta.get("runs", 0))
	meta.text = "Best distance: %d m   |   Wins: %d   |   Runs: %d" % [int(best), wins, runs]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_color_override("font_color", UITheme.muted_text_color())
	vbox.add_child(meta)

	var new_run_button: Button = Button.new()
	new_run_button.text = "  New Run  "
	new_run_button.custom_minimum_size = Vector2(220, 40)
	new_run_button.pressed.connect(_on_new_run)
	vbox.add_child(new_run_button)
	new_run_button.call_deferred("grab_focus")

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
	options_hint.custom_minimum_size = Vector2(half_width * 1.9, 34 if compact else 40)
	options_hint.add_theme_font_size_override(
		"font_size",
		UITheme.font_size(10 if compact else 14)
	)
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
	if _scene_transitioning:
		return
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	GameManager.clear_run_checkpoint()
	var seed := Time.get_ticks_msec()
	if not bool(GameManager.get_setting("tutorial_seen", false)):
		_pending_new_run_seed = seed
		_show_guide("Begin Run", true)
		return
	_start_run(seed, {})


func _on_continue() -> void:
	if _scene_transitioning:
		return
	AudioManager.notify_user_gesture()
	AudioManager.play("click")
	var snap: Dictionary = GameManager.peek_run_checkpoint()
	var run_data: Dictionary = RunSnapshot.run_state_data(snap)
	var seed: int = int(run_data.get("run_seed", Time.get_ticks_msec()))
	_start_run(seed, snap)


func _start_run(run_seed: int, resume: Dictionary) -> void:
	if _scene_transitioning:
		return
	_scene_transitioning = true
	_pending_new_run_seed = 0
	AudioManager.play("departure")
	_close_title_overlays()
	await _fade_scene(true)
	if _title_layer:
		_title_layer.queue_free()
		_title_layer = null
	var scene: PackedScene = load(GAME_WORLD_SCENE)
	_game_world = scene.instantiate()
	add_child(_game_world)
	_game_world.call("bootstrap", run_seed, resume)
	if _game_world.has_signal("run_ended"):
		_game_world.connect("run_ended", _on_run_ended)
	await get_tree().process_frame
	await _fade_scene(false)
	_scene_transitioning = false


func _on_run_ended(_victory: bool) -> void:
	if _scene_transitioning:
		return
	_scene_transitioning = true
	await _fade_scene(true)
	if _game_world:
		_game_world.queue_free()
		_game_world = null
	_build_title()
	await get_tree().process_frame
	await _fade_scene(false)
	_scene_transitioning = false


func _fade_scene(to_black: bool) -> void:
	if not is_instance_valid(_transition_layer):
		_transition_layer = CanvasLayer.new()
		_transition_layer.layer = 100
		add_child(_transition_layer)
		_transition_rect = ColorRect.new()
		_transition_rect.color = PresentationPalette.NIGHT_VOID
		_transition_rect.anchor_right = 1.0
		_transition_rect.anchor_bottom = 1.0
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_transition_layer.add_child(_transition_rect)
	_transition_rect.modulate.a = 0.0 if to_black else 1.0
	var duration: float = (
		REDUCED_SCENE_FADE_SECONDS
		if bool(GameManager.get_setting("reduced_motion", false))
		else SCENE_FADE_SECONDS
	)
	var tween := _transition_rect.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN if to_black else Tween.EASE_OUT)
	tween.tween_property(
		_transition_rect,
		"modulate:a",
		1.0 if to_black else 0.0,
		duration
	)
	await tween.finished
	if not to_black and is_instance_valid(_transition_layer):
		_transition_layer.queue_free()
		_transition_layer = null
		_transition_rect = null


func _show_settings() -> void:
	AudioManager.notify_user_gesture()
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.guide_requested.connect(_on_title_settings_guide_requested)
	_settings_panel.present()


func _show_guide(
	completion_label: String = "Close Guide",
	quick_start: bool = false
) -> void:
	AudioManager.notify_user_gesture()
	if is_instance_valid(_guide_panel):
		_guide_panel.queue_free()
	_guide_panel = GuidePanel.new()
	add_child(_guide_panel)
	_guide_panel.closed.connect(_on_guide_closed)
	_guide_panel.present(completion_label, quick_start)


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
	if _scene_transitioning:
		return
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


func _on_title_viewport_changed() -> void:
	if (
		_game_world == null
		and not _scene_transitioning
		and not is_instance_valid(_settings_panel)
		and not is_instance_valid(_guide_panel)
	):
		_rebuild_title()


func _close_title_overlays() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
	if is_instance_valid(_guide_panel):
		_guide_panel.queue_free()
		_guide_panel = null


func _prepare_title_capture() -> void:
	_capture_saved_settings = GameManager.settings.duplicate(true)
	if OS.has_environment("LANTERN_CAPTURE_ACCESSIBLE"):
		GameManager.settings["text_scale"] = 1.3
		GameManager.settings["high_contrast"] = true
		GameManager.settings["reduced_motion"] = true
		GameManager.settings["reduced_flashes"] = true
		GameManager.settings["screen_shake"] = false
	else:
		GameManager.settings["text_scale"] = 1.0
		GameManager.settings["high_contrast"] = false
		GameManager.settings["reduced_motion"] = false
		GameManager.settings["reduced_flashes"] = false
		GameManager.settings["screen_shake"] = true
	GameManager.emit_signal("settings_changed")
	if OS.has_environment("LANTERN_CAPTURE_COMPACT"):
		DisplayServer.window_set_size(Vector2i(960, 540))


func _capture_title(path: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result: Error = get_viewport().get_texture().get_image().save_png(path)
	if result == OK and FileAccess.file_exists(path):
		print("[capture] title=", path)
	else:
		if result == OK:
			result = ERR_FILE_CANT_WRITE
		printerr("[capture] title failed error=", result)
	_restore_title_capture_settings()
	get_tree().quit(0 if result == OK else 10)


func _on_title_capture_timeout() -> void:
	_restore_title_capture_settings()
	printerr("[capture] title timed out before a frame was available")
	get_tree().quit(11)


func _restore_title_capture_settings() -> void:
	if _capture_saved_settings.is_empty():
		return
	GameManager.settings = _capture_saved_settings
	_capture_saved_settings = {}
	GameManager.emit_signal("settings_changed")


func _run_smoke_test() -> void:
	var smoke: Node = load("res://scripts/run/smoke_test.gd").new()
	add_child(smoke)
	smoke.call("run", self)


class TitleDrawLayer extends Control:
	const GRAIN_TEXTURE: Texture2D = preload(
		"res://assets/generated/visual/grain.png"
	)
	const HEADLIGHT_TEXTURE: Texture2D = preload(
		"res://assets/generated/visual/headlight_falloff.png"
	)

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
		_draw_gradient(
			Rect2(Vector2.ZERO, s),
			PresentationPalette.NIGHT_VOID,
			PresentationPalette.SLATE.darkened(0.22)
		)
		_draw_ridge(s, s.y * 0.55, s.y * 0.055, PresentationPalette.COAL, 0.0)
		_draw_signal_tower(Vector2(s.x * 0.82, s.y * 0.55), s.y * 0.3)
		_draw_signal_tower(Vector2(s.x * 0.13, s.y * 0.63), s.y * 0.19)
		_draw_ridge(
			s,
			s.y * 0.66,
			s.y * 0.07,
			PresentationPalette.SLATE.darkened(0.28),
			1.7
		)
		_draw_ridge(
			s,
			s.y * 0.73,
			s.y * 0.045,
			PresentationPalette.IRON.darkened(0.4),
			3.1
		)

		var ground_y: float = s.y * 0.91
		draw_rect(
			Rect2(0.0, ground_y, s.x, s.y - ground_y),
			PresentationPalette.NIGHT_VOID
		)
		var tie_offset: float = (
			0.0
			if bool(GameManager.get_setting("reduced_motion", false))
			else fmod(_t * 44.0, 52.0)
		)
		for i in range(int(s.x / 52.0) + 2):
			var tie_x: float = float(i) * 52.0 - tie_offset
			draw_rect(
				Rect2(tie_x, ground_y + 16.0, 30.0, 4.0),
				PresentationPalette.IRON.darkened(0.35)
			)
		draw_line(
			Vector2(0.0, ground_y + 11.0),
			Vector2(s.x, ground_y + 11.0),
			PresentationPalette.IRON,
			3.0
		)
		draw_line(
			Vector2(0.0, ground_y + 27.0),
			Vector2(s.x, ground_y + 27.0),
			PresentationPalette.BRASS.darkened(0.5),
			2.0
		)

		var scale_factor: float = clampf(s.x / 1500.0, 0.6, 0.9)
		var train_anchor := Vector2(s.x * 0.39, s.y * 0.95)
		var lamp_position: Vector2 = (
			train_anchor + Vector2(67.0, -72.0) * scale_factor
		)
		var beam_size := Vector2(
			minf(s.x - lamp_position.x + 40.0, 680.0 * scale_factor),
			260.0 * scale_factor
		)
		draw_texture_rect(
			HEADLIGHT_TEXTURE,
			Rect2(
				lamp_position.x,
				lamp_position.y - beam_size.y * 0.5,
				beam_size.x,
				beam_size.y
			),
			false,
			PresentationPalette.with_alpha(&"ember", 0.72)
		)
		_draw_smoke(train_anchor, scale_factor)
		draw_set_transform(train_anchor, 0.0, Vector2.ONE * scale_factor)
		_draw_train_silhouette()
		draw_set_transform_matrix(Transform2D.IDENTITY)

		_draw_ash(s)
		draw_texture_rect(
			GRAIN_TEXTURE,
			Rect2(Vector2.ZERO, s),
			false,
			PresentationPalette.with_alpha(&"bone", 0.28)
		)

	func _draw_gradient(rect: Rect2, top: Color, bottom: Color) -> void:
		for i in range(16):
			var t0: float = float(i) / 16.0
			var t1: float = float(i + 1) / 16.0
			draw_rect(
				Rect2(
					rect.position.x,
					rect.position.y + rect.size.y * t0,
					rect.size.x,
					rect.size.y * (t1 - t0)
				),
				top.lerp(bottom, (t0 + t1) * 0.5)
			)

	func _draw_ridge(
		s: Vector2,
		base_y: float,
		amplitude: float,
		color: Color,
		phase: float
	) -> void:
		var ridge := PackedVector2Array([Vector2(0.0, s.y)])
		for i in range(29):
			var x: float = s.x * float(i) / 28.0
			var motion: float = (
				0.0
				if bool(GameManager.get_setting("reduced_motion", false))
				else _t * 0.08
			)
			var y: float = (
				base_y
				+ sin(float(i) * 0.72 + phase + motion) * amplitude
				+ cos(float(i) * 1.41 + phase) * amplitude * 0.42
			)
			ridge.append(Vector2(x, y))
		ridge.append(Vector2(s.x, s.y))
		draw_colored_polygon(ridge, color)

	func _draw_signal_tower(base: Vector2, height: float) -> void:
		var color: Color = PresentationPalette.SLATE.darkened(0.36)
		draw_rect(Rect2(base.x - 6.0, base.y - height, 12.0, height), color)
		draw_line(
			Vector2(base.x - 27.0, base.y - height * 0.78),
			Vector2(base.x + 27.0, base.y - height * 0.78),
			color,
			5.0
		)
		draw_line(
			Vector2(base.x - 20.0, base.y - height * 0.55),
			Vector2(base.x + 20.0, base.y - height * 0.55),
			color,
			4.0
		)
		draw_line(
			Vector2(base.x - 6.0, base.y - height * 0.9),
			Vector2(base.x + 6.0, base.y - height * 0.67),
			PresentationPalette.IRON.darkened(0.28),
			2.0
		)

	func _draw_smoke(anchor: Vector2, scale_factor: float) -> void:
		if bool(GameManager.get_setting("reduced_motion", false)):
			return
		for i in range(6):
			var age: float = fmod(_t * 0.28 + float(i) / 6.0, 1.0)
			var center := (
				anchor
				+ Vector2(-6.0 - age * 72.0, -104.0 - age * 88.0)
				* scale_factor
			)
			draw_circle(
				center,
				(7.0 + age * 16.0) * scale_factor,
				PresentationPalette.with_alpha(&"slate", (1.0 - age) * 0.18)
			)

	func _draw_train_silhouette() -> void:
		var brass: Color = PresentationPalette.BRASS.darkened(0.18)
		for car_index in range(3):
			var car_x: float = -306.0 + float(car_index) * 98.0
			var car_rect := Rect2(car_x, -61.0, 90.0, 47.0)
			draw_rect(car_rect, PresentationPalette.SLATE.darkened(0.16))
			draw_rect(car_rect, brass, false, 2.0)
			draw_line(
				Vector2(car_x + 3.0, -62.0),
				Vector2(car_x + 87.0, -62.0),
				PresentationPalette.BRASS,
				2.0
			)
			for window_index in range(3):
				draw_rect(
					Rect2(car_x + 13.0 + window_index * 23.0, -47.0, 11.0, 14.0),
					PresentationPalette.EMBER.darkened(0.08)
				)
			_draw_title_wheel(Vector2(car_x + 19.0, -7.0), 11.0)
			_draw_title_wheel(Vector2(car_x + 70.0, -7.0), 11.0)
			draw_line(
				Vector2(car_x + 90.0, -17.0),
				Vector2(car_x + 98.0, -17.0),
				PresentationPalette.IRON,
				3.0
			)

		var body := Rect2(-8.0, -76.0, 124.0, 62.0)
		draw_rect(body, PresentationPalette.COAL.lerp(PresentationPalette.IRON, 0.35))
		draw_rect(body, brass, false, 3.0)
		draw_rect(Rect2(-5.0, -112.0, 43.0, 53.0), PresentationPalette.COAL)
		draw_rect(Rect2(-5.0, -112.0, 43.0, 53.0), brass, false, 3.0)
		draw_line(
			Vector2(-10.0, -113.0),
			Vector2(44.0, -113.0),
			PresentationPalette.BRASS,
			4.0
		)
		draw_rect(Rect2(4.0, -100.0, 18.0, 16.0), PresentationPalette.EMBER)
		draw_rect(Rect2(4.0, -100.0, 18.0, 16.0), PresentationPalette.BONE, false, 1.5)
		draw_rect(Rect2(48.0, -66.0, 60.0, 31.0), PresentationPalette.SLATE.darkened(0.14))
		draw_rect(Rect2(48.0, -66.0, 60.0, 31.0), PresentationPalette.IRON, false, 2.0)
		draw_rect(Rect2(68.0, -103.0, 14.0, 39.0), PresentationPalette.COAL)
		draw_rect(Rect2(63.0, -108.0, 24.0, 6.0), PresentationPalette.IRON)
		draw_circle(Vector2(115.0, -52.0), 12.0, PresentationPalette.IRON.darkened(0.18))
		draw_circle(Vector2(120.0, -52.0), 6.0, PresentationPalette.BONE)
		draw_circle(Vector2(120.0, -52.0), 3.0, PresentationPalette.EMBER)
		_draw_title_wheel(Vector2(18.0, -6.0), 16.0)
		_draw_title_wheel(Vector2(67.0, -4.0), 22.0)
		_draw_title_wheel(Vector2(105.0, -6.0), 14.0)
		draw_line(Vector2(18.0, -6.0), Vector2(67.0, -4.0), brass, 3.0)
		draw_line(Vector2(67.0, -4.0), Vector2(105.0, -6.0), brass, 3.0)

	func _draw_title_wheel(center: Vector2, radius: float) -> void:
		draw_circle(center, radius, PresentationPalette.NIGHT_VOID)
		draw_arc(center, radius - 1.0, 0.0, TAU, 18, PresentationPalette.BRASS, 2.0)
		for spoke in range(4):
			var angle: float = _t * 0.6 + float(spoke) * PI * 0.5
			draw_line(
				center,
				center + Vector2.from_angle(angle) * (radius - 2.0),
				PresentationPalette.IRON,
				1.5
			)

	func _draw_ash(s: Vector2) -> void:
		for i in range(30):
			var drift: float = (
				0.0
				if bool(GameManager.get_setting("reduced_motion", false))
				else _t * (5.0 + float(i % 4))
			)
			var x: float = fmod(float(i * 83) + drift, s.x + 24.0) - 12.0
			var y: float = fmod(float(i * 47), s.y * 0.78)
			draw_line(
				Vector2(x, y),
				Vector2(x + 3.0, y - 1.0),
				PresentationPalette.with_alpha(&"bone", 0.12 + float(i % 3) * 0.03),
				1.0
			)
