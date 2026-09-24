class_name LongshadowView
extends Node2D
## LongshadowView
##
## Owns all body, mechanic, transition, status, and accessibility drawing for
## the Longshadow encounter. Reads a read-only `PresentationSnapshot`
## produced by `LongshadowEncounter.write_snapshot()` — never mutates it.
##
## Preserves the same 3.0 s entrance and 2.5 s phase-transition presentation
## and every accessibility variant that the pre-M2 combined class exposed. The
## simulation retains gate ownership; this view only expresses what the gate
## says.
##
## Every view implements the same interface: `update_snapshot(snapshot)`,
## `attach_assets(features)` / `detach_assets()`, and
## `apply_profile(profile_name, features)`.

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
	visible = _snapshot != null and _snapshot.longshadow_active
	if visible:
		queue_redraw()


func update_snapshot(snapshot: PresentationSnapshot) -> void:
	_snapshot = snapshot
	visible = snapshot != null and snapshot.longshadow_active
	queue_redraw()


func on_sim_event(event: SimEvent) -> void:
	_event_position = event.position
	_event_strength = event.strength
	_event_expiry = event.timestamp + 0.9
	queue_redraw()


func set_baked_enabled(enabled: bool) -> void:
	_baked_enabled = enabled
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
	if _snapshot == null or not _snapshot.longshadow_active:
		return
	var boss: Vector2 = _snapshot.longshadow_position
	if _baked_enabled:
		_draw_baked_placeholder(boss)
		_draw_event_emphasis()
		return
	var reduced_motion: bool = _snapshot.reduced_motion
	var pulse: float = (
		1.0
		if reduced_motion
		else 1.0 + sin(_snapshot.longshadow_elapsed * 2.4) * 0.045
	)
	match _snapshot.longshadow_phase:
		LongshadowEncounter.Phase.VEIL:
			_draw_veil_body(boss, pulse)
		LongshadowEncounter.Phase.TETHER:
			_draw_tether_body(boss, pulse)
		LongshadowEncounter.Phase.CHARGE:
			_draw_charge_body(boss, pulse)
	_draw_transition_flourish(boss, reduced_motion)
	if _snapshot.longshadow_transition_timer > 0.0:
		_draw_boss_status(boss)
		_draw_event_emphasis()
		return
	_draw_response_lock(boss)
	if _snapshot.longshadow_phase == LongshadowEncounter.Phase.VEIL:
		_draw_veil_mechanic(boss)
	elif _snapshot.longshadow_phase == LongshadowEncounter.Phase.TETHER:
		_draw_tether_mechanic(boss)
	elif _snapshot.longshadow_phase == LongshadowEncounter.Phase.CHARGE:
		_draw_charge_mechanic(boss)
	_draw_boss_status(boss)
	_draw_event_emphasis()


func _draw_veil_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var left := _offset_points(center, [
		Vector2(-5.0, -52.0),
		Vector2(-42.0, -43.0),
		Vector2(-73.0, -12.0),
		Vector2(-61.0, 35.0),
		Vector2(-26.0, 57.0),
		Vector2(-8.0, 22.0)
	], scale)
	var right := _offset_points(center, [
		Vector2(7.0, -48.0),
		Vector2(36.0, -57.0),
		Vector2(68.0, -27.0),
		Vector2(73.0, 18.0),
		Vector2(34.0, 51.0),
		Vector2(10.0, 20.0)
	], scale)
	_draw_outlined_polygon(
		left,
		PresentationPalette.COAL,
		PresentationPalette.with_alpha(&"shadow_veil", 0.72),
		2.5
	)
	_draw_outlined_polygon(
		right,
		PresentationPalette.COAL.lerp(shadow, 0.18),
		PresentationPalette.with_alpha(&"shadow_veil", 0.72),
		2.5
	)
	draw_circle(center, 27.0 * scale, shadow.darkened(0.28))
	draw_circle(center + Vector2(-4.0, 2.0), 18.0 * scale, PresentationPalette.NIGHT_VOID)
	draw_arc(
		center,
		43.0 * scale,
		-2.72,
		-0.62,
		18,
		PresentationPalette.with_alpha(&"bone", 0.24),
		2.0
	)
	draw_arc(
		center,
		49.0 * scale,
		0.38,
		2.24,
		18,
		PresentationPalette.with_alpha(&"shadow_veil", 0.8),
		4.0
	)


func _draw_tether_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var upper := _offset_points(center, [
		Vector2(-45.0, -7.0),
		Vector2(-30.0, -52.0),
		Vector2(2.0, -68.0),
		Vector2(34.0, -43.0),
		Vector2(21.0, -8.0)
	], scale)
	var lower := _offset_points(center, [
		Vector2(-43.0, 8.0),
		Vector2(-24.0, 53.0),
		Vector2(8.0, 67.0),
		Vector2(39.0, 36.0),
		Vector2(20.0, 8.0)
	], scale)
	_draw_outlined_polygon(
		upper,
		PresentationPalette.COAL.lerp(shadow, 0.28),
		PresentationPalette.with_alpha(&"shadow_veil", 0.82),
		2.5
	)
	_draw_outlined_polygon(
		lower,
		PresentationPalette.COAL,
		PresentationPalette.with_alpha(&"shadow_veil", 0.82),
		2.5
	)
	draw_rect(
		Rect2(
			center + Vector2(-8.0, -48.0) * scale,
			Vector2(16.0, 96.0) * scale
		),
		PresentationPalette.NIGHT_VOID
	)
	draw_line(
		center + Vector2(-7.0, -30.0) * scale,
		center + Vector2(7.0, -7.0) * scale,
		PresentationPalette.with_alpha(&"bone", 0.38),
		2.0
	)
	draw_line(
		center + Vector2(-7.0, 30.0) * scale,
		center + Vector2(7.0, 7.0) * scale,
		PresentationPalette.with_alpha(&"bone", 0.38),
		2.0
	)


func _draw_charge_body(center: Vector2, scale: float) -> void:
	var shadow: Color = PresentationPalette.color(
		&"shadow_veil",
		UITheme.high_contrast()
	)
	var wedge := _offset_points(center, [
		Vector2(-66.0, 0.0),
		Vector2(-25.0, -47.0),
		Vector2(33.0, -39.0),
		Vector2(70.0, 0.0),
		Vector2(28.0, 43.0),
		Vector2(-27.0, 46.0)
	], scale)
	_draw_outlined_polygon(
		wedge,
		PresentationPalette.COAL.lerp(shadow, 0.34),
		PresentationPalette.with_alpha(&"danger", 0.82),
		3.0
	)
	var slit := _offset_points(center, [
		Vector2(-38.0, 0.0),
		Vector2(12.0, -15.0),
		Vector2(29.0, 0.0),
		Vector2(12.0, 15.0)
	], scale)
	draw_colored_polygon(slit, PresentationPalette.NIGHT_VOID)
	for spine in range(3):
		var y: float = float(spine - 1) * 22.0
		draw_line(
			center + Vector2(30.0, y) * scale,
			center + Vector2(58.0, y * 1.25) * scale,
			PresentationPalette.with_alpha(&"shadow_veil", 0.72),
			4.0
		)


func _draw_transition_flourish(center: Vector2, reduced_motion: bool) -> void:
	if _snapshot.longshadow_transition_timer <= 0.0:
		return
	var gate_duration: float = _snapshot.longshadow_transition_total
	var flourish_duration: float = 1.1
	var elapsed: float = maxf(
		0.0, gate_duration - _snapshot.longshadow_transition_timer
	)
	if elapsed > flourish_duration:
		return
	var ratio: float = clampf(elapsed / flourish_duration, 0.0, 1.0)
	var visual_ratio: float = 1.0 if reduced_motion else ratio
	for ring in range(3):
		var radius: float = 70.0 + float(ring) * 15.0 + visual_ratio * 22.0
		var alpha: float = (0.48 - float(ring) * 0.1) * (1.0 - ratio * 0.7)
		for segment in range(3):
			var start: float = float(segment) * 2.12 + ratio * 0.6
			draw_arc(
				center,
				radius,
				start,
				start + 1.22,
				12,
				PresentationPalette.with_alpha(
					&"shadow_veil",
					alpha,
					UITheme.high_contrast()
				),
				3.5
			)


func _draw_response_lock(center: Vector2) -> void:
	var response_ratio: float = _snapshot.longshadow_response_ratio
	if not _snapshot.longshadow_phase_unlocked:
		var base_color: Color = PresentationPalette.with_alpha(
			&"shadow_veil",
			0.46,
			UITheme.high_contrast()
		)
		for segment in range(3):
			var start: float = -PI * 0.5 + float(segment) * 2.14
			draw_arc(
				center,
				80.0,
				start,
				start + 1.36,
				14,
				base_color,
				4.0
			)
		draw_arc(
			center,
			80.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * response_ratio,
			42,
			PresentationPalette.color(&"brass", UITheme.high_contrast()),
			5.5
		)
	var phase_lens: String = LongshadowEncounter.PHASE_LENSES[_snapshot.longshadow_phase]
	var response_text: String = (
		"EXPOSED"
		if _snapshot.longshadow_phase_unlocked
		else "%s + ACTIVE" % phase_lens.to_upper()
	)
	draw_string(
		UITheme.bold_font(),
		center + Vector2(-88.0, -124.0),
		response_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		176.0,
		UITheme.font_size(11),
		PresentationPalette.color(
			&"danger" if _snapshot.longshadow_phase_unlocked else &"brass",
			UITheme.high_contrast()
		)
	)


func _draw_veil_mechanic(center: Vector2) -> void:
	var rotation: float = (
		0.0
		if _snapshot.reduced_motion
		else _snapshot.longshadow_elapsed * 0.22
	)
	for segment in range(4):
		var start: float = rotation + float(segment) * 1.58
		draw_arc(
			center,
			64.0,
			start,
			start + 0.84,
			10,
			PresentationPalette.with_alpha(
				&"shadow_veil",
				0.66,
				UITheme.high_contrast()
			),
			5.0
		)


func _draw_tether_mechanic(_center: Vector2) -> void:
	var anchor: Vector2 = _snapshot.longshadow_target_position
	var train_pos: Vector2 = _snapshot.train_position
	var train_scale: float = _snapshot.train_scale
	var source: Vector2 = train_pos + Vector2(38.0, -22.0) * train_scale
	var bend := Vector2(lerpf(source.x, anchor.x, 0.52), anchor.y - 26.0)
	draw_polyline(
		PackedVector2Array([source, bend, anchor]),
		PresentationPalette.with_alpha(
			&"danger",
			0.78,
			UITheme.high_contrast()
		),
		4.0
	)
	for knot in range(1, 4):
		var t: float = float(knot) / 4.0
		var knot_pos: Vector2 = source.lerp(bend, minf(1.0, t * 1.7))
		if t > 0.58:
			knot_pos = bend.lerp(anchor, (t - 0.58) / 0.42)
		draw_rect(
			Rect2(knot_pos - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
			PresentationPalette.color(&"brass", UITheme.high_contrast())
		)
	var diamond := PackedVector2Array([
		anchor + Vector2(0.0, -17.0),
		anchor + Vector2(17.0, 0.0),
		anchor + Vector2(0.0, 17.0),
		anchor + Vector2(-17.0, 0.0)
	])
	_draw_outlined_polygon(
		diamond,
		PresentationPalette.COAL,
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		3.0
	)
	draw_string(
		UITheme.bold_font(),
		anchor + Vector2(-33.0, -23.0),
		"SEVER",
		HORIZONTAL_ALIGNMENT_CENTER,
		66.0,
		UITheme.font_size(10),
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _draw_charge_mechanic(center: Vector2) -> void:
	var charge_timer: float = _snapshot.longshadow_charge_timer
	var charge_ratio: float = 1.0 - clampf(charge_timer / 11.0, 0.0, 1.0)
	var warning_color: Color = PresentationPalette.with_alpha(
		&"danger",
		0.42 + charge_ratio * 0.5,
		UITheme.high_contrast()
	)
	var train_pos: Vector2 = _snapshot.train_position
	var train_scale: float = _snapshot.train_scale
	for chevron in range(3):
		var x: float = lerpf(
			center.x - 84.0,
			train_pos.x + 96.0 * train_scale,
			float(chevron) / 3.0
		)
		var y: float = lerpf(
			center.y,
			train_pos.y - 26.0 * train_scale,
			float(chevron) / 3.0
		)
		var size: float = 14.0 + charge_ratio * 9.0
		draw_polyline(
			PackedVector2Array([
				Vector2(x + size, y - size),
				Vector2(x, y),
				Vector2(x + size, y + size)
			]),
			warning_color,
			3.0 + charge_ratio * 2.0
		)
	if charge_timer <= 3.0:
		draw_string(
			UITheme.bold_font(),
			center + Vector2(-62.0, -148.0),
			"CHARGE %.1f" % charge_timer,
			HORIZONTAL_ALIGNMENT_CENTER,
			124.0,
			UITheme.font_size(13),
			PresentationPalette.color(&"danger", UITheme.high_contrast())
		)


func _draw_boss_status(center: Vector2) -> void:
	var font_size: int = UITheme.font_size(11)
	var phase_name: String = LongshadowEncounter.PHASE_NAMES[_snapshot.longshadow_phase]
	var title: String = "LONGSHADOW // %s" % phase_name
	draw_string(
		UITheme.bold_font(),
		center + Vector2(-88.0, -102.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		176.0,
		font_size,
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	var bar_pos: Vector2 = center + Vector2(-72.0, -88.0)
	draw_rect(
		Rect2(bar_pos, Vector2(144.0, 8.0)),
		PresentationPalette.color(&"night_void", UITheme.high_contrast())
	)
	var hp_ratio: float = _snapshot.longshadow_health_ratio
	draw_rect(
		Rect2(bar_pos, Vector2(144.0 * hp_ratio, 8.0)),
		PresentationPalette.color(
			&"danger" if hp_ratio <= 0.3 else &"shadow_veil",
			UITheme.high_contrast()
		)
	)
	draw_rect(
		Rect2(bar_pos, Vector2(144.0, 8.0)),
		PresentationPalette.with_alpha(&"bone", 0.54),
		false,
		1.0
	)


func _draw_baked_placeholder(center: Vector2) -> void:
	# M2 placeholder for the baked longshadow view. Real art arrives in M6.
	var transition_scale: float = lerpf(
		0.72,
		1.0,
		_snapshot.longshadow_transition_ratio
	)
	var body_size: Vector2 = Vector2(144.0, 144.0) * transition_scale
	var body := Rect2(center - body_size * 0.5, body_size)
	draw_rect(
		body,
		PresentationPalette.with_alpha(&"shadow_veil", 0.82),
	)
	draw_rect(
		body,
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		false,
		3.0
	)
	var phase_name: String = LongshadowEncounter.PHASE_NAMES[_snapshot.longshadow_phase]
	draw_string(
		UITheme.bold_font(),
		center + Vector2(-72.0, 12.0),
		"LONGSHADOW\n%s (baked)" % phase_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		144.0,
		UITheme.font_size(11),
		PresentationPalette.color(&"bone", UITheme.high_contrast())
	)
	_draw_boss_status(center)


func _draw_event_emphasis() -> void:
	if _snapshot == null or _event_position == Vector2.ZERO:
		return
	var reference_clock: float = maxf(
		_snapshot.simulation_time,
		_snapshot.reference_frame_time
	)
	if reference_clock > _event_expiry:
		return
	draw_arc(
		_event_position,
		18.0 + minf(absf(_event_strength), 24.0),
		0.0,
		TAU,
		24,
		PresentationPalette.with_alpha(
			&"shadow_veil",
			0.92,
			UITheme.high_contrast()
		),
		4.0
	)


func _offset_points(
	center: Vector2,
	offsets: Array,
	scale: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for offset_variant in offsets:
		var offset: Vector2 = offset_variant
		points.append(center + offset * scale)
	return points


func _draw_outlined_polygon(
	points: PackedVector2Array,
	fill: Color,
	outline: Color,
	width: float
) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill)
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline, width, true)
