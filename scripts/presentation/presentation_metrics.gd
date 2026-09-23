class_name PresentationMetrics
extends Node

const SAMPLE_INTERVAL: float = 0.5
const DEFAULT_WARMUP_SECONDS: float = 2.0
const BYTES_PER_MIB: float = 1048576.0
const MAX_FRAME_SAMPLES: int = 65536
const MAX_DRAW_SAMPLES: int = 4096

var _age: float = 0.0
var _sample_elapsed: float = 0.0
var _warmup_seconds: float = DEFAULT_WARMUP_SECONDS
var _sample_count: int = 0
var _measurement_active: bool = false
var _sample_limit_reached: bool = false
var _frame_times_ms: Array[float] = []
var _draw_call_samples: Array[float] = []
var _latest: Dictionary = {}


func _ready() -> void:
	set_process(false)


func reset_measurement(warmup_seconds: float = DEFAULT_WARMUP_SECONDS) -> void:
	_age = 0.0
	_sample_elapsed = 0.0
	_warmup_seconds = maxf(0.0, warmup_seconds)
	_sample_count = 0
	_measurement_active = true
	_sample_limit_reached = false
	_frame_times_ms.clear()
	_draw_call_samples.clear()
	_latest.clear()
	set_process(true)


func stop_measurement() -> void:
	_measurement_active = false
	set_process(false)


func _process(delta: float) -> void:
	if not _measurement_active:
		return
	_age += delta
	if _age < _warmup_seconds:
		return
	if _frame_times_ms.size() < MAX_FRAME_SAMPLES:
		_frame_times_ms.append(delta * 1000.0)
	else:
		_sample_limit_reached = true
	_sample_elapsed += delta
	if _sample_elapsed < SAMPLE_INTERVAL:
		return
	_sample_elapsed = fmod(_sample_elapsed, SAMPLE_INTERVAL)
	_record_draw_sample()


func sample_now() -> void:
	if _age < _warmup_seconds or _frame_times_ms.is_empty():
		_latest = {
			"warming_up": true,
			"warmup_remaining_seconds": maxf(0.0, _warmup_seconds - _age),
			"profile": GameManager.resolved_presentation_profile()
		}
		return
	_record_draw_sample()
	var draw_calls := float(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	))
	var sorted_frames: Array[float] = _frame_times_ms.duplicate()
	sorted_frames.sort()
	var sorted_draws: Array[float] = _draw_call_samples.duplicate()
	sorted_draws.sort()
	var frame_average := _average(_frame_times_ms)
	var frame_max := _maximum(_frame_times_ms)
	var draw_average := _average(_draw_call_samples)
	var draw_max := _maximum(_draw_call_samples)
	_latest = {
		"warming_up": false,
		"profile": GameManager.resolved_presentation_profile(),
		"fps": float(Performance.get_monitor(Performance.TIME_FPS)),
		"process_ms": float(
			Performance.get_monitor(Performance.TIME_PROCESS)
		) * 1000.0,
		"physics_ms": float(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		) * 1000.0,
		"average_frame_ms": frame_average,
		"worst_frame_ms": frame_max,
		"frame_p50_ms": _percentile_sorted(sorted_frames, 0.50),
		"frame_p95_ms": _percentile_sorted(sorted_frames, 0.95),
		"frame_p99_ms": _percentile_sorted(sorted_frames, 0.99),
		"draw_calls": int(round(draw_calls)),
		"draw_calls_average": draw_average,
		"draw_calls_p50": _percentile_sorted(sorted_draws, 0.50),
		"draw_calls_p95": _percentile_sorted(sorted_draws, 0.95),
		"draw_calls_p99": _percentile_sorted(sorted_draws, 0.99),
		"draw_calls_max": int(round(draw_max)),
		"render_objects": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		)),
		"primitives": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(
			Performance.OBJECT_RESOURCE_COUNT
		)),
		"audio_voices": AudioManager.active_voice_count(),
		"static_memory_mib": _mib(Performance.get_monitor(
			Performance.MEMORY_STATIC
		)),
		"video_memory_mib": _mib(Performance.get_monitor(
			Performance.RENDER_VIDEO_MEM_USED
		)),
		"texture_memory_mib": _mib(Performance.get_monitor(
			Performance.RENDER_TEXTURE_MEM_USED
		)),
		"buffer_memory_mib": _mib(Performance.get_monitor(
			Performance.RENDER_BUFFER_MEM_USED
		)),
		"pipeline_compilations_canvas": int(Performance.get_monitor(
			Performance.PIPELINE_COMPILATIONS_CANVAS
		)),
		"pipeline_compilations_mesh": int(Performance.get_monitor(
			Performance.PIPELINE_COMPILATIONS_MESH
		)),
		"pipeline_compilations_draw": int(Performance.get_monitor(
			Performance.PIPELINE_COMPILATIONS_DRAW
		)),
		"measurement_seconds": maxf(0.0, _age - _warmup_seconds),
		"recorded_frames": _frame_times_ms.size(),
		"samples": _sample_count,
		"sample_limit_reached": _sample_limit_reached
	}


func _record_draw_sample() -> void:
	if _age < _warmup_seconds:
		return
	if _draw_call_samples.size() >= MAX_DRAW_SAMPLES:
		_sample_limit_reached = true
		return
	_draw_call_samples.append(float(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	)))
	_sample_count += 1


func snapshot() -> Dictionary:
	return _latest.duplicate(true)


func summary_json() -> String:
	return JSON.stringify(snapshot())


func summary_text() -> String:
	if _latest.is_empty() or bool(_latest.get("warming_up", false)):
		return "metrics warming up"
	return (
		"profile=%s fps=%.1f process=%.2fms physics=%.2fms "
		+ "frame_avg=%.2fms p50=%.2fms p95=%.2fms p99=%.2fms max=%.2fms "
		+ "draws_avg=%.1f draws_p95=%.1f draws_max=%d objects=%d "
		+ "primitives=%d nodes=%d resources=%d voices=%d "
		+ "video_mem=%.1fMiB texture_mem=%.1fMiB samples=%d"
	) % [
		String(_latest["profile"]),
		float(_latest["fps"]),
		float(_latest["process_ms"]),
		float(_latest["physics_ms"]),
		float(_latest["average_frame_ms"]),
		float(_latest["frame_p50_ms"]),
		float(_latest["frame_p95_ms"]),
		float(_latest["frame_p99_ms"]),
		float(_latest["worst_frame_ms"]),
		float(_latest["draw_calls_average"]),
		float(_latest["draw_calls_p95"]),
		int(_latest["draw_calls_max"]),
		int(_latest["render_objects"]),
		int(_latest["primitives"]),
		int(_latest["nodes"]),
		int(_latest["resources"]),
		int(_latest["audio_voices"]),
		float(_latest["video_memory_mib"]),
		float(_latest["texture_memory_mib"]),
		int(_latest["samples"])
	]


static func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


static func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


static func _percentile_sorted(
	sorted_values: Array[float],
	ratio: float
) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(
		int(round(clampf(ratio, 0.0, 1.0) * float(sorted_values.size() - 1))),
		0,
		sorted_values.size() - 1
	)
	return sorted_values[index]


static func _mib(bytes: float) -> float:
	return maxf(0.0, bytes) / BYTES_PER_MIB
