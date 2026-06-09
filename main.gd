extends Node2D

@export var vehicle_scenes: Array[PackedScene] = []   # сцены транспорта (Car, Motorcycle, ...)

const SAVE_PATH := "user://savegame.cfg"
const PIXELS_PER_KMH := 14.0   # км/ч → пикселей/сек для визуала (регулятор «вжуха»)

# Спавн: новая ВОЛНА — через случайное РАССТОЯНИЕ; машины волны — с задержкой между собой.
const SPAWN_DIST_MIN := 1500.0    # мин. расстояние до следующей волны (px)
const SPAWN_DIST_MAX := 3500.0    # макс. расстояние до следующей волны (px)
const STAGGER_MIN := 0.15        # мин. задержка между машинами одной волны (сек)
const STAGGER_MAX := 0.45        # макс. задержка между машинами одной волны (сек)
const LANE_OFFSET := 30.0        # случайный сдвиг машины в пределах полосы (не строго по центру)
const SPAWN_GAP := 250.0         # не спавнить, если у верха полосы кто-то ближе этого (px)

# --- геометрия полос: 2 ЦЕНТРАЛЬНЫЕ всегда (слоты 0,1) + край слева (-1) / справа (2) ---
const SCREEN_WIDTH := 720.0
const LANE_WIDTH := 160.0
const CORE_LANES := 2
const CORE_LEFT := SCREEN_WIDTH / 2.0 - CORE_LANES * LANE_WIDTH / 2.0    # 200 (левый край центра)
const CORE_RIGHT := SCREEN_WIDTH / 2.0 + CORE_LANES * LANE_WIDTH / 2.0   # 520 (правый край центра)
const NO_BLOCK := 99   # «слот не заблокирован»

var left_lanes: int = 0       # доп. полоса слева (0/1) → слот -1
var right_lanes: int = 0      # доп. полоса справа (0/1) → слот 2
var road_left_px: float = CORE_LEFT     # анимируемый левый край асфальта
var road_right_px: float = CORE_RIGHT   # анимируемый правый край асфальта

# --- переходы: добавляем/убираем КРАЙ; центр спавнит всегда ---
enum Phase { NORMAL, WAIT_EDGE_CLEAR, ANIMATING }
const TRANSITION_DURATION := 1.5  # сек на анимацию края
const TRANS_DIST_MIN := 1500.0    # метров между переходами (мин)
const TRANS_DIST_MAX := 3500.0    # ... (макс)
var phase: int = Phase.NORMAL
var target_left_lanes: int = 0
var target_right_lanes: int = 0
var blocked_slot: int = NO_BLOCK  # закрывающийся край — в него не спавним
var next_transition_dist: float = 100.0   # первый переход — рано, удобно тестировать
var anim_left_from: float = 0.0
var anim_right_from: float = 0.0
var anim_time: float = 0.0

var distance_m: float = 0.0
var best_m: float = 0.0
var time_elapsed: float = 0.0
var game_over: bool = false
var world_speed_px: float = 0.0
var shake_strength: float = 0.0

var spawn_accum: float = 0.0
var next_wave_dist: float = 0.0
var spawn_queue: Array = []
var stagger_timer: float = 0.0

@onready var score_label: Label = $HUD/ScoreLabel
@onready var game_over_label: Label = $HUD/GameOverLabel

func _ready() -> void:
	road_left_px = CORE_LEFT - left_lanes * LANE_WIDTH
	road_right_px = CORE_RIGHT + right_lanes * LANE_WIDTH
	load_best()
	update_hud()
	next_wave_dist = randf_range(SPAWN_DIST_MIN, SPAWN_DIST_MAX)

func _process(delta: float) -> void:
	if not game_over:
		world_speed_px = $Player.speed * PIXELS_PER_KMH   # мир едет со скоростью мотоцикла
		distance_m += $Player.speed / 3.6 * delta          # км/ч → м/с, копим метры
		time_elapsed += delta                              # секундомер идёт вперёд
		update_lanes(delta)
		handle_spawning(delta)   # спавним ВСЕГДА — центр не прекращает
		update_hud()
	# тряска при аварии
	if shake_strength > 0.0:
		shake_strength = max(0.0, shake_strength - 40.0 * delta)
		$Camera2D.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
	else:
		$Camera2D.offset = Vector2.ZERO

# --- переходы: полоса появляется/исчезает С КРАЯ; центр живёт всегда ---
func update_lanes(delta: float) -> void:
	match phase:
		Phase.NORMAL:
			if distance_m >= next_transition_dist:
				start_transition()
		Phase.WAIT_EDGE_CLEAR:
			if slot_is_empty(blocked_slot):   # закрывающийся край опустел
				begin_animation()
		Phase.ANIMATING:
			anim_time += delta
			var t = clamp(anim_time / TRANSITION_DURATION, 0.0, 1.0)
			var e = smoothstep(0.0, 1.0, t)
			road_left_px = lerp(anim_left_from, CORE_LEFT - target_left_lanes * LANE_WIDTH, e)
			road_right_px = lerp(anim_right_from, CORE_RIGHT + target_right_lanes * LANE_WIDTH, e)
			if t >= 1.0:
				left_lanes = target_left_lanes
				right_lanes = target_right_lanes
				road_left_px = CORE_LEFT - left_lanes * LANE_WIDTH
				road_right_px = CORE_RIGHT + right_lanes * LANE_WIDTH
				blocked_slot = NO_BLOCK
				next_transition_dist = distance_m + randf_range(TRANS_DIST_MIN, TRANS_DIST_MAX)
				phase = Phase.NORMAL

func start_transition() -> void:
	target_left_lanes = left_lanes
	target_right_lanes = right_lanes
	blocked_slot = NO_BLOCK
	spawn_queue.clear()   # сбросить очередь (вдруг там старый край)
	var total := total_lanes()
	var add: bool
	if total <= 2:
		add = true
	elif total >= 4:
		add = false
	else:
		add = randf() < 0.5
	if add:
		if left_lanes == 0 and right_lanes == 0:
			if randf() < 0.5: target_left_lanes = 1
			else: target_right_lanes = 1
		elif left_lanes == 0:
			target_left_lanes = 1
		else:
			target_right_lanes = 1
		begin_animation()   # добавление — сразу анимируем, центр спавнит дальше
	else:
		if left_lanes == 1 and right_lanes == 1:
			if randf() < 0.5: target_left_lanes = 0
			else: target_right_lanes = 0
		elif left_lanes == 1:
			target_left_lanes = 0
		else:
			target_right_lanes = 0
		blocked_slot = -1 if target_left_lanes < left_lanes else 2  # какой край закрываем
		phase = Phase.WAIT_EDGE_CLEAR

func begin_animation() -> void:
	anim_left_from = road_left_px
	anim_right_from = road_right_px
	anim_time = 0.0
	phase = Phase.ANIMATING

func total_lanes() -> int:
	return CORE_LANES + left_lanes + right_lanes

# активные слоты: центр всегда, плюс края если есть
func active_slots() -> Array:
	var slots := [0, 1]
	if left_lanes >= 1: slots.append(-1)
	if right_lanes >= 1: slots.append(2)
	return slots

func slot_is_empty(slot: int) -> bool:
	for v in get_tree().get_nodes_in_group("items"):
		if v.lane == slot:
			return false
	return true

# --- спавн транспорта ---
func handle_spawning(delta: float) -> void:
	spawn_accum += world_speed_px * delta
	if spawn_accum >= next_wave_dist:
		spawn_accum = 0.0
		next_wave_dist = randf_range(SPAWN_DIST_MIN, SPAWN_DIST_MAX)
		queue_wave()
	stagger_timer -= delta
	if not spawn_queue.is_empty() and stagger_timer <= 0.0:
		spawn_vehicle(spawn_queue.pop_front())
		stagger_timer = randf_range(STAGGER_MIN, STAGGER_MAX)

func queue_wave() -> void:
	var slots := active_slots()
	slots.erase(blocked_slot)   # в закрывающийся край не спавним
	var count = 2 if randf() < 0.7 else 1
	count = min(count, slots.size() - 1)   # хотя бы одна полоса свободна
	slots.shuffle()
	for i in range(count):
		spawn_queue.append(slots[i])

func spawn_vehicle(slot: int) -> void:
	if slot == blocked_slot or vehicle_scenes.is_empty() or not lane_top_clear(slot):
		return
	var item = vehicle_scenes.pick_random().instantiate()
	item.lane = slot
	var x = lane_center(slot) + randf_range(-LANE_OFFSET, LANE_OFFSET)
	item.position = Vector2(x, -50.0)
	add_child(item)

func lane_top_clear(slot: int) -> bool:
	for v in get_tree().get_nodes_in_group("items"):
		if v.lane == slot and v.position.y < SPAWN_GAP - 50.0:
			return false
	return true

# --- геометрия: края анимируются, центры/разметка от слотов (центр не дрожит) ---
func road_left() -> float:
	return road_left_px

func road_right() -> float:
	return road_right_px

# центр слота: 0→280, 1→440, -1→120, 2→600
func lane_center(slot: int) -> float:
	return CORE_LEFT + LANE_WIDTH * (slot + 0.5)

func lane_divider_xs() -> Array:
	var xs := [CORE_LEFT + LANE_WIDTH]            # 360 — центральная (всегда)
	if left_lanes >= 1: xs.append(CORE_LEFT)      # 200 — между слотами -1 и 0
	if right_lanes >= 1: xs.append(CORE_LEFT + 2.0 * LANE_WIDTH)  # 520 — между 1 и 2
	return xs

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
