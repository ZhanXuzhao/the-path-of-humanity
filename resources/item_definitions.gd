# 物品定义 - Item Definitions
# 定义了游戏中所有物品、资源、建筑和配方
extends Node

# ==================== 物品类型枚举 ====================
enum ItemCategory {
	RAW_MATERIAL,    # 原材料
	REFINED_MATERIAL, # 精炼材料
	FOOD,            # 食物
	TOOL,            # 工具
	WEAPON,          # 武器
	EQUIPMENT,       # 装备
	BUILDING_MATERIAL, # 建筑材料
	CONSUMABLE,      # 消耗品
	RESOURCE         # 自然资源（不可采集移动到背包）
}

enum BuildingCategory {
	STORAGE,      # 存储
	PRODUCTION,   # 生产
	EXTRACTION,   # 采集
	DEFENSE,      # 防御
	RESIDENTIAL,  # 居住
	INFRASTRUCTURE, # 基础设施
	RESEARCH,     # 研究
	FURNITURE     # 家具
}

# ==================== 物品数据结构 ====================
class ItemData:
	var id: String           # 唯一标识符
	var name: String         # 显示名称
	var description: String  # 描述
	var category: ItemCategory
	var max_stack: int
	var weight: float
	var icon_frame: int      # 图标帧
	var nutrition: float     # 营养价值 (食物)
	var fuel_value: float    # 燃料价值
	var value: float         # 基础价值

class BuildingData:
	var id: String
	var name: String
	var description: String
	var category: BuildingCategory
	var size: Vector2i       # 占用格数 (宽x高)
	var hp: int              # 耐久度
	var work_cost: float     # 建造所需工作量
	var materials: Dictionary # 建造材料 {item_id: amount}
	var produces: Dictionary  # 生产输出 {item_id: amount_per_cycle}
	var consumes: Dictionary  # 生产输入 {item_id: amount_per_cycle}
	var production_time: float # 生产周期(秒)
	var storage_capacity: int # 存储容量 (0=不存储)
	var icon_frame: int
	var is_passable: bool = true  # 是否可通行（墙不可通行，门可通行）
	var attack_range: float = 0.0  # 攻击范围(格)，0=不能攻击
	var attack_damage: float = 0.0
	var attack_cooldown: float = 0.0  # 攻击间隔(秒)

class RecipeData:
	var id: String
	var name: String
	var description: String
	var inputs: Dictionary    # {item_id: amount}
	var outputs: Dictionary   # {item_id: amount}
	var work_time: float      # 制作时间(秒)
	var required_tech: String  # 所需科技
	var crafted_at: String    # 在哪个建筑中制作

class TechData:
	var id: String
	var name: String
	var description: String
	var cost: Dictionary      # {item_id: amount}
	var research_time: float  # 研究时间(秒)
	var prerequisites: Array[String]  # 前置科技
	var unlocks: Array[String]        # 解锁内容 (建筑/配方id)
	var category: String

# ==================== 物品注册表 ====================
# 集中管理所有物品、建筑、配方、科技数据

static var items: Dictionary = {}
static var buildings: Dictionary = {}
static var buildings_by_category: Dictionary = {}
static var recipes: Dictionary = {}
static var techs: Dictionary = {}

func _ready():
	_register_items()
	_register_buildings()
	_register_recipes()
	_register_techs()
	_build_category_index()
	print("ItemDefinitions initialized: %d items, %d buildings, %d recipes, %d techs" % [items.size(), buildings.size(), recipes.size(), techs.size()])

static func _build_category_index():
	buildings_by_category.clear()
	for b_id in buildings:
		var data = buildings[b_id]
		if not buildings_by_category.has(data.category):
			buildings_by_category[data.category] = []
		buildings_by_category[data.category].append(data)

# -------- 注册物品 --------
static func _register_items():
	# 原材料
	_add_item("wood", "木材", "从树木采集的木材", ItemCategory.RAW_MATERIAL, 50, 0.5, 0, 0.0, 0.0, 1.0)
	_add_item("stone", "石头", "从岩石采集的石料", ItemCategory.RAW_MATERIAL, 50, 1.0, 1, 0.0, 0.0, 1.0)
	_add_item("iron_ore", "铁矿石", "含铁的矿石", ItemCategory.RAW_MATERIAL, 50, 1.5, 2, 0.0, 0.0, 2.0)
	_add_item("copper_ore", "铜矿石", "含铜的矿石", ItemCategory.RAW_MATERIAL, 50, 1.5, 3, 0.0, 0.0, 2.0)
	_add_item("coal", "煤炭", "可燃的黑色矿石", ItemCategory.RAW_MATERIAL, 50, 1.0, 4, 0.0, 5.0, 2.0)
	_add_item("berry", "浆果", "野生的可食用浆果", ItemCategory.FOOD, 30, 0.1, 5, 5.0, 0.0, 0.5)
	_add_item("raw_meat", "生肉", "猎取的生肉，需要烹饪", ItemCategory.FOOD, 20, 0.3, 6, 8.0, 0.0, 2.0)
	_add_item("cloth", "布料", "由植物纤维制成的布料", ItemCategory.RAW_MATERIAL, 30, 0.2, 7, 0.0, 0.0, 1.5)
	
	# 精炼材料
	_add_item("iron_ingot", "铁锭", "熔炼铁矿石得到的铁锭", ItemCategory.REFINED_MATERIAL, 30, 2.0, 8, 0.0, 0.0, 5.0)
	_add_item("copper_ingot", "铜锭", "熔炼铜矿石得到的铜锭", ItemCategory.REFINED_MATERIAL, 30, 2.0, 9, 0.0, 0.0, 5.0)
	_add_item("steel_ingot", "钢锭", "铁和碳熔炼而成的合金", ItemCategory.REFINED_MATERIAL, 30, 2.5, 10, 0.0, 0.0, 10.0)
	_add_item("plank", "木板", "加工过的木板", ItemCategory.REFINED_MATERIAL, 40, 0.8, 11, 0.0, 2.0, 3.0)
	_add_item("brick", "砖块", "烧制而成的砖块", ItemCategory.REFINED_MATERIAL, 40, 1.2, 12, 0.0, 0.0, 3.0)

	# 食物
	_add_item("cooked_meat", "熟肉", "烹饪过的肉食", ItemCategory.FOOD, 20, 0.3, 13, 20.0, 0.0, 4.0)
	_add_item("bread", "面包", "用面粉烤制的面包", ItemCategory.FOOD, 30, 0.2, 14, 15.0, 0.0, 3.0)
	_add_item("vegetable_soup", "蔬菜汤", "营养丰富的蔬菜汤", ItemCategory.FOOD, 10, 0.5, 15, 25.0, 0.0, 5.0)
	_add_item("rice", "水稻", "种植收获的水稻，可食用", ItemCategory.FOOD, 50, 0.2, 5, 8.0, 0.0, 1.0)
	_add_item("wheat", "小麦", "种植收获的小麦，可磨粉或食用", ItemCategory.FOOD, 50, 0.2, 21, 7.0, 0.0, 1.0)
	_add_item("flour", "面粉", "小麦磨成的面粉，可烤制成面包", ItemCategory.FOOD, 50, 0.2, 22, 5.0, 0.0, 1.5)

	# 工具和设备
	_add_item("stone_axe", "石斧", "用石头制作的简易斧头", ItemCategory.TOOL, 1, 2.0, 16, 0.0, 0.0, 8.0)
	_add_item("stone_pickaxe", "石镐", "用石头制作的简易镐", ItemCategory.TOOL, 1, 2.0, 17, 0.0, 0.0, 8.0)

	# 武器
	_add_item("bow", "弓", "简易木弓，可发射箭矢", ItemCategory.WEAPON, 1, 1.5, 19, 0.0, 0.0, 5.0)
	_add_item("arrow", "箭矢", "木制箭矢", ItemCategory.WEAPON, 50, 0.1, 20, 0.0, 0.0, 0.5)

	# 消耗品
	_add_item("torch", "火把", "提供照明的火把", ItemCategory.CONSUMABLE, 20, 0.3, 18, 0.0, 0.0, 1.0)

# -------- 注册建筑 --------
static func _register_buildings():
	# 采集类
	_add_building("woodcutter_hut", "伐木屋", "自动采集周围树木", BuildingCategory.EXTRACTION, Vector2i(2, 2), 100, 30.0, {"wood": 20, "stone": 10}, {"wood": 1}, {}, 3.0, 0, 0)
	_add_building("stone_quarry", "采石场", "自动采集石头", BuildingCategory.EXTRACTION, Vector2i(2, 2), 150, 40.0, {"wood": 15, "stone": 20}, {"stone": 1}, {}, 4.0, 0, 1)
	_add_building("iron_mine", "铁矿坑", "开采铁矿石", BuildingCategory.EXTRACTION, Vector2i(2, 2), 200, 50.0, {"wood": 30, "stone": 20}, {"iron_ore": 1}, {}, 5.0, 0, 2)

	# 生产类
	_add_building("workbench", "工作台", "基础制造平台", BuildingCategory.PRODUCTION, Vector2i(2, 2), 80, 20.0, {"wood": 15}, {}, {}, 0.0, 0, 3)
	_add_building("furnace", "熔炉", "熔炼矿石和烧制", BuildingCategory.PRODUCTION, Vector2i(2, 1), 150, 30.0, {"stone": 25, "wood": 10}, {}, {}, 0.0, 0, 4)
	_add_building("cooking_stove", "灶台", "烹饪食物", BuildingCategory.PRODUCTION, Vector2i(1, 1), 60, 15.0, {"stone": 10, "wood": 5}, {}, {}, 0.0, 0, 5)
	_add_building("sawmill", "锯木厂", "将原木加工成木板", BuildingCategory.PRODUCTION, Vector2i(2, 2), 120, 35.0, {"wood": 30, "stone": 15}, {}, {}, 0.0, 0, 6)
	_add_building("kiln", "窑炉", "烧制砖块", BuildingCategory.PRODUCTION, Vector2i(2, 1), 130, 30.0, {"stone": 30, "wood": 10}, {}, {}, 0.0, 0, 7)
	_add_building("mill", "磨坊", "将小麦磨成面粉", BuildingCategory.PRODUCTION, Vector2i(2, 1), 100, 25.0, {"stone": 20, "wood": 15}, {}, {}, 0.0, 0, 22)

	# 存储类
	_add_building("storage_rack", "储物架", "存储物品", BuildingCategory.STORAGE, Vector2i(1, 1), 50, 10.0, {"wood": 10}, {}, {}, 0.0, 1000, 8)
	_add_building("warehouse", "仓库", "大型存储设施", BuildingCategory.STORAGE, Vector2i(3, 3), 300, 60.0, {"wood": 50, "stone": 30}, {}, {}, 0.0, 500, 9)

	# 居住类
	_add_building("tent", "帐篷", "简易住所", BuildingCategory.RESIDENTIAL, Vector2i(2, 2), 60, 15.0, {"cloth": 10, "wood": 5}, {}, {}, 0.0, 0, 10)
	_add_building("house", "房屋", "舒适的住所", BuildingCategory.RESIDENTIAL, Vector2i(3, 3), 200, 50.0, {"wood": 30, "plank": 20, "stone": 15}, {}, {}, 0.0, 0, 11)

	# 基础设施
	_add_building("campfire", "篝火", "提供照明和温暖", BuildingCategory.INFRASTRUCTURE, Vector2i(1, 1), 30, 5.0, {"wood": 5, "stone": 3}, {}, {}, 0.0, 0, 12)
	_add_building("road", "道路", "提高移动速度", BuildingCategory.INFRASTRUCTURE, Vector2i(1, 1), 40, 3.0, {"stone": 2}, {}, {}, 0.0, 0, 13)
	_add_building("town_center", "城镇中心", "消耗2个面包招募新居民的核心建筑", BuildingCategory.INFRASTRUCTURE, Vector2i(3, 3), 300, 60.0, {"wood": 40, "stone": 30, "plank": 20}, {}, {}, 0.0, 500, 23)
	# 防御建筑——墙（不可通行），门（可通行）
	_add_building("wood_wall", "木墙", "简易木质围墙", BuildingCategory.DEFENSE, Vector2i(1, 1), 150, 8.0, {"wood": 5}, {}, {}, 0.0, 0, 14, false)
	_add_building("wood_door", "木门", "简易木门", BuildingCategory.DEFENSE, Vector2i(1, 1), 100, 6.0, {"wood": 3}, {}, {}, 0.0, 0, 15, true)
	_add_building("stone_wall", "石墙", "坚固的石墙", BuildingCategory.DEFENSE, Vector2i(1, 1), 400, 15.0, {"stone": 5}, {}, {}, 0.0, 0, 17, false)
	_add_building("stone_door", "石门", "坚固的石门", BuildingCategory.DEFENSE, Vector2i(1, 1), 250, 10.0, {"stone": 3}, {}, {}, 0.0, 0, 18, true)
	_add_building("iron_wall", "铁墙", "坚不可摧的铁墙", BuildingCategory.DEFENSE, Vector2i(1, 1), 600, 20.0, {"iron_ingot": 5}, {}, {}, 0.0, 0, 19, false)
	_add_building("iron_door", "铁门", "坚固的铁门", BuildingCategory.DEFENSE, Vector2i(1, 1), 400, 15.0, {"iron_ingot": 3}, {}, {}, 0.0, 0, 20, true)
	# 防御建筑——哨塔（自动攻击）
	_add_building("wood_watchtower", "木哨塔", "自动射箭攻击进入射程的敌人", BuildingCategory.DEFENSE, Vector2i(1, 1), 500, 40.0, {"wood": 30}, {}, {}, 0.0, 0, 21, false, 5.0, 10.0, 2.0)

	# 家具类
	_add_building("wooden_bed", "木床", "一张舒适的木板床，可供一名定居者睡眠", BuildingCategory.FURNITURE, Vector2i(2, 1), 80, 20.0, {"wood": 10}, {}, {}, 0.0, 0, 16)

	# 研究类
	_add_building("research_table", "研究台", "进行科技研究", BuildingCategory.RESEARCH, Vector2i(2, 2), 100, 30.0, {"wood": 20, "plank": 10}, {}, {}, 0.0, 0, 15)

# -------- 注册配方 --------
static func _register_recipes():
	# 工作台配方
	_add_recipe("plank", "制作木板", "将原木加工成木板", {"wood": 2}, {"plank": 3}, 3.0, "", "workbench")
	_add_recipe("stone_axe", "制作石斧", "", {"wood": 3, "stone": 4}, {"stone_axe": 1}, 5.0, "", "workbench")
	_add_recipe("stone_pickaxe", "制作石镐", "", {"wood": 3, "stone": 4}, {"stone_pickaxe": 1}, 5.0, "", "workbench")
	_add_recipe("torch", "制作火把", "", {"wood": 1, "cloth": 1}, {"torch": 3}, 2.0, "", "workbench")
	_add_recipe("bow", "制作弓", "", {"wood": 5, "cloth": 2}, {"bow": 1}, 5.0, "archery", "workbench")
	_add_recipe("arrow", "制作箭矢", "", {"wood": 1, "stone": 1}, {"arrow": 5}, 2.0, "archery", "workbench")

	# 熔炉配方
	_add_recipe("iron_ingot", "熔炼铁锭", "将铁矿石熔炼成铁锭", {"iron_ore": 3, "coal": 1}, {"iron_ingot": 1}, 5.0, "", "furnace")
	_add_recipe("copper_ingot", "熔炼铜锭", "将铜矿石熔炼成铜锭", {"copper_ore": 3, "coal": 1}, {"copper_ingot": 1}, 5.0, "", "furnace")

	# 灶台配方
	_add_recipe("cooked_meat", "烹饪熟肉", "将生肉烤熟", {"raw_meat": 2}, {"cooked_meat": 1}, 4.0, "", "cooking_stove")
	_add_recipe("vegetable_soup", "制作蔬菜汤", "", {"berry": 3}, {"vegetable_soup": 1}, 5.0, "", "cooking_stove")

	# 锯木厂配方
	_add_recipe("plank_sawmill", "锯木(锯木厂)", "用锯木厂加工木板", {"wood": 1}, {"plank": 4}, 2.0, "", "sawmill")

	# 窑炉配方
	_add_recipe("brick", "烧制砖块", "将石头烧制成砖块", {"stone": 2, "coal": 1}, {"brick": 2}, 4.0, "", "kiln")

	# 磨坊配方
	_add_recipe("mill_flour", "磨面粉", "将小麦磨成面粉", {"wheat": 3}, {"flour": 2}, 4.0, "", "mill")

	# 灶台配方（面包）
	_add_recipe("bake_bread", "烤面包", "用面粉烤制面包", {"flour": 2}, {"bread": 1}, 5.0, "", "cooking_stove")

# -------- 注册科技 --------
static func _register_techs():
	_add_tech("primitive_tools", "原始工具", "掌握基本的工具制作", {"wood": 10, "stone": 10}, 30.0, [], ["stone_axe", "stone_pickaxe", "torch"], "基础")
	_add_tech("construction", "建筑构造", "解锁基础建筑", {"wood": 20, "stone": 15}, 45.0, ["primitive_tools"], ["tent", "campfire", "storage_rack", "workbench", "wood_wall", "wood_door"], "基础")
	_add_tech("metalworking", "金属加工", "掌握熔炼技术", {"stone": 20, "wood": 15}, 60.0, ["construction"], ["furnace", "iron_ingot", "copper_ingot", "iron_mine"], "工业")
	_add_tech("cooking", "烹饪技术", "学会烹饪食物和磨制面粉", {"wood": 10, "berry": 15}, 30.0, ["construction"], ["cooking_stove", "cooked_meat", "vegetable_soup", "mill", "mill_flour", "bake_bread"], "基础")
	_add_tech("archery", "弓箭", "学会制作和使用弓箭", {"wood": 20, "stone": 10}, 40.0, ["primitive_tools"], ["bow", "arrow", "wood_watchtower"], "军事")
	_add_tech("woodworking", "木工技术", "高级木材加工", {"wood": 30, "plank": 10}, 45.0, ["construction"], ["sawmill", "plank_sawmill", "house", "wooden_bed"], "工业")
	_add_tech("masonry", "石工技术", "掌握石材加工", {"stone": 30, "brick": 10}, 45.0, ["construction"], ["kiln", "brick", "stone_wall", "stone_door", "warehouse"], "工业")
	_add_tech("advanced_metal", "高级冶金", "炼钢技术", {"iron_ingot": 20, "coal": 20}, 90.0, ["metalworking"], ["steel_ingot", "iron_wall", "iron_door"], "工业")
	_add_tech("science", "科学研究", "开展科学研究", {"wood": 20, "stone": 15}, 60.0, ["construction"], ["research_table"], "科学")

# ==================== 辅助方法 ====================
static func _add_item(id: String, item_name: String, desc: String, cat: ItemCategory,
		max_stack: int, weight: float, icon: int, nutrition: float, fuel: float, value: float):
	var item := ItemData.new()
	item.id = id
	item.name = item_name
	item.description = desc
	item.category = cat
	item.max_stack = max_stack
	item.weight = weight
	item.icon_frame = icon
	item.nutrition = nutrition
	item.fuel_value = fuel
	item.value = value
	items[id] = item

static func _add_building(id: String, bld_name: String, desc: String, cat: BuildingCategory,
		size: Vector2i, hp: int, work_cost: float, materials: Dictionary,
		produces: Dictionary, consumes: Dictionary, prod_time: float,
		storage: int, icon: int, is_passable: bool = true,
		attack_range: float = 0.0, attack_damage: float = 0.0, attack_cooldown: float = 0.0):
	var building := BuildingData.new()
	building.id = id
	building.name = bld_name
	building.description = desc
	building.category = cat
	building.size = size
	building.hp = hp
	building.work_cost = work_cost
	building.materials = materials
	building.produces = produces
	building.consumes = consumes
	building.production_time = prod_time
	building.storage_capacity = storage
	building.icon_frame = icon
	building.is_passable = is_passable
	building.attack_range = attack_range
	building.attack_damage = attack_damage
	building.attack_cooldown = attack_cooldown
	buildings[id] = building

static func _add_recipe(id: String, recipe_name: String, desc: String,
		inputs: Dictionary, outputs: Dictionary, time: float,
		tech: String, building: String):
	var recipe := RecipeData.new()
	recipe.id = id
	recipe.name = recipe_name
	recipe.description = desc
	recipe.inputs = inputs
	recipe.outputs = outputs
	recipe.work_time = time
	recipe.required_tech = tech
	recipe.crafted_at = building
	recipes[id] = recipe

static func _add_tech(id: String, tech_name: String, desc: String,
		cost: Dictionary, time: float, prereqs: Array[String],
		unlocks: Array[String], cat: String):
	var tech := TechData.new()
	tech.id = id
	tech.name = tech_name
	tech.description = desc
	tech.cost = cost
	tech.research_time = time
	tech.prerequisites = prereqs
	tech.unlocks = unlocks
	tech.category = cat
	techs[id] = tech

# ==================== 查询方法 ====================
static func get_item(id: String) -> ItemData:
	return items.get(id, ItemData.new())

static func get_building(id: String) -> BuildingData:
	return buildings.get(id, BuildingData.new())

static func get_recipe(id: String) -> RecipeData:
	return recipes.get(id, RecipeData.new())

static func get_tech(id: String) -> TechData:
	return techs.get(id, TechData.new())

static func get_recipes_for_building(building_id: String) -> Array:
	var result: Array[RecipeData] = []
	for r in recipes.values():
		if r.crafted_at == building_id:
			result.append(r)
	return result

static func get_recipes_for_tech(tech_id: String) -> Array:
	var result: Array[RecipeData] = []
	for r in recipes.values():
		if r.required_tech == tech_id:
			result.append(r)
	return result
