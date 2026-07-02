# 制作系统 - Crafting System
# 管理物品制作、配方查询和生产队列
extends Node
class_name CraftingSystem

const ItemDefinitions = preload("res://resources/item_definitions.gd")

signal crafting_started(recipe_id: String, building_pos: Vector2i, settler_id: String)
signal crafting_completed(recipe_id: String, building_pos: Vector2i)
signal crafting_queue_changed(building_pos: Vector2i)

# 生产队列项目
class CraftingJob:
	var recipe_id: String
	var building_pos: Vector2i
	var assigned_settler_id: String
	var progress: float = 0.0
	var is_active: bool = false
	var repeat: bool = false
	
	func get_recipe():
		return ItemDefinitions.get_recipe(recipe_id)
	
	func _init(recipe: String, pos: Vector2i, settler: String = ""):
		recipe_id = recipe
		building_pos = pos
		assigned_settler_id = settler

# 每个建筑的生产队列
var crafting_queues: Dictionary = {}  # Vector2i(建筑主格子) -> Array[CraftingJob]
var active_jobs: Array[CraftingJob] = []

# -------- 队列管理 --------
func get_or_create_queue(pos: Vector2i) -> Array:
	if not crafting_queues.has(pos):
		crafting_queues[pos] = []
	return crafting_queues[pos]

func add_to_queue(recipe_id: String, building_pos: Vector2i, 
		settler_id: String = "", repeat: bool = false) -> bool:
	"""添加制作任务到队列"""
	var recipe = ItemDefinitions.get_recipe(recipe_id)
	if recipe == null or recipe.id == "":
		return false
	
	var queue = get_or_create_queue(building_pos)
	var job := CraftingJob.new(recipe_id, building_pos, settler_id)
	job.repeat = repeat
	queue.append(job)
	
	crafting_queue_changed.emit(building_pos)
	_try_start_next_job(building_pos)
	return true

func remove_from_queue(building_pos: Vector2i, index: int) -> bool:
	var queue = get_or_create_queue(building_pos)
	if index < 0 or index >= queue.size():
		return false
	queue.remove_at(index)
	crafting_queue_changed.emit(building_pos)
	return true

func clear_queue(building_pos: Vector2i):
	crafting_queues[building_pos] = []
	crafting_queue_changed.emit(building_pos)

func _try_start_next_job(building_pos: Vector2i):
	"""尝试开始队列中的下一个任务"""
	var queue = get_or_create_queue(building_pos)
	for job in queue:
		if not job.is_active:
			job.is_active = true
			active_jobs.append(job)
			crafting_started.emit(job.recipe_id, building_pos, job.assigned_settler_id)
			return

# -------- 制作进度 --------
func process_crafting(delta: float):
	"""处理所有活跃的制作任务"""
	for i in range(active_jobs.size() - 1, -1, -1):
		var job = active_jobs[i]
		var recipe = job.get_recipe()
		if recipe == null:
			active_jobs.remove_at(i)
			continue
		
		job.progress += delta
		if job.progress >= recipe.work_time:
			complete_crafting(job, recipe)
			active_jobs.remove_at(i)

func complete_crafting(job, _recipe):
	"""完成制作（由定居者AI或系统调用）"""
	# 输出物品 - 放入建筑库存或掉落
	crafting_completed.emit(job.recipe_id, job.building_pos)

# -------- 可用配方查询 --------
func get_pending_crafting_jobs() -> Array:
	"""获取所有尚未分配定居者的活跃制作任务"""
	var jobs: Array = []
	for pos in crafting_queues:
		var queue = crafting_queues[pos]
		for job in queue:
			if job.is_active and job.assigned_settler_id == "":
				jobs.append(job)
	return jobs

func is_building_occupied(building_pos: Vector2i) -> bool:
	"""检查指定建筑是否已有定居者在工作"""
	var queue = crafting_queues.get(building_pos)
	if queue == null:
		return false
	for job in queue:
		if job.is_active and job.assigned_settler_id != "":
			return true
	return false

func get_available_recipes(building_id: String, researched_techs: Array) -> Array:
	"""获取建筑可用的已解锁配方"""
	var all_recipes = ItemDefinitions.get_recipes_for_building(building_id)
	var available = []
	
	for recipe in all_recipes:
		if recipe.required_tech == "" or researched_techs.has(recipe.required_tech):
			available.append(recipe)
	
	return available

func auto_queue_production_for_item(item_id: String, needed: int) -> bool:
	"""自动为缺失的施工材料排队生产任务。返回是否有配方被成功排队。"""
	var producers = _find_recipes_producing(item_id)
	if producers.is_empty():
		return false

	for producer in producers:
		var produced_per_run = producer.outputs.get(item_id, 0)
		if produced_per_run <= 0:
			continue
		var runs = int(ceil(float(needed) / produced_per_run))

		var target_bld = _find_best_building_for_recipe(producer.id)
		if target_bld == null:
			continue

		add_with_prerequisites(producer.id, target_bld.grid_pos)

		for i in range(runs):
			add_to_queue(producer.id, target_bld.grid_pos)

		return true

	return false

# -------- 连锁制作（自动补齐中间材料） --------
func add_with_prerequisites(recipe_id: String, building_pos: Vector2i,
		visited: Dictionary = {}) -> bool:
	"""添加制作任务，自动补齐缺失的中间材料"""
	if visited.is_empty():
		visited = {}
	if visited.has(recipe_id):
		return false
	visited[recipe_id] = true

	var recipe = ItemDefinitions.get_recipe(recipe_id)
	if recipe == null or recipe.id == "":
		return false

	for item_id in recipe.inputs:
		var needed = recipe.inputs[item_id]
		var available = _count_item_globally(item_id)

		if available < needed:
			var deficit = needed - available
			var producers = _find_recipes_producing(item_id)
			for producer in producers:
				if visited.has(producer.id):
					continue
				var produced_per_run = producer.outputs.get(item_id, 0)
				if produced_per_run <= 0:
					continue

				var runs = int(ceil(float(deficit) / produced_per_run))

				var target_bld = _find_best_building_for_recipe(producer.id)
				if target_bld == null:
					continue

				add_with_prerequisites(producer.id, target_bld.grid_pos, visited)

				for i in range(runs):
					add_to_queue(producer.id, target_bld.grid_pos)

				break

	add_to_queue(recipe_id, building_pos)
	return true

func _count_item_globally(item_id: String) -> int:
	"""统计全地图某物品总数（存储建筑 + 地面 + 定居者背包）"""
	var total = 0
	var game = _get_game()
	if game == null:
		return 0

	if game.building_system:
		total += game.building_system.count_item_in_storage(item_id)

	if game.world:
		total += game.world.count_ground_item(item_id)

	for s in game.settlers:
		if is_instance_valid(s) and s.inventory:
			total += s.inventory.get_item_count(item_id)

	return total

func _find_recipes_producing(item_id: String) -> Array:
	"""查找所有能产出指定物品的配方"""
	var result: Array = []
	for r in ItemDefinitions.recipes.values():
		if r.outputs.has(item_id) and r.outputs[item_id] > 0:
			result.append(r)
	return result

func _find_best_building_for_recipe(recipe_id: String):
	"""为指定配方找到最合适的已完成建筑（队列最短的）"""
	var recipe = ItemDefinitions.get_recipe(recipe_id)
	if recipe == null or recipe.id == "":
		return null
	var game = _get_game()
	if game == null or game.building_system == null:
		return null
	var all_blds = game.building_system.get_buildings_by_type(recipe.crafted_at)
	var best = null
	var best_queue_len = 999999
	for bld in all_blds:
		if not bld.is_completed:
			continue
		var queue_len = 0
		if crafting_queues.has(bld.grid_pos):
			queue_len = crafting_queues[bld.grid_pos].size()
		if queue_len < best_queue_len:
			best_queue_len = queue_len
			best = bld
	return best

func _get_game():
	return Engine.get_main_loop().root.get_node_or_null("/root/Game")

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var data = {}
	for pos in crafting_queues:
		var key = "%d,%d" % [pos.x, pos.y]
		var queue_data = []
		for job in crafting_queues[pos]:
			queue_data.append({
				"recipe": job.recipe_id,
				"settler": job.assigned_settler_id,
				"progress": job.progress,
				"active": job.is_active,
				"repeat": job.repeat
			})
		data[key] = queue_data
	return data

func from_dict(data: Dictionary):
	crafting_queues.clear()
	active_jobs.clear()
	for key in data:
		var parts = key.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		var queue_data = data[key]
		var queue: Array[CraftingJob] = []
		for j_data in queue_data:
			var job := CraftingJob.new(j_data.recipe, pos, j_data.settler)
			job.progress = j_data.progress
			job.is_active = j_data.active
			job.repeat = j_data.repeat
			queue.append(job)
			if job.is_active:
				active_jobs.append(job)
		crafting_queues[pos] = queue
