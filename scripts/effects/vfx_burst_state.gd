class_name VfxBurstState
extends RefCounted
## Reusable one-shot placeholder effect state for VfxPool.

var active: bool = false
var type: StringName = &""
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var strength: float = 0.0
var age: float = 0.0
var duration: float = 0.45
var sequence: int = 0


func clear() -> void:
	active = false
	type = &""
	position = Vector2.ZERO
	direction = Vector2.RIGHT
	strength = 0.0
	age = 0.0
	duration = 0.45
	sequence = 0
