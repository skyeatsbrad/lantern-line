class_name LightProfile
extends RefCounted
## Shared headlight geometry consumed by rendering, enemies, and encounters.

var origin: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var color: Color = Color(1.0, 0.86, 0.62)
var range_px: float = 500.0
var spread_radians: float = 0.7227342478
var intensity: float = 1.0
var damage_multiplier: float = 1.0
var focused: bool = false


static func build(
	run_state: RunState,
	stats: TrainStats,
	aim_direction: Vector2,
	origin_point: Vector2
) -> LightProfile:
	var result: LightProfile = LightProfile.new()
	var lens: Dictionary = run_state.lens_config.get(run_state.current_lens, {})
	var color_values: Array = lens.get("color", [1.0, 0.86, 0.62])
	result.color = Color(
		float(color_values[0]),
		float(color_values[1]),
		float(color_values[2])
	)
	result.origin = origin_point
	result.direction = aim_direction.normalized()
	result.focused = run_state.focus_active_time > 0.0
	var effective_light: float = stats.effective_priority("light")
	var power_factor: float = lerpf(0.35, 1.0, clampf(run_state.power / 6.0, 0.0, 1.0))
	result.intensity = clampf(
		(0.35 + effective_light * 0.22 + run_state.lumen * 0.008)
		* power_factor,
		0.16,
		1.5
	)
	var lens_range: float = float(lens.get("reveal_range", 1.0))
	result.range_px = 500.0 * lens_range * result.intensity
	result.damage_multiplier = float(lens.get("beam_damage_multiplier", 1.0))
	if result.focused:
		result.range_px *= 1.16
		result.spread_radians = 0.17
		result.damage_multiplier *= 4.0
	else:
		result.spread_radians = 0.7227342478
	return result


func contains(point: Vector2) -> bool:
	var to_point: Vector2 = point - origin
	var distance_to_point: float = to_point.length()
	if distance_to_point <= 0.01 or distance_to_point > range_px:
		return false
	var alignment: float = to_point.normalized().dot(direction.normalized())
	return alignment >= cos(spread_radians)


func falloff_at(point: Vector2) -> float:
	if not contains(point):
		return 0.0
	return clampf(1.0 - origin.distance_to(point) / maxf(1.0, range_px), 0.2, 1.0)
