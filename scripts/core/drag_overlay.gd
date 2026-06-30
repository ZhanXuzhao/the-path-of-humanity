# 框选覆盖层 - Drag Overlay
# 独立的高 z_index Node2D，专门绘制标记模式的拖选框
extends Node2D

var drag_rect_pos: Vector2 = Vector2.ZERO
var drag_rect_size: Vector2 = Vector2.ZERO

func _draw():
	if drag_rect_size.x <= 0 or drag_rect_size.y <= 0:
		return
	
	var rect = Rect2(drag_rect_pos, drag_rect_size)
	# 半透明绿色填充
	draw_rect(rect, Color(0.3, 1.0, 0.3, 0.12), true)
	# 绿色边框
	draw_rect(rect, Color(0.3, 1.0, 0.3, 0.85), false, 2.0)
