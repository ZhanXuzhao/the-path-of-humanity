# 游戏主控制器 - Main Game Controller
# 管理游戏场景、系统协调、建造模式等
extends Node2D
class_name Game

const ItemDefinitions = preload("res://resources/item_definitions.gd")
const WorkManager = preload("res://scripts/autoload/work_manager.gd")

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

# 野猪管理
var boars: Array = []

# 野猪生成计时器
var _boar_spawn_timer: float = 0.0
const BOAR_SPAWN_INTERVAL: float = 30.0  # 每30现实秒尝试生成一头野猪
const MAX_BOARS: int = 5  # 地图上最多5头野猪

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

# 选中地面物品
var selected_ground_item_pos: Vector2i = Vector2i(-1, -1)
signal ground_item_selected(pos: Vector2i, stacks)
signal ground_item_deselected()

# 选中野猪
var selected_boar = null
signal boar_selected(boar)
signal boar_deselected()

# 建筑建造重试冷却（防止反复给同一缺物资建筑分配任务）
var _construction_retry_cooldown: Dictionary = {}  # "x,y" -> frame_number

# 自主行为计时器（每2秒执行一次）
var _autonomy_timer: float = 0.0

# 资源采集占用标记——防止多个定居者被分配到同一资源
# key: "x,y" -> settler_id，表示该资源正被哪个定居者采集
var _claimed_harvest_resources: Dictionary = {}

# ==================== 指令标记系统 ====================
# 标记模式——玩家可标记哪些资源允许采集
var designation_mode: bool = false
var designation_work_type: int = -1  # WorkManager.WorkType

# 清除模式——玩家可框选/点选清除已标记的资源
var clear_mode: bool = false

# 已标记的资源 {"x,y": work_type}
# 只有被标记的资源才会被定居者采集
var designated_resources: Dictionary = {}

# 已标记的野猪 {boar_instance_id: true} — 狩猎目标
var designated_boars: Dictionary = {}

signal designation_mode_changed(active: bool, work_type: int)
signal clear_mode_changed(active: bool)
signal designated_resources_changed()

# 框选拖拽状态
var _is_designation_dragging: bool = false
var _drag_start_grid: Vector2i = Vector2i(-999999, -999999)
var _drag_end_grid: Vector2i = Vector2i(-999999, -999999)
var _drag_overlay: Node2D = null  # 框选覆盖层（高z_index，显示在最上面）

# 清理过期采集占用的定时器（每30帧清理一次）
func _ready():
	# ===== 存档验证与加载 =====
	# 1. 检查是否有存档
	var has_save = _gm.has_save_file()
	var loaded_successfully = false
	
	if has_save:
		# 2. 检查存档是否有效（版本兼容）
		if _gm.is_save_valid():
			# 3. 有效存档 → 加载
			loaded_successfully = _gm.load_game(true)
		else:
			# 4. 无效存档 → 删除
			_gm.delete_save()
			print("存档版本不兼容，已删除，将开始新游戏")
	
	# ===== 根据结果启动游戏 =====
	if loaded_successfully:
		# 从存档恢复 - 不生成初始区域和定居者
		_gm.state = 1  # GameState.PLAYING
		_restore_from_save(_gm._loaded_save_data)
		_gm._loaded_save_data.clear()
		# 加载存档后也将相机移到世界中心
		_center_camera_on_world()
	else:
		# 新游戏 - 初始化世界和定居者
		_gm.start_game()
		_generate_initial_area()
		_spawn_initial_settlers()
		_spawn_initial_boars()
		_center_camera_on_world()
		
		# 新游戏提示：使用指令面板标记资源
		call_deferred("_show_command_panel_tutorial")
	
	# 初始化系统引用
	if building_system:
		building_system.world = world
		building_system.building_completed.connect(_on_building_completed)
	
	# 更新HUD速度标签（此时存档已加载完毕，time_speed 为实际值）
	_update_speed_label()

func _init_drag_overlay():
	"""创建框选覆盖层（独立 Node2D，高 z_index，确保绘制在最上面）"""
	if _drag_overlay != null:
		return
	_drag_overlay = Node2D.new()
	_drag_overlay.name = "DragOverlay"
	_drag_overlay.z_index = 200
	_drag_overlay.set_script(preload("res://scripts/core/drag_overlay.gd"))
	add_child(_drag_overlay)
	move_child(_drag_overlay, get_child_count() - 1)  # 移到最末尾，最后渲染

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
	
	# 标记/清除模式：更新框选视觉
	if (designation_mode or clear_mode) and _is_designation_dragging:
		var mouse_pos = get_global_mouse_position()
		_drag_end_grid = Vector2i(
			floori(mouse_pos.x / world.tile_size),
			floori(mouse_pos.y / world.tile_size)
		)
		_update_designation_drag_visual()

	# 野猪生成（每2秒检查一次）
	_boar_spawn_timer += delta
	if _boar_spawn_timer >= 2.0:
		_boar_spawn_timer = 0.0
		_try_spawn_boar()
	
	# 更新野猪AI
	_update_boars(delta)
	
	# 定居者AI定时更新（每1秒执行一次）
	_autonomy_timer += delta
	if _autonomy_timer >= 1.0:
		_autonomy_timer = 0.0
		
		# 更新定居者需求和AI
		_update_settlers(delta)
		
		# 分配任务给空闲定居者
		_assign_ai_tasks()
		
		# 仍有空闲的定居者 → 没活干了，去睡觉（没工作是前提）
		_handle_idle_sleep()
		
		# 检查选中的定居者是否还存活
		if selected_settler != null and not is_instance_valid(selected_settler):
			_deselect_settler()
		
		# 检查选中的野猪是否还存活
		if selected_boar != null and not is_instance_valid(selected_boar):
			_deselect_boar()
		
		# 检查选中的资源节点是否还存在（可能已被采集完）
		if selected_resource_pos.x >= 0:
			var res = world.get_resource_at(selected_resource_pos)
			if res == null or res.amount <= 0:
				_deselect_resource()
		
		# 清理已失效的资源采集标记（资源已被采完但标记未移除）
		_cleanup_depleted_designations()
		
		# 检查选中的地面物品是否还存在（可能已被拾取完）
		if selected_ground_item_pos.x >= 0:
			var stacks = world.get_ground_items_at(selected_ground_item_pos)
			if stacks.is_empty():
				_deselect_ground_item()
		
		

func _generate_initial_area():
	# 新游戏：随机化地图种子，确保每次地图不同
	world.world_seed = randi()
	# 确保整个世界所有区块均已生成
	for x in world.WORLD_CHUNKS_X:
		for y in world.WORLD_CHUNKS_Y:
			world.ensure_chunk_generated(Vector2i(x, y))

func _spawn_initial_settlers():
	# 创建初始定居者（数量由 GameConfig 配置）
	var work_manager = get_node_or_null("/root/WorkManager")
	var count = get_node("/root/GameConfig").initial_settler_count
	
	# 世界中心网格坐标
	var center_grid = Vector2i(
		world.WORLD_CHUNKS_X * world.CHUNK_SIZE / 2,
		world.WORLD_CHUNKS_Y * world.CHUNK_SIZE / 2
	)
	
	# 寻找中心附近最近的可行走格子（避免定居者生成在水上）
	var spawn_center_grid = _find_walkable_near(center_grid, 20)
	
	# 可行走中心像素坐标
	var spawn_center = Vector2(
		spawn_center_grid.x * world.tile_size + world.tile_size / 2.0,
		spawn_center_grid.y * world.tile_size + world.tile_size / 2.0
	)
	
	# 预生成不重复的姓名
	var used_names: Array = []
	var name_list: Array = []
	for i in count:
		var settler_name = Settler.generate_unique_name(used_names)
		name_list.append(settler_name)
		used_names.append(settler_name)
	
	for i in count:
		var settler = Settler.new()
		settler.position = spawn_center + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		# 覆盖自动生成的随机名，使用预先算好的不重复姓名
		settler.settler_name = name_list[i]
		add_child(settler)
		settlers.append(settler)
		if work_manager:
			work_manager.init_settler(settler.settler_id)
		_gm.show_notification("新成员加入了聚居地: %s" % settler.settler_name, 
			3)
	
	# 新手教程：在出生点附近掉落弓箭，方便狩猎
	world.drop_item_on_ground(spawn_center_grid + Vector2i(1, 0), "bow", 1)
	world.drop_item_on_ground(spawn_center_grid + Vector2i(0, 1), "arrow", 30)

func _spawn_initial_boars():
	"""在地图上随机位置生成初始野猪（数量由 GameConfig 配置）"""
	var count = get_node("/root/GameConfig").initial_boar_count
	if count <= 0:
		return
	
	# 在世界范围内随机寻找可行走位置生成
	var world_tiles_x = world.WORLD_CHUNKS_X * world.CHUNK_SIZE
	var world_tiles_y = world.WORLD_CHUNKS_Y * world.CHUNK_SIZE
	var spawned = 0
	var attempts = 0
	var max_attempts = count * 20  # 防止死循环
	
	while spawned < count and attempts < max_attempts:
		attempts += 1
		var rand_grid = Vector2i(
			randi_range(1, world_tiles_x - 2),
			randi_range(1, world_tiles_y - 2)
		)
		if not world.is_walkable(rand_grid):
			continue
		
		var boar = load("res://scripts/entities/boar.gd").new()
		boar.position = Vector2(
			rand_grid.x * world.tile_size + world.tile_size / 2.0,
			rand_grid.y * world.tile_size + world.tile_size / 2.0
		)
		add_child(boar)
		boars.append(boar)
		boar.died.connect(_on_boar_died.bind(boar))
		spawned += 1

func _find_walkable_near(from_grid: Vector2i, max_radius: int) -> Vector2i:
	"""从 from_grid 开始螺旋搜索，返回半径 max_radius 内第一个可行走网格"""
	for radius in range(max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var check = from_grid + Vector2i(dx, dy)
				if world.is_walkable(check):
					return check
	return from_grid  # 兜底：返回原坐标（虽然不太可能，但防止死循环）

func _center_camera_on_world():
	"""根据世界大小将相机移动到世界中心"""
	var center_pixel = world.get_world_center_pixel()
	if camera:
		camera.position = center_pixel

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
	
	# 同时关闭建造菜单（右键退出建造模式时菜单也应关闭）
	var build_menu = get_node_or_null("UI/BuildMenu")
	if build_menu:
		build_menu.visible = false
		# 重置菜单状态
		if build_menu.has_method("_populate_buildings"):
			build_menu.shortcut_category_active = false
			build_menu.current_category = -1
			build_menu._populate_buildings()
			build_menu.info_panel.visible = false
			build_menu.selected_building = ""
			for i in build_menu.category_tabs.get_child_count():
				build_menu.category_tabs.get_child(i).button_pressed = false

# ==================== 指令标记模式 ====================

func enter_designation_mode(work_type: int):
	"""进入标记模式，玩家可以标记指定类型的资源"""
	if build_mode:
		exit_build_mode()
	if clear_mode:
		exit_clear_mode()
	
	designation_mode = true
	designation_work_type = work_type
	_is_designation_dragging = false
	_init_drag_overlay()
	
	# 鼠标变为十字准星
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	
	designation_mode_changed.emit(true, work_type)

func exit_designation_mode():
	"""退出标记模式"""
	designation_mode = false
	designation_work_type = -1
	_is_designation_dragging = false
	if _drag_overlay:
		_drag_overlay.queue_redraw()
	if world_renderer and world_renderer.has_method("_clear_designation_preview"):
		world_renderer._clear_designation_preview()
	# 恢复默认鼠标
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	designation_mode_changed.emit(false, -1)

func enter_clear_mode():
	"""进入清除模式，玩家可以框选/点选清除已标记的资源"""
	if build_mode:
		exit_build_mode()
	if designation_mode:
		exit_designation_mode()
	
	clear_mode = true
	_is_designation_dragging = false
	_init_drag_overlay()
	
	# 鼠标变为禁止图标
	Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
	
	clear_mode_changed.emit(true)

func exit_clear_mode():
	"""退出清除模式"""
	clear_mode = false
	_is_designation_dragging = false
	if _drag_overlay:
		_drag_overlay.queue_redraw()
	if world_renderer and world_renderer.has_method("_clear_designation_preview"):
		world_renderer._clear_designation_preview()
	# 恢复默认鼠标
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	clear_mode_changed.emit(false)

func toggle_resource_designation(grid_pos: Vector2i) -> bool:
	"""切换指定网格位置的资源标记状态，返回标记后的状态（true=已标记）"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	var is_auto = (designation_work_type == -2)
	
	# 狩猎/自动模式：标记/取消标记野猪
	if designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
		if _toggle_boar_designation_at(grid_pos):
			return true
		if not is_auto:
			return false  # 纯狩猎模式，没有找到野猪
	
	if designated_resources.has(key):
		if is_auto:
			# 自动模式：无论什么类型，再次点击即取消
			designated_resources.erase(key)
			designated_resources_changed.emit()
			return false
		else:
			# 如果已标记，且工作类型相同则取消标记；类型不同则更新
			if designated_resources[key] == designation_work_type:
				designated_resources.erase(key)
				designated_resources_changed.emit()
				return false
			else:
				designated_resources[key] = designation_work_type
				designated_resources_changed.emit()
				return true
	else:
		# 检查该位置是否有可标记的资源
		var dep = world.get_resource_at(grid_pos) if world else null
		if dep != null and dep.amount > 0:
			if _is_resource_match_work_type(dep.type, designation_work_type):
				var actual_type = _auto_detect_work_type(dep.type) if is_auto else designation_work_type
				if actual_type >= 0:
					designated_resources[key] = actual_type
					designated_resources_changed.emit()
					return true
		# 搬运/自动模式：也标记地面物品
		if (designation_work_type == WorkManager.WorkType.HAULING or is_auto) and world:
			var stacks = world.get_ground_items_at(grid_pos)
			if not stacks.is_empty():
				designated_resources[key] = WorkManager.WorkType.HAULING
				designated_resources_changed.emit()
				return true
	
	return false

func is_resource_designated(grid_pos: Vector2i) -> bool:
	"""检查指定网格位置的资源是否已被标记"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return designated_resources.has(key)

func get_designated_work_type(grid_pos: Vector2i) -> int:
	"""获取指定资源的标记工作类型，-1表示未标记"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return designated_resources.get(key, -1)

# -------- 野猪标记（狩猎） --------
func _toggle_boar_designation_at(grid_pos: Vector2i) -> bool:
	"""切换指定网格位置的野猪标记状态（使用网格中心像素距离检测）"""
	var tile_center = Vector2(
		grid_pos.x * world.tile_size + world.tile_size / 2.0,
		grid_pos.y * world.tile_size + world.tile_size / 2.0
	)
	var click_dist = world.tile_size * 0.6  # 与点击选择相同的容差
	
	for b in boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(tile_center)
		if dist < click_dist:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				designated_resources_changed.emit()
				return false
			else:
				designated_boars[inst_id] = true
				b.is_designated = true
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
	return false

func _toggle_boar_designation_at_pos(global_pos: Vector2) -> bool:
	"""使用鼠标像素位置直接查找并标记野猪（更精确，不依赖网格对齐）"""
	var click_dist = world.tile_size * 0.6
	
	for b in boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(global_pos)
		if dist < click_dist:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
			else:
				designated_boars[inst_id] = true
				b.is_designated = true
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
	return false

func is_boar_designated(boar_instance_id: int) -> bool:
	return designated_boars.has(boar_instance_id)

func clear_all_designations():
	"""清除所有标记（包括资源标记和野猪标记）"""
	designated_resources.clear()
	# 清除所有野猪标记视觉
	for b in boars:
		if is_instance_valid(b):
			b.is_designated = false
			b.queue_redraw()
	designated_boars.clear()
	designated_resources_changed.emit()

func clear_designations_by_type(work_type: int):
	"""清除指定工作类型的所有标记"""
	var to_remove: Array[String] = []
	for key in designated_resources:
		if designated_resources[key] == work_type:
			to_remove.append(key)
	for key in to_remove:
		designated_resources.erase(key)
	if not to_remove.is_empty():
		designated_resources_changed.emit()

func remove_designation_at(grid_pos: Vector2i):
	"""移除指定网格位置的资源采集标记"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	if designated_resources.has(key):
		designated_resources.erase(key)
		designated_resources_changed.emit()

func _auto_detect_work_type(resource_type: int) -> int:
	"""根据资源类型自动推断工作类型"""
	match resource_type:
		World.ResourceNodeType.STONE_DEPOSIT, World.ResourceNodeType.IRON_DEPOSIT, World.ResourceNodeType.COPPER_DEPOSIT, World.ResourceNodeType.COAL_DEPOSIT:
			return WorkManager.WorkType.MINING
		World.ResourceNodeType.TREE:
			return WorkManager.WorkType.WOODCUTTING
		World.ResourceNodeType.BERRY_BUSH:
			return WorkManager.WorkType.FARMING
		_:
			return -1

func _is_resource_match_work_type(resource_type: int, work_type: int) -> bool:
	"""检查资源类型是否匹配指定的工作类型"""
	match work_type:
		WorkManager.WorkType.MINING:
			return resource_type in [
				World.ResourceNodeType.STONE_DEPOSIT,
				World.ResourceNodeType.IRON_DEPOSIT,
				World.ResourceNodeType.COPPER_DEPOSIT,
				World.ResourceNodeType.COAL_DEPOSIT,
			]
		WorkManager.WorkType.WOODCUTTING:
			return resource_type == World.ResourceNodeType.TREE
		WorkManager.WorkType.FARMING:
			return resource_type == World.ResourceNodeType.BERRY_BUSH
		-2:  # 自动模式：匹配所有可采集资源
			return resource_type in [
				World.ResourceNodeType.STONE_DEPOSIT,
				World.ResourceNodeType.IRON_DEPOSIT,
				World.ResourceNodeType.COPPER_DEPOSIT,
				World.ResourceNodeType.COAL_DEPOSIT,
				World.ResourceNodeType.TREE,
				World.ResourceNodeType.BERRY_BUSH,
			]
		_:
			return false

func _designate_resources_in_rect(from_grid: Vector2i, to_grid: Vector2i):
	"""在矩形区域内标记所有匹配工作类型的资源"""
	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)
	var is_auto = (designation_work_type == -2)
	
	# 标记矩形内的野猪（狩猎模式专用，或自动模式下也标记）
	var boar_changed = false
	if designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
		var tile_size = world.tile_size if world else 32.0
		var rect_pixel_min = Vector2(min_x * tile_size, min_y * tile_size)
		var rect_pixel_max = Vector2((max_x + 1) * tile_size, (max_y + 1) * tile_size)
		
		for b in boars:
			if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
				continue
			# 检查野猪位置是否在矩形内
			if b.position.x >= rect_pixel_min.x and b.position.x < rect_pixel_max.x \
					and b.position.y >= rect_pixel_min.y and b.position.y < rect_pixel_max.y:
				var inst_id = b.get_instance_id()
				if not designated_boars.has(inst_id):
					designated_boars[inst_id] = true
					b.is_designated = true
					b.queue_redraw()
					boar_changed = true
	
	# 纯狩猎模式标记完野猪即可返回
	if designation_work_type == WorkManager.WorkType.HUNTING:
		if boar_changed:
			designated_resources_changed.emit()
		return
	
	# 其他模式（含自动模式）：继续标记资源/地面物品
	var changed = false
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var pos = Vector2i(x, y)
			var dep = world.get_resource_at(pos) if world else null
			if dep != null and dep.amount > 0:
				if _is_resource_match_work_type(dep.type, designation_work_type):
					var key = "%d,%d" % [x, y]
					var actual_type = _auto_detect_work_type(dep.type) if is_auto else designation_work_type
					if actual_type >= 0:
						designated_resources[key] = actual_type
						changed = true
			# 搬运/自动模式也标记地面物品
			if (designation_work_type == WorkManager.WorkType.HAULING or is_auto) and world:
				var stacks = world.get_ground_items_at(pos)
				if not stacks.is_empty():
					var key = "%d,%d" % [x, y]
					designated_resources[key] = WorkManager.WorkType.HAULING
					changed = true
	
	if changed or boar_changed:
		designated_resources_changed.emit()

func _remove_designations_in_rect(from_grid: Vector2i, to_grid: Vector2i):
	"""在矩形区域内清除所有标记（包括资源标记和野猪标记）"""
	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)
	
	var tile_size = world.tile_size if world else 32.0
	var rect_pixel_min = Vector2(min_x * tile_size, min_y * tile_size)
	var rect_pixel_max = Vector2((max_x + 1) * tile_size, (max_y + 1) * tile_size)
	
	# 清除矩形内的野猪标记
	var boar_changed = false
	for b in boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		if b.position.x >= rect_pixel_min.x and b.position.x < rect_pixel_max.x \
				and b.position.y >= rect_pixel_min.y and b.position.y < rect_pixel_max.y:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				boar_changed = true
	
	# 清除矩形内的资源标记
	var changed = false
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var key = "%d,%d" % [x, y]
			if designated_resources.has(key):
				designated_resources.erase(key)
				changed = true
	
	if changed or boar_changed:
		designated_resources_changed.emit()

func _update_designation_drag_visual():
	"""更新框选拖拽的视觉反馈——将框选数据写入覆盖层并触发重绘"""
	if not _drag_overlay:
		return
	
	if not _is_designation_dragging or _drag_start_grid.x < -99999 or _drag_end_grid.x < -99999:
		_drag_overlay.visible = false
		return
	
	_drag_overlay.visible = true
	
	# 计算框选矩形，存入覆盖层供其 _draw() 使用
	var min_x = mini(_drag_start_grid.x, _drag_end_grid.x)
	var max_x = maxi(_drag_start_grid.x, _drag_end_grid.x)
	var min_y = mini(_drag_start_grid.y, _drag_end_grid.y)
	var max_y = maxi(_drag_start_grid.y, _drag_end_grid.y)
	
	var pixel_pos = Vector2(min_x * world.tile_size, min_y * world.tile_size)
	var pixel_size = Vector2(
		(max_x - min_x + 1) * world.tile_size,
		(max_y - min_y + 1) * world.tile_size
	)
	
	_drag_overlay.set("drag_rect_pos", pixel_pos)
	_drag_overlay.set("drag_rect_size", pixel_size)
	_drag_overlay.set("is_clear_mode", clear_mode)
	_drag_overlay.queue_redraw()
	
	# 更新框选内的标记预览
	if designation_mode and world_renderer and world_renderer.has_method("update_designation_preview"):
		world_renderer.update_designation_preview(
			Vector2i(min_x, min_y),
			Vector2i(max_x, max_y),
			designation_work_type,
			false
		)
	if clear_mode and world_renderer and world_renderer.has_method("update_designation_preview"):
		world_renderer.update_designation_preview(
			Vector2i(min_x, min_y),
			Vector2i(max_x, max_y),
			-1,
			true
		)

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

func _is_settler_at_grid(settler, grid_pos: Vector2i) -> bool:
	"""判断定居者是否在指定网格位置"""
	if settler == null or not is_instance_valid(settler):
		return false
	var s_grid = Vector2i(
		floori(settler.position.x / world.tile_size),
		floori(settler.position.y / world.tile_size)
	)
	return s_grid == grid_pos

func _try_select_settler() -> bool:
	"""尝试在鼠标位置选择定居者，返回是否选中"""
	var s = _find_settler_at_pos(get_global_mouse_position())
	if s != null:
		_select_settler(s)
		return true
	
	_deselect_settler()
	return false

func _select_settler(settler, focus_camera: bool = false):
	"""选中定居者，可选是否镜头居中聚焦"""
	if selected_settler == settler:
		return
	# 取消之前的选中
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	# 选中定居者时取消野猪选中
	if selected_boar != null:
		_deselect_boar()
	# 选中新定居者
	selected_settler = settler
	settler.set_selected(true)
	settler_selected.emit(settler)
	# 镜头居中聚焦（默认鼠标点击不聚焦，Tab切换时聚焦）
	if focus_camera and camera and is_instance_valid(camera):
		camera.focus_on(settler.position)

func _deselect_settler():
	"""取消选中定居者"""
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	selected_settler = null
	settler_deselected.emit()

# -------- 野猪选择 --------
func _find_boar_at_pos(global_pos: Vector2):
	"""查找指定位置附近的野猪，返回野猪或 null"""
	var closest = null
	var closest_dist = world.tile_size * 0.6  # 约19像素
	
	for b in boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(global_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = b
	
	return closest

func _select_boar(boar):
	"""选中野猪"""
	if selected_boar == boar:
		return
	# 取消之前的选中
	_deselect_boar()
	# 选中新野猪
	selected_boar = boar
	boar.set_selected(true)
	boar_selected.emit(boar)
	# 同时取消其他选中
	_deselect_settler()
	_deselect_construction()
	_deselect_building()
	_deselect_resource()
	_deselect_ground_item()

func _deselect_boar():
	"""取消选中野猪"""
	if selected_boar != null and is_instance_valid(selected_boar):
		selected_boar.set_selected(false)
	selected_boar = null
	boar_deselected.emit()

func _switch_to_next_settler():
	"""Tab切换：按定居者列表顺序切换到下一个定居者，镜头居中聚焦"""
	if settlers.is_empty():
		return
	
	# 过滤出有效的定居者
	var valid_settlers = []
	for s in settlers:
		if is_instance_valid(s):
			valid_settlers.append(s)
	
	if valid_settlers.is_empty():
		return
	
	# 找到当前选中定居者在有效列表中的索引
	var current_idx = -1
	if selected_settler != null and is_instance_valid(selected_settler):
		current_idx = valid_settlers.find(selected_settler)
	
	# 计算下一个索引（循环）
	var next_idx = (current_idx + 1) % valid_settlers.size()
	
	# 使用 _select_settler 并带上聚焦标记
	_select_settler(valid_settlers[next_idx], true)

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
	- 已完成 → 通用建筑信息面板（存储建筑显示库存）
	- 未完成（施工中）→ 建筑进度面板
	"""
	# 选中建筑时取消其他选中
	_deselect_resource()
	_deselect_ground_item()
	
	var bld = building_system.get_building_at(grid_pos) if building_system else null
	if bld == null:
		_deselect_construction()
		_deselect_building()
		return
	
	# 已完成建筑 → 通用建筑信息
	if bld.is_completed:
		_deselect_construction()
		_select_building(bld)
		return
	
	# 未完成的建筑（施工中）→ 建筑进度面板
	_deselect_building()
	_select_construction(bld)

func _select_building(bld):
	"""选中存储建筑"""
	if selected_building_instance == bld:
		return
	if selected_boar != null:
		_deselect_boar()
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
	if selected_boar != null:
		_deselect_boar()
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
	if selected_boar != null:
		_deselect_boar()
	selected_resource_pos = pos
	selected_resource_deposit = deposit
	resource_selected.emit(pos, deposit)

func _deselect_resource():
	"""取消选中资源节点"""
	if selected_resource_pos.x >= 0:
		selected_resource_pos = Vector2i(-1, -1)
		selected_resource_deposit = null
		resource_deselected.emit()

# -------- 地面物品选择 --------
func _select_ground_item(pos: Vector2i, stacks):
	"""选中地面物品"""
	if selected_ground_item_pos == pos:
		return
	if selected_boar != null:
		_deselect_boar()
	selected_ground_item_pos = pos
	ground_item_selected.emit(pos, stacks)

func _deselect_ground_item():
	"""取消选中地面物品"""
	if selected_ground_item_pos.x >= 0:
		selected_ground_item_pos = Vector2i(-1, -1)
		ground_item_deselected.emit()

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
# 自主行为已合并到 _update_settlers 中

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
		
		# 有选中地面物品时，Esc 取消
		if selected_ground_item_pos.x >= 0:
			_deselect_ground_item()
			return
		
		if designation_mode:
			exit_designation_mode()
			return
		
		if clear_mode:
			exit_clear_mode()
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
	
	# Q 键切换采集标记模式（自动）
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed:
		if designation_mode and designation_work_type == -2:
			exit_designation_mode()
		else:
			if build_mode:
				exit_build_mode()
			if clear_mode:
				exit_clear_mode()
			enter_designation_mode(-2)
		get_viewport().set_input_as_handled()
		return
	
	# C 键切换清除模式
	if event is InputEventKey and event.keycode == KEY_C and event.pressed:
		if clear_mode:
			exit_clear_mode()
		else:
			if build_mode:
				exit_build_mode()
			if designation_mode:
				exit_designation_mode()
			enter_clear_mode()
		get_viewport().set_input_as_handled()
		return
	
	# 右键退出标记/清除/建造模式
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if designation_mode:
			exit_designation_mode()
			return
		if clear_mode:
			exit_clear_mode()
			return
		if build_mode:
			exit_build_mode()
			return
		# 右键取消所有选中
		if selected_boar != null:
			_deselect_boar()
			return
		if selected_settler != null:
			_deselect_settler()
			return
	
	# 点击UI控件时不处理世界点击逻辑
	if event.is_action_pressed("left_click") and _is_mouse_over_ui():
		return
	
	# 标记模式的左键处理
	if event is InputEventMouseButton and not build_mode and designation_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始拖拽或点选
				var global_pos = get_global_mouse_position()
				_drag_start_grid = Vector2i(
					floori(global_pos.x / world.tile_size),
					floori(global_pos.y / world.tile_size)
				)
				_drag_end_grid = _drag_start_grid
				_is_designation_dragging = true
				if world_renderer and world_renderer.has_method("_clear_designation_preview"):
					world_renderer._clear_designation_preview()
				_update_designation_drag_visual()
			else:
				# 鼠标释放：完成框选
				if _is_designation_dragging:
					_is_designation_dragging = false
					_update_designation_drag_visual()
					# 清除标记预览
					if world_renderer and world_renderer.has_method("_clear_designation_preview"):
						world_renderer._clear_designation_preview()
					
					var global_pos = get_global_mouse_position()
					var end_grid = Vector2i(
						floori(global_pos.x / world.tile_size),
						floori(global_pos.y / world.tile_size)
					)
					
					# 判断是点选还是框选
					if _drag_start_grid == end_grid:
						var is_auto = (designation_work_type == -2)
						# 点选：先尝试切换野猪标记（使用鼠标实际像素位置）
						if designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
							if not _toggle_boar_designation_at_pos(global_pos) and is_auto:
								# 自动模式下未点到野猪，回退到常规资源标记
								toggle_resource_designation(_drag_start_grid)
						else:
							toggle_resource_designation(_drag_start_grid)
					else:
						# 框选：标记矩形内所有匹配资源
						_designate_resources_in_rect(_drag_start_grid, end_grid)
					
					_drag_start_grid = Vector2i(-999999, -999999)
					_drag_end_grid = Vector2i(-999999, -999999)
			return
	
	# 清除模式的左键处理
	if event is InputEventMouseButton and not build_mode and clear_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始拖拽
				var global_pos = get_global_mouse_position()
				_drag_start_grid = Vector2i(
					floori(global_pos.x / world.tile_size),
					floori(global_pos.y / world.tile_size)
				)
				_drag_end_grid = _drag_start_grid
				_is_designation_dragging = true
				if world_renderer and world_renderer.has_method("_clear_designation_preview"):
					world_renderer._clear_designation_preview()
				_update_designation_drag_visual()
			else:
				# 鼠标释放：清除框选区域内的标记
				if _is_designation_dragging:
					_is_designation_dragging = false
					_update_designation_drag_visual()
					if world_renderer and world_renderer.has_method("_clear_designation_preview"):
						world_renderer._clear_designation_preview()
					
					var global_pos = get_global_mouse_position()
					var end_grid = Vector2i(
						floori(global_pos.x / world.tile_size),
						floori(global_pos.y / world.tile_size)
					)
					
					if _drag_start_grid == end_grid:
						# 点选：清除单个资源的标记
						var key = "%d,%d" % [_drag_start_grid.x, _drag_start_grid.y]
						if designated_resources.has(key):
							designated_resources.erase(key)
							designated_resources_changed.emit()
					else:
						# 框选：清除矩形内所有标记
						_remove_designations_in_rect(_drag_start_grid, end_grid)
					
					_drag_start_grid = Vector2i(-999999, -999999)
					_drag_end_grid = Vector2i(-999999, -999999)
			return
	
	if event.is_action_pressed("left_click") and build_mode:
		_try_place_building()
		return
	
	# 定居者点击选择（非建造/标记/清除模式下的左键单击）
	if event.is_action_pressed("left_click") and not build_mode and not designation_mode and not clear_mode:
		var global_pos = get_global_mouse_position()
		var grid_pos = Vector2i(
			floori(global_pos.x / world.tile_size),
			floori(global_pos.y / world.tile_size)
		)
		
		# 查找当前位置的所有可选目标
		var clicked_settler = _find_settler_at_pos(global_pos)
		var clicked_boar = _find_boar_at_pos(global_pos)
		var clicked_bld = building_system.get_building_at(grid_pos) if building_system else null
		
		# 判断建筑是否可选择（所有建筑均可选）
		var bld_selectable = clicked_bld != null
		
		# 如果有野猪在最上层（优先级高于定居者/建筑用于选中）
		if clicked_boar != null and not bld_selectable and clicked_settler == null:
			# 只有野猪
			_deselect_settler()
			_deselect_construction()
			_deselect_building()
			_deselect_resource()
			_deselect_ground_item()
			_select_boar(clicked_boar)
			return
		
		if clicked_settler != null and bld_selectable:
			# 同时有定居者和建筑 → 轮流选择
			_deselect_resource()
			_deselect_ground_item()
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
			# 检查该格是否同时有资源节点或地面物品
			var res_at_pos = world.get_resource_at(grid_pos)
			var has_resource = res_at_pos != null and res_at_pos.amount > 0
			var ground_at_pos = world.get_ground_items_at(grid_pos)
			var has_ground = not ground_at_pos.is_empty()
			
			if has_resource or has_ground:
				# 同时有定居者和资源/地面物品 → 轮流选择
				var settler_at_this_grid = _is_settler_at_grid(selected_settler, grid_pos)
				if selected_settler != null and is_instance_valid(selected_settler) and settler_at_this_grid:
					# 当前选中该位置的定居者 → 切到资源/地面物品
					_deselect_settler()
					_deselect_construction()
					_deselect_building()
					if has_ground:
						_select_ground_item(grid_pos, ground_at_pos)
					else:
						_select_resource(grid_pos, res_at_pos)
				else:
					# 当前选中其他对象或未选中 → 切到定居者
					_deselect_resource()
					_deselect_ground_item()
					_deselect_construction()
					_deselect_building()
					_select_settler(clicked_settler)
			else:
				# 只有定居者，没有重叠对象
				_deselect_resource()
				_deselect_ground_item()
				_select_settler(clicked_settler)
				_deselect_construction()
		elif clicked_bld != null:
			# 只有建筑
			_deselect_resource()
			_deselect_ground_item()
			_try_select_building_at(grid_pos)
		else:
			# 检查是否有地面物品（优先级高于资源）
			var clicked_ground_stacks = world.get_ground_items_at(grid_pos)
			if not clicked_ground_stacks.is_empty():
				# 有地面物品 - 选中它
				_deselect_construction()
				_deselect_building()
				_deselect_settler()
				_deselect_boar()
				_deselect_resource()
				_select_ground_item(grid_pos, clicked_ground_stacks)
			else:
				# 检查是否有可采集的资源
				var clicked_resource = world.get_resource_at(grid_pos)
				if clicked_resource != null and clicked_resource.amount > 0:
					# 有资源 - 选中它（取消其他选中）
					_deselect_construction()
					_deselect_building()
					_deselect_settler()
					_deselect_boar()
					_deselect_ground_item()
					_select_resource(grid_pos, clicked_resource)
				else:
					# 什么都没选中
					_deselect_boar()
					_deselect_construction()
					_deselect_building()
					_deselect_settler()
					_deselect_resource()
					_deselect_ground_item()
	
	# 快捷键 Tab：在定居者之间循环切换，镜头居中聚焦
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_switch_to_next_settler()
			get_viewport().set_input_as_handled()
			return
	
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
		
		# 快捷键 -：减速
		if event.keycode == KEY_MINUS:
			_speed_down()
			get_viewport().set_input_as_handled()
		
		# 快捷键 =：加速
		if event.keycode == KEY_EQUAL:
			_speed_up()
			get_viewport().set_input_as_handled()

# -------- 指令面板教程提示 --------
func _show_command_panel_tutorial():
	"""新游戏时显示指令面板使用提示"""
	_gm.show_notification("使用右侧指令面板标记资源，定居者只会采集标记的资源", 8)

# -------- 速度控制（-= 快捷键） --------
func _speed_up():
	"""加速：切换到下一档速度"""
	var speeds = _gm.speed_levels
	var current = _gm.time_speed
	var idx = speeds.find(current)
	if idx >= 0 and idx < len(speeds) - 1:
		idx += 1
		_gm.set_time_speed(speeds[idx])
		_update_speed_label()

func _speed_down():
	"""减速：切换到上一档速度"""
	var speeds = _gm.speed_levels
	var current = _gm.time_speed
	var idx = speeds.find(current)
	if idx > 0:
		idx -= 1
		_gm.set_time_speed(speeds[idx])
		_update_speed_label()

func _update_speed_label():
	"""更新HUD上的速度显示"""
	var hud = get_node_or_null("UI/HUD")
	if hud and hud.speed_label:
		var speed = _gm.time_speed
		if speed == int(speed):
			hud.speed_label.text = "×%d" % speed
		else:
			hud.speed_label.text = "×%.1f" % speed

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
	
	# 恢复资源采集标记（v3+）
	if data.has("designated_resources"):
		designated_resources = data.designated_resources.duplicate()
		designated_resources_changed.emit()

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
	"""更新所有定居者的需求、基本状态和自主行为（进食/睡眠）"""
	var delta_hours = _gm.time_speed * delta * (24.0 / _gm.day_length)
	var _is_night = not _gm.is_daytime()
	
	for s in settlers:
		if not is_instance_valid(s):
			continue
		
		# 更新需求
		s.update_needs(delta_hours)
		
		# 自动回血（所有状态都生效）
		s.apply_passive_heal(delta_hours)
		
		# ---- 自主行为：仅在 IDLE 时触发 ----
		if s.state != Settler.SettlerState.IDLE:
			continue
		
		# 1. 饥饿处理（饱食度 < 25）
		if s.needs.get("hunger", 100) < 25:
			s.try_eat()
			continue
		
		# 2. 超重自动搬运
		if s.is_overweight():
			s._auto_store_overweight()
			continue
	
	# 清理已失效的资源采集占用标记
	_cleanup_harvest_claims()

func _handle_idle_sleep():
	"""仍有空闲的定居者 → 没活干了，去睡觉（没工作是前提）"""
	var is_night = not _gm.is_daytime()
	for s in settlers:
		if not is_instance_valid(s):
			continue
		if s.state != Settler.SettlerState.IDLE:
			continue
		# 只有精力不足(<30)或夜晚时才睡觉
		var rest = s.needs.get("rest", 100)
		if rest < 30.0 or is_night:
			LogUtil.info(s, "IDLE -> sleep (rest=%.1f, night=%s)" % [rest, is_night])
			var home = s.find_nearest_residential()
			if not home.is_empty():
				s.try_sleep(home.pos, home.world_pos)
				continue
			s.try_sleep(Vector2i.ZERO, s.position)

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
	
	# 3.5 地面物品清理——将地面上的物品搬运到最近的储物架
	var ground_cleanup_tasks = _scan_ground_item_storage_tasks(idle_settlers, haul_tasks)
	tasks.append_array(ground_cleanup_tasks)
	
	# 4. 狩猎任务 - 猎杀被标记的野猪
	var hunting_tasks = _scan_hunting_targets(idle_settlers)
	tasks.append_array(hunting_tasks)
	
	# 5. 采集任务 - 在已生成的区块中找最近的资源（不主动生成新区块）
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
				# 同一建筑同时只允许一人使用
				var building_pos = t.get("building_pos", Vector2i.ZERO)
				if building_pos != Vector2i.ZERO and crafting_system.is_building_occupied(building_pos):
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
		
		# 如果是采集任务，标记该资源已被占用，防止第二个定居者也被分配过来
		if best_task.get("type") == "HARVEST":
			var target_pos: Vector2i = best_task.get("target_pos", Vector2i.ZERO)
			var res_key = "%d,%d" % [target_pos.x, target_pos.y]
			_claimed_harvest_resources[res_key] = settler.settler_id
		
		tasks.remove_at(best_idx)
		settler.assign_task(best_task)
		LogUtil.d("settler.assign_task(best_task): %s -> %s" % [settler.settler_name, best_task.get("id", "")])

func _scan_hunting_targets(_idle_settlers: Array) -> Array:
	"""扫描被标记的野猪，生成狩猎任务"""
	var result: Array = []
	if designated_boars.is_empty():
		return result
	
	for b in boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			# 已死亡的野猪自动取消标记
			var dead_id = b.get_instance_id() if is_instance_valid(b) else 0
			if designated_boars.has(dead_id):
				designated_boars.erase(dead_id)
			continue
		
		var inst_id = b.get_instance_id()
		if not designated_boars.has(inst_id):
			continue
		
		result.append({
			"id": "hunt_%d" % inst_id,
			"type": "HUNTING",
			"target_pos": Vector2i.ZERO,  # 不需要网格目标
			"target_world_pos": b.position,
			"skill": "combat",
			"work_required": 10.0,
			"work_type": WorkManager.WorkType.HUNTING,
			"boar_instance_id": inst_id,
		})
	
	return result

func _scan_nearby_resources(idle_settlers: Array) -> Array:
	"""扫描定居者周围已生成区块中的可采集资源（不主动生成新区块）"""
	var result: Array = []
	var scanned_chunks: Dictionary = {}
	
	var search_radius = 5  # 区块半径
	if idle_settlers.is_empty():
		return result
	
	var center_chunk = world.global_to_chunk(Vector2i(
		floori(idle_settlers[0].position.x / world.tile_size),
		floori(idle_settlers[0].position.y / world.tile_size)
	))
	
	for cx in range(center_chunk.x - search_radius, center_chunk.x + search_radius + 1):
		for cy in range(center_chunk.y - search_radius, center_chunk.y + search_radius + 1):
			var chunk_pos = Vector2i(cx, cy)
			if scanned_chunks.has(chunk_pos):
				continue
			scanned_chunks[chunk_pos] = true
			
			# 只扫描已经生成的区块，不主动生成新区块
			var chunk = world.chunks.get(chunk_pos)
			if chunk == null or not chunk.is_generated:
				continue
			
			for local_pos in chunk.resources:
				var dep = chunk.resources[local_pos]
				if dep.amount <= 0:
					continue
				
				var global_pos = chunk_pos * world.CHUNK_SIZE + local_pos
				var res_key = "%d,%d" % [global_pos.x, global_pos.y]
				
				# 跳过已被其他定居者占用的资源，防止两人砍同一棵树
				if _claimed_harvest_resources.has(res_key):
					continue
				
				# 指令面板：只采集被标记的资源
				if not designated_resources.has(res_key):
					continue
				
				var world_pos = _grid_to_world(global_pos)
				var item_id = dep.get_item_drop()
				
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
					"work_required": dep.harvest_time,
					"work_type": work_type,
				})
	
	return result

func _scan_material_hauling_tasks(_settlers: Array) -> Array:
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

func _scan_ground_item_storage_tasks(_idle_settlers: Array, existing_haul_tasks: Array) -> Array:
	"""扫描地面上散落的物品，找到有空间的储物架，创建搬运存储任务"""
	if building_system == null or world == null:
		return []
	
	# 收集已有搬运任务中已经分配的地面物品位置，避免重复
	var already_claimed: Dictionary = {}  # "item_id@x,y" -> true
	for t in existing_haul_tasks:
		if t.get("source_type") == "ground":
			var src_pos = t.get("source_bld_pos", Vector2i.ZERO)
			var item = t.get("item_id", "")
			if item != "":
				already_claimed["%s@%d,%d" % [item, src_pos.x, src_pos.y]] = true
	
	# 收集所有有空间的储物架
	var storage_rack_list = building_system.get_storage_buildings_with_space()
	if storage_rack_list.is_empty():
		return []  # 没有储物架，不创建任务
	
	var result: Array = []
	
	# 遍历所有地面物品位置
	for pos in world.ground_items:
		var stacks = world.ground_items[pos]
		if stacks.is_empty():
			continue
		
		# 指令面板：搬运模式下只处理被标记的地面物品
		var haul_key = "%d,%d" % [pos.x, pos.y]
		if not designated_resources.is_empty() and not designated_resources.has(haul_key):
			continue
		
		for stack in stacks:
			if stack.amount <= 0:
				continue
			
			var item_id = stack.item_id
			var claim_key = "%s@%d,%d" % [item_id, pos.x, pos.y]
			if already_claimed.has(claim_key):
				continue
			
			# 找最近的可用储物架
			var best_storage = null
			var best_dist = INF
			var ground_world = _grid_to_world(pos)
			
			for bld in storage_rack_list:
				if bld.inventory == null or bld.inventory.is_full():
					continue
				var bld_center = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
				var dist = ground_world.distance_squared_to(bld_center)
				if dist < best_dist:
					best_dist = dist
					best_storage = bld
			
			if best_storage == null:
				continue  # 没有可用储物架
			
			already_claimed[claim_key] = true
			
			var to_haul = mini(stack.amount, 50)  # 一次最多搬运50个
			result.append({
				"id": "ground_store_%s_%d_%d" % [item_id, pos.x, pos.y],
				"type": "HAUL_CONSTRUCT",
				"target_pos": best_storage.grid_pos,
				"target_world_pos": _grid_to_world(pos),  # 先去地面位置
				"target_bld_pos": best_storage.grid_pos,
				"source_type": "ground",
				"source_bld_pos": pos,
				"item_id": item_id,
				"amount": to_haul,
				"haul_phase": "fetch",
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

func claim_harvest_resource(grid_pos: Vector2i, settler_id: String):
	"""标记一个资源为已被指定定居者占用采集"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	_claimed_harvest_resources[key] = settler_id

func release_harvest_resource(grid_pos: Vector2i):
	"""释放一个资源的采集占用标记"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	_claimed_harvest_resources.erase(key)

func _cleanup_depleted_designations():
	"""清理已被采完但仍然保留在 designated_resources 中的标记"""
	var to_remove: Array[String] = []
	for res_key in designated_resources:
		var parts = res_key.split(",")
		if parts.size() != 2:
			to_remove.append(res_key)
			continue
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		if world:
			var dep = world.get_resource_at(grid_pos)
			if dep == null or dep.amount <= 0:
				# 资源已不存在或已耗尽
				to_remove.append(res_key)
				continue
		# 搬运模式下的地面物品标记：检查地面物品是否还在
		var wt = designated_resources[res_key]
		if wt == WorkManager.WorkType.HAULING and world:
			var stacks = world.get_ground_items_at(grid_pos)
			if stacks.is_empty():
				to_remove.append(res_key)
	
	for key in to_remove:
		designated_resources.erase(key)
	if not to_remove.is_empty():
		designated_resources_changed.emit()

func _cleanup_harvest_claims():
	"""清理已失效的资源采集占用标记"""
	var expired_keys: Array = []
	for res_key in _claimed_harvest_resources:
		var claim_settler_id = _claimed_harvest_resources[res_key]
		# 检查该定居者是否仍然存在且仍在采集该资源
		var settler = get_settler_by_id(claim_settler_id)
		if settler == null or not is_instance_valid(settler):
			expired_keys.append(res_key)
			continue
		if settler.current_task == null or settler.current_task.get("type", "") != "HARVEST":
			expired_keys.append(res_key)
			continue
		var task_target = settler.current_task.get("target_pos", Vector2i.ZERO)
		var task_key = "%d,%d" % [task_target.x, task_target.y]
		if task_key != res_key:
			expired_keys.append(res_key)
			continue
		# 检查资源是否还存在
		if world:
			var parts = res_key.split(",")
			var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
			var dep = world.get_resource_at(grid_pos)
			if dep == null or dep.amount <= 0:
				expired_keys.append(res_key)
				continue
	
	for key in expired_keys:
		_claimed_harvest_resources.erase(key)

# ==================== 野猪系统 ====================

func _try_spawn_boar():
	"""尝试在地图边缘生成一头野猪"""
	if boars.size() >= MAX_BOARS:
		return
	
	# 随机概率生成（每2秒约40%概率）
	if randf() > 0.4:
		return
	
	var boar = load("res://scripts/entities/boar.gd").new()
	if boar.spawn_at_edge(self):
		add_child(boar)
		boars.append(boar)
		boar.died.connect(_on_boar_died.bind(boar))

func _on_boar_died(_grid_pos: Vector2i, boar: Node2D):
	"""野猪死亡时从列表中移除"""
	boars.erase(boar)

func _update_boars(_delta):
	"""更新所有野猪的AI（野猪有独立的_process，这里检查战斗互动）"""
	# 清理已死亡的野猪标记
	var dead_marks: Array = []
	for inst_id in designated_boars:
		var b = instance_from_id(inst_id) if inst_id else null
		if b == null or not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			dead_marks.append(inst_id)
	for id in dead_marks:
		designated_boars.erase(id)
	
	# 检查定居者附近的野猪——自动防御射击
	for settler in settlers:
		if not is_instance_valid(settler):
			continue
		# 有狩猎任务的不重复处理（由 _tick_hunting 管理）
		if settler.current_task and settler.current_task.get("type") == "HUNTING":
			continue
		# 只有持有弓和箭的定居者才会自动攻击
		if not settler.has_ranged_weapon():
			continue
		
		# 只在空闲或移动时攻击
		if settler.state != Settler.SettlerState.IDLE and settler.state != Settler.SettlerState.MOVING:
			continue
		
		# 寻找射程内的野猪
		var nearest_boar = null
		var nearest_dist = INF
		for boar in boars:
			if not is_instance_valid(boar) or boar.state == boar.BoarState.DEAD:
				continue
			var dist = settler.position.distance_squared_to(boar.position)
			if dist < nearest_dist and dist <= settler.ARROW_RANGE * settler.ARROW_RANGE:
				nearest_dist = dist
				nearest_boar = boar
		
		if nearest_boar:
			# 面向野猪射箭
			var dir = nearest_boar.position - settler.position
			settler.facing_direction = dir.normalized()
			settler.shoot_at(nearest_boar)

func _auto_heal_settlers(delta_hours: float):
	"""所有定居者自动回血"""
	for s in settlers:
		if is_instance_valid(s):
			s.apply_passive_heal(delta_hours)

func _is_mouse_over_ui() -> bool:
	"""检查鼠标是否悬浮在任意可见 UI 控件上方（点击UI时不触发世界操作）"""
	var mouse_pos = get_viewport().get_mouse_position()
	var ui_layer = get_node_or_null("UI")
	if not ui_layer:
		return false
	return _check_control_at_pos(ui_layer, mouse_pos)

func _check_control_at_pos(node: Node, pos: Vector2) -> bool:
	"""递归检查鼠标位置是否在某个可见 Control 的矩形区域内"""
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			if child.get_global_rect().has_point(pos):
				return true
		if child.get_child_count() > 0:
			if _check_control_at_pos(child, pos):
				return true
	return false
