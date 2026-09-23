class_name PointerRouter
extends Node
## Normalizes mouse and touch aiming without allowing UI-origin touches to leak
## into the world aim surface.

signal aim_changed(position: Vector2, source: StringName)
signal aim_touch_acquired(index: int)
signal aim_touch_released(index: int, canceled: bool)
signal held_actions_cancelled(reason: StringName)

const NO_TOUCH: int = -1
const EMULATED_MOUSE_SUPPRESSION_MS: int = 750

var _active_touch_index: int = NO_TOUCH
var _last_aim_position: Vector2 = Vector2.ZERO
var _has_aim_position: bool = false
var _blocked: bool = false
var _last_touch_input_msec: int = -EMULATED_MOUSE_SUPPRESSION_MS


func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_input_msec = Time.get_ticks_msec()
		var touch := event as InputEventScreenTouch
		if not touch.pressed and touch.index == _active_touch_index:
			route_screen_touch(touch)
		return
	if event is InputEventScreenDrag:
		_last_touch_input_msec = Time.get_ticks_msec()
		var drag := event as InputEventScreenDrag
		if drag.index == _active_touch_index:
			route_screen_drag(drag)
		return
	if (
		event is InputEventMouseMotion
		and not _blocked
		and _active_touch_index == NO_TOUCH
		and Time.get_ticks_msec() - _last_touch_input_msec
			> EMULATED_MOUSE_SUPPRESSION_MS
	):
		_update_aim((event as InputEventMouseMotion).position, &"mouse")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		route_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		route_screen_drag(event as InputEventScreenDrag)


func route_screen_touch(
	event: InputEventScreenTouch,
	originated_over_control: bool = false
) -> bool:
	_last_touch_input_msec = Time.get_ticks_msec()
	if event.pressed:
		if (
			_blocked
			or originated_over_control
			or _active_touch_index != NO_TOUCH
		):
			return false
		_active_touch_index = event.index
		_update_aim(event.position, &"touch")
		emit_signal("aim_touch_acquired", event.index)
		return true
	if event.index != _active_touch_index:
		return false
	_update_aim(event.position, &"touch")
	var released_index := _active_touch_index
	_active_touch_index = NO_TOUCH
	emit_signal("aim_touch_released", released_index, event.canceled)
	if event.canceled:
		emit_signal("held_actions_cancelled", &"touch_cancelled")
	return true


func route_screen_drag(event: InputEventScreenDrag) -> bool:
	_last_touch_input_msec = Time.get_ticks_msec()
	if _blocked or event.index != _active_touch_index:
		return false
	var next_position := event.position
	if (
		String(GameManager.get_setting("touch_aim_mode", "absolute"))
		== "relative"
	):
		var viewport_size := get_viewport().get_visible_rect().size
		var logical_delta := UITheme.physical_size_to_viewport(
			event.screen_relative,
			viewport_size
		)
		next_position = (
			_last_aim_position + logical_delta
		).clamp(Vector2.ZERO, viewport_size)
	_update_aim(next_position, &"touch")
	return true


func set_blocked(blocked: bool, reason: StringName = &"blocked") -> void:
	if _blocked == blocked:
		return
	_blocked = blocked
	if blocked:
		cancel_all(reason)


func cancel_all(reason: StringName = &"cancelled") -> void:
	if _active_touch_index != NO_TOUCH:
		var released_index := _active_touch_index
		_active_touch_index = NO_TOUCH
		emit_signal("aim_touch_released", released_index, true)
	emit_signal("held_actions_cancelled", reason)


func active_touch_index() -> int:
	return _active_touch_index


func has_active_touch() -> bool:
	return _active_touch_index != NO_TOUCH


func has_aim_position() -> bool:
	return _has_aim_position


func current_aim(fallback: Vector2) -> Vector2:
	return _last_aim_position if _has_aim_position else fallback


func _update_aim(position: Vector2, source: StringName) -> void:
	_last_aim_position = position
	_has_aim_position = true
	emit_signal("aim_changed", position, source)


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_APPLICATION_PAUSED
	):
		cancel_all(&"application_suspended")
