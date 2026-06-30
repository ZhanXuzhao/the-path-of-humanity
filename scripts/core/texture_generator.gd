# 纹理生成器 - Texture Generator
# 加载 SVG 图片资产作为游戏纹理
extends Node
class_name TextureGenerator

# SVG 资产根路径
const TILES_PATH := "res://assets/art/tiles/"
const BUILDINGS_PATH := "res://assets/art/buildings/"
const RESOURCES_PATH := "res://assets/art/resources/"
const CHARACTERS_PATH := "res://assets/art/characters/"
const ICONS_PATH := "res://assets/art/icons/"

# 生成所有纹理并返回字典
static func generate_all() -> Dictionary:
	var textures = {}
	textures["tiles"] = _load_tiles()
	textures["resources"] = _load_resources()
	textures["buildings"] = _load_buildings()
	textures["character"] = _load_character()
	textures["ground_item"] = _load_ground_item()
	return textures

# -------- 地形瓦片 (从 SVG 加载) --------
static func _load_tiles() -> Dictionary:
	var tiles = {}
	
	tiles[World.TileType.GRASS]      = _load_svg(TILES_PATH + "grass.svg")
	tiles[World.TileType.DIRT]       = _load_svg(TILES_PATH + "dirt.svg")
	tiles[World.TileType.SAND]       = _load_svg(TILES_PATH + "sand.svg")
	tiles[World.TileType.WATER]      = _load_svg(TILES_PATH + "water.svg")
	tiles[World.TileType.DEEP_WATER] = _load_svg(TILES_PATH + "deep_water.svg")
	tiles[World.TileType.STONE]      = _load_svg(TILES_PATH + "stone.svg")
	tiles[World.TileType.FOREST]     = _load_svg(TILES_PATH + "forest.svg")
	tiles[World.TileType.MOUNTAIN]   = _load_svg(TILES_PATH + "mountain.svg")
	tiles[World.TileType.SNOW]       = _load_svg(TILES_PATH + "snow.svg")
	tiles[World.TileType.ROAD]       = _load_svg(TILES_PATH + "road.svg")
	tiles[World.TileType.FLOOR]      = _load_svg(TILES_PATH + "floor.svg")
	tiles[World.TileType.WALL]       = _load_svg(TILES_PATH + "wall.svg")
	
	return tiles

# -------- 资源节点 (从 SVG 加载) --------
static func _load_resources() -> Dictionary:
	var res = {}
	
	res[World.ResourceNodeType.TREE]          = _load_svg(RESOURCES_PATH + "tree.svg")
	res[World.ResourceNodeType.STONE_DEPOSIT] = _load_svg(RESOURCES_PATH + "stone_deposit.svg")
	res[World.ResourceNodeType.IRON_DEPOSIT]  = _load_svg(RESOURCES_PATH + "iron_deposit.svg")
	res[World.ResourceNodeType.COPPER_DEPOSIT]= _load_svg(RESOURCES_PATH + "copper_deposit.svg")
	res[World.ResourceNodeType.COAL_DEPOSIT]  = _load_svg(RESOURCES_PATH + "coal_deposit.svg")
	res[World.ResourceNodeType.BERRY_BUSH]    = _load_svg(RESOURCES_PATH + "berry_bush.svg")
	
	return res

# -------- 建筑 (从 SVG 加载) --------
static func _load_buildings() -> Dictionary:
	var bld = {}
	
	bld["storage_rack"]     = _load_svg(BUILDINGS_PATH + "storage_rack.svg")
	bld["campfire"]         = _load_svg(BUILDINGS_PATH + "campfire.svg")
	bld["cooking_stove"]    = _load_svg(BUILDINGS_PATH + "cooking_stove.svg")
	bld["wood_wall"]        = _load_svg(BUILDINGS_PATH + "wood_wall.svg")
	bld["wood_door"]        = _load_svg(BUILDINGS_PATH + "wood_door.svg")
	bld["stone_wall"]       = _load_svg(BUILDINGS_PATH + "stone_wall.svg")
	bld["stone_door"]       = _load_svg(BUILDINGS_PATH + "stone_door.svg")
	bld["iron_wall"]        = _load_svg(BUILDINGS_PATH + "iron_wall.svg")
	bld["iron_door"]        = _load_svg(BUILDINGS_PATH + "iron_door.svg")
	bld["workbench"]        = _load_svg(BUILDINGS_PATH + "workbench.svg")
	bld["furnace"]          = _load_svg(BUILDINGS_PATH + "furnace.svg")
	bld["tent"]             = _load_svg(BUILDINGS_PATH + "tent.svg")
	bld["house"]            = _load_svg(BUILDINGS_PATH + "house.svg")
	bld["research_table"]   = _load_svg(BUILDINGS_PATH + "research_table.svg")
	bld["woodcutter_hut"]   = _load_svg(BUILDINGS_PATH + "woodcutter_hut.svg")
	bld["stone_quarry"]     = _load_svg(BUILDINGS_PATH + "stone_quarry.svg")
	bld["iron_mine"]        = _load_svg(BUILDINGS_PATH + "iron_mine.svg")
	bld["sawmill"]          = _load_svg(BUILDINGS_PATH + "sawmill.svg")
	bld["kiln"]             = _load_svg(BUILDINGS_PATH + "kiln.svg")
	bld["warehouse"]        = _load_svg(BUILDINGS_PATH + "warehouse.svg")
	bld["road"]             = _load_svg(BUILDINGS_PATH + "road.svg")
	bld["wooden_bed"]       = _load_svg(BUILDINGS_PATH + "wooden_bed.svg")
	
	return bld

# -------- 地面物品图标 --------
static func _load_ground_item() -> Texture2D:
	return _load_svg(ICONS_PATH + "ground_item.svg")

# -------- 角色 (从 PNG 加载) --------
static func _load_character() -> Dictionary:
	var chars = {}
	chars["player_boy"]        = _load_svg(CHARACTERS_PATH + "player_boy.png")
	chars["player_girl"]       = _load_svg(CHARACTERS_PATH + "player_girl.png")
	chars["player_girl2"]      = _load_svg(CHARACTERS_PATH + "player_girl2.png")
	chars["player_kid"]        = _load_svg(CHARACTERS_PATH + "player_kid.png")
	chars["player_little_boy"] = _load_svg(CHARACTERS_PATH + "player_little_boy.png")
	chars["player_little_girl"]= _load_svg(CHARACTERS_PATH + "player_little_girl.png")
	chars["player_woman"]      = _load_svg(CHARACTERS_PATH + "player_woman.png")
	chars["player_young_man"]  = _load_svg(CHARACTERS_PATH + "player_young_man.png")
	chars["player_young_man2"] = _load_svg(CHARACTERS_PATH + "player_young_man2.png")
	chars["player_young_man3"] = _load_svg(CHARACTERS_PATH + "player_young_man3.png")
	return chars

# ==================== SVG 加载工具 ====================

# 加载图片文件（SVG/PNG等）为 Texture2D
static func _load_svg(path: String) -> Texture2D:
	var tex = ResourceLoader.load(path, "Texture2D")
	if tex == null:
		push_error("TextureGenerator: 无法加载 SVG 纹理: " + path)
		# 返回 32x32 空白纹理作为 fallback
		var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		return ImageTexture.create_from_image(img)
	return tex
