class_name WebRuntimeQuery
extends RefCounted


static func parameter(name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var script := (
		"new URLSearchParams(window.location.search).get(%s) || ''"
		% JSON.stringify(name)
	)
	return String(JavaScriptBridge.eval(script, true))


static func environment_or_parameter(
	environment_name: String,
	parameter_name: String
) -> String:
	var environment_value := OS.get_environment(environment_name)
	if not environment_value.is_empty():
		return environment_value
	return parameter(parameter_name)


static func benchmark_parameter(name: String) -> String:
	if not OS.has_feature("qa_visual_benchmark"):
		return ""
	return parameter(name)


static func environment_or_benchmark_parameter(
	environment_name: String,
	parameter_name: String
) -> String:
	var environment_value := OS.get_environment(environment_name)
	if not environment_value.is_empty():
		return environment_value
	return benchmark_parameter(parameter_name)


static func publish(name: String, payload: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var script := "window[%s] = %s" % [
		JSON.stringify(name),
		JSON.stringify(payload)
	]
	JavaScriptBridge.eval(script, true)
