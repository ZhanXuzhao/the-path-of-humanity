# 游戏全局管理器 - Game Manager (Autoload)
# 管理游戏状态、时间、资源等全局数据
class_name GameManager
extends Node

signal day_changed(day: int)
signal time_changed(hour: float)
signal game_paused(is_paused: bool)
signal notification(msg: String, type: int)

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
}

func _ready():
	process_mode = PROCESS_MODE_ALWAYS

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
	var minutes = int((game_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

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

func show_notification(msg: String, type: NotificationType = NotificationType.INFO):
	notification.emit(msg, type)
