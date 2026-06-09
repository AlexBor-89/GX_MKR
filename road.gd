extends Node2D

# Процедурная дорога: трава + асфальт (3 полосы) + бегущая разметка.
# Геометрию полос берём у Main (родителя) — единый источник правды.

const GRASS := Color(0.22, 0.45, 0.2)
const ASPHALT := Color(0.18, 0.18, 0.2)
const DASH_LEFT := Color(1, 0.85, 0.2)
const DASH_RIGHT := Color(1, 0.85, 0.2)
const DASH_COLOR := Color.WHITE
const EDGE_WIDTH := 8.0
const DASH_WIDTH := 10.0
const DASH_HEIGHT := 70.0
const DASH_GAP := 55.0

var scroll: float = 0.0

func _process(delta: float) -> void:
	scroll += get_parent().world_speed_px * delta
	queue_redraw()

func _draw() -> void:
	var w := get_viewport_rect().size.x
	var h := get_viewport_rect().size.y
	var left = get_parent().road_left()
	var right = get_parent().road_right()
	# трава во весь экран
	draw_rect(Rect2(0, 0, w, h), GRASS)
	# асфальт по центру
	draw_rect(Rect2(left, 0, right - left, h), ASPHALT)
	# сплошные белые края дороги
	draw_rect(Rect2(left, 0, EDGE_WIDTH, h), DASH_LEFT)
	draw_rect(Rect2(right - EDGE_WIDTH, 0, EDGE_WIDTH, h), DASH_RIGHT)
	# бегущие пунктирные разделители между полосами
	var step := DASH_HEIGHT + DASH_GAP
	var start_y := fmod(scroll, step) - step
	for x in get_parent().lane_divider_xs():
		var y := start_y
		while y < h:
			draw_rect(Rect2(x - DASH_WIDTH / 2.0, y, DASH_WIDTH, DASH_HEIGHT), DASH_COLOR)
			y += step
