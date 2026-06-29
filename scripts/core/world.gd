# 世界系统 - World System
# 管理游戏地图、区块、资源、地形和地面物品
extends Node2D
class_name World

const ItemDefinitions = preload("res://resources/item_definitions.gd")

signal tile_changed(pos: Vector2i, tile_type: int)
signal resource_depleted(pos: Vector2i)
signal ground_items_changed(grid_pos: Vector2i)

# 世界大小（区块数）
const CHUNK_SIZE := 16
const WORLD_CHUNKS_X := 8
const WORLD_CHUNKS_Y := 8

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
	
	func get_data():
		return ItemDefinitions.get_item(item_id)
	
	func can_merge(other_id: String) -> bool:
		return item_id == other_id
	
	func add(amt: int) -> int:
		var data = get_data()
		if data == null:
			return amt
		var max_stack = data.max_stack
		var can_add = max_stack - amount
		var to_add = mini(can_add, amt)
		amount += to_add
		return amt - to_add  # 剩余未添加

# 地面物品：Vector2i(网格坐标) -> Array[GroundItemStack]
var ground_items: Dictionary = {}

# 存储数据
var chunks: Dictionary = {}  # Vector2i(区块坐标) -> ChunkData
var tile_size: int = 32
var rng := RandomNumberGenerator.new()
var world_seed: int = 0  # 地图随机种子，新游戏时随机生成

# 可配置参数
var resource_multiplier: float = 5.0     # 资源初始点数倍率
var default_harvest_amount: float = 5.0  # 每次采集获得的资源量

func _ready():
	rng.randomize()

func apply_settings(multiplier: float, harvest_amt: float):
	"""从 GameManager 加载可配置参数"""
	resource_multiplier = multiplier
	default_harvest_amount = harvest_amt

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

func _generate_chunk(chunk: ChunkData):
	# 使用多层噪声生成地形，产生自然连续的地貌
	# world_seed 确保每次新游戏地图不同；存档时保存 world_seed 保证读档后地图一致
	var seed_val = chunk.pos.x * 10000 + chunk.pos.y + world_seed * 100000
	var seed_base = hash(seed_val)
	
	# 地势噪声（Elevation）- 决定海拔高度
	var elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = seed_base
	elevation_noise.frequency = 0.045
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 4
	elevation_noise.fractal_lacunarity = 2.0
	elevation_noise.fractal_gain = 0.5
	elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# 湿度噪声（Moisture）- 决定植被分布
	var moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = seed_base + 9999
	moisture_noise.frequency = 0.07
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 3
	moisture_noise.fractal_lacunarity = 2.0
	moisture_noise.fractal_gain = 0.5
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# 微扰动噪声 - 为地形边缘增加自然过渡细节
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed_base + 5555
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
	return tile != TileType.WATER and tile != TileType.DEEP_WATER and tile != TileType.MOUNTAIN

# ==================== 地面物品管理 ====================

func drop_item_on_ground(grid_pos: Vector2i, item_id: String, amount: int) -> int:
	"""在地面指定格子掉落物品，返回未掉落的剩余数量（超出堆叠上限的部分）"""
	if amount <= 0 or item_id == "":
		return amount
	
	if not ground_items.has(grid_pos):
		ground_items[grid_pos] = []
	
	var stacks = ground_items[grid_pos]
	var remaining = amount
	
	# 先尝试合并到现有堆叠
	for stack in stacks:
		if stack.can_merge(item_id):
			remaining = stack.add(remaining)
			if remaining <= 0:
				ground_items_changed.emit(grid_pos)
				return 0
	
	# 还有剩余则创建新堆叠
	while remaining > 0:
		var new_stack := GroundItemStack.new(item_id)
		remaining = new_stack.add(remaining)
		stacks.append(new_stack)
	
	ground_items_changed.emit(grid_pos)
	return remaining

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
	
	return {"chunks": chunk_list, "ground_items": ground_data, "world_seed": world_seed}

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
