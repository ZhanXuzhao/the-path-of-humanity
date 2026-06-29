# 纹理生成器 - Texture Generator
# 在运行时生成游戏所需的所有纹理，无需外部图像文件
extends Node
class_name TextureGenerator

const TILE_SIZE := 32

# 生成所有纹理并返回字典
static func generate_all() -> Dictionary:
	var textures = {}
	textures["tiles"] = _generate_tiles()
	textures["resources"] = _generate_resources()
	textures["buildings"] = _generate_buildings()
	textures["character"] = _generate_character()
	return textures

# -------- 地形瓦片 (纯色+小装饰) --------
static func _generate_tiles() -> Dictionary:
	var tiles = {}
	
	tiles[World.TileType.GRASS]      = _solid_tile(Color("#5a8f3c"), Color("#6da84a"))
	tiles[World.TileType.DIRT]       = _solid_tile(Color("#8b6b3a"), Color("#7a5e30"))
	tiles[World.TileType.SAND]       = _solid_tile(Color("#d4b86a"), Color("#c9ae5e"))
	tiles[World.TileType.WATER]      = _solid_tile(Color("#3a7ebf"), Color("#5a9ed4"))
	tiles[World.TileType.DEEP_WATER] = _solid_tile(Color("#1a4a7a"), Color("#2a5a8a"))
	tiles[World.TileType.STONE]      = _solid_tile(Color("#7a7a7a"), Color("#8a8a8a"))
	tiles[World.TileType.FOREST]     = _solid_tile(Color("#2d6a1e"), Color("#3d8a2e"))
	tiles[World.TileType.MOUNTAIN]   = _solid_tile(Color("#5a5a5a"), Color("#6a6a6a"))
	tiles[World.TileType.SNOW]       = _solid_tile(Color("#d8dce0"), Color("#e8ecf0"))
	tiles[World.TileType.ROAD]       = _solid_tile(Color("#8a7a5a"), Color("#9a8a6a"))
	tiles[World.TileType.FLOOR]      = _solid_tile(Color("#a08860"), Color("#b09870"))
	tiles[World.TileType.WALL]       = _solid_tile(Color("#6a6a5a"), Color("#7a7a6a"))
	
	return tiles

# -------- 资源节点 (纯色块) --------
static func _generate_resources() -> Dictionary:
	var res = {}
	
	res[World.ResourceNodeType.TREE]          = _solid_tex(32, 48, Color("#2a6b1a"), Color("#338822"))
	res[World.ResourceNodeType.STONE_DEPOSIT] = _solid_tex(32, 24, Color("#7a7a7a"), Color("#8a8a8a"))
	res[World.ResourceNodeType.IRON_DEPOSIT]  = _solid_tex(32, 24, Color("#8a7a5a"), Color("#b08040"))
	res[World.ResourceNodeType.COPPER_DEPOSIT]= _solid_tex(32, 24, Color("#7a6a5a"), Color("#c08040"))
	res[World.ResourceNodeType.COAL_DEPOSIT]  = _solid_tex(32, 24, Color("#4a4a4a"), Color("#1a1a1a"))
	res[World.ResourceNodeType.BERRY_BUSH]    = _solid_tex(32, 24, Color("#3a6a2a"), Color("#4a7a30"))
	
	return res

# -------- 建筑 (纯色方块) --------
static func _generate_buildings() -> Dictionary:
	var bld = {}
	
	bld["storage_rack"]     = _solid_tex(32, 32, Color("#6a4a2a"), Color("#8a6a3a"))
	bld["campfire"]         = _solid_tex(32, 32, Color("#ff6633"), Color("#ffaa33"))
	bld["cooking_stove"]    = _solid_tex(32, 32, Color("#5a4a3a"), Color("#6a5a4a"))
	bld["wall"]             = _solid_tex(32, 32, Color("#7a7a6a"), Color("#8a8a7a"))
	bld["workbench"]        = _solid_tex(64, 48, Color("#6a4a2a"), Color("#8a6a3a"))
	bld["furnace"]          = _solid_tex(64, 32, Color("#6a5a3a"), Color("#cc4422"))
	bld["tent"]             = _solid_tex(64, 48, Color("#8a6a3a"), Color("#9a7a4a"))
	bld["house"]            = _solid_tex(96, 64, Color("#8a6a3a"), Color("#6a4a2a"))
	bld["research_table"]   = _solid_tex(64, 48, Color("#6a5a3a"), Color("#8a7a5a"))
	bld["woodcutter_hut"]   = _solid_tex(64, 64, Color("#8a6a3a"), Color("#6a4a2a"))
	bld["stone_quarry"]     = _solid_tex(64, 64, Color("#6a6a5a"), Color("#7a7a6a"))
	bld["iron_mine"]        = _solid_tex(64, 64, Color("#5a4a2a"), Color("#6a5a3a"))
	bld["sawmill"]          = _solid_tex(64, 48, Color("#7a5a3a"), Color("#5a3a1a"))
	bld["kiln"]             = _solid_tex(64, 32, Color("#7a5a3a"), Color("#cc4422"))
	bld["warehouse"]        = _solid_tex(96, 64, Color("#6a5a3a"), Color("#5a4a2a"))
	
	return bld

# -------- 角色 (简约人形) --------
static func _generate_character() -> Dictionary:
	var chars = {}
	
	# 创建角色纹理 (24x32)：头+身体+四肢的简约风格
	var img = Image.create(24, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	
	# 头 (肤色圆形)
	for x in range(7, 18):
		for y in range(1, 12):
			var dx = x - 12
			var dy = y - 6
			if dx * dx + dy * dy <= 25:
				img.set_pixel(x, y, Color("#e8b88a"))
	
	# 眼睛
	for x in [10, 14]:
		for y in [5]:
			img.set_pixel(x, y, Color("#444444"))
			img.set_pixel(x+1, y, Color("#444444"))
	
	# 身体 (蓝色上衣)
	for x in range(7, 17):
		for y in range(12, 22):
			img.set_pixel(x, y, Color("#4488aa"))
	
	# 腿 (深蓝裤子)
	for x in range(5, 10):
		for y in range(22, 30):
			img.set_pixel(x, y, Color("#3a5a7a"))
	for x in range(14, 19):
		for y in range(22, 30):
			img.set_pixel(x, y, Color("#3a5a7a"))
	
	chars["settler"] = ImageTexture.create_from_image(img)
	return chars

# ==================== 简化的纹理生成 ====================

# 生成双色方块纹理 (底色 + 装饰色)
static func _solid_tile(bg: Color, accent: Color) -> Texture2D:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	# 添加简单网格线装饰
	for x in range(0, TILE_SIZE, 8):
		for y in range(0, TILE_SIZE):
			img.set_pixel(x, y, accent)
	for y in range(0, TILE_SIZE, 8):
		for x in range(0, TILE_SIZE):
			img.set_pixel(x, y, accent)
	return ImageTexture.create_from_image(img)

# 生成纯色纹理 (用于建筑/资源)
static func _solid_tex(w: int, h: int, c1: Color, c2: Color) -> Texture2D:
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c1)
	# 添加水平条纹装饰
	for y in range(0, h, 6):
		for x in range(0, w):
			if y < h:
				img.set_pixel(x, y, c2)
	return ImageTexture.create_from_image(img)
