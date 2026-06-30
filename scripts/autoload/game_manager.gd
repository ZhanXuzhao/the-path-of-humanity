# 游戏全局管理器 - Game Manager (Autoload)
# 管理游戏状态、时间、资源等全局数据
extends Node

signal day_changed(day: int)
signal time_changed(hour: float)
signal game_paused(is_paused: bool)
signal notification(msg: String, type: int)
# 资源池已移除，所有资源存在于：置物架、背包、地面

# 游戏状态枚举
enum GameState {
	MENU,       # 主菜单
	PLAYING,    # 游戏中
	PAUSED,     # 暂停
	GAME_OVER   # 游戏结束
}

enum NotificationType {
	INFO,       # 信息
	WARNING,    # 警告
	ERROR,      # 错误
	SUCCESS,    # 成功
	RESEARCH,   # 研究
	COMBAT      # 战斗
}

# 时间系统
var game_time: float = 6.0         # 当前时间（小时，从0开始）
var time_speed: float = 1.0        # 时间流逝速度
var day_length: float = 240.0      # 一天的长度（现实秒），默认240秒=4分钟(10现实秒=1游戏小时)
var current_day: int = 1           # 当前天数

# 游戏设置（从配置文件加载）
var settings: Dictionary = {}

# 速度档位列表（从配置文件加载）
var speed_levels: Array[float] = []

# 游戏状态
var state: GameState = GameState.MENU
var colony_name: String = "人类聚居地"

# 统计数据
var stats = {
	"total_settlers": 0,
	"max_settlers": 0,
	"total_built": 0,
	"total_crafted": 0,
	"total_researched": 0,
	"survival_days": 0,
}

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	_load_settings()
	_setup_autosave()

func _load_settings():
	"""从 res://resources/game_settings.cfg 加载游戏设置"""
	var cfg = ConfigFile.new()
	var err = cfg.load("res://resources/game_settings.cfg")
	if err != OK:
		push_error("无法加载游戏设置文件：", err)
		return
	
	# 时间设置
	day_length = cfg.get_value("time", "day_length", 240.0)
	
	# 相机设置
	settings["scroll_speed"] = cfg.get_value("camera", "scroll_speed", 300.0)
	settings["edge_scroll_margin"] = cfg.get_value("camera", "edge_scroll_margin", 20)
	
	# 定居者设置
	settings["carry_capacity"] = cfg.get_value("settler", "carry_capacity", 50.0)
	settings["base_move_speed"] = cfg.get_value("settler", "base_move_speed", 60.0)
	settings["dexterity_move_bonus"] = cfg.get_value("settler", "dexterity_move_bonus", 3.0)
	settings["base_hp"] = cfg.get_value("settler", "base_hp", 80.0)
	settings["constitution_hp_bonus"] = cfg.get_value("settler", "constitution_hp_bonus", 4.0)
	settings["hunger_decay_per_hour"] = cfg.get_value("settler", "hunger_decay_per_hour", 4.17)
	settings["rest_decay_per_hour"] = cfg.get_value("settler", "rest_decay_per_hour", 5.0)
	settings["comfort_decay_per_hour"] = cfg.get_value("settler", "comfort_decay_per_hour", 1.0)
	settings["social_decay_per_hour"] = cfg.get_value("settler", "social_decay_per_hour", 2.0)
	settings["safety_decay_per_hour"] = cfg.get_value("settler", "safety_decay_per_hour", 0.5)
	settings["food_restore_amount"] = cfg.get_value("settler", "food_restore_amount", 100.0)
	settings["sleep_restore_per_hour"] = cfg.get_value("settler", "sleep_restore_per_hour", 50.0)
	settings["sleep_min_time"] = cfg.get_value("settler", "sleep_min_time", 3.0)
	settings["storage_search_radius"] = cfg.get_value("settler", "storage_search_radius", 300.0)
	settings["food_search_radius"] = cfg.get_value("settler", "food_search_radius", 400.0)
	
	# 资源采集设置
	settings["harvest_amount"] = cfg.get_value("resources", "harvest_amount", 5.0)
	settings["harvest_count"] = cfg.get_value("resources", "harvest_count", 5)
	settings["resource_amount_multiplier"] = cfg.get_value("resources", "resource_amount_multiplier", 5.0)

	# 工作速度设置
	settings["work_speed_base"] = cfg.get_value("work_speed", "base_speed", 1.0)
	settings["work_speed_level_bonus"] = cfg.get_value("work_speed", "level_bonus", 0.1)

	# 工作优先级设置
	settings["mining_priority"] = cfg.get_value("work", "mining_priority", 2)
	settings["woodcutting_priority"] = cfg.get_value("work", "woodcutting_priority", 3)
	settings["construction_priority"] = cfg.get_value("work", "construction_priority", 4)
	settings["crafting_priority"] = cfg.get_value("work", "crafting_priority", 3)
	settings["cooking_priority"] = cfg.get_value("work", "cooking_priority", 2)
	settings["farming_priority"] = cfg.get_value("work", "farming_priority", 2)
	settings["hauling_priority"] = cfg.get_value("work", "hauling_priority", 1)
	settings["research_priority"] = cfg.get_value("work", "research_priority", 3)
	settings["combat_priority"] = cfg.get_value("work", "combat_priority", 1)
	
	# 速度档位
	speed_levels = []
	for v in cfg.get_value("speed", "levels", [0.5, 1.0, 2.0, 3.0, 5.0, 10.0]):
		speed_levels.append(float(v))
	
	# 建筑设置
	settings["storage_rack_capacity"] = cfg.get_value("building", "storage_rack_capacity", 1000)
	
	print("游戏设置已加载")

func _setup_autosave():
	# 每分钟自动存档计时器
	var timer = Timer.new()
	timer.name = "AutosaveTimer"
	timer.wait_time = 60.0
	timer.timeout.connect(_on_autosave)
	timer.one_shot = false
	add_child(timer)

func _on_autosave():
	if state == GameState.PLAYING:
		save_game(true)

func _process(delta):
	if state != GameState.PLAYING:
		return
	
	# 更新时间
	var time_delta = delta * time_speed * (24.0 / day_length)
	game_time += time_delta
	
	if game_time >= 24.0:
		game_time -= 24.0
		current_day += 1
		stats.survival_days = current_day
		day_changed.emit(current_day)
	
	time_changed.emit(game_time)

# -------- 游戏控制 --------
func start_game():
	state = GameState.PLAYING
	game_time = 6.0
	current_day = 1
	time_speed = 1.0
	# 重置统计数据
	stats = {
		"total_settlers": 0,
		"max_settlers": 0,
		"total_built": 0,
		"total_crafted": 0,
		"total_researched": 0,
		"survival_days": 0,
	}
	# 清除之前加载的存档数据，确保是全新游戏
	_loaded_save_data.clear()
	notification.emit("人类之路开启了！", NotificationType.SUCCESS)

func pause_game():
	state = GameState.PAUSED
	game_paused.emit(true)

func resume_game():
	state = GameState.PLAYING
	game_paused.emit(false)

func toggle_pause():
	if state == GameState.PLAYING:
		pause_game()
	elif state == GameState.PAUSED:
		resume_game()

func set_time_speed(speed: float):
	time_speed = clampf(speed, 0.0, 10.0)

# -------- 辅助方法 --------
func get_time_string() -> String:
	var hours = int(game_time)
	return "%02d时" % [hours]

func is_daytime() -> bool:
	return game_time >= 6.0 and game_time < 18.0

func get_daylight_factor() -> float:
	"""返回0-1的光照因子，用于光照调整"""
	if game_time >= 5.0 and game_time < 7.0:
		return (game_time - 5.0) / 2.0  # 日出
	elif game_time >= 7.0 and game_time < 17.0:
		return 1.0  # 白天
	elif game_time >= 17.0 and game_time < 19.0:
		return 1.0 - (game_time - 17.0) / 2.0  # 日落
	else:
		return 0.0  # 夜晚

# -------- 资源管理（已废弃） --------
# 资源池已移除，所有资源存在于：置物架、背包、地面
# 请使用 World/建筑库存/角色背包 来管理资源
func add_resource(_resource_id: String, _amount: int) -> int:
	push_warning("add_resource 已废弃：资源应存入置物架或掉落地面")
	return 0

func remove_resource(_resource_id: String, _amount: int) -> int:
	push_warning("remove_resource 已废弃：资源应从置物架/背包/地面取出")
	return 0

func has_resource(_resource_id: String, _amount: int = 1) -> bool:
	return false

func get_resource(_resource_id: String) -> int:
	return 0

func show_notification(msg: String, type: NotificationType = NotificationType.INFO):
	notification.emit(msg, type)

func _drop_legacy_resources_to_ground(old_resources: Dictionary):
	"""v1旧存档兼容：将旧版全局资源池的物品掉落在出生点附近地面"""
	var game = get_node_or_null("/root/Game")
	if game == null or game.world == null:
		return
	# 出生点附近(0,0)区块
	var drop_pos = Vector2i(8, 8)
	for res_id in old_resources:
		var amount = old_resources[res_id]
		if amount > 0:
			game.world.drop_item_on_ground(drop_pos, res_id, amount)
	if not old_resources.is_empty():
		show_notification("旧版存档资源已迁移到地面", NotificationType.INFO)

# ==================== 存档系统 ====================

# 加载存档时暂存的数据，供 Game 场景恢复
var _loaded_save_data: Dictionary = {}

func has_save_file() -> bool:
	return FileAccess.file_exists("user://savegame.dat")

func save_game(silent: bool = false) -> bool:
	"""保存游戏（收集所有系统数据）"""
	var game = get_node_or_null("/root/Game")
	if not game:
		if not silent:
			show_notification("无法保存：未在游戏中", NotificationType.ERROR)
		return false
	
	var save_data = {
		"version": 2,  # v2: 移除了全局资源池
		"game_time": game_time,
		"current_day": current_day,
		"time_speed": time_speed,
		"stats": stats.duplicate(),
		"world": game.world.to_dict() if game.world else {},
		"buildings": game.building_system.to_dict() if game.building_system else {},
		"tech": game.tech_system.to_dict() if game.tech_system else {},
		"crafting": game.crafting_system.to_dict() if game.crafting_system else {},
		"settlers": _serialize_settlers(game.settlers),
		"work_priorities": get_node_or_null("/root/WorkManager").to_dict() if get_node_or_null("/root/WorkManager") else {},
	}
	
	var file = FileAccess.open("user://savegame.dat", FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		if not silent:
			show_notification("游戏已保存", NotificationType.SUCCESS)
		return true
	else:
		if not silent:
			show_notification("保存失败！", NotificationType.ERROR)
		return false

func load_game(silent: bool = false) -> bool:
	"""读取存档（恢复 GameManager 状态，暂存系统数据）"""
	var file = FileAccess.open("user://savegame.dat", FileAccess.READ)
	if not file:
		if not silent:
			show_notification("未找到存档", NotificationType.ERROR)
		return false
	
	var data = file.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		if not silent:
			show_notification("存档数据损坏", NotificationType.ERROR)
		return false
	
	# 恢复 GameManager 状态
	game_time = data.get("game_time", 6.0)
	current_day = data.get("current_day", 1)
	time_speed = data.get("time_speed", 1.0)
	stats = data.get("stats", {})
	state = GameState.PLAYING
	LogUtil.i("存档已加载：第%d天，时间%.2f time speed: %.2f " % [current_day, game_time, time_speed])
	
	# 暂存系统数据供 Game 场景恢复
	_loaded_save_data = data
	
	if not silent:
		show_notification("存档已读取", NotificationType.SUCCESS)
	return true

static func _serialize_settlers(settler_list: Array) -> Array:
	var result = []
	for s in settler_list:
		if is_instance_valid(s):
			result.append(s.to_dict())
	return result
