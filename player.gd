extends Area2D

# --- руль ---
@export var steer_speed: float = 2000.0
var target_x: float

# --- скорость мотоцикла (км/ч) ---
const MIN_SPEED := 30.0
const MAX_SPEED := 210.0
const ACCEL := 25.0   # разгон, км/ч за секунду (палец зажат)
const DECEL := 10.0   # торможение, км/ч за секунду (палец отпущен)
var speed: float = 40.0
var holding: bool = false

func _ready() -> void:
	target_x = global_position.x

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		holding = event.pressed        # нажал — газ, отпустил — тормоз
		target_x = event.position.x
	elif event is InputEventScreenDrag:
		target_x = event.position.x

func _process(delta: float) -> void:
	# газ / торможение
	if holding:
		speed = min(speed + ACCEL * delta, MAX_SPEED)
	else:
		speed = max(speed - DECEL * delta, MIN_SPEED)
	# руль (как раньше)
	var new_x = move_toward(global_position.x, target_x, steer_speed * delta)
	global_position.x = clamp(new_x, get_parent().road_left() + 25.0, get_parent().road_right() - 25.0)
