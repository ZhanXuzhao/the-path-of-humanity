# 主菜单 - Main Menu
# 支持主菜单和游戏中暂停菜单两种模式
extends Control

@onready var resume_btn: Button = $MenuButtons/ResumeBtn
@onready var start_btn: Button = $MenuButtons/StartBtn
@onready var load_btn: Button = $MenuButtons/LoadBtn
@onready var quit_btn: Button = $MenuButtons/QuitBtn

var _gm

func _ready():
	_gm = get_node("/root/GameManager")
	resume_btn.pressed.connect(_on_resume_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	_update_menu_mode()

func _update_menu_mode():
	"""根据游戏状态切换菜单模式"""
	if _gm.state == _gm.GameState.MENU:
		# 主菜单模式
		mouse_filter = MOUSE_FILTER_IGNORE
		resume_btn.visible = false
		start_btn.text = "开始游戏"
		load_btn.text = "读取存档"
		quit_btn.text = "退出游戏"
	else:
		# 游戏中暂停菜单模式
		mouse_filter = MOUSE_FILTER_STOP
		resume_btn.visible = true
		start_btn.text = "保存游戏"
		load_btn.text = "读取存档"
		quit_btn.text = "返回主菜单"
		# 暂停时关闭其他面板
		var build_menu = get_node_or_null("/root/Game/UI/BuildMenu")
		if build_menu:
			build_menu.visible = false
		var tech_panel = get_node_or_null("/root/Game/UI/TechPanel")
		if tech_panel:
			tech_panel.visible = false

func _on_resume_pressed():
	"""返回游戏"""
	_gm.resume_game()
	visible = false

func _on_start_pressed():
	if _gm.state == _gm.GameState.MENU:
		# 主菜单：开始游戏
		_gm.start_game()
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	else:
		# 游戏中：保存游戏
		_save_game()

func _on_load_pressed():
	_load_game()

func _on_quit_pressed():
	if _gm.state == _gm.GameState.MENU:
		# 主菜单：退出游戏
		get_tree().quit()
	else:
		# 游戏中：返回主菜单
		_gm.state = _gm.GameState.MENU
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ==================== 存档管理 ====================

func _save_game():
	var save_data = {
		"version": 1,
		"game_time": _gm.game_time,
		"current_day": _gm.current_day,
		"time_speed": _gm.time_speed,
		"resources": _gm.resources.duplicate(),
		"stats": _gm.stats.duplicate(),
	}
	var file = FileAccess.open("user://savegame.dat", FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		_gm.show_notification("游戏已保存", _gm.NotificationType.SUCCESS)
	else:
		_gm.show_notification("保存失败！", _gm.NotificationType.ERROR)

func _load_game():
	var file = FileAccess.open("user://savegame.dat", FileAccess.READ)
	if file:
		var data = file.get_var()
		if typeof(data) != TYPE_DICTIONARY:
			_gm.show_notification("存档数据损坏", _gm.NotificationType.ERROR)
			return
		_gm.game_time = data.get("game_time", 6.0)
		_gm.current_day = data.get("current_day", 1)
		_gm.time_speed = data.get("time_speed", 1.0)
		_gm.resources = data.get("resources", {})
		_gm.stats = data.get("stats", {})
		_gm.state = _gm.GameState.PLAYING
		_gm.show_notification("存档已读取", _gm.NotificationType.SUCCESS)
		# 如果当前不在游戏中，跳转到游戏场景
		if get_tree().current_scene.scene_file_path != "res://scenes/game.tscn":
			get_tree().change_scene_to_file("res://scenes/game.tscn")
	else:
		_gm.show_notification("未找到存档", _gm.NotificationType.ERROR)
