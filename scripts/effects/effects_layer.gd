class_name EffectsLayer
extends Node2D
## EffectsLayer
##
## Pooled screen shake, hit sparks, dawn glow overlay.

const MAX_HITS: int = 24

var _shake: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _hits: Array = []
var _dawn_progress: float = 0.0
var _reduced_motion: bool = false
var _screen_shake_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	set_process(true)


func request_shake(amount: float) -> void:
	if not bool(GameManager.get_setting("screen_shake", true)):
		return
	if bool(GameManager.get_setting("reduced_motion", false)):
		return
	_shake = clampf(_shake + amount, 0.0, 20.0)


func add_hit(pos: Vector2, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	if _hits.size() >= MAX_HITS:
		_hits.pop_front()
	_hits.append({"pos": pos, "age": 0.0, "life": 0.35, "color": color, "size": 12.0 + _rng.randf() * 6.0})


func set_dawn_progress(v: float) -> void:
	_dawn_progress = clampf(v, 0.0, 1.0)


func shake_offset() -> Vector2:
	return _shake_offset


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake_offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - delta * 40.0)
	else:
		_shake_offset = Vector2.ZERO
	for h in _hits:
		h["age"] = float(h["age"]) + delta
	_hits = _hits.filter(func(h: Dictionary) -> bool: return h["age"] < h["life"])
	queue_redraw()


func _draw() -> void:
	for h in _hits:
		var a: float = 1.0 - float(h["age"]) / float(h["life"])
		var c: Color = h["color"]
		draw_circle(h["pos"], h["size"] * a, Color(c.r, c.g, c.b, a))
	# dawn overlay near end
	if _dawn_progress > 0.05:
		var vp: Vector2 = get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.85, 0.55, _dawn_progress * 0.4))
