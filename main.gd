extends Node2D

@export var vehicle_scenes: Array[PackedScene] = []   # сцены транспорта (Car, Motorcycle, ...)

const SAVE_PATH := "user://savegame.cfg"
const PIXELS_PER_KMH := 14.0   # км/ч → пикселей/сек для визуала (регулятор «вжуха»)

# Спавн: новая ВОЛНА — через случайное РАССТОЯНИЕ; машины волны — с задержкой между собой.
const SPAWN_DIST_MIN := 500.0    # мин. расстояние до следующей волны (px)
const SPAWN_DIST_MAX := 3000.0   # макс. расстояние до следующей волны (px)
const STAGGER_MIN := 0.15        # мин. задержка между машинами одной волны (сек)
const STAGGER_MAX := 0.45        # макс. задержка между машинами одной волны (сек)
const LANE_OFFSET := 30.0        # случайный сдвиг машины в пределах полосы (не строго по центру)
const SPAWN_GAP := 250.0         # не спавнить, если у верха полосы кто-то ближе этого (px)

# --- геометрия полос (единый источник правды) ---
const SCREEN_WIDTH := 720.0
const LANE_WIDTH := 160.0
var lane_count: int = 3          # ТЕКУЩЕЕ число полос (будет меняться на переходах)

var distance_m: float = 0.0
var best_m: float = 0.0
var time_elapsed: float = 0.0
var game_over: bool = false
var world_speed_px: float = 0.0
var shake_strength: float = 0.0

# состояние спавна
var spawn_accum: float = 0.0       # накопленное расстояние с прошлой волны
var next_wave_dist: float = 0.0    # через сколько px будет следующая волна
var spawn_queue: Array = []        # полосы, ждущие появления (для задержки)
var stagger_timer: float = 0.0     # отсчёт до появления следующей машины из очереди

@onready var score_label: Label = $HUD/ScoreLabel
@onready var game_over_label: Label = $HUD/GameOverLabel

func _ready() -> void:
	load_best()
	update_hud()
	next_wave_dist = randf_range(SPAWN_DIST_MIN, SPAWN_DIST_MAX)

func _process(delta: float) -> void:
	if not game_over:
		world_speed_px = $Player.speed * PIXELS_PER_KMH   # мир едет со скоростью мотоцикла
		distance_m += $Player.speed / 3.6 * delta          # км/ч → м/с, копим метры
		time_elapsed += delta                              # секундомер идёт вперёд
		handle_spawning(delta)
		update_hud()
	# тряска при аварии
	if shake_strength > 0.0:
		shake_strength = max(0.0, shake_strength - 40.0 * delta)
		$Camera2D.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
	else:
		$Camera2D.offset = Vector2.ZERO

# --- спавн транспорта (полностью в коде, без SpawnTimer) ---
func handle_spawning(delta: float) -> void:
	# 1) новая волна — по пройденному расстоянию (случайный промежуток)
	spawn_accum += world_speed_px * delta
	if spawn_accum >= next_wave_dist:
		spawn_accum = 0.0
		next_wave_dist = randf_range(SPAWN_DIST_MIN, SPAWN_DIST_MAX)
		queue_wave()
	# 2) машины из очереди появляются ПО ОДНОЙ, с небольшой задержкой
	stagger_timer -= delta
	if not spawn_queue.is_empty() and stagger_timer <= 0.0:
		spawn_vehicle(spawn_queue.pop_front())
		stagger_timer = randf_range(STAGGER_MIN, STAGGER_MAX)

# набрать волну: 1–2 машины в разных полосах (одна полоса всегда свободна)
func queue_wave() -> void:
	var count = 2 if randf() < 0.7 else 1
	count = min(count, lane_count - 1)
	var lanes := []
	for i in range(lane_count):
		lanes.append(i)
	lanes.shuffle()
	for i in range(count):
		spawn_queue.append(lanes[i])

func spawn_vehicle(lane_index: int) -> void:
	if vehicle_scenes.is_empty() or not lane_top_clear(lane_index):
		return   # нет сцен или полоса забита у верха — пропускаем
	var item = vehicle_scenes.pick_random().instantiate()   # случайный тип транспорта
	item.lane = lane_index
	var x = lane_center(lane_index) + randf_range(-LANE_OFFSET, LANE_OFFSET)
	item.position = Vector2(x, -50.0)   # чуть в сторону от центра полосы
	add_child(item)

# свободен ли верх полосы (чтобы не спавнить поверх стоящих машин)
func lane_top_clear(lane_index: int) -> bool:
	for v in get_tree().get_nodes_in_group("items"):
		if v.lane == lane_index and v.position.y < SPAWN_GAP - 50.0:
			return false
	return true

# центр дороги: левый/правый край асфальта
func road_left() -> float:
	return (SCREEN_WIDTH - lane_count * LANE_WIDTH) / 2.0

func road_right() -> float:
	return road_left() + lane_count * LANE_WIDTH

# центр i-й полосы (0..lane_count-1)
func lane_center(i: int) -> float:
	return road_left() + LANE_WIDTH * (i + 0.5)

# x-координаты пунктирных разделителей между полосами
func lane_divider_xs() -> Array:
	var xs := []
	for i in range(1, lane_count):
		xs.append(road_left() + LANE_WIDTH * i)
	return xs

# SpawnTimer больше не нужен (спавн в _process). Узел можно удалить из сцены.
func _on_spawn_timer_timeout() -> void:
	pass

func _on_player_area_entered(area: Area2D) -> void:
	if game_over:
		return
	shake_strength = 20.0   # тряска при аварии
	finish("Авария!")

func finish(title: String) -> void:
	game_over = true
	get_tree().call_group("items", "set_process", false)
	$Player.set_process(false)
	world_speed_px = 0.0   # останавливаем мир (дорога и трафик замирают)
	if distance_m > best_m:
		best_m = distance_m
		save_best()
	game_over_label.text = "%s\nВремя: %d с\nМетры: %d\nРекорд: %d" % [title, int(time_elapsed), int(distance_m), int(best_m)]
	game_over_label.show()

func _input(event: InputEvent) -> void:
	if game_over and event is InputEventScreenTouch and event.pressed:
		get_tree().reload_current_scene()

func update_hud() -> void:
	score_label.text = "Время: %d\nСкорость: %d км/ч\nМетры: %d" % [int(time_elapsed), int($Player.speed), int(distance_m)]

func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_m = cfg.get_value("game", "best_m", 0)

func save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best_m", best_m)
	cfg.save(SAVE_PATH)
