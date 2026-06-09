extends Node2D

# Бесконечный поток сцен-чанков с декором (трава, столбы, забор, отбойники).
# Держим стопку из CHUNK_COUNT чанков; ушедший за нижний край — переносим наверх.

@export var chunk_scene: PackedScene
const CHUNK_HEIGHT := 640.0   # высота одного чанка в пикселях
const CHUNK_COUNT := 3        # хватает покрыть экран 1280 + запас

var chunks: Array = []

func _ready() -> void:
	if chunk_scene == null:
		return
	for i in range(CHUNK_COUNT):
		var c = chunk_scene.instantiate()
		c.position.y = (i - 1) * CHUNK_HEIGHT   # один над экраном, остальные ниже
		add_child(c)
		chunks.append(c)

func _process(delta: float) -> void:
	var move = get_parent().world_speed_px * delta   # двигаемся со скоростью мира
	var loop = CHUNK_HEIGHT * CHUNK_COUNT
	for c in chunks:
		c.position.y += move
		if c.position.y >= get_viewport_rect().size.y:
			c.position.y -= loop   # уехал вниз — наверх, в начало стопки
