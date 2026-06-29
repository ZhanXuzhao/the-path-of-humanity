# 库存系统 - Inventory System
# 管理物品的存储、堆叠、转移
class_name Inventory
extends RefCounted

const ItemDefinitions = preload("res://resources/item_definitions.gd")

var items: Array[ItemStack] = []  # 库存中的物品堆
var max_slots: int = 30           # 最大格子数
var capacity: int = 0             # 最大容量 (0=不限)

# 物品堆结构
class ItemStack:
	var item_id: String
	var amount: int
	
	func _init(id: String, amt: int = 1):
		item_id = id
		amount = amt
	
	func get_data():
		return ItemDefinitions.get_item(item_id)
	
	func is_full() -> bool:
		var data = get_data()
		if data == null:
			return true
		return amount >= data.max_stack
	
	func can_add(_amt: int = 1) -> int:
		var data = get_data()
		if data == null:
			return 0
		return data.max_stack - amount
	
	func add(amt: int) -> int:
		var data = get_data()
		if data == null:
			return amt
		var can_add_amt = data.max_stack - amount
		var to_add = min(can_add_amt, amt)
		amount += to_add
		return amt - to_add  # 返回剩余未添加的数量

func _init(slots: int = 30, cap: int = 0):
	max_slots = slots
	capacity = cap

# -------- 添加物品 --------
func add_item(item_id: String, amount: int = 1) -> int:
	"""添加物品，返回未添加的剩余数量"""
	if amount <= 0:
		return 0
	
	var item_def = ItemDefinitions.get_item(item_id)
	if item_def == null or item_def.id == "":
		return amount
	
	var remaining = amount
	
	# 先尝试堆叠到现有的同类型物品堆
	for stack in items:
		if stack.item_id == item_id and not stack.is_full():
			remaining = stack.add(remaining)
			if remaining <= 0:
				emit_signal("items_changed")
				return 0
	
	# 如果还有剩余，创建新堆叠
	while remaining > 0 and items.size() < max_slots:
		var new_stack := ItemStack.new(item_id)
		remaining = new_stack.add(remaining)
		items.append(new_stack)
	
	emit_signal("items_changed")
	return remaining

func remove_item(item_id: String, amount: int = 1) -> int:
	"""移除物品，返回实际移除的数量"""
	var removed = 0
	for i in range(items.size() - 1, -1, -1):
		if items[i].item_id == item_id:
			var stack = items[i]
			var to_remove = min(stack.amount, amount - removed)
			stack.amount -= to_remove
			removed += to_remove
			if stack.amount <= 0:
				items.remove_at(i)
			if removed >= amount:
				break
	
	if removed > 0:
		emit_signal("items_changed")
	return removed

# -------- 查询 --------
func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount

func get_item_count(item_id: String) -> int:
	var total = 0
	for stack in items:
		if stack.item_id == item_id:
			total += stack.amount
	return total

func get_total_items() -> int:
	var total = 0
	for stack in items:
		total += stack.amount
	return total

func is_empty() -> bool:
	return items.is_empty()

func is_full() -> bool:
	if capacity > 0 and get_total_items() >= capacity:
		return true
	return items.size() >= max_slots

func clear():
	items.clear()
	emit_signal("items_changed")

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var data = {
		"max_slots": max_slots,
		"capacity": capacity,
		"items": []
	}
	for stack in items:
		data.items.append({
			"id": stack.item_id,
			"amount": stack.amount
		})
	return data

func from_dict(data: Dictionary):
	max_slots = data.get("max_slots", 30)
	capacity = data.get("capacity", 0)
	items.clear()
	for item_data in data.get("items", []):
		var stack := ItemStack.new(item_data.id, item_data.amount)
		items.append(stack)
