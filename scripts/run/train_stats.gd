class_name TrainStats
extends RefCounted
## Immutable-by-convention derived train values for one simulation frame.

var power_production: float = 0.0
var car_power_draw: float = 0.0
var priority_power_draw: float = 0.0
var power_net: float = 0.0
var total_weight: float = 1.0
var speed: float = 0.0
var repair_rate: float = 0.0
var supply_efficiency: float = 1.0
var supply_generation: float = 0.0
var lumen_generation: float = 0.0
var rear_damage_multiplier: float = 1.0
var focus_cost: float = 5.0
var focus_cooldown: float = 10.0
var detach_boost_duration: float = 8.0
var detach_power_gain: float = 2.0
var detach_purge_radius: float = 240.0
var defense_mounts: Array = []


static func calculate(run_state: RunState) -> TrainStats:
	var result: TrainStats = TrainStats.new()
	result.power_production = run_state.power_production_base

	var has_passenger: bool = false
	var has_workshop: bool = false
	var workshop_repair_multiplier: float = 1.0
	for car_variant in run_state.cars:
		var car: Dictionary = car_variant
		if float(car.get("hp", 0.0)) <= 0.0:
			continue
		var type_key: String = String(car.get("type", ""))
		var cfg: Dictionary = run_state.cars_config.get(type_key, {})
		var effects: Dictionary = run_state.upgrade_effects(car)
		result.power_production += float(cfg.get("power_production", 0.0))
		result.power_production += float(effects.get("power_production", 0.0))
		result.car_power_draw += float(cfg.get("power_draw", 0.0))
		result.car_power_draw += float(effects.get("power_draw", 0.0))
		result.total_weight += (float(cfg.get("weight", 1.0)) + float(effects.get("weight", 0.0))) * 0.1

		if type_key == "Passenger":
			has_passenger = true
			result.supply_efficiency *= float(effects.get("supply_efficiency_mult", 1.0))
		elif type_key == "Workshop":
			has_workshop = true
			workshop_repair_multiplier *= float(effects.get("repair_mult", 1.0))
		elif type_key == "Greenhouse" and run_state.is_car_powered(car):
			result.supply_generation += 0.11 + float(effects.get("supply_generation", 0.0))
			result.lumen_generation += float(effects.get("lumen_generation", 0.0))
		elif type_key == "Defense" and run_state.is_car_powered(car):
			var mode: String = String(effects.get("defense_mode", "standard"))
			var mount_damage: float = float(effects.get("defense_damage", 4.5))
			var targets: int = int(effects.get("defense_targets", 1))
			result.defense_mounts.append({
				"car_id": String(car.get("id", "")),
				"mode": mode,
				"damage": mount_damage,
				"targets": maxi(1, targets)
			})

		result.focus_cost += float(effects.get("focus_cost", 0.0))
		result.focus_cooldown *= float(effects.get("focus_cooldown_mult", 1.0))

	if has_passenger:
		result.supply_efficiency *= 0.85
	if has_workshop and run_state.has_powered_car_type("Workshop"):
		result.repair_rate = maxf(result.repair_rate, 1.0) * 1.6 * workshop_repair_multiplier
	else:
		result.repair_rate = maxf(result.repair_rate, 1.0)

	var speed_multiplier: float = 1.0
	var defense_multiplier: float = 1.0
	for member_variant in run_state.crew:
		var member: Dictionary = member_variant
		if not run_state.is_crew_active(member):
			continue
		var bonus: Dictionary = member.get("bonus", {})
		match String(member.get("id", "")):
			"mara":
				if int(run_state.priorities.get("engine", 0)) >= 2 and run_state.power > 3.0:
					speed_multiplier *= 1.0 + float(bonus.get("engine_efficiency", 0.0))
			"ilo":
				defense_multiplier *= 1.0 + float(bonus.get("turret_damage", 0.0))
			"sable":
				var supply_bonus: float = float(bonus.get(
					"supply_efficiency",
					float(bonus.get("supply_bonus", 0.0)) * 0.375
				))
				result.supply_efficiency *= 1.0 - clampf(supply_bonus, 0.0, 0.5)
			"orrin":
				result.repair_rate *= 1.0 + float(bonus.get("repair_bonus", 0.0))

	for mount_variant in result.defense_mounts:
		var mount: Dictionary = mount_variant
		mount["damage"] = float(mount.get("damage", 0.0)) * defense_multiplier

	result.repair_rate *= float(run_state.priorities.get("repair", 0))
	result.priority_power_draw = (
		float(run_state.priorities.get("engine", 0)) * 0.85
		+ float(run_state.priorities.get("light", 0)) * 0.75
		+ float(run_state.priorities.get("defense", 0)) * 0.9
		+ float(run_state.priorities.get("repair", 0)) * 0.7
	)
	result.power_net = result.power_production - result.car_power_draw - result.priority_power_draw

	if not run_state.cars.is_empty():
		var rear: Dictionary = run_state.cars.back()
		var rear_effects: Dictionary = run_state.upgrade_effects(rear)
		result.rear_damage_multiplier = float(rear_effects.get("rear_damage_mult", 1.0))
		result.detach_boost_duration = float(rear_effects.get("detach_boost_duration", 8.0))
		result.detach_power_gain = float(rear_effects.get("detach_power_gain", 2.0))
		result.detach_purge_radius = float(rear_effects.get("detach_purge_radius", 240.0))

	result.focus_cost = clampf(result.focus_cost, 2.0, 8.0)
	result.focus_cooldown = clampf(result.focus_cooldown, 5.0, 14.0)
	var base_speed: float = 26.0 + 5.0 * float(run_state.priorities.get("engine", 0))
	var power_factor: float = lerpf(0.55, 1.0, clampf(run_state.power / 6.0, 0.0, 1.0))
	var detach_factor: float = 1.35 if run_state.detach_boost_time > 0.0 else 1.0
	result.speed = (
		base_speed
		* speed_multiplier
		* power_factor
		* detach_factor
		* run_state.external_speed_multiplier
		/ maxf(0.1, result.total_weight)
	)
	return result
