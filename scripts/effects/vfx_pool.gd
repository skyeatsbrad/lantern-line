class_name VfxPool
extends Node2D
## Routed M2 effects view. The vector EffectsLayer remains the default; this
## pooled placeholder proves the effects category can switch independently.

const CONSUMER_ID: String = "view.vfx_pool"
const POOL_CAPACITY: int = 32

var _snapshot: PresentationSnapshot
var _profile: String = PresentationProfile.HIGH
var _features: Dictionary = {}
var _baked_enabled: bool = false
var _assets_attached: bool = false
var _bursts: Array[VfxBurstState] = []
var _next_slot: int = 0
var _reference_capture_enabled: bool = false


func _init() -> void:
	_bursts.resize(POOL_CAPACITY)
	for index in range(POOL_CAPACITY):
		_bursts[index] = VfxBurstState.new()


func _ready() -> void:
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not _baked_enabled:
		return
	if _reference_capture_enabled:
		queue_redraw()
		return
	for burst in _bursts:
		if not burst.active:
			continue
		burst.age += delta
		if burst.age >= burst.duration:
			burst.clear()
	queue_redraw()


func update_snapshot(snapshot: PresentationSnapshot) -> void:
	_snapshot = snapshot
	queue_redraw()


func on_event(event: Variant) -> void:
	if not _baked_enabled:
		return
	if event is SimEvent:
		_add_burst(
			event.type,
			event.position,
			event.direction,
			event.strength,
			event.sequence
		)
	elif event is PresentationEvent:
		_add_burst(
			event.type,
			event.position,
			event.direction,
			event.strength,
			event.sequence
		)


func on_sim_event(event: SimEvent) -> void:
	on_event(event)


func on_presentation_event(event: PresentationEvent) -> void:
	on_event(event)


func set_reference_capture_state(enabled: bool, _frame_time: float) -> void:
	if enabled and not _reference_capture_enabled:
		for burst in _bursts:
			burst.clear()
		_next_slot = 0
	_reference_capture_enabled = enabled
	queue_redraw()


func _add_burst(
	type: StringName,
	position: Vector2,
	direction: Vector2,
	strength: float,
	sequence: int
) -> void:
	var burst: VfxBurstState = _bursts[_next_slot]
	_next_slot = (_next_slot + 1) % _bursts.size()
	burst.active = true
	burst.type = type
	burst.position = position
	burst.direction = direction
	burst.strength = strength
	burst.age = 0.0
	burst.duration = _duration_for(type)
	burst.sequence = sequence
	queue_redraw()


func set_baked_enabled(enabled: bool) -> void:
	if _baked_enabled == enabled:
		return
	_baked_enabled = enabled
	visible = enabled
	if not enabled:
		for burst in _bursts:
			burst.clear()
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
	var high_contrast: bool = _snapshot.high_contrast
	if _snapshot.dawn_progress > 0.0:
		draw_rect(
			Rect2(Vector2.ZERO, _snapshot.view_size),
			PresentationPalette.with_alpha(
				&"bone",
				_snapshot.dawn_progress * 0.12,
				high_contrast
			)
		)
	for burst in _bursts:
		if not burst.active:
			continue
		var progress: float = clampf(
			burst.age / maxf(0.001, burst.duration),
			0.0,
			1.0
		)
		var alpha: float = 1.0 - progress
		var radius: float = 10.0 + progress * (
			10.0 + minf(absf(burst.strength), 24.0)
		)
		var token: StringName = _color_token_for(burst.type)
		draw_arc(
			burst.position,
			radius,
			0.0,
			TAU,
			20,
			PresentationPalette.with_alpha(token, alpha, high_contrast),
			2.5
		)
		if not _snapshot.reduced_motion:
			draw_line(
				burst.position,
				burst.position + burst.direction * radius * 1.5,
				PresentationPalette.with_alpha(
					token,
					alpha * 0.75,
					high_contrast
				),
				2.0
			)


static func _duration_for(type: StringName) -> float:
	if type in [
		SimEvent.TYPE_WARD_SHATTERED,
		SimEvent.TYPE_DETACH_RELEASED,
		SimEvent.TYPE_BOSS_PHASE_ENTRY,
		SimEvent.TYPE_BOSS_DEFEAT,
		SimEvent.TYPE_DAWN_ARRIVAL
	]:
		return 0.9
	if type in [
		PresentationEvent.TYPE_CAMERA_IMPULSE,
		PresentationEvent.TYPE_PARTICLE_BURST,
		PresentationEvent.TYPE_UI_EMPHASIS
	]:
		return 0.7
	return 0.45


static func _color_token_for(type: StringName) -> StringName:
	if type in [
		SimEvent.TYPE_BOSS_PHASE_ENTRY,
		SimEvent.TYPE_BOSS_ATTACK,
		SimEvent.TYPE_BOSS_DEFEAT,
		SimEvent.TYPE_WARD_CRACKED,
		SimEvent.TYPE_WARD_SHATTERED
	]:
		return &"shadow_veil"
	if type in [
		SimEvent.TYPE_TRAIN_HIT,
		SimEvent.TYPE_CAR_HIT,
		SimEvent.TYPE_CAR_CRITICAL,
		SimEvent.TYPE_CAR_DESTROYED
	]:
		return &"danger"
	if type == SimEvent.TYPE_DAWN_ARRIVAL:
		return &"bone"
	if type in [
		PresentationEvent.TYPE_PARTICLE_BURST,
		PresentationEvent.TYPE_UI_EMPHASIS
	]:
		return &"cold_signal"
	return &"ember"
