# 纹理生成器 - Texture Generator
# 在运行时生成游戏所需的所有纹理，无需外部图像文件
extends Node
class_name TextureGenerator

const TILE_SIZE := 32
const TILE_HALF := 16

# 生成所有纹理并返回字典
static func generate_all() -> Dictionary:
	var textures = {}
	textures["tiles"] = _generate_tiles()
	textures["resources"] = _generate_resources()
	textures["buildings"] = _generate_buildings()
	textures["character"] = _generate_character()
	return textures

# -------- 地形瓦片 --------
static func _generate_tiles() -> Dictionary:
	var tiles = {}
	
	# 草地 - 绿色
	tiles[World.TileType.GRASS] = _make_tile(Color("#5a8f3c"), [
		{ "type": "circle", "x": 8, "y": 10, "r": 1.5, "color": Color("#6da84a"), "a": 0.5 },
		{ "type": "circle", "x": 20, "y": 6, "r": 1, "color": Color("#6da84a"), "a": 0.4 },
		{ "type": "circle", "x": 14, "y": 22, "r": 1.5, "color": Color("#6da84a"), "a": 0.5 },
		{ "type": "circle", "x": 24, "y": 18, "r": 1, "color": Color("#6da84a"), "a": 0.3 },
	])
	
	# 泥土 - 棕色
	tiles[World.TileType.DIRT] = _make_tile(Color("#8b6b3a"), [
		{ "type": "circle", "x": 10, "y": 8, "r": 2, "color": Color("#7a5e30"), "a": 0.4 },
		{ "type": "circle", "x": 22, "y": 14, "r": 1.5, "color": Color("#7a5e30"), "a": 0.3 },
		{ "type": "circle", "x": 8, "y": 20, "r": 2.5, "color": Color("#7a5e30"), "a": 0.35 },
		{ "type": "circle", "x": 24, "y": 24, "r": 1.8, "color": Color("#7a5e30"), "a": 0.3 },
	])
	
	# 沙地 - 黄色
	tiles[World.TileType.SAND] = _make_tile(Color("#d4b86a"), [
		{ "type": "circle", "x": 6, "y": 12, "r": 1, "color": Color("#c9ae5e"), "a": 0.5 },
		{ "type": "circle", "x": 16, "y": 6, "r": 1.2, "color": Color("#c9ae5e"), "a": 0.4 },
		{ "type": "circle", "x": 26, "y": 20, "r": 0.8, "color": Color("#c9ae5e"), "a": 0.5 },
		{ "type": "circle", "x": 12, "y": 26, "r": 1, "color": Color("#c9ae5e"), "a": 0.4 },
	])
	
	# 水域 - 蓝色波纹
	tiles[World.TileType.WATER] = _make_tile(Color("#3a7ebf"), [
		{ "type": "wave", "y": 12, "color": Color("#5a9ed4"), "a": 0.4 },
		{ "type": "wave", "y": 20, "color": Color("#5a9ed4"), "a": 0.3 },
	])
	
	# 深水 - 深蓝
	tiles[World.TileType.DEEP_WATER] = _make_tile(Color("#1a4a7a"), [
		{ "type": "wave", "y": 10, "color": Color("#2a5a8a"), "a": 0.35 },
		{ "type": "wave", "y": 18, "color": Color("#2a5a8a"), "a": 0.25 },
	])
	
	# 岩石 - 灰色
	tiles[World.TileType.STONE] = _make_tile(Color("#7a7a7a"), [
		{ "type": "rect", "x": 4, "y": 4, "w": 10, "h": 8, "color": Color("#8a8a8a"), "a": 0.4 },
		{ "type": "rect", "x": 18, "y": 2, "w": 8, "h": 6, "color": Color("#8a8a8a"), "a": 0.35 },
		{ "type": "rect", "x": 8, "y": 16, "w": 14, "h": 6, "color": Color("#8a8a8a"), "a": 0.3 },
		{ "type": "rect", "x": 3, "y": 22, "w": 7, "h": 7, "color": Color("#8a8a8a"), "a": 0.35 },
	])
	
	# 森林 - 深绿树木
	tiles[World.TileType.FOREST] = _make_tile(Color("#3d7a2e"), [
		{ "type": "tree", "x": 8, "color": Color("#2a6b1a"), "a": 0.65 },
		{ "type": "tree", "x": 22, "color": Color("#2a6b1a"), "a": 0.6 },
		{ "type": "tree", "x": 14, "color": Color("#2a6b1a"), "a": 0.55 },
	])
	
	# 山脉 - 灰色山峰
	tiles[World.TileType.MOUNTAIN] = _make_tile(Color("#5a5a5a"), [
		{ "type": "mountain", "color": Color("#6a6a6a"), "a": 0.6 },
	])
	
	# 雪地 - 白色
	tiles[World.TileType.SNOW] = _make_tile(Color("#d8dce0"), [
		{ "type": "circle", "x": 8, "y": 6, "r": 2, "color": Color("#e8ecf0"), "a": 0.5 },
		{ "type": "circle", "x": 22, "y": 10, "r": 1.5, "color": Color("#e8ecf0"), "a": 0.4 },
		{ "type": "circle", "x": 5, "y": 22, "r": 2.5, "color": Color("#e8ecf0"), "a": 0.45 },
		{ "type": "circle", "x": 26, "y": 24, "r": 2, "color": Color("#e8ecf0"), "a": 0.35 },
	])
	
	# 道路 - 浅棕条纹
	tiles[World.TileType.ROAD] = _make_tile(Color("#8a7a5a"), [
		{ "type": "line", "y": 10, "color": Color("#9a8a6a"), "a": 0.3 },
		{ "type": "line", "y": 18, "color": Color("#9a8a6a"), "a": 0.25 },
		{ "type": "line", "y": 26, "color": Color("#9a8a6a"), "a": 0.2 },
	])
	
	# 地板 - 浅色棋盘
	tiles[World.TileType.FLOOR] = _make_tile(Color("#a08860"), [
		{ "type": "rect", "x": 0, "y": 0, "w": 16, "h": 16, "color": Color("#b09870"), "a": 0.2 },
		{ "type": "rect", "x": 16, "y": 16, "w": 16, "h": 16, "color": Color("#b09870"), "a": 0.15 },
	])
	
	# 墙壁 - 深灰砖
	tiles[World.TileType.WALL] = _make_tile(Color("#6a6a5a"), [
		{ "type": "rect", "x": 2, "y": 2, "w": 13, "h": 13, "color": Color("#7a7a6a"), "a": 0.3 },
		{ "type": "rect", "x": 17, "y": 2, "w": 13, "h": 13, "color": Color("#7a7a6a"), "a": 0.3 },
		{ "type": "rect", "x": 2, "y": 17, "w": 13, "h": 13, "color": Color("#7a7a6a"), "a": 0.3 },
		{ "type": "rect", "x": 17, "y": 17, "w": 13, "h": 13, "color": Color("#7a7a6a"), "a": 0.3 },
		{ "type": "line_hv", "x": 16, "y": 16, "color": Color("#5a5a4a"), "a": 0.4 },
	])
	
	return tiles

# -------- 资源节点 --------
static func _generate_resources() -> Dictionary:
	var res = {}
	
	# 树木 - 绿色三角形 + 棕色树干
	res[World.ResourceNodeType.TREE] = _make_sprite(32, 48, func(img):
		# 树干
		_draw_rect(img, 13, 28, 6, 18, Color("#6a4a2a"))
		# 树冠三层
		_draw_polygon(img, [Vector2(16, 2), Vector2(4, 20), Vector2(28, 20)], Color("#2a7a1a"))
		_draw_polygon(img, [Vector2(16, 8), Vector2(6, 24), Vector2(26, 24)], Color("#338822"))
		_draw_polygon(img, [Vector2(16, 14), Vector2(8, 28), Vector2(24, 28)], Color("#3a9928"))
	)
	
	# 石头矿 - 灰色方块
	res[World.ResourceNodeType.STONE_DEPOSIT] = _make_sprite(32, 24, func(img):
		_draw_ellipse(img, 16, 18, 11, 6, Color("#7a7a7a"))
		_draw_rect(img, 8, 6, 8, 7, Color("#8a8a8a"))
		_draw_rect(img, 16, 8, 7, 6, Color("#7a7a7a"))
	)
	
	# 铁矿 - 褐色
	res[World.ResourceNodeType.IRON_DEPOSIT] = _make_sprite(32, 24, func(img):
		_draw_ellipse(img, 16, 18, 11, 6, Color("#8a7a5a"))
		_draw_rect(img, 6, 4, 8, 8, Color("#b08040"))
		_draw_rect(img, 17, 6, 7, 7, Color("#a07030"))
	)
	
	# 铜矿 - 铜色
	res[World.ResourceNodeType.COPPER_DEPOSIT] = _make_sprite(32, 24, func(img):
		_draw_ellipse(img, 16, 18, 11, 6, Color("#7a6a5a"))
		_draw_rect(img, 6, 4, 8, 8, Color("#c08040"))
		_draw_rect(img, 17, 6, 7, 7, Color("#b07030"))
	)
	
	# 煤矿 - 黑色
	res[World.ResourceNodeType.COAL_DEPOSIT] = _make_sprite(32, 24, func(img):
		_draw_ellipse(img, 16, 18, 11, 6, Color("#4a4a4a"))
		_draw_rect(img, 7, 5, 7, 7, Color("#1a1a1a"))
		_draw_rect(img, 17, 7, 6, 6, Color("#2a2a2a"))
	)
	
	# 浆果丛 - 绿色带红点
	res[World.ResourceNodeType.BERRY_BUSH] = _make_sprite(32, 24, func(img):
		_draw_ellipse(img, 16, 18, 10, 5, Color("#3a6a2a"))
		_draw_ellipse(img, 12, 14, 6, 5, Color("#4a7a30"))
		_draw_ellipse(img, 20, 12, 5, 4, Color("#4a7a30"))
		_draw_circle_fill(img, 12, 12, 2, Color("#cc2244"))
		_draw_circle_fill(img, 18, 10, 1.8, Color("#dd3355"))
		_draw_circle_fill(img, 16, 14, 1.5, Color("#bb1133"))
	)
	
	return res

# -------- 建筑 --------
static func _generate_buildings() -> Dictionary:
	var bld = {}
	
	bld["storage_rack"] = _make_sprite(32, 32, func(img):
		_draw_rect(img, 4, 4, 24, 6, Color("#6a4a2a"))
		_draw_rect(img, 4, 14, 24, 6, Color("#6a4a2a"))
		_draw_rect(img, 4, 24, 24, 5, Color("#6a4a2a"))
		_draw_rect(img, 6, 4, 20, 6, Color("#8a6a3a"))
		_draw_rect(img, 6, 14, 20, 6, Color("#8a6a3a"))
		_draw_rect(img, 6, 24, 20, 5, Color("#8a6a3a"))
		_draw_rect(img, 3, 4, 2, 25, Color("#5a3a1a"))
		_draw_rect(img, 27, 4, 2, 25, Color("#5a3a1a"))
	)
	
	bld["campfire"] = _make_sprite(32, 32, func(img):
		_draw_rect(img, 12, 22, 8, 8, Color("#5a3a1a"))
		_draw_polygon(img, [Vector2(16, 4), Vector2(8, 18), Vector2(24, 18)], Color("#ff6633"))
		_draw_polygon(img, [Vector2(16, 8), Vector2(10, 20), Vector2(22, 20)], Color("#ffaa33"))
		_draw_polygon(img, [Vector2(16, 12), Vector2(12, 22), Vector2(20, 22)], Color("#ffdd44"))
	)
	
	bld["cooking_stove"] = _make_sprite(32, 32, func(img):
		_draw_rect(img, 4, 8, 24, 20, Color("#5a4a3a"))
		_draw_rect(img, 4, 8, 24, 3, Color("#6a5a4a"))
		_draw_rect(img, 8, 14, 8, 6, Color("#3a2a1a"))
		_draw_rect(img, 18, 14, 6, 6, Color("#3a2a1a"))
		_draw_rect(img, 9, 15, 6, 4, Color("#cc4422"))
		_draw_rect(img, 19, 15, 4, 4, Color("#cc4422"))
	)
	
	bld["wall"] = _make_sprite(32, 32, func(img):
		_draw_rect(img, 2, 2, 28, 28, Color("#7a7a6a"))
		_draw_rect(img, 2, 2, 28, 4, Color("#8a8a7a"))
		_draw_rect(img, 2, 2, 4, 28, Color("#8a8a7a"))
		_draw_rect(img, 26, 2, 4, 28, Color("#6a6a5a"))
		_draw_rect(img, 2, 26, 28, 4, Color("#6a6a5a"))
	)
	
	# 工作台 (64x48)
	bld["workbench"] = _make_sprite(64, 48, func(img):
		_draw_rect(img, 4, 24, 56, 20, Color("#6a4a2a"))
		_draw_rect(img, 4, 24, 56, 4, Color("#7a5a3a"))
		_draw_rect(img, 8, 12, 48, 14, Color("#8a6a3a"))
		_draw_rect(img, 8, 12, 48, 3, Color("#9a7a4a"))
		_draw_rect(img, 8, 44, 6, 4, Color("#5a3a1a"))
		_draw_rect(img, 22, 44, 6, 4, Color("#5a3a1a"))
		_draw_rect(img, 36, 44, 6, 4, Color("#5a3a1a"))
		_draw_rect(img, 50, 44, 6, 4, Color("#5a3a1a"))
	)
	
	# 熔炉 (64x32)
	bld["furnace"] = _make_sprite(64, 32, func(img):
		_draw_rect(img, 8, 4, 48, 24, Color("#6a5a3a"))
		_draw_rect(img, 8, 4, 48, 4, Color("#7a6a4a"))
		_draw_rect(img, 12, 10, 16, 14, Color("#4a3a1a"))
		_draw_rect(img, 36, 10, 16, 14, Color("#4a3a1a"))
		_draw_rect(img, 14, 12, 12, 10, Color("#cc4422"))
		_draw_rect(img, 38, 12, 12, 10, Color("#cc4422"))
		_draw_rect(img, 28, 18, 8, 6, Color("#5a4a2a"))
	)
	
	# 帐篷 (64x48)
	bld["tent"] = _make_sprite(64, 48, func(img):
		_draw_polygon(img, [Vector2(4, 44), Vector2(32, 4), Vector2(60, 44)], Color("#8a6a3a"))
		_draw_polygon(img, [Vector2(6, 44), Vector2(32, 6), Vector2(58, 44)], Color("#9a7a4a"))
		_draw_rect(img, 24, 28, 16, 16, Color("#6a4a2a"))
	)
	
	# 房屋 (96x64)
	bld["house"] = _make_sprite(96, 64, func(img):
		_draw_rect(img, 6, 24, 84, 36, Color("#8a6a3a"))
		_draw_polygon(img, [Vector2(2, 26), Vector2(48, 4), Vector2(94, 26)], Color("#6a4a2a"))
		_draw_rect(img, 6, 24, 84, 4, Color("#9a7a4a"))
		_draw_rect(img, 38, 36, 20, 24, Color("#5a3a1a"))
		_draw_rect(img, 40, 38, 6, 8, Color("#3a2a0a"))
		_draw_rect(img, 14, 30, 14, 14, Color("#6a5a3a"))
		_draw_rect(img, 68, 30, 14, 14, Color("#6a5a3a"))
	)
	
	# 研究台 (64x48)
	bld["research_table"] = _make_sprite(64, 48, func(img):
		_draw_rect(img, 4, 20, 56, 24, Color("#6a5a3a"))
		_draw_rect(img, 4, 20, 56, 4, Color("#7a6a4a"))
		_draw_rect(img, 8, 8, 48, 14, Color("#8a7a5a"))
		_draw_rect(img, 8, 8, 48, 3, Color("#9a8a6a"))
		_draw_rect(img, 16, 12, 32, 6, Color("#5a4a2a"))
		_draw_circle_fill(img, 22, 15, 2, Color("#4488cc"))
		_draw_circle_fill(img, 28, 15, 2, Color("#44cc44"))
		_draw_circle_fill(img, 34, 15, 2, Color("#cc4444"))
		_draw_circle_fill(img, 40, 15, 2, Color("#ccaa44"))
		_draw_rect(img, 10, 44, 6, 4, Color("#5a4a2a"))
		_draw_rect(img, 24, 44, 6, 4, Color("#5a4a2a"))
		_draw_rect(img, 38, 44, 6, 4, Color("#5a4a2a"))
		_draw_rect(img, 52, 44, 6, 4, Color("#5a4a2a"))
	)
	
	# 伐木屋 (64x64)
	bld["woodcutter_hut"] = _make_sprite(64, 64, func(img):
		_draw_rect(img, 8, 28, 48, 32, Color("#8a6a3a"))
		_draw_polygon(img, [Vector2(4, 30), Vector2(32, 8), Vector2(60, 30)], Color("#6a4a2a"))
		_draw_rect(img, 24, 40, 16, 20, Color("#5a3a1a"))
	)
	
	# 采石场 (64x64)
	bld["stone_quarry"] = _make_sprite(64, 64, func(img):
		_draw_rect(img, 4, 30, 56, 30, Color("#6a6a5a"))
		_draw_rect(img, 10, 20, 44, 14, Color("#7a7a6a"))
		_draw_polygon(img, [Vector2(8, 22), Vector2(32, 8), Vector2(56, 22)], Color("#5a5a4a"))
		_draw_rect(img, 14, 36, 8, 8, Color("#8a8a7a"))
		_draw_rect(img, 28, 34, 10, 10, Color("#8a8a7a"))
		_draw_rect(img, 42, 38, 7, 7, Color("#8a8a7a"))
	)
	
	# 铁矿坑 (64x64)
	bld["iron_mine"] = _make_sprite(64, 64, func(img):
		_draw_polygon(img, [Vector2(10, 22), Vector2(32, 6), Vector2(54, 22)], Color("#5a4a2a"))
		_draw_rect(img, 6, 22, 52, 34, Color("#6a5a3a"))
		_draw_rect(img, 6, 22, 52, 8, Color("#7a6a4a"))
		_draw_rect(img, 24, 32, 16, 24, Color("#4a3a1a"))
		_draw_circle_fill(img, 32, 46, 6, Color("#3a2a0a"))
	)
	
	# 锯木厂 (64x48)
	bld["sawmill"] = _make_sprite(64, 48, func(img):
		_draw_rect(img, 4, 20, 56, 24, Color("#7a5a3a"))
		_draw_rect(img, 4, 20, 56, 4, Color("#8a6a4a"))
		_draw_polygon(img, [Vector2(6, 22), Vector2(32, 4), Vector2(58, 22)], Color("#5a3a1a"))
		_draw_rect(img, 20, 28, 8, 16, Color("#6a4a2a"))
		_draw_rect(img, 36, 28, 8, 16, Color("#6a4a2a"))
		_draw_rect(img, 28, 32, 8, 12, Color("#5a3a1a"))
	)
	
	# 窑炉 (64x32)
	bld["kiln"] = _make_sprite(64, 32, func(img):
		_draw_rect(img, 6, 6, 52, 22, Color("#7a5a3a"))
		_draw_ellipse(img, 32, 6, 26, 6, Color("#8a6a4a"))
		_draw_ellipse(img, 32, 6, 20, 4, Color("#6a4a2a"))
		_draw_rect(img, 12, 10, 40, 14, Color("#5a3a1a"))
		_draw_rect(img, 14, 12, 36, 10, Color("#cc4422"))
	)
	
	# 仓库 (96x64)
	bld["warehouse"] = _make_sprite(96, 64, func(img):
		_draw_rect(img, 4, 16, 88, 44, Color("#6a5a3a"))
		_draw_polygon(img, [Vector2(4, 18), Vector2(48, 4), Vector2(92, 18)], Color("#5a4a2a"))
		_draw_rect(img, 4, 16, 88, 6, Color("#7a6a4a"))
		for x in [12, 26, 40, 54, 68]:
			_draw_rect(img, x, 28, 8, 8, Color("#8a7a5a"))
			_draw_rect(img, x, 40, 8, 8, Color("#8a7a5a"))
	)
	
	return bld

# -------- 角色 --------
static func _generate_character() -> Dictionary:
	var chars = {}
	
	chars["settler"] = _make_sprite(24, 32, func(img):
		# 头
		_draw_circle_fill(img, 12, 6, 5, Color("#e8b88a"))
		# 眼睛
		_draw_circle_fill(img, 10, 5, 0.8, Color("#444444"))
		_draw_circle_fill(img, 14, 5, 0.8, Color("#444444"))
		# 身体
		_draw_rect(img, 7, 12, 10, 10, Color("#4488aa"))
		# 腿
		_draw_rect(img, 5, 22, 5, 8, Color("#3a5a7a"))
		_draw_rect(img, 14, 22, 5, 8, Color("#3a5a7a"))
		# 手臂
		_draw_line(img, 5, 14, 3, 18, Color("#e8b88a"), 2.5)
		_draw_line(img, 19, 14, 21, 18, Color("#e8b88a"), 2.5)
	)
	
	return chars

# ==================== 绘图辅助 ====================

static func _make_tile(bg: Color, decorations: Array) -> Texture2D:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	
	for d in decorations:
		var c = d["color"]
		c.a = d["a"]
		match d["type"]:
			"circle":
				_draw_circle_fill(img, d["x"], d["y"], d["r"], c)
			"rect":
				_draw_rect(img, d["x"], d["y"], d["w"], d["h"], c)
			"wave":
				_draw_wave(img, d["y"], c)
			"line":
				_draw_line_h(img, d["y"], c)
			"line_hv":
				_draw_line_h(img, d["y"], c)
				_draw_line_v(img, d["x"], c)
			"tree":
				_draw_tree(img, d["x"], c)
			"mountain":
				_draw_mountain(img, c)
	
	return ImageTexture.create_from_image(img)

static func _make_sprite(w: int, h: int, draw_func: Callable) -> Texture2D:
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	draw_func.call(img)
	return ImageTexture.create_from_image(img)

# 基础绘图函数
static func _draw_circle_fill(img: Image, cx: float, cy: float, r: float, color: Color):
	var x0 = maxi(0, floori(cx - r))
	var x1 = mini(img.get_width() - 1, floori(cx + r))
	var y0 = maxi(0, floori(cy - r))
	var y1 = mini(img.get_height() - 1, floori(cy + r))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, color)

static func _draw_rect(img: Image, x: int, y: int, w: int, h: int, color: Color):
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)

static func _draw_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, color: Color):
	var x0 = maxi(0, floori(cx - rx))
	var x1 = mini(img.get_width() - 1, floori(cx + rx))
	var y0 = maxi(0, floori(cy - ry))
	var y1 = mini(img.get_height() - 1, floori(cy + ry))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var dx = (x - cx) / rx
			var dy = (y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, color)

static func _draw_line(img: Image, x1: float, y1: float, x2: float, y2: float, color: Color, width: float = 1.0):
	var steps = maxi(1, floori(max(abs(x2 - x1), abs(y2 - y1))))
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var px = roundf(x1 + (x2 - x1) * t)
		var py = roundf(y1 + (y2 - y1) * t)
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			_draw_circle_fill(img, px, py, width / 2.0, color)

static func _draw_line_h(img: Image, y: int, color: Color):
	for x in range(0, img.get_width()):
		if y >= 0 and y < img.get_height():
			img.set_pixel(x, y, color)

static func _draw_line_v(img: Image, x: int, color: Color):
	for y in range(0, img.get_height()):
		if x >= 0 and x < img.get_width():
			img.set_pixel(x, y, color)

static func _draw_polygon(img: Image, points: Array, color: Color):
	if points.size() < 3:
		return
	# 简单填充：找到边界框然后逐点测试
	var min_x = int(points[0].x)
	var max_x = int(points[0].x)
	var min_y = int(points[0].y)
	var max_y = int(points[0].y)
	for p in points:
		min_x = mini(min_x, int(p.x))
		max_x = maxi(max_x, int(p.x))
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	
	min_x = maxi(0, min_x)
	max_x = mini(img.get_width() - 1, max_x)
	min_y = maxi(0, min_y)
	max_y = mini(img.get_height() - 1, max_y)
	
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			if _point_in_triangle(Vector2(x, y), points[0], points[1], points[2]):
				img.set_pixel(x, y, color)

static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var v0 = c - a
	var v1 = b - a
	var v2 = p - a
	var dot00 = v0.dot(v0)
	var dot01 = v0.dot(v1)
	var dot02 = v0.dot(v2)
	var dot11 = v1.dot(v1)
	var dot12 = v1.dot(v2)
	var inv = 1.0 / (dot00 * dot11 - dot01 * dot01)
	var u = (dot11 * dot02 - dot01 * dot12) * inv
	var v = (dot00 * dot12 - dot01 * dot02) * inv
	return u >= 0 and v >= 0 and u + v <= 1

static func _draw_wave(img: Image, y: int, color: Color):
	var w = img.get_width()
	for x in range(0, w):
		var offset = sin(x * 0.4) * 2.0
		var py = roundf(y + offset)
		if py >= 0 and py < img.get_height():
			img.set_pixel(x, py, color)

static func _draw_tree(img: Image, x: int, color: Color):
	var pyramid = [Vector2(x, 6), Vector2(x - 4, 18), Vector2(x + 4, 18)]
	_draw_polygon(img, pyramid, color)

static func _draw_mountain(img: Image, color: Color):
	_draw_polygon(img, [Vector2(16, 2), Vector2(4, 30), Vector2(28, 30)], color)
