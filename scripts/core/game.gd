# 游戏主控制器 - Main Game Controller
# 管理游戏场景、系统协调、建造模式等
extends Node2D
class_name Game

const ItemDefinitions = preload("res://resources/item_definitions.gd")

@onready var world = $World
@onready var building_system = $Systems/BuildingSystem
@onready var crafting_system = $Systems/CraftingSystem
@onready var tech_system = $Systems/TechSystem
@onready var camera: Camera2D = $Camera
@onready var ui: CanvasLayer = $UI
@onready var _gm = get_node("/root/GameManager")

# 建造模式
var build_mode: bool = false
var selected_building: String = ""
var build_preview: Sprite2D = null
var mouse_grid_pos: Vector2i

# 定居者管理
var settlers = []

func _ready():
	# 启动游戏状态（支持跳过菜单直接加载）
	if _gm.state != 1:  # GameState.PLAYING
		_gm.start_game()
	
	# 初始化世界
	_generate_initial_area()
	
	# 创建初始定居者
	_spawn_initial_settlers()
	
	# 初始化系统引用
	if building_system:
		building_system.world = world

func _process(_delta):
	if build_mode:
		_update_build_preview()

func _generate_initial_area():
	# 确保出生点周围区块已生成
	var center_chunk = Vector2i(0, 0)
	for x in range(-1, 2):
		for y in range(-1, 2):
			world.ensure_chunk_generated(center_chunk + Vector2i(x, y))

func _spawn_initial_settlers():
	# 创建3个初始定居者
	for i in 3:
		var settler = Settler.new()
		settler.position = Vector2(randf_range(300, 500), randf_range(300, 500))
		add_child(settler)
		settlers.append(settler)
		_gm.show_notification("新成员加入了聚居地: %s" % settler.settler_name, 
			3)

# -------- 建造模式 --------
func enter_build_mode(building_id: String):
	build_mode = true
	selected_building = building_id
	
	# 创建预览精灵
	if build_preview == null:
		build_preview = Sprite2D.new()
		add_child(build_preview)
	
	build_preview.visible = true
	build_preview.modulate = Color(1, 1, 1, 0.5)
	# TODO: 设置预览纹理

func exit_build_mode():
	build_mode = false
	selected_building = ""
	if build_preview:
		build_preview.visible = false

func _update_build_preview():
	# 更新预览位置
	var mouse_pos = get_global_mouse_position()
	mouse_grid_pos = Vector2i(
		floori(mouse_pos.x / world.tile_size),
		floori(mouse_pos.y / world.tile_size)
	)
	
	if build_preview:
		build_preview.position = mouse_grid_pos * world.tile_size
	
	# 检查是否可以放置
	if Input.is_action_just_pressed("left_click"):
		_try_place_building()

func _try_place_building():
	if not build_mode or selected_building == "":
		return
	
	var check = building_system.can_place_building(selected_building, mouse_grid_pos)
	if check.can_place:
		building_system.place_building(selected_building, mouse_grid_pos)
		_gm.show_notification("开始建造: " + ItemDefinitions.get_building(selected_building).name,
			3)
	else:
		_gm.show_notification("无法建造: " + check.reason,
			1)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if build_mode:
			exit_build_mode()
	
	if event.is_action_pressed("left_click") and build_mode:
		_try_place_building()

# -------- 定居者管理 --------
func get_idle_settlers() -> Array:
	var idle: Array[Settler] = []
	for s in settlers:
		if s.state == Settler.SettlerState.IDLE:
			idle.append(s)
	return idle

func get_settler_by_id(id: String):
	for s in settlers:
		if s.settler_id == id:
			return s
	return null
