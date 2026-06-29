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
	var inventory = null
	var assigned_settlers: Array[String] = []  # settler IDs
	
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
	
	func _init(id: String, pos: Vector2i):
		building_id = id
		grid_pos = pos
		var data = get_data()
		if data != null:
			hp = data.hp
			max_hp = data.hp
			if data.storage_capacity > 0:
				inventory = Inventory.new(20, data.storage_capacity)

# 所有建筑实例
var buildings: Dictionary = {}  # Vector2i -> BuildingInstance
var world = null

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
			
			# 检查是否在地图范围内
			if check_pos.x < 0 or check_pos.y < 0:
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
	
	bld.construction_progress += amount
	var data = bld.get_data()
	
	# 发射进度更新信号（供渲染器更新进度条）
	if data != null:
		construction_progress_updated.emit(bld.grid_pos, bld.construction_progress, data.work_cost)
	
	if data != null and bld.construction_progress >= data.work_cost:
		bld.is_completed = true
		bld.hp = data.hp
		building_completed.emit(bld.grid_pos)
		return true
	return false

func is_completed(pos: Vector2i) -> bool:
	var bld = get_building_at(pos)
	return bld != null and bld.is_completed

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
				"inventory": bld.inventory.to_dict() if bld.inventory else null
			}
	return data

func from_dict(data: Dictionary):
	buildings.clear()
	for key in data:
		var b_data = data[key]
		var pos = Vector2i(b_data.pos.x, b_data.pos.y)
		var bld := BuildingInstance.new(b_data.id, pos)
		bld.hp = b_data.hp
		bld.max_hp = b_data.max_hp
		bld.construction_progress = b_data.progress
		bld.is_completed = b_data.completed
		bld.production_timer = b_data.prod_timer
		if b_data.inventory != null and bld.inventory != null:
			bld.inventory.from_dict(b_data.inventory)
		
		# 重新注册所有格子
		var size = bld.get_size()
		for x in size.x:
			for y in size.y:
				buildings[pos + Vector2i(x, y)] = bld
