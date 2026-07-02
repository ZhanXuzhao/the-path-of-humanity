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
var designation_system: DesignationSystem
var selection_system: SelectionSystem
var task_system: TaskSystem
var farming_system: FarmingSystem

# 建造模式
var build_mode: bool = false
var selected_building: String = ""
var build_preview: Sprite2D = null
var mouse_grid_pos: Vector2i

# 种植模式
var plant_mode: bool = false
var selected_crop: String = ""
var plant_preview: Sprite2D = null

# 种植框选拖拽状态
var _is_plant_dragging: bool = false
var _plant_drag_start_grid: Vector2i = Vector2i(-999999, -999999)
var _plant_drag_end_grid: Vector2i = Vector2i(-999999, -999999)
var _plant_drag_overlay: Node2D = null

# 农田双击选择跟踪
var _last_farm_click_time: float = 0.0
var _last_farm_click_pos: Vector2i = Vector2i(-999, -999)
const FARM_DOUBLE_CLICK_TIME: float = 0.35

# 定居者管理
var settlers = []

# 野猪管理
var boars: Array = []

# 野猪生成计时器
var _boar_spawn_timer: float = 0.0
const BOAR_SPAWN_INTERVAL: float = 30.0  # 每30现实秒尝试生成一头野猪
const MAX_BOARS: int = 5  # 地图上最多5头野猪

# 敌对敌人管理
var enemies: Array = []

# 自主行为计时器（每2秒执行一次）
var _autonomy_timer: float = 0.0
func _ready():
	# 初始化子系统
	designation_system = DesignationSystem.new()
	designation_system.name = "DesignationSystem"
	add_child(designation_system)
	selection_system = SelectionSystem.new()
	selection_system.name = "SelectionSystem"
	add_child(selection_system)
	task_system = TaskSystem.new()
	task_system.name = "TaskSystem"
	add_child(task_system)
	farming_system = $Systems/FarmingSystem
	
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
	else:
		# 新游戏 - 初始化世界和定居者
		_gm.start_game()
		_generate_initial_area()
		_spawn_initial_settlers()
		_spawn_initial_boars()
		# 新游戏提示：使用指令面板标记资源
		call_deferred("_show_command_panel_tutorial")
	
	# 镜头对准第一个居民
	_focus_on_first_settler()
	
	# 初始化系统引用
	if building_system:
		building_system.world = world
	
	# 更新HUD速度标签（此时存档已加载完毕，time_speed 为实际值）
	_update_speed_label()

func _process(delta):
	# 建造模式预览
	if build_mode:
		_update_build_preview()
	
	# 种植模式预览
	if plant_mode:
		_update_plant_preview()
		_update_plant_drag_visual()
	
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
	if farming_system:
		farming_system.process_farming(delta)
	
	# 标记/清除模式：更新框选视觉
	designation_system.process_drag_update()

	# 野猪生成（每2秒检查一次）
	_boar_spawn_timer += delta
	if _boar_spawn_timer >= 2.0:
		_boar_spawn_timer = 0.0
		_try_spawn_boar()
	
	# 更新野猪AI
	_update_boars(delta)
	
	# 更新敌人AI
	_update_enemies(delta)
	
	# 单位分离——防止角色/敌人/野猪叠在一起
	_apply_unit_separation(delta)
	
	# 定居者AI定时更新（每1秒执行一次）
	_autonomy_timer += delta
	if _autonomy_timer >= 1.0:
		var elapsed = _autonomy_timer
		_autonomy_timer = 0.0
		
		# 更新定居者AI和任务分配
		task_system.process_tick(elapsed)
		
		# 检查选中的定居者是否还存活
		if selection_system.selected_settler != null and not is_instance_valid(selection_system.selected_settler):
			selection_system.deselect_settler()
		
		# 检查选中的野猪是否还存活
		if selection_system.selected_boar != null and not is_instance_valid(selection_system.selected_boar):
			selection_system.deselect_boar()
		
		# 检查选中的敌人是否还存活
		if selection_system.selected_enemy != null and not is_instance_valid(selection_system.selected_enemy):
			selection_system.deselect_enemy()
		
		# 检查选中的资源节点是否还存在（可能已被采集完）
		if selection_system.selected_resource_pos.x >= 0:
			var res = world.get_resource_at(selection_system.selected_resource_pos)
			if res == null or res.amount <= 0:
				selection_system.deselect_resource()
		
		# 检查选中的地面物品是否还存在（可能已被拾取完）
		if selection_system.selected_ground_item_pos.x >= 0:
			var stacks = world.get_ground_items_at(selection_system.selected_ground_item_pos)
			if stacks.is_empty():
				selection_system.deselect_ground_item()
		
		

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

func _focus_on_first_settler():
	"""延迟聚焦到第一个居民"""
	if settlers.size() > 0 and camera:
		camera.focus_on(settlers[0].position, 0.8)

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

# ==================== 种植模式 ====================
func enter_plant_mode(crop_id: String):
	plant_mode = true
	selected_crop = crop_id
	_is_plant_dragging = false

	if build_mode:
		exit_build_mode()
	if designation_system.designation_mode:
		designation_system.exit_designation_mode()
	if designation_system.clear_mode:
		designation_system.exit_clear_mode()
	if designation_system.demolition_mode:
		designation_system.exit_demolition_mode()

	if plant_preview == null:
		plant_preview = Sprite2D.new()
		plant_preview.z_index = 100
		add_child(plant_preview)

	var preview_tex = _create_plant_preview_texture()
	plant_preview.texture = preview_tex
	plant_preview.visible = true
	plant_preview.modulate = Color(0, 1, 0, 0.5)

	_init_plant_drag_overlay()

func exit_plant_mode():
	plant_mode = false
	selected_crop = ""
	_is_plant_dragging = false
	if plant_preview:
		plant_preview.visible = false
	if _plant_drag_overlay:
		_plant_drag_overlay.queue_redraw()

	var plant_panel = get_node_or_null("UI/PlantPanel")
	if plant_panel:
		plant_panel.visible = false

func _create_plant_preview_texture() -> Texture2D:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 1, 0, 0.3))
	for x in 32:
		img.set_pixel(x, 0, Color(0, 1, 0, 0.8))
		img.set_pixel(x, 31, Color(0, 1, 0, 0.8))
	for y in 32:
		img.set_pixel(0, y, Color(0, 1, 0, 0.8))
		img.set_pixel(31, y, Color(0, 1, 0, 0.8))
	return ImageTexture.create_from_image(img)

func _update_plant_preview():
	var mouse_pos = get_global_mouse_position()
	mouse_grid_pos = Vector2i(
		floori(mouse_pos.x / world.tile_size),
		floori(mouse_pos.y / world.tile_size)
	)

	if plant_preview and plant_mode:
		var pixel_pos = Vector2(
			mouse_grid_pos.x * world.tile_size + world.tile_size / 2.0,
			mouse_grid_pos.y * world.tile_size + world.tile_size / 2.0
		)
		plant_preview.position = pixel_pos

		var can_plant = _can_place_farm(mouse_grid_pos)
		if can_plant:
			plant_preview.modulate = Color(0, 1, 0, 0.5)
		else:
			plant_preview.modulate = Color(1, 0, 0, 0.5)

func _can_place_farm(grid_pos: Vector2i) -> bool:
	if not world or not world.is_in_world_bounds(grid_pos):
		return false
	if not world.is_walkable(grid_pos):
		return false
	if building_system and building_system.get_building_at(grid_pos) != null:
		return false
	if farming_system and farming_system.has_plot(grid_pos):
		return false
	return true

func _try_place_farm():
	if not plant_mode or selected_crop == "":
		return

	if not _can_place_farm(mouse_grid_pos):
		_gm.show_notification("无法在此处种植", _gm.NotificationType.WARNING)
		return

	if farming_system:
		if farming_system.add_plot(mouse_grid_pos, selected_crop):
			var crop_def = farming_system.get_crop_def(selected_crop)
			var name_str = crop_def.name if crop_def else selected_crop
			_gm.show_notification("已设置 %s 农田" % name_str, _gm.NotificationType.SUCCESS)

func _init_plant_drag_overlay():
	if _plant_drag_overlay != null:
		return
	_plant_drag_overlay = Node2D.new()
	_plant_drag_overlay.name = "PlantDragOverlay"
	_plant_drag_overlay.z_index = 200
	_plant_drag_overlay.set_script(preload("res://scripts/core/drag_overlay.gd"))
	add_child(_plant_drag_overlay)
	move_child(_plant_drag_overlay, get_child_count() - 1)

func _update_plant_drag_visual():
	if not _plant_drag_overlay:
		return

	if not _is_plant_dragging or _plant_drag_start_grid.x < -99999:
		_plant_drag_overlay.visible = false
		return

	var mouse_pos = get_global_mouse_position()
	_plant_drag_end_grid = Vector2i(
		floori(mouse_pos.x / world.tile_size),
		floori(mouse_pos.y / world.tile_size)
	)

	_plant_drag_overlay.visible = true

	var min_x = mini(_plant_drag_start_grid.x, _plant_drag_end_grid.x)
	var max_x = maxi(_plant_drag_start_grid.x, _plant_drag_end_grid.x)
	var min_y = mini(_plant_drag_start_grid.y, _plant_drag_end_grid.y)
	var max_y = maxi(_plant_drag_start_grid.y, _plant_drag_end_grid.y)

	var pixel_pos = Vector2(min_x * world.tile_size, min_y * world.tile_size)
	var pixel_size = Vector2(
		(max_x - min_x + 1) * world.tile_size,
		(max_y - min_y + 1) * world.tile_size
	)

	_plant_drag_overlay.set("drag_rect_pos", pixel_pos)
	_plant_drag_overlay.set("drag_rect_size", pixel_size)
	_plant_drag_overlay.set("is_plant_mode", true)
	_plant_drag_overlay.queue_redraw()

func _place_farms_in_rect(from_grid: Vector2i, to_grid: Vector2i):
	if not plant_mode or selected_crop == "":
		return

	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)

	var placed = 0
	var blocked = 0

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var pos = Vector2i(x, y)
			if _can_place_farm(pos):
				if farming_system and farming_system.add_plot(pos, selected_crop):
					placed += 1
			else:
				blocked += 1

	var crop_def = farming_system.get_crop_def(selected_crop) if farming_system else null
	var name_str = crop_def.name if crop_def else selected_crop

	if placed > 0:
		_gm.show_notification("已设置 %d 块 %s 农田" % [placed, name_str], _gm.NotificationType.SUCCESS)
	if blocked > 0:
		_gm.show_notification("%d 个位置无法种植" % blocked, _gm.NotificationType.WARNING)

# ==================== 定居者自主AI系统 ====================

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if selection_system.selected_settler != null:
			selection_system.deselect_settler()
			return
		
		if selection_system.selected_building_instance != null:
			selection_system.deselect_building()
			return
		
		if selection_system.selected_construction_building != null:
			selection_system.deselect_construction()
			return
		
		if selection_system.selected_resource_pos.x >= 0:
			selection_system.deselect_resource()
			return
		
		if selection_system.selected_ground_item_pos.x >= 0:
			selection_system.deselect_ground_item()
			return
		
		if selection_system.selected_tile_pos.x >= 0:
			selection_system.deselect_tile()
			return
		if selection_system.selected_farm_plot_pos.x >= 0:
			selection_system.deselect_farm_plot()
			return
		if designation_system.demolition_mode:
			designation_system.exit_demolition_mode()
			return
		if plant_mode:
			exit_plant_mode()
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
		# 关闭事件面板
		var hud = get_node_or_null("UI/HUD")
		if hud and hud.has_method("_on_event_pressed") and hud.event_panel and hud.event_panel.visible:
			hud.event_panel.visible = false
			return
		
		# 无菜单打开时，Esc 打开暂停菜单
		if main_menu:
			main_menu.visible = true
			_gm.pause_game()
	
	# Q 键切换采集标记模式（自动）
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed:
		if designation_system.designation_mode and designation_system.designation_work_type == -2:
			designation_system.exit_designation_mode()
		else:
			if build_mode:
				exit_build_mode()
			if designation_system.clear_mode:
				designation_system.exit_clear_mode()
			if designation_system.demolition_mode:
				designation_system.exit_demolition_mode()
			designation_system.enter_designation_mode(-2)
		get_viewport().set_input_as_handled()
		return
	
	# C 键切换清除模式
	if event is InputEventKey and event.keycode == KEY_C and event.pressed:
		if designation_system.clear_mode:
			designation_system.exit_clear_mode()
		else:
			if build_mode:
				exit_build_mode()
			if designation_system.designation_mode:
				designation_system.exit_designation_mode()
			if designation_system.demolition_mode:
				designation_system.exit_demolition_mode()
			designation_system.enter_clear_mode()
		get_viewport().set_input_as_handled()
		return
	
	# 右键退出标记/清除/建造模式
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if designation_system.designation_mode:
			designation_system.exit_designation_mode()
			return
		if designation_system.clear_mode:
			designation_system.exit_clear_mode()
			return
		if designation_system.demolition_mode:
			designation_system.exit_demolition_mode()
			return
		if plant_mode:
			exit_plant_mode()
			return
		if build_mode:
			exit_build_mode()
			return
		# 右键取消所有选中
		if selection_system.selected_boar != null:
			selection_system.deselect_boar()
			return
		if selection_system.selected_settler != null:
			selection_system.deselect_settler()
			return
		if selection_system.selected_enemy != null:
			selection_system.deselect_enemy()
			return
		if selection_system.selected_tile_pos.x >= 0:
			selection_system.deselect_tile()
			return
		if selection_system.selected_farm_plot_pos.x >= 0:
			selection_system.deselect_farm_plot()
			return
	
	# 点击UI控件时不处理世界点击逻辑
	if event.is_action_pressed("left_click") and _is_mouse_over_ui():
		return
	
	# 标记模式的左键处理
	if event is InputEventMouseButton and not build_mode and designation_system.designation_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var global_pos = get_global_mouse_position()
				designation_system._drag_start_grid = Vector2i(
					floori(global_pos.x / world.tile_size),
					floori(global_pos.y / world.tile_size)
				)
				designation_system._drag_end_grid = designation_system._drag_start_grid
				designation_system._is_designation_dragging = true
				if world_renderer and world_renderer.has_method("_clear_designation_preview"):
					world_renderer._clear_designation_preview()
				designation_system._update_designation_drag_visual()
			else:
				if designation_system._is_designation_dragging:
					designation_system._is_designation_dragging = false
					
					var global_pos = get_global_mouse_position()
					var end_grid = Vector2i(
						floori(global_pos.x / world.tile_size),
						floori(global_pos.y / world.tile_size)
					)
					
					if designation_system._drag_start_grid == end_grid:
						var is_auto = (designation_system.designation_work_type == -2)
						if designation_system.designation_work_type == WorkManager.WorkType.COMBAT:
							designation_system._toggle_enemy_designation_at_pos(global_pos)
						elif designation_system.designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
							if not designation_system._toggle_boar_designation_at_pos(global_pos) and is_auto:
								designation_system.toggle_resource_designation(designation_system._drag_start_grid)
						else:
							designation_system.toggle_resource_designation(designation_system._drag_start_grid)
					else:
						designation_system._designate_resources_in_rect(designation_system._drag_start_grid, end_grid)
					
					if designation_system._drag_overlay:
						designation_system._drag_overlay.visible = false
						designation_system._drag_overlay.queue_redraw()
					
					if world_renderer and world_renderer.has_method("_clear_designation_preview"):
						world_renderer._clear_designation_preview()
					
					designation_system._drag_start_grid = Vector2i(-999999, -999999)
					designation_system._drag_end_grid = Vector2i(-999999, -999999)
			return
	
	# 清除模式的左键处理
	if event is InputEventMouseButton and not build_mode and designation_system.clear_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var global_pos = get_global_mouse_position()
				designation_system._drag_start_grid = Vector2i(
					floori(global_pos.x / world.tile_size),
					floori(global_pos.y / world.tile_size)
				)
				designation_system._drag_end_grid = designation_system._drag_start_grid
				designation_system._is_designation_dragging = true
				if world_renderer and world_renderer.has_method("_clear_designation_preview"):
					world_renderer._clear_designation_preview()
				designation_system._update_designation_drag_visual()
			else:
				if designation_system._is_designation_dragging:
					designation_system._is_designation_dragging = false
					
					var global_pos = get_global_mouse_position()
					var end_grid = Vector2i(
						floori(global_pos.x / world.tile_size),
						floori(global_pos.y / world.tile_size)
					)
					
					if designation_system._drag_start_grid == end_grid:
						var key = "%d,%d" % [designation_system._drag_start_grid.x, designation_system._drag_start_grid.y]
						if designation_system.designated_resources.has(key):
							designation_system.designated_resources.erase(key)
							designation_system.designated_resources_changed.emit()
						if designation_system.designated_demolitions.has(key):
							designation_system.designated_demolitions.erase(key)
							designation_system.designated_resources_changed.emit()
					else:
						designation_system._remove_designations_in_rect(designation_system._drag_start_grid, end_grid)
					
					if designation_system._drag_overlay:
						designation_system._drag_overlay.visible = false
						designation_system._drag_overlay.queue_redraw()
					
					if world_renderer and world_renderer.has_method("_clear_designation_preview"):
						world_renderer._clear_designation_preview()
					
					designation_system._drag_start_grid = Vector2i(-999999, -999999)
					designation_system._drag_end_grid = Vector2i(-999999, -999999)
			return
	
	# 拆除模式的左键处理
	if event is InputEventMouseButton and not build_mode and designation_system.demolition_mode:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var global_pos = get_global_mouse_position()
			designation_system._toggle_demolition_at_pos(global_pos)
			return
	
	# 种植模式的左键框选处理
	if event is InputEventMouseButton and plant_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var global_pos = get_global_mouse_position()
				_plant_drag_start_grid = Vector2i(
					floori(global_pos.x / world.tile_size),
					floori(global_pos.y / world.tile_size)
				)
				_plant_drag_end_grid = _plant_drag_start_grid
				_is_plant_dragging = true
				_update_plant_drag_visual()
			else:
				if _is_plant_dragging:
					_is_plant_dragging = false

					var global_pos = get_global_mouse_position()
					var end_grid = Vector2i(
						floori(global_pos.x / world.tile_size),
						floori(global_pos.y / world.tile_size)
					)

					if _plant_drag_start_grid == end_grid:
						mouse_grid_pos = _plant_drag_start_grid
						_try_place_farm()
					else:
						_place_farms_in_rect(_plant_drag_start_grid, end_grid)

					if _plant_drag_overlay:
						_plant_drag_overlay.visible = false
						_plant_drag_overlay.queue_redraw()

					_plant_drag_start_grid = Vector2i(-999999, -999999)
					_plant_drag_end_grid = Vector2i(-999999, -999999)
		return

	if event.is_action_pressed("left_click") and build_mode:
		_try_place_building()
		return
	
	# 定居者点击选择（非建造/种植/标记/清除/拆除模式下的左键单击）
	if event.is_action_pressed("left_click") and not plant_mode and not build_mode and not designation_system.designation_mode and not designation_system.clear_mode and not designation_system.demolition_mode:
		var global_pos = get_global_mouse_position()
		var grid_pos = Vector2i(
			floori(global_pos.x / world.tile_size),
			floori(global_pos.y / world.tile_size)
		)
		
		var clicked_settler = selection_system.find_settler_at_pos(global_pos)
		var clicked_boar = selection_system.find_boar_at_pos(global_pos)
		var clicked_enemy = selection_system.find_enemy_at_pos(global_pos)
		var clicked_bld = building_system.get_building_at(grid_pos) if building_system else null
		
		var bld_selectable = clicked_bld != null
		
		if clicked_enemy != null and clicked_settler == null and clicked_boar == null and not bld_selectable:
			selection_system.deselect_settler()
			selection_system.deselect_boar()
			selection_system.deselect_construction()
			selection_system.deselect_building()
			selection_system.deselect_resource()
			selection_system.deselect_ground_item()
			selection_system.deselect_tile()
			selection_system.select_enemy(clicked_enemy)
			return
		
		if clicked_boar != null and not bld_selectable and clicked_settler == null:
			selection_system.deselect_settler()
			selection_system.deselect_enemy()
			selection_system.deselect_construction()
			selection_system.deselect_building()
			selection_system.deselect_resource()
			selection_system.deselect_ground_item()
			selection_system.deselect_tile()
			selection_system.select_boar(clicked_boar)
			return
		
		if clicked_settler != null and bld_selectable:
			selection_system.deselect_resource()
			selection_system.deselect_ground_item()
			selection_system.deselect_tile()
			if selection_system.selected_settler != null and is_instance_valid(selection_system.selected_settler):
				selection_system.deselect_settler()
				selection_system.try_select_building_at(grid_pos)
			else:
				selection_system.deselect_construction()
				selection_system.deselect_building()
				selection_system.select_settler(clicked_settler)
		elif clicked_settler != null:
			var res_at_pos = world.get_resource_at(grid_pos)
			var has_resource = res_at_pos != null and res_at_pos.amount > 0
			var ground_at_pos = world.get_ground_items_at(grid_pos)
			var has_ground = not ground_at_pos.is_empty()
			
			if has_resource or has_ground:
				var settler_at_this_grid = selection_system.is_settler_at_grid(selection_system.selected_settler, grid_pos)
				if selection_system.selected_settler != null and is_instance_valid(selection_system.selected_settler) and settler_at_this_grid:
					selection_system.deselect_settler()
					selection_system.deselect_construction()
					selection_system.deselect_building()
					selection_system.deselect_tile()
					if has_ground:
						selection_system.select_ground_item(grid_pos, ground_at_pos)
					else:
						selection_system.select_resource(grid_pos, res_at_pos)
				else:
					selection_system.deselect_resource()
					selection_system.deselect_ground_item()
					selection_system.deselect_construction()
					selection_system.deselect_building()
					selection_system.deselect_tile()
					selection_system.select_settler(clicked_settler)
			else:
				selection_system.deselect_resource()
				selection_system.deselect_ground_item()
				selection_system.deselect_tile()
				selection_system.select_settler(clicked_settler)
				selection_system.deselect_construction()
		elif clicked_bld != null:
			selection_system.deselect_resource()
			selection_system.deselect_ground_item()
			selection_system.deselect_tile()
			selection_system.try_select_building_at(grid_pos)
		else:
			var clicked_ground_stacks = world.get_ground_items_at(grid_pos)
			if not clicked_ground_stacks.is_empty():
				selection_system.deselect_construction()
				selection_system.deselect_building()
				selection_system.deselect_settler()
				selection_system.deselect_boar()
				selection_system.deselect_enemy()
				selection_system.deselect_resource()
				selection_system.deselect_tile()
				selection_system.select_ground_item(grid_pos, clicked_ground_stacks)
			else:
				var clicked_resource = world.get_resource_at(grid_pos)
				if clicked_resource != null and clicked_resource.amount > 0:
					selection_system.deselect_construction()
					selection_system.deselect_building()
					selection_system.deselect_settler()
					selection_system.deselect_boar()
					selection_system.deselect_enemy()
					selection_system.deselect_ground_item()
					selection_system.deselect_tile()
					selection_system.select_resource(grid_pos, clicked_resource)
				else:
					# 检查农田地块
					var clicked_plot = farming_system.get_plot(grid_pos) if farming_system else null
					if clicked_plot != null:
						selection_system.deselect_enemy()
						selection_system.deselect_boar()
						selection_system.deselect_construction()
						selection_system.deselect_building()
						selection_system.deselect_settler()
						selection_system.deselect_resource()
						selection_system.deselect_ground_item()
						selection_system.deselect_tile()

						# 双击检测：相同位置短时间内再次点击 → 选中相邻同作物
						var now = Time.get_ticks_msec() / 1000.0
						if grid_pos == _last_farm_click_pos and now - _last_farm_click_time < FARM_DOUBLE_CLICK_TIME:
							var connected = farming_system.get_connected_plots(grid_pos)
							if connected.size() > 1:
								selection_system.select_farm_plots_group(connected)
							else:
								selection_system.select_farm_plot(grid_pos, clicked_plot)
						else:
							selection_system.select_farm_plot(grid_pos, clicked_plot)
						_last_farm_click_time = now
						_last_farm_click_pos = grid_pos
					elif clicked_enemy != null:
						selection_system.deselect_boar()
						selection_system.deselect_construction()
						selection_system.deselect_building()
						selection_system.deselect_settler()
						selection_system.deselect_resource()
						selection_system.deselect_ground_item()
						selection_system.select_enemy(clicked_enemy)
					else:
						selection_system.deselect_enemy()
						selection_system.deselect_boar()
						selection_system.deselect_construction()
						selection_system.deselect_building()
						selection_system.deselect_settler()
						selection_system.deselect_resource()
						selection_system.deselect_ground_item()
						if world and world.is_in_world_bounds(grid_pos):
							var tile_type = world.get_tile_at(grid_pos)
							selection_system.select_tile(grid_pos, tile_type)
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			selection_system.switch_to_next_settler()
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
		designation_system.designated_resources = data.designated_resources.duplicate()
		designation_system.designated_resources_changed.emit()
	
	# 恢复拆除标记（v5+）
	if data.has("designated_demolitions"):
		designation_system.designated_demolitions = data.designated_demolitions.duplicate()
		designation_system.designated_resources_changed.emit()

	# 恢复农田数据
	if farming_system and data.has("farming"):
		farming_system.from_dict(data.farming)

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
	var dead_marks: Array = []
	for inst_id in designation_system.designated_boars:
		var b = instance_from_id(inst_id) if inst_id else null
		if b == null or not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			dead_marks.append(inst_id)
	for id in dead_marks:
		designation_system.designated_boars.erase(id)
	
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

# ==================== 敌对敌人系统 ====================

func get_enemies() -> Array:
	"""获取所有敌人列表（供建筑系统调用）"""
	return enemies

func trigger_enemy_raid(count: int = 3):
	"""触发敌袭事件：在地图边缘生成指定数量的敌人"""
	if enemies.size() >= 10:
		_gm.show_notification("地图上已有太多敌人，无法生成更多", _gm.NotificationType.WARNING)
		return
	
	var spawned = 0
	var attempts = 0
	var max_attempts = count * 20
	
	while spawned < count and attempts < max_attempts:
		attempts += 1
		var enemy = load("res://scripts/entities/enemy.gd").new()
		if not enemy.spawn_at_edge(self):
			enemy.queue_free()
			continue
		enemy.died.connect(_on_enemy_died.bind(enemy))
		add_child(enemy)
		enemies.append(enemy)
		spawned += 1
	
	if spawned > 0:
		_gm.show_notification("⚠️ 敌袭！%d个敌人从边缘入侵！" % spawned, _gm.NotificationType.COMBAT)
		print("敌袭事件：生成了 %d 个敌人" % spawned)

func _update_enemies(_delta):
	"""更新所有敌人状态（检查死亡清理、定居者自动反击）"""
	# 清理已死亡的敌人
	var dead_enemies: Array = []
	for e in enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
			dead_enemies.append(e)
	for e in dead_enemies:
		if is_instance_valid(e):
			var dead_id = e.get_instance_id()
			if designation_system.designated_enemies.has(dead_id):
				designation_system.designated_enemies.erase(dead_id)
		enemies.erase(e)
	
	# 定居者自动反击射程内的敌人
	for settler in settlers:
		if not is_instance_valid(settler):
			continue
		if not settler.has_ranged_weapon():
			continue
		if settler.state != Settler.SettlerState.IDLE and settler.state != Settler.SettlerState.MOVING:
			continue
		
		var nearest_enemy = null
		var nearest_dist = INF
		for e in enemies:
			if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
				continue
			var dist = settler.position.distance_squared_to(e.position)
			if dist < nearest_dist and dist <= settler.ARROW_RANGE * settler.ARROW_RANGE:
				nearest_dist = dist
				nearest_enemy = e
		
		if nearest_enemy:
			var dir = nearest_enemy.position - settler.position
			settler.facing_direction = dir.normalized()
			settler.shoot_at(nearest_enemy)

func _on_enemy_died(_grid_pos: Vector2i, enemy: Node2D):
	"""敌人死亡时从列表中移除"""
	enemies.erase(enemy)

# -------- 单位分离（防止重叠） --------
func _apply_unit_separation(_delta: float):
	"""对所有可移动单位施加软分离力，避免重叠"""
	var all_units: Array[Node2D] = []
	
	# 收集所有活着的单位
	for s in settlers:
		if is_instance_valid(s):
			all_units.append(s)
	for b in boars:
		if is_instance_valid(b):
			all_units.append(b)
	for e in enemies:
		if is_instance_valid(e):
			all_units.append(e)
	
	var count = all_units.size()
	if count < 2:
		return
	
	var min_dist = world.tile_size * 1.0  # 一格距离
	var push_force = 0.5  # 每帧推开幅度
	
	for i in range(count):
		var a = all_units[i]
		for j in range(i + 1, count):
			var b = all_units[j]
			var offset = a.position - b.position
			var dist_sq = offset.length_squared()
			
			if dist_sq < min_dist * min_dist and dist_sq > 0.01:
				var dist = sqrt(dist_sq)
				var push = (min_dist - dist) / min_dist * push_force
				var dir = offset / dist
				a.position += dir * push
				b.position -= dir * push

# -------- 敌人选择 --------
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
