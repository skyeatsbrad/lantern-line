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

const JOURNEY_TARGET: float = 16000.0
const STATION_DISTANCE: float = 7600.0
const BOSS_DISTANCE: float = 14500.0

# ----- Progress -----
var distance: float = 0.0
var travel_time: float = 0.0
var run_seed: int = 0
var reveal_index: int = 0
var station_completed: bool = false
var boss_triggered: bool = false
var boss_defeated: bool = false
var victory: bool = false
var defeat: bool = false

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

# ----- Cars (array of dicts): {type, hp, max_hp, order} -----
var cars: Array = []

# ----- Crew (assigned to power roles) -----
var crew: Array = []  # each dict has id, name, trait, bonus, assigned_role

# ----- Lens -----
var current_lens: String = "Standard"
var lens_cooldown: float = 0.0

# ----- Speed control -----
var paused: bool = false
var speed_scale: float = 1.0  # 1x or 2x
var detach_boost_time: float = 0.0

# ----- Config caches -----
var cars_config: Dictionary
var lens_config: Dictionary
var enemy_config: Dictionary
var crew_config: Array
var events_config: Array


func setup(run_seed_value: int, configs: Dictionary) -> void:
	run_seed = run_seed_value
	cars_config = configs.get("cars", {})
	lens_config = configs.get("lenses", {})
	enemy_config = configs.get("enemies", {})
	crew_config = configs.get("crew", [])
	events_config = configs.get("events", [])
	# default starting cars
	cars = [
		_new_car("Battery", 0),
		_new_car("Workshop", 1),
		_new_car("Passenger", 2)
	]
	# crew
	crew = []
	for entry in crew_config:
		var d: Dictionary = entry
		d = d.duplicate(true)
		d["assigned_role"] = ["engine", "defense", "light", "repair"][crew.size() % 4]
		crew.append(d)


func _new_car(type_key: String, order: int) -> Dictionary:
	var cfg: Dictionary = cars_config.get(type_key, {})
	var max_hp: float = float(cfg.get("max_integrity", 60))
	return {
		"type": type_key,
		"display": cfg.get("display", type_key),
		"max_hp": max_hp,
		"hp": max_hp,
		"order": order,
		"boarders": 0
	}


# --- Physics tick called from game_world (not _process). ---
func tick(delta: float) -> void:
	if paused or victory or defeat:
		return
	var scaled: float = delta * speed_scale
	travel_time += scaled
	distance += scaled * current_speed()
	# power balance
	var net: float = current_power_net()
	# Buffer power in a small range 0..12
	power = clampf(power + net * scaled * 0.5, 0.0, 12.0)
	# lens cooldown
	if lens_cooldown > 0.0:
		lens_cooldown = maxf(0.0, lens_cooldown - scaled)
	if detach_boost_time > 0.0:
		detach_boost_time = maxf(0.0, detach_boost_time - scaled)
	# supplies consumption (crew + baseline)
	var supply_rate: float = 0.07 + 0.012 * float(alive_crew_count())
	var eff: float = supply_efficiency_factor()
	supplies = maxf(0.0, supplies - supply_rate * eff * scaled)
	# greenhouse production if powered
	if _car_powered("Greenhouse"):
		supplies = minf(120.0, supplies + 0.11 * scaled)
	# repair pass on cars/locomotive
	_repair_tick(scaled)
	# supplies starvation timer
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
	emit_signal("resources_changed")
	emit_signal("power_changed")


func supply_efficiency_factor() -> float:
	var f: float = 1.0
	if _has_car_type("Passenger"):
		f *= 0.85
	for c in crew:
		if c.get("id") == "sable" and _car_powered("Passenger"):
			f *= 0.85
	return f


func alive_crew_count() -> int:
	return crew.size()


func current_speed() -> float:
	var base: float = 26.0 + 5.0 * float(priorities["engine"])
	var eff: float = 1.0
	for c in crew:
		if c.get("id") == "mara" and priorities["engine"] >= 2 and power > 3.0:
			eff *= 1.0 + float(c["bonus"]["engine_efficiency"])
	# heavier train slower
	var weight: float = 1.0
	for car in cars:
		var cfg: Dictionary = cars_config.get(car["type"], {})
		weight += float(cfg.get("weight", 1.0)) * 0.1
	var power_factor: float = lerpf(0.55, 1.0, clampf(power / 6.0, 0.0, 1.0))
	var detach_factor: float = 1.35 if detach_boost_time > 0.0 else 1.0
	return base * eff * power_factor * detach_factor / weight


func current_power_net() -> float:
	# Sum production - sum draw. Battery cars produce power.
	var prod: float = power_production_base
	var draw: float = 0.0
	for car in cars:
		if float(car.get("hp", 0.0)) <= 0.0:
			continue
		var cfg: Dictionary = cars_config.get(car["type"], {})
		prod += float(cfg.get("power_production", 0.0))
		draw += float(cfg.get("power_draw", 0.0))
	# Higher priorities are powerful, but running every system hot drains the buffer.
	draw += float(priorities["engine"]) * 0.85
	draw += float(priorities["light"]) * 0.75
	draw += float(priorities["defense"]) * 0.9
	draw += float(priorities["repair"]) * 0.7
	return prod - draw


func _has_car_type(type_key: String) -> bool:
	for c in cars:
		if c["type"] == type_key and c["hp"] > 0.0:
			return true
	return false


func _car_powered(type_key: String) -> bool:
	return _has_car_type(type_key) and power > 1.0


func _repair_tick(delta: float) -> void:
	if priorities["repair"] <= 0:
		return
	var rate: float = 1.0 * float(priorities["repair"])
	if _has_car_type("Workshop") and _car_powered("Workshop"):
		rate *= 1.6
	for c in crew:
		if c.get("id") == "orrin" and _has_car_type("Workshop"):
			rate *= 1.0 + float(c["bonus"].get("repair_bonus", 0.0))
	# Repair locomotive priority, then cars low HP first
	if locomotive_hp < locomotive_max_hp:
		locomotive_hp = minf(locomotive_max_hp, locomotive_hp + rate * 0.6 * delta)
	for car in cars:
		if car["hp"] < car["max_hp"]:
			car["hp"] = minf(car["max_hp"], car["hp"] + rate * 0.4 * delta)


# --- Actions ---
func request_lens(lens_key: String) -> bool:
	if not lens_config.has(lens_key):
		return false
	if lens_cooldown > 0.0:
		return false
	current_lens = lens_key
	lens_cooldown = 4.0
	return true


func set_priority(role: String, level: int) -> void:
	if not priorities.has(role):
		return
	priorities[role] = clampi(level, 0, 3)


func cycle_priority(role: String) -> void:
	set_priority(role, (int(priorities[role]) + 1) % 4)


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
	rear["hp"] = maxf(0.0, rear["hp"] - amount)
	if rear["hp"] <= 0.0:
		cars.pop_back()
		return {"destroyed": true, "type": rear["type"]}
	return {}


func damage_random_car(amount: float) -> void:
	if cars.is_empty():
		damage_locomotive(amount)
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = posmod(run_seed + (damage_roll_index + 1) * 104729, 2147483647)
	damage_roll_index += 1
	var idx: int = rng.randi_range(0, cars.size() - 1)
	cars[idx]["hp"] = maxf(0.0, cars[idx]["hp"] - amount)


func detach_rear_car() -> Dictionary:
	if cars.is_empty():
		return {}
	var rear: Dictionary = cars.pop_back()
	return rear


func trigger_detach_boost() -> void:
	detach_boost_time = 8.0


func add_car(type_key: String) -> bool:
	if cars.size() >= 5:
		return false
	if not cars_config.has(type_key):
		return false
	cars.append(_new_car(type_key, cars.size()))
	return true


func rotate_rear_car_forward() -> bool:
	if cars.size() < 2:
		return false
	var rear: Dictionary = cars.pop_back()
	cars.push_front(rear)
	for index in range(cars.size()):
		cars[index]["order"] = index
	return true


func apply_event_reward(rewards: Dictionary) -> void:
	for key in rewards.keys():
		var v: float = float(rewards[key])
		match key:
			"supplies":
				supplies = clampf(supplies + v, 0.0, 200.0)
			"scrap":
				scrap = clampf(scrap + v, 0.0, 200.0)
			"power":
				power = clampf(power + v, 0.0, 12.0)
			"lumen":
				lumen = clampf(lumen + v, 0.0, 40.0)
			"crew_boost":
				# no new crew in prototype, but grant supplies as morale
				supplies = clampf(supplies + 6.0, 0.0, 200.0)


func journey_ratio() -> float:
	return clampf(distance / JOURNEY_TARGET, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"run_seed": run_seed,
		"distance": distance,
		"travel_time": travel_time,
		"reveal_index": reveal_index,
		"station_completed": station_completed,
		"boss_triggered": boss_triggered,
		"boss_defeated": boss_defeated,
		"power": power,
		"scrap": scrap,
		"supplies": supplies,
		"lumen": lumen,
		"priorities": priorities,
		"current_lens": current_lens,
		"locomotive_hp": locomotive_hp,
		"damage_roll_index": damage_roll_index,
		"detach_boost_time": detach_boost_time,
		"cars": cars.duplicate(true),
		"crew": crew.duplicate(true)
	}


func apply_dict(d: Dictionary) -> void:
	distance = float(d.get("distance", 0.0))
	travel_time = float(d.get("travel_time", 0.0))
	reveal_index = int(d.get("reveal_index", 0))
	station_completed = bool(d.get("station_completed", false))
	boss_triggered = bool(d.get("boss_triggered", false))
	boss_defeated = bool(d.get("boss_defeated", false))
	power = float(d.get("power", 6.0))
	scrap = float(d.get("scrap", 8.0))
	supplies = float(d.get("supplies", 40.0))
	lumen = float(d.get("lumen", 10.0))
	priorities = d.get("priorities", priorities).duplicate(true)
	current_lens = String(d.get("current_lens", "Standard"))
	locomotive_hp = float(d.get("locomotive_hp", locomotive_max_hp))
	damage_roll_index = maxi(0, int(d.get("damage_roll_index", 0)))
	detach_boost_time = maxf(0.0, float(d.get("detach_boost_time", 0.0)))
	if d.has("cars"):
		cars = (d["cars"] as Array).duplicate(true)
	if d.has("crew"):
		crew = (d["crew"] as Array).duplicate(true)
