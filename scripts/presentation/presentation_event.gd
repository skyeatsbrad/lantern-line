class_name PresentationEvent
extends RefCounted
## PresentationEvent
##
## Pooled one-shot presentation-only event, emitted by views/effects/UI and
## consumed by other presentation systems (audio, screen shake, HUD flourishes,
## camera impulses). Never touches simulation state and is never emitted by
## simulation owners. Consumers must not retain the record after the
## synchronous callback returns because the bus immediately recycles it.

const TYPE_BEAM_ACQUIRED: StringName = &"beam.acquired"
const TYPE_BEAM_FOCUSED: StringName = &"beam.focused"
const TYPE_DETACH_ARMED: StringName = &"detach.armed"
const TYPE_DETACH_CANCELED: StringName = &"detach.canceled"
const TYPE_DETACH_FLOURISH: StringName = &"detach.flourish"
const TYPE_CAMERA_IMPULSE: StringName = &"camera.impulse"
const TYPE_PARTICLE_BURST: StringName = &"particle.burst"
const TYPE_UI_EMPHASIS: StringName = &"ui.emphasis"

const ALL_TYPES: Array[StringName] = [
	TYPE_BEAM_ACQUIRED,
	TYPE_BEAM_FOCUSED,
	TYPE_DETACH_ARMED,
	TYPE_DETACH_CANCELED,
	TYPE_DETACH_FLOURISH,
	TYPE_CAMERA_IMPULSE,
	TYPE_PARTICLE_BURST,
	TYPE_UI_EMPHASIS
]

var type: StringName = TYPE_UI_EMPHASIS
var producer_id: String = ""
var source_id: String = ""
var timestamp: float = 0.0
var sequence: int = 0
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var strength: float = 0.0
var material: StringName = &"none"
var payload: Dictionary = {}


func reset() -> void:
	type = TYPE_UI_EMPHASIS
	producer_id = ""
	source_id = ""
	timestamp = 0.0
	sequence = 0
	position = Vector2.ZERO
	direction = Vector2.RIGHT
	strength = 0.0
	material = &"none"
	payload.clear()


func snapshot() -> Dictionary:
	return {
		"type": String(type),
		"producer_id": producer_id,
		"source_id": source_id,
		"timestamp": timestamp,
		"sequence": sequence,
		"position": [position.x, position.y],
		"direction": [direction.x, direction.y],
		"strength": strength,
		"material": String(material),
		"payload": payload.duplicate(true)
	}
