# 小地图 - Minimap
# 在屏幕右上角显示世界缩略图，包含地形、建筑、定居者和相机视口
extends Control
class_name Minimap

# 小地图尺寸
const MINIMAP_SIZE := 200
const MARGIN := 10

# 瓦片颜色映射
const TILE_COLORS = {
	World.TileType.GRASS: Color(0.35, 0.55, 0.20),      # 草地 - 绿色
	World.TileType.DIRT: Color(0.55, 0.42, 0.22),        # 泥土 - 棕色
	World.TileType.SAND: Color(0.76, 0.70, 0.50),        # 沙地 - 浅黄
	World.TileType.WATER: Color(0.20, 0.40, 0.60),       # 水域 - 蓝色
	World.TileType.DEEP_WATER: Color(0.10, 0.25, 0.45),  # 深水 - 深蓝
	World.TileType.STONE: Color(0.45, 0.45, 0.45),       # 岩石 - 灰色
	World.TileType.FOREST: Color(0.15, 0.35, 0.10),      # 森林 - 深绿
	World.TileType.MOUNTAIN: Color(0.35, 0.30, 0.25),    # 山脉 - 深棕
	World.TileType.SNOW: Color(0.90, 0.92, 0.95),        # 雪地 - 白色
	World.TileType.ROAD: Color(0.65, 0.60, 0.50),        # 道路 - 浅灰棕
	World.TileType.FLOOR: Color(0.50, 0.45, 0.35),       # 地板 - 中棕
	World.TileType.WALL: Color(0.30, 0.25, 0.20),        # 墙壁 - 深灰棕
}

# 资源颜色
const RESOURCE_COLORS = {
	World.ResourceNodeType.TREE: Color(0.0, 0.5, 0.0),
	World.ResourceNodeType.STONE_DEPOSIT: Color(0.5, 0.5, 0.5),
	World.ResourceNodeType.IRON_DEPOSIT: Color(0.8, 0.4, 0.2),
	World.ResourceNodeType.COPPER_DEPOSIT: Color(0.8, 0.5, 0.2),
	World.ResourceNodeType.COAL_DEPOSIT: Color(0.2, 0.2, 0.2),
	World.ResourceNodeType.BERRY_BUSH: Color(0.8, 0.2, 0.2),
}

var _world: World
var _game: Game
var _camera: Camera2D
var _bg_texture: ImageTexture = null
var _bg_image: Image = null
var _needs_redraw := true

# 世界包围盒缓存（瓦片坐标），用于 _draw 和点击导航
var _world_min_tile := Vector2i.ZERO
var _world_max_tile := Vector2i.ZERO
var _world_tile_w := 1
var _world_tile_h := 1

func _ready():
	# 设置位置和大小
	size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	position = Vector2(
		get_viewport_rect().size.x - MINIMAP_SIZE - MARGIN,
		MARGIN
	)
	
	# 等待场景完全就绪后获取引用
	call_deferred("_init_refs")

func _init_refs():
	_game = get_node("/root/Game")
	if not _game:
		return
	
	_world = _game.world
	_camera = _game.camera
	
	if not _world:
		return
	
	# 当世界变化时重新生成背景
	_world.tile_changed.connect(_on_tile_changed)
	
	# 连接建筑信号
	if _game.building_system:
		_game.building_system.building_placed.connect(_on_building_changed)
		_game.building_system.building_removed.connect(_on_building_changed)
	
	# 初始渲染
	call_deferred("_rebuild_bg_texture")
	
	# 监听窗口大小变化
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized():
	position = Vector2(
		get_viewport_rect().size.x - MINIMAP_SIZE - MARGIN,
		MARGIN
	)

func _process(_delta):
	# 每帧重绘动态元素（相机视口、定居者位置）
	if _world and _game and _camera:
		queue_redraw()

func _on_tile_changed(_pos: Vector2i, _tile_type: int):
	_needs_redraw = true
	call_deferred("_rebuild_bg_texture")

func _on_building_changed(_id: String, _pos: Vector2i):
	_needs_redraw = true
	call_deferred("_rebuild_bg_texture")

func _rebuild_bg_texture():
	if not _world:
		return
	
	# 计算所有已生成区块的包围盒（瓦片坐标）
	var min_tile := Vector2i.ZERO
	var max_tile := Vector2i.ZERO
	var first := true
	for chunk_pos in _world.chunks:
		var chunk = _world.chunks[chunk_pos]
		if not chunk.is_generated:
			continue
		var chunk_origin = chunk_pos * World.CHUNK_SIZE
		var chunk_end = chunk_origin + Vector2i(World.CHUNK_SIZE - 1, World.CHUNK_SIZE - 1)
		if first:
			min_tile = chunk_origin
			max_tile = chunk_end
			first = false
		else:
			min_tile.x = min(min_tile.x, chunk_origin.x)
			min_tile.y = min(min_tile.y, chunk_origin.y)
			max_tile.x = max(max_tile.x, chunk_end.x)
			max_tile.y = max(max_tile.y, chunk_end.y)
	
	if first:
		return  # 没有已生成的区块
	
	# 缓存包围盒供 _draw 和点击导航使用
	_world_min_tile = min_tile
	_world_max_tile = max_tile
	_world_tile_w = max_tile.x - min_tile.x + 1
	_world_tile_h = max_tile.y - min_tile.y + 1
	
	var img = Image.create(MINIMAP_SIZE, MINIMAP_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var scale_x = float(MINIMAP_SIZE) / float(_world_tile_w)
	var scale_y = float(MINIMAP_SIZE) / float(_world_tile_h)
	
	# 绘制已生成的区块
	for chunk_pos in _world.chunks:
		var chunk = _world.chunks[chunk_pos]
		if not chunk.is_generated:
			continue
		
		var chunk_origin = chunk_pos * World.CHUNK_SIZE
		
		for tile_pos in chunk.tiles:
			var global_pos = chunk_origin + tile_pos
			var tile_type = chunk.tiles[tile_pos]
			var color = TILE_COLORS.get(tile_type, Color(0.3, 0.3, 0.3))
			
			# 映射到小地图坐标
			var lx = global_pos.x - min_tile.x
			var ly = global_pos.y - min_tile.y
			
			var px = int(lx * scale_x)
			var py = int(ly * scale_y)
			var px_end = int((lx + 1) * scale_x)
			var py_end = int((ly + 1) * scale_y)
			
			# 确保至少1像素宽并限制在范围内
			px_end = clampi(px_end, px + 1, MINIMAP_SIZE)
			py_end = clampi(py_end, py + 1, MINIMAP_SIZE)
			px = clampi(px, 0, MINIMAP_SIZE - 1)
			py = clampi(py, 0, MINIMAP_SIZE - 1)
			
			for x in range(px, px_end):
				for y in range(py, py_end):
					img.set_pixel(x, y, color)
		
		# 绘制资源
		for res_pos in chunk.resources:
			var global_pos = chunk_origin + res_pos
			var deposit = chunk.resources[res_pos]
			var res_color = RESOURCE_COLORS.get(deposit.type, Color(1, 1, 0))
			
			var lx = global_pos.x - min_tile.x
			var ly = global_pos.y - min_tile.y
			var px = clampi(int(lx * scale_x), 0, MINIMAP_SIZE - 1)
			var py = clampi(int(ly * scale_y), 0, MINIMAP_SIZE - 1)
			img.set_pixel(px, py, res_color)
		
		# 绘制建筑
		for bld_pos in chunk.buildings:
			var global_pos = chunk_origin + bld_pos
			var bld_color = Color(0.8, 0.6, 0.3)  # 建筑用金色
			
			var lx = global_pos.x - min_tile.x
			var ly = global_pos.y - min_tile.y
			
			var px = clampi(int(lx * scale_x), 0, MINIMAP_SIZE - 1)
			var py = clampi(int(ly * scale_y), 0, MINIMAP_SIZE - 1)
			var px_end = clampi(int((lx + 1) * scale_x), px + 1, MINIMAP_SIZE)
			var py_end = clampi(int((ly + 1) * scale_y), py + 1, MINIMAP_SIZE)
			
			for x in range(px, px_end):
				for y in range(py, py_end):
					img.set_pixel(x, y, bld_color)
	
	_bg_image = img
	_bg_texture = ImageTexture.create_from_image(img)
	_needs_redraw = false
	queue_redraw()

func _draw():
	if not _world or not _game or not _camera:
		return
	
	var world_pixel_w = _world_tile_w * _world.tile_size
	var world_pixel_h = _world_tile_h * _world.tile_size
	var origin_offset = Vector2(_world_min_tile.x * _world.tile_size, _world_min_tile.y * _world.tile_size)
	
	# 绘制背景纹理
	if _bg_texture:
		draw_texture(_bg_texture, Vector2.ZERO)
	else:
		# 背景
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12, 0.9))
	
	# 绘制边框
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5), false, 1.0)
	
	# 缩放因子：世界像素 → 小地图像素
	var scale_x = float(MINIMAP_SIZE) / float(world_pixel_w)
	var scale_y = float(MINIMAP_SIZE) / float(world_pixel_h)
	
	# 绘制相机视口矩形
	var view_rect = _get_camera_world_rect()
	var offset_pos = view_rect.position - origin_offset
	var cam_pos = offset_pos * Vector2(scale_x, scale_y)
	var cam_size = view_rect.size * Vector2(scale_x, scale_y)
	draw_rect(Rect2(cam_pos, cam_size), Color(1, 1, 1, 0.5), false, 1.5)
	
	# 绘制定居者
	for s in _game.settlers:
		if not is_instance_valid(s):
			continue
		var lx = s.position.x - origin_offset.x
		var ly = s.position.y - origin_offset.y
		var mx = lx * scale_x
		var my = ly * scale_y
		if mx >= 0 and mx < MINIMAP_SIZE and my >= 0 and my < MINIMAP_SIZE:
			draw_circle(Vector2(mx, my), 2.0, Color(0.3, 0.8, 1.0, 0.9))

func _get_camera_world_rect() -> Rect2:
	"""获取相机在世界空间中的视口矩形"""
	var view_size = get_viewport_rect().size
	var zoom = _camera.zoom
	
	# 相机中心位置
	var cam_center = _camera.position
	
	# 视口大小（世界坐标）
	# 当 zoom > 1（放大）时看到的世界范围变小，所以用除法
	var view_w = view_size.x / zoom.x
	var view_h = view_size.y / zoom.y
	
	return Rect2(
		Vector2(cam_center.x - view_w / 2.0, cam_center.y - view_h / 2.0),
		Vector2(view_w, view_h)
	)

func _gui_input(event):
	"""处理小地图点击事件"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_navigate_to_click(event.position)
		accept_event()

func _navigate_to_click(click_pos: Vector2):
	"""点击小地图，将相机移动到对应位置"""
	if not _world or not _camera:
		return
	
	var world_pixel_w = _world_tile_w * _world.tile_size
	var world_pixel_h = _world_tile_h * _world.tile_size
	var origin_offset = Vector2(_world_min_tile.x * _world.tile_size, _world_min_tile.y * _world.tile_size)
	
	var scale_x = float(MINIMAP_SIZE) / float(world_pixel_w)
	var scale_y = float(MINIMAP_SIZE) / float(world_pixel_h)
	
	var local_x = click_pos.x / scale_x
	var local_y = click_pos.y / scale_y
	
	_camera.position = Vector2(local_x + origin_offset.x, local_y + origin_offset.y)
