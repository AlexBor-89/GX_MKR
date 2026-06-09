extends Area2D

# Базовый скрипт транспорта. Текстуру (цвет), коллизию и позже поворотники/стопы
# настраиваешь в КОНКРЕТНОЙ сцене (Car.tscn, Motorcycle.tscn, ...).
# Логика движения и «не наезжать на переднего» — общая, тут.

@export var textures: Array[Texture2D] = []   # цветовые варианты (выбирается случайный)
@export var rel_speed_min: float = 0.3        # скорость как доля от скорости игрока: мин
@export var rel_speed_max: float = 0.5         # ... макс (больше = едет быстрее)

const BUMPER := 30.0       # зазор между бамперами при следовании (px)
const BRAKE_ZONE := 220.0  # за сколько ДО дистанции начинать плавно тормозить (px)
const ACCEL := 3000.0      # макс. изменение скорости в секунду (плавность)

var lane: int = 0
var rel_speed: float = 0.4   # конкретная скорость этого экземпляра
var drift: float = 0.0       # фактическая скорость вниз в этом кадре (читают те, кто сзади)
var half_len: float = 60.0   # половина длины спрайта (для дистанции следования)

func _ready() -> void:
	if not textures.is_empty():
		$Sprite2D.texture = textures.pick_random()   # случайный цвет
	rel_speed = randf_range(rel_speed_min, rel_speed_max)
	if $Sprite2D.texture != null:
		half_len = $Sprite2D.texture.get_size().y * 0.5

func _process(delta: float) -> void:
	# своя скорость: едем вниз медленнее дороги — значит едем ВПЕРЁД относительно неё
	var free_drift = get_parent().world_speed_px * (1.0 - rel_speed)
	var target = free_drift
	var lead = find_leader()
	var min_gap = 0.0
	var gap = 0.0
	if lead != null:
		min_gap = half_len + lead.half_len + BUMPER   # дистанция бампер-в-бампер по размеру
		gap = lead.position.y - position.y
		if gap < min_gap + BRAKE_ZONE:   # в зоне торможения плавно гасим скорость
			var t = clamp((gap - min_gap) / BRAKE_ZONE, 0.0, 1.0)
			target = lerp(min(free_drift, lead.drift), free_drift, t)
	drift = move_toward(drift, target, ACCEL * delta)   # плавно, без рывков
	if lead != null and gap < min_gap:                  # страховка от наезда
		drift = min(drift, lead.drift)
	position.y += drift * delta
	if position.y > get_viewport_rect().size.y + 100.0:
		queue_free()

# ближайшая машина впереди (ниже по экрану) в той же полосе
func find_leader():
	var best = null
	var best_gap := 1.0e20
	for other in get_tree().get_nodes_in_group("items"):
		if other == self or other.lane != lane:
			continue
		var g = other.position.y - position.y
		if g > 0.0 and g < best_gap:
			best_gap = g
			best = other
	return best
