# 世界系统 - World System
# 管理游戏地图、区块、资源和地形
extends Node2D
class_name World

signal tile_changed(pos: Vector2i, tile_type: int)
signal resource_depleted(pos: Vector2i)

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
	
	func _init(t: ResourceNodeType, amt: float, time: float = 2.0):
		type = t
		amount = amt
		max_amount = amt
		harvest_time = time
	
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

# 存储数据
var chunks: Dictionary = {}  # Vector2i(区块坐标) -> ChunkData
var tile_size: int = 32
var rng := RandomNumberGenerator.new()

func _ready():
	rng.randomize()

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
	# 使用噪声生成地形
	var seed_val = chunk.pos.x * 10000 + chunk.pos.y
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = hash(seed_val)
	
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			var tile_pos := Vector2i(x, y)
			# 基础地形 - 大多数为草地
			var tile = TileType.GRASS
			var rand_val = local_rng.randf()
			
			if rand_val < 0.05:
				tile = TileType.WATER
			elif rand_val < 0.08:
				tile = TileType.SAND
			elif rand_val < 0.15:
				tile = TileType.STONE
			elif rand_val < 0.30:
				tile = TileType.FOREST
			elif rand_val < 0.35:
				tile = TileType.DIRT
			
			chunk.tiles[tile_pos] = tile
			
			# 生成自然资源
			var res_rand = local_rng.randf()
			if tile == TileType.FOREST and res_rand < 0.6:
				chunk.resources[tile_pos] = ResourceDeposit.new(
					ResourceNodeType.TREE,
					local_rng.randf_range(5.0, 15.0),
					2.0
				)
			elif tile == TileType.STONE and res_rand < 0.5:
				chunk.resources[tile_pos] = ResourceDeposit.new(
					ResourceNodeType.STONE_DEPOSIT,
					local_rng.randf_range(10.0, 30.0),
					3.0
				)
			elif tile == TileType.GRASS and res_rand < 0.08:
				chunk.resources[tile_pos] = ResourceDeposit.new(
					ResourceNodeType.BERRY_BUSH,
					local_rng.randf_range(3.0, 8.0),
					1.5
				)
	
	# 在草地和泥土上生成一些额外资源
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			var tile_pos := Vector2i(x, y)
			var tile = chunk.tiles.get(tile_pos, TileType.GRASS)
			if tile in [TileType.GRASS, TileType.DIRT] and not chunk.resources.has(tile_pos):
				var res_rand = local_rng.randf()
				if res_rand < 0.02:  # 铁矿石
					chunk.resources[tile_pos] = ResourceDeposit.new(
						ResourceNodeType.IRON_DEPOSIT,
						local_rng.randf_range(8.0, 25.0),
						4.0
					)
				elif res_rand < 0.035:  # 铜矿石
					chunk.resources[tile_pos] = ResourceDeposit.new(
						ResourceNodeType.COPPER_DEPOSIT,
						local_rng.randf_range(8.0, 25.0),
						4.0
					)
				elif res_rand < 0.045:  # 煤矿
					chunk.resources[tile_pos] = ResourceDeposit.new(
						ResourceNodeType.COAL_DEPOSIT,
						local_rng.randf_range(5.0, 20.0),
						3.0
					)
	
	chunk.is_generated = true

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
func harvest_resource(pos: Vector2i, amount: float = 1.0) -> Dictionary:
	"""采集资源，返回{item_id, amount}，如果资源耗尽返回空"""
	var deposit = get_resource_at(pos)
	if deposit == null or deposit.amount <= 0:
		return {}
	
	var item_id = deposit.get_item_drop()
	if item_id == "":
		return {}
	
	var harvested = min(amount, deposit.amount)
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
	return {"chunks": chunk_list}

func from_dict(data: Dictionary):
	chunks.clear()
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
