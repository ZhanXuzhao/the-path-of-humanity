# 游戏全局管理器 - Game Manager (Autoload)
# 管理游戏状态、时间、资源等全局数据
extends Node

signal day_changed(day: int)
signal time_changed(hour: float)
signal game_paused(is_paused: bool)
signal notification(msg: String, type: int)
signal resources_changed(resource_id: String, old_amount: int, new_amount: int)

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
var day_length: float = 24.0       # 一天的长度（现实秒）
var current_day: int = 1           # 当前天数

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
var resources = {
	"wood": 0,
	"stone": 0,
	"food": 0,
	"iron_ore": 0,
	"copper_ore": 0,
	"coal": 0,
	"iron_ingot": 0,
	"copper_ingot": 0,
	"plank": 0,
	"brick": 0,
	"berry": 0,
	"raw_meat": 0,
	"cooked_meat": 0,
	"cloth": 0,
}

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	_setup_autosave()
	# 窗口关闭时自动保存
	get_tree().root.close_requested.connect(_on_close_requested)

func _on_close_requested():
	save_game(true)
	get_tree().quit()

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
	stats.survival_days = 0
	# 重置资源
	resources = {
		"wood": 0,
		"stone": 0,
		"food": 0,
		"iron_ore": 0,
		"copper_ore": 0,
		"coal": 0,
		"iron_ingot": 0,
		"copper_ingot": 0,
		"plank": 0,
		"brick": 0,
		"berry": 0,
		"raw_meat": 0,
		"cooked_meat": 0,
		"cloth": 0,
	}
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

# -------- 资源管理 --------
func add_resource(resource_id: String, amount: int) -> int:
	"""添加资源，返回实际添加数量"""
	if amount <= 0:
		return 0
	var old = resources.get(resource_id, 0)
	resources[resource_id] = old + amount
	resources_changed.emit(resource_id, old, resources[resource_id])
	return amount

func remove_resource(resource_id: String, amount: int) -> int:
	"""移除资源，返回实际移除数量"""
	if amount <= 0:
		return 0
	var old = resources.get(resource_id, 0)
	var actual = min(old, amount)
	resources[resource_id] = old - actual
	resources_changed.emit(resource_id, old, resources[resource_id])
	return actual

func has_resource(resource_id: String, amount: int = 1) -> bool:
	return resources.get(resource_id, 0) >= amount

func get_resource(resource_id: String) -> int:
	return resources.get(resource_id, 0)

func show_notification(msg: String, type: NotificationType = NotificationType.INFO):
	notification.emit(msg, type)

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
		"version": 1,
		"game_time": game_time,
		"current_day": current_day,
		"time_speed": time_speed,
		"resources": resources.duplicate(),
		"stats": stats.duplicate(),
		"world": game.world.to_dict() if game.world else {},
		"buildings": game.building_system.to_dict() if game.building_system else {},
		"tech": game.tech_system.to_dict() if game.tech_system else {},
		"crafting": game.crafting_system.to_dict() if game.crafting_system else {},
		"settlers": _serialize_settlers(game.settlers),
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
	resources = data.get("resources", {})
	stats = data.get("stats", {})
	state = GameState.PLAYING
	
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
