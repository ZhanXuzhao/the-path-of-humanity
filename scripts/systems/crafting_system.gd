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
			if job.assigned_settler_id != "":
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
			_complete_crafting(job, recipe)
			active_jobs.remove_at(i)

func _complete_crafting(job, _recipe):
	"""完成制作"""
	# 输出物品 - 放入建筑库存或掉落
	crafting_completed.emit(job.recipe_id, job.building_pos)

# -------- 可用配方查询 --------
func get_available_recipes(building_id: String, researched_techs: Array) -> Array:
	"""获取建筑可用的已解锁配方"""
	var all_recipes = ItemDefinitions.get_recipes_for_building(building_id)
	var available = []
	
	for recipe in all_recipes:
		if recipe.required_tech == "" or researched_techs.has(recipe.required_tech):
			available.append(recipe)
	
	return available

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
