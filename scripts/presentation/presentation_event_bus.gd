class_name PresentationEventBus
extends Node
## PresentationEventBus
##
## Central presentation-boundary event router. Simulation owners emit
## `SimEvent` records after their tick; presentation consumers subscribe by
## event type. Presentation-only systems may also emit and consume
## `PresentationEvent`s. Every emission names a registered producer, uses an
## explicit timestamp, dispatches synchronously, and returns the record to its
## pool before returning. This makes role enforcement real rather than a
## metadata-only startup lint.

const ROLE_SIMULATION: StringName = &"simulation"
const ROLE_PRESENTATION: StringName = &"presentation"

signal sim_event(event: SimEvent)
signal presentation_event(event: PresentationEvent)
signal audit_completed(issues: Array[String])

const SIM_POOL_LIMIT: int = 64
const PRESENTATION_POOL_LIMIT: int = 32

var _sim_pool: Array[SimEvent] = []
var _presentation_pool: Array[PresentationEvent] = []
var _sequence: int = 0
var _producers: Dictionary = {}
var _consumers: Dictionary = {}
var _audit_issues: Array[String] = []
var _runtime_issues: Array[String] = []
var _audit_completed: bool = false
var _last_sim_snapshot: Dictionary = {}
var _last_presentation_snapshot: Dictionary = {}

var recent_sim_events: Array[Dictionary] = []
var recent_presentation_events: Array[Dictionary] = []
var recent_capacity: int = 64


func _ready() -> void:
	if _sim_pool.is_empty():
		for i in range(SIM_POOL_LIMIT):
			_sim_pool.append(SimEvent.new())
	if _presentation_pool.is_empty():
		for i in range(PRESENTATION_POOL_LIMIT):
			_presentation_pool.append(PresentationEvent.new())


func register_simulation_producer(
	producer_id: String,
	event_types: Array[StringName]
) -> void:
	if producer_id.is_empty():
		return
	_producers[producer_id] = {
		"role": ROLE_SIMULATION,
		"types": event_types.duplicate()
	}


func register_presentation_producer(
	producer_id: String,
	event_types: Array[StringName]
) -> void:
	if producer_id.is_empty():
		return
	_producers[producer_id] = {
		"role": ROLE_PRESENTATION,
		"types": event_types.duplicate()
	}


func register_simulation_consumer(
	consumer_id: String,
	event_types: Array[StringName],
	callback: Callable
) -> void:
	_register_consumer(
		consumer_id,
		ROLE_SIMULATION,
		event_types,
		callback
	)


func register_presentation_consumer(
	consumer_id: String,
	event_types: Array[StringName],
	callback: Callable
) -> void:
	_register_consumer(
		consumer_id,
		ROLE_PRESENTATION,
		event_types,
		callback
	)


func _register_consumer(
	consumer_id: String,
	role: StringName,
	event_types: Array[StringName],
	callback: Callable
) -> void:
	if consumer_id.is_empty():
		return
	_consumers[consumer_id] = {
		"role": role,
		"types": event_types.duplicate(),
		"callback": callback
	}


func emit_sim(
	producer_id: String,
	type: StringName,
	source_id: String,
	target_id: String,
	timestamp: float,
	position: Vector2,
	direction: Vector2,
	strength: float,
	material: StringName,
	payload: Dictionary = {}
) -> int:
	if not _producer_can_emit(
		producer_id,
		ROLE_SIMULATION,
		type,
		SimEvent.ALL_TYPES
	):
		return 0
	var event: SimEvent = _acquire_sim()
	event.type = type
	event.producer_id = producer_id
	event.source_id = source_id
	event.target_id = target_id
	event.timestamp = maxf(0.0, timestamp)
	_sequence += 1
	event.sequence = _sequence
	event.position = position
	event.direction = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	event.strength = strength
	event.material = material
	event.payload = payload.duplicate(true)
	var snapshot: Dictionary = event.snapshot()
	_record_recent(recent_sim_events, snapshot)
	_last_sim_snapshot = snapshot
	_dispatch(type, event)
	emit_signal("sim_event", event)
	var sequence: int = event.sequence
	_release_sim(event)
	return sequence


func emit_presentation(
	producer_id: String,
	type: StringName,
	source_id: String,
	timestamp: float,
	position: Vector2,
	direction: Vector2,
	strength: float,
	material: StringName,
	payload: Dictionary = {}
) -> int:
	if not _producer_can_emit(
		producer_id,
		ROLE_PRESENTATION,
		type,
		PresentationEvent.ALL_TYPES
	):
		return 0
	var event: PresentationEvent = _acquire_presentation()
	event.type = type
	event.producer_id = producer_id
	event.source_id = source_id
	event.timestamp = maxf(0.0, timestamp)
	_sequence += 1
	event.sequence = _sequence
	event.position = position
	event.direction = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	event.strength = strength
	event.material = material
	event.payload = payload.duplicate(true)
	var snapshot: Dictionary = event.snapshot()
	_record_recent(recent_presentation_events, snapshot)
	_last_presentation_snapshot = snapshot
	_dispatch(type, event)
	emit_signal("presentation_event", event)
	var sequence: int = event.sequence
	_release_presentation(event)
	return sequence


func run_startup_audit() -> Array[String]:
	_audit_issues = _runtime_issues.duplicate()
	for producer_id_variant in _producers.keys():
		var producer_id: String = String(producer_id_variant)
		var entry: Dictionary = _producers[producer_id]
		var role: StringName = entry.get("role", ROLE_SIMULATION)
		var types_variant: Array = entry.get("types", [])
		for event_type_variant in types_variant:
			var event_type: StringName = event_type_variant
			if role == ROLE_SIMULATION:
				if not SimEvent.ALL_TYPES.has(event_type):
					_audit_issues.append(
						"simulation producer %s advertises non-sim event %s" % [
							producer_id, String(event_type)
						]
					)
			elif role == ROLE_PRESENTATION:
				if not PresentationEvent.ALL_TYPES.has(event_type):
					_audit_issues.append(
						"presentation producer %s advertises non-presentation event %s" % [
							producer_id, String(event_type)
						]
					)
	for consumer_id_variant in _consumers.keys():
		var consumer_id: String = String(consumer_id_variant)
		var entry: Dictionary = _consumers[consumer_id]
		var role: StringName = entry.get("role", ROLE_PRESENTATION)
		var types_variant: Array = entry.get("types", [])
		var callback: Callable = entry.get("callback", Callable())
		if not callback.is_valid():
			_audit_issues.append(
				"consumer %s has no valid event callback" % consumer_id
			)
		for event_type_variant in types_variant:
			var event_type: StringName = event_type_variant
			if role == ROLE_SIMULATION:
				if not SimEvent.ALL_TYPES.has(event_type):
					_audit_issues.append(
						"simulation consumer %s subscribes to non-sim event %s" % [
							consumer_id, String(event_type)
						]
					)
				if PresentationEvent.ALL_TYPES.has(event_type):
					_audit_issues.append(
						"simulation consumer %s attempts to subscribe to presentation event %s" % [
							consumer_id, String(event_type)
						]
					)
			elif role == ROLE_PRESENTATION:
				if not (
					SimEvent.ALL_TYPES.has(event_type)
					or PresentationEvent.ALL_TYPES.has(event_type)
				):
					_audit_issues.append(
						"presentation consumer %s subscribes to unknown event %s" % [
							consumer_id, String(event_type)
						]
					)
	_audit_completed = true
	emit_signal("audit_completed", _audit_issues.duplicate())
	return _audit_issues.duplicate()


func audit_completed_ok() -> bool:
	return _audit_completed and _audit_issues.is_empty()


func audit_issues() -> Array[String]:
	return _audit_issues.duplicate()


func producer_role(producer_id: String) -> StringName:
	return _producers.get(producer_id, {}).get("role", &"")


func consumer_role(consumer_id: String) -> StringName:
	return _consumers.get(consumer_id, {}).get("role", &"")


func has_producer(producer_id: String) -> bool:
	return _producers.has(producer_id)


func has_consumer(consumer_id: String) -> bool:
	return _consumers.has(consumer_id)


func last_sim_snapshot() -> Dictionary:
	return _last_sim_snapshot.duplicate(true)


func last_presentation_snapshot() -> Dictionary:
	return _last_presentation_snapshot.duplicate(true)


func recent_sim_snapshots() -> Array[Dictionary]:
	return recent_sim_events.duplicate()


func recent_presentation_snapshots() -> Array[Dictionary]:
	return recent_presentation_events.duplicate()


func clear_recent() -> void:
	recent_sim_events.clear()
	recent_presentation_events.clear()


func _acquire_sim() -> SimEvent:
	if _sim_pool.is_empty():
		return SimEvent.new()
	var event: SimEvent = _sim_pool.pop_back()
	event.reset()
	return event


func _acquire_presentation() -> PresentationEvent:
	if _presentation_pool.is_empty():
		return PresentationEvent.new()
	var event: PresentationEvent = _presentation_pool.pop_back()
	event.reset()
	return event


func pool_stats() -> Dictionary:
	return {
		"sim_available": _sim_pool.size(),
		"sim_limit": SIM_POOL_LIMIT,
		"presentation_available": _presentation_pool.size(),
		"presentation_limit": PRESENTATION_POOL_LIMIT
	}


func _release_sim(event: SimEvent) -> void:
	if event == null:
		return
	if _sim_pool.size() >= SIM_POOL_LIMIT:
		return
	event.reset()
	_sim_pool.append(event)


func _release_presentation(event: PresentationEvent) -> void:
	if event == null:
		return
	if _presentation_pool.size() >= PRESENTATION_POOL_LIMIT:
		return
	event.reset()
	_presentation_pool.append(event)


func _record_recent(target: Array[Dictionary], snapshot: Dictionary) -> void:
	target.append(snapshot)
	if target.size() > recent_capacity:
		target.remove_at(0)


func _producer_can_emit(
	producer_id: String,
	expected_role: StringName,
	event_type: StringName,
	known_types: Array[StringName]
) -> bool:
	if not known_types.has(event_type):
		_record_runtime_issue(
			"%s event unknown type=%s" % [
				String(expected_role), String(event_type)
			]
		)
		return false
	if not _producers.has(producer_id):
		_record_runtime_issue(
			"unregistered producer %s attempted %s event %s" % [
				producer_id, String(expected_role), String(event_type)
			]
		)
		return false
	var entry: Dictionary = _producers[producer_id]
	var role: StringName = entry.get("role", &"")
	if role != expected_role:
		_record_runtime_issue(
			"producer %s role=%s attempted %s event %s" % [
				producer_id,
				String(role),
				String(expected_role),
				String(event_type)
			]
		)
		return false
	var advertised: Array = entry.get("types", [])
	if not advertised.has(event_type):
		_record_runtime_issue(
			"producer %s emitted undeclared event %s" % [
				producer_id, String(event_type)
			]
		)
		return false
	return true


func _dispatch(event_type: StringName, event: Variant) -> void:
	for consumer_id_variant in _consumers.keys():
		var consumer_id: String = String(consumer_id_variant)
		var entry: Dictionary = _consumers[consumer_id]
		var accepted_types: Array = entry.get("types", [])
		if not accepted_types.has(event_type):
			continue
		var callback: Callable = entry.get("callback", Callable())
		if not callback.is_valid():
			_record_runtime_issue(
				"consumer %s callback became invalid" % consumer_id
			)
			continue
		callback.call(event)


func _record_runtime_issue(issue: String) -> void:
	if not _runtime_issues.has(issue):
		_runtime_issues.append(issue)
	if not _audit_issues.has(issue):
		_audit_issues.append(issue)
