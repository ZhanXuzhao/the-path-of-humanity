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

# 需求衰减速度（每小时）——从 GameManager.settings 加载
var NEED_DECAY = {
	"hunger": 4.17,
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

# 读取 GameManager 配置的快捷方式
static func _settler_setting(key: String, default_value):
	var gm = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	if gm and gm.settings.has(key):
		return gm.settings[key]
	return default_value

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
	# 从GameManager配置加载参数
	_apply_config_settings()

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
		SettlerState.SLEEPING:
			_tick_sleep(delta)
		SettlerState.EATING:
			_tick_eat(delta)

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
		# 到达目标，根据任务类型切换状态
		if current_task != null:
			var task_type = current_task.get("type", "")
			match task_type:
				"SLEEP":
					_tick_go_sleep()
				"EAT_FROM_RACK":
					_tick_eat_from_rack()
				_:
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
		"STORE":
			_tick_store()
		"EAT_FROM_RACK":
			_tick_eat_from_rack()
		"SLEEP":
			_tick_go_sleep()

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
	
	var item_id = result.item_id
	var amount = result.amount
	var gm = get_node("/root/GameManager")
	
	# 采集到背包（优先放入个人背包）
	inventory.add_item(item_id, amount)
	
	# 检查是否超重，超重则自动存储到附近置物架
	if is_overweight():
		_store_excess_to_storage()
	
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

# -------- 库存负重管理 --------
func get_inventory_weight() -> float:
	"""计算背包中所有物品的总重量"""
	var total = 0.0
	for stack in inventory.items:
		var data = stack.get_data()
		if data:
			total += data.weight * stack.amount
	return total

func is_overweight() -> bool:
	"""是否超过负重上限"""
	return get_inventory_weight() > carry_capacity

func _store_excess_to_storage():
	"""将背包中超重的部分存入附近置物架，若无可用的则上交全局"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		# 没有存储系统，直接上交全局
		_dump_inventory_to_global()
		return
	
	# 找附近已完成的存储建筑（置物架/仓库）
	var storage_buildings = _find_nearby_storage()
	if storage_buildings.is_empty():
		_dump_inventory_to_global()
		return
	
	# 从最近的存储建筑开始尝试存入
	for bld in storage_buildings:
		if bld.inventory == null or bld.inventory.is_full():
			continue
		
		# 把背包物品转移到置物架（只转移超重部分）
		var to_store = []
		var weight = get_inventory_weight()
		var target_weight = carry_capacity * 0.7  # 降到70%负重
		
		for i in range(inventory.items.size() - 1, -1, -1):
			if weight <= target_weight:
				break
			var stack = inventory.items[i]
			if stack == null:
				continue
			var data = stack.get_data()
			if data == null:
				continue
			var stack_weight = data.weight * stack.amount
			if weight - stack_weight >= target_weight:
				# 整组转移
				var remaining = bld.inventory.add_item(stack.item_id, stack.amount)
				if remaining < stack.amount:
					inventory.remove_item(stack.item_id, stack.amount - remaining)
					weight -= stack_weight - remaining * data.weight
			else:
				# 转移部分
				var move_count = floori((weight - target_weight) / data.weight)
				move_count = max(1, move_count)
				var remaining = bld.inventory.add_item(stack.item_id, move_count)
				var actual = move_count - remaining
				if actual > 0:
					inventory.remove_item(stack.item_id, actual)
					weight -= actual * data.weight
		
		if not is_overweight():
			break

func _dump_inventory_to_global():
	"""背包物品全部上交全局资源（兜底方案）"""
	var gm = get_node("/root/GameManager")
	if gm == null:
		return
	for i in range(inventory.items.size() - 1, -1, -1):
		var stack = inventory.items[i]
		if stack:
			gm.add_resource(stack.item_id, stack.amount)
	inventory.clear()

func _find_nearby_storage(max_dist: float = -1.0) -> Array:
	"""查找附近有空间的存储建筑，按距离排序"""
	if max_dist < 0:
		max_dist = _settler_setting("storage_search_radius", 300.0)
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return []
	
	var result = []
	for bld in game.building_system.get_all_buildings():
		if not bld.is_completed:
			continue
		var data = bld.get_data()
		if data == null or data.storage_capacity <= 0:
			continue
		if bld.inventory == null or bld.inventory.is_full():
			continue
		var center = _bld_world_center(bld)
		var dist = position.distance_to(center)
		if dist <= max_dist:
			result.append({"bld": bld, "dist": dist})
	
	result.sort_custom(func(a, b): return a.dist < b.dist)
	var sorted = []
	for entry in result:
		sorted.append(entry.bld)
	return sorted

func _bld_world_center(bld) -> Vector2:
	"""获取建筑的世界坐标中心"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return Vector2.ZERO
	var ts = game.world.tile_size
	var size = bld.get_size()
	return Vector2(
		bld.grid_pos.x * ts + size.x * ts / 2.0,
		bld.grid_pos.y * ts + size.y * ts / 2.0
	)

# -------- 存储任务（搬运） --------
func _tick_store():
	"""执行一次存储工作"""
	var game = get_node_or_null("/root/Game")
	if game == null:
		complete_task()
		return
	
	var target_bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	var item_id: String = current_task.get("item_id", "")
	var amount: int = current_task.get("amount", 0)
	
	if item_id == "" or amount <= 0:
		complete_task()
		return
	
	# 从背包移除物品并存入建筑
	var bld = game.building_system.get_building_at(target_bld_pos)
	if bld == null or bld.inventory == null:
		complete_task()
		return
	
	var removed = inventory.remove_item(item_id, amount)
	if removed > 0:
		bld.inventory.add_item(item_id, removed)
	
	complete_task()

# -------- 睡眠系统 --------
func try_sleep(bld_pos: Vector2i, world_pos: Vector2):
	"""尝试去睡觉"""
	current_task = {"type": "SLEEP", "target_bld_pos": bld_pos}
	target_world_pos = world_pos
	state = SettlerState.MOVING

func _tick_go_sleep():
	"""移动到睡眠位置后开始睡觉"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	var bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	var bld = game.building_system.get_building_at(bld_pos)
	if bld == null:
		complete_task()
		return
	state = SettlerState.SLEEPING

func _tick_sleep(delta):
	"""睡眠中恢复精力"""
	var gm = get_node("/root/GameManager")
	var delta_hours = 1.0
	if gm:
		delta_hours = gm.time_speed * delta * (24.0 / gm.day_length)
	
	# 快速恢复精力
	var sleep_restore = _settler_setting("sleep_restore_per_hour", 15.0)
	modify_need("rest", delta_hours * sleep_restore)
	
	# 检查是否天亮了或精力已满
	if needs["rest"] >= 95.0:
		complete_task()
		state = SettlerState.IDLE
		return
	
	# 检查是否白天了
	if gm:
		var hour = int(gm.game_time)
		if hour >= 6 and hour < 18:
			complete_task()
			state = SettlerState.IDLE

func find_nearest_residential() -> Dictionary:
	"""查找最近的居住建筑（帐篷/房屋），返回{pos, world_pos}"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return {}
	
	var residential_ids = ["tent", "house"]
	var best = null
	var best_dist = INF
	
	for bld in game.building_system.get_all_buildings():
		if not bld.is_completed:
			continue
		if bld.building_id in residential_ids:
			var center = _bld_world_center(bld)
			var dist = position.distance_squared_to(center)
			if dist < best_dist:
				best_dist = dist
				best = {"pos": bld.grid_pos, "world_pos": center}
	
	return best if best else {}

# -------- 进食系统 --------
func try_eat():
	"""尝试进食——检查背包食物、置物架食物、或去采集"""
	var game = get_node_or_null("/root/Game")
	if game == null:
		return
	
	# 1. 先吃背包里的食物
	var food_restore = _settler_setting("food_restore_amount", 100.0)
	var food_ids = ["berry", "cooked_meat", "raw_meat", "bread", "vegetable_soup"]
	for food_id in food_ids:
		if inventory.has_item(food_id, 1):
			var removed = inventory.remove_item(food_id, 1)
			if removed > 0:
				modify_need("hunger", food_restore)
				state = SettlerState.EATING
				# 将进食动画计时器设为2秒
				_eat_timer = 2.0
				return
	
	# 2. 背包没食物，找置物架
	var food_source = _find_food_in_storage()
	if not food_source.is_empty():
		var center = _bld_world_center(food_source.bld)
		current_task = {
			"type": "EAT_FROM_RACK",
			"target_bld_pos": food_source.bld.grid_pos,
			"food_id": food_source.food_id,
			"target_world_pos": center
		}
		target_world_pos = center
		state = SettlerState.MOVING
		return
	
	# 3. 都没有的话，去找浆果丛采集
	_find_and_harvest_berries()

var _eat_timer: float = 0.0

func _tick_eat(delta):
	"""进食中恢复饱食度"""
	if _eat_timer > 0:
		_eat_timer -= delta
		if _eat_timer <= 0:
			complete_task()
			state = SettlerState.IDLE

func _tick_eat_from_rack():
	"""从置物架取食物并进食"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	
	var bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	var food_id: String = current_task.get("food_id", "")
	if food_id == "":
		complete_task()
		return
	
	var bld = game.building_system.get_building_at(bld_pos)
	if bld == null or bld.inventory == null:
		complete_task()
		return
	
	# 从置物架取一份食物
	var food_restore = _settler_setting("food_restore_amount", 100.0)
	var removed = bld.inventory.remove_item(food_id, 1)
	if removed > 0:
		modify_need("hunger", food_restore)
		_eat_timer = 2.0
		state = SettlerState.EATING
	else:
		complete_task()
		state = SettlerState.IDLE

func _find_food_in_storage() -> Dictionary:
	"""在附近的存储建筑中查找食物，返回{bld, food_id}"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return {}
	
	var food_ids = ["berry", "cooked_meat", "raw_meat", "bread", "vegetable_soup"]
	var search_dist = _settler_setting("food_search_radius", 400.0)
	var storage_buildings = _find_nearby_storage(search_dist)
	
	for bld in storage_buildings:
		if bld.inventory == null:
			continue
		for food_id in food_ids:
			if bld.inventory.has_item(food_id, 1):
				return {"bld": bld, "food_id": food_id}
	
	return {}

func _find_and_harvest_berries():
	"""找最近的浆果丛去采集"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return
	
	# 搜索周围区块找浆果丛
	var search_radius = 4
	var center_chunk = game.world.global_to_chunk(Vector2i(
		int(position.x / game.world.tile_size),
		int(position.y / game.world.tile_size)
	))
	
	var best_pos = null
	var best_dist = INF
	
	for cx in range(center_chunk.x - search_radius, center_chunk.x + search_radius + 1):
		for cy in range(center_chunk.y - search_radius, center_chunk.y + search_radius + 1):
			var chunk_pos = Vector2i(cx, cy)
			game.world.ensure_chunk_generated(chunk_pos)
			var chunk = game.world.get_chunk(chunk_pos)
			if not chunk.is_generated:
				continue
			for local_pos in chunk.resources:
				var dep = chunk.resources[local_pos]
				if dep == null or dep.amount <= 0:
					continue
				if dep.type != game.world.ResourceNodeType.BERRY_BUSH:
					continue
				var global_pos = chunk_pos * game.world.CHUNK_SIZE + local_pos
				var world_pos = Vector2(
					global_pos.x * game.world.tile_size + game.world.tile_size / 2.0,
					global_pos.y * game.world.tile_size + game.world.tile_size / 2.0
				)
				var dist = position.distance_squared_to(world_pos)
				if dist < best_dist:
					best_dist = dist
					best_pos = {"global_pos": global_pos, "world_pos": world_pos}
	
	if best_pos != null:
		current_task = {
			"type": "HARVEST",
			"target_pos": best_pos.global_pos,
			"target_world_pos": best_pos.world_pos,
			"skill": "woodcutting",
			"priority": 4,
		}
		target_world_pos = best_pos.world_pos
		state = SettlerState.MOVING

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

func _apply_config_settings():
	"""从GameManager.config加载可配置参数"""
	var base_hp = _settler_setting("base_hp", 80.0)
	var con_bonus = _settler_setting("constitution_hp_bonus", 4.0)
	var base_speed = _settler_setting("base_move_speed", 60.0)
	var dex_bonus = _settler_setting("dexterity_move_bonus", 3.0)
	carry_capacity = _settler_setting("carry_capacity", 50.0)
	
	hp = base_hp + stats.constitution * con_bonus
	max_hp = hp
	move_speed = base_speed + stats.dexterity * dex_bonus
	
	# 加载需求衰减配置
	NEED_DECAY["hunger"] = _settler_setting("hunger_decay_per_hour", 4.17)
	NEED_DECAY["rest"] = _settler_setting("rest_decay_per_hour", 3.0)
	NEED_DECAY["comfort"] = _settler_setting("comfort_decay_per_hour", 1.0)
	NEED_DECAY["social"] = _settler_setting("social_decay_per_hour", 2.0)
	NEED_DECAY["safety"] = _settler_setting("safety_decay_per_hour", 0.5)

func _randomize_stats():
	var rng = RandomNumberGenerator.new()
	for stat in stats:
		stats[stat] = rng.randf_range(3.0, 8.0)
	for skill in skills:
		skills[skill] = rng.randf_range(1.0, 5.0)
	_apply_config_settings()

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
	# 死亡时把背包物品掉到地上（放到全局资源池作为简化）
	var gm = get_node("/root/GameManager")
	if gm and inventory:
		for stack in inventory.items:
			gm.add_resource(stack.item_id, stack.amount)
	var game = get_node_or_null("/root/Game")
	if game:
		game.settlers.erase(self)
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
