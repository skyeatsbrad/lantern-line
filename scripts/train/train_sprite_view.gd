class_name TrainSpriteView
extends Node2D
## TrainSpriteView
##
## Placeholder train view for the M2 baked-sprite category. It reads the
## `PresentationSnapshot` and, when routed by `PresentationRouter`, draws a
## deterministic placeholder body. Production sprites replace this in M3.
##
## The existing `TrainRenderer` remains the vector fallback and continues to
## own the shipping visuals until authored art lands.

var _snapshot: PresentationSnapshot
var _profile: String = PresentationProfile.HIGH
var _features: Dictionary = {}
var _baked_enabled: bool = false
var _assets_attached: bool = false
var _event_type: StringName = &""
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
	_event_type = event.type
	_event_position = event.position
	_event_strength = event.strength
	_event_expiry = event.timestamp + 0.75
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
	var origin: Vector2 = _snapshot.train_position
	var scale: float = _snapshot.train_scale
	var body := Rect2(
		origin + Vector2(-56.0, -32.0) * scale,
		Vector2(112.0, 62.0) * scale
	)
	draw_rect(
		body,
		PresentationPalette.with_alpha(&"brass", 0.85, UITheme.high_contrast())
	)
	draw_rect(
		body,
		PresentationPalette.color(&"night_void", UITheme.high_contrast()),
		false,
		2.0
	)
	draw_string(
		UITheme.bold_font(),
		origin + Vector2(-56.0, 6.0),
		"TRAIN (baked M2 placeholder)",
		HORIZONTAL_ALIGNMENT_CENTER,
		112.0 * scale,
		UITheme.font_size(9),
		PresentationPalette.color(&"night_void", UITheme.high_contrast())
	)
	_draw_hp_bar(
		Rect2(
			origin + Vector2(-50.0, 34.0) * scale,
			Vector2(100.0, 4.0) * scale
		),
		_snapshot.train_hp_ratio
	)
	for index in range(_snapshot.car_count):
		var car: CarViewState = _snapshot.cars[index]
		var car_center: Vector2 = origin + Vector2(
			-112.0 - float(index) * 100.0,
			0.0
		) * scale
		var car_body := Rect2(
			car_center + Vector2(-42.0, -26.0) * scale,
			Vector2(84.0, 48.0) * scale
		)
		draw_rect(
			car_body,
			PresentationPalette.with_alpha(
				&"iron",
				0.88,
				UITheme.high_contrast()
			)
		)
		draw_rect(
			car_body,
			PresentationPalette.color(
				&"brass",
				UITheme.high_contrast()
			),
			false,
			2.0
		)
		draw_string(
			UITheme.bold_font(),
			car_center + Vector2(-38.0, 3.0) * scale,
			car.car_type.substr(0, 3).to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER,
			76.0 * scale,
			UITheme.font_size(8),
			PresentationPalette.color(
				&"bone",
				UITheme.high_contrast()
			)
		)
		_draw_hp_bar(
			Rect2(
				car_center + Vector2(-36.0, 27.0) * scale,
				Vector2(72.0, 3.0) * scale
			),
			car.hp_ratio
		)
	var reference_clock: float = maxf(
		_snapshot.simulation_time,
		_snapshot.reference_frame_time
	)
	if (
		not _event_type.is_empty()
		and reference_clock <= _event_expiry
		and _event_position != Vector2.ZERO
	):
		draw_arc(
			_event_position,
			12.0 + minf(absf(_event_strength), 18.0),
			0.0,
			TAU,
			20,
			PresentationPalette.with_alpha(
				&"ember",
				0.9,
				UITheme.high_contrast()
			),
			3.0
		)


func _draw_hp_bar(rect: Rect2, ratio: float) -> void:
	draw_rect(
		rect,
		PresentationPalette.with_alpha(
			&"night_void",
			0.85,
			UITheme.high_contrast()
		)
	)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)),
		PresentationPalette.color(
			&"danger" if ratio < 0.35 else &"brass",
			UITheme.high_contrast()
		)
	)
