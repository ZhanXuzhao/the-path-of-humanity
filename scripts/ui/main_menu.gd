# 主菜单 - Main Menu
extends Control

@onready var start_btn: Button = $MenuButtons/StartBtn
@onready var load_btn: Button = $MenuButtons/LoadBtn
@onready var quit_btn: Button = $MenuButtons/QuitBtn

func _ready():
	start_btn.pressed.connect(_on_start_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	get_node("/root/GameManager").start_game()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_load_pressed():
	# TODO: 实现加载存档
	get_node("/root/GameManager").show_notification("存档功能开发中", 1)

func _on_quit_pressed():
	get_tree().quit()
