class_name CarViewState
extends RefCounted
## Reusable per-car presentation record owned by PresentationSnapshot.

var id: String = ""
var stable_id: String = ""
var car_type: String = ""
var upgrade: String = ""
var order: int = 0
var hp: float = 0.0
var max_hp: float = 1.0
var hp_ratio: float = 1.0


func clear() -> void:
	id = ""
	stable_id = ""
	car_type = ""
	upgrade = ""
	order = 0
	hp = 0.0
	max_hp = 1.0
	hp_ratio = 1.0


func populate(car: Dictionary) -> void:
	id = String(car.get("id", ""))
	stable_id = VisualStateIds.car(id)
	car_type = String(car.get("type", ""))
	upgrade = String(car.get("upgrade", ""))
	order = int(car.get("order", 0))
	max_hp = maxf(1.0, float(car.get("max_hp", 1.0)))
	hp = float(car.get("hp", max_hp))
	hp_ratio = clampf(hp / max_hp, 0.0, 1.0)
