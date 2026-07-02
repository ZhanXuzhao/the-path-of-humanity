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

# 速度档位列表（从 GameConfig 加载）
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
	# 从 GameConfig 获取配置值
	var game_config = get_node("/root/GameConfig")
	day_length = game_config.day_length
	speed_levels = game_config.speed_levels.duplicate()
	_setup_autosave()

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
	
	# 更新时间（delta 已包含 Engine.time_scale 倍率）
	var time_delta = delta * (24.0 / day_length)
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
	Engine.time_scale = 1.0
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
	Engine.time_scale = time_speed

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

# 存档版本号 — 不兼容的版本存档将被删除
const SAVE_VERSION := 4
# 游戏版本号，仅供显示
const GAME_VERSION := "0.2.0"

# 加载存档时暂存的数据，供 Game 场景恢复
var _loaded_save_data: Dictionary = {}

func has_save_file() -> bool:
	return FileAccess.file_exists("user://savegame.dat")

func delete_save():
	"""删除存档文件"""
	if has_save_file():
		DirAccess.remove_absolute("user://savegame.dat")

func is_save_valid() -> bool:
	"""检查存档是否有效（版本匹配）"""
	var file = FileAccess.open("user://savegame.dat", FileAccess.READ)
	if not file:
		return false
	var data = file.get_var()
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var save_version = data.get("save_version", 0)
	return save_version == SAVE_VERSION

func save_game(silent: bool = false) -> bool:
	"""保存游戏（收集所有系统数据）"""
	var game = get_node_or_null("/root/Game")
	if not game:
		if not silent:
			show_notification("无法保存：未在游戏中", NotificationType.ERROR)
		return false
	
	var save_data = {
		"save_version": SAVE_VERSION,
		"game_version": GAME_VERSION,
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
		"designated_resources": game.designated_resources.duplicate(),
	}
	
	var file = FileAccess.open("user://savegame.dat", FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		if not silent:
			show_notification("游戏已保存", NotificationType.SUCCESS)
		return true
	else:
		if not silent:
			show_notification("保存失败！", NotificationType.ERROR)
		return false

func load_game(silent: bool = false) -> bool:
	"""读取存档（恢复 GameManager 状态，暂存系统数据）
	如果存档版本不兼容则自动删除，返回 false。
	"""
	var file = FileAccess.open("user://savegame.dat", FileAccess.READ)
	if not file:
		if not silent:
			show_notification("未找到存档", NotificationType.ERROR)
		return false
	
	var data = file.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		file.close()
		delete_save()
		if not silent:
			show_notification("存档数据损坏，已删除", NotificationType.ERROR)
		return false
	
	# 检查存档版本兼容性
	var save_version = data.get("save_version", 0)
	if save_version != SAVE_VERSION:
		file.close()
		delete_save()
		LogUtil.w("存档版本不兼容（存档v%d，当前v%d），已删除" % [save_version, SAVE_VERSION])
		if not silent:
			show_notification("存档版本不兼容，已删除，将开始新游戏", NotificationType.WARNING)
		return false
	
	# 恢复 GameManager 状态
	file.close()
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
