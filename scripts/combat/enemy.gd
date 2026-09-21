class_name Enemy
extends RefCounted
## Enemy
##
## Pure data enemy for pooled use. game_world owns the pool.

var kind: String = "Pursuer"
var display: String = "Rail Pursuer"
var hp: float = 30.0
var max_hp: float = 30.0
var damage: float = 6.0
var speed: float = 55.0
var attack_interval: float = 1.6
var attack_timer: float = 0.0
var color: Color = Color(0.65, 0.2, 0.25)
# world position in screen coordinates
var position: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var alive: bool = false
var role: String = "ground"  # ground, roof, air
var value: int = 1
var boarder_car_index: int = -1
var attack_warning_time: float = 0.65
var warded: bool = false
var ward_hp: float = 0.0
var ward_max_hp: float = 0.0


func init_from_config(kind_key: String, cfg: Dictionary) -> void:
	kind = kind_key
	display = String(cfg.get("display", kind_key))
	hp = float(cfg.get("hp", 30))
	max_hp = hp
	damage = float(cfg.get("damage", 5))
	speed = float(cfg.get("speed", 50))
	attack_interval = float(cfg.get("attack_interval", 1.6))
	var col_arr: Array = cfg.get("color", [0.7, 0.3, 0.3])
	color = Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]))
	value = 1
	if kind == "Boarder":
		role = "roof"
	elif kind == "Drainer":
		role = "air"
	else:
		role = "ground"
	boarder_car_index = -1
	attack_warning_time = 0.65
	attack_timer = attack_interval
	warded = false
	ward_hp = 0.0
	ward_max_hp = 0.0
