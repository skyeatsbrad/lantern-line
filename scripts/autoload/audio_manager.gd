extends Node
## AudioManager
##
## Pooled procedural audio only. No files, no external assets.
## Silence-safe: if generation fails, methods return without erroring.

const SAMPLE_RATE: int = 22050
const POOL_SIZE: int = 6

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _cache: Dictionary = {}
var _ambient: AudioStreamPlayer
var _ambient_stream: AudioStreamGenerator
var _ambient_playback: AudioStreamGeneratorPlayback
var _ambient_phase: float = 0.0
var _wheel_phase: float = 0.0
var _wheel_rate: float = 3.0
var _enabled: bool = true
var _user_gestured: bool = false


func _ready() -> void:
	set_process(false)
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Master"
	add_child(_ambient)
	_apply_volume()
	GameManager.settings_changed.connect(_apply_volume)


func notify_user_gesture() -> void:
	if _user_gestured:
		return
	_user_gestured = true
	_start_ambient()
	set_process(true)


func set_wheel_rate(rate_hz: float) -> void:
	_wheel_rate = clampf(rate_hz, 0.0, 8.0)


func play(name: String) -> void:
	if not _enabled or not _user_gestured:
		return
	var stream: AudioStreamWAV = _cache.get(name, null)
	if stream == null:
		stream = _synth(name)
		if stream == null:
			return
		_cache[name] = stream
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = 0.0
	player.play()


func _apply_volume() -> void:
	var vol: float = float(GameManager.get_setting("master_volume", 0.8))
	var db: float = linear_to_db(max(0.0001, vol))
	AudioServer.set_bus_volume_db(0, db)


func _start_ambient() -> void:
	_ambient_stream = AudioStreamGenerator.new()
	_ambient_stream.mix_rate = SAMPLE_RATE
	_ambient_stream.buffer_length = 0.25
	_ambient.stream = _ambient_stream
	_ambient.play()
	_ambient_playback = _ambient.get_stream_playback()


func _process(_delta: float) -> void:
	if _ambient_playback == null:
		return
	var frames_to_push: int = _ambient_playback.get_frames_available()
	if frames_to_push <= 0:
		return
	var buf: PackedVector2Array = PackedVector2Array()
	buf.resize(frames_to_push)
	var inv_sr: float = 1.0 / float(SAMPLE_RATE)
	var wheel_step: float = _wheel_rate * inv_sr
	for i in range(frames_to_push):
		_ambient_phase = fmod(_ambient_phase + 55.0 * inv_sr, 1.0)
		_wheel_phase = fmod(_wheel_phase + wheel_step, 1.0)
		var hum: float = sin(_ambient_phase * TAU) * 0.05
		var thud: float = 0.0
		if _wheel_phase < 0.05:
			thud = (1.0 - _wheel_phase / 0.05) * 0.12 * sin(_wheel_phase * TAU * 8.0)
		var s: float = hum + thud
		buf[i] = Vector2(s, s)
	_ambient_playback.push_buffer(buf)


func _synth(name: String) -> AudioStreamWAV:
	match name:
		"click":
			return _make_click(0.05, 900.0, 1200.0)
		"alarm":
			return _make_click(0.4, 440.0, 300.0, true)
		"impact":
			return _make_noise(0.25, 0.8)
		"detach":
			return _make_click(0.6, 220.0, 60.0, true)
		"victory":
			return _make_chord([392.0, 523.0, 659.0], 1.2)
		"defeat":
			return _make_chord([146.0, 175.0, 208.0], 1.4, true)
		"reveal":
			return _make_click(0.3, 660.0, 990.0)
		_:
			return null


func _make_click(duration: float, start_hz: float, end_hz: float, pulse: bool = false) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var phase: float = 0.0
	for i in range(frames):
		var t: float = float(i) / max(1.0, float(frames))
		var freq: float = lerp(start_hz, end_hz, t)
		phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
		var env: float = pow(1.0 - t, 2.0)
		var s: float = sin(phase * TAU) * env * 0.4
		if pulse:
			s *= 0.5 + 0.5 * sin(t * TAU * 6.0)
		_write_s16(data, i, s)
	return _wrap(data)


func _make_noise(duration: float, amp: float) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(frames):
		var t: float = float(i) / max(1.0, float(frames))
		var env: float = pow(1.0 - t, 3.0)
		var s: float = (rng.randf() * 2.0 - 1.0) * env * amp * 0.5
		_write_s16(data, i, s)
	return _wrap(data)


func _make_chord(freqs: Array, duration: float, minor: bool = false) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var phases: Array[float] = []
	for f in freqs:
		phases.append(0.0)
	for i in range(frames):
		var t: float = float(i) / max(1.0, float(frames))
		var env: float = sin(clamp(t * PI, 0.0, PI)) * 0.35
		var s: float = 0.0
		for j in range(freqs.size()):
			var f: float = freqs[j]
			if minor and j == 1:
				f *= 0.94
			phases[j] = fmod(phases[j] + f / float(SAMPLE_RATE), 1.0)
			s += sin(phases[j] * TAU) * env / float(freqs.size())
		_write_s16(data, i, s)
	return _wrap(data)


func _write_s16(data: PackedByteArray, i: int, sample: float) -> void:
	var v: int = int(clamp(sample, -1.0, 1.0) * 32000.0)
	data[i * 2] = v & 0xFF
	data[i * 2 + 1] = (v >> 8) & 0xFF


func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = data
	return w
