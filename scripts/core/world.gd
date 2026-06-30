# 世界系统 - World System
# 管理游戏地图、区块、资源、地形和地面物品
extends Node2D
class_name World

const ItemDefinitions = preload("res://resources/item_definitions.gd")

signal tile_changed(pos: Vector2i, tile_type: int)
signal resource_depleted(pos: Vector2i)
signal ground_items_changed(grid_pos: Vector2i)
signal chunk_generated(chunk_pos: Vector2i)

# 每个区块的大小（瓦片数）
const CHUNK_SIZE := 16

# 世界大小（区块数），可通过 game_settings.cfg 配置
var WORLD_CHUNKS_X := GameConfig.world_chunks_x
var WORLD_CHUNKS_Y := GameConfig.world_chunks_y

# 地形类型枚举
enum TileType {
	GRASS,       # 草地
	DIRT,        # 泥土
	SAND,        # 沙地
	WATER,       # 水域
	DEEP_WATER,  # 深水
	STONE,       # 岩石地面
	FOREST,      # 森林
	MOUNTAIN,    # 山脉
	SNOW,        # 雪地
	ROAD,        # 道路
	FLOOR,       # 地板（建筑内部）
	WALL,        # 墙壁
}

# 资源节点类型
enum ResourceNodeType {
	NONE,
	TREE,        # 树木
	STONE_DEPOSIT,  # 石矿
	IRON_DEPOSIT,   # 铁矿
	COPPER_DEPOSIT, # 铜矿
	COAL_DEPOSIT,   # 煤矿
	BERRY_BUSH,     # 浆果丛
	WILDLIFE,       # 野生动物
}

# 区块数据结构
class ChunkData:
	var pos: Vector2i
	var tiles: Dictionary  # Vector2i(局部坐标) -> TileType
	var resources: Dictionary  # Vector2i(局部坐标) -> {type, amount}
	var buildings: Dictionary  # Vector2i(局部坐标) -> building_id
	var is_generated: bool = false
	
	func _init(p: Vector2i):
		pos = p

# 资源矿石数据
class ResourceDeposit:
	var type: ResourceNodeType
	var amount: float
	var max_amount: float
	var harvest_time: float  # 每次采集耗时
	var harvest_amount: float = 1.0  # 每次采集获得的资源量
	
	func _init(t: ResourceNodeType, amt: float, time: float = 2.0):
		type = t
		amount = amt
		max_amount = amt
		harvest_time = time
	
	func set_harvest_amount(amt: float):
		harvest_amount = amt
	
	func get_item_drop() -> String:
		match type:
			ResourceNodeType.TREE:
				return "wood"
			ResourceNodeType.STONE_DEPOSIT:
				return "stone"
			ResourceNodeType.IRON_DEPOSIT:
				return "iron_ore"
			ResourceNodeType.COPPER_DEPOSIT:
				return "copper_ore"
			ResourceNodeType.COAL_DEPOSIT:
				return "coal"
			ResourceNodeType.BERRY_BUSH:
				return "berry"
		return ""

# ==================== 地面物品系统 ====================
# 地面物品堆（同一格子同类物品合并）
class GroundItemStack:
	var item_id: String
	var amount: int
	
	func _init(id: String, amt: int = 1):
		item_id = id
		amount = amt
	
	func can_merge(other_id: String) -> bool:
		return item_id == other_id
	
	func add(amt: int) -> int:
		amount += amt
		return 0

# 地面物品：Vector2i(网格坐标) -> Array[GroundItemStack]
var ground_items: Dictionary = {}

# 存储数据
var chunks: Dictionary = {}  # Vector2i(区块坐标) -> ChunkData
var tile_size: int = 32
var rng := RandomNumberGenerator.new()
var world_seed: int = 0  # 地图随机种子，新游戏时随机生成

# 动态世界边界跟踪（支持世界向任意方向扩张）
var _min_chunk_x: int = 0
var _max_chunk_x: int = 0
var _min_chunk_y: int = 0
var _max_chunk_y: int = 0

# 可配置参数（初始化时从 GameConfig 加载）
var resource_multiplier: float = 5.0     # 资源初始点数倍率
var default_harvest_amount: float = 5.0  # 每次采集获得的资源量

func _ready():
	rng.randomize()
	var game_config = get_node("/root/GameConfig")
	resource_multiplier = game_config.resource_amount_multiplier
	default_harvest_amount = game_config.harvest_amount
	# 初始化世界边界
	_max_chunk_x = WORLD_CHUNKS_X - 1
	_max_chunk_y = WORLD_CHUNKS_Y - 1
	_min_chunk_x = 0
	_min_chunk_y = 0

# func _load_world_settings():
# 	"""从 GameConfig 加载世界配置参数"""
# 	WORLD_CHUNKS_X = GameConfig.world_chunks_x
# 	WORLD_CHUNKS_Y = GameConfig.world_chunks_y

# -------- 区块生成 --------
func get_chunk(chunk_pos: Vector2i) -> ChunkData:
	if not chunks.has(chunk_pos):
		chunks[chunk_pos] = ChunkData.new(chunk_pos)
	return chunks[chunk_pos]

func ensure_chunk_generated(chunk_pos: Vector2i):
	var chunk = get_chunk(chunk_pos)
	if chunk.is_generated:
		return
	_generate_chunk(chunk)
	_update_world_bounds(chunk_pos)

func ensure_surrounding_chunks_generated(center_chunk: Vector2i):
	"""生成中心区块及其周围8个区块（已生成的忽略）"""
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var chunk_pos = center_chunk + Vector2i(dx, dy)
			var chunk = get_chunk(chunk_pos)
			if chunk.is_generated:
				continue
			_generate_chunk(chunk)
			# 更新世界边界记录，确保新增区块被纳入世界范围
			_update_world_bounds(chunk_pos)

func _generate_chunk(chunk: ChunkData):
	# 使用多层噪声生成地形，产生自然连续的地貌
	# 所有区块共享同一个全局噪声种子（hash(world_seed)），
	# 仅靠世界坐标 (wx, wy) 区分采样位置，保证跨区块地形天然连续
	var noise_seed = hash(world_seed)
	
	# 区块级种子仅用于资源哈希，不影响地形连续性
	var seed_val = chunk.pos.x * 10000 + chunk.pos.y + world_seed * 100000
	var seed_base = hash(seed_val)
	
	# 地势噪声（Elevation）- 决定海拔高度
	var elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = noise_seed
	elevation_noise.frequency = 0.045
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 4
	elevation_noise.fractal_lacunarity = 2.0
	elevation_noise.fractal_gain = 0.5
	elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# 湿度噪声（Moisture）- 决定植被分布
	var moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = noise_seed + 9999
	moisture_noise.frequency = 0.07
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 3
	moisture_noise.fractal_lacunarity = 2.0
	moisture_noise.fractal_gain = 0.5
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# 微扰动噪声 - 为地形边缘增加自然过渡细节
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = noise_seed + 5555
	detail_noise.frequency = 0.15
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 2
	
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			var tile_pos := Vector2i(x, y)
			# 世界坐标（用于噪声采样，保证跨区块连续）
			var wx = chunk.pos.x * CHUNK_SIZE + x
			var wy = chunk.pos.y * CHUNK_SIZE + y
			var world_pos = Vector2i(wx, wy)
			
			# 采样地势 [-1, 1] + 微扰动
			var elevation = elevation_noise.get_noise_2d(wx, wy)
			elevation += detail_noise.get_noise_2d(wx, wy) * 0.08
			
			# 根据地势高度分配地形类型，形成自然带状分布
			var tile: int
			if elevation < -0.55:
				tile = TileType.DEEP_WATER
			elif elevation < -0.25:
				tile = TileType.WATER
			elif elevation < -0.10:
				tile = TileType.SAND
			elif elevation < 0.40:
				# 中海拔区：由湿度决定森林、草地或泥土
				var moisture = moisture_noise.get_noise_2d(wx, wy)
				if moisture > 0.15:
					tile = TileType.FOREST
				elif moisture < -0.35:
					tile = TileType.DIRT
				else:
					tile = TileType.GRASS
			elif elevation < 0.55:
				tile = TileType.STONE
			elif elevation < 0.75:
				tile = TileType.MOUNTAIN
			else:
				tile = TileType.SNOW
			
			chunk.tiles[tile_pos] = tile
			
			# 使用世界坐标哈希替代顺序RNG，保证跨区块边界的资源分布连续性
			var res_rand = _world_rand(world_pos, seed_base, 0)
			
			# 根据地形概率生成自然资源
			if tile == TileType.FOREST and res_rand < 0.6:
				var dep = ResourceDeposit.new(
					ResourceNodeType.TREE,
					_world_rand_range(world_pos, seed_base, 1, 5.0, 15.0) * resource_multiplier,
					2.0
				)
				dep.set_harvest_amount(default_harvest_amount)
				chunk.resources[tile_pos] = dep
			elif tile == TileType.STONE and res_rand < 0.5:
				var dep = ResourceDeposit.new(
					ResourceNodeType.STONE_DEPOSIT,
					_world_rand_range(world_pos, seed_base, 1, 10.0, 30.0) * resource_multiplier,
					3.0
				)
				dep.set_harvest_amount(default_harvest_amount)
				chunk.resources[tile_pos] = dep
			elif tile == TileType.GRASS and res_rand < 0.08:
				var dep = ResourceDeposit.new(
					ResourceNodeType.BERRY_BUSH,
					_world_rand_range(world_pos, seed_base, 1, 3.0, 8.0) * resource_multiplier,
					1.5
				)
				dep.set_harvest_amount(default_harvest_amount)
				chunk.resources[tile_pos] = dep
			# 矿石资源 - 与自然资源合并到同一循环，使用独立哈希通道保证跨区块连续性
			elif tile in [TileType.GRASS, TileType.DIRT] and not chunk.resources.has(tile_pos):
				var ore_rand = _world_rand(world_pos, seed_base, 2)
				if ore_rand < 0.02:  # 铁矿石
					var dep = ResourceDeposit.new(
						ResourceNodeType.IRON_DEPOSIT,
						_world_rand_range(world_pos, seed_base, 3, 8.0, 25.0) * resource_multiplier,
						4.0
					)
					dep.set_harvest_amount(default_harvest_amount)
					chunk.resources[tile_pos] = dep
				elif ore_rand < 0.035:  # 铜矿石
					var dep = ResourceDeposit.new(
						ResourceNodeType.COPPER_DEPOSIT,
						_world_rand_range(world_pos, seed_base, 3, 8.0, 25.0) * resource_multiplier,
						4.0
					)
					dep.set_harvest_amount(default_harvest_amount)
					chunk.resources[tile_pos] = dep
				elif ore_rand < 0.045:  # 煤矿
					var dep = ResourceDeposit.new(
						ResourceNodeType.COAL_DEPOSIT,
						_world_rand_range(world_pos, seed_base, 3, 5.0, 20.0) * resource_multiplier,
						3.0
					)
					dep.set_harvest_amount(default_harvest_amount)
					chunk.resources[tile_pos] = dep
	
	chunk.is_generated = true
	chunk_generated.emit(chunk.pos)

# -------- 确定性随机数辅助函数（基于世界坐标，保证跨区块边界连续）--------
func _world_rand(pos: Vector2i, base_seed: int, channel: int) -> float:
	"""基于世界坐标的确定性伪随机数 [0, 1)"""
	var h = hash(pos) ^ hash(base_seed + channel)
	return (h % 1000000) / 1000000.0

func _world_rand_range(pos: Vector2i, base_seed: int, channel: int, from: float, to: float) -> float:
	"""基于世界坐标的确定性范围内随机值"""
	return lerpf(from, to, _world_rand(pos, base_seed, channel))

# -------- 世界坐标操作 --------
func global_to_chunk(global_pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(global_pos.x / float(CHUNK_SIZE)),
		floori(global_pos.y / float(CHUNK_SIZE))
	)

func global_to_local(global_pos: Vector2i) -> Vector2i:
	var chunk_pos = global_to_chunk(global_pos)
	return global_pos - chunk_pos * CHUNK_SIZE

func get_tile_at(pos: Vector2i) -> int:
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	return chunk.tiles.get(local_pos, TileType.GRASS)

func get_resource_at(pos: Vector2i) -> ResourceDeposit:
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	return chunk.resources.get(local_pos, null)

func set_tile_at(pos: Vector2i, tile_type: int):
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	chunk.tiles[local_pos] = tile_type
	tile_changed.emit(pos, tile_type)

func set_building_at(pos: Vector2i, building_id: String):
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	chunk.buildings[local_pos] = building_id

func remove_building_at(pos: Vector2i):
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	chunk.buildings.erase(local_pos)

func get_building_at(pos: Vector2i) -> String:
	var chunk_pos = global_to_chunk(pos)
	var local_pos = global_to_local(pos)
	var chunk = get_chunk(chunk_pos)
	return chunk.buildings.get(local_pos, "")

# -------- 资源交互 --------
func harvest_resource(pos: Vector2i, amount: float = -1.0) -> Dictionary:
	"""采集资源，返回{item_id, amount}，如果资源耗尽返回空
	参数 amount: 传入 >0 使用指定值，传入 <=0 使用资源点自身的 harvest_amount"""
	var deposit = get_resource_at(pos)
	if deposit == null or deposit.amount <= 0:
		return {}
	
	var item_id = deposit.get_item_drop()
	if item_id == "":
		return {}
	
	var harvest_amt = deposit.harvest_amount if amount <= 0.0 else amount
	var harvested = min(harvest_amt, deposit.amount)
	deposit.amount -= harvested
	
	if deposit.amount <= 0:
		var chunk_pos = global_to_chunk(pos)
		var local_pos = global_to_local(pos)
		chunks[chunk_pos].resources.erase(local_pos)
		resource_depleted.emit(pos)
	
	return {"item_id": item_id, "amount": harvested}

# -------- 路径查找 --------
func is_walkable(pos: Vector2i) -> bool:
	var tile = get_tile_at(pos)
	if tile == TileType.WATER or tile == TileType.DEEP_WATER or tile == TileType.MOUNTAIN:
		return false
	
	# 检查是否有不可通行的建筑（墙）
	var building_id = get_building_at(pos)
	if building_id != "":
		var bld_data = ItemDefinitions.get_building(building_id)
		if bld_data and bld_data.id != "" and not bld_data.is_passable:
			return false
	
	return true

func find_path(from_pos: Vector2i, to_pos: Vector2i, max_steps: int = 500) -> Array[Vector2i]:
	"""A*寻路，返回从 from_pos 到 to_pos 的网格路径（不含起点），
	如果无路可走则返回空数组。
	max_steps 限制搜索步数防止死循环。"""
	if from_pos == to_pos:
		return []
	if not is_walkable(to_pos):
		return []
	
	var came_from := Dictionary()  # Vector2i -> Vector2i
	var g_score := Dictionary()    # Vector2i -> float
	var f_score := Dictionary()    # Vector2i -> float
	
	var key_from = _pos_key(from_pos)
	var _key_to = _pos_key(to_pos)
	g_score[key_from] = 0.0
	f_score[key_from] = _astar_heuristic(from_pos, to_pos)
	
	var open_set := [from_pos]
	var open_set_keys := {key_from: true}  # 快速查找
	
	var steps := 0
	
	while open_set.size() > 0 and steps < max_steps:
		steps += 1
		
		# 找 f_score 最小的节点
		var current = open_set[0]
		var current_key = _pos_key(current)
		var best_idx = 0
		var best_f = f_score.get(current_key, INF)
		for i in range(1, open_set.size()):
			var k = _pos_key(open_set[i])
			var f = f_score.get(k, INF)
			if f < best_f:
				best_f = f
				current = open_set[i]
				current_key = k
				best_idx = i
		
		# 到达目标
		if current == to_pos:
			return _reconstruct_path(came_from, current)
		
		# 从 open_set 移除
		open_set.remove_at(best_idx)
		open_set_keys.erase(current_key)
		
		# 检查邻居（4方向 + 对角线）
		var neighbors = [
			current + Vector2i(0, -1),
			current + Vector2i(0, 1),
			current + Vector2i(-1, 0),
			current + Vector2i(1, 0),
			current + Vector2i(-1, -1),
			current + Vector2i(1, -1),
			current + Vector2i(-1, 1),
			current + Vector2i(1, 1),
		]
		
		# 确保所有区块已生成
		for n in neighbors:
			var chunk_n = global_to_chunk(n)
			ensure_chunk_generated(chunk_n)
		
		var current_g = g_score.get(current_key, INF)
		
		for neighbor in neighbors:
			if not is_walkable(neighbor):
				continue
			
			# 对角线移动时检查是否被角落阻挡
			var diff = neighbor - current
			if abs(diff.x) == 1 and abs(diff.y) == 1:
				# 如果两个相邻直角格子都是不可行走的，则不能对角线穿越
				if not is_walkable(current + Vector2i(diff.x, 0)) and not is_walkable(current + Vector2i(0, diff.y)):
					continue
			
			var n_key = _pos_key(neighbor)
			var move_cost = 1.0 if (diff.x == 0 or diff.y == 0) else 1.414  # 对角线略贵
			var tentative_g = current_g + move_cost
			
			if tentative_g < g_score.get(n_key, INF):
				came_from[n_key] = current
				g_score[n_key] = tentative_g
				f_score[n_key] = tentative_g + _astar_heuristic(neighbor, to_pos)
				
				if not open_set_keys.has(n_key):
					open_set.append(neighbor)
					open_set_keys[n_key] = true
	
	# 无路可走
	return []

func get_world_center_pixel() -> Vector2:
	"""返回世界中心像素坐标（考虑动态扩张后的边界）"""
	var center_chunk_x = (_min_chunk_x + _max_chunk_x) / 2.0
	var center_chunk_y = (_min_chunk_y + _max_chunk_y) / 2.0
	return Vector2(
		center_chunk_x * CHUNK_SIZE * tile_size + CHUNK_SIZE * tile_size / 2.0,
		center_chunk_y * CHUNK_SIZE * tile_size + CHUNK_SIZE * tile_size / 2.0
	)

func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]

func _astar_heuristic(a: Vector2i, b: Vector2i) -> float:
	# 八方向曼哈顿距离（允许对角线移动）
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	return max(dx, dy) + (1.414 - 1.0) * min(dx, dy)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var node = current
	while came_from.has(_pos_key(node)):
		path.append(node)
		node = came_from[_pos_key(node)]
	path.reverse()
	return path

# ==================== 地面物品管理 ====================

func drop_item_on_ground(grid_pos: Vector2i, item_id: String, amount: int) -> int:
	"""在地面指定格子掉落物品"""
	if amount <= 0 or item_id == "":
		return amount
	
	if not ground_items.has(grid_pos):
		ground_items[grid_pos] = []
	
	var stacks = ground_items[grid_pos]
	
	# 合并到现有堆叠
	for stack in stacks:
		if stack.can_merge(item_id):
			stack.add(amount)
			ground_items_changed.emit(grid_pos)
			return 0
	
	# 没有现有堆叠则创建新堆叠
	stacks.append(GroundItemStack.new(item_id, amount))
	ground_items_changed.emit(grid_pos)
	return 0

func pickup_from_ground(grid_pos: Vector2i, item_id: String, amount: int) -> int:
	"""从地面拾取物品，返回实际拾取数量"""
	if amount <= 0 or item_id == "":
		return 0
	if not ground_items.has(grid_pos):
		return 0
	
	var stacks = ground_items[grid_pos]
	var picked = 0
	
	for i in range(stacks.size() - 1, -1, -1):
		var stack = stacks[i]
		if stack.item_id == item_id:
			var to_take = mini(stack.amount, amount - picked)
			stack.amount -= to_take
			picked += to_take
			if stack.amount <= 0:
				stacks.remove_at(i)
			if picked >= amount:
				break
	
	# 清理空格子
	if stacks.is_empty():
		ground_items.erase(grid_pos)
	
	if picked > 0:
		ground_items_changed.emit(grid_pos)
	return picked

func get_ground_items_at(grid_pos: Vector2i) -> Array:
	"""获取指定格子上的所有地面物品"""
	return ground_items.get(grid_pos, []).duplicate()

func count_ground_item(item_id: String) -> int:
	"""统计全地图某种地面物品的总数"""
	var total = 0
	for pos in ground_items:
		for stack in ground_items[pos]:
			if stack.item_id == item_id:
				total += stack.amount
	return total

func has_ground_item(item_id: String, amount: int = 1) -> bool:
	"""检查地面上是否有足够数量的某种物品"""
	return count_ground_item(item_id) >= amount

func find_nearest_ground_item(grid_center: Vector2i, item_id: String, max_radius: int = 10) -> Vector2i:
	"""从中心网格开始螺旋搜索，寻找最近的包含指定物品的地面格子"""
	for radius in range(max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var check_pos = grid_center + Vector2i(dx, dy)
				if ground_items.has(check_pos):
					for stack in ground_items[check_pos]:
						if stack.item_id == item_id and stack.amount > 0:
							return check_pos
	return Vector2i(-1, -1)

func get_all_ground_positions_of(item_id: String) -> Array:
	"""获取所有包含指定物品的地面格子位置列表"""
	var result: Array = []
	for pos in ground_items:
		for stack in ground_items[pos]:
			if stack.item_id == item_id and stack.amount > 0:
				result.append(pos)
				break
	return result

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var chunk_list = []
	for c in chunks:
		var chunk = chunks[c]
		var res_data = {}
		for r_pos in chunk.resources:
			var r = chunk.resources[r_pos]
			res_data[var_to_str(r_pos)] = {
				"type": r.type,
				"amount": r.amount,
				"max_amount": r.max_amount
			}
		var build_data = {}
		for b_pos in chunk.buildings:
			build_data[var_to_str(b_pos)] = chunk.buildings[b_pos]
		chunk_list.append({
			"pos_x": c.x,
			"pos_y": c.y,
			"tiles": chunk.tiles.duplicate(),
			"resources": res_data,
			"buildings": build_data,
			"generated": chunk.is_generated
		})
	# 序列化地面物品
	var ground_data = {}
	for pos in ground_items:
		var stacks_data = []
		for stack in ground_items[pos]:
			stacks_data.append({
				"id": stack.item_id,
				"amount": stack.amount
			})
		ground_data["%d,%d" % [pos.x, pos.y]] = stacks_data
	
	return {
		"chunks": chunk_list,
		"ground_items": ground_data,
		"world_seed": world_seed,
		"world_chunks_x": WORLD_CHUNKS_X,
		"world_chunks_y": WORLD_CHUNKS_Y,
	}

func _update_world_bounds(chunk_pos: Vector2i):
	"""根据新区块坐标扩展世界边界记录"""
	var changed = false
	if chunk_pos.x < _min_chunk_x:
		_min_chunk_x = chunk_pos.x
		changed = true
	if chunk_pos.x > _max_chunk_x:
		_max_chunk_x = chunk_pos.x
		changed = true
	if chunk_pos.y < _min_chunk_y:
		_min_chunk_y = chunk_pos.y
		changed = true
	if chunk_pos.y > _max_chunk_y:
		_max_chunk_y = chunk_pos.y
		changed = true
	
	if changed:
		WORLD_CHUNKS_X = _max_chunk_x - _min_chunk_x + 1
		WORLD_CHUNKS_Y = _max_chunk_y - _min_chunk_y + 1

func from_dict(data: Dictionary):
	chunks.clear()
	ground_items.clear()
	world_seed = data.get("world_seed", 0)
	
	# 恢复地面物品
	if data.has("ground_items"):
		for key in data.ground_items:
			var parts = key.split(",")
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			var stacks_data = data.ground_items[key]
			var stacks: Array[GroundItemStack] = []
			for sd in stacks_data:
				var stack := GroundItemStack.new(sd.id, sd.amount)
				stacks.append(stack)
			ground_items[pos] = stacks
	
	# 先恢复所有区块，然后重新计算世界边界
	var loaded_chunks: Array[Vector2i] = []
	for c_data in data.get("chunks", []):
		var cpos := Vector2i(c_data.pos_x, c_data.pos_y)
		var chunk := ChunkData.new(cpos)
		chunk.tiles = c_data.tiles
		
		for r_pos_str in c_data.resources:
			var r_data = c_data.resources[r_pos_str]
			var r = ResourceDeposit.new(r_data.type, r_data.amount)
			r.max_amount = r_data.max_amount
			chunk.resources[str_to_var(r_pos_str)] = r
		
		for b_pos_str in c_data.buildings:
			chunk.buildings[str_to_var(b_pos_str)] = c_data.buildings[b_pos_str]
		
		chunk.is_generated = c_data.generated
		chunks[cpos] = chunk
		loaded_chunks.append(cpos)
	
	# 根据实际加载的区块重新计算世界边界（覆盖存档中的固定值）
	if not loaded_chunks.is_empty():
		_min_chunk_x = loaded_chunks[0].x
		_max_chunk_x = loaded_chunks[0].x
		_min_chunk_y = loaded_chunks[0].y
		_max_chunk_y = loaded_chunks[0].y
		for cp in loaded_chunks:
			_min_chunk_x = mini(_min_chunk_x, cp.x)
			_max_chunk_x = maxi(_max_chunk_x, cp.x)
			_min_chunk_y = mini(_min_chunk_y, cp.y)
			_max_chunk_y = maxi(_max_chunk_y, cp.y)
		WORLD_CHUNKS_X = _max_chunk_x - _min_chunk_x + 1
		WORLD_CHUNKS_Y = _max_chunk_y - _min_chunk_y + 1
	else:
		# 没有任何区块时使用存档中保存的尺寸（兼容旧存档）
		WORLD_CHUNKS_X = data.get("world_chunks_x", WORLD_CHUNKS_X)
		WORLD_CHUNKS_Y = data.get("world_chunks_y", WORLD_CHUNKS_Y)
		_max_chunk_x = WORLD_CHUNKS_X - 1
		_max_chunk_y = WORLD_CHUNKS_Y - 1
		_min_chunk_x = 0
		_min_chunk_y = 0
