# 通知组件 - Notification
extends Control

@onready var label: Label = $Label

# NotificationType enum values: INFO=0, WARNING=1, ERROR=2, SUCCESS=3, RESEARCH=4, COMBAT=5
var type_colors = {
	0: Color(0.5, 0.8, 1.0),      # INFO - 蓝色
	1: Color(1.0, 0.8, 0.2),      # WARNING - 黄色
	2: Color(1.0, 0.3, 0.3),      # ERROR - 红色
	3: Color(0.3, 1.0, 0.3),      # SUCCESS - 绿色
	4: Color(0.8, 0.5, 1.0),      # RESEARCH - 紫色
	5: Color(1.0, 0.3, 0.3),      # COMBAT - 红色
}

func show_notification(msg: String, type: int):
	label.text = msg
	var color = type_colors.get(type, Color.WHITE)
	label.add_theme_color_override("font_color", color)
	modulate = Color(1, 1, 1, 0)
	
	# 淡入淡出动画
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(queue_free)
