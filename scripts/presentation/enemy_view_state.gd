class_name EnemyViewState
extends RefCounted
## EnemyViewState
##
## Reusable snapshot record for a single enemy, populated by EnemyDirector
## after its simulation tick and consumed read-only by EnemyViewPool. Pooled
## inside PresentationSnapshot; never allocated per frame.

var visual_id: int = 0
var stable_id: String = ""
var kind: String = "Pursuer"
var role: String = "ground"
var alive: bool = false
var position: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var hp_ratio: float = 1.0
var max_hp: float = 1.0
var attack_timer: float = 0.0
var attack_warning_time: float = 0.65
var attack_ratio: float = 0.0
var warded: bool = false
var ward_hp_ratio: float = 0.0
var boarder_car_index: int = -1


func clear() -> void:
	visual_id = 0
	stable_id = ""
	kind = "Pursuer"
	role = "ground"
	alive = false
	position = Vector2.ZERO
	target = Vector2.ZERO
	hp_ratio = 1.0
	max_hp = 1.0
	attack_timer = 0.0
	attack_warning_time = 0.65
	attack_ratio = 0.0
	warded = false
	ward_hp_ratio = 0.0
	boarder_car_index = -1
