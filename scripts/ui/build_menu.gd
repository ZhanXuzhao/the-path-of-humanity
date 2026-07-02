# 建筑菜单 - Build Menu
# 显示可建造的建筑列表
extends Panel
class_name BuildMenu

const ItemDefinitions = preload("res://resources/item_definitions.gd")

@onready var building_list: GridContainer = $ScrollContainer/BuildingList
@onready var category_tabs: HBoxContainer = $CategoryTabs
@onready var info_panel: Panel = $InfoPanel
@onready var info_name: Label = $InfoPanel/Name
@onready var info_desc: Label = $InfoPanel/Description
@onready var info_materials: VBoxContainer = $InfoPanel/Materials

var tech_system
var building_system
var building_buttons: Dictionary = {}  # building_id -> Button
var building_shortcut_map: Dictionary = {}  # shortcut_index -> building_id
var current_category: int = -1
var selected_building: String = ""

# 快捷键状态
var shortcut_category_active: bool = false  # 是否正在等待选择分类

var _categories_list = [
	ItemDefinitions.BuildingCategory.STORAGE,
	ItemDefinitions.BuildingCategory.PRODUCTION,
	ItemDefinitions.BuildingCategory.EXTRACTION,
	ItemDefinitions.BuildingCategory.DEFENSE,
	ItemDefinitions.BuildingCategory.RESIDENTIAL,
	ItemDefinitions.BuildingCategory.INFRASTRUCTURE,
	ItemDefinitions.BuildingCategory.RESEARCH,
	ItemDefinitions.BuildingCategory.FURNITURE,
]

var _category_names = {
	ItemDefinitions.BuildingCategory.STORAGE: "存储",
	ItemDefinitions.BuildingCategory.PRODUCTION: "生产",
	ItemDefinitions.BuildingCategory.EXTRACTION: "采集",
	ItemDefinitions.BuildingCategory.DEFENSE: "防御",
	ItemDefinitions.BuildingCategory.RESIDENTIAL: "居住",
	ItemDefinitions.BuildingCategory.INFRASTRUCTURE: "基础设施",
	ItemDefinitions.BuildingCategory.RESEARCH: "研究",
	ItemDefinitions.BuildingCategory.FURNITURE: "家具",
}

var _category_emoji = {
	ItemDefinitions.BuildingCategory.STORAGE: "📦",
	ItemDefinitions.BuildingCategory.PRODUCTION: "⚙️",
	ItemDefinitions.BuildingCategory.EXTRACTION: "⛏️",
	ItemDefinitions.BuildingCategory.DEFENSE: "🛡️",
	ItemDefinitions.BuildingCategory.RESIDENTIAL: "🏠",
	ItemDefinitions.BuildingCategory.INFRASTRUCTURE: "🛤️",
	ItemDefinitions.BuildingCategory.RESEARCH: "🔬",
	ItemDefinitions.BuildingCategory.FURNITURE: "🪑",
}

# 建筑对应的 Emoji 图标
const BUILDING_EMOJI = {
	"woodcutter_hut": "🌲",
	"stone_quarry": "🪨",
	"iron_mine": "⛏️",
	"workbench": "🔧",
	"furnace": "🔥",
	"cooking_stove": "🍳",
	"sawmill": "🪚",
	"kiln": "🔥",
	"storage_rack": "📦",
	"warehouse": "🏢",
	"tent": "⛺",
	"house": "🏠",
	"campfire": "🔥",
	"road": "🛤️",
	"wood_wall": "🪵",
	"wood_door": "🚪",
	"stone_wall": "🧱",
	"stone_door": "🚪",
	"iron_wall": "🪨",
	"iron_door": "🚪",
	"wood_watchtower": "🗼",
	"wooden_bed": "🛏️",
	"research_table": "🔬",
}

func _ready():
	tech_system = get_node("/root/Game/Systems/TechSystem")
	building_system = get_node("/root/Game/Systems/BuildingSystem")
	
	visible = false
	_populate_categories()
	_populate_buildings()


func _input(event):
	if not visible:
		return
	
	# 处理数字键快捷键
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		
		# 数字键 1-9
		if keycode >= KEY_1 and keycode <= KEY_9:
			var index = keycode - KEY_1  # 0-based index
			get_viewport().set_input_as_handled()
			
			if not shortcut_category_active and current_category < 0:
				# 第一次按数字：选择分类
				_select_category_by_shortcut(index)
			else:
				# 第二次按数字：选择建筑
				_select_building_by_shortcut(index)
		
		# Esc：返回上一级或关闭菜单
		if keycode == KEY_ESCAPE:
			if shortcut_category_active:
				# 如果正在等待选择建筑，返回分类选择
				shortcut_category_active = false
				get_viewport().set_input_as_handled()
			elif current_category >= 0:
				# 如果已选择分类，取消选择分类回到总览
				current_category = -1
				_populate_buildings()
				info_panel.visible = false
				selected_building = ""
				get_viewport().set_input_as_handled()

func _populate_categories():
	# 清空
	for child in category_tabs.get_children():
		child.queue_free()
	
	for i in range(_categories_list.size()):
		var cat = _categories_list[i]
		var btn = Button.new()
		var emoji = _category_emoji.get(cat, "📌")
		btn.text = "%d.%s %s" % [i + 1, emoji, _category_names.get(cat, "其他")]
		btn.toggle_mode = true
		btn.pressed.connect(_on_category_selected.bind(cat))
		category_tabs.add_child(btn)

func _populate_buildings():
	# 清空
	for child in building_list.get_children():
		child.queue_free()
	building_buttons.clear()
	building_shortcut_map.clear()
	
	var shortcut_index = 0
	for bld_id in ItemDefinitions.buildings:
		var data = ItemDefinitions.buildings[bld_id]
		# 检查是否解锁
		if tech_system and not tech_system.is_building_unlocked(bld_id):
			continue
		
		# 按分类过滤
		if current_category >= 0 and data.category != current_category:
			continue
		
		var btn = Button.new()
		# 显示快捷键编号（1-9）
		var shortcut_label = ""
		if shortcut_index < 9:
			shortcut_label = "%d. " % (shortcut_index + 1)
			building_shortcut_map[shortcut_index] = bld_id
		var emoji = BUILDING_EMOJI.get(bld_id, "📐")
		btn.text = shortcut_label + emoji + " " + data.name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_building_selected.bind(bld_id))
		building_list.add_child(btn)
		building_buttons[bld_id] = btn
		shortcut_index += 1

func _select_category_by_shortcut(index: int):
	"""通过快捷键选择分类"""
	if index < 0 or index >= _categories_list.size():
		return
	
	var category = _categories_list[index]
	_on_category_selected(category)
	shortcut_category_active = true

func _select_building_by_shortcut(index: int):
	"""通过快捷键选择建筑"""
	if not building_shortcut_map.has(index):
		return
	
	var bld_id = building_shortcut_map[index]
	_on_building_selected(bld_id)
	
	shortcut_category_active = false

func _on_category_selected(category: int):
	# 更新所有分类按钮的选中状态
	for i in category_tabs.get_child_count():
		category_tabs.get_child(i).button_pressed = (i < _categories_list.size() and _categories_list[i] == category)
	
	current_category = category
	_populate_buildings()
	# 清空之前选中的建筑信息
	info_panel.visible = false
	selected_building = ""

func _on_building_selected(building_id: String):
	selected_building = building_id
	var data = ItemDefinitions.get_building(building_id)
	
	info_name.text = data.name
	info_desc.text = data.description
	
	# 显示材料需求
	for child in info_materials.get_children():
		child.queue_free()
	
	for mat_id in data.materials:
		var amount = data.materials[mat_id]
		var item_data = ItemDefinitions.get_item(mat_id)
		var label = Label.new()
		label.text = "  %s × %d" % [item_data.name, amount]
		info_materials.add_child(label)
	
	info_panel.visible = true
	
	# 直接进入建造模式，无需额外点击建造按钮
	var game = get_node("/root/Game")
	if game.has_method("enter_build_mode"):
		game.enter_build_mode(selected_building)

