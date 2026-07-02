extends Node2D

var center: Vector2
var radius: float
var fill_color := Color(0.3, 0.8, 1.0, 0.06)
var border_color := Color(0.3, 0.8, 1.0, 0.5)

func _draw():
	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0, TAU, 64, border_color, 2.0)
