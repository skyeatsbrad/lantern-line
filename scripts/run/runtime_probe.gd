extends Node
## runtime_probe.gd
##
## Boots into a real game_world for ~8 seconds, then quits.
## Exercises the actual scene tree, tick loop, spawn, aim, HUD wiring.

var _elapsed: float = 0.0
var _duration: float = 8.0
var _saw_enemies: bool = false
var _detached: bool = false
var _detach_hold_started: bool = false
var _focused: bool = false
var _distance_start: float = 0.0
var _game_world: Node
var _bootstrapped: bool = false
var _saved_meta: Dictionary
var _saved_pending: Dictionary
var _saved_has_pending: bool


func _ready() -> void:
	_saved_meta = GameManager.meta.duplicate(true)
	_saved_pending = GameManager.pending_run.duplicate(true)
	_saved_has_pending = GameManager.has_pending_run
	set_process(true)
	var scene: PackedScene = load("res://scenes/game_world.tscn")
	_game_world = scene.instantiate()
	get_tree().root.add_child.call_deferred(_game_world)
	# defer bootstrap until it's in tree
	get_tree().process_frame.connect(_maybe_bootstrap)


func _maybe_bootstrap() -> void:
	if _bootstrapped:
		return
	if _game_world.is_inside_tree():
		_game_world.call("bootstrap", 42, {})
		_bootstrapped = true
		if "run_state" in _game_world:
			var rs: Object = _game_world.get("run_state")
			if rs:
				_distance_start = float(rs.distance)


func _process(delta: float) -> void:
	if not _bootstrapped:
		return
	_elapsed += delta
	if _game_world and "run_state" in _game_world:
		var rs: Object = _game_world.get("run_state")
		if rs:
			var ed: Object = _game_world.get("_enemy_director") if "_enemy_director" in _game_world else null
			# poke aim + priority etc
			if _elapsed > 2.0 and int(rs.priorities.get("light", 0)) < 2:
				rs.cycle_priority("light")
			if _elapsed > 3.0 and rs.lens_cooldown == 0.0 and rs.current_lens == "Standard":
				rs.request_lens("Pale")
			if _elapsed > 4.0 and ed != null and not _saw_enemies:
				ed._spawn_wave()
				_saw_enemies = ed.active_count() > 0
			if _elapsed > 4.2 and not _focused:
				_focused = bool(rs.request_focus())
			if _elapsed > 5.0 and not _detach_hold_started:
				_detach_hold_started = true
				_game_world.call("_on_detach_hold_changed", true)
			if _detach_hold_started and int(rs.cars.size()) == 2:
				_detached = true
	if _elapsed >= _duration:
		var rs2: Object = _game_world.get("run_state") if _game_world else null
		if rs2 == null:
			_finish(4, "[probe] no run_state after run", true)
			return
		var dist: float = float(rs2.distance)
		if dist <= _distance_start:
			_finish(5, "[probe] distance did not advance: %s" % dist, true)
			return
		if not _saw_enemies:
			_finish(6, "[probe] enemy spawn not observed", true)
			return
		if not _detached:
			_finish(8, "[probe] detach not observed", true)
			return
		if not _focused:
			_finish(9, "[probe] focus activation not observed", true)
			return
		_finish(0, "[probe] OK distance=%s" % dist)


func _finish(exit_code: int, message: String, is_error: bool = false) -> void:
	GameManager.meta = _saved_meta
	GameManager.pending_run = _saved_pending
	GameManager.has_pending_run = _saved_has_pending
	GameManager.call("_save")
	if is_error:
		printerr(message)
	else:
		print(message)
	get_tree().quit(exit_code)
