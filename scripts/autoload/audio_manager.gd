extends Node
## Bounded original score, procedural train ambience, and semantic cue playback.

const SAMPLE_RATE: int = 22050
const POOL_SIZE: int = 12
const MUSIC_PLAYER_COUNT: int = 2
const MAX_VOICES: int = 16
const MUSIC_CROSSFADE_SECONDS: float = 1.8
const SILENCE_DB: float = -72.0
const UI_EVENTS: Array[String] = ["click", "reveal", "ui_reject"]
const MUSIC_STREAMS: Dictionary = {
	"title": "res://assets/generated/audio/music_title.ogg",
	"travel_calm": "res://assets/generated/audio/music_travel_calm.ogg",
	"travel_tension": "res://assets/generated/audio/music_travel_tension.ogg",
	"station": "res://assets/generated/audio/music_station.ogg",
	"longshadow": "res://assets/generated/audio/music_longshadow.ogg",
	"dawn": "res://assets/generated/audio/music_dawn.ogg"
}
const MUSIC_STINGERS: Dictionary = {
	"victory": "res://assets/generated/audio/victory_stinger.ogg",
	"defeat": "res://assets/generated/audio/defeat_stinger.ogg"
}
const GENERATED_STREAMS: Dictionary = {
	"click": [
		"res://assets/generated/audio/ui_click_01.wav",
		"res://assets/generated/audio/ui_click_02.wav",
		"res://assets/generated/audio/ui_click_03.wav"
	],
	"reveal": [
		"res://assets/generated/audio/ui_confirm_01.wav",
		"res://assets/generated/audio/ui_confirm_02.wav",
		"res://assets/generated/audio/ui_confirm_03.wav"
	],
	"ui_reject": [
		"res://assets/generated/audio/ui_reject_01.wav",
		"res://assets/generated/audio/ui_reject_02.wav",
		"res://assets/generated/audio/ui_reject_03.wav"
	],
	"alarm": [
		"res://assets/generated/audio/critical_alarm_01.wav",
		"res://assets/generated/audio/critical_alarm_02.wav",
		"res://assets/generated/audio/critical_alarm_03.wav"
	],
	"departure": ["res://assets/generated/audio/departure_whistle.wav"],
	"impact": [
		"res://assets/generated/audio/impact_01.wav",
		"res://assets/generated/audio/impact_02.wav",
		"res://assets/generated/audio/impact_03.wav"
	],
	"detach": [
		"res://assets/generated/audio/detach_01.wav",
		"res://assets/generated/audio/detach_02.wav",
		"res://assets/generated/audio/detach_03.wav"
	],
	"salvo": [
		"res://assets/generated/audio/salvo_01.wav",
		"res://assets/generated/audio/salvo_02.wav",
		"res://assets/generated/audio/salvo_03.wav"
	],
	"defense_fire": [
		"res://assets/generated/audio/defense_fire_01.wav",
		"res://assets/generated/audio/defense_fire_02.wav",
		"res://assets/generated/audio/defense_fire_03.wav"
	],
	"repair": [
		"res://assets/generated/audio/repair_01.wav",
		"res://assets/generated/audio/repair_02.wav",
		"res://assets/generated/audio/repair_03.wav"
	],
	"overcharge": [
		"res://assets/generated/audio/overcharge_01.wav",
		"res://assets/generated/audio/overcharge_02.wav",
		"res://assets/generated/audio/overcharge_03.wav"
	],
	"flare": [
		"res://assets/generated/audio/flare_01.wav",
		"res://assets/generated/audio/flare_02.wav",
		"res://assets/generated/audio/flare_03.wav"
	],
	"focus": [
		"res://assets/generated/audio/focus_01.wav",
		"res://assets/generated/audio/focus_02.wav",
		"res://assets/generated/audio/focus_03.wav"
	],
	"ward_break": [
		"res://assets/generated/audio/ward_break_01.wav",
		"res://assets/generated/audio/ward_break_02.wav",
		"res://assets/generated/audio/ward_break_03.wav"
	],
	"ward_warning": [
		"res://assets/generated/audio/ward_warning_01.wav",
		"res://assets/generated/audio/ward_warning_02.wav",
		"res://assets/generated/audio/ward_warning_03.wav"
	],
	"route_commit": [
		"res://assets/generated/audio/route_commit_01.wav",
		"res://assets/generated/audio/route_commit_02.wav",
		"res://assets/generated/audio/route_commit_03.wav"
	],
	"station_enter": [
		"res://assets/generated/audio/station_enter_01.wav",
		"res://assets/generated/audio/station_enter_02.wav",
		"res://assets/generated/audio/station_enter_03.wav"
	],
	"threat_pursuer": [
		"res://assets/generated/audio/threat_pursuer_01.wav",
		"res://assets/generated/audio/threat_pursuer_02.wav",
		"res://assets/generated/audio/threat_pursuer_03.wav"
	],
	"threat_boarder": [
		"res://assets/generated/audio/threat_boarder_01.wav",
		"res://assets/generated/audio/threat_boarder_02.wav",
		"res://assets/generated/audio/threat_boarder_03.wav"
	],
	"threat_drainer": [
		"res://assets/generated/audio/threat_drainer_01.wav",
		"res://assets/generated/audio/threat_drainer_02.wav",
		"res://assets/generated/audio/threat_drainer_03.wav"
	],
	"boss_veil": [
		"res://assets/generated/audio/boss_veil_01.wav",
		"res://assets/generated/audio/boss_veil_02.wav",
		"res://assets/generated/audio/boss_veil_03.wav"
	],
	"boss_tether": [
		"res://assets/generated/audio/boss_tether_01.wav",
		"res://assets/generated/audio/boss_tether_02.wav",
		"res://assets/generated/audio/boss_tether_03.wav"
	],
	"boss_charge": [
		"res://assets/generated/audio/boss_charge_01.wav",
		"res://assets/generated/audio/boss_charge_02.wav",
		"res://assets/generated/audio/boss_charge_03.wav"
	],
	"boss_impact": [
		"res://assets/generated/audio/boss_impact_01.wav",
		"res://assets/generated/audio/boss_impact_02.wav",
		"res://assets/generated/audio/boss_impact_03.wav"
	]
}
const CUE_VOLUME_DB: Dictionary = {
	"click": -5.0,
	"reveal": -3.0,
	"ui_reject": -2.0,
	"alarm": -1.0,
	"defense_fire": -4.0,
	"impact": -1.0,
	"focus": -2.0,
	"ward_break": -1.0,
	"ward_warning": -2.0,
	"threat_pursuer": -2.0,
	"threat_boarder": -2.0,
	"threat_drainer": -2.0,
	"boss_veil": -1.0,
	"boss_tether": -1.0,
	"boss_charge": -1.0,
	"boss_impact": 0.0
}

var _players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _stinger: AudioStreamPlayer
var _next_player: int = 0
var _cache: Dictionary = {}
var _variant_counters: Dictionary = {}

var _ambient: AudioStreamPlayer
var _ambient_stream: AudioStreamGenerator
var _ambient_playback: AudioStreamGeneratorPlayback
var _ambient_noise_state: int = 0x1A17E2
var _engine_phase: float = 0.0
var _boiler_phase: float = 0.0
var _wheel_phase: float = 0.0
var _rail_phase: float = 0.0
var _carriage_phase: float = 0.0
var _pressure_phase: float = 0.0
var _rail_impulse: float = 0.0
var _rail_side: float = -1.0
var _boiler_filter: float = 0.0
var _wind_filter_left: float = 0.0
var _wind_filter_right: float = 0.0
var _wheel_rate: float = 3.0

var _enabled: bool = true
var _user_gestured: bool = false
var _presentation_state: Dictionary = {
	"mode": "title",
	"music_state": "title",
	"tension": 0.0,
	"paused": false
}
var _requested_music_state: String = "title"
var _music_state: String = ""
var _music_primary_index: int = -1
var _music_fade_out_index: int = -1
var _music_fade_elapsed: float = 0.0
var _music_fade_out_start_gain: float = 0.0
var _music_crossfading: bool = false


func _ready() -> void:
	set_process(false)
	_ensure_buses()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX Center"
		player.playback_type = AudioServer.PLAYBACK_TYPE_DEFAULT
		add_child(player)
		_players.append(player)
	for i in range(MUSIC_PLAYER_COUNT):
		var music_player := AudioStreamPlayer.new()
		music_player.bus = &"Music"
		music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		music_player.volume_db = SILENCE_DB
		add_child(music_player)
		_music_players.append(music_player)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = &"Music"
	_stinger.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_stinger)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = &"Ambience"
	_ambient.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_ambient)
	_apply_volume()
	GameManager.settings_changed.connect(_apply_volume)


func notify_user_gesture() -> void:
	if _user_gestured:
		return
	_user_gestured = true
	_start_ambient()
	_transition_music(_requested_music_state)
	set_process(true)


func set_wheel_rate(rate_hz: float) -> void:
	_wheel_rate = clampf(rate_hz, 0.0, 8.0)


func play(name: String) -> void:
	if MUSIC_STINGERS.has(name):
		_play_stinger(name)
		return
	_play_cue(name, 0.0)


func play_spatial(name: String, pan: float) -> void:
	_play_cue(name, clampf(pan, -1.0, 1.0))


func set_presentation_state(state: Dictionary) -> void:
	_presentation_state = state.duplicate(true)
	_requested_music_state = String(
		_presentation_state.get("music_state", "travel_calm")
	)
	if _ambient != null:
		var mode: String = String(_presentation_state.get("mode", "travel"))
		_ambient.volume_db = {
			"title": -5.0,
			"route": -2.0,
			"station": -1.0,
			"ending": -4.0,
			"ended": -8.0
		}.get(mode, 0.0)
	if _user_gestured and _requested_music_state != _music_state:
		_transition_music(_requested_music_state)


func presentation_state() -> Dictionary:
	return _presentation_state.duplicate(true)


func active_voice_count() -> int:
	var count: int = 1 if _ambient != null and _ambient.playing else 0
	for player in _players:
		if player.playing:
			count += 1
	for player in _music_players:
		if player.playing:
			count += 1
	if _stinger != null and _stinger.playing:
		count += 1
	return count


func active_music_player_count() -> int:
	var count: int = 0
	for player in _music_players:
		if player.playing:
			count += 1
	return count


func voice_capacity() -> int:
	return MAX_VOICES


func music_state_count() -> int:
	return MUSIC_STREAMS.size()


func variant_count(name: String) -> int:
	var paths: Array = GENERATED_STREAMS.get(name, [])
	return paths.size()


func has_cue(name: String) -> bool:
	return GENERATED_STREAMS.has(name) or MUSIC_STINGERS.has(name)


func debug_snapshot() -> Dictionary:
	return {
		"user_gestured": _user_gestured,
		"ambient_playing": _ambient != null and _ambient.playing,
		"music_state": _music_state,
		"requested_music_state": _requested_music_state,
		"active_music_players": active_music_player_count(),
		"active_voices": active_voice_count(),
		"voice_capacity": MAX_VOICES,
		"crossfading": _music_crossfading,
		"cached_streams": _cache.size()
	}


func stop_all_for_probe() -> void:
	for player in _players:
		player.stop()
		player.stream = null
	for player in _music_players:
		player.stop()
		player.stream = null
	if _stinger != null:
		_stinger.stop()
		_stinger.stream = null
	if _ambient != null:
		_ambient.stop()
		_ambient.stream = null
	_ambient_playback = null
	_ambient_stream = null
	_music_primary_index = -1
	_music_fade_out_index = -1
	_music_crossfading = false
	_cache.clear()
	for bus_name in [&"SFX Right", &"SFX Center", &"SFX Left"]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.remove_bus(bus_index)
	set_process(false)


func _play_cue(name: String, pan: float) -> void:
	if not _enabled or not _user_gestured or _players.is_empty():
		return
	var stream: AudioStream = _next_variant_stream(name)
	if stream == null:
		stream = _synth(name)
	if stream == null:
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.bus = (
		&"UI"
		if UI_EVENTS.has(name)
		else _sfx_bus_for_pan(pan)
	)
	player.stream = stream
	player.volume_db = float(CUE_VOLUME_DB.get(name, 0.0))
	player.pitch_scale = 1.0
	player.play()


func _play_stinger(name: String) -> void:
	if not _enabled or not _user_gestured or _stinger == null:
		return
	var path: String = String(MUSIC_STINGERS.get(name, ""))
	var stream: AudioStream = _load_stream(path, false)
	if stream == null:
		stream = _synth(name)
	if stream == null:
		return
	_stinger.stop()
	_stinger.stream = stream
	_stinger.volume_db = -0.5
	_stinger.play()


func _next_variant_stream(name: String) -> AudioStream:
	var paths: Array = GENERATED_STREAMS.get(name, [])
	if paths.is_empty():
		return null
	var counter: int = int(_variant_counters.get(name, 0))
	var offset: int = posmod(name.hash(), paths.size())
	var path: String = String(paths[(counter + offset) % paths.size()])
	_variant_counters[name] = counter + 1
	return _load_stream(path, false)


func _load_stream(path: String, looped: bool) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var cache_key: String = "%s|%s" % [path, str(looped)]
	var cached: AudioStream = _cache.get(cache_key, null)
	if cached != null:
		return cached
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return null
	if looped and stream is AudioStreamOggVorbis:
		stream = stream.duplicate() as AudioStream
		(stream as AudioStreamOggVorbis).loop = true
		(stream as AudioStreamOggVorbis).loop_offset = 0.0
	_cache[cache_key] = stream
	return stream


func _transition_music(next_state: String) -> void:
	if not _user_gestured:
		return
	if next_state == _music_state and _music_primary_index >= 0:
		var current: AudioStreamPlayer = _music_players[_music_primary_index]
		if current.playing:
			return
	if (
		_music_fade_out_index >= 0
		and _music_fade_out_index != _music_primary_index
	):
		_music_players[_music_fade_out_index].stop()
	var previous_index: int = _music_primary_index
	var previous_gain: float = (
		db_to_linear(_music_players[previous_index].volume_db)
		if previous_index >= 0
		else 0.0
	)
	_music_fade_out_index = previous_index
	_music_fade_out_start_gain = previous_gain
	_music_primary_index = -1
	_music_state = next_state
	_music_fade_elapsed = 0.0
	_music_crossfading = true

	if next_state != "silence":
		var path: String = String(MUSIC_STREAMS.get(next_state, ""))
		var stream: AudioStream = _load_stream(path, true)
		if stream != null:
			var target_index: int = (
				0 if previous_index < 0 else 1 - previous_index
			)
			var target: AudioStreamPlayer = _music_players[target_index]
			target.stop()
			target.stream = stream
			target.volume_db = SILENCE_DB
			target.play()
			_music_primary_index = target_index

	if _music_primary_index < 0 and _music_fade_out_index < 0:
		_music_crossfading = false


func _update_music(delta: float) -> void:
	if not _music_crossfading:
		return
	_music_fade_elapsed += delta
	var ratio: float = clampf(
		_music_fade_elapsed / MUSIC_CROSSFADE_SECONDS,
		0.0,
		1.0
	)
	var smooth_ratio: float = ratio * ratio * (3.0 - 2.0 * ratio)
	if _music_primary_index >= 0:
		_set_player_gain(_music_players[_music_primary_index], smooth_ratio)
	if _music_fade_out_index >= 0:
		_set_player_gain(
			_music_players[_music_fade_out_index],
			_music_fade_out_start_gain * (1.0 - smooth_ratio)
		)
	if ratio < 1.0:
		return
	if _music_fade_out_index >= 0:
		_music_players[_music_fade_out_index].stop()
		_music_players[_music_fade_out_index].volume_db = SILENCE_DB
	if _music_primary_index >= 0:
		_music_players[_music_primary_index].volume_db = 0.0
	_music_fade_out_index = -1
	_music_crossfading = false


func _set_player_gain(player: AudioStreamPlayer, gain: float) -> void:
	player.volume_db = linear_to_db(maxf(0.00025, gain))


func _apply_volume() -> void:
	_set_bus_linear("Master", float(GameManager.get_setting("master_volume", 0.8)))
	_set_bus_linear("Music", float(GameManager.get_setting("music_volume", 0.72)))
	_set_bus_linear(
		"Ambience",
		float(GameManager.get_setting("ambience_volume", 0.72))
	)
	_set_bus_linear("SFX", float(GameManager.get_setting("sfx_volume", 0.86)))
	_set_bus_linear("UI", float(GameManager.get_setting("ui_volume", 0.82)))


func _ensure_buses() -> void:
	for bus_name in [&"Music", &"Ambience", &"SFX", &"UI"]:
		_ensure_bus(bus_name, &"Master")
	_ensure_panner_bus(&"SFX Left", -0.72)
	_ensure_panner_bus(&"SFX Center", 0.0)
	_ensure_panner_bus(&"SFX Right", 0.72)


func _ensure_bus(bus_name: StringName, send_name: StringName) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus_name)
	if not send_name.is_empty():
		AudioServer.set_bus_send(index, send_name)
	return index


func _ensure_panner_bus(bus_name: StringName, pan: float) -> void:
	var index: int = _ensure_bus(bus_name, &"SFX")
	var panner: AudioEffectPanner = null
	for effect_index in range(AudioServer.get_bus_effect_count(index)):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, effect_index)
		if effect is AudioEffectPanner:
			panner = effect as AudioEffectPanner
			break
	if panner == null:
		panner = AudioEffectPanner.new()
		AudioServer.add_bus_effect(index, panner)
	panner.pan = pan


func _sfx_bus_for_pan(pan: float) -> StringName:
	if pan < -0.24:
		return &"SFX Left"
	if pan > 0.24:
		return &"SFX Right"
	return &"SFX Center"


func _set_bus_linear(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(
		index,
		linear_to_db(maxf(0.0001, clampf(value, 0.0, 1.0)))
	)


func _start_ambient() -> void:
	if _ambient == null or _ambient.playing:
		return
	_ambient_stream = AudioStreamGenerator.new()
	_ambient_stream.mix_rate = SAMPLE_RATE
	_ambient_stream.buffer_length = 0.35
	_ambient.stream = _ambient_stream
	_ambient.play()
	_ambient_playback = _ambient.get_stream_playback()


func _process(delta: float) -> void:
	_update_music(delta)
	_fill_ambient()


func _fill_ambient() -> void:
	if _ambient_playback == null:
		return
	var frames_to_push: int = _ambient_playback.get_frames_available()
	if frames_to_push <= 0:
		return
	var levels: Dictionary = _ambient_levels()
	var engine_level: float = float(levels.get("engine", 0.0))
	var boiler_level: float = float(levels.get("boiler", 0.0))
	var wheel_level: float = float(levels.get("wheel", 0.0))
	var wind_level: float = float(levels.get("wind", 0.0))
	var carriage_level: float = float(levels.get("carriage", 0.0))
	var pressure_level: float = float(levels.get("pressure", 0.0))
	var stereo_width: float = float(levels.get("width", 0.5))
	var paused: bool = bool(_presentation_state.get("paused", false))
	var speed_ratio: float = clampf(_wheel_rate / 6.0, 0.0, 1.0)
	if paused:
		wheel_level *= 0.12
		engine_level *= 0.55

	var buffer := PackedVector2Array()
	buffer.resize(frames_to_push)
	var inv_sample_rate: float = 1.0 / float(SAMPLE_RATE)
	for index in range(frames_to_push):
		var noise_left: float = _next_noise()
		var noise_right: float = _next_noise()
		_boiler_filter = lerpf(_boiler_filter, noise_left, 0.035)
		_wind_filter_left = lerpf(_wind_filter_left, noise_left, 0.006)
		_wind_filter_right = lerpf(_wind_filter_right, noise_right, 0.006)

		_engine_phase = fmod(
			_engine_phase + (47.0 + speed_ratio * 18.0) * inv_sample_rate,
			1.0
		)
		_boiler_phase = fmod(_boiler_phase + 0.34 * inv_sample_rate, 1.0)
		_carriage_phase = fmod(_carriage_phase + 91.0 * inv_sample_rate, 1.0)
		_pressure_phase = fmod(_pressure_phase + 31.0 * inv_sample_rate, 1.0)
		_rail_phase = fmod(_rail_phase + 1180.0 * inv_sample_rate, 1.0)

		var wheel_next: float = _wheel_phase + _wheel_rate * inv_sample_rate
		if wheel_next >= 1.0:
			wheel_next = fmod(wheel_next, 1.0)
			_rail_impulse = 1.0
			_rail_side *= -1.0
		_wheel_phase = wheel_next

		var piston: float = pow(
			maxf(0.0, sin(_wheel_phase * TAU)),
			7.0
		)
		var engine: float = (
			sin(_engine_phase * TAU) * 0.034
			+ sin(_engine_phase * TAU * 2.0) * 0.011
			+ piston * 0.024
		) * engine_level
		var boiler_breath: float = 0.64 + 0.36 * sin(_boiler_phase * TAU)
		var boiler: float = _boiler_filter * boiler_breath * 0.038 * boiler_level
		var rail: float = (
			sin(_rail_phase * TAU) * 0.07
			+ noise_right * 0.025
		) * _rail_impulse * wheel_level
		_rail_impulse *= 0.9962
		var wind_left: float = _wind_filter_left * 0.055 * wind_level
		var wind_right: float = _wind_filter_right * 0.055 * wind_level
		var carriage_mod: float = 0.5 + 0.5 * sin(_boiler_phase * TAU * 0.5)
		var carriage: float = (
			sin(_carriage_phase * TAU) * carriage_mod * 0.018
			* carriage_level
		)
		var pressure: float = (
			sin(_pressure_phase * TAU) * 0.036 * pressure_level
		)
		var rail_left: float = rail * (1.0 if _rail_side < 0.0 else 0.34)
		var rail_right: float = rail * (1.0 if _rail_side > 0.0 else 0.34)
		var left: float = (
			engine
			+ boiler * (1.0 - stereo_width * 0.18)
			+ wind_left * (0.55 + stereo_width * 0.45)
			+ rail_left
			+ carriage * 0.82
			+ pressure
		)
		var right: float = (
			engine
			+ boiler * (1.0 + stereo_width * 0.18)
			+ wind_right * (0.55 + stereo_width * 0.45)
			+ rail_right
			+ carriage
			+ pressure
		)
		buffer[index] = Vector2(
			clampf(left, -0.82, 0.82),
			clampf(right, -0.82, 0.82)
		)
	_ambient_playback.push_buffer(buffer)


func _ambient_levels() -> Dictionary:
	var mode: String = String(_presentation_state.get("mode", "travel"))
	var tension: float = clampf(
		float(_presentation_state.get("tension", 0.0)),
		0.0,
		1.0
	)
	match mode:
		"title":
			return {
				"engine": 0.0,
				"boiler": 0.22,
				"wheel": 0.0,
				"wind": 0.52,
				"carriage": 0.1,
				"pressure": 0.0,
				"width": 0.78
			}
		"route":
			return {
				"engine": 0.38,
				"boiler": 0.48,
				"wheel": 0.16,
				"wind": 0.46,
				"carriage": 0.35,
				"pressure": tension * 0.18,
				"width": 0.72
			}
		"station":
			return {
				"engine": 0.24,
				"boiler": 0.72,
				"wheel": 0.03,
				"wind": 0.38,
				"carriage": 0.26,
				"pressure": 0.0,
				"width": 1.0
			}
		"boss":
			return {
				"engine": 0.72,
				"boiler": 0.5,
				"wheel": 0.55,
				"wind": 0.62,
				"carriage": 0.68,
				"pressure": 0.75 + tension * 0.25,
				"width": 0.7
			}
		"ending", "ended":
			return {
				"engine": 0.16,
				"boiler": 0.34,
				"wheel": 0.05,
				"wind": 0.28,
				"carriage": 0.2,
				"pressure": 0.0,
				"width": 0.9
			}
		_:
			return {
				"engine": 0.62 + tension * 0.16,
				"boiler": 0.46,
				"wheel": 0.62 + tension * 0.22,
				"wind": 0.34 + tension * 0.2,
				"carriage": 0.46 + tension * 0.22,
				"pressure": tension * 0.22,
				"width": 0.58
			}


func _next_noise() -> float:
	_ambient_noise_state = int(
		(_ambient_noise_state * 1664525 + 1013904223) & 0xFFFFFFFF
	)
	return (
		float((_ambient_noise_state >> 8) & 0xFFFFFF) / 8388607.5
		- 1.0
	)


func _synth(name: String) -> AudioStreamWAV:
	match name:
		"click":
			return _make_click(0.05, 900.0, 1200.0)
		"alarm", "ui_reject":
			return _make_click(0.4, 440.0, 300.0, true)
		"impact", "boss_impact":
			return _make_noise(0.25, 0.8)
		"detach":
			return _make_click(0.6, 220.0, 60.0, true)
		"salvo", "defense_fire":
			return _make_noise(0.32, 1.0)
		"repair":
			return _make_click(0.28, 420.0, 840.0)
		"overcharge", "flare", "focus":
			return _make_click(0.42, 180.0, 1100.0, true)
		"victory":
			return _make_chord([392.0, 523.0, 659.0], 1.2)
		"defeat":
			return _make_chord([146.0, 175.0, 208.0], 1.4, true)
		"reveal", "ward_break", "ward_warning", "route_commit", "station_enter":
			return _make_click(0.3, 660.0, 990.0)
		"departure":
			return _make_chord([293.66, 440.0, 587.33], 0.9)
		_:
			return null


func _make_click(
	duration: float,
	start_hz: float,
	end_hz: float,
	pulse: bool = false
) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase: float = 0.0
	for i in range(frames):
		var ratio: float = float(i) / maxf(1.0, float(frames))
		var frequency: float = lerpf(start_hz, end_hz, ratio)
		phase = fmod(phase + frequency / float(SAMPLE_RATE), 1.0)
		var env: float = pow(1.0 - ratio, 2.0)
		var sample: float = sin(phase * TAU) * env * 0.4
		if pulse:
			sample *= 0.5 + 0.5 * sin(ratio * TAU * 6.0)
		_write_s16(data, i, sample)
	return _wrap(data)


func _make_noise(duration: float, amplitude: float) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(frames):
		var ratio: float = float(i) / maxf(1.0, float(frames))
		var env: float = pow(1.0 - ratio, 3.0)
		var sample: float = (
			(rng.randf() * 2.0 - 1.0) * env * amplitude * 0.5
		)
		_write_s16(data, i, sample)
	return _wrap(data)


func _make_chord(
	frequencies: Array,
	duration: float,
	minor: bool = false
) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phases: Array[float] = []
	for frequency in frequencies:
		phases.append(0.0)
	for i in range(frames):
		var ratio: float = float(i) / maxf(1.0, float(frames))
		var env: float = sin(clampf(ratio * PI, 0.0, PI)) * 0.35
		var sample: float = 0.0
		for j in range(frequencies.size()):
			var frequency: float = float(frequencies[j])
			if minor and j == 1:
				frequency *= 0.94
			phases[j] = fmod(
				phases[j] + frequency / float(SAMPLE_RATE),
				1.0
			)
			sample += (
				sin(phases[j] * TAU) * env / float(frequencies.size())
			)
		_write_s16(data, i, sample)
	return _wrap(data)


func _write_s16(data: PackedByteArray, index: int, sample: float) -> void:
	var value: int = int(clampf(sample, -1.0, 1.0) * 32000.0)
	data[index * 2] = value & 0xFF
	data[index * 2 + 1] = (value >> 8) & 0xFF


func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
