# 日志工具类 - LogUtil (Autoload 单例)
# 提供统一的日志输出，默认只打印选中角色的信息
# 用法: LogUtil.info(settler, "消息")  或  LogUtil.info(null, "全局消息", true)

extends Node

# 日志级别
enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR,
}

# 是否强制打印所有日志（调试用）
var verbose: bool = false

func _should_log(settler = null, force: bool = false) -> bool:
	if force or verbose:
		return true
	if settler == null:
		return false
	if "is_selected" in settler:
		return settler.is_selected
	return false

func _get_time_str() -> String:
	"""返回现实时间字符串，格式 HH:MM:SS"""
	var dt = Time.get_datetime_dict_from_system()
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

func _format_message(settler, level: Level, message: String) -> String:
	var prefix = ""
	match level:
		Level.DEBUG: prefix = "[D]"
		Level.INFO:  prefix = "[I]"
		Level.WARN:  prefix = "[W]"
		Level.ERROR: prefix = "[E]"
	
	var time_str = _get_time_str()
	var name_str = ""
	if settler != null and "settler_name" in settler:
		name_str = settler.settler_name
	
	if name_str != "":
		return "%s [%s] [%s] %s" % [prefix, time_str, name_str, message]
	else:
		return "%s [%s] %s" % [prefix, time_str, message]

# @param settler:  定居者对象，非 null 且选中时才会打印；传 null 且 force=false 则静默
# @param message:  日志文本
# @param force:    true 时无视 settler 选择状态强制打印
func debug(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.DEBUG, message))

# @param settler:  定居者对象，非 null 且选中时才会打印；传 null 且 force=false 则静默
# @param message:  日志文本
# @param force:    true 时无视 settler 选择状态强制打印
func info(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.INFO, message))

# @param settler:  定居者对象，非 null 且选中时才会打印；传 null 且 force=false 则静默
# @param message:  日志文本
# @param force:    true 时无视 settler 选择状态强制打印
func warn(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.WARN, message))

# @param settler:  定居者对象，非 null 且选中时才会打印；传 null 且 force=false 则静默
# @param message:  日志文本
# @param force:    true 时无视 settler 选择状态强制打印
func error(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.ERROR, message))

# -------- 无需 settler 参数的快捷方法 --------
# @param message:  日志文本
func d(message: String):
	debug(null, message, true)

# @param message:  日志文本
func i(message: String):
	info(null, message, true)

# @param message:  日志文本
func w(message: String):
	warn(null, message, true)

# @param message:  日志文本
func e(message: String):
	error(null, message, true)
