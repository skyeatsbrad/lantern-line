class_name WorldSpriteView
extends Node2D
## WorldSpriteView
##
## Placeholder world view for the M2 baked-sprite category. Reads a read-only
## `PresentationSnapshot` and draws a deterministic parallax placeholder when
## the router enables the `world` category. Production parallax kits replace
## this in M4/M5.

var _snapshot: PresentationSnapshot
var _profile: String = PresentationProfile.HIGH
var _features: Dictionary = {}
var _baked_enabled: bool = false
var _assets_attached: bool = false
var _event_position: Vector2 = Vector2.ZERO
var _event_strength: float = 0.0
var _event_expiry: float = 0.0


func _ready() -> void:
	set_process(true)
	visible = false


func _process(_delta: float) -> void:
	visible = _baked_enabled and _snapshot != null
	if visible:
		queue_redraw()


func update_snapshot(snapshot: PresentationSnapshot) -> void:
	_snapshot = snapshot
	queue_redraw()


func on_sim_event(event: SimEvent) -> void:
	_event_position = event.position
	_event_strength = event.strength
	_event_expiry = event.timestamp + 0.9
	queue_redraw()


func set_baked_enabled(enabled: bool) -> void:
	_baked_enabled = enabled
	visible = enabled
	queue_redraw()


func baked_enabled() -> bool:
	return _baked_enabled


func attach_assets(features: Dictionary) -> void:
	_features = features
	_assets_attached = true


func detach_assets() -> void:
	_features = {}
	_assets_attached = false


func apply_profile(profile_name: String, features: Dictionary) -> void:
	_profile = PresentationProfile.normalize(profile_name)
	_features = features


func has_assets() -> bool:
	return _assets_attached


func _draw() -> void:
	if not _baked_enabled or _snapshot == null:
		return
	var view: Vector2 = _snapshot.view_size
	var category: String = String(
		_snapshot.route_context.get("category", "neutral")
	)
	var horizon: float = view.y * 0.68
	var high_contrast: bool = UITheme.high_contrast()
	var top: Color = PresentationPalette.color(&"night_void", high_contrast)
	var mid: Color = PresentationPalette.color(&"coal", high_contrast)
	var bottom: Color = PresentationPalette.color(&"iron", high_contrast)
	match category:
		"living":
			mid = PresentationPalette.color(&"growth", high_contrast).darkened(0.4)
		"machinery":
			mid = PresentationPalette.color(&"cold_signal", high_contrast).darkened(0.4)
		"danger":
			mid = PresentationPalette.color(&"shadow_veil", high_contrast).darkened(0.3)
	draw_rect(Rect2(Vector2.ZERO, Vector2(view.x, horizon)), top)
	draw_rect(
		Rect2(Vector2(0.0, horizon * 0.55), Vector2(view.x, horizon * 0.45)),
		mid
	)
	draw_rect(
		Rect2(Vector2(0.0, horizon), Vector2(view.x, view.y - horizon)),
		bottom
	)
	var beam_length: float = minf(
		_snapshot.light_range,
		view.x * 0.72
	)
	var beam_direction: Vector2 = _snapshot.light_direction.normalized()
	var beam_end: Vector2 = (
		_snapshot.light_origin
		+ beam_direction * beam_length
	)
	var beam_half_width: float = tan(_snapshot.light_spread) * beam_length
	var beam_normal: Vector2 = beam_direction.orthogonal()
	draw_colored_polygon(
		PackedVector2Array([
			_snapshot.light_origin,
			beam_end + beam_normal * beam_half_width,
			beam_end - beam_normal * beam_half_width
		]),
		PresentationPalette.with_alpha(
			&"bone",
			clampf(_snapshot.light_intensity * 0.14, 0.03, 0.22),
			high_contrast
		)
	)
	var reference_clock: float = maxf(
		_snapshot.simulation_time,
		_snapshot.reference_frame_time
	)
	if (
		_event_position != Vector2.ZERO
		and reference_clock <= _event_expiry
	):
		draw_arc(
			_event_position,
			12.0 + minf(absf(_event_strength), 24.0),
			0.0,
			TAU,
			20,
			PresentationPalette.with_alpha(
				&"cold_signal",
				0.9,
				high_contrast
			),
			3.0
		)
	draw_string(
		UITheme.bold_font(),
		Vector2(view.x * 0.5 - 96.0, view.y - 16.0),
		"WORLD (baked M2 placeholder)",
		HORIZONTAL_ALIGNMENT_CENTER,
		192.0,
		UITheme.font_size(9),
		PresentationPalette.color(&"bone", high_contrast)
	)
