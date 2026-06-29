# 科技系统 - Tech/Research System
# 管理科技树、研究进度和解锁内容
extends Node
class_name TechSystem

signal research_started(tech_id: String)
signal research_completed(tech_id: String)
signal tech_unlocked(tech_id: String)

# 研究项目
class ResearchProject:
	var tech_id: String
	var progress: float = 0.0
	var assigned_settler_id: String = ""
	var research_points_per_sec: float = 1.0
	
	func get_data():
		return ItemDefinitions.get_tech(tech_id)
	
	func get_total_time() -> float:
		var data = get_data()
		if data == null:
			return 999.0
		return data.research_time
	
	func is_complete() -> bool:
		return progress >= get_total_time()

# 已研究的科技
var researched_techs: Array[String] = []
# 当前研究项目
var current_research: ResearchProject = null
# 已解锁的内容
var unlocked_buildings: Array[String] = []
var unlocked_recipes: Array[String] = []

func _ready():
	# 默认解锁基础内容
	_unlock_initial()

func _unlock_initial():
	# 初始解锁：帐篷、篝火、储物架、工作台
	unlocked_buildings.append("tent")
	unlocked_buildings.append("campfire")
	unlocked_buildings.append("storage_rack")
	unlocked_buildings.append("workbench")
	unlocked_buildings.append("road")

# -------- 研究管理 --------
func start_research(tech_id: String, settler_id: String = "") -> bool:
	"""开始研究一项科技"""
	if is_tech_researched(tech_id):
		return false
	
	var tech_data = ItemDefinitions.get_tech(tech_id)
	if tech_data == null or tech_data.id == "":
		return false
	
	# 检查前置科技
	for prereq in tech_data.prerequisites:
		if not researched_techs.has(prereq):
			return false
	
	var project := ResearchProject.new()
	project.tech_id = tech_id
	project.assigned_settler_id = settler_id
	current_research = project
	
	research_started.emit(tech_id)
	return true

func process_research(delta: float):
	"""处理研究进度"""
	if current_research == null:
		return
	
	current_research.progress += current_research.research_points_per_sec * delta
	
	if current_research.is_complete():
		_complete_research(current_research)

func _complete_research(project: ResearchProject):
	var tech_data = project.get_data()
	if tech_data == null:
		current_research = null
		return
	
	var tech_id = project.tech_id
	researched_techs.append(tech_id)
	
	# 解锁内容
	for unlock_id in tech_data.unlocks:
		# 判断是建筑还是配方
		if ItemDefinitions.buildings.has(unlock_id):
			unlocked_buildings.append(unlock_id)
		elif ItemDefinitions.recipes.has(unlock_id):
			unlocked_recipes.append(unlock_id)
	
	research_completed.emit(tech_id)
	tech_unlocked.emit(tech_id)
	current_research = null

# -------- 查询 --------
func is_tech_researched(tech_id: String) -> bool:
	return researched_techs.has(tech_id)

func is_building_unlocked(building_id: String) -> bool:
	return unlocked_buildings.has(building_id)

func is_recipe_unlocked(recipe_id: String) -> bool:
	return unlocked_recipes.has(recipe_id)

func can_research(tech_id: String) -> Dictionary:
	"""检查是否可以研究某项科技"""
	var tech_data = ItemDefinitions.get_tech(tech_id)
	if tech_data == null or tech_data.id == "":
		return {"can": false, "reason": "未知科技"}
	
	if is_tech_researched(tech_id):
		return {"can": false, "reason": "已研究"}
	
	if current_research != null:
		return {"can": false, "reason": "正在研究中"}
	
	for prereq in tech_data.prerequisites:
		if not is_tech_researched(prereq):
			return {"can": false, "reason": "需要前置科技: " + ItemDefinitions.get_tech(prereq).name}
	
	return {"can": true, "reason": ""}

func get_available_techs() -> Array:
	"""获取当前可研究的科技列表"""
	var available = []
	for tech_id in ItemDefinitions.techs:
		if can_research(tech_id).can:
			available.append(ItemDefinitions.techs[tech_id])
	return available

# -------- 序列化 --------
func to_dict() -> Dictionary:
	var data = {
		"researched": researched_techs.duplicate(),
		"unlocked_buildings": unlocked_buildings.duplicate(),
		"unlocked_recipes": unlocked_recipes.duplicate(),
	}
	if current_research:
		data["current_research"] = {
			"tech_id": current_research.tech_id,
			"progress": current_research.progress,
			"settler": current_research.assigned_settler_id,
		}
	return data

func from_dict(data: Dictionary):
	researched_techs = data.get("researched", [])
	unlocked_buildings = data.get("unlocked_buildings", [])
	unlocked_recipes = data.get("unlocked_recipes", [])
	
	if data.has("current_research"):
		var rd = data.current_research
		var project := ResearchProject.new()
		project.tech_id = rd.tech_id
		project.progress = rd.progress
		project.assigned_settler_id = rd.settler
		current_research = project
