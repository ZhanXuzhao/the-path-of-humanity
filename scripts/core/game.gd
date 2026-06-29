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

# 选中定居者
var selected_settler = null
signal settler_selected(settler)
signal settler_deselected()

# 选中建筑（置物架等）
var selected_building_instance = null
signal building_selected(building_instance)
signal building_deselected()

# 选中在建建筑（施工进度）
var selected_construction_building = null
signal construction_selected(building_instance)
signal construction_deselected()

# 选中资源节点
var selected_resource_pos: Vector2i = Vector2i(-1, -1)
var selected_resource_deposit = null  # World.ResourceDeposit
signal resource_selected(pos: Vector2i, deposit)
signal resource_deselected()

# 建筑建造重试冷却（防止反复给同一缺物资建筑分配任务）
var _construction_retry_cooldown: Dictionary = {}  # "x,y" -> frame_number

# 自主行为计时器（每2秒执行一次）
var _autonomy_timer: float = 0.0

func _ready():
	# 自动加载存档（静默读取，不弹通知）
	if _gm.state != 1 and _gm._loaded_save_data.is_empty() and _gm.has_save_file():
		_gm.load_game(true)
	
	# 启动游戏状态
	if _gm.state != 1:  # GameState.PLAYING
		_gm.start_game()
	
	# 检查是否有读档数据
	var is_loading = not _gm._loaded_save_data.is_empty()
	
	if is_loading:
		# 从存档恢复 - 不生成初始区域和定居者
		_restore_from_save(_gm._loaded_save_data)
		_gm._loaded_save_data.clear()
	else:
		# 新游戏 - 初始化世界和定居者
		_generate_initial_area()
		_spawn_initial_settlers()
	
	# 初始化系统引用
	if building_system:
		building_system.world = world
		building_system.building_completed.connect(_on_building_completed)

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
	
	# 检查选中的定居者是否还存活
	if selected_settler != null and not is_instance_valid(selected_settler):
		_deselect_settler()
	
	# 检查选中的资源节点是否还存在（可能已被采集完）
	if selected_resource_pos.x >= 0:
		var res = world.get_resource_at(selected_resource_pos)
		if res == null or res.amount <= 0:
			_deselect_resource()
	
	# 定居者自主行为（进食、睡眠等）——每2秒检查一次避免频繁打断
	_autonomy_timer += delta
	if _autonomy_timer >= 2.0:
		_autonomy_timer = 0.0
		_update_settler_autonomy()
	
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
	var work_manager = get_node_or_null("/root/WorkManager")
	for i in 3:
		var settler = Settler.new()
		settler.position = Vector2(randf_range(300, 500), randf_range(300, 500))
		add_child(settler)
		settlers.append(settler)
		if work_manager:
			work_manager.init_settler(settler.settler_id)
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

# -------- 定居者选择 --------
func _find_settler_at_pos(global_pos: Vector2):
	"""查找指定位置附近的定居者，返回定居者或 null"""
	var closest = null
	var closest_dist = world.tile_size * 0.6  # 约19像素，匹配角色视觉大小
	
	for s in settlers:
		if not is_instance_valid(s):
			continue
		var dist = s.position.distance_to(global_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = s
	
	return closest

func _try_select_settler() -> bool:
	"""尝试在鼠标位置选择定居者，返回是否选中"""
	var s = _find_settler_at_pos(get_global_mouse_position())
	if s != null:
		_select_settler(s)
		return true
	
	_deselect_settler()
	return false

func _select_settler(settler):
	"""选中定居者"""
	if selected_settler == settler:
		return
	# 取消之前的选中
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	# 选中新定居者
	selected_settler = settler
	settler.set_selected(true)
	settler_selected.emit(settler)

func _deselect_settler():
	"""取消选中定居者"""
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	selected_settler = null
	settler_deselected.emit()

# -------- 建筑点击选择 --------
func _try_select_building():
	"""尝试在鼠标位置选择建筑"""
	var global_pos = get_global_mouse_position()
	var grid_pos = Vector2i(
		floori(global_pos.x / world.tile_size),
		floori(global_pos.y / world.tile_size)
	)
	_try_select_building_at(grid_pos)

func _try_select_building_at(grid_pos: Vector2i):
	"""在指定网格位置选择建筑
	- 已完成且有存储功能 → 存储面板
	- 未完成（施工中）→ 建筑进度面板
	"""
	# 选中建筑时取消资源选中
	_deselect_resource()
	
	var bld = building_system.get_building_at(grid_pos) if building_system else null
	if bld == null:
		_deselect_construction()
		_deselect_building()
		return
	
	# 已完成且有存储功能的建筑 → 存储面板
	if bld.is_completed:
		var data = bld.get_data()
		if data != null and data.storage_capacity > 0 and bld.inventory != null:
			_deselect_construction()
			_select_building(bld)
			return
		# 已完成的非存储建筑 → 取消所有选中
		_deselect_construction()
		_deselect_building()
		return
	
	# 未完成的建筑（施工中）→ 建筑进度面板
	_deselect_building()
	_select_construction(bld)

func _select_building(bld):
	"""选中存储建筑"""
	if selected_building_instance == bld:
		return
	selected_building_instance = bld
	building_selected.emit(bld)

func _deselect_building():
	"""取消选中建筑"""
	selected_building_instance = null
	building_deselected.emit()

func _select_construction(bld):
	"""选中在建建筑，显示进度面板"""
	if selected_construction_building == bld:
		return
	selected_construction_building = bld
	construction_selected.emit(bld)

func _deselect_construction():
	"""取消选中在建建筑"""
	if selected_construction_building != null:
		selected_construction_building = null
		construction_deselected.emit()

# -------- 资源节点选择 --------
func _select_resource(pos: Vector2i, deposit):
	"""选中资源节点"""
	if selected_resource_pos == pos:
		return
	selected_resource_pos = pos
	selected_resource_deposit = deposit
	resource_selected.emit(pos, deposit)

func _deselect_resource():
	"""取消选中资源节点"""
	if selected_resource_pos.x >= 0:
		selected_resource_pos = Vector2i(-1, -1)
		selected_resource_deposit = null
		resource_deselected.emit()

func _on_building_completed(pos: Vector2i):
	"""建筑完成时：若当前正选中此建筑，自动切换显示"""
	if selected_construction_building and selected_construction_building.grid_pos == pos:
		_deselect_construction()
		# 如果完成的是存储建筑，自动选中显示存储面板
		var bld = building_system.get_building_at(pos) if building_system else null
		if bld:
			var data = bld.get_data()
			if data and data.storage_capacity > 0 and bld.inventory:
				_select_building(bld)

# ==================== 定居者自主AI系统 ====================

func _update_settler_autonomy():
	"""更新定居者自主行为（进食、睡眠等基本需求）"""
	var is_night = not _gm.is_daytime()
	
	for s in settlers:
		if not is_instance_valid(s):
			continue
		
		# 跳过已经在执行非工作状态（进食/睡眠）的定居者
		if s.state == Settler.SettlerState.SLEEPING or s.state == Settler.SettlerState.EATING:
			continue
		
		# 如果正在工作中，不打断（除非需求极低）
		if s.state == Settler.SettlerState.WORKING or s.state == Settler.SettlerState.MOVING:
			# 检查是否有紧急需求
			if s.needs.get("hunger", 100) < 15 or s.needs.get("rest", 100) < 10:
				# 传入 true 跳过自动搬运，让角色先满足基本需求（进食/睡眠）
				s.complete_task(true)
			else:
				continue
		
		# 1. 饥饿处理（饱食度 < 25 且空闲）
		if s.needs.get("hunger", 100) < 25 and s.state == Settler.SettlerState.IDLE:
			s.try_eat()
			continue
		
		# 2. 夜晚处理（天黑且空闲→去睡觉）
		if is_night and s.needs.get("rest", 100) < 70 and s.state == Settler.SettlerState.IDLE:
			var home = s.find_nearest_residential()
			if not home.is_empty():
				s.try_sleep(home.pos, home.world_pos)
				continue
			# 没有住所也尝试原地休息
			if s.needs.get("rest", 100) < 30:
				s.try_sleep(Vector2i.ZERO, s.position)
				continue

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		# 有选中定居者时，Esc 取消选中
		if selected_settler != null:
			_deselect_settler()
			return
		
		# 有选中建筑时，Esc 取消
		if selected_building_instance != null:
			_deselect_building()
			return
		
		# 有选中在建建筑时，Esc 取消
		if selected_construction_building != null:
			_deselect_construction()
			return
		
		# 有选中资源节点时，Esc 取消
		if selected_resource_pos.x >= 0:
			_deselect_resource()
			return
		
		if build_mode:
			exit_build_mode()
			return
		
		# 优先关闭暂停菜单
		var main_menu = get_node_or_null("UI/MainMenu")
		if main_menu and main_menu.visible:
			main_menu.visible = false
			_gm.resume_game()
			return
		# 关闭打开的菜单
		var build_menu = get_node_or_null("UI/BuildMenu")
		if build_menu and build_menu.visible:
			build_menu.visible = false
			return
		var tech_panel = get_node_or_null("UI/TechPanel")
		if tech_panel and tech_panel.visible:
			tech_panel.visible = false
			return
		var work_panel = get_node_or_null("UI/WorkPanel")
		if work_panel and work_panel.visible:
			work_panel.visible = false
			return
		
		# 无菜单打开时，Esc 打开暂停菜单
		if main_menu:
			main_menu.visible = true
			_gm.pause_game()
	
	# 右键退出建造模式
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and build_mode:
		exit_build_mode()
		return
	
	if event.is_action_pressed("left_click") and build_mode:
		_try_place_building()
		return
	
	# 定居者点击选择（非建造模式下的左键单击）
	if event.is_action_pressed("left_click") and not build_mode:
		var global_pos = get_global_mouse_position()
		var grid_pos = Vector2i(
			floori(global_pos.x / world.tile_size),
			floori(global_pos.y / world.tile_size)
		)
		
		# 查找当前位置的所有可选目标
		var clicked_settler = _find_settler_at_pos(global_pos)
		var clicked_bld = building_system.get_building_at(grid_pos) if building_system else null
		
		# 判断建筑是否可选择（存储建筑或施工中建筑）
		var bld_selectable = false
		if clicked_bld != null:
			if clicked_bld.is_completed:
				var data = clicked_bld.get_data()
				if data != null and data.storage_capacity > 0 and clicked_bld.inventory != null:
					bld_selectable = true
			else:
				bld_selectable = true
		
		if clicked_settler != null and bld_selectable:
			# 同时有定居者和建筑 → 轮流选择
			_deselect_resource()
			if selected_settler != null and is_instance_valid(selected_settler):
				# 当前选中定居者 → 切到建筑
				_deselect_settler()
				_try_select_building_at(grid_pos)
			else:
				# 当前选中建筑或未选中 → 切到定居者
				_deselect_construction()
				_deselect_building()
				_select_settler(clicked_settler)
		elif clicked_settler != null:
			# 只有定居者
			_deselect_resource()
			_select_settler(clicked_settler)
			_deselect_construction()
		elif clicked_bld != null:
			# 只有建筑
			_deselect_resource()
			_try_select_building_at(grid_pos)
		else:
			# 检查是否有可采集的资源
			var clicked_resource = world.get_resource_at(grid_pos)
			if clicked_resource != null and clicked_resource.amount > 0:
				# 有资源 - 选中它（取消其他选中）
				_deselect_construction()
				_deselect_building()
				_deselect_settler()
				_select_resource(grid_pos, clicked_resource)
			else:
				# 什么都没选中
				_deselect_construction()
				_deselect_building()
				_deselect_settler()
				_deselect_resource()
	
	# 快捷键 B：打开/关闭建造菜单
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			var build_menu = get_node_or_null("UI/BuildMenu")
			if build_menu:
				build_menu.visible = not build_menu.visible
				if build_menu.visible:
					# 重置菜单到初始状态
					build_menu.shortcut_category_active = false
					build_menu.current_category = -1
					build_menu._populate_buildings()
					build_menu.info_panel.visible = false
					build_menu.selected_building = ""
					build_menu.build_btn.disabled = true
					# 取消所有分类按钮的选中状态
					for i in build_menu.category_tabs.get_child_count():
						build_menu.category_tabs.get_child(i).button_pressed = false
				get_viewport().set_input_as_handled()
		
		# 快捷键 Space：暂停/继续游戏
		if event.keycode == KEY_SPACE:
			# 有菜单打开时，Space 不触发暂停（避免误操作）
			var build_menu = get_node_or_null("UI/BuildMenu")
			var tech_panel = get_node_or_null("UI/TechPanel")
			var work_panel = get_node_or_null("UI/WorkPanel")
			var main_menu = get_node_or_null("UI/MainMenu")
			if (build_menu and build_menu.visible) or (tech_panel and tech_panel.visible) or (work_panel and work_panel.visible) or (main_menu and main_menu.visible):
				return
			_gm.toggle_pause()
			# 更新暂停按钮文字
			var hud = get_node_or_null("UI/HUD")
			if hud and hud.pause_btn:
				hud.pause_btn.text = "▶" if _gm.state == 2 else "⏸"
			get_viewport().set_input_as_handled()

# ==================== 存档恢复 ====================

func _restore_from_save(data: Dictionary):
	"""从存档数据恢复所有系统状态"""
	# 先恢复世界（区块/地形/资源）
	if world and data.has("world"):
		world.from_dict(data.world)
	
	# 恢复系统
	if building_system and data.has("buildings"):
		building_system.from_dict(data.buildings)
	if tech_system and data.has("tech"):
		tech_system.from_dict(data.tech)
	if crafting_system and data.has("crafting"):
		crafting_system.from_dict(data.crafting)
	
	# 恢复工作优先级
	if data.has("work_priorities"):
		var wm = get_node_or_null("/root/WorkManager")
		if wm:
			wm.from_dict(data.work_priorities)
	
	# 恢复定居者
	if data.has("settlers"):
		for s_data in data.settlers:
			var settler = load("res://scripts/entities/settler.gd").new()
			settler.from_dict(s_data)
			add_child(settler)
			settlers.append(settler)

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
	
	# 超重空闲定居者自动搬运
	for s in settlers:
		if is_instance_valid(s) and s.state == Settler.SettlerState.IDLE and s.is_overweight():
			s._auto_store_overweight()

func _assign_ai_tasks():
	"""为所有空闲定居者分配任务（使用 WorkManager 的优先级配置）"""
	var idle_settlers = get_idle_settlers()
	if idle_settlers.is_empty():
		return
	
	var work_manager = get_node_or_null("/root/WorkManager")
	
	# 清理过期的建造重试冷却（保留近300帧的记录）
	var current_frame = Engine.get_physics_frames()
	var expired_keys = []
	for key in _construction_retry_cooldown:
		if current_frame - _construction_retry_cooldown[key] > 300:
			expired_keys.append(key)
	for key in expired_keys:
		_construction_retry_cooldown.erase(key)
	
	# 收集所有可用任务
	var tasks = []
	
	# 1. 建造任务——物资不足时不创建任务，带重试冷却
	var uncompleted = building_system.get_uncompleted_buildings() if building_system else []
	for bld in uncompleted:
		var data = bld.get_data()
		if data == null:
			continue
		
		var bld_key = "%d,%d" % [bld.grid_pos.x, bld.grid_pos.y]
		
		# 检查重试冷却：如果上次尝试失败且还在冷却期，跳过
		if _construction_retry_cooldown.has(bld_key):
			continue
		
		# 如果材料已备齐（已搬运到工地），直接创建建造任务
		# 如果材料未备齐，检查存储建筑或地面是否有可用材料
		if not bld.is_materials_ready():
			var has_any_material = false
			var missing = bld.get_missing_materials()
			for mat_id in missing.keys():
				# 检查所有存储建筑
				if _has_material_in_storage(mat_id):
					has_any_material = true
					break
				# 检查地面物品
				if world and world.has_ground_item(mat_id, 1):
					has_any_material = true
					break
			if not has_any_material:
				# 没有任何材料可用，加入冷却防止反复尝试
				_construction_retry_cooldown[bld_key] = current_frame
				continue  # 跳过此建筑，角色去做其他工作
		
		var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		tasks.append({
			"id": "construct_%d_%d" % [bld.grid_pos.x, bld.grid_pos.y],
			"type": "CONSTRUCT",
			"target_pos": bld.grid_pos,
			"target_world_pos": center_pixel,
			"skill": "construction",
			"work_required": data.work_cost - bld.construction_progress if data else 10.0,
			"work_type": WorkManager.WorkType.CONSTRUCTION,
		})
	
	# 2. 制作任务
	if crafting_system:
		var pending_jobs = crafting_system.get_pending_crafting_jobs()
		for job in pending_jobs:
			var bld = building_system.get_building_at(job.building_pos) if building_system else null
			if bld == null:
				continue
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
				"crafting_job": job,
				"work_type": WorkManager.WorkType.CRAFTING,
			})
	
	# 3. 搬运任务——为缺少物资的建筑/工地运送材料
	var haul_tasks = _scan_material_hauling_tasks(idle_settlers)
	tasks.append_array(haul_tasks)
	
	# 4. 采集任务 - 在地图已生成区块中找最近的资源
	var harvest_tasks = _scan_nearby_resources(idle_settlers)
	tasks.append_array(harvest_tasks)
	
	if tasks.is_empty():
		return
	
	# 为每个空闲定居者分配任务（考虑个人工作优先级）
	for settler in idle_settlers:
		if tasks.is_empty():
			break
		
		# 超重角色不分配采集/制作/建造任务，先让它们去存放
		if settler.is_overweight():
			continue
		
		var sid = settler.settler_id
		
		# 找到该定居者允许做的、距离最近的最高优先级任务
		var best_task = null
		var best_score = INF
		var best_idx = -1
		var best_priority = 0  # 记录当前最高优先级
		
		for i in range(tasks.size()):
			var t = tasks[i]
			
			# 检查该定居者是否允许做此工作类型
			var pri = 0  # 不允许
			if work_manager:
				var wt = t.get("work_type", -1)
				if wt >= 0:
					pri = work_manager.get_priority(sid, wt)
			
			if pri <= 0:
				continue  # 该定居者不做此类型工作
			
			# 制作任务需要检查是否有其他定居者已经在做
			if t.get("type") == "CRAFT":
				var job = t.get("crafting_job")
				if job and job.assigned_settler_id != "":
					continue
			
			# 建造任务：如果该定居者对同一建筑已重试过多次，跳过
			if t.get("type") == "CONSTRUCT" and settler._construction_retry_count >= settler.MAX_CONSTRUCTION_RETRIES:
				continue
			
			var task_pos = t.get("target_world_pos", Vector2.ZERO)
			var dist = settler.position.distance_squared_to(task_pos) if task_pos != Vector2.ZERO else 0
			
			# 优先级优先：先比较优先级，同优先级内再比较距离
			# 优先级1-4，4为最高；用优先级平方放大差距
			var score = dist / (pri * pri * 2.0)
			
			# 如果此任务优先级更高，直接覆盖（无论距离）
			if pri > best_priority or (pri == best_priority and score < best_score):
				best_priority = pri
				best_score = score
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
				
				var work_type = WorkManager.WorkType.WOODCUTTING
				match dep.type:
					world.ResourceNodeType.STONE_DEPOSIT, world.ResourceNodeType.IRON_DEPOSIT, world.ResourceNodeType.COPPER_DEPOSIT, world.ResourceNodeType.COAL_DEPOSIT:
						work_type = WorkManager.WorkType.MINING
					world.ResourceNodeType.BERRY_BUSH:
						work_type = WorkManager.WorkType.FARMING
				
				result.append({
					"id": "harvest_%d_%d" % [global_pos.x, global_pos.y],
					"type": "HARVEST",
					"target_pos": global_pos,
					"target_world_pos": world_pos,
					"resource_type": dep.type,
					"harvest_item": item_id,
					"skill": skill_map.get(dep.type, "woodcutting"),
					"work_required": dep.harvest_time,
					"work_type": work_type,
				})
	
	return result

func _scan_material_hauling_tasks(settlers: Array) -> Array:
	"""扫描需要搬运物资的建筑（施工工地/生产建筑），生成搬运任务"""
	var result: Array = []
	if building_system == null:
		return result
	
	var haul_tasks_added: Dictionary = {}  # 防止重复添加
	
	# 1. 施工工地——检查缺哪些材料
	for bld in building_system.get_uncompleted_buildings():
		if bld.is_materials_ready():
			continue
		var missing = bld.get_missing_materials()
		var bld_center = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		
		for mat_id in missing.keys():
			var needed = missing[mat_id]
			var task_key = "haul_construct_%d_%d_%s" % [bld.grid_pos.x, bld.grid_pos.y, mat_id]
			if haul_tasks_added.has(task_key):
				continue
			
			# 检查是否有来源可取材料
			var source_pos = _find_material_source(mat_id)
			if source_pos == null:
				continue  # 没有任何来源
			
			haul_tasks_added[task_key] = true
			var source_world_pos = source_pos.world_pos if source_pos.has("world_pos") else Vector2.ZERO
			result.append({
				"id": task_key,
				"type": "HAUL_CONSTRUCT",
				"target_pos": bld.grid_pos,
				"target_world_pos": source_world_pos,  # 先去来源地
				"target_bld_pos": bld.grid_pos,
				"source_type": source_pos.type,
				"source_bld_pos": source_pos.get("bld_pos", Vector2i.ZERO),
				"item_id": mat_id,
				"amount": needed,
				"haul_phase": "fetch",  # 初始阶段：取货
				"skill": "",
				"work_type": WorkManager.WorkType.HAULING,
			})
	
	# 2. 生产建筑——检查缺输入材料
	for bld in building_system.get_completed_production_buildings():
		var data = bld.get_data()
		if data == null or data.consumes.is_empty():
			continue
		
		for mat_id in data.consumes:
			var needed = data.consumes[mat_id]
			# 检查库存是否缺少
			if bld.inventory != null and bld.inventory.has_item(mat_id, needed):
				continue  # 材料充足
			
			var task_key = "haul_prod_%d_%d_%s" % [bld.grid_pos.x, bld.grid_pos.y, mat_id]
			if haul_tasks_added.has(task_key):
				continue
			
			var source_pos = _find_material_source(mat_id)
			if source_pos == null:
				continue
			
			haul_tasks_added[task_key] = true
			var source_world_pos = source_pos.world_pos if source_pos.has("world_pos") else Vector2.ZERO
			result.append({
				"id": task_key,
				"type": "HAUL_CONSTRUCT",
				"target_pos": bld.grid_pos,
				"target_world_pos": source_world_pos,  # 先去来源地
				"target_bld_pos": bld.grid_pos,
				"source_type": source_pos.type,
				"source_bld_pos": source_pos.get("bld_pos", Vector2i.ZERO),
				"item_id": mat_id,
				"amount": needed,
				"haul_phase": "fetch",  # 初始阶段：取货
				"skill": "",
				"work_type": WorkManager.WorkType.HAULING,
			})
	
	return result

func _find_material_source(item_id: String):
	"""查找指定材料的来源位置，返回{type, bld_pos, world_pos, grid_pos}或null"""
	if building_system == null:
		return null
	
	# 1. 查存储建筑（使用预索引快查）
	var best_bld = null
	var best_dist = INF
	var storage_blds = building_system.get_storage_buildings_with_item(item_id, 1)
	for bld in storage_blds:
		var center = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		var dist = center.length_squared()
		if dist < best_dist:
			best_dist = dist
			best_bld = bld
	
	if best_bld != null:
		return {
			"type": "storage",
			"bld_pos": best_bld.grid_pos,
			"world_pos": _grid_to_world(best_bld.grid_pos + best_bld.get_size() / 2)
		}
	
	# 2. 查地面物品
	if world:
		var ground_positions = world.get_all_ground_positions_of(item_id)
		if not ground_positions.is_empty():
			# 找最近的
			var best_grid = ground_positions[0]
			best_dist = INF
			for gp in ground_positions:
				var center = _grid_to_world(gp)
				var dist = center.length_squared()
				if dist < best_dist:
					best_dist = dist
					best_grid = gp
			return {
				"type": "ground",
				"bld_pos": best_grid,
				"grid_pos": best_grid,
				"world_pos": _grid_to_world(best_grid)
			}
	
	return null

func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""将网格坐标转换为世界像素坐标（格子中心）"""
	return Vector2(
		grid_pos.x * world.tile_size + world.tile_size / 2.0,
		grid_pos.y * world.tile_size + world.tile_size / 2.0
	)
func _has_material_in_storage(item_id: String) -> bool:
	"""检查所有已完成的存储建筑中是否有指定材料"""
	if building_system == null:
		return false
	return not building_system.get_storage_buildings_with_item(item_id, 1).is_empty()
