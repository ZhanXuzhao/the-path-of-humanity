# 定居者角色 - Settler
# 管理每个NPC角色的属性、状态、行为和AI
extends Node2D
class_name Settler

signal needs_changed(need_id: String, value: float)
signal task_assigned(task_id: String)
signal task_completed(task_id: String)

const ItemDefinitions = preload("res://resources/item_definitions.gd")

# 角色属性
var settler_name: String
var settler_id: String

# 视觉
var settler_sprite: Sprite2D

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

# 性别
enum Gender {
	MALE,
	FEMALE,
}

var state: SettlerState = SettlerState.IDLE
var gender: Gender
var hp: float = 100.0
var max_hp: float = 100.0
var move_speed: float = 60.0  # 像素/秒
var carry_capacity: float = 50.0  # 负重上限

# 当前行为
var current_task = null  # 当前任务数据
var target_position: Vector2i
var inventory

# 移动和工作的中间变量
var target_world_pos: Vector2 = Vector2.ZERO   # 移动目标（像素坐标）
var work_accumulator: float = 0.0               # 工作累积计时器
var work_tick_interval: float = 0.5             # 每次工作刻的间隔（秒）
var is_working_on_construction: bool = false    # 是否正在建造建筑

# 选中状态
var is_selected: bool = false

# 年龄和寿命
var age: float
var lifespan: float = 80.0

func _init():
	settler_id = str(Time.get_ticks_usec())
	inventory = Inventory.new(10, 30)
	_randomize_name()
	_randomize_stats()
	_randomize_age()
	_setup_sprite()

const TILE_SIZE: float = 32.0

func _setup_sprite():
	settler_sprite = Sprite2D.new()
	settler_sprite.texture = _pick_character_texture()
	# 自动缩放到一个格子大小
	var tex_size = settler_sprite.texture.get_size()
	var scale_factor = TILE_SIZE / max(tex_size.x, tex_size.y)
	settler_sprite.scale = Vector2(scale_factor, scale_factor)
	settler_sprite.z_index = 3
	add_child(settler_sprite)

# 根据性别和年龄随机选择一个合适的角色贴图
func _pick_character_texture() -> Texture2D:
	var base_path = "res://assets/art/characters/"
	match gender:
		Gender.MALE:
			if age < 8.0:
				return load(base_path + "player_little_boy.png")
			elif age < 14.0:
				return load(base_path + "player_boy.png")
			elif age < 40.0:
				var choices = ["player_young_man.png", "player_young_man2.png", "player_young_man3.png"]
				return load(base_path + choices[randi() % choices.size()])
			else:
				return load(base_path + "player_man2.png")
		Gender.FEMALE:
			if age < 8.0:
				return load(base_path + "player_little_girl.png")
			elif age < 14.0:
				var choices = ["player_girl.png", "player_girl2.png"]
				return load(base_path + choices[randi() % choices.size()])
			elif age < 40.0:
				return load(base_path + "player_woman.png")
			else:
				return load(base_path + "player_woman.png")
		_:
			return load(base_path + "player_young_man.png")

func _process(delta):
	# 暂停时停止移动和工作
	var gm = get_node("/root/GameManager")
	if gm and gm.state != gm.GameState.PLAYING:
		return
	
	match state:
		SettlerState.IDLE:
			# Game 主循环会分配任务，空闲时什么都不做
			pass
		SettlerState.MOVING:
			_move_towards(delta)
		SettlerState.WORKING:
			_execute_work(delta)

# -------- 选中状态 --------
func set_selected(selected: bool):
	"""设置选中状态，显示/隐藏选择指示圈"""
	is_selected = selected
	queue_redraw()

func _draw():
	"""绘制选择指示圈"""
	if is_selected:
		# 外圈发光
		draw_circle(Vector2.ZERO, TILE_SIZE * 0.55, Color(0.3, 0.8, 1.0, 0.0), false, 2.5)
		# 选择光环
		draw_arc(Vector2.ZERO, TILE_SIZE * 0.55, 0, TAU, 36, Color(0.3, 0.8, 1.0, 0.9), 2.5)

static func get_state_display(state_val: int) -> String:
	"""将状态枚举转换为中文显示文字"""
	match state_val:
		SettlerState.IDLE: return "空闲"
		SettlerState.MOVING: return "移动中"
		SettlerState.WORKING: return "工作中"
		SettlerState.EATING: return "进食中"
		SettlerState.SLEEPING: return "睡眠中"
		SettlerState.FLEEING: return "逃跑中"
		SettlerState.COMBAT: return "战斗中"
		_: return "未知"

# -------- 移动系统 --------
func move_to(target: Vector2):
	"""移动到目标像素位置"""
	target_world_pos = target
	state = SettlerState.MOVING

func _move_towards(delta):
	if target_world_pos == Vector2.ZERO:
		state = SettlerState.IDLE
		return
	var offset = target_world_pos - position
	var dist = offset.length()
	if dist > 2.0:
		position += offset.normalized() * move_speed * delta
	else:
		position = target_world_pos
		# 到达目标，如果是工作类任务则开始工作
		if current_task != null:
			state = SettlerState.WORKING
			work_accumulator = 0.0
		else:
			state = SettlerState.IDLE

# -------- 工作系统 --------
func _execute_work(delta):
	if current_task == null:
		state = SettlerState.IDLE
		return
	
	var task_type = current_task.get("type", "")
	if task_type == "":
		complete_task()
		return
	
	# 根据技能计算工作速度
	var skill_id = current_task.get("skill", "")
	var skill_level = get_skill(skill_id)
	var work_speed = max(0.1, skill_level * 0.4)  # 技能越高干得越快
	
	work_accumulator += delta * work_speed
	
	if work_accumulator >= work_tick_interval:
		work_accumulator -= work_tick_interval
		_do_work_tick(task_type)

func _do_work_tick(task_type: String):
	match task_type:
		"HARVEST":
			_tick_harvest()
		"CONSTRUCT":
			_tick_construct()
		"CRAFT":
			_tick_craft()

func _tick_harvest():
	"""执行一次采集工作"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		complete_task()
		return
	
	var grid_pos: Vector2i = current_task.get("target_pos", Vector2i.ZERO)
	var result = game.world.harvest_resource(grid_pos, 1.0)
	if result.is_empty() or result.amount <= 0:
		# 资源已耗尽
		complete_task()
		return
	
	# 采集到的物品直接上交到聚居地资源库
	var item_id = result.item_id
	var amount = result.amount
	var gm = get_node("/root/GameManager")
	if gm:
		gm.add_resource(item_id, amount)
	
	# 增加经验
	add_skill_experience(current_task.get("skill", ""), 1.0)

func _tick_construct():
	"""执行一次建造工作"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	
	var grid_pos: Vector2i = current_task.get("target_pos", Vector2i.ZERO)
	var bld = game.building_system.get_building_at(grid_pos)
	if bld == null:
		complete_task()
		return
	
	if bld.is_completed:
		complete_task()
		return
	
	var data = bld.get_data()
	var gm = get_node("/root/GameManager")
	
	# 首次建造时消耗材料
	if data and data.materials.size() > 0 and gm and not current_task.has("materials_consumed"):
		var can_afford = true
		for mat_id in data.materials:
			var needed = data.materials[mat_id]
			if not gm.has_resource(mat_id, needed):
				can_afford = false
				break
		if can_afford:
			for mat_id in data.materials:
				var needed = data.materials[mat_id]
				gm.remove_resource(mat_id, needed)
			current_task["materials_consumed"] = true
		else:
			# 材料不足，稍后再试
			return
	
	# 增加建造进度（技能越高建造越快）
	var skill_level = get_skill("construction")
	var work_amount = 1.0 + skill_level * 0.3
	game.building_system.add_construction_progress(grid_pos, work_amount)
	
	# 检查是否刚完成
	if game.building_system.get_building_at(grid_pos) and game.building_system.get_building_at(grid_pos).is_completed:
		var name_str = data.name if data else "建筑"
		var gm_notify = get_node("/root/GameManager")
		if gm_notify:
			gm_notify.show_notification("%s 建造完成！" % name_str, gm_notify.NotificationType.SUCCESS)
		complete_task()
	
	add_skill_experience("construction", 1.0)

func _tick_craft():
	"""执行一次制作工作"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.crafting_system == null:
		complete_task()
		return
	
	var building_pos: Vector2i = current_task.get("building_pos", Vector2i.ZERO)
	var recipe_id: String = current_task.get("recipe_id", "")
	
	if recipe_id == "":
		complete_task()
		return
	
	# 查找对应制作任务并推进进度
	var queue = game.crafting_system.get_or_create_queue(building_pos)
	var recipe = ItemDefinitions.get_recipe(recipe_id)
	if recipe == null:
		complete_task()
		return
	
	for job in queue:
		if job.recipe_id == recipe_id and job.is_active:
			# 推进制作进度
			var work_speed = get_skill(current_task.get("skill", "")) * 0.5
			job.progress += work_speed
			add_skill_experience(current_task.get("skill", ""), 1.0)
			
			# 检查是否完成
			if job.progress >= recipe.work_time:
				game.crafting_system.complete_crafting(job, recipe)
				queue.erase(job)
				game.crafting_system.active_jobs.erase(job)
				# 如果是重复任务，重新加入队列
				if job.repeat:
					var new_job = game.crafting_system.CraftingJob.new(recipe_id, building_pos, settler_id)
					new_job.repeat = true
					queue.append(new_job)
					game.crafting_system._try_start_next_job(building_pos)
				complete_task()
			return
	
	# 没有找到对应的活跃任务
	complete_task()

func _randomize_name():
	var first_names_male = ["阿明", "大壮", "铁柱", "志强", "建国"]
	var first_names_female = ["小芳", "阿珍", "翠花", "秀英", "丽华"]
	var last_names = ["李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴"]
	var is_male = randi() % 2 == 0
	if is_male:
		gender = Gender.MALE
		settler_name = last_names[randi() % last_names.size()] + first_names_male[randi() % first_names_male.size()]
	else:
		gender = Gender.FEMALE
		settler_name = last_names[randi() % last_names.size()] + first_names_female[randi() % first_names_female.size()]

func _randomize_age():
	age = 10.0 + randi() % 51  # 10~60 岁

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
	
	# 设置移动目标（像素坐标）
	var target_pixel = task_data.get("target_world_pos", Vector2.ZERO)
	if target_pixel != Vector2.ZERO:
		target_world_pos = target_pixel
		state = SettlerState.MOVING
	else:
		# 没有目标位置则直接开始工作
		state = SettlerState.WORKING
		work_accumulator = 0.0
	
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
		"gender": gender,
		"stats": stats.duplicate(),
		"skills": skills.duplicate(),
		"needs": needs.duplicate(),
		"hp": hp,
		"max_hp": max_hp,
		"age": age,
		"position": {"x": position.x, "y": position.y},
		"state": state,
		"inventory": inventory.to_dict(),
	}

func from_dict(data: Dictionary):
	settler_id = data.id
	gender = data.get("gender", Gender.MALE)
	stats = data.stats
	skills = data.skills
	needs = data.needs
	hp = data.hp
	max_hp = data.max_hp
	age = data.age
	position = Vector2(data.get("position", {}).get("x", 0.0), data.get("position", {}).get("y", 0.0))
	state = data.get("state", SettlerState.IDLE)
	inventory.from_dict(data.inventory)
	# 反序列化后更新角色贴图和缩放
	if settler_sprite:
		settler_sprite.texture = _pick_character_texture()
		var tex_size = settler_sprite.texture.get_size()
		var scale_factor = TILE_SIZE / max(tex_size.x, tex_size.y)
		settler_sprite.scale = Vector2(scale_factor, scale_factor)
