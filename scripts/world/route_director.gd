class_name RouteDirector
extends RefCounted
## RouteDirector
##
## Deterministic route reveals derived from run_seed + reveal index.
## Owns event pool; selection is weighted by active lens bias.

var _events: Array
var _lenses: Dictionary
var _run_seed: int

const VALID_EFFECTS: Array[String] = [
	"resource",
	"damage_locomotive",
	"damage_rear",
	"repair_all",
	"set_flag",
	"clear_flag"
]
const VALID_RESOURCES: Array[String] = ["supplies", "scrap", "power", "lumen", "crew_boost"]


func setup(run_seed: int, events: Array, lenses: Dictionary) -> void:
	_run_seed = run_seed
	_events = events
	_lenses = lenses


func generate_choices(
	reveal_index: int,
	lens_key: String,
	seen_ids: Array = [],
	flags: Dictionary = {}
) -> Array:
	var lens: Dictionary = _lenses.get(lens_key, {})
	var bias: Dictionary = lens.get("weight_bias", {"living": 1.0, "machinery": 1.0, "danger": 1.0})
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _hash_seed(_run_seed, reveal_index)
	var eligible: Array = []
	for event_variant in _events:
		var event: Dictionary = event_variant
		if _is_valid_event(event) and _conditions_met(event, flags):
			eligible.append(event)
	var pool: Array = eligible.filter(func(event: Dictionary) -> bool:
		return not seen_ids.has(String(event.get("id", "")))
	)
	if pool.size() < 3:
		pool = eligible
	_shuffle(pool, rng)
	var weighted: Array = []
	for e in pool:
		var w: float = float(bias.get(String(e.get("category", "living")), 1.0))
		weighted.append({"event": e, "weight": maxf(0.05, w)})
	var chosen: Array = []
	var positions: Array = ["upper", "middle", "lower"]
	for i in range(3):
		if weighted.is_empty():
			break
		var pick_i: int = _weighted_pick(weighted, rng)
		var entry: Dictionary = weighted[pick_i]
		var ev: Dictionary = entry["event"].duplicate(true)
		ev["position"] = positions[i]
		chosen.append(ev)
		weighted.remove_at(pick_i)
	return chosen


func _conditions_met(event: Dictionary, flags: Dictionary) -> bool:
	for required_variant in event.get("requires_flags", []):
		if not bool(flags.get(String(required_variant), false)):
			return false
	for excluded_variant in event.get("excludes_flags", []):
		if bool(flags.get(String(excluded_variant), false)):
			return false
	return true


func _is_valid_event(event: Dictionary) -> bool:
	if String(event.get("id", "")).is_empty():
		return false
	if not ["living", "machinery", "danger"].has(String(event.get("category", ""))):
		return false
	var effects: Array = event.get("effects", [])
	for effect_variant in effects:
		if not (effect_variant is Dictionary):
			return false
		var effect: Dictionary = effect_variant
		var operation := String(effect.get("op", ""))
		if not VALID_EFFECTS.has(operation):
			return false
		if operation == "resource" and not VALID_RESOURCES.has(String(effect.get("key", ""))):
			return false
	return true


func _hash_seed(seed_value: int, index: int) -> int:
	var mix: int = seed_value ^ ((index + 1) * 2654435761)
	if mix < 0:
		mix = -mix
	return mix % 2147483647


func _weighted_pick(entries: Array, rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for e in entries:
		total += float(e["weight"])
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(entries.size()):
		acc += float(entries[i]["weight"])
		if r <= acc:
			return i
	return entries.size() - 1


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
