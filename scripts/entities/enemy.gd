# 敌对实体 - Enemy
# 敌袭事件中生成，主动寻找并攻击玩家的建筑
# 默认远程射箭攻击，优先攻击防御建筑
extends Node2D
class_name Enemy

signal died(pos: Vector2i)
signal building_attacked(building, damage: float)

# 状态中文名称
const STATE_NAMES := {
	EnemyState.SPAWNING: "出现中",
	EnemyState.MOVING: "前进中",
	EnemyState.ATTACKING: "攻击中",
	EnemyState.APPROACHING: "接近中",
	EnemyState.DEAD: "已死亡",
}

static func get_state_display(state_val: int) -> String:
	return STATE_NAMES.get(state_val, "未知")

# 弓箭攻击属性（默认远程射箭）
var arrow_speed: float = 200.0       # 箭矢飞行速度
var arrow_range: float = 4.0 * 32.0  # 格数→像素

# 属性
var hp: float = 80.0
var max_hp: float = 80.0
var move_speed: float = 30.0  # 像素/秒
var attack_damage: float = 5.0
var attack_cooldown: float = 2.5  # 秒
var _last_attack_time: float = 0.0

# 弓箭投射物伤害
var _arrow_projectile_damage: float = 5.0

# 读取 GameConfig 的快捷函数
static func _enemy_config(key: String, default_value):
	var gc = Engine.get_main_loop().root.get_node_or_null("/root/GameConfig")
	if gc and key in gc:
		return gc.get(key)
	return default_value

# 状态
enum EnemyState {
	SPAWNING,
	MOVING,
	APPROACHING,  # 正在靠近建筑到射程内
	ATTACKING,    # 在射程内射箭攻击
	DEAD,
}
var state: EnemyState = EnemyState.SPAWNING

# 移动
var target_world_pos: Vector2 = Vector2.ZERO
var _path: Array[Vector2i] = []
var _path_target_grid_cache: Vector2i = Vector2i(-1, -1)

# 当前攻击目标建筑
var target_building = null

# 精灵
var _sprite: Sprite2D
var _base_sprite_scale: float = 1.0

# 选中状态
var is_selected: bool = false
# 攻击标记状态（被玩家标记为攻击目标）
var is_designated: bool = false
var _status_font: Font = null

const TILE_SIZE: float = 32.0
var facing_direction: Vector2 = Vector2.DOWN

func _init():
	_randomize_stats()
	_apply_config()

func _ready():
	_setup_sprite()
	# 生成后立即寻找建筑目标
	state = EnemyState.MOVING
	_find_best_building_target()

func _setup_sprite():
	_sprite = Sprite2D.new()
	# 使用成年男性角色贴图，叠加红色色调
	var tex = ResourceLoader.load("res://assets/art/characters/player_young_man.png", "Texture2D")
	if tex:
		_sprite.texture = tex
		var tex_size = tex.get_size()
		var scale_factor = TILE_SIZE / max(tex_size.x, tex_size.y)
		_base_sprite_scale = scale_factor
		_sprite.scale = Vector2(scale_factor, scale_factor)
	# 红色色调（敌对标识）
	_sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)
	_sprite.z_index = 3
	add_child(_sprite)

func _randomize_stats():
	hp = _enemy_config("enemy_base_hp", 80.0) + randf_range(0.0, _enemy_config("enemy_hp_variance", 40.0))
	max_hp = hp
	attack_damage = _enemy_config("enemy_attack_damage", 5.0)
	attack_cooldown = _enemy_config("enemy_attack_cooldown", 2.5)
	move_speed = _enemy_config("enemy_base_move_speed", 30.0) + randf_range(0.0, _enemy_config("enemy_move_speed_variance", 15.0))
	_arrow_projectile_damage = _enemy_config("enemy_arrow_damage", 5.0)

func _apply_config():
	"""应用来自GameConfig的配置（非随机部分）"""
	arrow_speed = _enemy_config("enemy_arrow_speed", 200.0)
	var range_tiles = _enemy_config("enemy_arrow_range", 4.0)
	arrow_range = range_tiles * 32.0

# -------- 选中状态 --------
func set_selected(selected: bool):
	is_selected = selected
	queue_redraw()

func _draw():
	var half_size = TILE_SIZE * 0.5
	
	# 被标记为攻击目标时，始终显示标记指示
	if is_designated:
		var mark_rect = Rect2(-half_size, -half_size, TILE_SIZE, TILE_SIZE)
		# 深红色标记边框（比选中更粗更亮）
		draw_rect(mark_rect, Color(1.0, 0.1, 0.1, 0.12), true)
		draw_rect(mark_rect, Color(1.0, 0.1, 0.1, 0.8), false, 3.0)
		# 右上角画一个攻击标记（X形）
		var cross_size = 6.0
		var cx = half_size - 4.0
		var cy = -half_size + 4.0
		draw_line(Vector2(cx - cross_size, cy - cross_size), Vector2(cx + cross_size, cy + cross_size), Color(1.0, 0.0, 0.0, 0.9), 2.0)
		draw_line(Vector2(cx + cross_size, cy - cross_size), Vector2(cx - cross_size, cy + cross_size), Color(1.0, 0.0, 0.0, 0.9), 2.0)
	
	if not is_selected:
		return
	
	var rect = Rect2(-half_size, -half_size, TILE_SIZE, TILE_SIZE)
	# 红色半透明填充（与普通角色蓝色区分）
	draw_rect(rect, Color(1.0, 0.3, 0.3, 0.15), true)
	# 红色边框
	draw_rect(rect, Color(1.0, 0.2, 0.2, 0.9), false, 2.0)
	
	# 绘制HP条
	if hp < max_hp:
		_draw_hp_bar()
	
	# 选中时在脚下绘制状态文字
	_draw_status_below()

func _draw_hp_bar():
	if _status_font == null:
		_status_font = ThemeDB.fallback_font
		if _status_font == null:
			return
	
	var bar_width = TILE_SIZE * 0.8
	var bar_height = 3.0
	var bar_x = -bar_width / 2.0
	var bar_y = -TILE_SIZE / 2.0 - bar_height - 2.0
	
	# 背景
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.15, 0.15, 0.8))
	
	# HP填充（红色表示敌人）
	var hp_ratio = hp / max_hp if max_hp > 0 else 0.0
	var hp_color = Color(1.0, 0.3, 0.3, 0.9)  # 红色（敌人）
	draw_rect(Rect2(bar_x, bar_y, bar_width * hp_ratio, bar_height), hp_color)

func _draw_status_below():
	if _status_font == null:
		_status_font = ThemeDB.fallback_font
		if _status_font == null:
			return
	
	var font_size = 11
	var state_text = get_state_display(state)
	var text_y = TILE_SIZE / 2.0 + 2.0
	var text_size = _status_font.get_string_size(state_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2.0, text_y + text_size.y)
	
	# 文字阴影
	_status_font.draw_string(get_canvas_item(), text_pos + Vector2(1, 1), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	# 文字本体（敌人用红色文字）
	_status_font.draw_string(get_canvas_item(), text_pos, state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.3, 0.3, 0.95))

func _process(delta):
	var game = get_node_or_null("/root/Game")
	var gm = get_node("/root/GameManager")
	if not game or not gm or gm.state != 1:
		return
	
	# 已死亡不处理
	if state == EnemyState.DEAD:
		return
	
	# 每帧根据水平朝向翻转精灵
	if _sprite:
		_sprite.scale.x = -_base_sprite_scale if facing_direction.x < 0 else _base_sprite_scale
	
	match state:
		EnemyState.MOVING:
			# 检查目标建筑是否仍然有效（BuildingInstance 不是 Node，需通过系统查询）
			if target_building == null or not _is_building_valid(target_building):
				_find_best_building_target()
				if target_building == null:
					_pick_wander_target()
				return
			
			# 先寻路向目标建筑移动（不过判断条件改成：进入射程即可攻击）
			if not _move_towards(delta, game):
				return
			
			# 到达路径终点后检查距离
			var dist_to_building = _distance_to_building(target_building)
			if dist_to_building <= arrow_range:
				state = EnemyState.ATTACKING
			else:
				# 重新寻路
				_find_best_building_target()
		
		EnemyState.APPROACHING:
			# 接近阶段：向目标移动直到进入射程
			if target_building == null or not _is_building_valid(target_building):
				target_building = null
				_find_best_building_target()
				if target_building == null:
					_pick_wander_target()
				return
			
			var dist = _distance_to_building(target_building)
			if dist <= arrow_range:
				# 进入射程，停止移动开始攻击
				state = EnemyState.ATTACKING
				# 面向建筑
				var bld_center = _get_building_center(target_building)
				facing_direction = (bld_center - position).normalized()
				return
			
			if not _move_towards(delta, game):
				return
			# 到达路径点后重新评估
			dist = _distance_to_building(target_building)
			if dist <= arrow_range:
				state = EnemyState.ATTACKING
		
		EnemyState.ATTACKING:
			var now = Time.get_ticks_msec() / 1000.0
			
			# 检查目标是否依然有效
			if target_building == null or not _is_building_valid(target_building):
				target_building = null
				_find_best_building_target()
				if target_building == null:
					_pick_wander_target()
				return
			
			# 检查是否仍在射程内
			var dist = _distance_to_building(target_building)
			if dist > arrow_range * 1.2:
				# 超出射程，重新靠近
				state = EnemyState.APPROACHING
				_find_best_building_target()
				return
			
			# 射箭攻击冷却（跟随游戏变速）
			var effective_cd = attack_cooldown / (Engine.time_scale if Engine.time_scale > 0 else 1.0)
			if now - _last_attack_time >= effective_cd:
				_shoot_arrow_at_building()

func _find_best_building_target():
	"""寻找最佳建筑目标——优先攻击防御建筑，其次最近建筑"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.building_system:
		return
	
	var all_buildings = game.building_system.get_all_buildings()
	var best = null
	var best_score = INF  # 分数越低优先级越高
	var ItemDefs = preload("res://resources/item_definitions.gd")
	
	for bld in all_buildings:
		if not bld.is_completed:
			continue
		
		var bld_center = _get_building_center(bld)
		var dist = position.distance_squared_to(bld_center)
		
		# 基础分数 = 距离
		var score = dist
		
		# 防御建筑（DEFENSE）优先级大幅提高（分数减半）
		var data = bld.get_data()
		if data and data.category == ItemDefs.BuildingCategory.DEFENSE:
			score *= 0.3  # 防御建筑距离权重降至30%，优先攻击
		
		if score < best_score:
			best_score = score
			best = bld
	
	target_building = best
	
	# 设置移动目标到建筑射程位置（而非紧邻）
	if best != null:
		var my_grid = _get_grid()
		var target_grid = _find_range_attack_position(best.grid_pos, best.get_size(), my_grid)
		
		var occupied = _get_occupied()
		if target_grid.x >= 0:
			target_world_pos = _grid_to_world(target_grid)
			_path = game.world.find_path_generated_only(my_grid, target_grid, 500, occupied)
			state = EnemyState.APPROACHING
		else:
			# 找不到合适的远程位置，直接靠近建筑
			var near_grid = _find_adjacent_walkable_target(best.grid_pos, best.get_size(), my_grid)
			if near_grid.x >= 0:
				target_world_pos = _grid_to_world(near_grid)
				_path = game.world.find_path_generated_only(my_grid, near_grid, 500, occupied)

func _find_range_attack_position(bld_grid: Vector2i, bld_size: Vector2i, from_grid: Vector2i) -> Vector2i:
	"""寻找可进入射程（arrow_range）攻击建筑的最佳位置（不一定要紧邻）"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return Vector2i(-1, -1)
	
	var tile_size = game.world.tile_size
	var bld_center_pixel = Vector2(
		(bld_grid.x + bld_size.x / 2.0) * tile_size,
		(bld_grid.y + bld_size.y / 2.0) * tile_size
	)
	
	var best_target = Vector2i(-1, -1)
	var best_dist = INF
	
	# 在射程范围内搜索可行走格子（从近到远）
	var range_tiles = ceil(arrow_range / tile_size)
	for radius in range(1, range_tiles + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var check = Vector2i(bld_grid.x + dx, bld_grid.y + dy)
				if not game.world.is_in_world_bounds(check):
					continue
				if not game.world.is_walkable(check):
					continue
				# 跳过建筑内部格子
				if dx >= 0 and dx < bld_size.x and dy >= 0 and dy < bld_size.y:
					continue
				
				# 检查该格子中心到建筑中心的距离是否在射程内
				var check_center = Vector2(
					check.x * tile_size + tile_size / 2.0,
					check.y * tile_size + tile_size / 2.0
				)
				var dist_to_bld = check_center.distance_to(bld_center_pixel)
				if dist_to_bld > arrow_range:
					continue
				
				var dist_from_me = from_grid.distance_squared_to(check)
				if dist_from_me < best_dist:
					best_dist = dist_from_me
					best_target = check
		
		if best_target.x >= 0:
			break
	
	return best_target

func _find_adjacent_walkable_target(bld_grid: Vector2i, bld_size: Vector2i, from_grid: Vector2i) -> Vector2i:
	"""寻找建筑旁边最近的可行走格子"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return Vector2i(-1, -1)
	
	# 建筑占据的格子范围
	var min_x = bld_grid.x
	var max_x = bld_grid.x + bld_size.x - 1
	var min_y = bld_grid.y
	var max_y = bld_grid.y + bld_size.y - 1
	
	var best_target = Vector2i(-1, -1)
	var best_dist = INF
	
	# 搜索建筑周围的格子
	for dx in range(-1, bld_size.x + 1):
		for dy in range(-1, bld_size.y + 1):
			var check = Vector2i(bld_grid.x + dx, bld_grid.y + dy)
			
			# 跳过建筑内部格子
			if dx >= 0 and dx < bld_size.x and dy >= 0 and dy < bld_size.y:
				continue
			
			if not game.world.is_walkable(check):
				continue
			
			var dist = from_grid.distance_squared_to(check)
			if dist < best_dist:
				best_dist = dist
				best_target = check
	
	# 如果找不到紧邻的格子，扩大搜索范围
	if best_target.x < 0:
		for radius in range(2, 6):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if abs(dx) != radius and abs(dy) != radius:
						continue
					var check = Vector2i(bld_grid.x + dx, bld_grid.y + dy)
					if not game.world.is_in_world_bounds(check):
						continue
					if not game.world.is_walkable(check):
						continue
					var dist = from_grid.distance_squared_to(check)
					if dist < best_dist:
						best_dist = dist
						best_target = check
			if best_target.x >= 0:
				break
	
	return best_target

func _is_building_valid(bld) -> bool:
	"""检查 BuildingInstance 是否仍然存在于建筑系统中（BuildingInstance 不是 Node，不能用 is_instance_valid）"""
	if bld == null:
		return false
	if not bld.is_completed:
		return false
	var game = get_node_or_null("/root/Game")
	if not game or not game.building_system:
		return false
	return game.building_system.get_building_at(bld.grid_pos) != null

func _get_building_center(bld) -> Vector2:
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return position
	var tile_size = game.world.tile_size
	var bld_size = bld.get_size()
	return Vector2(
		(bld.grid_pos.x + bld_size.x / 2.0) * tile_size,
		(bld.grid_pos.y + bld_size.y / 2.0) * tile_size
	)

func _distance_to_building(bld) -> float:
	"""计算到建筑中心的距离（像素）"""
	var center = _get_building_center(bld)
	return position.distance_to(center)

func _is_adjacent_to_building(bld) -> bool:
	"""检查是否在建筑旁边（相邻格）"""
	var my_grid = _get_grid()
	var bld_grid = bld.grid_pos
	var bld_size = bld.get_size()
	
	for dx in range(-1, bld_size.x + 1):
		for dy in range(-1, bld_size.y + 1):
			if dx >= 0 and dx < bld_size.x and dy >= 0 and dy < bld_size.y:
				continue
			var check = Vector2i(bld_grid.x + dx, bld_grid.y + dy)
			if check == my_grid:
				return true
	return false

func _shoot_arrow_at_building():
	"""远程射箭攻击目标建筑"""
	if target_building == null or not _is_building_valid(target_building):
		return
	
	_last_attack_time = Time.get_ticks_msec() / 1000.0
	
	var game = get_node_or_null("/root/Game")
	if not game:
		return
	
	print("[enemy] shooting arrow at ", target_building.building_id, " pos=", target_building.grid_pos, " damage=", _arrow_projectile_damage)
	
	var bld_center = _get_building_center(target_building)
	var actual_damage = _arrow_projectile_damage
	var attacked_building = target_building
	
	# 创建一个轻量箭矢视觉（不依赖 ArrowProjectile，避免方法覆盖问题）
	_launch_arrow_visual(bld_center, attacked_building, actual_damage, game)
	
	# 射箭时面向建筑
	var dir = bld_center - position
	if dir.length_squared() > 0:
		facing_direction = dir.normalized()

func _launch_arrow_visual(target_pos: Vector2, attacked_building, damage: float, game: Node2D):
	"""发射一个简单的箭矢视觉飞行物"""
	var arrow = Sprite2D.new()
	arrow.texture = ResourceLoader.load("res://assets/art/creatures/arrow.svg", "Texture2D")
	arrow.position = position
	arrow.z_index = 5
	game.add_child(arrow)
	
	# 设置箭头朝向目标方向
	arrow.rotation = position.angle_to_point(target_pos)
	
	# 飞行 Tween
	var fly_time = position.distance_to(target_pos) / arrow_speed
	var tween = create_tween()
	tween.tween_property(arrow, "position", target_pos, fly_time).set_ease(Tween.EASE_IN)
	
	# 命中后处理
	tween.tween_callback(func():
		# 对建筑造成伤害（BuildingInstance 不是 Node，不能用 is_instance_valid）
		if attacked_building != null and game and game.building_system:
			# 检查建筑是否仍存在于系统中（未被其他敌人先摧毁）
			var still_exists = game.building_system.get_building_at(attacked_building.grid_pos) != null
			if still_exists:
				var killed = game.building_system.damage_building(attacked_building.grid_pos, damage)
				if killed:
					target_building = null
					call_deferred("_find_best_building_target")
					if target_building == null:
						call_deferred("_pick_wander_target")
			building_attacked.emit(attacked_building, damage)
		
		# 击中特效
		var spark = Sprite2D.new()
		if arrow.texture:
			spark.texture = arrow.texture
		spark.position = arrow.position
		spark.scale = Vector2(0.5, 0.5)
		spark.modulate = Color(1, 0.8, 0.2, 0.8)
		spark.z_index = 5
		game.add_child(spark)
		var spark_tween = create_tween()
		spark_tween.tween_property(spark, "modulate", Color(1, 1, 1, 0), 0.2)
		spark_tween.tween_callback(spark.queue_free)
		
		arrow.queue_free()
	)

func _pick_wander_target():
	"""无目标时随机游走"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.world:
		return
	var cur_grid = _get_grid()
	var offset_x = randi_range(-3, 3)
	var offset_y = randi_range(-3, 3)
	var target_grid = Vector2i(cur_grid.x + offset_x, cur_grid.y + offset_y)
	
	if not game.world.is_in_world_bounds(target_grid):
		target_grid = Vector2i(
			clampi(target_grid.x, 1, game.world.WORLD_CHUNKS_X * game.world.CHUNK_SIZE - 2),
			clampi(target_grid.y, 1, game.world.WORLD_CHUNKS_Y * game.world.CHUNK_SIZE - 2)
		)
	
	if game.world.is_walkable(target_grid):
		target_world_pos = _grid_to_world(target_grid)
		var occupied = _get_occupied()
		_path = game.world.find_path_generated_only(cur_grid, target_grid, 200, occupied)
	state = EnemyState.MOVING

# -------- 伤害系统 --------
func take_damage(amount: float, attacker: Node2D = null):
	hp -= amount
	queue_redraw()  # 刷新头顶HP条
	if hp <= 0:
		_die()
		return

func _die():
	if state == EnemyState.DEAD:
		return
	state = EnemyState.DEAD
	
	# 掉落战利品
	var game = get_node_or_null("/root/Game")
	if game and game.world:
		var grid_pos = _get_grid()
		game.world.drop_item_on_ground(grid_pos, "raw_meat", randi_range(10, 30))
	
	hp = 0
	died.emit(_get_grid())
	
	# 死亡动画：变红然后消失
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 0.3, 0.3, 0.5), 0.5)
	tween.tween_callback(queue_free)

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

func _get_occupied() -> Dictionary:
	"""获取当前所有被单位占据的网格位置"""
	var occupied: Dictionary = {}
	var game = get_node_or_null("/root/Game")
	if not game:
		return occupied
	return game.selection_system.get_occupied_grid_positions(self)

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
		if game.world.is_in_world_bounds(target_grid):
			var occupied = _get_occupied()
			_path = game.world.find_path_generated_only(cur_grid, target_grid, 500, occupied)
		else:
			_path = []
	
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
		# delta 已包含 Engine.time_scale 倍率
		position += dir * move_speed * delta
		return false
	else:
		if not _path.is_empty():
			_path.remove_at(0)
			return false
		else:
			position = target_world_pos
			return true

func spawn_at_edge(game_node) -> bool:
	"""在地图随机边缘生成敌人，返回是否成功"""
	if not game_node or not game_node.world:
		return false
	
	var world = game_node.world
	var edge = randi() % 4
	var world_tiles_x = world.WORLD_CHUNKS_X * world.CHUNK_SIZE
	var world_tiles_y = world.WORLD_CHUNKS_Y * world.CHUNK_SIZE
	
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
		var found = false
		for radius in range(1, 10):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if abs(dx) != radius and abs(dy) != radius:
						continue
					var check = spawn_grid + Vector2i(dx, dy)
					if world.is_in_world_bounds(check) and world.is_walkable(check):
						spawn_grid = check
						found = true
						break
				if found:
					break
			if found:
				break
	
	if not world.is_walkable(spawn_grid):
		return false
	
	position = _grid_to_world(spawn_grid)
	# 向世界中心方向移动
	var center_pixel = world.get_world_center_pixel()
	var dir_to_center = (center_pixel - position).normalized()
	target_world_pos = position + dir_to_center * 300.0
	return true
