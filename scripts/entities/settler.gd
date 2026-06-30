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

# 需求衰减速度（每小时）——从 GameConfig 加载
var NEED_DECAY = {
	"hunger": 4.17,
	"rest": 5.0,
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

# 读取 GameConfig 配置的快捷方式
static func _settler_setting(key: String, default_value):
	var gc = Engine.get_main_loop().root.get_node_or_null("/root/GameConfig")
	if gc and key in gc:
		return gc.get(key)
	return default_value

# 当前行为
var current_task = null  # 当前任务数据
var target_position: Vector2i
var inventory

# 移动和工作的中间变量
var target_world_pos: Vector2 = Vector2.ZERO   # 移动目标（像素坐标）
var _path: Array[Vector2i] = []                # A*寻路路径（网格坐标，不含起点）
var _path_target_grid: Vector2i = Vector2i(-1, -1)  # 上次计算路径的目标网格
var _last_chunk_pos: Vector2i = Vector2i(-9999, -9999)  # 上次所在区块坐标（用于世界扩张）
var work_tick_interval: float = 3.0             # 每次工作刻的间隔（秒）
var _last_work_tick_time: float = 0.0           # 上次工作刻的现实时间戳（秒）
var is_working_on_construction: bool = false    # 是否正在建造建筑

# 状态切换冷却（至少间隔1秒）
var _last_state_change_time: float = 0.0
const STATE_CHANGE_COOLDOWN: float = 1.0

# 对当前任务目标建筑的尝试计数器（防止反复分配同一缺物资建筑）
var _construction_retry_count: int = 0
const MAX_CONSTRUCTION_RETRIES: int = 2

# 选中状态
var is_selected: bool = false

# 朝向方向（单位向量），用于显示朝向小三角
var facing_direction: Vector2 = Vector2.DOWN

# 角色下方状态显示的字体缓存
var _status_font: Font = null

# 被分配到的床铺网格位置（-1表示无床）
var assigned_bed_pos: Vector2i = Vector2i(-1, -1)

# 年龄和寿命
var age: float
var lifespan: float = 80.0

func _init():
	settler_id = str(Time.get_ticks_usec())
	inventory = Inventory.new()
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
			else:
				var choices = ["player_young_man.png", "player_young_man2.png", "player_young_man3.png"]
				return load(base_path + choices[randi() % choices.size()])
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
	
	# 每帧重绘：更新角色下方状态显示（HP条、状态文字）和选中指示线
	queue_redraw()
	
	match state:
		SettlerState.IDLE:
			var _game = get_node_or_null("/root/Game")
			if _game and _game.world:
				var _grid = Vector2i(
					floori(position.x / _game.world.tile_size),
					floori(position.y / _game.world.tile_size)
				)
				if not _game.world.is_walkable(_grid):
					_move_away_from_water(_game)
					return
			
			# 自主行为已移至 Game._update_settlers 统一管理
		SettlerState.MOVING:
			_move_towards(delta)
		SettlerState.WORKING:
			_execute_work(delta)
			# 工作中朝向目标方向
			_update_facing_to_target()
		SettlerState.SLEEPING:
			_tick_sleep(delta)
		SettlerState.EATING:
			_tick_eat(delta)
		SettlerState.COMBAT:
			_tick_hunting(delta)

# -------- 选中状态 --------
func set_selected(selected: bool):
	"""设置选中状态，显示/隐藏选择指示圈"""
	is_selected = selected
	queue_redraw()

func _draw():
	"""绘制角色下方状态（HP条、状态文字）和选中指示框"""
	_draw_status_below()
	_draw_direction_triangle()
	
	if is_selected:
		var half_size = TILE_SIZE * 0.5
		var rect = Rect2(-half_size, -half_size, TILE_SIZE, TILE_SIZE)
		# 淡蓝色半透明填充
		draw_rect(rect, Color(0.3, 0.8, 1.0, 0.15), true)
		# 蓝色边框
		draw_rect(rect, Color(0.3, 0.8, 1.0, 0.9), false, 2.0)
		
		# 绘制目标指示线
		_draw_target_line()

func _draw_status_below():
	"""在角色下方绘制HP条和当前状态文字"""
	# 初始化字体缓存
	if _status_font == null:
		_status_font = ThemeDB.fallback_font
		if _status_font == null:
			return
	
	var font_size = 11
	
	# 条状共用尺寸
	var bar_width = TILE_SIZE * 0.8
	var bar_height = 3.0
	var bar_x = -bar_width / 2.0
	
	# ===== HP 条（仅受伤时显示） =====
	if hp < max_hp:
		var bar_y = -TILE_SIZE / 2.0 - bar_height - 2.0  # 精灵上方
		
		# 背景
		draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.15, 0.15, 0.8))
		
		# HP填充
		var hp_ratio = hp / max_hp if max_hp > 0 else 0.0
		var hp_color = Color(0.3, 1.0, 0.3, 0.9)  # 绿色
		if hp_ratio < 0.3:
			hp_color = Color(1.0, 0.3, 0.3, 0.9)  # 红色
		elif hp_ratio < 0.6:
			hp_color = Color(1.0, 0.8, 0.2, 0.9)  # 黄色
		if hp_ratio > 0.0:
			draw_rect(Rect2(bar_x, bar_y, bar_width * hp_ratio, bar_height), hp_color)
	
	# ===== 状态文字 =====
	var state_text = get_state_display(state, current_task if current_task else {})
	var text_y = TILE_SIZE / 2.0 + 2.0  # 精灵底部下方
	var text_size = _status_font.get_string_size(state_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2.0, text_y + text_size.y)
	
	# 文字阴影（轻微偏移增加可读性）
	_status_font.draw_string(get_canvas_item(), text_pos + Vector2(1, 1), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	# 文字本体
	_status_font.draw_string(get_canvas_item(), text_pos, state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))
	
	# ===== 工作进度条（仅工作中显示） =====
	if state == SettlerState.WORKING:
		var progress = _get_work_progress()
		if progress > 0.0:
			var prog_bar_y = text_y + text_size.y + 2.0
			# 背景
			draw_rect(Rect2(bar_x, prog_bar_y, bar_width, bar_height), Color(0.15, 0.15, 0.15, 0.8))
			# 进度填充（橙色进度条）
			var prog_color = Color(1.0, 0.7, 0.2, 0.9)  # 橙色
			draw_rect(Rect2(bar_x, prog_bar_y, bar_width * progress, bar_height), prog_color)

func _draw_target_line():
	"""绘制连接到目标位置的指示虚线（选中时显示），有导航路径时沿路径绘制"""
	if target_world_pos == Vector2.ZERO or position.distance_squared_to(target_world_pos) < 16.0:
		return
	
	var line_color = Color(0.3, 0.8, 1.0, 0.6)
	
	# 如果有导航路径，沿路径点绘制折线
	if not _path.is_empty():
		var game = get_node_or_null("/root/Game")
		var ts = game.world.tile_size if game and game.world else 32.0
		var prev_point = Vector2.ZERO  # 起点是角色自身位置（局部坐标原点）
		for grid_pos in _path:
			var wp = Vector2(
				grid_pos.x * ts + ts / 2.0,
				grid_pos.y * ts + ts / 2.0
			) - position
			draw_dashed_line(prev_point, wp, line_color, 1.5, 4.0, true)
			# 路径点小圆点
			draw_circle(wp, 1.5, line_color)
			prev_point = wp
		# 最后一段到最终目标
		var local_target = target_world_pos - position
		draw_dashed_line(prev_point, local_target, line_color, 1.5, 4.0, true)
		draw_circle(local_target, 3.0, line_color)
	else:
		# 无路径时直接画直线
		var local_target = target_world_pos - position
		draw_dashed_line(Vector2.ZERO, local_target, line_color, 1.5, 4.0, true)
		draw_circle(local_target, 3.0, line_color)

func _draw_direction_triangle():
	"""在角色朝向方向绘制一个小三角指示器"""
	var tri_size = 4.0
	var offset = TILE_SIZE * 0.5 + 2.0  # 从角色中心到边缘 + 间距
	
	# 计算三角三个顶点
	var tip = facing_direction * (offset + tri_size)
	var perp = Vector2(-facing_direction.y, facing_direction.x)
	var base_center = facing_direction * offset
	var bl = base_center + perp * tri_size * 0.5
	var br = base_center - perp * tri_size * 0.5
	
	var points = PackedVector2Array([tip, bl, br])
	var color = Color(1.0, 0.85, 0.3, 0.95)  # 金色
	draw_colored_polygon(points, color)

func _get_work_progress() -> float:
	"""返回当前工作进度 (0.0~1.0)，用于显示工作进度条"""
	if state != SettlerState.WORKING or current_task == null:
		return 0.0
	
	var task_type = current_task.get("type", "")
	if task_type == "":
		return 0.0
	
	# 计算工作速度
	var skill_id = current_task.get("skill", "")
	var skill_level = get_skill(skill_id)
	var base_speed = _settler_setting("work_speed_base", 1.0)
	var level_bonus = _settler_setting("work_speed_level_bonus", 0.1)
	var work_speed = base_speed + (skill_level - 1.0) * level_bonus
	
	var gm = get_node("/root/GameManager")
	var speed_mult = gm.time_speed if gm else 1.0
	
	var now = Time.get_ticks_msec() / 1000.0
	var adjusted_interval = work_tick_interval / (work_speed * speed_mult)
	
	if adjusted_interval <= 0:
		return 0.0
	
	var elapsed = now - _last_work_tick_time
	return clampf(elapsed / adjusted_interval, 0.0, 1.0)

# 根据任务数据获取工作类别显示文字
static func get_work_type_from_task(task_data: Dictionary) -> String:
	"""从任务数据中提取工作类别名称"""
	if task_data.is_empty():
		return ""
	var task_type = task_data.get("type", "")
	match task_type:
		"HARVEST":
			var skill = task_data.get("skill", "")
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
		"HUNTING": return "狩猎"
		"EAT_FROM_RACK": return "进食"
		"SLEEP": return "睡眠"
		_: return ""

static func get_state_display(state_val: int, task_data: Dictionary = {}) -> String:
	"""将状态枚举转换为中文显示文字"""
	match state_val:
		SettlerState.IDLE: return "无工作"
		SettlerState.MOVING:
			var work_name = get_work_type_from_task(task_data)
			if work_name != "":
				return work_name + "中"
			return "移动中"
		SettlerState.WORKING:
			var work_name = get_work_type_from_task(task_data)
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
	# 清除缓存的路径，_move_towards 会重新计算
	_path.clear()
	_path_target_grid = Vector2i(-1, -1)
	set_state(SettlerState.MOVING)
	if is_selected:
		queue_redraw()

func _move_towards(delta):
	if target_world_pos == Vector2.ZERO:
		_path.clear()
		_path_target_grid = Vector2i(-1, -1)
		LogUtil.info(self, "移动目标为零，结束当前任务")
		complete_task()
		return
	
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return
	
	var tile_ts = game.world.tile_size
	var current_grid = Vector2i(
		floori(position.x / tile_ts),
		floori(position.y / tile_ts)
	)
	
	# 检测角色是否进入了新区块，若是则生成周围区块（实现世界地图向外扩张）
	var current_chunk = game.world.global_to_chunk(current_grid)
	if current_chunk != _last_chunk_pos:
		_last_chunk_pos = current_chunk
		game.world.ensure_surrounding_chunks_generated(current_chunk)
	
	# 检查当前是否站在不可行走的地形上（兜底保护）
	if not game.world.is_walkable(current_grid):
		_path.clear()
		_path_target_grid = Vector2i(-1, -1)
		# 如果还没有逃逸目标，尝试寻找最近的可行走格子
		if target_world_pos == Vector2.ZERO:
			if not _move_away_from_water(game):
				complete_task()
			return
		# 已有逃逸目标，继续移动（允许踏出水面到相邻陆地）
	
	# 计算目标网格
	var target_grid = Vector2i(
		floori(target_world_pos.x / tile_ts),
		floori(target_world_pos.y / tile_ts)
	)
	
	# 如果路径无效或目标变了，重新计算A*路径
	if _path.is_empty() or target_grid != _path_target_grid:
		_path_target_grid = target_grid
		var start_grid = current_grid
		_path = game.world.find_path(start_grid, target_grid, 800)
		
		if _path.is_empty() and start_grid != target_grid:
			# 无路可走，取消任务
			complete_task()
			return
		
		if _path.is_empty() and start_grid == target_grid:
			# start==target：已经在目标格子上，直接进入工作状态
			pass  # 下面会处理 arrival
	
	# 沿路径前进：目标是路径中下一个网格的中心
	var target_pixel: Vector2
	if not _path.is_empty():
		var next_grid = _path[0]
		target_pixel = Vector2(
			next_grid.x * tile_ts + tile_ts / 2.0,
			next_grid.y * tile_ts + tile_ts / 2.0
		)
	else:
		target_pixel = target_world_pos
	
	var offset = target_pixel - position
	var dist = offset.length()
	
	if dist > 2.0:
		var dir = offset.normalized()
		facing_direction = dir
		var gm = get_node("/root/GameManager")
		var speed_mult = gm.time_speed if gm else 1.0
		position += dir * move_speed * delta * speed_mult
	else:
		# 到达当前路径点
		if not _path.is_empty():
			_path.remove_at(0)  # 移动到下一个路径点
			# 继续下一帧处理下一个路径点
			return
		
		# 最终目的地到达
		position = target_world_pos
		_path.clear()
		_path_target_grid = Vector2i(-1, -1)
		
		if current_task != null:
			var task_type = current_task.get("type", "")
			match task_type:
				"SLEEP":
					_tick_go_sleep()
				"EAT_FROM_RACK":
					_tick_eat_from_rack()
				"STORE":
					_tick_store()
				"HAUL_CONSTRUCT":
					var haul_phase = current_task.get("haul_phase", "fetch")
					if haul_phase == "fetch":
						_tick_haul_construct_fetch()
					elif haul_phase == "deliver":
						_tick_haul_construct()
				"HUNTING":
					# 到达狩猎区后切换到战斗状态，由 _tick_hunting 处理
					set_state(SettlerState.COMBAT, true)
				_:
					set_state(SettlerState.WORKING, true)
					_last_work_tick_time = Time.get_ticks_msec() / 1000.0
		else:
			set_state(SettlerState.IDLE, true)

func _update_facing_to_target():
	"""工作中朝向任务目标方向"""
	if current_task == null:
		return
	var target_pos = current_task.get("target_pos", Vector2i(-1, -1))
	if target_pos.x < 0:
		return
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return
	var ts = game.world.tile_size
	var target_center = Vector2(
		target_pos.x * ts + ts / 2.0,
		target_pos.y * ts + ts / 2.0
	)
	var dir = target_center - position
	if dir.length_squared() > 4.0:
		facing_direction = dir.normalized()

# -------- 工作系统 --------
func _execute_work(_delta):
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
	var base_speed = _settler_setting("work_speed_base", 1.0)
	var level_bonus = _settler_setting("work_speed_level_bonus", 0.1)
	var work_speed = base_speed + (skill_level - 1.0) * level_bonus  # 技能越高干得越快
	
	# 根据时间加速倍率同步提升工作速度
	var gm = get_node("/root/GameManager")
	var speed_mult = gm.time_speed if gm else 1.0
	
	# 基于现实时间检测工作刻，不受 delta 累积误差影响
	var now = Time.get_ticks_msec() / 1000.0
	var adjusted_interval = work_tick_interval / (work_speed * speed_mult)
	if now - _last_work_tick_time >= adjusted_interval:
		_last_work_tick_time = now
		_do_work_tick(task_type)

func _do_work_tick(task_type: String):
	LogUtil.info(self, "执行工作刻: %s" % task_type)
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
	"""执行一次采集工作——采集任务目标格子上的资源（角色站在相邻格子上采集）"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		complete_task()
		return
	
	var max_amount = _settler_setting("harvest_count", 5)
	
	# 使用任务中的 target_pos（资源格子位置）作为采集目标
	# 角色实际站在资源格子旁边的可行走格子上
	var grid_pos: Vector2i = current_task.get("target_pos", Vector2i.ZERO)
	
	# 释放该资源的占用标记
	if game.has_method("release_harvest_resource"):
		game.release_harvest_resource(grid_pos)
	
	# 采集单个资源点（最多 harvest_count 个）
	var result = game.world.harvest_resource(grid_pos, max_amount)
	if result.is_empty() or result.amount <= 0:
		# 资源已耗尽，同时移除采集标记
		if game.has_method("remove_designation_at"):
			game.remove_designation_at(grid_pos)
		complete_task()
		return
	
	var item_id = result.item_id
	var total_amount = result.amount
	
	# 采集到背包
	inventory.add_item(item_id, total_amount)
	LogUtil.info(self, "采集到 %d 个 %s" % [total_amount, item_id])
	
	# 检查是否超重——超重时去存放
	if is_overweight():
		complete_task()
		return
	
	# 重新占用该点（如果仍有剩余资源）
	var dep = game.world.get_resource_at(grid_pos)
	if dep != null and dep.amount > 0:
		if game.has_method("claim_harvest_resource"):
			game.claim_harvest_resource(grid_pos, settler_id)
	else:
		# 资源已被完全采完，移除采集标记
		if game.has_method("remove_designation_at"):
			game.remove_designation_at(grid_pos)
	
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
		# 到达来源地，取材料到背包（受负重限制）
		var fetch_source = current_task.get("fetch_source_type", "storage")
		var fetch_item = current_task.get("fetch_item_id", "")
		var fetch_amount = current_task.get("fetch_amount", 0)
		var site_center: Vector2
		
		if fetch_item != "" and fetch_amount > 0:
			# 根据剩余负重计算实际能取多少
			var max_carry = _get_max_carryable(fetch_item, fetch_amount)
			if max_carry <= 0:
				# 背包已满，直接回去工地先存入
				current_task["construct_phase"] = "return_to_site"
				site_center = _bld_world_center(bld)
				target_world_pos = site_center
				set_state(SettlerState.MOVING)
				return
			if fetch_source == "ground":
				# 从地面捡取
				var ground_pos: Vector2i = current_task.get("fetch_storage_pos", Vector2i.ZERO)
				var picked = game.world.pickup_from_ground(ground_pos, fetch_item, max_carry)
				if picked > 0:
					inventory.add_item(fetch_item, picked)
					current_task["fetch_amount"] = fetch_amount - picked
			else:
				# 从存储建筑取
				var storage_pos: Vector2i = current_task.get("fetch_storage_pos", Vector2i.ZERO)
				var storage_bld = game.building_system.get_building_at(storage_pos)
				if storage_bld != null and storage_bld.inventory != null:
					var available = storage_bld.inventory.get_item_count(fetch_item)
					var to_take = mini(max_carry, mini(fetch_amount, available))
					if to_take > 0:
						var removed = storage_bld.inventory.remove_item(fetch_item, to_take)
						if removed > 0:
							inventory.add_item(fetch_item, removed)
							current_task["fetch_amount"] = fetch_amount - removed
		
		# 转向回建筑工地
		current_task["construct_phase"] = "return_to_site"
		site_center = _bld_world_center(bld)
		target_world_pos = site_center
		set_state(SettlerState.MOVING)
		return
	
	if construct_phase == "return_to_site":
		# 刚从存储建筑取了材料回来，存入建筑工地
		# 不依赖 fetch_amount 判断（它可能在 fetch 阶段被减到0），
		# 直接检查背包里实际携带的材料并存入
		var fetch_item = current_task.get("fetch_item_id", "")
		var fetch_amount = current_task.get("fetch_amount", 0)
		if fetch_item != "":
			var in_bp = inventory.get_item_count(fetch_item)
			var to_deposit = in_bp if fetch_amount <= 0 else mini(in_bp, fetch_amount)
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

func _construct_fetch_from_storage(_bld, missing: Dictionary) -> bool:
	"""查找最近的存储建筑或地面取建筑材料，返回是否找到材料去向"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return false
	
	var cur_grid = Vector2i(
		floori(position.x / game.world.tile_size),
		floori(position.y / game.world.tile_size)
	)
	
	# 收集所有候选来源（存储建筑+地面物品），按距离排序
	var candidates: Array[Dictionary] = []
	
	for mat_id in missing.keys():
		var _needed = missing[mat_id]
		
		# 1. 存储建筑
		var storage_blds = _find_storage_with_item(mat_id, 99999)
		for sbld in storage_blds:
			if sbld.inventory == null:
				continue
			var center = _bld_world_center(sbld)
			var dist_sq = position.distance_squared_to(center)
			candidates.append({
				"type": "storage",
				"bld": sbld,
				"bld_pos": sbld.grid_pos,
				"mat_id": mat_id,
				"needed": _needed,
				"target_world_pos": center,
				"dist_sq": dist_sq,
			})
		
		# 2. 地面物品
		var grid_center = Vector2i(
			floori(position.x / game.world.tile_size),
			floori(position.y / game.world.tile_size)
		)
		var ground_pos = game.world.find_nearest_ground_item(grid_center, mat_id, 10)
		if ground_pos.x >= 0:
			var world_pos = Vector2(
				ground_pos.x * game.world.tile_size + game.world.tile_size / 2.0,
				ground_pos.y * game.world.tile_size + game.world.tile_size / 2.0
			)
			var dist_sq = position.distance_squared_to(world_pos)
			candidates.append({
				"type": "ground",
				"bld_pos": ground_pos,
				"mat_id": mat_id,
				"needed": _needed,
				"target_world_pos": world_pos,
				"dist_sq": dist_sq,
			})
	
	# 按距离排序，最近的优先
	candidates.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	
	for cand in candidates:
		var mat_id = cand.mat_id
		var needed = cand.needed
		var target_wp = cand.target_world_pos
		
		# 检查负重限额
		var carry_limit = _get_max_carryable(mat_id, needed)
		if carry_limit <= 0:
			continue
		
		# 检查路径是否可达
		var target_grid = Vector2i(
			floori(target_wp.x / game.world.tile_size),
			floori(target_wp.y / game.world.tile_size)
		)
		if cur_grid != target_grid:
			var test_path = game.world.find_path(cur_grid, target_grid, 100)
			if test_path.is_empty():
				continue
		
		# 选中此来源
		if cand.type == "storage":
			current_task["fetch_storage_pos"] = cand.bld_pos
			current_task["fetch_item_id"] = mat_id
			current_task["fetch_amount"] = carry_limit
			current_task["construct_phase"] = "fetch"
			target_world_pos = target_wp
			set_state(SettlerState.MOVING)
			return true
		else:
			current_task["fetch_storage_pos"] = cand.bld_pos
			current_task["fetch_item_id"] = mat_id
			current_task["fetch_amount"] = carry_limit
			current_task["construct_phase"] = "fetch"
			current_task["fetch_source_type"] = "ground"
			target_world_pos = target_wp
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
	
	# 根据剩余负重计算实际能取多少
	var max_carry = _get_max_carryable(item_id, amount)
	if max_carry <= 0:
		# 背包已满，任务失败
		complete_task()
		return
	
	if source_type == "ground":
		# 从地面捡取
		var source_pos: Vector2i = current_task.get("source_bld_pos", Vector2i.ZERO)
		if game.world:
			taken = game.world.pickup_from_ground(source_pos, item_id, max_carry)
			if taken > 0:
				inventory.add_item(item_id, taken)
	elif source_type == "storage":
		# 从存储建筑取
		var source_pos: Vector2i = current_task.get("source_bld_pos", Vector2i.ZERO)
		var source_bld = game.building_system.get_building_at(source_pos)
		if source_bld != null and source_bld.inventory != null:
			var available = source_bld.inventory.get_item_count(item_id)
			var to_take = mini(max_carry, mini(amount, available))
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
				# 产出物品放入定居者背包
				for out_id in recipe.outputs:
					var out_amt = recipe.outputs[out_id]
					inventory.add_item(out_id, out_amt)
				var out_desc = ""
				for out_id in recipe.outputs:
					var item_data = ItemDefinitions.get_item(out_id)
					var item_name = item_data.name if item_data else out_id
					if out_desc != "": out_desc += ", "
					out_desc += "%s×%d" % [item_name, recipe.outputs[out_id]]
				LogUtil.info(self, "制作完成: %s, 产出 %s" % [recipe.name, out_desc])
				
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
	for item_id in inventory.items:
		var amt = inventory.items[item_id]
		var data = ItemDefinitions.get_item(item_id)
		if data:
			total += data.weight * amt
	return total

func is_overweight() -> bool:
	"""是否超过负重上限"""
	return get_inventory_weight() > carry_capacity

func _get_max_carryable(item_id: String, desired_amount: int) -> int:
	"""计算在不超过负重上限的前提下，最多还能携带多少个指定物品"""
	var current_weight = get_inventory_weight()
	var remaining_capacity = carry_capacity - current_weight
	if remaining_capacity <= 0:
		return 0
	# 查物品重量
	var data = ItemDefinitions.get_item(item_id)
	if data == null or data.weight <= 0:
		return desired_amount
	var max_by_weight = int(floor(remaining_capacity / data.weight))
	return mini(desired_amount, max_by_weight)

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
		
		# 把背包物品转移到置物架（清空背包）
		for item_id in inventory.items.duplicate():
			var amt = inventory.items[item_id]
			if amt <= 0:
				continue
			var remaining = bld.inventory.add_item(item_id, amt)
			if remaining < amt:
				inventory.remove_item(item_id, amt - remaining)
		
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
	
	# 清空背包——把背包中所有物品转移到置物架
	for item_id in inventory.items.duplicate():
		var amt = inventory.items[item_id]
		if amt <= 0:
			continue
		var remaining = bld.inventory.add_item(item_id, amt)
		if remaining < amt:
			inventory.remove_item(item_id, amt - remaining)

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
		floori(position.x / game.world.tile_size),
		floori(position.y / game.world.tile_size)
	)
	for item_id in inventory.items:
		var amt = inventory.items[item_id]
		if amt > 0:
			game.world.drop_item_on_ground(grid_pos, item_id, amt)
	inventory.clear()

func _find_adjacent_walkable(resource_grid: Vector2i, world) -> Vector2i:
	"""寻找资源格子旁边最近的可行走网格（用于采集时站位）"""
	var dirs = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	for d in dirs:
		var check = resource_grid + d
		if world.is_walkable(check):
			return check
	return Vector2i(-1, -1)  # 无可用站位

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

func _move_away_from_water(game_node) -> bool:
	"""当站在水面上时，尝试向最近的可行走方向移动"""
	var tile_ts = game_node.world.tile_size
	var center_grid = Vector2i(
		floori(position.x / tile_ts),
		floori(position.y / tile_ts)
	)
	# 搜索周围6格范围内第一个可行走的格子
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1),
		Vector2i(-1, 1), Vector2i(1, 1),
	]
	for dir in directions:
		var check_pos = center_grid + dir
		if game_node.world.is_walkable(check_pos):
			var target_pixel = Vector2(
				check_pos.x * tile_ts + tile_ts / 2.0,
				check_pos.y * tile_ts + tile_ts / 2.0
			)
			target_world_pos = target_pixel
			_path.clear()
			_path_target_grid = Vector2i(-1, -1)
			set_state(SettlerState.MOVING, true)
			return true
	return false

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
	# 如果已经在睡眠位置，直接开始睡觉，避免 MOVING→complete_task 死循环
	if position.distance_squared_to(world_pos) < 4.0:
		_tick_go_sleep()
		return
	set_state(SettlerState.MOVING)
	LogUtil.info(self, "开始前往睡眠位置 %s" % bld_pos)

func _tick_go_sleep():
	"""移动到睡眠位置后开始睡觉"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		complete_task()
		return
	var bld_pos: Vector2i = current_task.get("target_bld_pos", Vector2i.ZERO)
	if bld_pos != Vector2i.ZERO:
		var bld = game.building_system.get_building_at(bld_pos)
		if bld == null:
			# 建筑不存在（可能被拆了），放弃睡眠任务，防止 IDLE→MOVING 死循环
			complete_task()
			return
	# 到达床位后开始睡觉（无建筑时也能原地休息）
	set_state(SettlerState.SLEEPING)
	LogUtil.info(self, "开始睡觉")

func _tick_sleep(delta):
	"""睡眠中恢复精力"""
	var gm = get_node("/root/GameManager")
	var delta_hours = 1.0
	if gm:
		delta_hours = gm.time_speed * delta * (24.0 / gm.day_length)
	
	# 快速恢复精力
	var sleep_restore = _settler_setting("sleep_restore_per_hour", 50.0)
	modify_need("rest", delta_hours * sleep_restore)
	
	# 最小睡眠时间（防止频繁打断），最大睡眠时间（防止一直睡不干活）
	var now = Time.get_ticks_msec() / 1000.0
	var min_sleep_time = _settler_setting("sleep_min_time", 3.0)
	var max_sleep_time = _settler_setting("sleep_max_time", 8.0)
	var elapsed = now - _last_state_change_time
	
	# 最短睡够 min_sleep_time 秒后才检查是否醒来
	if elapsed < min_sleep_time:
		return
	
	# 睡够 max_sleep_time 秒后强制醒来检查是否有工作
	if elapsed >= max_sleep_time:
		LogUtil.info(self, "睡眠结束：睡够了(%.1f秒)" % elapsed)
		complete_task()
		return
	
	# 精力已满（≥95）则醒来
	if needs["rest"] >= 95.0:
		LogUtil.info(self, "睡眠结束：精力已满(%.1f)" % needs["rest"])
		complete_task()
		return
	
	# 白天则醒来工作
	if gm:
		var hour = int(gm.game_time)
		if hour >= 6 and hour < 18:
			LogUtil.info(self, "睡眠结束：天亮了(游戏时间 %.1f)" % gm.game_time)
			complete_task()

func find_nearest_residential() -> Dictionary:
	"""查找最近的居住建筑（优先使用自己的床，其次帐篷/房屋），返回{pos, world_pos}"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.building_system == null:
		return {}
	
	# 1. 优先使用自己分配到的床
	if assigned_bed_pos.x >= 0:
		var bed_bld = game.building_system.get_building_at(assigned_bed_pos)
		if bed_bld != null and bed_bld.is_completed and bed_bld.building_id == "wooden_bed":
			return {"pos": bed_bld.grid_pos, "world_pos": _bld_world_center(bed_bld)}
	
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

# -------- 狩猎系统 --------
func _tick_hunting(_delta):
	"""狩猎状态：追猎被标记的野猪并射箭"""
	if current_task == null:
		set_state(SettlerState.IDLE, true)
		return
	
	var boar_inst_id = current_task.get("boar_instance_id", 0)
	if boar_inst_id == 0:
		complete_task()
		return
	
	# 通过实例ID查找野猪
	var boar = instance_from_id(boar_inst_id) if boar_inst_id else null
	if boar == null or not is_instance_valid(boar) or boar.state == boar.BoarState.DEAD:
		# 野猪已死亡，清理标记并完成任务
		var game = get_node_or_null("/root/Game")
		if game:
			game.designated_boars.erase(boar_inst_id)
		complete_task()
		return
	
	# 检查是否有弓箭
	if not has_ranged_weapon():
		# 没有弓箭了，放弃狩猎
		complete_task()
		return
	
	# 检查距离——在射程内则射箭
	var dist = position.distance_to(boar.position)
	if dist <= ARROW_RANGE:
		# 面向野猪
		var dir = boar.position - position
		if dir.length_squared() > 0:
			facing_direction = dir.normalized()
		# 射箭
		shoot_at(boar)
	else:
		# 距离太远：如果野猪在 1.5 格外才追，避免微移循环
		var min_chase_dist = ARROW_RANGE * 1.5
		if dist > min_chase_dist:
			move_to(boar.position)
			current_task["target_world_pos"] = boar.position
		# 若在 1~1.5 倍射程之间，原地等待野猪靠近或下一帧继续判断

# 姓氏池（100个）
const SURNAMES = [
	"李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "马", "胡", "朱", "郭", "何", "罗", "高", "林",
	"梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
	"程", "曹", "袁", "邓", "许", "傅", "沈", "曾", "彭", "吕",
	"苏", "卢", "蒋", "蔡", "贾", "丁", "魏", "薛", "叶", "阎",
	"余", "潘", "杜", "戴", "夏", "钟", "汪", "田", "任", "姜",
	"范", "方", "石", "姚", "谭", "廖", "邹", "熊", "金", "陆",
	"郝", "孔", "白", "崔", "康", "毛", "邱", "秦", "江", "史",
	"顾", "侯", "邵", "孟", "龙", "万", "段", "雷", "钱", "汤",
	"尹", "黎", "易", "常", "武", "乔", "贺", "赖", "龚", "文"
]

# 男性名字池（100个）
const MALE_NAMES = [
	"伟", "强", "磊", "军", "勇", "明", "杰", "涛", "斌", "俊",
	"浩", "鹏", "志", "峰", "超", "波", "辉", "刚", "健", "龙",
	"毅", "飞", "宇", "文", "博", "华", "平", "民", "国", "建",
	"旭", "阳", "海", "鑫", "铭", "辰", "睿", "晨", "曦", "昊天",
	"浩宇", "志远", "鹏飞", "天宇", "翰林", "泽宇", "思远", "俊杰",
	"浩然", "天佑", "文博", "明远", "子轩", "雨泽", "思哲", "宇轩",
	"景行", "致远", "鸿涛", "宇恒", "嘉懿", "宏远", "云帆", "安澜",
	"修远", "瑾瑜", "璟煜", "承泽", "瑞霖", "明熙", "晨曦", "皓轩",
	"子涵", "一鸣", "奕辰", "弘毅", "启航", "嘉瑞", "沛泽", "锦程",
	"骏驰", "铭泽", "景桓", "辰逸", "柏豪", "俊楠", "昊天", "泽楷"
]

# 女性名字池（100个）
const FEMALE_NAMES = [
	"芳", "娟", "敏", "静", "丽", "娜", "霞", "燕", "艳", "琳",
	"雪", "梅", "琴", "兰", "红", "玲", "英", "萍", "华", "青",
	"文", "秀", "美", "惠", "月", "洁", "云", "莲", "珍", "蓉",
	"蕊", "婷", "慧", "萱", "妍", "琪", "瑶", "怡", "梦", "颖",
	"悦", "蕾", "薇", "妮", "璇", "艺", "佳", "茜", "芷", "雯",
	"馨", "梓涵", "雨涵", "语嫣", "婉婷", "若曦", "梦琪", "慕晴",
	"诗涵", "雅静", "芷若", "嫣然", "心怡", "舒雅", "思颖", "晓萱",
	"紫萱", "雅琴", "冰洁", "洛晴", "映雪", "听荷", "含玉", "书瑶",
	"安雅", "清欢", "以寒", "雨薇", "诗韵", "若兰", "芷荷", "筠心",
	"沛珊", "雪怡", "乐菱", "念薇", "疏桐", "宁馨", "语琴", "云梦",
	"绮彤", "灵芸", "沐曦", "瑾萱", "茹雪", "芷柔", "黛眉", "碧菡"
]

# 随机生成一个不重复的名字
static func generate_unique_name(existing_names: Array) -> String:
	var is_male = randi() % 2 == 0
	var surname = SURNAMES[randi() % SURNAMES.size()]
	var given_name
	if is_male:
		given_name = MALE_NAMES[randi() % MALE_NAMES.size()]
	else:
		given_name = FEMALE_NAMES[randi() % FEMALE_NAMES.size()]
	var full_name = surname + given_name
	
	# 去重：最多尝试50次
	var attempts = 0
	while full_name in existing_names and attempts < 50:
		surname = SURNAMES[randi() % SURNAMES.size()]
		if is_male:
			given_name = MALE_NAMES[randi() % MALE_NAMES.size()]
		else:
			given_name = FEMALE_NAMES[randi() % FEMALE_NAMES.size()]
		full_name = surname + given_name
		attempts += 1
	
	return full_name

func _randomize_name():
	var is_male = randi() % 2 == 0
	if is_male:
		gender = Gender.MALE
	else:
		gender = Gender.FEMALE
	settler_name = generate_unique_name([])

func randomize_name_with_pool(existing_names: Array):
	"""使用已有的名字池生成不重复的名字"""
	var is_male = randi() % 2 == 0
	if is_male:
		gender = Gender.MALE
	else:
		gender = Gender.FEMALE
	settler_name = generate_unique_name(existing_names)

func _randomize_age():
	age = 10.0 + randi() % 51  # 10~60 岁

func _apply_config_settings():
	"""从 GameConfig 加载可配置参数"""
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
	NEED_DECAY["rest"] = _settler_setting("rest_decay_per_hour", 5.0)
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
	var phase_str = current_task.get("construct_phase","?") if current_task else "null"
	if is_selected:
		print("[状态] %s %s -> %s  phase=%s%s" % [settler_name, old_state_str, new_state_str, phase_str, " (强制)" if force else ""])
	state = new_state
	_last_state_change_time = now
	
	# 睡觉时角色横过来，其他状态扶正
	if settler_sprite:
		if state == SettlerState.SLEEPING:
			settler_sprite.rotation = deg_to_rad(-90.0)
		else:
			settler_sprite.rotation = 0.0
	
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
		skills[skill_id] = minf(10.0, skills[skill_id] + amount * 0.1)

# -------- 任务系统 --------
func assign_task(task_data: Dictionary) -> bool:
	"""分配任务，返回是否可以接受"""
	var target_pixel = task_data.get("target_world_pos", Vector2.ZERO)
	
	if target_pixel != Vector2.ZERO:
		var game = get_node_or_null("/root/Game")
		if game and game.world:
			var ts = game.world.tile_size
			# 采集/建造任务：站在目标旁边的可行走格子上
			if task_data.get("type") in ["HARVEST", "CONSTRUCT"]:
				var target_grid = task_data.get("target_pos", Vector2i.ZERO)
				var stand_grid = _find_adjacent_walkable(target_grid, game.world)
				if stand_grid != Vector2i(-1, -1):
					target_pixel = Vector2(
						stand_grid.x * ts + ts / 2.0,
						stand_grid.y * ts + ts / 2.0
					)
				elif not game.world.is_walkable(target_grid):
					LogUtil.info(self, "目标格 %s 不可行走，无法执行任务" % target_grid)
					return false  # 目标不可达，拒绝接受任务
			else:
				var target_grid = Vector2i(
					floori(target_pixel.x / ts),
					floori(target_pixel.y / ts)
				)
				if not game.world.is_walkable(target_grid):
					LogUtil.info(self, "目标格 %s 不可行走，无法执行任务" % target_grid)
					return false  # 目标不可达，拒绝接受任务
	
	current_task = task_data
	
	# 设置移动目标（像素坐标）
	if target_pixel != Vector2.ZERO:
		target_world_pos = target_pixel
		set_state(SettlerState.MOVING, true)  # 强制切换，防止冷却导致任务卡住
		if is_selected:
			queue_redraw()
	else:
		# 没有目标位置则直接开始工作
		set_state(SettlerState.WORKING, true)  # 强制切换，防止冷却导致任务卡住
		_last_work_tick_time = Time.get_ticks_msec() / 1000.0
	
	task_assigned.emit(task_data.get("id", ""))
	return true

func complete_task(skip_auto_store: bool = false):
	if current_task:
		task_completed.emit(current_task.get("id", ""))
		# 成功完成任务，减少重试计数
		_construction_retry_count = max(0, _construction_retry_count - 1)
	current_task = null
	target_world_pos = Vector2.ZERO
	_path.clear()
	_path_target_grid = Vector2i(-1, -1)
	set_state(SettlerState.IDLE, true)  # 强制切换，防止冷却导致卡死
	if is_selected:
		queue_redraw()
	
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
			floori(position.x / game.world.tile_size),
			floori(position.y / game.world.tile_size)
		)
		for item_id in inventory.items:
			var amt = inventory.items[item_id]
			if amt > 0:
				game.world.drop_item_on_ground(grid_pos, item_id, amt)
	if game:
		game.settlers.erase(self)
	queue_free()

# -------- 战斗系统（远程弓箭） --------
var _last_arrow_shot_time: float = 0.0
const ARROW_COOLDOWN: float = 2.0  # 射速2秒每发
const ARROW_DAMAGE: float = 5.0
const ARROW_RANGE: float = 3.0 * 32.0  # 3格 = 96像素
const ARROW_MELEE_DAMAGE: float = 2.0
const ARROW_MELEE_COOLDOWN: float = 2.0

func has_bow() -> bool:
	"""检查是否持有弓（被动装备，人人都有）"""
	return true

func has_arrow() -> bool:
	"""检查是否有箭矢（被动装备，人人都有，不消耗）"""
	return true

func shoot_at(target_node: Node2D) -> bool:
	"""向目标发射箭矢，返回是否成功发射"""
	if not has_bow() or not has_arrow():
		return false
	
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_arrow_shot_time < ARROW_COOLDOWN:
		return false
	
	# 检查距离（3格射程）
	var dist = position.distance_to(target_node.position)
	if dist > ARROW_RANGE:
		return false
	
	# 箭不消耗（被动装备）
	_last_arrow_shot_time = now
	
	# 创建箭矢投射物
	var game = get_node_or_null("/root/Game")
	if game:
		var arrow = load("res://scripts/entities/arrow_projectile.gd").new()
		arrow.init(position, target_node, ARROW_DAMAGE)
		arrow.shooter = self
		game.call_deferred("add_child", arrow)
	
	# 射箭时面朝目标
	var dir = target_node.position - position
	if dir.length_squared() > 0:
		facing_direction = dir.normalized()
	
	return true

func has_ranged_weapon() -> bool:
	"""是否有远程武器（弓）"""
	return has_bow() and has_arrow()

# -------- 自动回血 --------
func apply_passive_heal(delta_hours: float):
	"""每小时恢复5点HP"""
	if hp < max_hp:
		heal(5.0 * delta_hours)

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
		"assigned_bed_pos_x": assigned_bed_pos.x,
		"assigned_bed_pos_y": assigned_bed_pos.y,
	}

func from_dict(data: Dictionary):
	settler_id = data.id
	settler_name = data.get("name", "")
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
	assigned_bed_pos = Vector2i(
		data.get("assigned_bed_pos_x", -1),
		data.get("assigned_bed_pos_y", -1)
	)
	# 反序列化后更新角色贴图和缩放
	if settler_sprite:
		settler_sprite.texture = _pick_character_texture()
		var tex_size = settler_sprite.texture.get_size()
		var scale_factor = TILE_SIZE / max(tex_size.x, tex_size.y)
		settler_sprite.scale = Vector2(scale_factor, scale_factor)
