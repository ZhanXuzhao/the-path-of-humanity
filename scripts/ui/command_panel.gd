# 指令面板 - Command Panel
# 提供采矿、伐木、农业、搬运指令按钮
# 点击后进入标记模式，玩家可框选/点选对应类型的资源
extends Panel
class_name CommandPanel

const WorkManager = preload("res://scripts/autoload/work_manager.gd")

# 指令按钮配置（使用 Dictionary 代替 struct）
var commands: Array[Dictionary] = [
	{"name": "采矿", "work_type": WorkManager.WorkType.MINING, "icon": "⛏️", "desc": "标记矿石资源（铁矿、铜矿、煤矿、石矿）"},
	{"name": "伐木", "work_type": WorkManager.WorkType.WOODCUTTING, "icon": "🪓", "desc": "标记树木资源"},
	{"name": "农业", "work_type": WorkManager.WorkType.FARMING, "icon": "🌾", "desc": "标记浆果丛资源"},
	{"name": "搬运", "work_type": WorkManager.WorkType.HAULING, "icon": "📦", "desc": "标记地面物品为搬运目标"},
]

@onready var button_container: VBoxContainer = $MarginContainer/VBox/ButtonContainer
@onready var clear_btn: Button = $MarginContainer/VBox/ClearBtn
@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel

var _buttons: Dictionary = {}  # work_type -> Button
var _game = null

func _ready():
	_game = get_node("/root/Game")
	title_label.text = "指令面板"
	hint_label.text = "点击按钮后，在地图上\n点击或拖拽框选资源"
	
	# 创建指令按钮
	for cmd in commands:
		var btn = Button.new()
		btn.text = "%s %s" % [cmd.icon, cmd.name]
		btn.tooltip_text = cmd.desc
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(100, 36)
		btn.pressed.connect(_on_command_button_pressed.bind(cmd.work_type, btn))
		button_container.add_child(btn)
		_buttons[cmd.work_type] = btn
	
	# 清除标记按钮
	clear_btn.pressed.connect(_on_clear_pressed)
	
	# 连接游戏信号
	if _game:
		_game.designation_mode_changed.connect(_on_designation_mode_changed)
	
	visible = true

func _on_command_button_pressed(work_type: int, btn: Button):
	if not _game:
		return
	
	if _game.designation_mode and _game.designation_work_type == work_type:
		# 已选中此按钮 → 退出标记模式
		_game.exit_designation_mode()
		btn.button_pressed = false
	else:
		# 取消其他按钮的选中状态
		for wt in _buttons:
			if wt != work_type:
				_buttons[wt].button_pressed = false
		# 进入标记模式
		_game.enter_designation_mode(work_type)
		btn.button_pressed = true

func _on_clear_pressed():
	"""清除所有指定类型的标记"""
	if not _game:
		return
	
	# 退出标记模式
	_game.exit_designation_mode()
	for wt in _buttons:
		_buttons[wt].button_pressed = false
	
	# 清除所有标记
	_game.clear_all_designations()

func _on_designation_mode_changed(active: bool, work_type: int):
	"""当外部（如按Esc）退出标记模式时，同步按钮状态"""
	if not active:
		for wt in _buttons:
			_buttons[wt].button_pressed = false
		hint_label.text = "点击按钮后，在地图上\n点击或拖拽框选资源"
	else:
		for wt in _buttons:
			_buttons[wt].button_pressed = (wt == work_type)
		var cmd_name = ""
		for cmd in commands:
			if cmd.work_type == work_type:
				cmd_name = cmd.name
				break
		hint_label.text = "在地图上点击或拖拽\n框选%s资源" % cmd_name
