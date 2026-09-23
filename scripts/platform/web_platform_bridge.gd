class_name WebPlatformBridge
extends RefCounted
## Safe, feature-detected access to browser and mobile platform information.


static func is_web() -> bool:
	return OS.has_feature("web")


static func is_native_mobile() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


static func touch_available() -> bool:
	var forced_touch := OS.get_environment("LANTERN_FORCE_TOUCH")
	if not forced_touch.is_empty():
		return forced_touch != "0"
	if DisplayServer.get_name() == "headless":
		return false
	if is_web():
		var detected: Variant = JavaScriptBridge.eval(
			"Boolean("
			+ "navigator.maxTouchPoints > 0 "
			+ "&& window.matchMedia('(pointer: coarse)').matches"
			+ ")",
			true
		)
		return bool(detected)
	return DisplayServer.is_touchscreen_available()


static func css_viewport_size() -> Vector2:
	if not is_web():
		return Vector2.ZERO
	var data: Dictionary = _eval_json(
		"(window.LanternPlatform && window.LanternPlatform.viewportSize"
		+ " ? window.LanternPlatform.viewportSize()"
		+ " : {width: window.innerWidth, height: window.innerHeight})"
	)
	var width := float(data.get("width", 0.0))
	var height := float(data.get("height", 0.0))
	if width < 1.0 or height < 1.0:
		return Vector2.ZERO
	return Vector2(width, height)


static func safe_insets_physical() -> Vector4:
	if is_web():
		var data: Dictionary = _eval_json(
			"(window.LanternPlatform && window.LanternPlatform.safeInsets"
			+ " ? window.LanternPlatform.safeInsets()"
			+ " : {left: 0, top: 0, right: 0, bottom: 0})"
		)
		return Vector4(
			maxf(0.0, float(data.get("left", 0.0))),
			maxf(0.0, float(data.get("top", 0.0))),
			maxf(0.0, float(data.get("right", 0.0))),
			maxf(0.0, float(data.get("bottom", 0.0)))
		)
	if not is_native_mobile():
		return Vector4.ZERO
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := Vector2(DisplayServer.screen_get_size())
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(safe_area.position.x)),
		maxf(0.0, float(safe_area.position.y)),
		maxf(0.0, screen_size.x - float(safe_area.end.x)),
		maxf(0.0, screen_size.y - float(safe_area.end.y))
	)


static func is_portrait() -> bool:
	var size := css_viewport_size() if is_web() else Vector2(
		DisplayServer.window_get_size()
	)
	return size.y > size.x and size.x > 0.0


static func configure_runtime() -> void:
	if is_native_mobile():
		DisplayServer.screen_set_orientation(
			DisplayServer.SCREEN_SENSOR_LANDSCAPE
		)
		DisplayServer.screen_set_keep_on(true)


static func notify_game_ready() -> void:
	if not is_web():
		return
	JavaScriptBridge.eval(
		"window.LanternPlatform?.gameReady?.()",
		true
	)


static func _eval_json(expression: String) -> Dictionary:
	var raw: Variant = JavaScriptBridge.eval(
		"JSON.stringify(%s)" % expression,
		true
	)
	if raw == null:
		return {}
	var parsed: Variant = JSON.parse_string(String(raw))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
