class_name RunState
extends RefCounted
## RunState
##
## All runtime state for a run. Owned by game_world; not a singleton.
## Serializable via to_dict / apply_dict.

signal resources_changed()
signal power_changed()
signal locomotive_damaged(hp: float)
signal supplies_zero_started()
signal supplies_zero_ended()
signal car_destroyed(display_name: String, evacuated_names: Array)
signal crew_changed()

const JOURNEY_TARGET: float = 16000.0
const STATION_DISTANCE: float = 7600.0
const BOSS_DISTANCE: float = 14500.0
const BOSS_GATE_DISTANCE: float = 15700.0
const SNAPSHOT_VERSION: int = 2
const START_SLOT_CAPACITY: int = 4
const MAX_SLOT_CAPACITY: int = 5
const SLOT_EXPANSION_COST: int = 16
const SCRAP_MAX: float = 120.0
const SUPPLIES_MAX: float = 120.0
const LUMEN_MAX: float = 40.0

# ----- Progress -----
var distance: float = 0.0
var travel_time: float = 0.0
var run_seed: int = 0
var reveal_index: int = 0
var route_history: Array = []
var route_seen_ids: Array = []
var event_flags: Dictionary = {}
var station_completed: bool = false
var boss_triggered: bool = false
var boss_defeated: bool = false
var victory: bool = false
var defeat: bool = false
var run_history: Dictionary = {
	"detached_cars": [],
	"lost_crew": [],
	"purchased_cars": [],
	"upgrades": [],
	"boss_responses": []
}

# ----- Resources -----
var power_production_base: float = 3.0
var power: float = 6.0
var scrap: float = 8.0
var supplies: float = 52.0
var lumen: float = 10.0
var _supplies_zero_time: float = 0.0
var damage_roll_index: int = 0

# ----- Power priorities: engine, light, defense, repair -----
var priorities: Dictionary = {
	"engine": 1,
	"light": 2,
	"defense": 1,
	"repair": 1
}

# ----- Locomotive -----
var locomotive_max_hp: float = 120.0
var locomotive_hp: float = 120.0

# ----- Cars (array of dicts): {id, type, hp, max_hp, order, upgrade} -----
var cars: Array = []
var slot_capacity: int = START_SLOT_CAPACITY
var next_car_id: int = 1

# ----- Crew (assigned to stable car IDs) -----
var crew: Array = []

# ----- Lens -----
var current_lens: String = "Standard"
var lens_cooldown: float = 0.0
var focus_active_time: float = 0.0
var focus_cooldown: float = 0.0

# ----- Speed control -----
var paused: bool = false
var simulation_enabled: bool = true
var speed_scale: float = 1.0  # 1x or 2x
var detach_boost_time: float = 0.0
var external_speed_multiplier: float = 1.0
var distance_cap: float = JOURNEY_TARGET
var resume_grace_time: float = 0.0

# ----- Config caches -----
var cars_config: Dictionary
var lens_config: Dictionary
var enemy_config: Dictionary
var crew_config: Array
var events_config: Array
var frame_stats: TrainStats


func setup(run_seed_value: int, configs: Dictionary) -> void:
	run_seed = run_seed_value
	cars_config = configs.get("cars", {})
	lens_config = configs.get("lenses", {})
	enemy_config = configs.get("enemies", {})
	crew_config = configs.get("crew", [])
	events_config = configs.get("events", [])
	next_car_id = 1
	slot_capacity = START_SLOT_CAPACITY
	cars = [
		_new_car("Battery", 0),
		_new_car("Workshop", 1),
		_new_car("Passenger", 2)
	]
	crew = []
	for entry_variant in crew_config:
		var member: Dictionary = (entry_variant as Dictionary).duplicate(true)
		member["status"] = "fit"
		member["assigned_car_id"] = _default_assignment_for(String(member.get("id", "")))
		crew.append(member)
	refresh_stats()


func _new_car(type_key: String, order: int) -> Dictionary:
	var cfg: Dictionary = cars_config.get(type_key, {})
	var max_hp: float = float(cfg.get("max_integrity", 60))
	var car_id: String = "car-%03d" % next_car_id
	next_car_id += 1
	return {
		"id": car_id,
		"type": type_key,
		"display": cfg.get("display", type_key),
		"max_hp": max_hp,
		"hp": max_hp,
		"order": order,
		"boarders": 0,
		"upgrade": ""
	}


# --- Physics tick called from game_world (not _process). ---
func tick(delta: float) -> void:
	if is_simulation_paused() or victory or defeat:
		return
	var scaled: float = delta * speed_scale
	refresh_stats()
	travel_time += scaled
	distance = minf(distance_cap, distance + scaled * frame_stats.speed)
	power = clampf(power + frame_stats.power_net * scaled * 0.5, 0.0, 12.0)
	if lens_cooldown > 0.0:
		lens_cooldown = maxf(0.0, lens_cooldown - scaled)
	if focus_active_time > 0.0:
		focus_active_time = maxf(0.0, focus_active_time - scaled)
	if focus_cooldown > 0.0:
		focus_cooldown = maxf(0.0, focus_cooldown - scaled)
	if detach_boost_time > 0.0:
		detach_boost_time = maxf(0.0, detach_boost_time - scaled)
	var supply_rate: float = 0.07 + 0.012 * float(alive_crew_count())
	supplies = clampf(
		supplies
		- supply_rate * frame_stats.supply_efficiency * scaled
		+ frame_stats.supply_generation * scaled,
		0.0,
		SUPPLIES_MAX
	)
	lumen = clampf(lumen + frame_stats.lumen_generation * scaled, 0.0, LUMEN_MAX)
	_repair_tick(scaled)
	if supplies <= 0.0:
		if _supplies_zero_time == 0.0:
			emit_signal("supplies_zero_started")
		_supplies_zero_time += scaled
		if _supplies_zero_time > 25.0:
			locomotive_hp = maxf(0.0, locomotive_hp - 4.0 * scaled)
			emit_signal("locomotive_damaged", locomotive_hp)
			if locomotive_hp <= 0.0:
				defeat = true
	else:
		if _supplies_zero_time > 0.0:
			emit_signal("supplies_zero_ended")
		_supplies_zero_time = 0.0
	if resume_grace_time > 0.0:
		resume_grace_time = maxf(0.0, resume_grace_time - scaled)
	refresh_stats()
	emit_signal("resources_changed")
	emit_signal("power_changed")


func supply_efficiency_factor() -> float:
	return stats().supply_efficiency


func alive_crew_count() -> int:
	var count: int = 0
	for member_variant in crew:
		var member: Dictionary = member_variant
		if String(member.get("status", "fit")) == "fit":
			count += 1
	return count


func current_speed() -> float:
	return stats().speed


func current_power_net() -> float:
	refresh_stats()
	return frame_stats.power_net


func _has_car_type(type_key: String) -> bool:
	return has_car_type(type_key)


func has_car_type(type_key: String) -> bool:
	for car_variant in cars:
		var car: Dictionary = car_variant
		if String(car.get("type", "")) == type_key and float(car.get("hp", 0.0)) > 0.0:
			return true
	return false


func _car_powered(type_key: String) -> bool:
	return has_powered_car_type(type_key)


func has_powered_car_type(type_key: String) -> bool:
	return has_car_type(type_key) and power > 1.0


func is_car_powered(car: Dictionary) -> bool:
	return float(car.get("hp", 0.0)) > 0.0 and power > 1.0


func car_by_id(car_id: String) -> Dictionary:
	for car_variant in cars:
		var car: Dictionary = car_variant
		if String(car.get("id", "")) == car_id:
			return car
	return {}


func upgrade_effects(car: Dictionary) -> Dictionary:
	var upgrade_key: String = String(car.get("upgrade", ""))
	if upgrade_key.is_empty():
		return {}
	var cfg: Dictionary = cars_config.get(String(car.get("type", "")), {})
	var upgrades: Dictionary = cfg.get("upgrades", {})
	var upgrade: Dictionary = upgrades.get(upgrade_key, {})
	return (upgrade.get("effects", {}) as Dictionary).duplicate(true)


func is_crew_active(member: Dictionary) -> bool:
	if String(member.get("status", "fit")) != "fit":
		return false
	var car_id: String = String(member.get("assigned_car_id", ""))
	if car_id.is_empty():
		return false
	var car: Dictionary = car_by_id(car_id)
	return not car.is_empty() and float(car.get("hp", 0.0)) > 0.0


func active_crew_for_car(car_id: String) -> Array:
	var result: Array = []
	var car: Dictionary = car_by_id(car_id)
	if car.is_empty() or float(car.get("hp", 0.0)) <= 0.0:
		return result
	for member_variant in crew:
		var member: Dictionary = member_variant
		if (
			String(member.get("assigned_car_id", "")) == car_id
			and String(member.get("status", "fit")) == "fit"
		):
			result.append(member)
	return result


func refresh_stats() -> void:
	frame_stats = TrainStats.calculate(self)


func stats() -> TrainStats:
	if frame_stats == null:
		refresh_stats()
	return frame_stats


func is_simulation_paused() -> bool:
	return paused or not simulation_enabled


func _repair_tick(delta: float) -> void:
	var rate: float = stats().repair_rate
	if rate <= 0.0:
		return
	if locomotive_hp < locomotive_max_hp:
		locomotive_hp = minf(locomotive_max_hp, locomotive_hp + rate * 0.6 * delta)
	for car in cars:
		if car["hp"] < car["max_hp"]:
			car["hp"] = minf(car["max_hp"], car["hp"] + rate * 0.4 * delta)
			if float(car["hp"]) > 0.0:
				car["destroyed_notified"] = false


# --- Actions ---
func request_lens(lens_key: String) -> bool:
	if not lens_config.has(lens_key):
		return false
	if lens_cooldown > 0.0:
		return false
	current_lens = lens_key
	lens_cooldown = 4.0
	return true


func request_focus() -> bool:
	var current_stats: TrainStats = stats()
	if focus_cooldown > 0.0 or focus_active_time > 0.0:
		return false
	if lumen < current_stats.focus_cost:
		return false
	lumen = maxf(0.0, lumen - current_stats.focus_cost)
	focus_active_time = 1.8
	focus_cooldown = current_stats.focus_cooldown
	emit_signal("resources_changed")
	return true


func set_priority(role: String, level: int) -> void:
	if not priorities.has(role):
		return
	priorities[role] = clampi(level, 0, 3)
	refresh_stats()
	emit_signal("power_changed")


func cycle_priority(role: String) -> void:
	set_priority(role, (int(priorities[role]) + 1) % 4)


func change_priority(role: String, delta: int) -> void:
	if not priorities.has(role):
		return
	set_priority(role, posmod(int(priorities[role]) + delta, 4))


func toggle_pause() -> void:
	paused = not paused


func toggle_speed() -> void:
	if speed_scale >= 2.0:
		speed_scale = 1.0
	else:
		speed_scale = 2.0


func damage_locomotive(amount: float) -> void:
	locomotive_hp = maxf(0.0, locomotive_hp - amount)
	emit_signal("locomotive_damaged", locomotive_hp)
	if locomotive_hp <= 0.0:
		defeat = true


func damage_rear_car(amount: float) -> Dictionary:
	if cars.is_empty():
		damage_locomotive(amount)
		return {}
	var rear: Dictionary = cars[cars.size() - 1]
	rear["hp"] = maxf(0.0, float(rear["hp"]) - amount * stats().rear_damage_multiplier)
	if rear["hp"] <= 0.0:
		return _remove_destroyed_car(cars.size() - 1)
	return {}


func damage_random_car(amount: float) -> Dictionary:
	if cars.is_empty():
		damage_locomotive(amount)
		return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = posmod(run_seed + (damage_roll_index + 1) * 104729, 2147483647)
	damage_roll_index += 1
	var idx: int = rng.randi_range(0, cars.size() - 1)
	cars[idx]["hp"] = maxf(0.0, cars[idx]["hp"] - amount)
	if (
		float(cars[idx].get("hp", 0.0)) <= 0.0
		and not bool(cars[idx].get("destroyed_notified", false))
	):
		return _disable_destroyed_car(idx)
	return {}


func detach_rear_car() -> Dictionary:
	if cars.is_empty():
		return {}
	var rear: Dictionary = cars.pop_back()
	var crew_resolution: Dictionary = _resolve_crew_for_removed_car(rear, true)
	rear["lost_crew"] = crew_resolution.get("lost", [])
	rear["evacuated_crew"] = crew_resolution.get("evacuated", [])
	(run_history["detached_cars"] as Array).append({
		"type": String(rear.get("type", "")),
		"display": String(rear.get("display", "")),
		"upgrade": String(rear.get("upgrade", "")),
		"lost_crew": (rear["lost_crew"] as Array).duplicate()
	})
	_reindex_cars()
	refresh_stats()
	emit_signal("crew_changed")
	emit_signal("power_changed")
	return rear


func trigger_detach_boost(duration: float = -1.0) -> void:
	detach_boost_time = stats().detach_boost_duration if duration < 0.0 else duration


func add_car(type_key: String) -> bool:
	if cars.size() >= slot_capacity:
		return false
	if not cars_config.has(type_key):
		return false
	cars.append(_new_car(type_key, cars.size()))
	refresh_stats()
	return true


func rotate_rear_car_forward() -> bool:
	if cars.size() < 2:
		return false
	var rear: Dictionary = cars.pop_back()
	cars.push_front(rear)
	for index in range(cars.size()):
		cars[index]["order"] = index
	refresh_stats()
	return true


func apply_event_reward(rewards: Dictionary) -> void:
	for key in rewards.keys():
		var v: float = float(rewards[key])
		match key:
			"supplies":
				supplies = clampf(supplies + v, 0.0, SUPPLIES_MAX)
			"scrap":
				scrap = clampf(scrap + v, 0.0, SCRAP_MAX)
			"power":
				power = clampf(power + v, 0.0, 12.0)
			"lumen":
				lumen = clampf(lumen + v, 0.0, LUMEN_MAX)
			"crew_boost":
				supplies = clampf(supplies + 6.0, 0.0, SUPPLIES_MAX)
	emit_signal("resources_changed")


func apply_route_event(event: Dictionary) -> void:
	var effects: Array = event.get("effects", [])
	if effects.is_empty():
		apply_event_reward(event.get("rewards", {}))
	else:
		for effect_variant in effects:
			var effect: Dictionary = effect_variant
			match String(effect.get("op", "")):
				"resource":
					apply_event_reward({
						String(effect.get("key", "")): float(effect.get("amount", 0.0))
					})
				"damage_locomotive":
					damage_locomotive(float(effect.get("amount", 0.0)))
				"damage_rear":
					damage_rear_car(float(effect.get("amount", 0.0)))
				"repair_all":
					repair_train(float(effect.get("amount", 0.0)))
				"set_flag":
					event_flags[String(effect.get("key", ""))] = true
				"clear_flag":
					event_flags.erase(String(effect.get("key", "")))
	var event_id: String = String(event.get("id", ""))
	if not event_id.is_empty():
		route_history.append(event_id)
	if int(event.get("danger", 0)) > 0 and _has_upgrade("Workshop", "salvage_rig"):
		scrap = minf(SCRAP_MAX, scrap + 2.0)
	emit_signal("resources_changed")


func record_offered_routes(choices: Array) -> void:
	for choice_variant in choices:
		var choice: Dictionary = choice_variant
		var event_id: String = String(choice.get("id", ""))
		if not event_id.is_empty() and not route_seen_ids.has(event_id):
			route_seen_ids.append(event_id)


func reset_route_seen() -> void:
	route_seen_ids.clear()


func repair_train(amount: float) -> void:
	locomotive_hp = minf(locomotive_max_hp, locomotive_hp + amount)
	for car_variant in cars:
		var car: Dictionary = car_variant
		car["hp"] = minf(float(car.get("max_hp", 0.0)), float(car.get("hp", 0.0)) + amount)
		if float(car["hp"]) > 0.0:
			car["destroyed_notified"] = false


func car_purchase_cost(type_key: String) -> int:
	return int(cars_config.get(type_key, {}).get("cost", 10))


func repair_quote() -> int:
	var missing: float = locomotive_max_hp - locomotive_hp
	for car_variant in cars:
		var car: Dictionary = car_variant
		missing += float(car.get("max_hp", 0.0)) - float(car.get("hp", 0.0))
	if missing <= 0.01:
		return 0
	return clampi(int(ceil(missing / 12.0)), 4, 18)


func purchase_car(type_key: String) -> Dictionary:
	if not cars_config.has(type_key):
		return _result(false, "Unknown car type.")
	if cars.size() >= slot_capacity:
		return _result(false, "No open coupling slot.")
	var cost: int = car_purchase_cost(type_key)
	if scrap < cost:
		return _result(false, "Need %d scrap." % cost)
	scrap -= cost
	if not add_car(type_key):
		scrap += cost
		return _result(false, "Could not add the car.")
	(run_history["purchased_cars"] as Array).append(type_key)
	emit_signal("resources_changed")
	return _result(true, "%s coupled to the line." % String(cars_config[type_key].get("display", type_key)))


func purchase_slot() -> Dictionary:
	if slot_capacity >= MAX_SLOT_CAPACITY:
		return _result(false, "All coupling slots are already fitted.")
	if scrap < SLOT_EXPANSION_COST:
		return _result(false, "Need %d scrap." % SLOT_EXPANSION_COST)
	scrap -= SLOT_EXPANSION_COST
	slot_capacity += 1
	emit_signal("resources_changed")
	return _result(true, "Fifth coupling slot installed.")


func purchase_upgrade(car_id: String, upgrade_key: String) -> Dictionary:
	var car: Dictionary = car_by_id(car_id)
	if car.is_empty():
		return _result(false, "Car not found.")
	if not String(car.get("upgrade", "")).is_empty():
		return _result(false, "This car already has its permanent refit.")
	var cfg: Dictionary = cars_config.get(String(car.get("type", "")), {})
	var upgrades: Dictionary = cfg.get("upgrades", {})
	if not upgrades.has(upgrade_key):
		return _result(false, "Upgrade not available for this car.")
	var upgrade: Dictionary = upgrades[upgrade_key]
	var cost: int = int(upgrade.get("cost", 10))
	if scrap < cost:
		return _result(false, "Need %d scrap." % cost)
	scrap -= cost
	car["upgrade"] = upgrade_key
	(run_history["upgrades"] as Array).append({
		"car_id": car_id,
		"type": String(car.get("type", "")),
		"upgrade": upgrade_key
	})
	refresh_stats()
	emit_signal("resources_changed")
	emit_signal("power_changed")
	return _result(true, "%s refit installed." % String(upgrade.get("display", upgrade_key)))


func purchase_repair() -> Dictionary:
	var cost: int = repair_quote()
	if cost <= 0:
		return _result(false, "The train is already fully repaired.")
	if scrap < cost:
		return _result(false, "Need %d scrap." % cost)
	scrap -= cost
	locomotive_hp = locomotive_max_hp
	for car_variant in cars:
		var car: Dictionary = car_variant
		car["hp"] = car["max_hp"]
		car["destroyed_notified"] = false
	emit_signal("resources_changed")
	return _result(true, "The line is fully repaired.")


func move_car(car_id: String, offset: int) -> Dictionary:
	var from_index: int = -1
	for index in range(cars.size()):
		if String(cars[index].get("id", "")) == car_id:
			from_index = index
			break
	if from_index < 0:
		return _result(false, "Car not found.")
	var to_index: int = clampi(from_index + offset, 0, cars.size() - 1)
	if to_index == from_index:
		return _result(false, "Car is already at that end.")
	var car: Dictionary = cars.pop_at(from_index)
	cars.insert(to_index, car)
	_reindex_cars()
	refresh_stats()
	return _result(true, "Consist reordered.")


func assign_crew(crew_id: String, car_id: String) -> Dictionary:
	var member: Dictionary = {}
	for crew_variant in crew:
		var candidate: Dictionary = crew_variant
		if String(candidate.get("id", "")) == crew_id:
			member = candidate
			break
	if member.is_empty() or String(member.get("status", "fit")) != "fit":
		return _result(false, "Crew member is unavailable.")
	if car_id.is_empty():
		member["assigned_car_id"] = ""
		emit_signal("crew_changed")
		refresh_stats()
		return _result(true, "%s is unassigned." % String(member.get("name", "Crew")))
	var car: Dictionary = car_by_id(car_id)
	if car.is_empty():
		return _result(false, "Car not found.")
	var compatible: Array = member.get("compatible_cars", [])
	if not compatible.is_empty() and not compatible.has(String(car.get("type", ""))):
		return _result(false, "%s cannot work in that car." % String(member.get("name", "Crew")))
	var occupants: Array = active_crew_for_car(car_id)
	var already_here: bool = String(member.get("assigned_car_id", "")) == car_id
	var slots: int = crew_slots_for_car(car)
	if occupants.size() >= slots and not already_here:
		return _result(false, "That car has no open crew post.")
	member["assigned_car_id"] = car_id
	emit_signal("crew_changed")
	refresh_stats()
	return _result(true, "%s assigned to %s." % [
		String(member.get("name", "Crew")),
		String(car.get("display", car.get("type", "car")))
	])


func crew_slots_for_car(car: Dictionary) -> int:
	var cfg: Dictionary = cars_config.get(String(car.get("type", "")), {})
	return maxi(0, int(cfg.get("crew_slots", 0)) + int(upgrade_effects(car).get("crew_slots", 0)))


func detach_preview() -> Dictionary:
	if cars.is_empty():
		return {}
	var rear: Dictionary = cars.back()
	var assigned: Array = active_crew_for_car(String(rear.get("id", "")))
	var names: Array = []
	for member_variant in assigned:
		var member: Dictionary = member_variant
		names.append(String(member.get("name", "Crew")))
	var protected: bool = bool(upgrade_effects(rear).get("crew_detach_protection", false))
	return {
		"display": String(rear.get("display", rear.get("type", "Rear car"))),
		"crew_names": names,
		"crew_protected": protected
	}


func journey_ratio() -> float:
	return clampf(distance / JOURNEY_TARGET, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"snapshot_version": SNAPSHOT_VERSION,
		"run_seed": run_seed,
		"distance": distance,
		"travel_time": travel_time,
		"reveal_index": reveal_index,
		"route_history": route_history.duplicate(true),
		"route_seen_ids": route_seen_ids.duplicate(true),
		"event_flags": event_flags.duplicate(true),
		"station_completed": station_completed,
		"boss_triggered": boss_triggered,
		"boss_defeated": boss_defeated,
		"power": power,
		"scrap": scrap,
		"supplies": supplies,
		"lumen": lumen,
		"priorities": priorities,
		"current_lens": current_lens,
		"lens_cooldown": lens_cooldown,
		"focus_active_time": focus_active_time,
		"focus_cooldown": focus_cooldown,
		"locomotive_hp": locomotive_hp,
		"supplies_zero_time": _supplies_zero_time,
		"damage_roll_index": damage_roll_index,
		"speed_scale": speed_scale,
		"detach_boost_time": detach_boost_time,
		"slot_capacity": slot_capacity,
		"next_car_id": next_car_id,
		"cars": cars.duplicate(true),
		"crew": crew.duplicate(true),
		"run_history": run_history.duplicate(true)
	}


func apply_dict(d: Dictionary) -> void:
	var source_version := int(d.get("snapshot_version", 1))
	run_seed = int(d.get("run_seed", run_seed))
	distance = float(d.get("distance", 0.0))
	travel_time = float(d.get("travel_time", 0.0))
	reveal_index = int(d.get("reveal_index", 0))
	route_history = (d.get("route_history", []) as Array).duplicate(true)
	route_seen_ids = (d.get("route_seen_ids", []) as Array).duplicate(true)
	event_flags = (d.get("event_flags", {}) as Dictionary).duplicate(true)
	station_completed = bool(d.get("station_completed", false))
	boss_triggered = bool(d.get("boss_triggered", false))
	boss_defeated = bool(d.get("boss_defeated", false))
	power = float(d.get("power", 6.0))
	scrap = float(d.get("scrap", 8.0))
	supplies = float(d.get("supplies", 40.0))
	lumen = float(d.get("lumen", 10.0))
	priorities = d.get("priorities", priorities).duplicate(true)
	current_lens = String(d.get("current_lens", "Standard"))
	lens_cooldown = maxf(0.0, float(d.get("lens_cooldown", 0.0)))
	focus_active_time = maxf(0.0, float(d.get("focus_active_time", 0.0)))
	focus_cooldown = maxf(0.0, float(d.get("focus_cooldown", 0.0)))
	locomotive_hp = float(d.get("locomotive_hp", locomotive_max_hp))
	_supplies_zero_time = maxf(0.0, float(d.get("supplies_zero_time", 0.0)))
	damage_roll_index = maxi(0, int(d.get("damage_roll_index", 0)))
	speed_scale = 2.0 if float(d.get("speed_scale", 1.0)) >= 2.0 else 1.0
	detach_boost_time = maxf(0.0, float(d.get("detach_boost_time", 0.0)))
	if d.has("cars"):
		cars = (d["cars"] as Array).duplicate(true)
	if d.has("crew"):
		crew = (d["crew"] as Array).duplicate(true)
	slot_capacity = clampi(
		int(d.get("slot_capacity", maxi(START_SLOT_CAPACITY, cars.size()))),
		maxi(START_SLOT_CAPACITY, cars.size()),
		MAX_SLOT_CAPACITY
	)
	next_car_id = maxi(1, int(d.get("next_car_id", 1)))
	run_history = (d.get("run_history", run_history) as Dictionary).duplicate(true)
	_normalize_cars()
	_normalize_crew(source_version < SNAPSHOT_VERSION)
	_normalize_history()
	refresh_stats()


func _remove_destroyed_car(index: int) -> Dictionary:
	if index < 0 or index >= cars.size():
		return {}
	var removed: Dictionary = cars.pop_at(index)
	var resolution: Dictionary = _resolve_crew_for_removed_car(removed, false)
	_reindex_cars()
	refresh_stats()
	emit_signal(
		"car_destroyed",
		String(removed.get("display", removed.get("type", "Car"))),
		resolution.get("evacuated", [])
	)
	emit_signal("crew_changed")
	emit_signal("power_changed")
	return {
		"destroyed": true,
		"type": String(removed.get("type", "")),
		"display": String(removed.get("display", "")),
		"car_id": String(removed.get("id", "")),
		"evacuated_crew": resolution.get("evacuated", [])
	}


func _disable_destroyed_car(index: int) -> Dictionary:
	if index < 0 or index >= cars.size():
		return {}
	var car: Dictionary = cars[index]
	car["hp"] = 0.0
	car["destroyed_notified"] = true
	var resolution: Dictionary = _resolve_crew_for_removed_car(car, false)
	refresh_stats()
	emit_signal(
		"car_destroyed",
		String(car.get("display", car.get("type", "Car"))),
		resolution.get("evacuated", [])
	)
	emit_signal("crew_changed")
	emit_signal("power_changed")
	return {
		"destroyed": true,
		"type": String(car.get("type", "")),
		"display": String(car.get("display", "")),
		"car_id": String(car.get("id", "")),
		"evacuated_crew": resolution.get("evacuated", [])
	}


func _resolve_crew_for_removed_car(car: Dictionary, deliberate: bool) -> Dictionary:
	var car_id: String = String(car.get("id", ""))
	var protected: bool = bool(upgrade_effects(car).get("crew_detach_protection", false))
	var lost_names: Array = []
	var evacuated_names: Array = []
	for member_variant in crew:
		var member: Dictionary = member_variant
		if String(member.get("assigned_car_id", "")) != car_id:
			continue
		member["assigned_car_id"] = ""
		if deliberate and not protected:
			member["status"] = "lost"
			var lost_name: String = String(member.get("name", "Crew"))
			lost_names.append(lost_name)
			if not (run_history["lost_crew"] as Array).has(String(member.get("id", ""))):
				(run_history["lost_crew"] as Array).append(String(member.get("id", "")))
		else:
			evacuated_names.append(String(member.get("name", "Crew")))
	return {"lost": lost_names, "evacuated": evacuated_names}


func _normalize_cars() -> void:
	var used_ids: Dictionary = {}
	var highest_id: int = 0
	for index in range(cars.size()):
		var car: Dictionary = cars[index]
		var type_key: String = String(car.get("type", "Utility"))
		var cfg: Dictionary = cars_config.get(type_key, {})
		var car_id: String = String(car.get("id", ""))
		if car_id.is_empty() or used_ids.has(car_id):
			car_id = "car-%03d" % maxi(1, next_car_id)
			next_car_id = maxi(1, next_car_id) + 1
		car["id"] = car_id
		used_ids[car_id] = true
		var pieces: PackedStringArray = car_id.split("-")
		if pieces.size() == 2 and pieces[1].is_valid_int():
			highest_id = maxi(highest_id, int(pieces[1]))
		car["display"] = String(car.get("display", cfg.get("display", type_key)))
		car["max_hp"] = float(car.get("max_hp", cfg.get("max_integrity", 60.0)))
		car["hp"] = clampf(float(car.get("hp", car["max_hp"])), 0.0, float(car["max_hp"]))
		car["order"] = index
		car["boarders"] = maxi(0, int(car.get("boarders", 0)))
		car["destroyed_notified"] = (
			bool(car.get("destroyed_notified", false))
			and float(car.get("hp", 0.0)) <= 0.0
		)
		var upgrade_key: String = String(car.get("upgrade", ""))
		if not (cfg.get("upgrades", {}) as Dictionary).has(upgrade_key):
			upgrade_key = ""
		car["upgrade"] = upgrade_key
	next_car_id = maxi(next_car_id, highest_id + 1)


func _normalize_crew(is_legacy: bool) -> void:
	var config_by_id: Dictionary = {}
	for entry_variant in crew_config:
		var entry: Dictionary = entry_variant
		config_by_id[String(entry.get("id", ""))] = entry
	for member_variant in crew:
		var member: Dictionary = member_variant
		var member_id: String = String(member.get("id", ""))
		var cfg: Dictionary = config_by_id.get(member_id, {})
		for key in cfg.keys():
			if not member.has(key):
				member[key] = cfg[key]
		if not (member.get("bonus", null) is Dictionary):
			member["bonus"] = (cfg.get("bonus", {}) as Dictionary).duplicate(true)
		member["status"] = String(
			member.get("status", "fit" if bool(member.get("alive", true)) else "lost")
		)
		var assigned_car_id: String = String(member.get("assigned_car_id", ""))
		if is_legacy and not member.has("assigned_car_id"):
			member["assigned_car_id"] = _legacy_assignment_for(member)
		elif not assigned_car_id.is_empty() and car_by_id(assigned_car_id).is_empty():
			member["assigned_car_id"] = ""
		member.erase("assigned_role")


func _normalize_history() -> void:
	for key in ["detached_cars", "lost_crew", "purchased_cars", "upgrades", "boss_responses"]:
		if not run_history.has(key) or typeof(run_history[key]) != TYPE_ARRAY:
			run_history[key] = []


func _default_assignment_for(crew_id: String) -> String:
	match crew_id:
		"mara", "orrin":
			return _first_car_id_of_type("Workshop")
		"sable":
			return _first_car_id_of_type("Passenger")
		"ilo":
			return _first_car_id_of_type("Defense")
		_:
			return ""


func _legacy_assignment_for(member: Dictionary) -> String:
	var role: String = String(member.get("assigned_role", "")).to_lower()
	match role:
		"engine", "repair":
			return _first_car_id_of_type("Workshop")
		"defense":
			return _first_car_id_of_type("Defense")
		"light":
			return _first_car_id_of_type("Passenger")
		_:
			return _default_assignment_for(String(member.get("id", "")))


func _first_car_id_of_type(type_key: String) -> String:
	for car_variant in cars:
		var car: Dictionary = car_variant
		if String(car.get("type", "")) == type_key:
			return String(car.get("id", ""))
	return ""


func _reindex_cars() -> void:
	for index in range(cars.size()):
		cars[index]["order"] = index


func _has_upgrade(type_key: String, upgrade_key: String) -> bool:
	for car_variant in cars:
		var car: Dictionary = car_variant
		if (
			String(car.get("type", "")) == type_key
			and String(car.get("upgrade", "")) == upgrade_key
			and float(car.get("hp", 0.0)) > 0.0
		):
			return true
	return false


func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
