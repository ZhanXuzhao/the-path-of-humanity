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

func _format_message(settler, level: Level, message: String) -> String:
	var prefix = ""
	match level:
		Level.DEBUG: prefix = "[D]"
		Level.INFO:  prefix = "[I]"
		Level.WARN:  prefix = "[W]"
		Level.ERROR: prefix = "[E]"
	
	var name_str = ""
	if settler != null and "settler_name" in settler:
		name_str = settler.settler_name
	
	if name_str != "":
		return "%s [%s] %s" % [prefix, name_str, message]
	else:
		return "%s %s" % [prefix, message]

func debug(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.DEBUG, message))

func info(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.INFO, message))

func warn(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.WARN, message))

func error(settler, message: String, force: bool = false):
	if not _should_log(settler, force): return
	print(_format_message(settler, Level.ERROR, message))
