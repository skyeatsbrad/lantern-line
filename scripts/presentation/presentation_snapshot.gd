class_name PresentationSnapshot
extends RefCounted
## PresentationSnapshot
##
## Reusable presentation state produced by simulation and consumed read-only
## by views. Repeated enemy and car records are pooled and reused in place so
## the normal frame update does not allocate dictionaries or record objects.
## Contains train, car, enemy, longshadow, and world-context sub-records.

const ENEMY_POOL_CAPACITY: int = 48
const CAR_POOL_CAPACITY: int = 8

var elapsed: float = 0.0
var simulation_time: float = 0.0
var enemy_elapsed: float = 0.0
var view_size: Vector2 = Vector2(1280.0, 720.0)
var train_position: Vector2 = Vector2(360.0, 500.0)
var train_scale: float = 1.0
var train_stable_id: String = VisualStateIds.TRAIN_LOCOMOTIVE
var train_hp_ratio: float = 1.0
var train_max_hp: float = 120.0
var distance: float = 0.0
var distance_ratio: float = 0.0
var current_lens: String = "Standard"
var dawn_progress: float = 0.0
var tension: float = 0.0
var mode_name: String = "travel"
var boss_phase_name: String = ""
var reduced_motion: bool = false
var reduced_flashes: bool = false
var high_contrast: bool = false
var simulation_paused: bool = false
var route_context: Dictionary = {
	"category": "neutral",
	"event_id": "",
	"danger": 0
}
var world_context_id: String = VisualStateIds.world_context("neutral")

var car_count: int = 0
var cars: Array[CarViewState] = []

var light_origin: Vector2 = Vector2.ZERO
var light_direction: Vector2 = Vector2.RIGHT
var light_range: float = 500.0
var light_spread: float = 0.72
var light_focused: bool = false
var light_intensity: float = 1.0
var light_damage_multiplier: float = 1.0

var enemy_count: int = 0
var enemies: Array[EnemyViewState] = []

var longshadow_active: bool = false
var longshadow_completed: bool = false
var longshadow_phase: int = 0
var longshadow_phase_id: String = VisualStateIds.longshadow_phase(0)
var longshadow_stable_id: String = VisualStateIds.LONGSHADOW_ROOT
var longshadow_position: Vector2 = Vector2.ZERO
var longshadow_target_position: Vector2 = Vector2.ZERO
var longshadow_health_ratio: float = 1.0
var longshadow_phase_max_health: float = 1.0
var longshadow_transition_timer: float = 0.0
var longshadow_transition_total: float = 0.0
var longshadow_transition_ratio: float = 0.0
var longshadow_response_progress: float = 0.0
var longshadow_response_threshold: float = 1.0
var longshadow_response_ratio: float = 0.0
var longshadow_phase_unlocked: bool = false
var longshadow_charge_timer: float = 11.0
var longshadow_charge_stagger: float = 0.0
var longshadow_charge_warning_issued: bool = false
var longshadow_attack_timer: float = 0.0
var longshadow_target_band: int = 1
var longshadow_phase_elapsed: float = 0.0
var longshadow_elapsed: float = 0.0
var longshadow_status_text: String = ""
var reference_scenario_id: String = ""
var reference_frame_label: String = ""
var reference_frame_time: float = 0.0
var reference_frame_index: int = 0


func _init() -> void:
	cars.resize(CAR_POOL_CAPACITY)
	for i in range(CAR_POOL_CAPACITY):
		cars[i] = CarViewState.new()
	enemies.resize(ENEMY_POOL_CAPACITY)
	for i in range(ENEMY_POOL_CAPACITY):
		enemies[i] = EnemyViewState.new()


func begin_frame() -> void:
	for index in range(car_count):
		cars[index].clear()
	car_count = 0
	for index in range(enemy_count):
		enemies[index].clear()
	enemy_count = 0


func acquire_car_state() -> CarViewState:
	while cars.size() <= car_count:
		cars.append(CarViewState.new())
	var state: CarViewState = cars[car_count]
	state.clear()
	car_count += 1
	return state


func acquire_enemy_state() -> EnemyViewState:
	while enemies.size() <= enemy_count:
		enemies.append(EnemyViewState.new())
	var state: EnemyViewState = enemies[enemy_count]
	state.clear()
	enemy_count += 1
	return state


func set_route_context(context: Dictionary) -> void:
	route_context["category"] = String(context.get("category", "neutral"))
	route_context["event_id"] = String(context.get("event_id", ""))
	route_context["danger"] = int(context.get("danger", 0))
	world_context_id = VisualStateIds.world_context(
		String(context.get("category", "neutral"))
	)


func active_enemy_states() -> Array[EnemyViewState]:
	var result: Array[EnemyViewState] = []
	for index in range(enemy_count):
		result.append(enemies[index])
	return result
