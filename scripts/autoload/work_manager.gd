# 工作管理器 - Work Manager (Autoload)
# 管理每个定居者的工作优先级配置，类似 RimWorld 的工作标签页
extends Node

signal work_priorities_changed(settler_id: String)

# 工作类型定义
enum WorkType {
	MINING,         # 采矿
	WOODCUTTING,    # 伐木
	CONSTRUCTION,   # 建造
	CRAFTING,       # 制作
	COOKING,        # 烹饪
	FARMING,        # 农业
	HAULING,        # 搬运
	RESEARCH,       # 研究
	COMBAT,         # 战斗
	HUNTING,        # 狩猎
}

# 工作类型对应的中文名
const WORK_TYPE_NAMES = {
	WorkType.MINING: "采矿",
	WorkType.WOODCUTTING: "伐木",
	WorkType.CONSTRUCTION: "建造",
	WorkType.CRAFTING: "制作",
	WorkType.COOKING: "烹饪",
	WorkType.FARMING: "农业",
	WorkType.HAULING: "搬运",
	WorkType.RESEARCH: "研究",
	WorkType.COMBAT: "战斗",
	WorkType.HUNTING: "狩猎",
}

# 工作类型对应的技能ID（用于查询定居者技能等级）
const WORK_TYPE_SKILLS = {
	WorkType.MINING: "mining",
	WorkType.WOODCUTTING: "woodcutting",
	WorkType.CONSTRUCTION: "construction",
	WorkType.CRAFTING: "crafting",
	WorkType.COOKING: "cooking",
	WorkType.FARMING: "farming",
	WorkType.HAULING: "",
	WorkType.RESEARCH: "research",
	WorkType.COMBAT: "combat",
	WorkType.HUNTING: "combat",
}

# 工作类型对应的任务类型
const WORK_TYPE_TASKS = {
	WorkType.MINING: "HARVEST",
	WorkType.WOODCUTTING: "HARVEST",
	WorkType.CONSTRUCTION: "CONSTRUCT",
	WorkType.CRAFTING: "CRAFT",
	WorkType.COOKING: "CRAFT",
	WorkType.FARMING: "HARVEST",
	WorkType.HAULING: "STORE",
	WorkType.RESEARCH: "RESEARCH",
	WorkType.COMBAT: "COMBAT",
	WorkType.HUNTING: "HUNTING",
}

# 资源类型到工作类型的映射（用于采集任务）
const RESOURCE_TO_WORK = {
	"TREE": WorkType.WOODCUTTING,
	"STONE_DEPOSIT": WorkType.MINING,
	"IRON_DEPOSIT": WorkType.MINING,
	"COPPER_DEPOSIT": WorkType.MINING,
	"COAL_DEPOSIT": WorkType.MINING,
	"BERRY_BUSH": WorkType.FARMING,
}

# 工作类型列表（用于遍历）
const ALL_WORK_TYPES = [
	WorkType.MINING,
	WorkType.WOODCUTTING,
	WorkType.CONSTRUCTION,
	WorkType.CRAFTING,
	WorkType.COOKING,
	WorkType.FARMING,
	WorkType.HAULING,
	WorkType.RESEARCH,
	WorkType.COMBAT,
	WorkType.HUNTING,
]

# 优先级：0=不做, 1=最低, 2=低, 3=中, 4=最高
# 每个定居者的工作优先级: settler_id -> { WorkType: priority }
var _priorities: Dictionary = {}

# 默认优先级（所有新定居者使用此配置）
var default_priorities: Dictionary = {}

func _ready():
	_init_default_priorities()

func _init_default_priorities():
	default_priorities = _load_defaults_from_config()

# 配置文件键名到工作类型的映射

func _load_defaults_from_config() -> Dictionary:
	"""从 GameConfig 读取默认工作优先级"""
	var game_config = get_node("/root/GameConfig")
	return {
		WorkType.MINING: game_config.mining_priority,
		WorkType.WOODCUTTING: game_config.woodcutting_priority,
		WorkType.CONSTRUCTION: game_config.construction_priority,
		WorkType.CRAFTING: game_config.crafting_priority,
		WorkType.COOKING: game_config.cooking_priority,
		WorkType.FARMING: game_config.farming_priority,
		WorkType.HAULING: game_config.hauling_priority,
		WorkType.RESEARCH: game_config.research_priority,
		WorkType.COMBAT: game_config.combat_priority,
		WorkType.HUNTING: game_config.hunting_priority,
	}

# -------- 优先级管理 --------

func get_priority(settler_id: String, work_type: int) -> int:
	"""获取定居者对某工作类型的优先级（0=不做）"""
	if _priorities.has(settler_id) and _priorities[settler_id].has(work_type):
		return _priorities[settler_id][work_type]
	return default_priorities.get(work_type, 0)

func set_priority(settler_id: String, work_type: int, priority: int):
	"""设置定居者对某工作类型的优先级"""
	if not _priorities.has(settler_id):
		_priorities[settler_id] = {}
	_priorities[settler_id][work_type] = clamp(priority, 0, 4)
	work_priorities_changed.emit(settler_id)

func set_all_priorities(settler_id: String, priorities: Dictionary):
	"""批量设置定居者的所有工作优先级"""
	_priorities[settler_id] = priorities.duplicate()
	work_priorities_changed.emit(settler_id)

func get_all_priorities(settler_id: String) -> Dictionary:
	"""获取定居者的所有工作优先级"""
	if _priorities.has(settler_id):
		return _priorities[settler_id].duplicate()
	return default_priorities.duplicate()

func reset_to_default(settler_id: String):
	"""将定居者的优先级重置为默认值"""
	_priorities.erase(settler_id)
	work_priorities_changed.emit(settler_id)

func reset_all():
	"""重置所有定居者的优先级"""
	_priorities.clear()
	work_priorities_changed.emit("")

func remove_settler(settler_id: String):
	"""移除定居者的优先级设置"""
	_priorities.erase(settler_id)

# -------- 定居者初始化 --------

func init_settler(settler_id: String):
	"""为新定居者初始化默认优先级"""
	if not _priorities.has(settler_id):
		_priorities[settler_id] = default_priorities.duplicate()

# -------- AI辅助查询 --------

func get_sorted_work_types(settler_id: String) -> Array:
	"""获取定居者按优先级排序的工作类型列表（优先级越高越靠前）"""
	var sorted: Array = []
	var priorities = get_all_priorities(settler_id)
	
	for wt in ALL_WORK_TYPES:
		var pri = priorities.get(wt, 0)
		if pri > 0:
			sorted.append({"work_type": wt, "priority": pri})
	
	sorted.sort_custom(func(a, b): return a.priority > b.priority)
	return sorted

func get_priority_for_task(settler_id: String, task_type: String, resource_type: String = "") -> int:
	"""根据任务类型获取该定居者对该任务的优先级（0=不做）"""
	var wt = _task_to_work_type(task_type, resource_type)
	if wt < 0:
		return 0
	return get_priority(settler_id, wt)

func is_task_allowed(settler_id: String, task_type: String, resource_type: String = "") -> bool:
	"""检查定居者是否允许执行此任务"""
	return get_priority_for_task(settler_id, task_type, resource_type) > 0

func _task_to_work_type(task_type: String, resource_type: String = "") -> int:
	"""将任务类型转换为工作类型"""
	match task_type:
		"CONSTRUCT":
			return WorkType.CONSTRUCTION
		"CRAFT":
			return WorkType.CRAFTING
		"STORE":
			return WorkType.HAULING
		"RESEARCH":
			return WorkType.RESEARCH
		"COMBAT":
			return WorkType.COMBAT
		"HUNTING":
			return WorkType.HUNTING
		"HARVEST":
			# 根据资源类型判断
			if resource_type != "":
				return RESOURCE_TO_WORK.get(resource_type, WorkType.WOODCUTTING)
			return WorkType.WOODCUTTING
		_:
			return -1

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var data = {}
	for sid in _priorities:
		data[sid] = _priorities[sid].duplicate()
	return data

func from_dict(data: Dictionary):
	_priorities.clear()
	for sid in data:
		_priorities[sid] = data[sid].duplicate()
