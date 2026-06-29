# 主菜单 / 暂停菜单 - Main Menu & Pause Menu
# 统一菜单，一级显示所有按钮，不分主菜单/暂停模式
extends Control

@onready var start_btn: Button = $MenuButtons/StartBtn
@onready var save_btn: Button = $MenuButtons/SaveBtn
@onready var load_btn: Button = $MenuButtons/LoadBtn
@onready var quit_btn: Button = $MenuButtons/QuitBtn

var _gm

func _ready():
	_gm = get_node("/root/GameManager")
	start_btn.pressed.connect(_on_start_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	# 统一阻止鼠标穿透（主菜单场景无下层，暂停菜单需阻断游戏交互）
	mouse_filter = MOUSE_FILTER_STOP
	
	_on_visibility_changed()

func _on_visibility_changed():
	if visible and _gm.state != _gm.GameState.MENU:
		# 暂停时关闭其他面板
		var build_menu = get_node_or_null("/root/Game/UI/BuildMenu")
		if build_menu:
			build_menu.visible = false
		var tech_panel = get_node_or_null("/root/Game/UI/TechPanel")
		if tech_panel:
			tech_panel.visible = false

func _on_start_pressed():
	# 无论主菜单还是暂停菜单，都新建游戏
	_gm.start_game()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_save_pressed():
	_save_game()

func _on_load_pressed():
	_load_game()

func _on_quit_pressed():
	# 游戏中先保存再退出
	if _gm.state != _gm.GameState.MENU:
		_save_game()
	get_tree().quit()

# ==================== 存档管理 ====================

func _save_game():
	_gm.save_game()

func _load_game():
	if _gm.load_game():
		if get_tree().current_scene.scene_file_path != "res://scenes/game.tscn":
			get_tree().change_scene_to_file("res://scenes/game.tscn")
