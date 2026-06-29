# 通知组件 - Notification
extends Control

@onready var label: Label = $Label
@onready var animation: AnimationPlayer = $AnimationPlayer

var type_colors = {
	GameManager.NotificationType.INFO: Color(0.5, 0.8, 1.0),      # 蓝色
	GameManager.NotificationType.WARNING: Color(1.0, 0.8, 0.2),   # 黄色
	GameManager.NotificationType.ERROR: Color(1.0, 0.3, 0.3),     # 红色
	GameManager.NotificationType.SUCCESS: Color(0.3, 1.0, 0.3),   # 绿色
	GameManager.NotificationType.RESEARCH: Color(0.8, 0.5, 1.0),  # 紫色
	GameManager.NotificationType.COMBAT: Color(1.0, 0.3, 0.3),    # 红色
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
