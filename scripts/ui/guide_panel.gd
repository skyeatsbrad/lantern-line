class_name GuidePanel
extends Control
## Four-page, keyboard-friendly onboarding and reference guide.

signal closed()

const PAGES: Array[Dictionary] = [
	{
		"title": "AIM THE LANTERN",
		"body": "Move the mouse to sweep the headlight across the track and sky. "
			+ "Standard exposes roof boarders, Hearth burns rear pursuers, and Pale sears lumen drainers. "
			+ "The enemy silhouettes differ even without color; High Contrast also adds role and lens labels.",
		"controls": "Mouse aim  |  1 Standard  |  2 Hearth  |  3 Pale"
	},
	{
		"title": "BALANCE POWER AND PACE",
		"body": "Engine, Light, Defense, and Repair priorities run from 0 to 3. "
			+ "When demand exceeds supply, low-priority systems throttle first. "
			+ "Use 1.5x for normal play; 2x speeds travel while Threat Brake automatically slows crowded combat.",
		"controls": "Q/W/E/R raise priority  |  Shift + key lowers  |  T pace  |  Space pause"
	},
	{
		"title": "MAKE ACTIVE RESPONSES",
		"body": "Focus spends lumen on a narrow burst. A Defense Salvo spends power from a weapon platform. "
			+ "Either action breaks a Shadow Ward. After Waypost Five, scrap also buys Patch, Overcharge, and Flare actions. "
			+ "The Longshadow names the lens and response required in every phase.",
		"controls": "F Focus  |  C Salvo  |  V Patch  |  B Overcharge  |  G Flare"
	},
	{
		"title": "CHOOSE WHAT REACHES DAWN",
		"body": "Route projections state their reward, danger, and story consequences before commitment. "
			+ "At Waypost Five, Build, Crew, and Refits tabs preview every permanent change. "
			+ "Holding X detaches the rear car as a last resort; read the crew warning before the meter fills.",
		"controls": "Arrow routes or Tab/Enter  |  H guide  |  Escape options  |  Hold X detach"
	}
]

var _page_index: int = 0
var _open: bool = false
var _completion_label: String = "Close Guide"
var _counter_label: Label
var _title_label: Label
var _body_label: Label
var _controls_label: Label
var _back_button: Button
var _next_button: Button


func present(completion_label: String = "Close Guide") -> void:
	_completion_label = completion_label
	_page_index = 0
	_open = true
	visible = true
	_build()
	set_process_input(true)


func is_open() -> bool:
	return _open


func _build() -> void:
	theme = UITheme.build()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.84)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var viewport_size := get_viewport_rect().size
	var frame_width := minf(760.0, viewport_size.x - 32.0)
	var frame_height := minf(520.0, viewport_size.y - 32.0)
	var frame := PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -frame_width * 0.5
	frame.offset_right = frame_width * 0.5
	frame.offset_top = -frame_height * 0.5
	frame.offset_bottom = frame_height * 0.5
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	frame.add_child(root)
	var heading := Label.new()
	heading.text = "CONDUCTOR'S GUIDE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", UITheme.font_size(24))
	heading.add_theme_color_override("font_color", UITheme.accent_color())
	root.add_child(heading)

	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_color_override("font_color", UITheme.muted_text_color())
	root.add_child(_counter_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", UITheme.font_size(21))
	root.add_child(_title_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(frame_width - 42.0, 0.0)
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", UITheme.font_size(16))
	_body_label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.96))
	content.add_child(_body_label)
	var control_card := PanelContainer.new()
	content.add_child(control_card)
	_controls_label = Label.new()
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_label.add_theme_color_override("font_color", UITheme.accent_color())
	control_card.add_child(_controls_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	_back_button = Button.new()
	_back_button.text = "Previous"
	_back_button.custom_minimum_size = Vector2(140.0, 44.0)
	_back_button.pressed.connect(_previous_page)
	actions.add_child(_back_button)
	_next_button = Button.new()
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.custom_minimum_size = Vector2(0.0, 44.0)
	_next_button.pressed.connect(_next_page)
	actions.add_child(_next_button)
	_refresh_page()
	call_deferred("_focus_next")


func _refresh_page() -> void:
	var page: Dictionary = PAGES[_page_index]
	_counter_label.text = "PAGE %d OF %d" % [_page_index + 1, PAGES.size()]
	_title_label.text = String(page.get("title", ""))
	_body_label.text = String(page.get("body", ""))
	_controls_label.text = String(page.get("controls", ""))
	_back_button.disabled = _page_index <= 0
	_next_button.text = (
		_completion_label
		if _page_index == PAGES.size() - 1
		else "Next"
	)


func _focus_next() -> void:
	if is_instance_valid(_next_button):
		_next_button.grab_focus()


func _previous_page() -> void:
	if _page_index <= 0:
		return
	_page_index -= 1
	AudioManager.play("click")
	_refresh_page()


func _next_page() -> void:
	if _page_index < PAGES.size() - 1:
		_page_index += 1
		AudioManager.play("click")
		_refresh_page()
		return
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	GameManager.set_setting("tutorial_seen", true)
	AudioManager.play("click")
	emit_signal("closed")


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_guide"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_previous_page()
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_next_page()
