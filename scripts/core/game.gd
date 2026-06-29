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

func _process(delta):
	# 建造模式预览
	if build_mode:
		_update_build_preview()
	
	# 只有游戏进行中才执行AI和系统更新
	if _gm.state != 1:
		return
	
	# 驱动各系统更新
	if building_system:
		building_system.process_buildings(delta)
	if crafting_system:
		crafting_system.process_crafting(delta)
	if tech_system:
		tech_system.process_research(delta)
	
	# 更新定居者需求和AI
	_update_settlers(delta)
	
	# 分配任务给空闲定居者
	_assign_ai_tasks()

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

# ==================== 定居者AI系统 ====================

func _update_settlers(delta):
	"""更新所有定居者的需求和基本状态"""
	var delta_hours = _gm.time_speed * delta * (24.0 / _gm.day_length)
	for s in settlers:
		if is_instance_valid(s):
			s.update_needs(delta_hours)

func _assign_ai_tasks():
	"""为所有空闲定居者分配任务（优先级：建造 > 制作 > 采集）"""
	var idle_settlers = get_idle_settlers()
	if idle_settlers.is_empty():
		return
	
	# 收集所有可用任务
	var tasks = []
	
	# 1. 建造任务（优先级最高）
	var uncompleted = building_system.get_uncompleted_buildings() if building_system else []
	for bld in uncompleted:
		var data = bld.get_data()
		var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		tasks.append({
			"id": "construct_%d_%d" % [bld.grid_pos.x, bld.grid_pos.y],
			"type": "CONSTRUCT",
			"target_pos": bld.grid_pos,
			"target_world_pos": center_pixel,
			"skill": "construction",
			"work_required": data.work_cost - bld.construction_progress if data else 10.0,
			"priority": 3,
		})
	
	# 2. 制作任务（中等优先级）
	if crafting_system:
		var pending_jobs = crafting_system.get_pending_crafting_jobs()
		for job in pending_jobs:
			var bld = building_system.get_building_at(job.building_pos) if building_system else null
			if bld == null:
				continue
			var data = bld.get_data()
			var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
			var recipe = job.get_recipe()
			tasks.append({
				"id": "craft_%d_%d_%s" % [job.building_pos.x, job.building_pos.y, job.recipe_id],
				"type": "CRAFT",
				"target_pos": job.building_pos,
				"target_world_pos": center_pixel,
				"building_pos": job.building_pos,
				"recipe_id": job.recipe_id,
				"skill": "crafting",
				"work_required": recipe.work_time if recipe else 5.0,
				"priority": 2,
				"crafting_job": job,
			})
	
	# 3. 采集任务（低优先级）- 在地图已生成区块中找最近的资源
	var harvest_tasks = _scan_nearby_resources(idle_settlers)
	tasks.append_array(harvest_tasks)
	
	if tasks.is_empty():
		return
	
	# 按优先级排序
	tasks.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
	
	# 为每个空闲定居者分配最近的最优任务
	for settler in idle_settlers:
		if tasks.is_empty():
			break
		
		# 找到距离定居者最近的高优先级任务
		var best_task = null
		var best_dist = INF
		var best_idx = -1
		
		for i in range(tasks.size()):
			var t = tasks[i]
			# 制作任务需要检查是否有其他定居者已经在做
			if t.get("type") == "CRAFT":
				var job = t.get("crafting_job")
				if job and job.assigned_settler_id != "":
					continue
			
			var task_pos = t.get("target_world_pos", Vector2.ZERO)
			var dist = settler.position.distance_squared_to(task_pos) if task_pos != Vector2.ZERO else 0
			# 优先级权重：同一优先级内选最近的
			var weighted_dist = dist / max(1, t.get("priority", 1))
			if weighted_dist < best_dist:
				best_dist = weighted_dist
				best_task = t
				best_idx = i
		
		if best_task == null:
			continue
		
		# 如果是制作任务，将定居者ID写入任务
		if best_task.get("type") == "CRAFT":
			var job = best_task.get("crafting_job")
			if job:
				job.assigned_settler_id = settler.settler_id
		
		tasks.remove_at(best_idx)
		settler.assign_task(best_task)

func _scan_nearby_resources(settlers: Array) -> Array:
	"""扫描定居者周围的可采集资源"""
	var result: Array = []
	var scanned_chunks: Dictionary = {}
	
	# 决定搜索范围：以所有空闲定居者位置为中心
	var search_radius = 5  # 区块半径
	if settlers.is_empty():
		return result
	
	var center_chunk = world.global_to_chunk(Vector2i(
		int(settlers[0].position.x / world.tile_size),
		int(settlers[0].position.y / world.tile_size)
	))
	
	for cx in range(center_chunk.x - search_radius, center_chunk.x + search_radius + 1):
		for cy in range(center_chunk.y - search_radius, center_chunk.y + search_radius + 1):
			var chunk_pos = Vector2i(cx, cy)
			if scanned_chunks.has(chunk_pos):
				continue
			scanned_chunks[chunk_pos] = true
			
			world.ensure_chunk_generated(chunk_pos)
			var chunk = world.get_chunk(chunk_pos)
			if not chunk.is_generated:
				continue
			
			for local_pos in chunk.resources:
				var dep = chunk.resources[local_pos]
				if dep.amount <= 0:
					continue
				
				var global_pos = chunk_pos * world.CHUNK_SIZE + local_pos
				var world_pos = _grid_to_world(global_pos)
				var item_id = dep.get_item_drop()
				
				# 根据资源类型映射技能
				var skill_map = {
					world.ResourceNodeType.TREE: "woodcutting",
					world.ResourceNodeType.STONE_DEPOSIT: "mining",
					world.ResourceNodeType.IRON_DEPOSIT: "mining",
					world.ResourceNodeType.COPPER_DEPOSIT: "mining",
					world.ResourceNodeType.COAL_DEPOSIT: "mining",
					world.ResourceNodeType.BERRY_BUSH: "woodcutting",
				}
				
				result.append({
					"id": "harvest_%d_%d" % [global_pos.x, global_pos.y],
					"type": "HARVEST",
					"target_pos": global_pos,
					"target_world_pos": world_pos,
					"resource_type": dep.type,
					"harvest_item": item_id,
					"skill": skill_map.get(dep.type, "woodcutting"),
					"work_required": dep.harvest_time,
					"priority": 1,
				})
	
	return result

func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""将网格坐标转换为世界像素坐标（格子中心）"""
	return Vector2(
		grid_pos.x * world.tile_size + world.tile_size / 2.0,
		grid_pos.y * world.tile_size + world.tile_size / 2.0
	)
