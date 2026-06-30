# 野猪实体 - Wild Boar
# 野生动物：从地图边缘进入，会饥饿觅食，夜晚睡觉，受攻击反击
extends Node2D
class_name Boar

signal died(pos: Vector2i)

# 贴图资源路径
const BOAR_TEXTURE_PATH := "res://assets/art/creatures/boar.svg"

# 属性
var hp: float = 100.0
var max_hp: float = 100.0
var move_speed: float = 40.0  # 像素/秒
var attack_damage: float = 2.0
var attack_cooldown: float = 2.0  # 秒
var _last_attack_time: float = 0.0

# 需求
var hunger: float = 80.0  # 0-100，随时间降低
var energy: float = 80.0  # 0-100，夜晚睡觉恢复

# 状态
enum BoarState {
	IDLE,
	WANDERING,
	MOVING_TO_FOOD,
	EATING,
	SLEEPING,
	COMBAT,
	FLEEING,
	DEAD,
}
var state: BoarState = BoarState.IDLE
# 移动
var target_world_pos: Vector2 = Vector2.ZERO
var _path: Array[Vector2i] = []
var _wait_timer: float = 0.0

# 精灵
var _sprite: Sprite2D
var _base_sprite_scale: float = 1.0

# 选中状态
var is_selected: bool = false
var _status_font: Font = null

# 狩猎标记
var is_designated: bool = false

# 攻击目标
var attack_target: Node2D = null

const TILE_SIZE: float = 32.0

func _init():
	_randomize_stats()

func _ready():
	_setup_sprite()
	# 从边缘进入后随机游走
	state = BoarState.WANDERING
	_pick_wander_target()

func _setup_sprite():
	_sprite = Sprite2D.new()
	var tex = ResourceLoader.load(BOAR_TEXTURE_PATH, "Texture2D")
	if tex:
		_sprite.texture = tex
		var tex_size = tex.get_size()
		var scale_factor = TILE_SIZE / max(tex_size.x, tex_size.y)
		_base_sprite_scale = scale_factor
		_sprite.scale = Vector2(scale_factor, scale_factor)
	_sprite.z_index = 2
	add_child(_sprite)

func _randomize_stats():
	hp = 100.0
	max_hp = 100.0
	hunger = 60.0 + randf_range(0.0, 40.0)
	energy = 60.0 + randf_range(0.0, 40.0)

# -------- 选中状态 --------
func set_selected(selected: bool):
	is_selected = selected
	queue_redraw()

func _draw():
	var half_size = TILE_SIZE * 0.5
	
	# 狩猎标记：头顶红色标记
	if is_designated:
		var mark_size = 4.0
		var top_y = -half_size - 8.0
		# 画一个红色菱形标记
		var points = PackedVector2Array([
			Vector2(0, top_y - mark_size),
			Vector2(mark_size, top_y),
			Vector2(0, top_y + mark_size),
			Vector2(-mark_size, top_y),
		])
		draw_colored_polygon(points, Color(1.0, 0.2, 0.1, 0.9))
		# 画瞄准十字线
		draw_line(Vector2(-mark_size - 2, top_y), Vector2(mark_size + 2, top_y), Color(1.0, 0.2, 0.1, 0.7), 1.0)
		draw_line(Vector2(0, top_y - mark_size - 2), Vector2(0, top_y + mark_size + 2), Color(1.0, 0.2, 0.1, 0.7), 1.0)
	
	if not is_selected:
		return
	
	var rect = Rect2(-half_size, -half_size, TILE_SIZE, TILE_SIZE)
	# 金色半透明填充（与树木资源选中框一致）
	draw_rect(rect, Color(1.0, 0.85, 0.3, 0.15), true)
	# 金色边框
	draw_rect(rect, Color(1.0, 0.8, 0.2, 0.9), false, 2.0)
	
	# 绘制HP条
	if hp < max_hp:
		_draw_hp_bar()

func _draw_hp_bar():
	"""在野猪上方绘制HP条（与角色风格一致）"""
	if _status_font == null:
		_status_font = ThemeDB.fallback_font
		if _status_font == null:
			return
	
	var bar_width = TILE_SIZE * 0.8
	var bar_height = 3.0  # 与角色一致
	var bar_x = -bar_width / 2.0
	var bar_y = -TILE_SIZE / 2.0 - bar_height - 2.0
	
	# 背景
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.15, 0.15, 0.8))
	
	# HP填充
	var hp_ratio = hp / max_hp if max_hp > 0 else 0.0
	var hp_color = Color(0.3, 1.0, 0.3, 0.9)  # 绿色（与角色一致）
	if hp_ratio < 0.3:
		hp_color = Color(1.0, 0.3, 0.3, 0.9)  # 红色
	elif hp_ratio < 0.6:
		hp_color = Color(1.0, 0.8, 0.2, 0.9)  # 黄色
	draw_rect(Rect2(bar_x, bar_y, bar_width * hp_ratio, bar_height), hp_color)

func _process(delta):
	var game = get_node_or_null("/root/Game")
	var gm = get_node("/root/GameManager")
	if not game or not gm or gm.state != 1:
		return
	
	# 已死亡不处理
	if state == BoarState.DEAD:
		return
	
	var delta_hours = gm.time_speed * delta * (24.0 / gm.day_length)
	var is_night = not gm.is_daytime()
	var now = Time.get_ticks_msec() / 1000.0
	
	# 更新需求
	hunger = max(0.0, hunger - 1.5 * delta_hours)
	if state != BoarState.SLEEPING:
		energy = max(0.0, energy - 2.0 * delta_hours)
	
	# ----- AI 决策 -----
	# 每帧根据水平朝向翻转精灵（放在match之前，避免被早期return跳过）
	if _sprite:
		_sprite.scale.x = -_base_sprite_scale if facing_direction.x < 0 else _base_sprite_scale
	
	match state:
		BoarState.IDLE:
			_wait_timer -= delta
			if _wait_timer <= 0:
				if is_night and energy < 50.0:
					_start_sleeping()
				elif hunger < 40.0:
					_search_food()
				else:
					_pick_wander_target()
		
		BoarState.WANDERING:
			if not _move_towards(delta, game):
				return  # 还在移动中
			# 到达目标，进入IDLE一会
			state = BoarState.IDLE
			_wait_timer = randf_range(1.0, 4.0)
		
		BoarState.MOVING_TO_FOOD:
			if not _move_towards(delta, game):
				return  # 还在移动中
			# 到达食物位置
			if hunger < 60.0:
				_eat_food()
			else:
				state = BoarState.IDLE
				_wait_timer = 2.0
		
		BoarState.EATING:
			# 吃东西恢复饥饿度
			hunger = min(100.0, hunger + 20.0 * delta_hours)
			if hunger >= 90.0:
				state = BoarState.IDLE
				_wait_timer = randf_range(1.0, 3.0)
		
		BoarState.SLEEPING:
			energy = min(100.0, energy + 30.0 * delta_hours)
			if energy >= 90.0 or (not is_night and energy > 50.0):
				if _sprite:
					_sprite.rotation = 0.0
				state = BoarState.IDLE
				_wait_timer = randf_range(1.0, 3.0)
		
		BoarState.COMBAT:
			# 攻击冷却
			if attack_target and is_instance_valid(attack_target):
				if now - _last_attack_time >= attack_cooldown:
					if _is_adjacent_to_target():
						_melee_attack()
					else:
						# 追向目标
						_chase_target(delta, game)
			else:
				attack_target = null
				state = BoarState.IDLE
				_wait_timer = 1.0

func _pick_wander_target():
	"""随机选择一个游走目标（不出地图边界）"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return
	var cur_grid = _get_grid()
	var offset_x = randi_range(-5, 5)
	var offset_y = randi_range(-5, 5)
	var target_grid = Vector2i(cur_grid.x + offset_x, cur_grid.y + offset_y)
	
	# 确保目标在世界边界内
	if not game.world.is_in_world_bounds(target_grid):
		target_grid = Vector2i(
			clampi(target_grid.x, 1, game.world.WORLD_CHUNKS_X * game.world.CHUNK_SIZE - 2),
			clampi(target_grid.y, 1, game.world.WORLD_CHUNKS_Y * game.world.CHUNK_SIZE - 2)
		)
	
	if game.world.is_walkable(target_grid):
		target_world_pos = _grid_to_world(target_grid)
		_path = game.world.find_path_generated_only(cur_grid, target_grid, 200)
		state = BoarState.WANDERING

func _search_food():
	"""寻找食物（浆果丛或地面食物）"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return
	var cur_grid = _get_grid()
	# 寻找附近的浆果丛
	var best_pos = Vector2i(-1, -1)
	var best_dist = INF
	
	# 搜索附近区块
	var center_chunk = game.world.global_to_chunk(cur_grid)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var chunk_pos = center_chunk + Vector2i(dx, dy)
			var chunk = game.world.chunks.get(chunk_pos)
			if not chunk or not chunk.is_generated:
				continue
			for local_pos in chunk.resources:
				var dep = chunk.resources[local_pos]
				if dep.type == game.world.ResourceNodeType.BERRY_BUSH and dep.amount > 0:
					var global_pos = chunk_pos * game.world.CHUNK_SIZE + local_pos
					var dist = cur_grid.distance_squared_to(global_pos)
					if dist < best_dist:
						best_dist = dist
						best_pos = global_pos
	
	# 也找地面上的食物
	var food_ids = ["berry", "raw_meat", "cooked_meat"]
	for fid in food_ids:
		var gpos = game.world.find_nearest_ground_item(cur_grid, fid, 8)
		if gpos.x >= 0:
			var dist = cur_grid.distance_squared_to(gpos)
			if dist < best_dist:
				best_dist = dist
				best_pos = gpos
	
	if best_pos.x >= 0:
		target_world_pos = _grid_to_world(best_pos)
		_path = game.world.find_path_generated_only(cur_grid, best_pos, 200)
		state = BoarState.MOVING_TO_FOOD
	else:
		_pick_wander_target()

func _eat_food():
	"""在当前位置吃食物"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		state = BoarState.IDLE
		return
	
	var cur_grid = _get_grid()
	
	# 先吃地面食物
	var food_ids = ["berry", "raw_meat", "cooked_meat"]
	for fid in food_ids:
		var picked = game.world.pickup_from_ground(cur_grid, fid, 1)
		if picked > 0:
			state = BoarState.EATING
			return
	
	# 再吃浆果丛
	var dep = game.world.get_resource_at(cur_grid)
	if dep and dep.type == game.world.ResourceNodeType.BERRY_BUSH and dep.amount > 0:
		game.world.harvest_resource(cur_grid, 1)
		state = BoarState.EATING
		return
	
	# 没找到食物
	state = BoarState.IDLE
	_wait_timer = 2.0

func _start_sleeping():
	state = BoarState.SLEEPING
	if _sprite:
		_sprite.rotation = deg_to_rad(-90.0)

# -------- 战斗系统 --------
func take_damage(amount: float, attacker: Node2D = null):
	hp -= amount
	if hp <= 0:
		_die()
		return
	
	# 受攻击后反击
	if attacker and is_instance_valid(attacker):
		attack_target = attacker
		state = BoarState.COMBAT
		# 如果攻击者在相邻格，立即反击
		if _is_adjacent_to(attacker):
			_melee_attack()
		else:
			_chase_target(0, null)

func _die():
	if state == BoarState.DEAD:
		return
	state = BoarState.DEAD
	
	# 掉落生肉
	var game = get_node_or_null("/root/Game")
	if game and game.world:
		var grid_pos = _get_grid()
		game.world.drop_item_on_ground(grid_pos, "raw_meat", 100)
	
	hp = 0
	died.emit(_get_grid())
	
	# 死亡动画：变红然后消失
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 0.3, 0.3, 0.5), 0.5)
	tween.tween_callback(queue_free)

func _melee_attack():
	"""近战攻击相邻敌人"""
	if not attack_target or not is_instance_valid(attack_target):
		return
	_last_attack_time = Time.get_ticks_msec() / 1000.0
	
	if attack_target.has_method("take_damage"):
		attack_target.take_damage(attack_damage)
	
	# 攻击时面向目标
	var dir = attack_target.position - position
	if dir.length_squared() > 0:
		facing_direction = dir.normalized()

func _is_adjacent_to_target() -> bool:
	if not attack_target or not is_instance_valid(attack_target):
		return false
	return _is_adjacent_to(attack_target)

func _is_adjacent_to(other: Node2D) -> bool:
	var my_grid = _get_grid()
	var other_grid = Vector2i(
		floori(other.position.x / TILE_SIZE),
		floori(other.position.y / TILE_SIZE)
	)
	return abs(my_grid.x - other_grid.x) <= 1 and abs(my_grid.y - other_grid.y) <= 1

func _chase_target(delta, game):
	"""追踪攻击目标"""
	if not attack_target or not is_instance_valid(attack_target):
		return
	if not game or not game.world:
		return
	
	var target_grid = Vector2i(
		floori(attack_target.position.x / TILE_SIZE),
		floori(attack_target.position.y / TILE_SIZE)
	)
	var cur_grid = _get_grid()
	
	# 如果已经在相邻格，停止移动
	if abs(cur_grid.x - target_grid.x) <= 1 and abs(cur_grid.y - target_grid.y) <= 1:
		return
	
	# 确保目标不在世界外
	if game.world.is_in_world_bounds(target_grid):
		target_world_pos = attack_target.position
		_path = game.world.find_path_generated_only(cur_grid, target_grid, 200)
	else:
		# 目标跑到世界外了，放弃追击
		attack_target = null
		state = BoarState.IDLE
		_wait_timer = 1.0
		return
	_move_towards(delta, game)

# -------- 移动系统 --------
func _get_grid() -> Vector2i:
	return Vector2i(
		floori(position.x / TILE_SIZE),
		floori(position.y / TILE_SIZE)
	)

func _grid_to_world(grid: Vector2i) -> Vector2:
	return Vector2(
		grid.x * TILE_SIZE + TILE_SIZE / 2.0,
		grid.y * TILE_SIZE + TILE_SIZE / 2.0
	)

var facing_direction: Vector2 = Vector2.RIGHT

func _move_towards(delta, game) -> bool:
	"""向目标移动，返回是否已到达"""
	if target_world_pos == Vector2.ZERO:
		return true
	
	if not game or not game.world:
		return true
	
	var tile_ts = game.world.tile_size
	var cur_grid = _get_grid()
	var target_grid = Vector2i(
		floori(target_world_pos.x / tile_ts),
		floori(target_world_pos.y / tile_ts)
	)
	
	if _path.is_empty() or target_grid != _path_target_grid_cache:
		_path_target_grid_cache = target_grid
		if _path.size() > 0:
			_path.clear()
		# 仅在目标位于世界边界内时寻路
		if game.world.is_in_world_bounds(target_grid):
			_path = game.world.find_path_generated_only(cur_grid, target_grid, 200)
		else:
			_path = []
	
	# 移动
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
		return false  # 还在移动中
	else:
		if not _path.is_empty():
			_path.remove_at(0)
			return false  # 继续下一个路径点
		else:
			position = target_world_pos
			return true  # 到达

var _path_target_grid_cache: Vector2i = Vector2i(-1, -1)

func spawn_at_edge(game_node) -> bool:
	"""在地图随机边缘生成野猪，返回是否成功"""
	if not game_node or not game_node.world:
		return false
	
	var world = game_node.world
	# 在地图边缘随机选择方向
	var edge = randi() % 4  # 0=上, 1=下, 2=左, 3=右
	var world_chunks_x = world.WORLD_CHUNKS_X
	var world_chunks_y = world.WORLD_CHUNKS_Y
	var world_tiles_x = world_chunks_x * world.CHUNK_SIZE
	var world_tiles_y = world_chunks_y * world.CHUNK_SIZE
	
	var spawn_grid: Vector2i
	match edge:
		0:  # 上边缘
			spawn_grid = Vector2i(randi_range(0, world_tiles_x - 1), 0)
		1:  # 下边缘
			spawn_grid = Vector2i(randi_range(0, world_tiles_x - 1), world_tiles_y - 1)
		2:  # 左边缘
			spawn_grid = Vector2i(0, randi_range(0, world_tiles_y - 1))
		3:  # 右边缘
			spawn_grid = Vector2i(world_tiles_x - 1, randi_range(0, world_tiles_y - 1))
	
	# 确保该位置可行走
	if not world.is_walkable(spawn_grid):
		# 向内部搜索可行走格子
		for radius in range(1, 10):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if abs(dx) != radius and abs(dy) != radius:
						continue
					var check = spawn_grid + Vector2i(dx, dy)
					if world.is_in_world_bounds(check) and world.is_walkable(check):
						spawn_grid = check
						radius = 10
						break
			if spawn_grid != Vector2i(-1, -1):
				break
	
	if not world.is_walkable(spawn_grid):
		return false
	
	position = _grid_to_world(spawn_grid)
	# 向世界中心方向稍微偏移，让野猪向内走
	var center = world.get_world_center_pixel()
	var dir_to_center = (center - position).normalized()
	target_world_pos = position + dir_to_center * 200.0
	state = BoarState.WANDERING
	
	return true
