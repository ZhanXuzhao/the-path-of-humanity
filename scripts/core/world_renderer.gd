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

# 当前可见的精灵节点
var tile_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var resource_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var building_sprites: Dictionary = {}  # Vector2i -> Sprite2D

# 建造进度条
var construction_overlays: Dictionary = {}  # Vector2i(建筑主格) -> Node2D(进度条容器)
var PROGRESS_BAR_HEIGHT: float = 6.0

# 选中框
var _selected_building_pos: Vector2i = Vector2i(-1, -1)
var _selected_building_size: Vector2i = Vector2i.ONE
var _selection_overlay: Node2D  # 单独的高层级选中框叠加层

func _ready():
	# 使用 TextureGenerator 生成所有纹理
	var all_textures = _TG.generate_all()
	tile_textures = all_textures["tiles"]
	resource_textures = all_textures["resources"]
	building_textures = all_textures["buildings"]
	settler_texture = all_textures["character"]["player_young_man"]
	
	# 连接信号
	world.tile_changed.connect(_on_tile_changed)
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
	
	# 延迟一帧渲染，确保 Game._ready() 已完成区块生成
	call_deferred("_render_existing_chunks")
	
	# 创建选中框叠加层（在建筑之上显示）
	_selection_overlay = Node2D.new()
	_selection_overlay.z_index = 100
	_selection_overlay.name = "SelectionOverlay"
	add_child(_selection_overlay)
	
	# 强制触发 _draw()
	queue_redraw()



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

func _on_tile_changed(pos: Vector2i, tile_type: int):
	"""瓦片变化时更新渲染"""
	# 移除旧的精灵
	var key = pos
	if tile_sprites.has(key):
		tile_sprites[key].queue_free()
		tile_sprites.erase(key)
	_render_tile(pos, tile_type)

func _on_resource_depleted(pos: Vector2i):
	"""资源耗尽时移除精灵"""
	var key = pos
	if resource_sprites.has(key):
		resource_sprites[key].queue_free()
		resource_sprites.erase(key)

func _on_building_placed(building_id: String, pos: Vector2i):
	"""建筑放置时渲染"""
	_render_building(pos, building_id)

func _on_building_removed(building_id: String, pos: Vector2i):
	"""建筑移除时清除精灵和进度条"""
	_remove_construction_overlay(pos)
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

# -------- 信号处理 --------
func _on_building_completed(pos: Vector2i):
	"""建筑完成时：移除进度条、恢复不透明"""
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
	
	# 清除选中框
	_selected_building_pos = Vector2i(-1, -1)
	_clear_selection_overlay()
