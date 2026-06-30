# 指令面板 - Command Panel
# 提供采矿、伐木、农业、搬运指令按钮
# 点击后进入标记模式，玩家可框选/点选对应类型的资源
extends Panel
class_name CommandPanel

const WorkManager = preload("res://scripts/autoload/work_manager.gd")

# 自动模式特殊值
const AUTO_WORK_TYPE := -2

# 指令按钮配置（使用 Dictionary 代替 struct）
var commands: Array[Dictionary] = [
	{"name": "采集", "work_type": AUTO_WORK_TYPE, "icon": "🧺", "desc": "自动标记采矿/伐木/农业/搬运目标"},
	{"name": "采矿", "work_type": WorkManager.WorkType.MINING, "icon": "⛏️", "desc": "标记矿石资源（铁矿、铜矿、煤矿、石矿）"},
	{"name": "伐木", "work_type": WorkManager.WorkType.WOODCUTTING, "icon": "🪓", "desc": "标记树木资源"},
	{"name": "农业", "work_type": WorkManager.WorkType.FARMING, "icon": "🌾", "desc": "标记浆果丛资源"},
	{"name": "搬运", "work_type": WorkManager.WorkType.HAULING, "icon": "📦", "desc": "标记地面物品为搬运目标"},
]

@onready var button_container: VBoxContainer = $MarginContainer/VBox/ButtonContainer
@onready var title_label: Label = $MarginContainer/VBox/TitleLabel

var _buttons: Dictionary = {}  # work_type -> Button
var _clear_btn: Button = null
var _game = null

const CLEAR_WORK_TYPE := -1

func _ready():
	_game = get_node("/root/Game")
	title_label.text = "指令面板"
	
	# 创建指令按钮
	for cmd in commands:
		_create_cmd_button(cmd.icon, cmd.name, cmd.work_type, cmd.desc)
	
	# 创建取消按钮（风格统一）
	_create_cmd_button("❌", "取消", CLEAR_WORK_TYPE, "框选或点选清除已标记的资源")
	
	# 连接游戏信号
	if _game:
		_game.designation_mode_changed.connect(_on_designation_mode_changed)
		_game.clear_mode_changed.connect(_on_clear_mode_changed)
	
	visible = true

func _create_cmd_button(icon: String, name: String, work_type: int, desc: String):
	"""统一创建标记/取消按钮"""
	var btn = Button.new()
	btn.text = "%s %s" % [icon, name]
	btn.tooltip_text = desc
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(100, 36)
	
	if work_type == CLEAR_WORK_TYPE:
		_clear_btn = btn
		btn.pressed.connect(_on_clear_pressed)
	else:
		btn.pressed.connect(_on_command_button_pressed.bind(work_type, btn))
		_buttons[work_type] = btn
	
	button_container.add_child(btn)

func _on_command_button_pressed(work_type: int, btn: Button):
	if not _game:
		return
	
	if _game.designation_mode and _game.designation_work_type == work_type:
		_game.exit_designation_mode()
		btn.button_pressed = false
	else:
		for wt in _buttons:
			if wt != work_type:
				_buttons[wt].button_pressed = false
		if _clear_btn:
			_clear_btn.button_pressed = false
		if _game.clear_mode:
			_game.exit_clear_mode()
		_game.enter_designation_mode(work_type)
		btn.button_pressed = true

func _on_clear_pressed():
	"""进入/退出清除模式"""
	if not _game or not _clear_btn:
		return
	
	if _game.clear_mode:
		_game.exit_clear_mode()
		_clear_btn.button_pressed = false
	else:
		for wt in _buttons:
			_buttons[wt].button_pressed = false
		if _game.designation_mode:
			_game.exit_designation_mode()
		_game.enter_clear_mode()
		_clear_btn.button_pressed = true

func _on_designation_mode_changed(active: bool, work_type: int):
	"""当外部退出标记模式时，同步按钮状态"""
	if not active:
		for wt in _buttons:
			_buttons[wt].button_pressed = false
	else:
		for wt in _buttons:
			_buttons[wt].button_pressed = (wt == work_type)
		if _clear_btn:
			_clear_btn.button_pressed = false
	
	if _clear_btn and not active:
		_clear_btn.button_pressed = false

func _on_clear_mode_changed(active: bool):
	"""清除模式状态变化时更新UI"""
	if _clear_btn:
		_clear_btn.button_pressed = active
	if active:
		for wt in _buttons:
			_buttons[wt].button_pressed = false
