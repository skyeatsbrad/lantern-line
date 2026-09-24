class_name VisualStateIds
extends RefCounted
## VisualStateIds
##
## Stable, deterministic string identifiers that persist across ticks so views
## and future animation state machines can address individual visual entities
## by identity rather than by transient array positions. Simulation owns these
## ids; views only read them.

const TRAIN_LOCOMOTIVE: String = "train:locomotive"
const WORLD_ROOT: String = "world:root"
const LONGSHADOW_ROOT: String = "longshadow:root"


static func train() -> String:
	return TRAIN_LOCOMOTIVE


static func world_root() -> String:
	return WORLD_ROOT


static func world_context(category: String) -> String:
	var key: String = "" if category == null else String(category).strip_edges().to_lower()
	if key.is_empty():
		key = "neutral"
	return "world:%s" % key


static func car(car_id: String) -> String:
	if car_id.is_empty():
		return "car:unknown"
	return "car:%s" % car_id


static func enemy(visual_id: int) -> String:
	return "enemy:%06d" % maxi(0, visual_id)


static func enemy_ward(visual_id: int) -> String:
	return "enemy_ward:%06d" % maxi(0, visual_id)


static func longshadow_root() -> String:
	return LONGSHADOW_ROOT


static func longshadow_phase(phase_index: int) -> String:
	var phases: Array[String] = ["veil", "tether", "charge"]
	if phase_index < 0 or phase_index >= phases.size():
		return "longshadow:unknown"
	return "longshadow:%s" % phases[phase_index]


static func crew(crew_id: String) -> String:
	if crew_id.is_empty():
		return "crew:unknown"
	return "crew:%s" % crew_id


static func defense_mount(car_id: String) -> String:
	if car_id.is_empty():
		return "defense:unknown"
	return "defense:%s" % car_id
