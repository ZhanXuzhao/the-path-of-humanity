# 建筑系统 - Building System
# 管理建筑的放置、建造、拆除和运行
extends Node
class_name BuildingSystem

const ItemDefinitions = preload("res://resources/item_definitions.gd")

signal building_placed(building_id: String, pos: Vector2i)
signal building_removed(building_id: String, pos: Vector2i)
signal building_completed(pos: Vector2i)
signal construction_progress_updated(pos: Vector2i, progress: float, work_cost: float)
signal production_output(pos: Vector2i, item_id: String, amount: int)
signal building_damaged(pos: Vector2i, damage: float, current_hp: int)
signal building_destroyed(building_id: String, pos: Vector2i)

# 建筑实例数据
class BuildingInstance:
	var building_id: String
	var grid_pos: Vector2i
	var rotation: int = 0        # 0, 90, 180, 270
	var hp: int
	var max_hp: int
	var is_completed: bool = false
	var construction_progress: float = 0.0
	var production_timer: float = 0.0
	var attack_timer: float = 0.0  # 攻击冷却计时器
	var inventory = null
	var assigned_settlers: Array[String] = []  # settler IDs
	var deposited_materials: Dictionary = {}  # 已搬运到工地的建筑材料 {item_id: amount}
	var display_name: String = ""  # 显示名称（带编号，如"储物架 1"）
	var assigned_settler_id: String = ""  # 分配给谁的床（木床专用）
	var assigned_settler_name: String = ""  # 分配对象的姓名缓存
	
	func get_data():
		return ItemDefinitions.get_building(building_id)
	
	func get_size() -> Vector2i:
		var data = get_data()
		if data == null:
			return Vector2i.ONE
		# 处理旋转
		if rotation == 90 or rotation == 270:
			return Vector2i(data.size.y, data.size.x)
		return data.size
	
	func get_missing_materials() -> Dictionary:
		"""返回还缺少的建筑材料 {item_id: amount}"""
		var data = get_data()
		if data == null or data.materials.is_empty():
			return {}
		var missing = {}
		for mat_id in data.materials:
			var needed = data.materials[mat_id]
			var deposited = deposited_materials.get(mat_id, 0)
			var still_needed = needed - deposited
			if still_needed > 0:
				missing[mat_id] = still_needed
		return missing
	
	func is_materials_ready() -> bool:
		"""检查是否所有建筑材料都已备齐"""
		return get_missing_materials().is_empty()
	
	func deposit_material(item_id: String, amount: int) -> int:
		"""存入建筑材料，返回未消耗的剩余数量"""
		var data = get_data()
		if data == null:
			return amount
		var needed = data.materials.get(item_id, 0)
		var deposited = deposited_materials.get(item_id, 0)
		var can_take = needed - deposited
		if can_take <= 0:
			return amount  # 已够，全部退回
		var to_add = mini(amount, can_take)
		deposited_materials[item_id] = deposited + to_add
		return amount - to_add  # 返回多余的部分
	
	func _init(id: String, pos: Vector2i):
		building_id = id
		grid_pos = pos
		var data = get_data()
		if data != null:
			hp = data.hp
			max_hp = data.hp
			if data.storage_capacity > 0:
				inventory = Inventory.new()
				# 从 GameConfig 读取容量，实现可配置
				if id == "storage_rack":
					var game_config = Engine.get_main_loop().root.get_node("/root/GameConfig")
					inventory.capacity = game_config.storage_rack_capacity
				else:
					inventory.capacity = data.storage_capacity

# 所有建筑实例
var buildings: Dictionary = {}  # Vector2i -> BuildingInstance
var world = null

# 存储建筑编号计数器
var _storage_rack_counter: int = 0

# 已完成床铺索引 {grid_pos: BuildingInstance}，用于快速查找有床位的建筑
var _completed_bed_index: Dictionary = {}

# 已完成存储建筑索引（按 grid_pos 索引，方便快速查找和移除）
var _completed_storage_index: Dictionary = {}  # Vector2i -> BuildingInstance

func _ready():
	# 尝试获取世界引用
	world = get_node_or_null("/root/Game/World")
	if world == null:
		world = get_parent().get_node_or_null("World")

# -------- 放置建筑 --------
func can_place_building(building_id: String, pos: Vector2i) -> Dictionary:
	"""检查是否可以放置建筑，返回{can_place, reason}"""
	var data = ItemDefinitions.get_building(building_id)
	if data == null or data.id == "":
		return {"can_place": false, "reason": "未知建筑"}
	
	var size = data.size
	
	# 检查所有占用格子
	for x in size.x:
		for y in size.y:
			var check_pos = pos + Vector2i(x, y)
			
			# 检查是否在地图范围内（支持动态扩张后的负坐标）
			if world and not world.is_in_world_bounds(check_pos):
				return {"can_place": false, "reason": "超出地图边界"}
			
			# 检查是否可行走
			if world and not world.is_walkable(check_pos):
				return {"can_place": false, "reason": "地形不可建造"}
			
			# 检查是否被其他建筑占用
			if buildings.has(check_pos):
				return {"can_place": false, "reason": "该位置已被占用"}
	
	return {"can_place": true, "reason": ""}

func place_building(building_id: String, pos: Vector2i) -> bool:
	"""放置建筑（开始建造）"""
	var check = can_place_building(building_id, pos)
	if not check.can_place:
		return false
	
	var data = ItemDefinitions.get_building(building_id)
	if data == null:
		return false
	
	var instance := BuildingInstance.new(building_id, pos)
	
	# 存储建筑自动编号
	if building_id == "storage_rack":
		_storage_rack_counter += 1
		instance.display_name = "%s %d" % [data.name, _storage_rack_counter]
	
	var size = data.size
	
	# 注册所有占用格子
	for x in size.x:
		for y in size.y:
			var grid_pos = pos + Vector2i(x, y)
			buildings[grid_pos] = instance
			if world:
				world.set_building_at(grid_pos, building_id)
	
	building_placed.emit(building_id, pos)
	return true

# -------- 建造进度 --------
func add_construction_progress(pos: Vector2i, amount: float) -> bool:
	"""增加建筑建造进度，返回是否完成"""
	var bld = get_building_at(pos)
	if bld == null:
		return false
	if bld.is_completed:
		return true
	
	# 物资未备齐不能建造
	if not bld.is_materials_ready():
		return false
	
	bld.construction_progress += amount
	var data = bld.get_data()
	
	# 发射进度更新信号（供渲染器更新进度条）
	if data != null:
		construction_progress_updated.emit(bld.grid_pos, bld.construction_progress, data.work_cost)
	
	if data != null and bld.construction_progress >= data.work_cost:
		bld.is_completed = true
		bld.hp = data.hp
		# 如果是存储建筑，加入索引
		if data.storage_capacity > 0:
			_completed_storage_index[bld.grid_pos] = bld
		# 如果是床铺建筑，加入床铺索引并自动分配
		if bld.building_id == "wooden_bed":
			_completed_bed_index[bld.grid_pos] = bld
			_assign_bed_to_settler(bld)
		building_completed.emit(bld.grid_pos)
		return true
	return false

func is_completed(pos: Vector2i) -> bool:
	var bld = get_building_at(pos)
	return bld != null and bld.is_completed

# -------- 床铺分配 --------
func _assign_bed_to_settler(bed_bld):
	"""自动将此床分配给一个没有床的定居者"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.settlers.is_empty():
		return
	
	# 获取所有已有床的定居者 ID
	var settled_ids: Dictionary = {}
	for pos in _completed_bed_index:
		var other_bed = _completed_bed_index[pos]
		if other_bed != bed_bld and other_bed.assigned_settler_id != "":
			settled_ids[other_bed.assigned_settler_id] = true
	
	# 找第一个没有床的定居者
	for s in game.settlers:
		if not is_instance_valid(s):
			continue
		if settled_ids.has(s.settler_id):
			continue  # 已有床
		# 分配此床给该定居者
		bed_bld.assigned_settler_id = s.settler_id
		bed_bld.assigned_settler_name = s.settler_name
		# 通知定居者他有床了（可选，用于后续AI优先使用自己的床）
		s.assigned_bed_pos = bed_bld.grid_pos
		# 提示
		var gm = get_node("/root/GameManager")
		if gm:
			gm.show_notification("%s 被分配到了木床" % s.settler_name, gm.NotificationType.INFO)
		return
	
	# 所有定居者都有床了，不做分配
	print("所有定居者已有床铺，木床暂未分配")

func get_beds_without_assignment() -> Array:
	"""获取所有未分配的床"""
	var result: Array = []
	for pos in _completed_bed_index:
		var bld = _completed_bed_index[pos]
		if bld.assigned_settler_id == "":
			result.append(bld)
	return result

func get_bed_for_settler(settler_id: String):
	"""获取指定定居者被分配到的床"""
	for pos in _completed_bed_index:
		var bld = _completed_bed_index[pos]
		if bld.assigned_settler_id == settler_id:
			return bld
	return null

func get_all_beds() -> Array:
	"""获取所有已完成的床"""
	var result: Array = []
	for pos in _completed_bed_index:
		result.append(_completed_bed_index[pos])
	return result

# -------- 建筑运行 --------
func process_buildings(delta: float):
	"""处理所有建筑的运行逻辑"""
	for pos in buildings.keys():
		var bld = buildings[pos]
		# 只在主格子处理一次
		if bld.grid_pos != pos:
			continue
		if not bld.is_completed:
			continue
		
		var data = bld.get_data()
		if data == null:
			continue
		
		# 生产建筑
		if data.production_time > 0 and not data.produces.is_empty():
			bld.production_timer += delta
			if bld.production_timer >= data.production_time:
				bld.production_timer = 0.0
				_try_produce(bld, data)
		
		# 防御建筑——自动攻击（攻击间隔跟随游戏变速）
		if data.attack_range > 0 and data.attack_damage > 0:
			var gm = get_node_or_null("/root/GameManager")
			var speed_mult = gm.time_speed if gm else 1.0
			bld.attack_timer += delta * speed_mult
			if bld.attack_timer >= data.attack_cooldown:
				bld.attack_timer = 0.0
				_try_tower_attack(bld, data)

func _try_tower_attack(bld, data):
	"""哨塔尝试攻击射程内的敌人（野猪等）"""
	var game = get_node_or_null("/root/Game")
	if game == null or world == null:
		return
	
	# 计算塔的中心像素位置
	var tile_size = world.tile_size
	var tower_center = Vector2(
		bld.grid_pos.x * tile_size + tile_size / 2.0,
		bld.grid_pos.y * tile_size + tile_size / 2.0
	)
	
	var attack_range_pixels = data.attack_range * tile_size
	var nearest_enemy = null
	var nearest_dist = INF
	
	# 扫描所有野猪
	for boar in game.boars:
		if not is_instance_valid(boar) or boar.state == boar.BoarState.DEAD:
			continue
		var dist = tower_center.distance_squared_to(boar.position)
		if dist < nearest_dist and dist <= attack_range_pixels * attack_range_pixels:
			nearest_dist = dist
			nearest_enemy = boar
	
	# 扫描所有敌对敌人
	if game.has_method("get_enemies"):
		for enemy in game.get_enemies():
			if not is_instance_valid(enemy) or enemy.state == enemy.EnemyState.DEAD:
				continue
			var dist = tower_center.distance_squared_to(enemy.position)
			if dist < nearest_dist and dist <= attack_range_pixels * attack_range_pixels:
				nearest_dist = dist
				nearest_enemy = enemy
	
	if nearest_enemy == null:
		return
	
	# 发射箭矢
	var arrow = load("res://scripts/entities/arrow_projectile.gd").new()
	arrow.init(tower_center, nearest_enemy, data.attack_damage)
	arrow.shooter = null  # 塔不是具体角色
	game.call_deferred("add_child", arrow)

func _try_produce(bld, data):
	"""尝试生产物品"""
	# 检查是否有足够的输入材料
	for item_id in data.consumes:
		var needed = data.consumes[item_id]
		# 从建筑库存或全局检查
		if bld.inventory and not bld.inventory.has_item(item_id, needed):
			return  # 材料不足
	
	# 消耗材料
	for item_id in data.consumes:
		var needed = data.consumes[item_id]
		if bld.inventory:
			bld.inventory.remove_item(item_id, needed)
	
	# 生产输出
	for item_id in data.produces:
		var produced = data.produces[item_id]
		if bld.inventory:
			bld.inventory.add_item(item_id, produced)
		production_output.emit(bld.grid_pos, item_id, produced)

# -------- 建筑查询 --------
func get_building_at(pos: Vector2i) -> BuildingInstance:
	return buildings.get(pos, null)

func get_all_buildings() -> Array:
	var unique: Array[BuildingInstance] = []
	var seen: Dictionary = {}
	for pos in buildings:
		var bld = buildings[pos]
		if not seen.has(bld.grid_pos):
			seen[bld.grid_pos] = true
			unique.append(bld)
	return unique

func get_buildings_by_type(building_id: String) -> Array:
	var result: Array[BuildingInstance] = []
	for bld in get_all_buildings():
		if bld.building_id == building_id:
			result.append(bld)
	return result

# -------- 建筑伤害系统 --------
func damage_building(pos: Vector2i, damage: float) -> bool:
	"""对建筑造成伤害，返回建筑是否被摧毁"""
	var bld = get_building_at(pos)
	if bld == null:
		return false
	if not bld.is_completed:
		return false
	
	bld.hp -= int(damage)
	building_damaged.emit(bld.grid_pos, damage, bld.hp)
	
	if bld.hp <= 0:
		_destroy_building(bld)
		return true
	return false

func repair_building(pos: Vector2i, amount: float) -> bool:
	"""维修建筑，恢复HP，返回是否已修满"""
	var bld = get_building_at(pos)
	if bld == null:
		return false
	if not bld.is_completed:
		return false
	if bld.hp >= bld.max_hp:
		return true  # 已满
	
	bld.hp = mini(bld.hp + int(amount), bld.max_hp)
	building_damaged.emit(bld.grid_pos, -amount, bld.hp)  # 负伤害表示维修
	return bld.hp >= bld.max_hp

func get_damaged_buildings() -> Array:
	"""获取所有需要维修的已完工建筑（HP未满）"""
	var result: Array = []
	var seen: Dictionary = {}
	for pos in buildings:
		var bld = buildings[pos]
		if seen.has(bld.grid_pos):
			continue
		seen[bld.grid_pos] = true
		if bld.is_completed and bld.hp < bld.max_hp:
			result.append(bld)
	return result

func _destroy_building(bld):
	"""摧毁建筑并清理（掉落库存物品到地面）"""
	var data = bld.get_data()
	var bld_id = bld.building_id
	var bld_pos = bld.grid_pos
	
	# 掉落库存物品到地面（存储建筑/生产建筑有 inventory）
	if bld.inventory != null and world:
		var world_node = world
		var game = get_node_or_null("/root/Game")
		# 遍历建筑占据的所有格子，将物品分散掉落
		var drop_positions: Array[Vector2i] = []
		var size = bld.get_size()
		for x in size.x:
			for y in size.y:
				drop_positions.append(bld.grid_pos + Vector2i(x, y))
		
		for item_id in bld.inventory.items:
			var amount = bld.inventory.items[item_id]
			if amount <= 0:
				continue
			# 分散掉落到每个格子
			var per_grid = ceil(amount / float(drop_positions.size()))
			var remaining = amount
			for gpos in drop_positions:
				if remaining <= 0:
					break
				var drop_amt = mini(per_grid, remaining)
				world_node.drop_item_on_ground(gpos, item_id, drop_amt)
				remaining -= drop_amt
	
	# 从索引中移除
	_completed_storage_index.erase(bld.grid_pos)
	_completed_bed_index.erase(bld.grid_pos)
	
	# 清除占用格子
	var size = bld.get_size()
	for x in size.x:
		for y in size.y:
			var grid_pos = bld.grid_pos + Vector2i(x, y)
			buildings.erase(grid_pos)
			if world:
				world.remove_building_at(grid_pos)
	
	building_destroyed.emit(bld_id, bld_pos)
	building_removed.emit(bld_id, bld_pos)  # 通知渲染器清理精灵
	
	# 通知游戏管理器
	var gm = get_node("/root/GameManager")
	if gm:
		var data2 = bld.get_data()
		var name_str = data2.name if data2 else bld_id
		gm.show_notification("建筑被摧毁: %s" % name_str, gm.NotificationType.COMBAT)

# -------- 存储建筑查询（使用预索引，O(1)~O(n)） --------
func get_completed_storage_buildings() -> Array:
	"""获取所有已完成的存储建筑"""
	var result: Array[BuildingInstance] = []
	for pos in _completed_storage_index:
		result.append(_completed_storage_index[pos])
	return result

func get_storage_buildings_with_space() -> Array:
	"""获取有空位的存储建筑"""
	var result: Array[BuildingInstance] = []
	for pos in _completed_storage_index:
		var bld = _completed_storage_index[pos]
		if bld.inventory != null and not bld.inventory.is_full():
			result.append(bld)
	return result

func get_storage_buildings_with_item(item_id: String, min_amount: int = 1) -> Array:
	"""获取存有指定物品的存储建筑"""
	var result: Array[BuildingInstance] = []
	for pos in _completed_storage_index:
		var bld = _completed_storage_index[pos]
		if bld.inventory != null and bld.inventory.has_item(item_id, min_amount):
			result.append(bld)
	return result

func count_item_in_storage(item_id: String) -> int:
	"""统计所有存储建筑中指定物品的总数"""
	var total = 0
	for pos in _completed_storage_index:
		var bld = _completed_storage_index[pos]
		if bld.inventory != null:
			total += bld.inventory.get_item_count(item_id)
	return total

# -------- AI辅助查询 --------
func get_uncompleted_buildings() -> Array:
	"""获取所有未完成的建筑（施工工地）"""
	var result: Array = []
	var seen: Dictionary = {}
	for pos in buildings:
		var bld = buildings[pos]
		if seen.has(bld.grid_pos):
			continue
		seen[bld.grid_pos] = true
		if not bld.is_completed:
			result.append(bld)
	return result

func get_completed_production_buildings() -> Array:
	"""获取所有已完成且有生产能力的建筑"""
	var result: Array = []
	var seen: Dictionary = {}
	for pos in buildings:
		var bld = buildings[pos]
		if seen.has(bld.grid_pos):
			continue
		seen[bld.grid_pos] = true
		if not bld.is_completed:
			continue
		var data = bld.get_data()
		if data and (data.production_time > 0 or data.storage_capacity > 0):
			result.append(bld)
	return result

# -------- 拆除建筑 --------
func remove_building(pos: Vector2i) -> bool:
	var bld = get_building_at(pos)
	if bld == null:
		return false
	
	var data = bld.get_data()
	var size = data.size if data else Vector2i.ONE
	
	# 从存储建筑索引中移除
	_completed_storage_index.erase(bld.grid_pos)
	
	# 从床铺索引中移除，并释放定居者的床分配
	if _completed_bed_index.has(bld.grid_pos):
		_completed_bed_index.erase(bld.grid_pos)
		if bld.assigned_settler_id != "":
			var game = get_node_or_null("/root/Game")
			if game:
				var settler = game.get_settler_by_id(bld.assigned_settler_id)
				if settler and is_instance_valid(settler):
					settler.assigned_bed_pos = Vector2i(-1, -1)
	
	# 清除所有占用格子
	for x in size.x:
		for y in size.y:
			var grid_pos = bld.grid_pos + Vector2i(x, y)
			buildings.erase(grid_pos)
			if world:
				world.remove_building_at(grid_pos)
	
	# 返还部分材料
	building_removed.emit(bld.building_id, bld.grid_pos)
	return true

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var data = {}
	for pos in buildings:
		var bld = buildings[pos]
		if bld.grid_pos == pos:  # 只序列化主格子
			var key = "%d,%d" % [pos.x, pos.y]
			data[key] = {
				"id": bld.building_id,
				"pos": {"x": pos.x, "y": pos.y},
				"hp": bld.hp,
				"max_hp": bld.max_hp,
				"progress": bld.construction_progress,
				"completed": bld.is_completed,
				"prod_timer": bld.production_timer,
				"attack_timer": bld.attack_timer,
				"inventory": bld.inventory.to_dict() if bld.inventory else null,
				"deposited_materials": bld.deposited_materials.duplicate(),
				"assigned_settler_id": bld.assigned_settler_id,
				"assigned_settler_name": bld.assigned_settler_name
			}
	return data

func from_dict(data: Dictionary):
	buildings.clear()
	_completed_storage_index.clear()
	for key in data:
		var b_data = data[key]
		var pos = Vector2i(b_data.pos.x, b_data.pos.y)
		var bld := BuildingInstance.new(b_data.id, pos)
		bld.hp = b_data.hp
		bld.max_hp = b_data.max_hp
		bld.construction_progress = b_data.progress
		bld.is_completed = b_data.completed
		bld.production_timer = b_data.prod_timer
		bld.attack_timer = b_data.get("attack_timer", 0.0)
		if b_data.has("deposited_materials"):
			bld.deposited_materials = b_data.deposited_materials.duplicate()
		if b_data.has("assigned_settler_id"):
			bld.assigned_settler_id = b_data.assigned_settler_id
			bld.assigned_settler_name = b_data.get("assigned_settler_name", "")
		
		if b_data.inventory != null and bld.inventory != null:
			bld.inventory.from_dict(b_data.inventory)
		
		# 重新注册所有格子
		var size = bld.get_size()
		for x in size.x:
			for y in size.y:
				buildings[pos + Vector2i(x, y)] = bld
		
		# 重建索引
		if bld.is_completed:
			var bld_data = bld.get_data()
			if bld_data:
				if bld_data.storage_capacity > 0:
					_completed_storage_index[bld.grid_pos] = bld
				if bld.building_id == "wooden_bed":
					_completed_bed_index[bld.grid_pos] = bld
