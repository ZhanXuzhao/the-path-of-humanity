# 主HUD - Main HUD
# 显示时间、资源、人口等基本信息
extends CanvasLayer
class_name HUD

const ItemDefinitions = preload("res://resources/item_definitions.gd")

@onready var time_label: Label = $TopBar/TimeLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var population_label: Label = $TopBar/PopulationLabel
@onready var resource_container: HBoxContainer = $TopBar/Resources
@onready var notification_container: VBoxContainer = $Notifications
@onready var speed_btn: Button = $BottomBar/SpeedBtn
@onready var pause_btn: Button = $BottomBar/PauseBtn
@onready var build_menu_btn: Button = $BottomBar/BuildBtn
@onready var tech_btn: Button = $BottomBar/TechBtn
@onready var menu_btn: Button = $BottomBar/MenuBtn

var game_manager
var notification_scene = load("res://scenes/ui/notification.tscn")

# 要显示的资源列表
var tracked_resources = ["wood", "stone", "food", "iron_ore", "copper_ore", "coal"]

func _ready():
	game_manager = get_node("/root/GameManager")
	
	# 连接信号
	game_manager.time_changed.connect(_on_time_changed)
	game_manager.day_changed.connect(_on_day_changed)
	game_manager.notification.connect(_on_notification)
	
	# 按钮连接
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_pressed)
	if speed_btn:
		speed_btn.pressed.connect(_on_speed_pressed)
	if build_menu_btn:
		build_menu_btn.pressed.connect(_on_build_menu_pressed)
	if tech_btn:
		tech_btn.pressed.connect(_on_tech_pressed)
	
	_update_resource_display()

func _on_time_changed(_hour: float):
	if time_label:
		time_label.text = game_manager.get_time_string()

func _on_day_changed(day: int):
	if day_label:
		day_label.text = "第 %d 天" % day

func _on_pause_pressed():
	game_manager.toggle_pause()
	if pause_btn:
		pause_btn.text = "▶" if game_manager.state == 2 else "⏸"

func _on_speed_pressed():
	var speeds = [1.0, 2.0, 3.0, 5.0]
	var current = game_manager.time_speed
	var idx = speeds.find(current)
	idx = (idx + 1) % speeds.size()
	game_manager.set_time_speed(speeds[idx])
	if speed_btn:
		speed_btn.text = "×%d" % speeds[idx]

func _on_build_menu_pressed():
	# 发送打开建筑菜单的信号
	var build_menu = get_node_or_null("/root/Game/UI/BuildMenu")
	if build_menu:
		build_menu.visible = not build_menu.visible

func _on_tech_pressed():
	var tech_panel = get_node_or_null("/root/Game/UI/TechPanel")
	if tech_panel:
		tech_panel.visible = not tech_panel.visible

func _on_notification(msg: String, type: int):
	var notif = notification_scene.instantiate()
	notification_container.add_child(notif)
	notif.show_notification(msg, type)
	# 自动移除
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(notif):
		notif.queue_free()

func _update_resource_display():
	# 这个方法会被外部调用来更新资源显示
	pass

func update_resource(resource_id: String, amount: int):
	"""更新单个资源显示"""
	for child in resource_container.get_children():
		if child.name == resource_id:
			child.text = "%s: %d" % [ItemDefinitions.get_item(resource_id).name, amount]
			return
	
	# 如果没有找到，创建一个
	var label = Label.new()
	label.name = resource_id
	label.add_theme_color_override("font_color", Color.WHITE)
	label.text = "%s: %d" % [ItemDefinitions.get_item(resource_id).name, amount]
	resource_container.add_child(label)
