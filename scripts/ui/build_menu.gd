# 建筑菜单 - Build Menu
# 显示可建造的建筑列表
extends Panel
class_name BuildMenu

@onready var building_list: VBoxContainer = $ScrollContainer/BuildingList
@onready var category_tabs: HBoxContainer = $CategoryTabs
@onready var info_panel: Panel = $InfoPanel
@onready var info_name: Label = $InfoPanel/Name
@onready var info_desc: Label = $InfoPanel/Description
@onready var info_materials: VBoxContainer = $InfoPanel/Materials
@onready var build_btn: Button = $InfoPanel/BuildBtn

var tech_system
var building_system
var building_buttons: Dictionary = {}  # building_id -> Button
var current_category: int = -1
var selected_building: String = ""

func _ready():
	tech_system = get_node("/root/Game/Systems/TechSystem")
	building_system = get_node("/root/Game/Systems/BuildingSystem")
	
	visible = false
	_populate_categories()
	_populate_buildings()

func _populate_categories():
	var categories = [
		ItemDefinitions.BuildingCategory.STORAGE,
		ItemDefinitions.BuildingCategory.PRODUCTION,
		ItemDefinitions.BuildingCategory.EXTRACTION,
		ItemDefinitions.BuildingCategory.DEFENSE,
		ItemDefinitions.BuildingCategory.RESIDENTIAL,
		ItemDefinitions.BuildingCategory.INFRASTRUCTURE,
		ItemDefinitions.BuildingCategory.RESEARCH,
		ItemDefinitions.BuildingCategory.FURNITURE,
	]
	
	var category_names = {
		ItemDefinitions.BuildingCategory.STORAGE: "存储",
		ItemDefinitions.BuildingCategory.PRODUCTION: "生产",
		ItemDefinitions.BuildingCategory.EXTRACTION: "采集",
		ItemDefinitions.BuildingCategory.DEFENSE: "防御",
		ItemDefinitions.BuildingCategory.RESIDENTIAL: "居住",
		ItemDefinitions.BuildingCategory.INFRASTRUCTURE: "基础设施",
		ItemDefinitions.BuildingCategory.RESEARCH: "研究",
		ItemDefinitions.BuildingCategory.FURNITURE: "家具",
	}
	
	for cat in categories:
		var btn = Button.new()
		btn.text = category_names.get(cat, "其他")
		btn.toggle_mode = true
		btn.pressed.connect(_on_category_selected.bind(cat))
		category_tabs.add_child(btn)

func _populate_buildings():
	# 清空
	for child in building_list.get_children():
		child.queue_free()
	building_buttons.clear()
	
	for bld_id in ItemDefinitions.buildings:
		var data = ItemDefinitions.buildings[bld_id]
		# 检查是否解锁
		if tech_system and not tech_system.is_building_unlocked(bld_id):
			continue
		
		# 按分类过滤
		if current_category >= 0 and data.category != current_category:
			continue
		
		var btn = Button.new()
		btn.text = data.name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_building_selected.bind(bld_id))
		building_list.add_child(btn)
		building_buttons[bld_id] = btn

func _on_category_selected(category: int):
	# 取消其他选中
	for child in category_tabs.get_children():
		child.button_pressed = false
	
	current_category = category
	_populate_buildings()

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
	build_btn.disabled = false

func _on_build_btn_pressed():
	if selected_building == "":
		return
	# 进入建造模式
	var game = get_node("/root/Game")
	if game.has_method("enter_build_mode"):
		game.enter_build_mode(selected_building)
	visible = false
