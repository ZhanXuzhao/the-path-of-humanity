# 世界渲染器 - World Renderer
# 负责使用 SVG 纹理绘制地图、资源和建筑
extends Node2D
class_name WorldRenderer

const _ID = preload("res://resources/item_definitions.gd")
const _TG = preload("res://scripts/core/texture_generator.gd")

@onready var world: World = get_parent()
@onready var building_system = get_node("/root/Game/Systems/BuildingSystem")

# 瓦片纹理映射
var tile_textures: Dictionary = {}

# 资源纹理映射
var resource_textures: Dictionary = {}

# 建筑纹理映射
var building_textures: Dictionary = {}

# 角色纹理
var settler_texture: Texture2D

# 地面物品纹理
var ground_item_texture: Texture2D

# 当前可见的精灵节点
var tile_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var resource_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var building_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var ground_item_sprites: Dictionary = {}  # Vector2i -> Sprite2D

# 建造进度条
var construction_overlays: Dictionary = {}  # Vector2i(建筑主格) -> Node2D(进度条容器)

# 床铺分配姓名标签 {建筑主格: Label}
var _bed_name_labels: Dictionary = {}
var PROGRESS_BAR_HEIGHT: float = 6.0

# 选中框
var _selected_building_pos: Vector2i = Vector2i(-1, -1)
var _selected_building_size: Vector2i = Vector2i.ONE
var _selection_overlay: Node2D  # 单独的高层级选中框叠加层

# 选中资源节点
var _selected_resource_pos: Vector2i = Vector2i(-1, -1)
var _resource_selection_overlay: Node2D  # 资源选中叠加层（含标签）
var _resource_info_label: Label  # 缓存的资源信息标签引用
var _last_resource_amount: float = -1.0  # 上次显示的资源量，用于避免重复刷新

# 选中地面物品
var _selected_ground_item_pos: Vector2i = Vector2i(-1, -1)
var _ground_item_selection_overlay: Node2D  # 地面物品选中叠加层
var _ground_item_info_label: Label  # 缓存的标签引用

# ==================== 指令标记视觉 ====================
var _designation_overlay: Node2D  # 标记覆盖层
var _designation_sprites: Dictionary = {}  # "x,y" -> Node2D (每个标记位置的图标容器)
var _designation_preview_sprites: Dictionary = {}  # "x,y" -> Node2D (拖拽预览图标)

# 工作类型对应的图标 Emoji
const DESIGNATION_ICONS = {
	0: "⛏️",   # MINING
	1: "🪓",   # WOODCUTTING
	5: "🌾",   # FARMING
	6: "📦",   # HAULING
}

func _ready():
	# 使用 TextureGenerator 生成所有纹理
	var all_textures = _TG.generate_all()
	tile_textures = all_textures["tiles"]
	resource_textures = all_textures["resources"]
	building_textures = all_textures["buildings"]
	settler_texture = all_textures["character"]["player_young_man"]
	ground_item_texture = all_textures.get("ground_item", null)
	
	# 连接信号
	world.tile_changed.connect(_on_tile_changed)
	world.ground_items_changed.connect(_on_ground_items_changed)
	world.resource_depleted.connect(_on_resource_depleted)
	
	# 连接建筑系统信号
	if building_system:
		building_system.building_placed.connect(_on_building_placed)
		building_system.building_removed.connect(_on_building_removed)
		building_system.building_completed.connect(_on_building_completed)
		building_system.construction_progress_updated.connect(_on_construction_progress_updated)
	
	# 连接选中信号
	var game = get_node("/root/Game")
	if game:
		game.building_selected.connect(_on_building_selected)
		game.building_deselected.connect(_on_building_deselected)
		game.construction_selected.connect(_on_construction_selected)
		game.construction_deselected.connect(_on_construction_deselected)
		game.resource_selected.connect(_on_resource_selected)
		game.resource_deselected.connect(_on_resource_deselected)
		game.ground_item_selected.connect(_on_ground_item_selected)
		game.ground_item_deselected.connect(_on_ground_item_deselected)
	
	# 延迟一帧渲染，确保 Game._ready() 已完成区块生成
	call_deferred("_render_existing_chunks")
	
	# 创建选中框叠加层（在建筑之上显示）
	_selection_overlay = Node2D.new()
	_selection_overlay.z_index = 100
	_selection_overlay.name = "SelectionOverlay"
	add_child(_selection_overlay)
	
	# 创建资源选中叠加层（在资源之上，建筑之下显示）
	_resource_selection_overlay = Node2D.new()
	_resource_selection_overlay.z_index = 50
	_resource_selection_overlay.name = "ResourceSelectionOverlay"
	add_child(_resource_selection_overlay)
	
	# 创建地面物品选中叠加层（z_index 与资源选中相同层）
	_ground_item_selection_overlay = Node2D.new()
	_ground_item_selection_overlay.z_index = 51
	_ground_item_selection_overlay.name = "GroundItemSelectionOverlay"
	add_child(_ground_item_selection_overlay)
	
	# 创建指令标记叠加层（z_index 略高于资源，与资源选中同层）
	_designation_overlay = Node2D.new()
	_designation_overlay.z_index = 52
	_designation_overlay.name = "DesignationOverlay"
	add_child(_designation_overlay)
	
	# 连接指令标记变化信号
	if game:
		game.designated_resources_changed.connect(_on_designated_resources_changed)
	
	# 渲染已有的地面物品（加载存档时可能已有数据）
	call_deferred("_render_existing_ground_items")
	
	# 强制触发 _draw()
	queue_redraw()

func _process(_delta):
	# 更新选中的资源节点信息标签（资源量可能因采集而变化）
	if _selected_resource_pos.x >= 0:
		var deposit = world.get_resource_at(_selected_resource_pos)
		if deposit != null and deposit.amount > 0:
			# 只在资源量变化时更新标签文字
			if deposit.amount != _last_resource_amount:
				_last_resource_amount = deposit.amount
				_update_resource_label_text(deposit)

func _render_existing_chunks():
	"""渲染所有已生成的区块"""
	for chunk_pos in world.chunks:
		var chunk = world.chunks[chunk_pos]
		if not chunk.is_generated:
			continue
		var chunk_origin = chunk_pos * World.CHUNK_SIZE
		for tile_pos in chunk.tiles:
			var global_pos = chunk_origin + tile_pos
			_render_tile(global_pos, chunk.tiles[tile_pos])
		for res_pos in chunk.resources:
			var global_pos = chunk_origin + res_pos
			_render_resource(global_pos, chunk.resources[res_pos])
		for bld_pos in chunk.buildings:
			var global_pos = chunk_origin + bld_pos
			var bld_id = chunk.buildings[bld_pos]
			var bld_instance = building_system.get_building_at(global_pos) if building_system else null
			if bld_instance and bld_instance.grid_pos == global_pos:
				_render_building(global_pos, bld_id)

func _render_tile(pos: Vector2i, tile_type: int):
	"""渲染单个瓦片"""
	var key = pos
	if tile_sprites.has(key):
		return
	
	var tex = tile_textures.get(tile_type)
	if tex == null:
		return
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	var pixel_pos = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(world.tile_size / 2.0, world.tile_size / 2.0)
	sprite.position = pixel_pos
	sprite.scale = Vector2(world.tile_size / 32.0, world.tile_size / 32.0)
	sprite.z_index = 0
	add_child(sprite)
	tile_sprites[key] = sprite

func _render_resource(pos: Vector2i, deposit: World.ResourceDeposit):
	"""渲染资源节点"""
	var key = pos
	if resource_sprites.has(key):
		return
	
	var tex = resource_textures.get(deposit.type)
	if tex == null:
		return
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	var pixel_pos = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(world.tile_size / 2.0, world.tile_size / 2.0)
	sprite.position = pixel_pos
	# 资源比瓦片稍大
	sprite.scale = Vector2(0.7, 0.7)
	sprite.z_index = 1
	add_child(sprite)
	resource_sprites[key] = sprite

func render_building_at(pos: Vector2i, building_id: String):
	"""渲染建筑（从外部调用）"""
	_render_building(pos, building_id)

func _render_building(pos: Vector2i, building_id: String):
	"""渲染建筑"""
	var key = pos
	if building_sprites.has(key):
		return
	
	var tex = building_textures.get(building_id)
	if tex == null:
		return
	
	var data = _ID.get_building(building_id)
	var size = data.size if data else Vector2i.ONE
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	# 建筑以格子为单位居中
	var center = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(size.x * world.tile_size / 2.0, size.y * world.tile_size / 2.0)
	sprite.position = center
	# 根据建筑大小调整缩放
	sprite.scale = Vector2(world.tile_size / 32.0, world.tile_size / 32.0)
	sprite.z_index = 2
	add_child(sprite)
	building_sprites[key] = sprite
	
	# 如果建筑未完成，设置半透明并添加进度条
	var bld_instance = building_system.get_building_at(pos) if building_system else null
	if bld_instance != null and not bld_instance.is_completed:
		sprite.modulate = Color(1, 1, 1, 0.45)
		_create_construction_overlay(bld_instance.grid_pos, data, bld_instance.construction_progress)
	
	# 如果已完成且是床铺，显示分配的定居者姓名标签
	if bld_instance != null and bld_instance.is_completed and bld_instance.building_id == "wooden_bed":
		_update_bed_name_label(bld_instance)

func _on_tile_changed(pos: Vector2i, tile_type: int):
	"""瓦片变化时更新渲染"""
	# 移除旧的精灵
	var key = pos
	if tile_sprites.has(key):
		tile_sprites[key].queue_free()
		tile_sprites.erase(key)
	_render_tile(pos, tile_type)

func _on_building_placed(building_id: String, pos: Vector2i):
	"""建筑放置时渲染"""
	_render_building(pos, building_id)

func _on_building_removed(building_id: String, pos: Vector2i):
	"""建筑移除时清除精灵、进度条和床铺姓名标签"""
	_remove_construction_overlay(pos)
	_remove_bed_name_label(pos)
	var data = _ID.get_building(building_id)
	var size = data.size if data else Vector2i.ONE
	for x in size.x:
		for y in size.y:
			clear_building(pos + Vector2i(x, y))

func clear_building(pos: Vector2i):
	"""清除建筑精灵"""
	var key = pos
	if building_sprites.has(key):
		building_sprites[key].queue_free()
		building_sprites.erase(key)

# -------- 建造进度条 --------
func _create_construction_overlay(bld_pos: Vector2i, data, progress: float):
	"""为未完成的建筑创建进度条叠加层"""
	if construction_overlays.has(bld_pos):
		return
	
	var size = data.size if data else Vector2i.ONE
	var bar_width = size.x * world.tile_size - 4.0  # 留2像素边距
	var bar_x = bld_pos.x * world.tile_size + 2.0
	var bar_y = bld_pos.y * world.tile_size + size.y * world.tile_size + 2.0
	
	# 创建进度条容器
	var overlay = Node2D.new()
	overlay.z_index = 10  # 进度条在建筑之上
	add_child(overlay)
	
	# 进度条背景（深色半透明）
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.size = Vector2(bar_width, PROGRESS_BAR_HEIGHT)
	bg.position = Vector2(bar_x, bar_y)
	overlay.add_child(bg)
	
	# 进度条填充（颜色随进度变化）
	var fill = ColorRect.new()
	var ratio = progress / data.work_cost if data and data.work_cost > 0 else 0.0
	fill.color = _get_progress_color(ratio)
	fill.size = Vector2(bar_width * ratio, PROGRESS_BAR_HEIGHT)
	fill.position = Vector2(bar_x, bar_y)
	overlay.add_child(fill)
	
	# 进度条边框
	var border = ColorRect.new()
	border.color = Color(1.0, 1.0, 1.0, 0.3)
	border.size = Vector2(bar_width, 1.0)
	border.position = Vector2(bar_x, bar_y)
	overlay.add_child(border)
	
	construction_overlays[bld_pos] = {
		"overlay": overlay,
		"bg": bg,
		"fill": fill,
		"border": border,
		"bar_width": bar_width,
		"bar_x": bar_x,
		"bar_y": bar_y,
	}

func _update_construction_overlay(bld_pos: Vector2i, progress: float, work_cost: float):
	"""更新建造进度条"""
	if not construction_overlays.has(bld_pos):
		return
	
	var overlay_data = construction_overlays[bld_pos]
	var ratio = progress / work_cost if work_cost > 0 else 0.0
	ratio = clamp(ratio, 0.0, 1.0)
	
	overlay_data.fill.color = _get_progress_color(ratio)
	overlay_data.fill.size.x = overlay_data.bar_width * ratio

func _remove_construction_overlay(bld_pos: Vector2i):
	"""移除建造进度条"""
	if construction_overlays.has(bld_pos):
		var overlay_data = construction_overlays[bld_pos]
		overlay_data.overlay.queue_free()
		construction_overlays.erase(bld_pos)

func _get_progress_color(ratio: float) -> Color:
	"""根据进度比例返回颜色：红→黄→绿"""
	if ratio < 0.3:
		return Color(1.0, 0.3, 0.2, 0.9)  # 红色（初期）
	elif ratio < 0.7:
		return Color(1.0, 0.8, 0.2, 0.9)  # 黄色（中期）
	else:
		return Color(0.3, 1.0, 0.3, 0.9)  # 绿色（接近完成）

# -------- 选中框 --------
func _on_building_selected(bld):
	"""建筑被选中时记录位置并绘制选中框"""
	_selected_building_pos = bld.grid_pos
	_selected_building_size = bld.get_size()
	_update_selection_overlay()

func _on_building_deselected():
	"""建筑取消选中时清除"""
	_selected_building_pos = Vector2i(-1, -1)
	_clear_selection_overlay()

func _on_construction_selected(bld):
	"""在建建筑被选中时记录位置并绘制选中框"""
	_selected_building_pos = bld.grid_pos
	_selected_building_size = bld.get_size()
	_update_selection_overlay()

func _on_construction_deselected():
	"""在建建筑取消选中时清除"""
	_selected_building_pos = Vector2i(-1, -1)
	_clear_selection_overlay()

func _clear_selection_overlay():
	"""清除选中框叠加层"""
	for child in _selection_overlay.get_children():
		child.queue_free()

func _update_selection_overlay():
	"""在叠加层上绘制选中框（确保显示在建筑之上）"""
	_clear_selection_overlay()
	
	if _selected_building_pos.x < 0:
		return
	
	var pixel_pos = Vector2(
		_selected_building_pos.x * world.tile_size,
		_selected_building_pos.y * world.tile_size
	)
	var pixel_size = Vector2(
		_selected_building_size.x * world.tile_size,
		_selected_building_size.y * world.tile_size
	)
	
	# 淡蓝色半透明填充
	var fill = ColorRect.new()
	fill.color = Color(0.3, 0.8, 1.0, 0.12)
	fill.position = pixel_pos
	fill.size = pixel_size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.add_child(fill)
	
	# 蓝色边框（使用4条边）
	var bw = 2.0  # 边框宽度
	# 上边框
	var top = ColorRect.new()
	top.color = Color(0.3, 0.8, 1.0, 0.9)
	top.position = pixel_pos
	top.size = Vector2(pixel_size.x, bw)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.add_child(top)
	# 下边框
	var bottom = ColorRect.new()
	bottom.color = Color(0.3, 0.8, 1.0, 0.9)
	bottom.position = pixel_pos + Vector2(0, pixel_size.y - bw)
	bottom.size = Vector2(pixel_size.x, bw)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.add_child(bottom)
	# 左边框
	var left = ColorRect.new()
	left.color = Color(0.3, 0.8, 1.0, 0.9)
	left.position = pixel_pos
	left.size = Vector2(bw, pixel_size.y)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.add_child(left)
	# 右边框
	var right = ColorRect.new()
	right.color = Color(0.3, 0.8, 1.0, 0.9)
	right.position = pixel_pos + Vector2(pixel_size.x - bw, 0)
	right.size = Vector2(bw, pixel_size.y)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.add_child(right)

# -------- 资源节点选中显示 --------
func _on_resource_selected(pos: Vector2i, deposit):
	"""资源节点被选中时显示选中框和信息标签"""
	_selected_resource_pos = pos
	_last_resource_amount = -1.0  # 重置缓存，确保标签刷新
	# 每次选中都重建叠加层（位置可能改变）
	_build_resource_selection_overlay(deposit)

func _on_resource_deselected():
	"""资源取消选中时清除"""
	_selected_resource_pos = Vector2i(-1, -1)
	_clear_resource_selection_overlay()
	_last_resource_amount = -1.0

func _clear_resource_selection_overlay():
	"""清除资源选中叠加层"""
	for child in _resource_selection_overlay.get_children():
		child.queue_free()
	_resource_info_label = null

func _on_resource_depleted(pos: Vector2i):
	"""资源耗尽时移除精灵并取消选中"""
	# 移除资源精灵（原有逻辑）
	var key = pos
	if resource_sprites.has(key):
		resource_sprites[key].queue_free()
		resource_sprites.erase(key)
	
	# 如果选中的正是这个资源，取消选中
	if _selected_resource_pos == pos:
		var game = get_node("/root/Game")
		if game:
			game._deselect_resource()

func _build_resource_selection_overlay(deposit):
	"""创建资源选中叠加层：选中框 + 资源信息标签（仅首次调用）"""
	_clear_resource_selection_overlay()
	
	if _selected_resource_pos.x < 0:
		return
	
	var pixel_pos = Vector2(
		_selected_resource_pos.x * world.tile_size,
		_selected_resource_pos.y * world.tile_size
	)
	var tile_size_px = world.tile_size
	
	# 黄色半透明填充（与建筑蓝色区分，使用金色系）
	var fill = ColorRect.new()
	fill.color = Color(1.0, 0.85, 0.3, 0.15)
	fill.position = pixel_pos
	fill.size = Vector2(tile_size_px, tile_size_px)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_selection_overlay.add_child(fill)
	
	# 金色边框
	var bw = 2.0
	var border_color = Color(1.0, 0.8, 0.2, 0.9)
	# 上
	var top = ColorRect.new()
	top.color = border_color
	top.position = pixel_pos
	top.size = Vector2(tile_size_px, bw)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_selection_overlay.add_child(top)
	# 下
	var bottom = ColorRect.new()
	bottom.color = border_color
	bottom.position = pixel_pos + Vector2(0, tile_size_px - bw)
	bottom.size = Vector2(tile_size_px, bw)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_selection_overlay.add_child(bottom)
	# 左
	var left = ColorRect.new()
	left.color = border_color
	left.position = pixel_pos
	left.size = Vector2(bw, tile_size_px)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_selection_overlay.add_child(left)
	# 右
	var right = ColorRect.new()
	right.color = border_color
	right.position = pixel_pos + Vector2(tile_size_px - bw, 0)
	right.size = Vector2(bw, tile_size_px)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_selection_overlay.add_child(right)
	
	# 资源信息标签
	_resource_info_label = Label.new()
	_resource_info_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_resource_info_label.add_theme_constant_override("minimum_font_size", 11)
	_resource_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	var label_pos = pixel_pos + Vector2(tile_size_px / 2.0, -18.0)
	_resource_info_label.position = label_pos
	_resource_info_label.size = Vector2(80, 20)
	_resource_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resource_selection_overlay.add_child(_resource_info_label)
	
	# 初始化文字和缓存
	_update_resource_label_text(deposit)

func _update_resource_label_text(deposit):
	"""仅更新资源标签的文字内容"""
	if _resource_info_label == null or not is_instance_valid(_resource_info_label):
		return
	
	var res_names = {
		world.ResourceNodeType.TREE: "树木",
		world.ResourceNodeType.STONE_DEPOSIT: "石矿",
		world.ResourceNodeType.IRON_DEPOSIT: "铁矿",
		world.ResourceNodeType.COPPER_DEPOSIT: "铜矿",
		world.ResourceNodeType.COAL_DEPOSIT: "煤矿",
		world.ResourceNodeType.BERRY_BUSH: "浆果丛",
	}
	
	var res_name = res_names.get(deposit.type, "资源")
	_resource_info_label.text = "%s: %.0f" % [res_name, deposit.amount]

# -------- 地面物品选中显示 --------
func _on_ground_item_selected(pos: Vector2i, _stacks):
	"""地面物品被选中时显示选中框和信息标签"""
	_selected_ground_item_pos = pos
	_build_ground_item_selection_overlay()

func _on_ground_item_deselected():
	"""地面物品取消选中时清除"""
	_selected_ground_item_pos = Vector2i(-1, -1)
	_clear_ground_item_selection_overlay()

func _clear_ground_item_selection_overlay():
	"""清除地面物品选中叠加层"""
	for child in _ground_item_selection_overlay.get_children():
		child.queue_free()
	_ground_item_info_label = null

func _build_ground_item_selection_overlay():
	"""创建地面物品选中叠加层：青色选中框 + 简要标签"""
	_clear_ground_item_selection_overlay()
	
	if _selected_ground_item_pos.x < 0:
		return
	
	var pixel_pos = Vector2(
		_selected_ground_item_pos.x * world.tile_size,
		_selected_ground_item_pos.y * world.tile_size
	)
	var tile_size_px = world.tile_size
	
	# 青色半透明填充（与资源金色、建筑蓝色区分）
	var fill = ColorRect.new()
	fill.color = Color(0.3, 1.0, 0.9, 0.15)
	fill.position = pixel_pos
	fill.size = Vector2(tile_size_px, tile_size_px)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_selection_overlay.add_child(fill)
	
	# 青色边框
	var bw = 2.0
	var border_color = Color(0.3, 1.0, 0.9, 0.9)
	# 上
	var top = ColorRect.new()
	top.color = border_color
	top.position = pixel_pos
	top.size = Vector2(tile_size_px, bw)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_selection_overlay.add_child(top)
	# 下
	var bottom = ColorRect.new()
	bottom.color = border_color
	bottom.position = pixel_pos + Vector2(0, tile_size_px - bw)
	bottom.size = Vector2(tile_size_px, bw)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_selection_overlay.add_child(bottom)
	# 左
	var left = ColorRect.new()
	left.color = border_color
	left.position = pixel_pos
	left.size = Vector2(bw, tile_size_px)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_selection_overlay.add_child(left)
	# 右
	var right = ColorRect.new()
	right.color = border_color
	right.position = pixel_pos + Vector2(tile_size_px - bw, 0)
	right.size = Vector2(bw, tile_size_px)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_selection_overlay.add_child(right)
	
	# 地面物品标签
	_ground_item_info_label = Label.new()
	_ground_item_info_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9))
	_ground_item_info_label.add_theme_constant_override("minimum_font_size", 11)
	_ground_item_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	var label_pos = pixel_pos + Vector2(tile_size_px / 2.0, -18.0)
	_ground_item_info_label.position = label_pos
	_ground_item_info_label.size = Vector2(80, 20)
	_ground_item_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ground_item_info_label.text = "📦 物品"
	_ground_item_selection_overlay.add_child(_ground_item_info_label)

# ==================== 地面物品渲染 ====================

func _render_existing_ground_items():
	"""渲染所有已有的地面物品（加载存档时使用）"""
	if ground_item_texture == null:
		return
	for pos in world.ground_items:
		var stacks = world.ground_items[pos]
		if stacks.is_empty():
			continue
		_render_ground_item(pos)

func _render_ground_item(pos: Vector2i):
	"""在指定网格位置创建地面物品精灵"""
	var key = pos
	if ground_item_sprites.has(key):
		return
	if ground_item_texture == null:
		return
	
	var sprite = Sprite2D.new()
	sprite.texture = ground_item_texture
	var pixel_pos = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(world.tile_size / 2.0, world.tile_size / 2.0 + 2.0)
	sprite.position = pixel_pos
	sprite.scale = Vector2(0.6, 0.6)
	sprite.z_index = 1.5  # 在资源(1)和建筑(2)之间，高于地形(0)
	add_child(sprite)
	ground_item_sprites[key] = sprite

func _remove_ground_item(pos: Vector2i):
	"""移除指定位置的地面物品精灵"""
	var key = pos
	if ground_item_sprites.has(key):
		ground_item_sprites[key].queue_free()
		ground_item_sprites.erase(key)

func _clear_all_ground_items():
	"""清除所有地面物品精灵"""
	for key in ground_item_sprites.keys():
		ground_item_sprites[key].queue_free()
	ground_item_sprites.clear()

func _on_ground_items_changed(grid_pos: Vector2i):
	"""地面物品变化时更新精灵"""
	var stacks = world.get_ground_items_at(grid_pos)
	if stacks.is_empty():
		_remove_ground_item(grid_pos)
	else:
		_render_ground_item(grid_pos)

# -------- 信号处理 --------
func _on_building_completed(pos: Vector2i):
	"""建筑完成时：移除进度条、恢复不透明，如果是床则更新姓名标签"""
	_remove_construction_overlay(pos)
	
	# 恢复该建筑所有格子的精灵为不透明
	var bld = building_system.get_building_at(pos) if building_system else null
	if bld:
		var data = bld.get_data()
		var size = data.size if data else Vector2i.ONE
		for x in size.x:
			for y in size.y:
				var grid_pos = bld.grid_pos + Vector2i(x, y)
				if building_sprites.has(grid_pos):
					building_sprites[grid_pos].modulate = Color(1, 1, 1, 1)
		
		# 如果是床，显示分配的定居者姓名
		if bld.building_id == "wooden_bed":
			_update_bed_name_label(bld)

func _update_bed_name_label(bld):
	"""在床铺下方显示分配的定居者姓名"""
	var bld_pos = bld.grid_pos
	
	# 先移除旧标签
	if _bed_name_labels.has(bld_pos):
		if is_instance_valid(_bed_name_labels[bld_pos]):
			_bed_name_labels[bld_pos].queue_free()
		_bed_name_labels.erase(bld_pos)
	
	if bld.assigned_settler_name == "":
		return
	
	# 创建姓名标签
	var label = Label.new()
	label.text = bld.assigned_settler_name
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	label.add_theme_constant_override("minimum_font_size", 10)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	
	var size = bld.get_size()
	var center_x = bld_pos.x * world.tile_size + size.x * world.tile_size / 2.0
	var label_y = bld_pos.y * world.tile_size + size.y * world.tile_size + 2.0
	label.position = Vector2(center_x - 50.0, label_y)  # 预留100px宽度居中
	label.size = Vector2(100, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 15  # 在建筑和进度条之上
	add_child(label)
	_bed_name_labels[bld_pos] = label

func _remove_bed_name_label(bld_pos: Vector2i):
	"""移除床铺姓名标签"""
	if _bed_name_labels.has(bld_pos):
		if is_instance_valid(_bed_name_labels[bld_pos]):
			_bed_name_labels[bld_pos].queue_free()
		_bed_name_labels.erase(bld_pos)

func _on_construction_progress_updated(pos: Vector2i, progress: float, work_cost: float):
	"""建造进度更新时刷新进度条"""
	_update_construction_overlay(pos, progress, work_cost)

func clear_all():
	"""清除所有精灵"""
	for s in tile_sprites.values():
		s.queue_free()
	tile_sprites.clear()
	for s in resource_sprites.values():
		s.queue_free()
	resource_sprites.clear()
	for s in building_sprites.values():
		s.queue_free()
	building_sprites.clear()
	
	# 清除所有建造进度条
	for key in construction_overlays:
		construction_overlays[key].overlay.queue_free()
	construction_overlays.clear()
	
	# 清除床铺姓名标签
	for key in _bed_name_labels:
		if is_instance_valid(_bed_name_labels[key]):
			_bed_name_labels[key].queue_free()
	_bed_name_labels.clear()
	
	# 清除选中框
	_selected_building_pos = Vector2i(-1, -1)
	_clear_selection_overlay()
	
	# 清除资源选中叠加层
	_selected_resource_pos = Vector2i(-1, -1)
	_clear_resource_selection_overlay()
	_resource_info_label = null
	_last_resource_amount = -1.0
	
	# 清除指令标记
	_clear_all_designation_overlays()

# ==================== 指令标记视觉渲染 ====================

func _on_designated_resources_changed():
	"""指令标记变化时，增量更新标记覆盖层"""
	_rebuild_designation_overlays()

func _rebuild_designation_overlays():
	"""重建所有指令标记覆盖层"""
	_clear_all_designation_overlays()
	
	var game = get_node_or_null("/root/Game")
	if game == null:
		return
	
	var designated = game.designated_resources
	if designated.is_empty():
		return
	
	for key in designated:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		var work_type = designated[key]
		_create_designation_overlay(grid_pos, work_type)

func _create_designation_overlay(grid_pos: Vector2i, work_type: int):
	"""为指定位置的资源创建图标标记"""
	if _designation_sprites.has("%d,%d" % [grid_pos.x, grid_pos.y]):
		return
	
	var icon_text = DESIGNATION_ICONS.get(work_type, "❓")
	
	var pixel_center = Vector2(
		grid_pos.x * world.tile_size + world.tile_size / 2.0,
		grid_pos.y * world.tile_size + world.tile_size / 2.0
	)
	
	# 图标标签
	var label = Label.new()
	label.text = icon_text
	label.add_theme_constant_override("minimum_font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	# 标签居中定位
	var text_size = label.get_combined_minimum_size()
	label.position = pixel_center - text_size / 2.0
	label.size = text_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_designation_overlay.add_child(label)
	_designation_sprites["%d,%d" % [grid_pos.x, grid_pos.y]] = label

func _create_preview_icon(grid_pos: Vector2i, work_type: int):
	"""为框选预览创建半透明图标"""
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	if _designation_preview_sprites.has(key):
		return
	# 如果已是正式标记，不重复显示预览
	if _designation_sprites.has(key):
		return
	
	var icon_text = DESIGNATION_ICONS.get(work_type, "❓")
	var pixel_center = Vector2(
		grid_pos.x * world.tile_size + world.tile_size / 2.0,
		grid_pos.y * world.tile_size + world.tile_size / 2.0
	)
	
	var label = Label.new()
	label.text = icon_text
	label.add_theme_constant_override("minimum_font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	# 预览半透明
	label.modulate = Color(1, 1, 1, 0.45)
	var text_size = label.get_combined_minimum_size()
	label.position = pixel_center - text_size / 2.0
	label.size = text_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_designation_overlay.add_child(label)
	_designation_preview_sprites[key] = label

func update_designation_preview(from_grid: Vector2i, to_grid: Vector2i, work_type: int):
	"""根据框选矩形更新标记预览——显示矩形内匹配资源的半透明图标"""
	_clear_designation_preview()
	
	if from_grid.x < 0 or to_grid.x < 0:
		return
	
	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)
	
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var pos = Vector2i(x, y)
			var dep = world.get_resource_at(pos) if world else null
			if dep != null and dep.amount > 0:
				if _is_resource_match_work_type(dep.type, work_type):
					_create_preview_icon(pos, work_type)
			# 搬运模式也预览地面物品
			if work_type == 6 and world:  # HAULING
				var stacks = world.get_ground_items_at(pos)
				if not stacks.is_empty():
					_create_preview_icon(pos, work_type)

func _clear_designation_preview():
	"""清除框选预览图标"""
	for key in _designation_preview_sprites:
		if is_instance_valid(_designation_preview_sprites[key]):
			_designation_preview_sprites[key].queue_free()
	_designation_preview_sprites.clear()

func _clear_all_designation_overlays():
	"""清除所有指令标记覆盖层"""
	for key in _designation_sprites:
		if is_instance_valid(_designation_sprites[key]):
			_designation_sprites[key].queue_free()
	_designation_sprites.clear()
	_clear_designation_preview()

func _is_resource_match_work_type(resource_type: int, work_type: int) -> bool:
	"""检查资源类型是否匹配指定的工作类型（与 Game.gd 保持同步）"""
	match work_type:
		0:  # MINING
			return resource_type in [
				World.ResourceNodeType.STONE_DEPOSIT,
				World.ResourceNodeType.IRON_DEPOSIT,
				World.ResourceNodeType.COPPER_DEPOSIT,
				World.ResourceNodeType.COAL_DEPOSIT,
			]
		1:  # WOODCUTTING
			return resource_type == World.ResourceNodeType.TREE
		5:  # FARMING
			return resource_type == World.ResourceNodeType.BERRY_BUSH
		_:
			return false
