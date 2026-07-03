extends Node2D

var center: Vector2
var tile_size: float = 32.0

func _draw():
	var r = tile_size * 0.4
	draw_circle(center, r, Color(0.3, 0.8, 1.0, 0.15))
	draw_arc(center, r, 0, TAU, 32, Color(0.3, 0.8, 1.0, 0.9), 2.0)
