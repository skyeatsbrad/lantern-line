class_name PresentationMetrics
extends Node

const SAMPLE_INTERVAL: float = 0.5

var _elapsed: float = 0.0
var _sample_count: int = 0
var _frame_count: int = 0
var _frame_time_total_ms: float = 0.0
var _worst_frame_ms: float = 0.0
var _latest: Dictionary = {}


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_frame_count += 1
	_frame_time_total_ms += frame_ms
	_worst_frame_ms = maxf(_worst_frame_ms, frame_ms)
	_elapsed += delta
	if _elapsed < SAMPLE_INTERVAL:
		return
	_elapsed = 0.0
	sample_now()


func sample_now() -> void:
	_sample_count += 1
	_latest = {
		"fps": float(Performance.get_monitor(Performance.TIME_FPS)),
		"process_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"physics_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		"draw_calls": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		)),
		"render_objects": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		)),
		"primitives": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"audio_voices": AudioManager.active_voice_count(),
		"average_frame_ms": (
			_frame_time_total_ms / maxf(1.0, float(_frame_count))
		),
		"worst_frame_ms": _worst_frame_ms,
		"samples": _sample_count
	}


func snapshot() -> Dictionary:
	return _latest.duplicate(true)


func summary_text() -> String:
	if _latest.is_empty():
		return "metrics unavailable"
	return (
		"fps=%.1f process=%.2fms physics=%.2fms frame_avg=%.2fms "
		+ "frame_worst=%.2fms draws=%d objects=%d primitives=%d nodes=%d "
		+ "resources=%d voices=%d samples=%d"
	) % [
		float(_latest["fps"]),
		float(_latest["process_ms"]),
		float(_latest["physics_ms"]),
		float(_latest["average_frame_ms"]),
		float(_latest["worst_frame_ms"]),
		int(_latest["draw_calls"]),
		int(_latest["render_objects"]),
		int(_latest["primitives"]),
		int(_latest["nodes"]),
		int(_latest["resources"]),
		int(_latest["audio_voices"]),
		int(_latest["samples"])
	]
