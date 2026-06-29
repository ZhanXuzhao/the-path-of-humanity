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

# 状态切换冷却（至少间隔1秒）
var _last_state_change_time: float = 0.0
const STATE_CHANGE_COOLDOWN: float = 1.0

# 对当前任务目标建筑的尝试计数器（防止反复分配同一缺物资建筑）
var _construction_retry_count: int = 0
const MAX_CONSTRUCTION_RETRIES: int = 2

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
	"""绘制选择指示框"""
	if is_selected:
		var half_size = TILE_SIZE * 0.5
		var rect = Rect2(-half_size, -half_size, TILE_SIZE, TILE_SIZE)
		# 淡蓝色半透明填充
		draw_rect(rect, Color(0.3, 0.8, 1.0, 0.15), true)
		# 蓝色边框
		draw_rect(rect, Color(0.3, 0.8, 1.0, 0.9), false, 2.0)

# 根据任务数据获取工作类别显示文字
static func get_work_type_from_task(current_task: Dictionary) -> String:
	"""从任务数据中提取工作类别名称"""
	if current_task.is_empty():
		return ""
	var task_type = current_task.get("type", "")
	match task_type:
		"HARVEST":
			var skill = current_task.get("skill", "")
			match skill:
				"mining": return "采矿"
				"woodcutting": return "伐木"
				_: return "采集"
		"CONSTRUCT": return "建造"
		"HAUL_CONSTRUCT": return "搬运"
		"CRAFT": return "制作"
		"STORE": return "搬运"
		"RESEARCH": return "研究"
		"COMBAT": return "战斗"
		"EAT_FROM_RACK": return "进食"
		"SLEEP": return "睡眠"
		_: return ""

static func get_state_display(state_val: int, current_task: Dictionary = {}) -> String:
	"""将状态枚举转换为中文显示文字"""
	match state_val:
		SettlerState.IDLE: return "无工作"
		SettlerState.MOVING:
			var work_name = get_work_type_from_task(current_task)
			if work_name != "":
				return work_name + "中"
			return "移动中"
		SettlerState.WORKING:
			var work_name = get_work_type_from_task(current_task)
			if work_name != "":
				return work_name + "中"
			return "工作中"
		SettlerState.EATING: return "进食中"
		SettlerState.SLEEPING: return "睡眠中"
		SettlerState.FLEEING: return "逃跑中"
		SettlerState.COMBAT: return "战斗中"
		_: return "未知"

# -------- 移动系统 --------
func move_to(target: Vector2):
	"""移动到目标像素位置"""
	target_world_pos = target
	set_state(SettlerState.MOVING)

func _move_towards(delta):
	if target_world_pos == Vector2.ZERO:
		set_state(SettlerState.IDLE, true)  # 强制切换，防止无目标时卡在MOVING
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
				"STORE":
					# STORE 任务不需要工作刻，到达后立即执行存储
					_tick_store()
				"HAUL_CONSTRUCT":
					# 搬运物资任务：根据当前阶段处理
					var haul_phase = current_task.get("haul_phase", "fetch")
					if haul_phase == "fetch":
						# 已到达来源地，进入取货阶段
						_tick_haul_construct_fetch()
					elif haul_phase == "deliver":
						# 已到达目标建筑，立即存放入库
						_tick_haul_construct()
				_:  # 其他任务类型 → 到达后开始工作
					# 到达目标后强制开始工作（防止被冷却阻挡导致卡在MOVING→autonomy打断循环）
					set_state(SettlerState.WORKING, true)
					work_accumulator = 0.0
		else:
			set_state(SettlerState.IDLE, true)  # 强制切换

# -------- 工作系统 --------
func _execute_work(delta):
	if current_task == null:
		set_state(SettlerState.IDLE, true)  # 强制切换，防止无任务时卡在WORKING
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
		"HAUL_CONSTRUCT":
			_tick_haul_construct()
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
	
	# 检查是否超重，超重则去置物架存放
	if is_overweight():
		complete_task()
		return
	
	# 增加经验
	add_skill_experience(current_task.get("skill", ""), 1.0)

func _tick_construct():
	"""执行一次建造工作——分两阶段：先搬运物资，物资齐了再建造"""
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
	if data == null:
		complete_task()
		return
	
	var gm = get_node("/root/GameManager")
	
	# ========== 阶段1：搬运建筑材料 ==========
	var construct_phase = current_task.get("construct_phase", "")
	
	if construct_phase == "fetch":
		# 到达来源地，取材料到背包
		var fetch_source = current_task.get("fetch_source_type", "storage")
		var fetch_item = current_task.get("fetch_item_id", "")
		var fetch_amount = current_task.get("fetch_amount", 0)
		
		if fetch_item != "" and fetch_amount > 0:
			if fetch_source == "ground":
				# 从地面捡取
				var ground_pos: Vector2i = current_task.get("fetch_storage_pos", Vector2i.ZERO)
				var picked = game.world.pickup_from_ground(ground_pos, fetch_item, fetch_amount)
				if picked > 0:
					inventory.add_item(fetch_item, picked)
					current_task["fetch_amount"] = fetch_amount - picked
			else:
				# 从存储建筑取
				var storage_pos: Vector2i = current_task.get("fetch_storage_pos", Vector2i.ZERO)
				var storage_bld = game.building_system.get_building_at(storage_pos)
				if storage_bld != null and storage_bld.inventory != null:
					var available = storage_bld.inventory.get_item_count(fetch_item)
					var to_take = mini(fetch_amount, available)
					if to_take > 0:
						var removed = storage_bld.inventory.remove_item(fetch_item, to_take)
						if removed > 0:
							inventory.add_item(fetch_item, removed)
							current_task["fetch_amount"] = fetch_amount - removed
		
		# 转向回建筑工地
		current_task["construct_phase"] = "return_to_site"
		var site_center = _bld_world_center(bld)
		target_world_pos = site_center
		set_state(SettlerState.MOVING)
		return
	
	if construct_phase == "return_to_site":
		# 刚从存储建筑取了材料回来，存入建筑工地
		var fetch_item = current_task.get("fetch_item_id", "")
		var fetch_amount = current_task.get("fetch_amount", 0)
		if fetch_item != "" and fetch_amount > 0:
			var in_bp = inventory.get_item_count(fetch_item)
			var to_deposit = mini(in_bp, fetch_amount)
			if to_deposit > 0:
				var removed = inventory.remove_item(fetch_item, to_deposit)
				if removed > 0:
					bld.deposit_material(fetch_item, removed)
		# 清除搬运标记
		current_task.erase("fetch_storage_pos")
		current_task.erase("fetch_item_id")
		current_task.erase("fetch_amount")
		current_task.erase("construct_phase")
		# 继续检查是否还需要搬运其他材料
	
	# 检查是否还缺材料
	var missing = bld.get_missing_materials()
	if not missing.is_empty():
		# 先检查背包有没有可用的建筑材料，有的话直接存入
		var deposited_any = false
		for mat_id in missing.keys():
			if inventory.has_item(mat_id, 1):
				var in_bp = inventory.get_item_count(mat_id)
				var to_deposit = mini(in_bp, missing[mat_id])
				if to_deposit > 0:
					var removed = inventory.remove_item(mat_id, to_deposit)
					if removed > 0:
						bld.deposit_material(mat_id, removed)
						deposited_any = true
		
		if deposited_any:
			# 重新检查材料是否齐了
			missing = bld.get_missing_materials()
		
		if not missing.is_empty():
			# 检查角色是否已在建筑位置（用于判断全局取料后是否需要移动）
			var was_at_site = position.distance_to(_bld_world_center(bld)) < 10.0
			
			# 背包里的不够，去存储建筑或地面取材料
			if _construct_fetch_from_storage(bld, missing):
				# 如果角色已在建筑处，尝试直接存入背包中的材料
				if was_at_site and current_task.get("construct_phase", "") == "return_to_site":
					_immediate_deposit_materials()
					# 重新检查材料是否齐了
					missing = bld.get_missing_materials()
					if missing.is_empty():
						pass  # 材料齐了，继续建造
					else:
						# 材料还不够，继续尝试取料（递归安全，最多1层）
						if _construct_fetch_from_storage(bld, missing):
							if current_task.get("construct_phase", "") == "return_to_site":
								_immediate_deposit_materials()
								missing = bld.get_missing_materials()
								if missing.is_empty():
									pass
								else:
									# 第二次尝试后仍缺料且无可取，放弃
									_construction_retry_count += 1
									complete_task()
									return
							else:
								return  # 去取存储建筑的材料
						else:
							_construction_retry_count += 1
							complete_task()
							return
				else:
					return  # 不在建筑旁，正常移动回去，或者正在前往存储建筑
			else:
				# 没有任何材料可用，无法建造——增加重试计数防止反复分配
				_construction_retry_count += 1
				complete_task()
				return
	
	# ========== 阶段2：建造（物资已齐） ==========
	# 增加建造进度（技能越高建造越快）
	var skill_level = get_skill("construction")
	var work_amount = 1.0 + skill_level * 0.3
	game.building_system.add_construction_progress(grid_pos, work_amount)
	
	# 检查是否刚完成
	if game.building_system.get_building_at(grid_pos) and game.building_system.get_building_at(grid_pos).is_completed:
		var name_str = bld.display_name if bld.display_name != "" else (data.name if data else "建筑")
		if gm:
			gm.show_notification("%s 建造完成！" % name_str, gm.NotificationType.SUCCESS)
		complete_task()
	
	add_skill_experience("construction", 1.0)
	# 成功建造了一次，重置重试计数
	_construction_retry_count = 0

func _immediate_deposit_materials():
	"""立即存入背包中标记为建设材料的物品（用于从地面取材料后无须移动直接存入）"""
	if current_task == null:
		return
	var fetch_item = current_task.get("fetch_item_id", "")
	var fetch_amount = current_task.get("fetch_amount", 0)
	if fetch_item == "" or fetch_amount <= 0:
		return
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return
	var grid_pos: Vector2i = current_task.get("target_pos", Vector2i.ZERO)
	var bld = game.building_system.get_building_at(grid_pos)
	if bld == null:
		return
	var in_bp = inventory.get_item_count(fetch_item)
	var to_deposit = mini(in_bp, fetch_amount)
	if to_deposit > 0:
		var removed = inventory.remove_item(fetch_item, to_deposit)
		if removed > 0:
			bld.deposit_material(fetch_item, removed)
	# 清除搬运标记
	current_task.erase("fetch_storage_pos")
	current_task.erase("fetch_item_id")
	current_task.erase("fetch_amount")
	current_task.erase("construct_phase")

func _construct_fetch_from_storage(bld, missing: Dictionary) -> bool:
	"""查找最近的存储建筑或地面取建筑材料，返回是否找到材料去向"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return false
	
	var best_storage = null
	var best_mat_id = ""
	var best_dist = INF
	var best_ground_pos = null
	
	for mat_id in missing.keys():
		var needed = missing[mat_id]
		# 1. 检查存储建筑（使用专门用来取料的查询，不过滤已满的仓库）
		var storage_blds = _find_storage_with_item(mat_id, 99999)
		for sbld in storage_blds:
			if sbld.inventory == null:
				continue
			var center = _bld_world_center(sbld)
			var dist = position.distance_squared_to(center)
			if dist < best_dist:
				best_dist = dist
				best_storage = sbld
				best_mat_id = mat_id
		
		# 2. 检查地面物品
		if best_storage == null:
			var grid_center = Vector2i(
				int(position.x / game.world.tile_size),
				int(position.y / game.world.tile_size)
			)
			var ground_pos = game.world.find_nearest_ground_item(grid_center, mat_id, 10)
			if ground_pos.x >= 0:
				best_ground_pos = ground_pos
				best_mat_id = mat_id
	
	# 优先去存储建筑取材料
	if best_storage != null and best_mat_id != "":
		var needed = missing[best_mat_id]
		var center = _bld_world_center(best_storage)
		current_task["fetch_storage_pos"] = best_storage.grid_pos
		current_task["fetch_item_id"] = best_mat_id
		current_task["fetch_amount"] = needed
		current_task["construct_phase"] = "fetch"
		target_world_pos = center
		set_state(SettlerState.MOVING)
		return true
	
	# 其次从地面捡取
	if best_ground_pos != null and best_mat_id != "":
		var needed = missing[best_mat_id]
		var world_pos = Vector2(
			best_ground_pos.x * game.world.tile_size + game.world.tile_size / 2.0,
			best_ground_pos.y * game.world.tile_size + game.world.tile_size / 2.0
		)
		current_task["fetch_storage_pos"] = best_ground_pos
		current_task["fetch_item_id"] = best_mat_id
		current_task["fetch_amount"] = needed
		current_task["construct_phase"] = "fetch"
		current_task["fetch_source_type"] = "ground"  # 标记为地面来源
		target_world_pos = world_pos
		set_state(SettlerState.MOVING)
		return true
	
	return false

# ========== 搬运物资到建筑 ==========
func _tick_haul_construct_fetch():
	"""搬运物资：到达来源地后取货，然后前往目标建筑"""
	if current_task == null:
		complete_task()
		return
	
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	
	var source_type = current_task.get("source_type", "global")
	var item_id: String = current_task.get("item_id", "")
	var amount: int = current_task.get("amount", 0)
	var target_bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	
	if item_id == "" or amount <= 0:
		complete_task()
		return
	
	var taken = 0
	
	if source_type == "ground":
		# 从地面捡取
		var source_pos: Vector2i = current_task.get("source_bld_pos", Vector2i.ZERO)
		if game.world:
			taken = game.world.pickup_from_ground(source_pos, item_id, amount)
			if taken > 0:
				inventory.add_item(item_id, taken)
	elif source_type == "storage":
		# 从存储建筑取
		var source_pos: Vector2i = current_task.get("source_bld_pos", Vector2i.ZERO)
		var source_bld = game.building_system.get_building_at(source_pos)
		if source_bld != null and source_bld.inventory != null:
			var available = source_bld.inventory.get_item_count(item_id)
			var to_take = mini(amount, available)
			if to_take > 0:
				taken = source_bld.inventory.remove_item(item_id, to_take)
				if taken > 0:
					inventory.add_item(item_id, taken)
	
	if taken <= 0:
		# 没取到物资，任务失败
		complete_task()
		return
	
	# 标记已取到的物资量
	current_task["haul_phase"] = "deliver"
	current_task["fetch_amount"] = taken
	
	# 转向目标建筑
	var bld = game.building_system.get_building_at(target_bld_pos)
	if bld == null:
		complete_task()
		return
	var target_center = _bld_world_center(bld)
	target_world_pos = target_center
	set_state(SettlerState.MOVING)

func _tick_haul_construct():
	"""搬运物资：到达目标建筑后存入物资"""
	if current_task == null:
		complete_task()
		return
	
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	
	var target_bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	var item_id: String = current_task.get("item_id", "")
	var fetch_amount: int = current_task.get("fetch_amount", 0)
	
	var bld = game.building_system.get_building_at(target_bld_pos)
	if bld == null:
		complete_task()
		return
	
	if item_id != "" and fetch_amount > 0:
		var in_bp = inventory.get_item_count(item_id)
		var to_deposit = mini(in_bp, fetch_amount)
		if to_deposit > 0:
			var removed = inventory.remove_item(item_id, to_deposit)
			if removed > 0:
				# 判断是建筑工地（未完成）还是生产建筑（已完成）
				if not bld.is_completed:
					# 施工工地 - 使用deposit_material
					bld.deposit_material(item_id, removed)
				else:
					# 生产建筑 - 放入建筑库存
					if bld.inventory:
						bld.inventory.add_item(item_id, removed)
					else:
						# 没有库存就掉落在地面
						if game.world:
							game.world.drop_item_on_ground(bld.grid_pos, item_id, removed)
	
	complete_task()

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
	"""将背包中超重的部分存入附近置物架，若无可用的则掉落地面"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		_drop_inventory_to_ground()
		return
	
	# 找附近已完成的存储建筑（置物架/仓库）
	var storage_buildings = _find_nearby_storage()
	
	# 附近找不到时，扩大搜索范围到全图
	if storage_buildings.is_empty():
		storage_buildings = _find_nearby_storage(999999.0)
	
	if storage_buildings.is_empty():
		_drop_inventory_to_ground()
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

func _store_excess_to_storage_at(bld_pos: Vector2i):
	"""将背包中超重的部分存入指定建筑"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		_drop_inventory_to_ground()
		return
	
	var bld = game.building_system.get_building_at(bld_pos)
	if bld == null or bld.inventory == null:
		# 目标建筑无效（可能被拆了），尝试自动找其他存储建筑
		_auto_store_overweight()
		return
	
	var target_weight = carry_capacity * 0.7  # 降到70%负重
	var weight = get_inventory_weight()
	
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

func _auto_store_overweight():
	"""超重时自动寻找最近的置物架，创建搬运任务走过去存放"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		_drop_inventory_to_ground()
		return
	
	# 先按默认半径找附近的置物架
	var storage_buildings = _find_nearby_storage()
	
	# 如果附近找不到，扩大搜索范围到全图（不设距离限制），让角色跑远路去存放
	if storage_buildings.is_empty():
		storage_buildings = _find_nearby_storage(999999.0)
	
	if storage_buildings.is_empty():
		# 真的没有任何存储建筑，才丢到地上
		_drop_inventory_to_ground()
		return
	
	# 找最近的置物架
	var best_bld = storage_buildings[0]
	var center_pos = _bld_world_center(best_bld)
	
	# 创建搬运任务——走到置物架后自动存放超重物品
	current_task = {
		"type": "STORE",
		"target_bld_pos": best_bld.grid_pos,
		"target_world_pos": center_pos,
		"skill": "",
	}
	target_world_pos = center_pos
	set_state(SettlerState.MOVING)

func _drop_inventory_to_ground():
	"""超重且无处可存时，把背包物品掉落在地上"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return
	var grid_pos = Vector2i(
		int(position.x / game.world.tile_size),
		int(position.y / game.world.tile_size)
	)
	for i in range(inventory.items.size() - 1, -1, -1):
		var stack = inventory.items[i]
		if stack:
			game.world.drop_item_on_ground(grid_pos, stack.item_id, stack.amount)
	inventory.clear()

func _find_nearby_storage(max_dist: float = -1.0) -> Array:
	"""查找附近有空间的存储建筑（用于存放物品），按距离排序"""
	if max_dist < 0:
		max_dist = _settler_setting("storage_search_radius", 300.0)
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return []
	
	# 使用 BuildingSystem 预索引的快查方法
	var storage_blds = game.building_system.get_storage_buildings_with_space()
	
	var result = []
	for bld in storage_blds:
		var center = _bld_world_center(bld)
		var dist = position.distance_to(center)
		if dist <= max_dist:
			result.append({"bld": bld, "dist": dist})
	
	result.sort_custom(func(a, b): return a.dist < b.dist)
	var sorted = []
	for entry in result:
		sorted.append(entry.bld)
	return sorted

func _find_storage_with_item(item_id: String, max_dist: float = -1.0) -> Array:
	"""查找所有存有指定物品的存储建筑（不过滤已满），按距离排序——用于取材料"""
	if max_dist < 0:
		max_dist = _settler_setting("storage_search_radius", 300.0)
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return []
	
	# 使用 BuildingSystem 预索引的快查方法
	var storage_blds = game.building_system.get_storage_buildings_with_item(item_id, 1)
	
	var result = []
	for bld in storage_blds:
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
	
	var bld = game.building_system.get_building_at(target_bld_pos)
	if bld == null or bld.inventory == null:
		complete_task()
		return
	
	# 检查是否在存储建筑附近（防止虚空转移）
	var bld_center = _bld_world_center(bld)
	var dist_to_bld = position.distance_to(bld_center)
	var max_store_dist = _settler_setting("storage_search_radius", 300.0) * 0.3  # 默认为搜索半径的30%
	if dist_to_bld > max_store_dist:
		# 距离太远，重新走向建筑
		target_world_pos = bld_center
		set_state(SettlerState.MOVING)
		return
	
	if item_id != "" and amount > 0:
		# 指定物品——仅搬运指定物品
		var removed = inventory.remove_item(item_id, amount)
		if removed > 0:
			bld.inventory.add_item(item_id, removed)
		complete_task()
	else:
		# 未指定物品——自动存放所有超重部分
		_store_excess_to_storage_at(target_bld_pos)
		# 如果还超重，继续搬运
		if is_overweight():
			_auto_store_overweight()
			# _auto_store_overweight 可能因存储已满而将物品上交全局，
			# 此时背包已空不再超重，需要完成任务
			if not is_overweight():
				complete_task()
		else:
			complete_task()

# -------- 睡眠系统 --------
func try_sleep(bld_pos: Vector2i, world_pos: Vector2):
	"""尝试去睡觉"""
	current_task = {"type": "SLEEP", "target_bld_pos": bld_pos}
	target_world_pos = world_pos
	set_state(SettlerState.MOVING)

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
	# 到达床位后开始睡觉（受冷却控制，最多等1秒）
	set_state(SettlerState.SLEEPING)

func _tick_sleep(delta):
	"""睡眠中恢复精力"""
	var gm = get_node("/root/GameManager")
	var delta_hours = 1.0
	if gm:
		delta_hours = gm.time_speed * delta * (24.0 / gm.day_length)
	
	# 快速恢复精力
	var sleep_restore = _settler_setting("sleep_restore_per_hour", 15.0)
	modify_need("rest", delta_hours * sleep_restore)
	
	# 最少睡满1秒（防止刚入睡就被打断导致睡眠循环）
	var now = Time.get_ticks_msec() / 1000.0
	var min_sleep_time = 1.0
	
	# 检查是否天亮了或精力已满
	if needs["rest"] >= 95.0 and now - _last_state_change_time >= min_sleep_time:
		complete_task()
		return
	
	# 检查是否白天了（最少睡满1秒防循环）
	if gm and now - _last_state_change_time >= min_sleep_time:
		var hour = int(gm.game_time)
		if hour >= 6 and hour < 18:
			complete_task()

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
				# 从背包进食（受冷却控制）
				set_state(SettlerState.EATING)
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
		set_state(SettlerState.MOVING)
		return
	
	# 3. 都没有的话，去找浆果丛采集
	_find_and_harvest_berries()

var _eat_timer: float = 0.0

func _tick_eat(delta):
	"""进食中恢复饱食度"""
	if _eat_timer <= 0:
		# 安全兜底：防止因加载存档等导致 _eat_timer 为 0 而卡死
		complete_task()
		return
	_eat_timer -= delta
	if _eat_timer <= 0:
		# complete_task() 已处理状态切换（如超重时自动转为 MOVING）
		complete_task()

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
		# 到达置物架后开始进食（强制切换，防止被冷却阻挡导致反复取食）
		set_state(SettlerState.EATING, true)
	else:
		# complete_task() 已处理状态切换
		complete_task()

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
		set_state(SettlerState.MOVING)

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

# -------- 状态切换控制 --------
func set_state(new_state: SettlerState, force: bool = false) -> bool:
	"""设置状态，返回是否成功设置
	force=true 时强制切换（用于 complete_task 等关键路径）"""
	var now = Time.get_ticks_msec() / 1000.0
	if state == new_state:
		return true  # 相同状态不算切换
	var old_state_str = get_state_display(state, current_task if current_task else {})
	var new_state_str = get_state_display(new_state, current_task if current_task else {})
	state = new_state
	_last_state_change_time = now
	if is_selected and old_state_str != new_state_str:
		print("[%s] 状态切换: %s -> %s (%.1fs)%s" % [settler_name, old_state_str, new_state_str, now, " (强制)" if force else ""])
	return true

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
		set_state(SettlerState.MOVING, true)  # 强制切换，防止冷却导致任务卡住
	else:
		# 没有目标位置则直接开始工作
		set_state(SettlerState.WORKING, true)  # 强制切换，防止冷却导致任务卡住
		work_accumulator = 0.0
	
	task_assigned.emit(task_data.get("id", ""))
	return true

func complete_task(skip_auto_store: bool = false):
	if current_task:
		task_completed.emit(current_task.get("id", ""))
		# 成功完成任务，减少重试计数
		_construction_retry_count = max(0, _construction_retry_count - 1)
	current_task = null
	set_state(SettlerState.IDLE, true)  # 强制切换，防止冷却导致卡死
	
	# 如果超重，自动寻找置物架去存放物品
	# 但跳过紧急需求打断时的自动搬运，让角色先满足基本需求
	if not skip_auto_store and is_overweight():
		_auto_store_overweight()

# -------- 伤害系统 --------
func take_damage(amount: float):
	hp -= amount
	if hp <= 0:
		die()

func heal(amount: float):
	hp = min(max_hp, hp + amount)

func die():
	# 死亡时把背包物品掉在地上
	var game = get_node_or_null("/root/Game")
	if game and game.world and inventory:
		var grid_pos = Vector2i(
			int(position.x / game.world.tile_size),
			int(position.y / game.world.tile_size)
		)
		for stack in inventory.items:
			game.world.drop_item_on_ground(grid_pos, stack.item_id, stack.amount)
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
