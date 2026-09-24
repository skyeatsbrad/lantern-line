class_name EnemyViewPool
extends Node2D
## EnemyViewPool
##
## Owns the vector fallback rendering for regular threats. Reads a read-only
## `PresentationSnapshot` produced by `EnemyDirector` after simulation. Uses a
## pooled reusable snapshot-record layout; the pool creates no per-frame
## objects.
##
## The M2 baked path routes into `_draw_baked_placeholder()` and exists only
## to prove that per-category baked toggling works. Production art arrives in
## M3/M4/M5 and replaces the placeholder while keeping the same interface.
##
## Every view exposed to the router implements:
##   - `update_snapshot(snapshot)` — copy state before redraw
##   - `attach_assets(features)` / `detach_assets()` — load/unload placeholder
##   - `apply_profile(profile_name, features)` — honor Reduced Motion, HC, etc.

const CONSUMER_ID: String = "view.enemy_view_pool"

var _snapshot: PresentationSnapshot
var _elapsed: float = 0.0
var _reduced_motion: bool = false
var _profile: String = PresentationProfile.HIGH
var _features: Dictionary = {}
var _baked_enabled: bool = false
var _assets_attached: bool = false
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _event_type: StringName = &""
var _event_position: Vector2 = Vector2.ZERO
var _event_strength: float = 0.0
var _event_expiry: float = 0.0


func _ready() -> void:
	set_process(false)


func update_snapshot(snapshot: PresentationSnapshot) -> void:
	_snapshot = snapshot
	if snapshot != null:
		_view_size = snapshot.view_size
		_reduced_motion = snapshot.reduced_motion
		_elapsed = snapshot.enemy_elapsed
	queue_redraw()


func on_sim_event(event: SimEvent) -> void:
	_event_type = event.type
	_event_position = event.position
	_event_strength = event.strength
	_event_expiry = event.timestamp + 0.75
	queue_redraw()


func set_baked_enabled(enabled: bool) -> void:
	if enabled == _baked_enabled:
		return
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
	if _snapshot == null or _snapshot.enemy_count <= 0:
		return
	if _baked_enabled:
		_draw_baked_placeholder()
		_draw_event_emphasis()
		return
	_draw_vector_active()
	_draw_accessibility_labels()
	_draw_event_emphasis()


func _draw_vector_active() -> void:
	for index in range(_snapshot.enemy_count):
		var state: EnemyViewState = _snapshot.enemies[index]
		if not state.alive:
			continue
		match state.kind:
			"Pursuer":
				_draw_pursuer(state)
			"Boarder":
				_draw_boarder(state)
			"Drainer":
				_draw_drainer(state)
		if state.warded:
			_draw_ward(state)
		_draw_attack_warning(state)
		_draw_hp(state)


func _draw_accessibility_labels() -> void:
	if not UITheme.high_contrast():
		return
	var occupied_labels: Array[Rect2] = []
	var labeled: Array[EnemyViewState] = []
	for index in range(_snapshot.enemy_count):
		var state: EnemyViewState = _snapshot.enemies[index]
		if state.alive:
			labeled.append(state)
	labeled.sort_custom(
		func(a: EnemyViewState, b: EnemyViewState) -> bool:
			return a.position.x < b.position.x
	)
	for state in labeled:
		occupied_labels.append(_draw_accessibility_label(state, occupied_labels))


func _draw_ward(state: EnemyViewState) -> void:
	var ratio: float = clampf(state.ward_hp_ratio, 0.0, 1.0)
	var rotation: float = 0.0 if _reduced_motion else _elapsed * 0.65
	var radius: float = 27.0
	var ward_color: Color = PresentationPalette.with_alpha(
		&"shadow_veil",
		0.48 + ratio * 0.42,
		UITheme.high_contrast()
	)
	var segments := [
		Vector2(0.05, 1.2),
		Vector2(1.72, 3.1),
		Vector2(3.72, 5.56)
	]
	for segment_variant in segments:
		var segment: Vector2 = segment_variant
		draw_arc(
			state.position,
			radius,
			segment.x + rotation,
			segment.y + rotation,
			12,
			ward_color,
			3.0 + ratio
		)
	for shard_index in range(3):
		var shard_angle: float = rotation + 1.4 + float(shard_index) * 2.05
		var shard_center: Vector2 = (
			state.position
			+ Vector2.from_angle(shard_angle) * (radius + 4.0)
		)
		draw_colored_polygon(
			PackedVector2Array([
				shard_center + Vector2.from_angle(shard_angle) * 5.0,
				shard_center + Vector2.from_angle(shard_angle + 2.35) * 4.0,
				shard_center + Vector2.from_angle(shard_angle - 2.35) * 4.0
			]),
			ward_color
		)
	var ward_font_size: int = UITheme.font_size(9)
	draw_string(
		UITheme.bold_font(),
		state.position + Vector2(-42.0, -47.0),
		"FOCUS / SALVO",
		HORIZONTAL_ALIGNMENT_CENTER,
		84.0,
		ward_font_size,
		PresentationPalette.color(&"shadow_veil", UITheme.high_contrast())
	)


func _draw_pursuer(state: EnemyViewState) -> void:
	var p: Vector2 = state.position
	var body_color: Color = _threat_color("Pursuer")
	var outline: Color = _threat_outline()
	var body: PackedVector2Array = PackedVector2Array([
		p + Vector2(-29.0, -1.0),
		p + Vector2(-15.0, -15.0),
		p + Vector2(8.0, -18.0),
		p + Vector2(25.0, -7.0),
		p + Vector2(17.0, 10.0),
		p + Vector2(-13.0, 12.0)
	])
	_draw_outlined_polygon(body, body_color, outline, 2.0)
	var leg_points := [
		[Vector2(-15.0, 9.0), Vector2(-27.0, 19.0), Vector2(-34.0, 16.0)],
		[Vector2(1.0, 11.0), Vector2(-6.0, 23.0), Vector2(-15.0, 22.0)],
		[Vector2(15.0, 7.0), Vector2(27.0, 17.0), Vector2(34.0, 14.0)]
	]
	for leg_variant in leg_points:
		var leg: Array = leg_variant
		draw_polyline(
			PackedVector2Array([
				p + leg[0],
				p + leg[1],
				p + leg[2]
			]),
			body_color,
			4.0
		)
	draw_line(
		p + Vector2(-11.0, -12.0),
		p + Vector2(11.0, 5.0),
		PresentationPalette.with_alpha(&"bone", 0.32),
		1.5
	)
	draw_circle(
		p + Vector2(-20.0, -4.0),
		4.0,
		PresentationPalette.color(&"ember", UITheme.high_contrast())
	)
	draw_circle(p + Vector2(-20.0, -4.0), 1.5, PresentationPalette.BONE)


func _draw_boarder(state: EnemyViewState) -> void:
	var p: Vector2 = state.position
	var body_color: Color = _threat_color("Boarder")
	var outline: Color = _threat_outline()
	draw_circle(p + Vector2(0.0, -20.0), 7.0, body_color)
	draw_arc(
		p + Vector2(0.0, -20.0),
		7.0,
		0.0,
		TAU,
		16,
		outline,
		1.5
	)
	_draw_outlined_polygon(
		PackedVector2Array([
			p + Vector2(-6.0, -14.0),
			p + Vector2(6.0, -14.0),
			p + Vector2(8.0, 9.0),
			p + Vector2(0.0, 15.0),
			p + Vector2(-8.0, 9.0)
		]),
		body_color,
		outline,
		1.5
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(-4.0, -9.0),
			p + Vector2(-19.0, -2.0),
			p + Vector2(-29.0, 12.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(5.0, -8.0),
			p + Vector2(17.0, 1.0),
			p + Vector2(22.0, 17.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(-3.0, 12.0),
			p + Vector2(-12.0, 28.0),
			p + Vector2(-21.0, 31.0)
		]),
		body_color,
		4.0
	)
	draw_polyline(
		PackedVector2Array([
			p + Vector2(3.0, 12.0),
			p + Vector2(11.0, 29.0),
			p + Vector2(20.0, 32.0)
		]),
		body_color,
		4.0
	)
	var hook_center := p + Vector2(-29.0, 12.0)
	draw_arc(
		hook_center,
		10.0,
		-PI * 0.65,
		PI * 0.65,
		16,
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		3.0
	)
	draw_line(
		p + Vector2(22.0, 17.0),
		p + Vector2(29.0, 24.0),
		PresentationPalette.color(&"brass", UITheme.high_contrast()),
		2.0
	)


func _draw_drainer(state: EnemyViewState) -> void:
	var p: Vector2 = state.position
	var t: float = 0.0 if _reduced_motion else _elapsed * 1.8
	var body_color: Color = _threat_color("Drainer")
	var outline: Color = _threat_outline()
	var shell := PackedVector2Array()
	for i in range(9):
		var angle: float = float(i) * TAU / 9.0
		var radius: float = 12.0 + float((i * 7) % 5)
		shell.append(p + Vector2.from_angle(angle + t * 0.08) * radius)
	_draw_outlined_polygon(shell, PresentationPalette.COAL, body_color, 2.5)
	draw_circle(p, 7.0, PresentationPalette.NIGHT_VOID)
	draw_arc(p, 8.0, 0.0, TAU, 20, outline, 1.5)
	var tendril_angles := [-2.72, -0.62, 0.92, 2.18]
	var tendril_lengths := [24.0, 18.0, 29.0, 21.0]
	for i in range(tendril_angles.size()):
		var sway: float = 0.0 if _reduced_motion else sin(t + float(i) * 1.7) * 0.16
		var angle: float = float(tendril_angles[i]) + sway
		var length: float = float(tendril_lengths[i])
		var joint: Vector2 = p + Vector2.from_angle(angle) * length * 0.55
		var end: Vector2 = (
			joint
			+ Vector2.from_angle(angle + (0.38 if i % 2 == 0 else -0.42))
			* length
			* 0.55
		)
		draw_polyline(
			PackedVector2Array([p, joint, end]),
			body_color,
			2.5
		)
		draw_circle(end, 2.5, body_color)
	if state.position.distance_to(state.target) < 190.0:
		var bend := Vector2(lerpf(p.x, state.target.x, 0.55), minf(p.y, state.target.y) - 18.0)
		draw_polyline(
			PackedVector2Array([p, bend, state.target]),
			PresentationPalette.with_alpha(
				&"drainer_glow",
				0.68,
				UITheme.high_contrast()
			),
			2.5
		)
		draw_rect(
			Rect2(state.target - Vector2(6.0, 6.0), Vector2(12.0, 12.0)),
			PresentationPalette.with_alpha(
				&"drainer_glow",
				0.38,
				UITheme.high_contrast()
			),
			false,
			2.0
		)


func _draw_accessibility_label(
	state: EnemyViewState,
	occupied_labels: Array[Rect2]
) -> Rect2:
	var text: String = {
		"Pursuer": "REAR / HEARTH [2]",
		"Boarder": "ROOF / STANDARD [1]",
		"Drainer": "AIR / PALE [3]"
	}.get(state.kind, "THREAT")
	var label_center := Vector2(
		clampf(state.position.x, 78.0, _view_size.x - 78.0),
		maxf(state.position.y, 84.0)
	)
	var font_size: int = UITheme.font_size(10)
	var rect_size := Vector2(152.0, float(font_size) + 8.0)
	var label_offset_y: float = -104.0 if state.warded else -78.0
	var rect := Rect2(
		label_center + Vector2(-rect_size.x * 0.5, label_offset_y),
		rect_size
	)
	var safe_bottom: float = UITheme.gameplay_safe_bottom(_view_size)
	rect.position.y = clampf(
		rect.position.y,
		8.0,
		safe_bottom - rect.size.y - 8.0
	)
	var base_position: Vector2 = rect.position
	for existing in occupied_labels:
		if not rect.intersects(existing.grow(4.0)):
			continue
		rect.position.y = existing.position.y - rect.size.y - 5.0
		if rect.position.y < 8.0:
			rect.position.y = existing.end.y + 5.0
	rect.position.y = clampf(
		rect.position.y,
		8.0,
		safe_bottom - rect.size.y - 8.0
	)
	if not rect.position.is_equal_approx(base_position):
		draw_line(
			state.position + Vector2(0.0, -28.0),
			Vector2(rect.get_center().x, rect.end.y),
			PresentationPalette.with_alpha(&"brass", 0.72, true),
			1.5
		)
	draw_rect(
		rect,
		PresentationPalette.with_alpha(&"night_void", 0.94, true)
	)
	draw_rect(
		rect,
		PresentationPalette.color(&"brass", true),
		false,
		1.5
	)
	draw_string(
		UITheme.bold_font(),
		rect.position + Vector2(4.0, float(font_size) + 2.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8.0,
		font_size,
		PresentationPalette.color(&"bone", true)
	)
	return rect


func _draw_attack_warning(state: EnemyViewState) -> void:
	if (
		state.position.distance_to(state.target) >= 44.0
		or state.attack_timer > state.attack_warning_time
	):
		return
	var ratio: float = state.attack_ratio
	var visual_ratio: float = 1.0 if _reduced_motion else ratio
	var warning_color: Color = PresentationPalette.with_alpha(
		&"danger",
		0.7 + ratio * 0.3,
		UITheme.high_contrast()
	)
	var radius: float = (40.0 if state.warded else 31.0) + visual_ratio * 5.0
	for quadrant in range(4):
		var start: float = float(quadrant) * PI * 0.5 + 0.13
		draw_arc(
			state.position,
			radius,
			start,
			start + 0.72,
			8,
			warning_color,
			3.0
		)
	draw_line(
		state.position,
		state.target,
		PresentationPalette.with_alpha(
			&"danger",
			0.18 + ratio * 0.22,
			UITheme.high_contrast()
		),
		1.5
	)
	draw_line(
		state.target + Vector2(-7.0, 0.0),
		state.target + Vector2(7.0, 0.0),
		warning_color,
		2.0
	)
	draw_line(
		state.target + Vector2(0.0, -7.0),
		state.target + Vector2(0.0, 7.0),
		warning_color,
		2.0
	)
	var warning: String = {
		"Pursuer": "REAR",
		"Boarder": "BOARD",
		"Drainer": "LUMEN"
	}.get(state.kind, "THREAT")
	var warning_font_size: int = UITheme.font_size(10)
	var warning_offset_y: float = 52.0 if state.warded else -40.0
	draw_string(
		UITheme.bold_font(),
		state.position + Vector2(-34.0, warning_offset_y),
		warning,
		HORIZONTAL_ALIGNMENT_CENTER,
		68.0,
		warning_font_size,
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _draw_hp(state: EnemyViewState) -> void:
	if state.max_hp <= 0.0:
		return
	var ratio: float = clampf(state.hp_ratio, 0.0, 1.0)
	var w: float = 28.0
	var pos: Vector2 = state.position + Vector2(-w * 0.5, -31.0)
	draw_rect(
		Rect2(pos, Vector2(w, 4.0)),
		PresentationPalette.color(&"night_void", UITheme.high_contrast())
	)
	draw_rect(
		Rect2(pos, Vector2(w * ratio, 4.0)),
		PresentationPalette.color(&"danger", UITheme.high_contrast())
	)


func _draw_event_emphasis() -> void:
	if _snapshot == null or _event_type.is_empty():
		return
	var reference_clock: float = maxf(
		_snapshot.simulation_time,
		_snapshot.reference_frame_time
	)
	if reference_clock > _event_expiry:
		return
	draw_arc(
		_event_position,
		10.0 + minf(absf(_event_strength), 20.0),
		0.0,
		TAU,
		20,
		PresentationPalette.with_alpha(
			(
				&"cold_signal"
				if _event_type == SimEvent.TYPE_ENEMY_TELEGRAPHED
				else &"ember"
			),
			0.9,
			UITheme.high_contrast()
		),
		3.0
	)


func _draw_baked_placeholder() -> void:
	# M2 placeholder: distinguish baked from vector visually so QA can verify
	# category routing. Real atlases replace this in M3+.
	for index in range(_snapshot.enemy_count):
		var state: EnemyViewState = _snapshot.enemies[index]
		if not state.alive:
			continue
		var fill: Color = PresentationPalette.with_alpha(
			&"brass",
			0.7,
			UITheme.high_contrast()
		)
		var body := Rect2(
			state.position - Vector2(18.0, 18.0),
			Vector2(36.0, 36.0)
		)
		draw_rect(body, fill)
		draw_rect(
			body,
			PresentationPalette.color(&"night_void", UITheme.high_contrast()),
			false,
			2.0
		)
		draw_string(
			UITheme.bold_font(),
			state.position + Vector2(-18.0, 6.0),
			state.kind.substr(0, 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			36.0,
			UITheme.font_size(11),
			PresentationPalette.color(&"night_void", UITheme.high_contrast())
		)
		if state.warded:
			draw_arc(
				state.position,
				25.0,
				0.0,
				TAU,
				24,
				PresentationPalette.with_alpha(
					&"shadow_veil",
					0.82,
					UITheme.high_contrast()
				),
				3.0
			)
		draw_rect(
			Rect2(
				state.position + Vector2(-18.0, 22.0),
				Vector2(36.0 * state.hp_ratio, 3.0)
			),
			PresentationPalette.color(
				(
					&"danger"
					if state.hp_ratio < 0.35
					else &"brass"
				),
				UITheme.high_contrast()
			)
		)


func _threat_color(kind: String) -> Color:
	match kind:
		"Pursuer":
			return PresentationPalette.color(
				&"pursuer_rust",
				UITheme.high_contrast()
			)
		"Boarder":
			return PresentationPalette.color(
				&"boarder_ochre",
				UITheme.high_contrast()
			)
		"Drainer":
			return PresentationPalette.color(
				&"drainer_glow",
				UITheme.high_contrast()
			)
		_:
			return PresentationPalette.color(&"danger", UITheme.high_contrast())


func _threat_outline() -> Color:
	return PresentationPalette.with_alpha(
		&"bone",
		0.9 if UITheme.high_contrast() else 0.48,
		UITheme.high_contrast()
	)


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
