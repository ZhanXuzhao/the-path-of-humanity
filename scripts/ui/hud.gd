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

# 资源对应的 Emoji 图标
const RESOURCE_EMOJI = {
	"wood": "🪵",
	"stone": "🪨",
	"food": "🍖",
	"iron_ore": "⛏️",
	"copper_ore": "🪙",
	"coal": "⬛",
}

func _ready():
	game_manager = get_node("/root/GameManager")
	
	# 连接信号
	game_manager.time_changed.connect(_on_time_changed)
	game_manager.day_changed.connect(_on_day_changed)
	game_manager.notification.connect(_on_notification)
	game_manager.resources_changed.connect(_on_resources_changed)
	
	# 按钮连接
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_pressed)
	if speed_btn:
		speed_btn.pressed.connect(_on_speed_pressed)
	if build_menu_btn:
		build_menu_btn.pressed.connect(_on_build_menu_pressed)
	if tech_btn:
		tech_btn.pressed.connect(_on_tech_pressed)
	
	# 延迟一帧初始化资源显示（等待 GameManager 完全就绪）
	call_deferred("_update_resource_display")

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

func _on_resources_changed(resource_id: String, _old_amount: int, new_amount: int):
	"""单个资源变化时更新对应标签"""
	var emoji = RESOURCE_EMOJI.get(resource_id, "")
	for child in resource_container.get_children():
		if child.name == resource_id:
			var item_def = ItemDefinitions.get_item(resource_id)
			var name_str = item_def.name if item_def else resource_id
			child.text = "%s %s: %d" % [emoji, name_str, new_amount]
			return

func _update_resource_display():
	"""初始化或刷新所有资源标签"""
	if not game_manager or resource_container == null:
		return
	
	for res_id in tracked_resources:
		var amount = game_manager.resources.get(res_id, 0)
		var emoji = RESOURCE_EMOJI.get(res_id, "")
		
		# 查找是否已有对应标签
		var existing = null
		for child in resource_container.get_children():
			if child.name == res_id:
				existing = child
				break
		
		if existing:
			var item_def = ItemDefinitions.get_item(res_id)
			var name_str = item_def.name if item_def else res_id
			existing.text = "%s %s: %d" % [emoji, name_str, amount]
		else:
			var label = Label.new()
			label.name = res_id
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_constant_override("minimum_font_size", 14)
			var item_def = ItemDefinitions.get_item(res_id)
			var name_str = item_def.name if item_def else res_id
			label.text = "%s %s: %d" % [emoji, name_str, amount]
			resource_container.add_child(label)

func update_resource(resource_id: String, amount: int):
	"""更新单个资源显示（外部调用，兼容旧接口）"""
	_on_resources_changed(resource_id, 0, amount)
