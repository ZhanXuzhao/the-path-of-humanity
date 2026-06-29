# 库存系统 - Inventory System
# 管理物品的存储、转移（按物品种类记录总数，不区分堆叠）
class_name Inventory
extends RefCounted

const ItemDefinitions = preload("res://resources/item_definitions.gd")

signal items_changed

var items: Dictionary = {}  # item_id -> total_amount，每种物品只占一条

# 容量上限（0 = 无限制）
var capacity: int = 0

func _init():
	pass

# -------- 添加物品 --------
func add_item(item_id: String, amount: int = 1) -> int:
	"""添加物品，返回未添加的剩余数量"""
	if amount <= 0:
		return 0
	
	var item_def = ItemDefinitions.get_item(item_id)
	if item_def == null or item_def.id == "":
		return amount
	
	# 容量检查
	if capacity > 0:
		var current = get_total_items()
		var space = capacity - current
		if space <= 0:
			return amount  # 已满，全部退回
		amount = mini(amount, space)
	
	items[item_id] = items.get(item_id, 0) + amount
	emit_signal("items_changed")
	return 0

func remove_item(item_id: String, amount: int = 1) -> int:
	"""移除物品，返回实际移除的数量"""
	if not items.has(item_id) or items[item_id] <= 0:
		return 0
	
	var available = items[item_id]
	var to_remove = mini(available, amount)
	items[item_id] = available - to_remove
	if items[item_id] <= 0:
		items.erase(item_id)
	
	emit_signal("items_changed")
	return to_remove

# -------- 查询 --------
func has_item(item_id: String, amount: int = 1) -> bool:
	return items.get(item_id, 0) >= amount

func get_item_count(item_id: String) -> int:
	return items.get(item_id, 0)

func get_total_items() -> int:
	var total = 0
	for amt in items.values():
		total += amt
	return total

func is_empty() -> bool:
	return items.is_empty()

func is_full() -> bool:
	return capacity > 0 and get_total_items() >= capacity

func clear():
	items.clear()
	emit_signal("items_changed")

# -------- 序列化 --------
func to_dict() -> Dictionary:
	return {
		"items": items.duplicate(),
	}

func from_dict(data: Dictionary):
	items.clear()
	var raw_items = data.get("items", {})
	if raw_items is Array:
		# 兼容旧存档：items 为 [{id, amount}, ...] 格式
		for entry in raw_items:
			var item_id = entry.get("id", "")
			var amt = entry.get("amount", 0)
			if item_id != "" and amt > 0:
				items[item_id] = items.get(item_id, 0) + amt
	else:
		# 新存档：items 为 {item_id: amount, ...} 格式
		for item_id in raw_items:
			var amt = raw_items[item_id]
			if amt > 0:
				items[item_id] = amt
