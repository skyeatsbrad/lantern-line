class_name TrainStats
extends RefCounted
## Immutable-by-convention derived train values for one simulation frame.

var power_production: float = 0.0
var car_power_draw: float = 0.0
var priority_power_draw: float = 0.0
var power_net: float = 0.0
var requested_power_draw: float = 0.0
var requested_power_net: float = 0.0
var shed_power_draw: float = 0.0
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
var effective_priorities: Dictionary = {}
var system_states: Dictionary = {}
var car_states: Dictionary = {}


func effective_priority(role: String) -> float:
	return float(effective_priorities.get(role, 0.0))


func system_state(role: String) -> String:
	return String(system_states.get(role, "standby"))


func car_state(car_id: String) -> String:
	return String(car_states.get(car_id, "passive"))


static func calculate(run_state: RunState) -> TrainStats:
	var result: TrainStats = TrainStats.new()
	result.power_production = run_state.power_production_base

	var has_passenger: bool = false
	var has_workshop: bool = false
	var workshop_repair_multiplier: float = 1.0
	var passive_car_draw: float = 0.0
	var role_car_draws: Dictionary = {
		"defense": 0.0,
		"repair": 0.0,
		"support": 0.0
	}
	for car_variant in run_state.cars:
		var car: Dictionary = car_variant
		var car_id: String = String(car.get("id", ""))
		if float(car.get("hp", 0.0)) <= 0.0:
			result.car_states[car_id] = "destroyed"
			continue
		var type_key: String = String(car.get("type", ""))
		var cfg: Dictionary = run_state.cars_config.get(type_key, {})
		var effects: Dictionary = run_state.upgrade_effects(car)
		var car_draw: float = (
			float(cfg.get("power_draw", 0.0))
			+ float(effects.get("power_draw", 0.0))
		)
		result.power_production += float(cfg.get("power_production", 0.0))
		result.power_production += float(effects.get("power_production", 0.0))
		result.total_weight += (float(cfg.get("weight", 1.0)) + float(effects.get("weight", 0.0))) * 0.1

		match type_key:
			"Passenger":
				has_passenger = true
				passive_car_draw += car_draw
				result.supply_efficiency *= float(effects.get("supply_efficiency_mult", 1.0))
			"Workshop":
				has_workshop = true
				role_car_draws["repair"] = float(role_car_draws["repair"]) + car_draw
				workshop_repair_multiplier *= float(effects.get("repair_mult", 1.0))
			"Greenhouse":
				role_car_draws["support"] = float(role_car_draws["support"]) + car_draw
			"Defense":
				role_car_draws["defense"] = float(role_car_draws["defense"]) + car_draw
			_:
				passive_car_draw += car_draw

		result.focus_cost += float(effects.get("focus_cost", 0.0))
		result.focus_cooldown *= float(effects.get("focus_cooldown_mult", 1.0))

	var raw_priorities: Dictionary = {
		"engine": float(run_state.priorities.get("engine", 0)),
		"light": float(run_state.priorities.get("light", 0)),
		"defense": float(run_state.priorities.get("defense", 0)),
		"repair": float(run_state.priorities.get("repair", 0))
	}
	var role_requests: Dictionary = {
		"engine": float(raw_priorities["engine"]) * 0.85,
		"light": float(raw_priorities["light"]) * 0.75,
		"defense": (
			float(raw_priorities["defense"]) * 0.9
			+ float(role_car_draws["defense"])
			if float(raw_priorities["defense"]) > 0.0
			else 0.0
		),
		"repair": (
			float(raw_priorities["repair"]) * 0.7
			+ float(role_car_draws["repair"])
			if float(raw_priorities["repair"]) > 0.0
			else 0.0
		),
		"support": float(role_car_draws["support"])
	}
	result.requested_power_draw = passive_car_draw
	for requested_variant in role_requests.values():
		result.requested_power_draw += float(requested_variant)
	result.requested_power_net = result.power_production - result.requested_power_draw

	var role_fractions: Dictionary = {}
	for role_variant in role_requests.keys():
		var role: String = String(role_variant)
		role_fractions[role] = 1.0 if float(role_requests[role]) > 0.0 else 0.0
	if run_state.brownout_active:
		# Leave recharge headroom so a brownout can recover instead of oscillating at zero.
		var available: float = maxf(0.0, result.power_production - passive_car_draw - 0.8)
		var order: Array[String] = ["engine", "light", "defense", "repair", "support"]
		var tie_break: Dictionary = {
			"light": 5,
			"engine": 4,
			"repair": 3,
			"defense": 2,
			"support": 1
		}
		order.sort_custom(func(a: String, b: String) -> bool:
			var a_priority: float = (
				float(raw_priorities.get(a, 0.0))
				if a != "support"
				else 0.25
			)
			var b_priority: float = (
				float(raw_priorities.get(b, 0.0))
				if b != "support"
				else 0.25
			)
			if not is_equal_approx(a_priority, b_priority):
				return a_priority > b_priority
			return int(tie_break[a]) > int(tie_break[b])
		)
		for role in order:
			var requested: float = float(role_requests[role])
			if requested <= 0.0:
				role_fractions[role] = 0.0
				continue
			var fraction: float = clampf(available / requested, 0.0, 1.0)
			role_fractions[role] = fraction
			available = maxf(0.0, available - requested * fraction)

	for role_variant in role_requests.keys():
		var role: String = String(role_variant)
		var requested: float = float(role_requests[role])
		var fraction: float = float(role_fractions[role])
		if requested <= 0.0:
			result.system_states[role] = "standby"
		elif fraction >= 0.99:
			result.system_states[role] = "active"
		elif fraction > 0.01:
			result.system_states[role] = "throttled"
		else:
			result.system_states[role] = "offline"
		if role != "support":
			result.effective_priorities[role] = float(raw_priorities[role]) * fraction

	result.car_power_draw = passive_car_draw
	result.car_power_draw += float(role_car_draws["defense"]) * float(role_fractions["defense"])
	result.car_power_draw += float(role_car_draws["repair"]) * float(role_fractions["repair"])
	result.car_power_draw += float(role_car_draws["support"]) * float(role_fractions["support"])
	result.priority_power_draw = (
		float(raw_priorities["engine"]) * 0.85 * float(role_fractions["engine"])
		+ float(raw_priorities["light"]) * 0.75 * float(role_fractions["light"])
		+ float(raw_priorities["defense"]) * 0.9 * float(role_fractions["defense"])
		+ float(raw_priorities["repair"]) * 0.7 * float(role_fractions["repair"])
	)
	result.power_net = result.power_production - result.car_power_draw - result.priority_power_draw
	result.shed_power_draw = maxf(0.0, result.requested_power_draw - result.car_power_draw - result.priority_power_draw)

	var support_fraction: float = float(role_fractions["support"])
	var defense_fraction: float = float(role_fractions["defense"])
	for car_variant in run_state.cars:
		var car: Dictionary = car_variant
		var car_id: String = String(car.get("id", ""))
		if float(car.get("hp", 0.0)) <= 0.0:
			continue
		var type_key: String = String(car.get("type", ""))
		var cfg: Dictionary = run_state.cars_config.get(type_key, {})
		var effects: Dictionary = run_state.upgrade_effects(car)
		match type_key:
			"Battery":
				result.car_states[car_id] = "producing"
			"Workshop":
				result.car_states[car_id] = result.system_state("repair")
			"Greenhouse":
				result.car_states[car_id] = result.system_state("support")
				if support_fraction > 0.0:
					var story_multiplier: float = (
						1.25 if bool(run_state.event_flags.get("ash_garden_found", false)) else 1.0
					)
					result.supply_generation += (
						0.11 + float(effects.get("supply_generation", 0.0))
					) * support_fraction * story_multiplier
					result.lumen_generation += (
						float(effects.get("lumen_generation", 0.0))
						* support_fraction
						* story_multiplier
					)
			"Defense":
				result.car_states[car_id] = result.system_state("defense")
				if defense_fraction > 0.0:
					var mode: String = String(
						effects.get("defense_mode", cfg.get("defense_mode", "standard"))
					)
					var mount_damage: float = float(
						effects.get("defense_damage", cfg.get("defense_damage", 5.2))
					)
					var targets: int = int(
						effects.get("defense_targets", cfg.get("defense_targets", 1))
					)
					result.defense_mounts.append({
						"car_id": car_id,
						"mode": mode,
						"damage": mount_damage * defense_fraction,
						"targets": maxi(1, targets),
						"power_factor": defense_fraction
					})
			_:
				result.car_states[car_id] = "passive"

	if has_passenger:
		result.supply_efficiency *= 0.85
	var effective_repair: float = result.effective_priority("repair")
	if has_workshop and float(role_fractions["repair"]) > 0.0:
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
				if result.effective_priority("engine") >= 2.0 and run_state.power > 3.0:
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

	result.repair_rate *= effective_repair
	if bool(run_state.event_flags.get("buried_bell_answered", false)) and effective_repair > 0.0:
		result.repair_rate += 0.25 * effective_repair
	if run_state.current_lens == "Hearth":
		result.repair_rate *= 1.1
		result.supply_generation *= 1.1
	if bool(run_state.event_flags.get("signal_vault_opened", false)):
		result.focus_cooldown *= 0.9

	if not run_state.cars.is_empty():
		var rear: Dictionary = run_state.cars.back()
		var rear_effects: Dictionary = run_state.upgrade_effects(rear)
		result.rear_damage_multiplier = float(rear_effects.get("rear_damage_mult", 1.0))
		result.detach_boost_duration = float(rear_effects.get("detach_boost_duration", 8.0))
		result.detach_power_gain = float(rear_effects.get("detach_power_gain", 2.0))
		result.detach_purge_radius = float(rear_effects.get("detach_purge_radius", 240.0))

	result.focus_cost = clampf(result.focus_cost, 2.0, 8.0)
	result.focus_cooldown = clampf(result.focus_cooldown, 5.0, 14.0)
	var base_speed: float = 26.0 + 5.0 * result.effective_priority("engine")
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
