class_name SimEvent
extends RefCounted
## SimEvent
##
## Pooled deterministic simulation event carried across the M2 view boundary.
## Emitted only by simulation owners (RunState, EnemyDirector,
## LongshadowEncounter, GameWorld). Consumed by views, HUD, audio, effects.
## Consumers must treat the record as read-only and must not retain it after
## the synchronous callback returns. `PresentationEventBus` immediately
## recycles the instance after dispatch.

const TYPE_TRAIN_HIT: StringName = &"train.hit"
const TYPE_CAR_HIT: StringName = &"car.hit"
const TYPE_CAR_CRITICAL: StringName = &"car.critical"
const TYPE_CAR_DESTROYED: StringName = &"car.destroyed"
const TYPE_DEFENSE_FIRED: StringName = &"defense.fired"
const TYPE_ENEMY_SPAWNED: StringName = &"enemy.spawned"
const TYPE_ENEMY_TELEGRAPHED: StringName = &"enemy.telegraphed"
const TYPE_ENEMY_ATTACKED: StringName = &"enemy.attacked"
const TYPE_ENEMY_HIT: StringName = &"enemy.hit"
const TYPE_ENEMY_KILLED: StringName = &"enemy.killed"
const TYPE_WARD_FORMED: StringName = &"ward.formed"
const TYPE_WARD_CRACKED: StringName = &"ward.cracked"
const TYPE_WARD_SHATTERED: StringName = &"ward.shattered"
const TYPE_ROUTE_REVEAL: StringName = &"route.reveal"
const TYPE_ROUTE_COMMIT: StringName = &"route.commit"
const TYPE_STATION_ARRIVAL: StringName = &"station.arrival"
const TYPE_STATION_DEPARTURE: StringName = &"station.departure"
const TYPE_DETACH_RELEASED: StringName = &"detach.released"
const TYPE_BOSS_PHASE_ENTRY: StringName = &"boss.phase_entry"
const TYPE_BOSS_RESPONSE: StringName = &"boss.response"
const TYPE_BOSS_ATTACK: StringName = &"boss.attack"
const TYPE_BOSS_DEFEAT: StringName = &"boss.defeat"
const TYPE_DAWN_ARRIVAL: StringName = &"dawn.arrival"

const ALL_TYPES: Array[StringName] = [
	TYPE_TRAIN_HIT,
	TYPE_CAR_HIT,
	TYPE_CAR_CRITICAL,
	TYPE_CAR_DESTROYED,
	TYPE_DEFENSE_FIRED,
	TYPE_ENEMY_SPAWNED,
	TYPE_ENEMY_TELEGRAPHED,
	TYPE_ENEMY_ATTACKED,
	TYPE_ENEMY_HIT,
	TYPE_ENEMY_KILLED,
	TYPE_WARD_FORMED,
	TYPE_WARD_CRACKED,
	TYPE_WARD_SHATTERED,
	TYPE_ROUTE_REVEAL,
	TYPE_ROUTE_COMMIT,
	TYPE_STATION_ARRIVAL,
	TYPE_STATION_DEPARTURE,
	TYPE_DETACH_RELEASED,
	TYPE_BOSS_PHASE_ENTRY,
	TYPE_BOSS_RESPONSE,
	TYPE_BOSS_ATTACK,
	TYPE_BOSS_DEFEAT,
	TYPE_DAWN_ARRIVAL
]

var type: StringName = TYPE_ENEMY_SPAWNED
var producer_id: String = ""
var source_id: String = ""
var target_id: String = ""
var timestamp: float = 0.0
var sequence: int = 0
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var strength: float = 0.0
var material: StringName = &"none"
var payload: Dictionary = {}


func reset() -> void:
	type = TYPE_ENEMY_SPAWNED
	producer_id = ""
	source_id = ""
	target_id = ""
	timestamp = 0.0
	sequence = 0
	position = Vector2.ZERO
	direction = Vector2.RIGHT
	strength = 0.0
	material = &"none"
	payload.clear()


func snapshot() -> Dictionary:
	return {
		"type": String(type),
		"producer_id": producer_id,
		"source_id": source_id,
		"target_id": target_id,
		"timestamp": timestamp,
		"sequence": sequence,
		"position": [position.x, position.y],
		"direction": [direction.x, direction.y],
		"strength": strength,
		"material": String(material),
		"payload": payload.duplicate(true)
	}
