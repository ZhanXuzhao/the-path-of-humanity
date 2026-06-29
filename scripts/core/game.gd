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
@onready var world_renderer = $World/WorldRenderer
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
		build_preview.z_index = 100  # 确保预览始终在最上层
		add_child(build_preview)
	
	# 设置建筑预览纹理
	if world_renderer and world_renderer.building_textures.has(building_id):
		build_preview.texture = world_renderer.building_textures[building_id]
	else:
		build_preview.texture = null
	
	build_preview.visible = true
	
	# 根据建筑大小设置缩放
	var data = ItemDefinitions.get_building(building_id)
	if data:
		build_preview.scale = Vector2(world.tile_size / 32.0, world.tile_size / 32.0)
	
	# 默认绿色（可建造）
	build_preview.modulate = Color(0, 1, 0, 0.5)

func exit_build_mode():
	build_mode = false
	selected_building = ""
	if build_preview:
		build_preview.visible = false

func _update_build_preview():
	var mouse_pos = get_global_mouse_position()
	mouse_grid_pos = Vector2i(
		floori(mouse_pos.x / world.tile_size),
		floori(mouse_pos.y / world.tile_size)
	)
	
	if build_preview and build_mode:
		var data = ItemDefinitions.get_building(selected_building)
		if data:
			var size = data.size
			# 将预览精灵居中于建筑占用的区域
			var center = Vector2(
				mouse_grid_pos.x * world.tile_size + size.x * world.tile_size / 2.0,
				mouse_grid_pos.y * world.tile_size + size.y * world.tile_size / 2.0
			)
			build_preview.position = center
		
		# 检查建造合法性并设置颜色
		var check = building_system.can_place_building(selected_building, mouse_grid_pos)
		if check.can_place:
			build_preview.modulate = Color(0, 1, 0, 0.5)  # 绿色-可建造
		else:
			build_preview.modulate = Color(1, 0, 0, 0.5)  # 红色-不可建造

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
