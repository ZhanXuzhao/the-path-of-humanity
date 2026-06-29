# 定居者角色 - Settler
# 管理每个NPC角色的属性、状态、行为和AI
extends Node2D
class_name Settler

signal needs_changed(need_id: String, value: float)
signal task_assigned(task_id: String)
signal task_completed(task_id: String)

# 角色属性
var settler_name: String
var settler_id: String

# 基础属性
var stats = {
	"strength": 5.0,     # 力量 - 影响近战、搬运
	"constitution": 5.0, # 体质 - 影响生命、耐力
	"dexterity": 5.0,    # 敏捷 - 影响移动、制作
	"intelligence": 5.0, # 智力 - 影响研究、医疗
	"perception": 5.0,   # 感知 - 影响采集、狩猎
	"charisma": 5.0,     # 魅力 - 影响交易、社交
}

# 技能等级
var skills = {
	"mining": 3.0,       # 采矿
	"woodcutting": 3.0,  # 伐木
	"construction": 3.0, # 建造
	"crafting": 3.0,     # 制作
	"cooking": 3.0,      # 烹饪
	"farming": 3.0,      # 农业
	"research": 3.0,     # 研究
	"combat": 3.0,       # 战斗
	"social": 3.0,       # 社交
}

# 需求系统 (0-100)
var needs = {
	"hunger": 80.0,      # 饱食度 - 随时间降低
	"rest": 80.0,        # 精力 - 随时间降低
	"comfort": 50.0,     # 舒适度 - 受环境影响
	"social": 50.0,      # 社交 - 孤独降低
	"safety": 80.0,      # 安全感 - 受防御影响
}

# 需求衰减速度（每小时）
const NEED_DECAY = {
	"hunger": 5.0,
	"rest": 3.0,
	"comfort": 1.0,
	"social": 2.0,
	"safety": 0.5,
}

# 状态
enum SettlerState {
	IDLE,           # 空闲
	MOVING,         # 移动中
	WORKING,        # 工作中
	EATING,         # 进食中
	SLEEPING,       # 睡眠中
	FLEEING,        # 逃跑
	COMBAT,         # 战斗
}

var state: SettlerState = SettlerState.IDLE
var hp: float = 100.0
var max_hp: float = 100.0
var move_speed: float = 60.0  # 像素/秒
var carry_capacity: float = 50.0  # 负重上限

# 当前行为
var current_task = null  # 当前任务数据
var target_position: Vector2i
var inventory

# 年龄和寿命
var age: float = 20.0
var lifespan: float = 80.0

func _init():
	settler_id = str(Time.get_ticks_usec())
	inventory = Inventory.new(10, 30)
	_randomize_name()
	_randomize_stats()

func _randomize_name():
	var first_names = ["阿明", "小芳", "大壮", "阿珍", "铁柱", "翠花", "志强", "秀英", "建国", "丽华"]
	var last_names = ["李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴"]
	settler_name = last_names[randi() % last_names.size()] + first_names[randi() % first_names.size()]

func _randomize_stats():
	var rng = RandomNumberGenerator.new()
	for stat in stats:
		stats[stat] = rng.randf_range(3.0, 8.0)
	for skill in skills:
		skills[skill] = rng.randf_range(1.0, 5.0)
	hp = 80.0 + stats.constitution * 4.0
	max_hp = hp
	move_speed = 50.0 + stats.dexterity * 3.0

# -------- 需求更新 --------
func update_needs(delta_hours: float):
	"""更新需求值（每帧调用）"""
	for need_id in needs:
		var decay = NEED_DECAY.get(need_id, 1.0) * delta_hours
		needs[need_id] = max(0.0, needs[need_id] - decay)
		needs_changed.emit(need_id, needs[need_id])

func modify_need(need_id: String, amount: float):
	"""修改需求值"""
	if needs.has(need_id):
		needs[need_id] = clampf(needs[need_id] + amount, 0.0, 100.0)
		needs_changed.emit(need_id, needs[need_id])

func get_most_pressing_need() -> String:
	"""返回最迫切的需求"""
	var lowest = 100.0
	var lowest_id = ""
	for need_id in needs:
		if needs[need_id] < lowest:
			lowest = needs[need_id]
			lowest_id = need_id
	return lowest_id

# -------- 技能系统 --------
func get_skill(skill_id: String) -> float:
	return skills.get(skill_id, 1.0)

func add_skill_experience(skill_id: String, amount: float):
	if skills.has(skill_id):
		skills[skill_id] += amount * 0.1

# -------- 任务系统 --------
func assign_task(task_data: Dictionary) -> bool:
	"""分配任务，返回是否可以接受"""
	current_task = task_data
	state = SettlerState.WORKING
	task_assigned.emit(task_data.get("id", ""))
	return true

func complete_task():
	if current_task:
		task_completed.emit(current_task.get("id", ""))
	current_task = null
	state = SettlerState.IDLE

# -------- 伤害系统 --------
func take_damage(amount: float):
	hp -= amount
	if hp <= 0:
		die()

func heal(amount: float):
	hp = min(max_hp, hp + amount)

func die():
	queue_free()

# -------- 序列化 --------
func to_dict() -> Dictionary:
	return {
		"id": settler_id,
		"name": settler_name,
		"stats": stats.duplicate(),
		"skills": skills.duplicate(),
		"needs": needs.duplicate(),
		"hp": hp,
		"max_hp": max_hp,
		"age": age,
		"inventory": inventory.to_dict(),
	}

func from_dict(data: Dictionary):
	settler_id = data.id
	settler_name = data.name
	stats = data.stats
	skills = data.skills
	needs = data.needs
	hp = data.hp
	max_hp = data.max_hp
	age = data.age
	inventory.from_dict(data.inventory)
