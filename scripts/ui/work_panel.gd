# 工作优先级面板 - Work Panel
# 类似 RimWorld 的工作标签页，设置每个定居者的工作优先级
extends Panel
class_name WorkPanel

const WorkManagerScript = preload("res://scripts/autoload/work_manager.gd")

@onready var work_grid: GridContainer = $ScrollContainer/WorkGrid
@onready var close_btn: Button = $TitleBar/CloseBtn
@onready var reset_all_btn: Button = $BottomBar/ResetAllBtn

var _work_manager
var _settler_priority_btns: Dictionary = {}  # settler_id -> { work_type -> Button }
var _header_labels: Array = []

# 优先级颜色（数字越大优先级越高）
const PRIORITY_COLORS = {
	0: Color(0.35, 0.35, 0.35),  # 禁用 - 灰色
	1: Color(1.0, 0.5, 0.2),     # 最低 - 橙色
	2: Color(1.0, 1.0, 0.2),     # 低 - 黄色
	3: Color(0.3, 1.0, 0.3),     # 中 - 绿色
	4: Color(0.2, 0.8, 1.0),     # 最高 - 青色
}

const PRIORITY_LABELS = {
	0: "",
	1: "1",
	2: "2",
	3: "3",
	4: "4",
}

func _ready():
	_work_manager = get_node("/root/WorkManager")
	
	close_btn.pressed.connect(func(): visible = false)
	reset_all_btn.pressed.connect(_on_reset_all)
	
	# 监听工作优先级变化
	_work_manager.work_priorities_changed.connect(_on_priorities_changed)
	
	# 监听定居者变化
	var game = get_node_or_null("/root/Game")
	if game:
		game.settler_selected.connect(_refresh)
	
	visible = false

func _refresh(_unused = null):
	"""刷新整个面板"""
	_rebuild_grid()

func _rebuild_grid():
	"""重建工作优先级表格"""
	# 清空网格
	for child in work_grid.get_children():
		child.queue_free()
	_settler_priority_btns.clear()
	_header_labels.clear()
	
	var game = get_node_or_null("/root/Game")
	if not game:
		return
	
	var settlers = game.settlers
	if settlers.is_empty():
		var empty_label = Label.new()
		empty_label.text = "  没有定居者"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		work_grid.add_child(empty_label)
		return
	
	# 第一行：左上角空白 + 工作类型列标题
	var corner_label = Label.new()
	corner_label.text = "  角色 \\ 工作"
	corner_label.custom_minimum_size = Vector2(120, 28)
	corner_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	corner_label.add_theme_constant_override("minimum_font_size", 12)
	work_grid.add_child(corner_label)
	
	# 添加每个工作类型的列标题
	for wt in WorkManager.ALL_WORK_TYPES:
		var header = Button.new()
		header.text = WorkManager.WORK_TYPE_NAMES.get(wt, "?")
		header.custom_minimum_size = Vector2(72, 28)
		header.disabled = true
		header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		header.add_theme_constant_override("minimum_font_size", 11)
		work_grid.add_child(header)
	
	# 每行：定居者名称 + 各工作类型的优先级按钮
	for s in settlers:
		if not is_instance_valid(s):
			continue
		
		var sid = s.settler_id
		_work_manager.init_settler(sid)
		
		# 初始化该定居者的按钮字典
		if not _settler_priority_btns.has(sid):
			_settler_priority_btns[sid] = {}
		
		# 定居者名称
		var name_label = Label.new()
		name_label.text = "  " + s.settler_name
		name_label.custom_minimum_size = Vector2(120, 30)
		name_label.add_theme_constant_override("minimum_font_size", 12)
		# 如果选中了此定居者，高亮名字
		if game.selected_settler == s:
			name_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		work_grid.add_child(name_label)
		
		# 该定居者的优先级
		var priorities = _work_manager.get_all_priorities(sid)
		
		for wt in WorkManager.ALL_WORK_TYPES:
			var pri = priorities.get(wt, 0)
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(72, 30)
			btn.text = PRIORITY_LABELS.get(pri, "")
			btn.add_theme_color_override("font_color", PRIORITY_COLORS.get(pri, Color.WHITE))
			btn.add_theme_constant_override("minimum_font_size", 13)
			btn.tooltip_text = WorkManager.WORK_TYPE_NAMES.get(wt, "?")
			
			# 左键增加优先级，右键减少优先级
			var work_type = wt
			var settler_id = sid
			btn.pressed.connect(_on_left_click.bind(sid, work_type, btn))
			btn.gui_input.connect(_on_priority_btn_gui_input.bind(sid, work_type, btn))
			
			work_grid.add_child(btn)
			_settler_priority_btns[sid][wt] = btn

func _on_left_click(settler_id: String, work_type: int, btn: Button):
	"""左键增加优先级 (0->1->2->3->4->4)"""
	var current = _work_manager.get_priority(settler_id, work_type)
	var next_pri = mini(current + 1, 4)
	_work_manager.set_priority(settler_id, work_type, next_pri)
	_update_btn_visual(btn, next_pri)

func _on_priority_btn_gui_input(event: InputEvent, settler_id: String, work_type: int, btn: Button):
	"""右键减少优先级 (4->3->2->1->0->0)"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var current = _work_manager.get_priority(settler_id, work_type)
		var next_pri = maxi(current - 1, 0)
		_work_manager.set_priority(settler_id, work_type, next_pri)
		_update_btn_visual(btn, next_pri)
		get_viewport().set_input_as_handled()

func _update_btn_visual(btn: Button, priority: int):
	"""更新按钮的显示和颜色"""
	btn.text = PRIORITY_LABELS.get(priority, "")
	btn.add_theme_color_override("font_color", PRIORITY_COLORS.get(priority, Color.WHITE))

func _on_priorities_changed(_settler_id: String):
	"""当优先级变更时刷新显示"""
	# 不需要完全重建，只更新视觉
	for sid in _settler_priority_btns:
		var priorities = _work_manager.get_all_priorities(sid)
		for wt in WorkManager.ALL_WORK_TYPES:
			if _settler_priority_btns[sid].has(wt):
				var btn = _settler_priority_btns[sid][wt]
				var pri = priorities.get(wt, 0)
				_update_btn_visual(btn, pri)

func _on_reset_all():
	"""重置所有定居者的优先级为默认值"""
	if _work_manager:
		_work_manager.reset_all()
		_rebuild_grid()

func _process(_delta):
	# 面板显示时定时刷新定居者列表（检测新定居者加入）
	if visible and Engine.get_physics_frames() % 120 == 0:
		_check_settler_changes()

func _check_settler_changes():
	"""检查定居者列表是否有变化，有则重建网格"""
	var game = get_node_or_null("/root/Game")
	if not game:
		return
	
	var current_count = 0
	for s in game.settlers:
		if is_instance_valid(s):
			current_count += 1
	
	# 简单的计数检查，不精确但足够
	var grid_count = 0
	for child in work_grid.get_children():
		if child is Button or child is Label:
			grid_count += 1
	
	# 每行有 1(名字) + 9(工作类型) = 10 个控件，减去标题行
	var expected_rows = (grid_count - 10) / 10 + 1 if grid_count >= 10 else 0
	if expected_rows != current_count:
		_rebuild_grid()
