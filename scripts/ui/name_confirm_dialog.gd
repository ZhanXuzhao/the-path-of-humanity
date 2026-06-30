# 角色名确认对话框 - Name Confirmation Dialog
# 新建游戏时显示，让玩家逐一确认初始定居者的姓名
extends Control

signal confirmed(name_list: Array)  # 玩家确认后发射，传入最终姓名列表
signal cancelled()                   # 玩家取消

# 每位定居者的UI控件组
class NameSlot:
	var panel: Panel
	var name_label: Label
	var gender_label: Label
	var reroll_btn: Button
	var index: int
	var name: String
	var is_male: bool

var _name_slots: Array[NameSlot] = []
var _settler_count: int = 3

@onready var container: VBoxContainer = $MarginContainer/VBox/ScrollContainer/SlotsContainer
@onready var confirm_btn: Button = $MarginContainer/VBox/ConfirmBtn
@onready var reroll_all_btn: Button = $MarginContainer/VBox/RerollAllBtn
@onready var title_label: Label = $MarginContainer/VBox/TitleLabel

func _ready():
	# 连接按钮
	confirm_btn.pressed.connect(_on_confirm)
	reroll_all_btn.pressed.connect(_on_reroll_all)

func setup(count: int = 3):
	_settler_count = count
	# 清除旧的控件
	for child in container.get_children():
		child.queue_free()
	_name_slots.clear()
	
	# 初始姓名列表（用于去重）
	var used_names: Array = []
	
	for i in range(count):
		var slot = _create_name_slot(i, used_names)
		_name_slots.append(slot)
		container.add_child(slot.panel)
	
	# 更新确认按钮状态
	_update_confirm_button()

func _create_name_slot(index: int, used_names: Array) -> NameSlot:
	var slot = NameSlot.new()
	slot.index = index
	
	# 生成角色名字（男女交替以提高多样性）
	var is_male = (index % 2 == 0)
	slot.is_male = is_male
	slot.name = _generate_name(is_male, used_names)
	used_names.append(slot.name)
	
	# 创建面板
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(400, 60)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var hbox = HBoxContainer.new()
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)
	
	# 序号标签
	var idx_label = Label.new()
	idx_label.text = "成员%d" % (index + 1)
	idx_label.custom_minimum_size = Vector2(60, 40)
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idx_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	idx_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(idx_label)
	
	# 性别标签
	var gender_label = Label.new()
	gender_label.text = "♂" if is_male else "♀"
	gender_label.custom_minimum_size = Vector2(30, 40)
	gender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gender_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gender_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(gender_label)
	slot.gender_label = gender_label
	
	# 名字标签
	var name_label = Label.new()
	name_label.text = slot.name
	name_label.custom_minimum_size = Vector2(120, 40)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	hbox.add_child(name_label)
	slot.name_label = name_label
	
	# 弹性空间
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	
	# 重新随机按钮
	var reroll_btn = Button.new()
	reroll_btn.text = "重新随机"
	reroll_btn.custom_minimum_size = Vector2(100, 36)
	reroll_btn.pressed.connect(_on_reroll_single.bind(index))
	hbox.add_child(reroll_btn)
	slot.reroll_btn = reroll_btn
	
	slot.panel = panel
	return slot

func _generate_name(is_male: bool, used_names: Array) -> String:
	# 复用Settler的静态方法生成不重复名字
	var surname = _get_random_surname()
	var given_name = _get_random_given_name(is_male)
	var full_name = surname + given_name
	
	# 去重：最多尝试50次
	var attempts = 0
	while full_name in used_names and attempts < 50:
		surname = _get_random_surname()
		given_name = _get_random_given_name(is_male)
		full_name = surname + given_name
		attempts += 1
	
	return full_name

# 姓氏池
const SURNAMES = [
	"李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "马", "胡", "朱", "郭", "何", "罗", "高", "林",
	"梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
	"程", "曹", "袁", "邓", "许", "傅", "沈", "曾", "彭", "吕",
	"苏", "卢", "蒋", "蔡", "贾", "丁", "魏", "薛", "叶", "阎",
	"余", "潘", "杜", "戴", "夏", "钟", "汪", "田", "任", "姜",
	"范", "方", "石", "姚", "谭", "廖", "邹", "熊", "金", "陆",
	"郝", "孔", "白", "崔", "康", "毛", "邱", "秦", "江", "史",
	"顾", "侯", "邵", "孟", "龙", "万", "段", "雷", "钱", "汤",
	"尹", "黎", "易", "常", "武", "乔", "贺", "赖", "龚", "文"
]

# 男性名字池（100个）
const MALE_NAMES = [
	"伟", "强", "磊", "军", "勇", "明", "杰", "涛", "斌", "俊",
	"浩", "鹏", "志", "峰", "超", "波", "辉", "刚", "健", "龙",
	"毅", "飞", "宇", "文", "博", "华", "平", "民", "国", "建",
	"旭", "阳", "海", "鑫", "铭", "辰", "睿", "晨", "曦", "昊天",
	"浩宇", "志远", "鹏飞", "天宇", "翰林", "泽宇", "思远", "俊杰",
	"浩然", "天佑", "文博", "明远", "子轩", "雨泽", "思哲", "宇轩",
	"景行", "致远", "鸿涛", "宇恒", "嘉懿", "宏远", "云帆", "安澜",
	"修远", "瑾瑜", "璟煜", "承泽", "瑞霖", "明熙", "晨曦", "皓轩",
	"子涵", "一鸣", "奕辰", "弘毅", "启航", "嘉瑞", "沛泽", "锦程",
	"骏驰", "铭泽", "景桓", "辰逸", "柏豪", "俊楠", "昊天", "泽楷"
]

# 女性名字池（100个）
const FEMALE_NAMES = [
	"芳", "娟", "敏", "静", "丽", "娜", "霞", "燕", "艳", "琳",
	"雪", "梅", "琴", "兰", "红", "玲", "英", "萍", "华", "青",
	"文", "秀", "美", "惠", "月", "洁", "云", "莲", "珍", "蓉",
	"蕊", "婷", "慧", "萱", "妍", "琪", "瑶", "怡", "梦", "颖",
	"悦", "蕾", "薇", "妮", "璇", "艺", "佳", "茜", "芷", "雯",
	"馨", "梓涵", "雨涵", "语嫣", "婉婷", "若曦", "梦琪", "慕晴",
	"诗涵", "雅静", "芷若", "嫣然", "心怡", "舒雅", "思颖", "晓萱",
	"紫萱", "雅琴", "冰洁", "洛晴", "映雪", "听荷", "含玉", "书瑶",
	"安雅", "清欢", "以寒", "雨薇", "诗韵", "若兰", "芷荷", "筠心",
	"沛珊", "雪怡", "乐菱", "念薇", "疏桐", "宁馨", "语琴", "云梦",
	"绮彤", "灵芸", "沐曦", "瑾萱", "茹雪", "芷柔", "黛眉", "碧菡"
]

static func _get_random_surname() -> String:
	return SURNAMES[randi() % SURNAMES.size()]

static func _get_random_given_name(is_male: bool) -> String:
	if is_male:
		return MALE_NAMES[randi() % MALE_NAMES.size()]
	else:
		return FEMALE_NAMES[randi() % FEMALE_NAMES.size()]

func _on_reroll_single(index: int):
	var slot = _name_slots[index]
	# 收集除自己外所有已使用的名字
	var other_names: Array = []
	for i in range(_name_slots.size()):
		if i != index:
			other_names.append(_name_slots[i].name)
	
	# 重新生成
	var new_name = _generate_name(slot.is_male, other_names)
	slot.name = new_name
	slot.name_label.text = new_name
	
	_update_confirm_button()

func _on_reroll_all():
	# 清除所有名字，重新生成
	var used_names: Array = []
	for i in range(_name_slots.size()):
		var is_male = (i % 2 == 0)
		var new_name = _generate_name(is_male, used_names)
		_name_slots[i].name = new_name
		_name_slots[i].name_label.text = new_name
		_name_slots[i].is_male = is_male
		used_names.append(new_name)
	
	_update_confirm_button()

func _update_confirm_button():
	# 检查是否有重复名字
	var names: Array = []
	var has_duplicate = false
	for slot in _name_slots:
		if slot.name in names:
			has_duplicate = true
			break
		names.append(slot.name)
	
	if has_duplicate:
		confirm_btn.disabled = true
		confirm_btn.text = "存在重名，请重新随机"
		confirm_btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		confirm_btn.disabled = false
		confirm_btn.text = "确认开始 ✓"
		confirm_btn.modulate = Color(1, 1, 1)

func _on_confirm():
	# 再次检查重复
	var names: Array = []
	for slot in _name_slots:
		if slot.name in names:
			return
		names.append(slot.name)
	confirmed.emit(names)
	queue_free()

func _on_cancel():
	cancelled.emit()
	queue_free()
