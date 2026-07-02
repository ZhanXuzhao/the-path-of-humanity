# 主HUD - Main HUD
# 显示时间、资源、人口等基本信息
extends CanvasLayer
class_name HUD

const ItemDefinitions = preload("res://resources/item_definitions.gd")
const _FS = preload("res://scripts/systems/farming_system.gd")

@onready var time_label: Label = $TopBar/TimeLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var population_label: Label = $TopBar/PopulationLabel
@onready var fps_label: Label = $TopBar/FpsLabel
@onready var resource_container: HBoxContainer = $TopBar/Resources
@onready var notification_container: VBoxContainer = $Notifications
@onready var speed_down_btn: Button = $TopBar/SpeedBox/SpeedDownBtn
@onready var speed_label: Label = $TopBar/SpeedBox/SpeedLabel
@onready var speed_up_btn: Button = $TopBar/SpeedBox/SpeedUpBtn
@onready var pause_btn: Button = $TopBar/PauseBtn
@onready var build_menu_btn: Button = $BottomBar/BuildBtn
@onready var tech_btn: Button = $BottomBar/TechBtn
@onready var work_btn: Button = $BottomBar/WorkBtn
@onready var event_btn: Button = $BottomBar/EventBtn
@onready var menu_btn: Button = $BottomBar/MenuBtn
@onready var plant_btn: Button = $BottomBar/PlantBtn

# 定居者信息面板
@onready var settler_info_panel: Panel = $SettlerInfoPanel
@onready var settler_name_label: Label = $SettlerInfoPanel/ScrollContainer/VBox/NameLabel
@onready var settler_state_label: Label = $SettlerInfoPanel/ScrollContainer/VBox/StateLabel
@onready var settler_hp_bar: ProgressBar = $SettlerInfoPanel/ScrollContainer/VBox/HpBarHBox/HPBar
@onready var settler_hp_label: Label = $SettlerInfoPanel/ScrollContainer/VBox/HpBarHBox/HPLabel
@onready var settler_needs_container: VBoxContainer = $SettlerInfoPanel/ScrollContainer/VBox/NeedsContainer

# 野猪信息面板
@onready var boar_info_panel: Panel = $BoarInfoPanel
@onready var boar_state_label: Label = $BoarInfoPanel/ScrollContainer/VBox/StateLabel
@onready var boar_hp_bar: ProgressBar = $BoarInfoPanel/ScrollContainer/VBox/HpBarHBox/HPBar
@onready var boar_hp_label: Label = $BoarInfoPanel/ScrollContainer/VBox/HpBarHBox/HPLabel
@onready var boar_needs_container: VBoxContainer = $BoarInfoPanel/ScrollContainer/VBox/NeedsContainer

# 敌对敌人信息面板
@onready var enemy_info_panel: Panel = $EnemyInfoPanel
@onready var enemy_state_label: Label = $EnemyInfoPanel/ScrollContainer/VBox/StateLabel
@onready var enemy_hp_bar: ProgressBar = $EnemyInfoPanel/ScrollContainer/VBox/HpBarHBox/HPBar
@onready var enemy_hp_label: Label = $EnemyInfoPanel/ScrollContainer/VBox/HpBarHBox/HPLabel

# 存储建筑信息面板
@onready var storage_panel: Panel = $StoragePanel
@onready var storage_name_label: Label = $StoragePanel/ScrollContainer/VBox/NameLabel
@onready var storage_capacity_label: Label = $StoragePanel/ScrollContainer/VBox/CapacityLabel
@onready var storage_items_container: VBoxContainer = $StoragePanel/ScrollContainer/VBox/ItemsContainer

# 通用建筑信息面板（非存储建筑）
@onready var building_info_panel: Panel = $BuildingInfoPanel
@onready var building_info_name_label: Label = $BuildingInfoPanel/ScrollContainer/VBox/NameLabel
@onready var building_info_desc_label: Label = $BuildingInfoPanel/ScrollContainer/VBox/DescLabel
@onready var building_info_category_label: Label = $BuildingInfoPanel/ScrollContainer/VBox/CategoryLabel
@onready var building_info_size_label: Label = $BuildingInfoPanel/ScrollContainer/VBox/SizeLabel
@onready var building_info_extra_container: VBoxContainer = $BuildingInfoPanel/ScrollContainer/VBox/ExtraInfoContainer

# 在建建筑进度面板
@onready var construction_panel: Panel = $ConstructionPanel
@onready var construction_name_label: Label = $ConstructionPanel/ScrollContainer/VBox/NameLabel
@onready var construction_progress_bar: ProgressBar = $ConstructionPanel/ScrollContainer/VBox/ProgressBar
@onready var construction_progress_label: Label = $ConstructionPanel/ScrollContainer/VBox/ProgressLabel
@onready var construction_materials_container: VBoxContainer = $ConstructionPanel/ScrollContainer/VBox/MaterialsContainer
@onready var construction_status_label: Label = $ConstructionPanel/ScrollContainer/VBox/StatusLabel

# 资源节点信息面板
@onready var resource_panel: Panel = $ResourcePanel
@onready var resource_name_label: Label = $ResourcePanel/ScrollContainer/VBox/NameLabel
@onready var resource_amount_label: Label = $ResourcePanel/ScrollContainer/VBox/AmountLabel
@onready var resource_max_label: Label = $ResourcePanel/ScrollContainer/VBox/MaxLabel

# 地块信息面板（空格子）
@onready var tile_info_panel: Panel = $TileInfoPanel
@onready var tile_type_label: Label = $TileInfoPanel/ScrollContainer/VBox/TypeLabel
@onready var tile_coord_label: Label = $TileInfoPanel/ScrollContainer/VBox/CoordLabel

# 事件菜单面板
@onready var event_panel: Panel = $EventPanel
@onready var event_title_label: Label = $EventPanel/VBox/TitleLabel
@onready var event_button_container: VBoxContainer = $EventPanel/VBox/EventListContainer

var game_manager
var notification_scene = load("res://scenes/ui/notification.tscn")

# 要显示的资源列表
var tracked_resources = ["wood", "stone", "food", "iron_ore", "copper_ore", "coal"]

# 资源对应的 Emoji 图标
const RESOURCE_EMOJI = {
	"wood": "🪵",
	"stone": "🪨",
	"food": "🍖",
	"iron_ore": "⛏️",
	"copper_ore": "🪙",
	"coal": "⬛",
}

var _resource_refresh_timer: float = 0.0

func _ready():
	game_manager = get_node("/root/GameManager")
	
	# 连接信号
	game_manager.time_changed.connect(_on_time_changed)
	game_manager.day_changed.connect(_on_day_changed)
	game_manager.notification.connect(_on_notification)
	
		# 按钮连接
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_pressed)
	if speed_down_btn:
		speed_down_btn.pressed.connect(_on_speed_down_pressed)
	if speed_up_btn:
		speed_up_btn.pressed.connect(_on_speed_up_pressed)
	if build_menu_btn:
		build_menu_btn.pressed.connect(_on_build_menu_pressed)
		build_menu_btn.text = "建造 [B]"
	if tech_btn:
		tech_btn.pressed.connect(_on_tech_pressed)
	if work_btn:
		work_btn.pressed.connect(_on_work_pressed)
	if event_btn:
		event_btn.pressed.connect(_on_event_pressed)
	if menu_btn:
		menu_btn.pressed.connect(_on_menu_pressed)
	if plant_btn:
		plant_btn.pressed.connect(_on_plant_pressed)
	
	# 初始化事件面板
	if event_panel:
		event_panel.visible = false
		_populate_event_buttons()
	
	# 延迟一帧初始化资源显示（等 Game 场景就绪）
	call_deferred("_refresh_resource_display")
	
	# 连接建筑完成和地面物品变化信号，触发实时刷新
	var game = get_node_or_null("/root/Game")
	if game:
		if game.building_system:
			game.building_system.building_completed.connect(_refresh_resource_display)
		if game.world:
			game.world.ground_items_changed.connect(_on_ground_items_changed)
	
	# 定居者选择信号连接
	_settler_info_connections()
	
	# 更新人口显示
	_update_population()

	# 创建农田信息面板（动态创建）
	call_deferred("_init_farm_plot_panel")

# 定居者信息面板相关变量
var _tracked_settler = null
var _tracked_boar = null

# 标记当前存储面板显示的是地面物品还是置物架（两者复用同一面板）
var _showing_ground_items: bool = false
var _need_bars: Dictionary = {}  # need_id -> ProgressBar
var _inventory_weight_label: Label
var _inventory_container: VBoxContainer

func _settler_info_connections():
	var game = get_node("/root/Game")
	if game:
		call_deferred("_connect_selection_signals")

func _connect_selection_signals():
	var game = get_node_or_null("/root/Game")
	if game and game.selection_system:
		game.selection_system.settler_selected.connect(_on_settler_selected)
		game.selection_system.settler_deselected.connect(_on_settler_deselected)
		game.selection_system.building_selected.connect(_on_building_selected)
		game.selection_system.building_deselected.connect(_on_building_deselected)
		game.selection_system.construction_selected.connect(_on_construction_selected)
		game.selection_system.construction_deselected.connect(_on_construction_deselected)
		game.selection_system.resource_selected.connect(_on_resource_selected)
		game.selection_system.resource_deselected.connect(_on_resource_deselected)
		game.selection_system.ground_item_selected.connect(_on_ground_item_selected)
		game.selection_system.ground_item_deselected.connect(_on_ground_item_deselected_storage)
		game.selection_system.boar_selected.connect(_on_boar_selected)
		game.selection_system.boar_deselected.connect(_on_boar_deselected)
		game.selection_system.enemy_selected.connect(_on_enemy_selected)
		game.selection_system.enemy_deselected.connect(_on_enemy_deselected)
		game.selection_system.tile_selected.connect(_on_tile_selected)
		game.selection_system.tile_deselected.connect(_on_tile_deselected)
		game.selection_system.farm_plot_selected.connect(_on_farm_plot_selected)
		game.selection_system.farm_plot_deselected.connect(_on_farm_plot_deselected)

func _hide_all_info_panels():
	"""隐藏所有左下角信息面板，确保同时只显示一个"""
	settler_info_panel.visible = false
	boar_info_panel.visible = false
	enemy_info_panel.visible = false
	storage_panel.visible = false
	building_info_panel.visible = false
	construction_panel.visible = false
	resource_panel.visible = false
	tile_info_panel.visible = false
	if _farm_plot_info_panel:
		_farm_plot_info_panel.visible = false

func _on_settler_selected(settler):
	"""选中定居者时显示信息面板"""
	_hide_all_info_panels()
	settler_info_panel.visible = true
	_tracked_settler = settler
	_build_settler_info_ui(settler)

func _update_inventory_display(settler):
	"""更新背包显示内容和负重情况"""
	if not is_instance_valid(settler) or not is_instance_valid(_inventory_weight_label):
		return
	
	var weight = settler.get_inventory_weight()
	var cap = settler.carry_capacity
	var pct = minf(weight / max(cap, 1.0), 1.0) * 100.0
	
	# 负重显示
	var weight_color = Color(0.9, 0.9, 0.6)
	if pct >= 90.0:
		weight_color = Color(1.0, 0.3, 0.3)
	elif pct >= 70.0:
		weight_color = Color(1.0, 0.8, 0.2)
	_inventory_weight_label.add_theme_color_override("font_color", weight_color)
	_inventory_weight_label.text = "负重: %.1f/%.1f (%.0f%%)" % [weight, cap, pct]
	
	# 物品列表
	for child in _inventory_container.get_children():
		child.queue_free()
	
	if settler.inventory == null or settler.inventory.is_empty():
		var empty_label = Label.new()
		empty_label.text = "  (背包为空)"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.add_theme_constant_override("minimum_font_size", 11)
		_inventory_container.add_child(empty_label)
		return
	
	# 显示物品种类及总数（ inventories 现已按种类汇总）
	for item_id in settler.inventory.items:
		var total = settler.inventory.items[item_id]
		var item_data = ItemDefinitions.get_item(item_id)
		var name_str = item_data.name if item_data else item_id
		var hbox = HBoxContainer.new()
		var icon_label = Label.new()
		icon_label.text = "•"
		icon_label.custom_minimum_size = Vector2(16, 0)
		var name_label = Label.new()
		name_label.text = "%s × %d" % [name_str, total]
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.add_theme_constant_override("minimum_font_size", 11)
		hbox.add_child(icon_label)
		hbox.add_child(name_label)
		_inventory_container.add_child(hbox)

func _on_settler_deselected():
	"""取消选中时隐藏信息面板"""
	settler_info_panel.visible = false
	_tracked_settler = null

# -------- 野猪信息面板 --------
func _on_boar_selected(boar):
	"""选中野猪时显示信息面板"""
	_hide_all_info_panels()
	boar_info_panel.visible = true
	_tracked_boar = boar
	_build_boar_info_ui(boar)

func _on_boar_deselected():
	"""取消选中时隐藏野猪面板"""
	boar_info_panel.visible = false
	_tracked_boar = null

# -------- 敌对敌人信息面板 --------
func _on_enemy_selected(enemy):
	"""选中敌人时显示信息面板"""
	_hide_all_info_panels()
	enemy_info_panel.visible = true
	_update_enemy_info_panel(enemy)

func _on_enemy_deselected():
	"""取消选中时隐藏敌人面板"""
	enemy_info_panel.visible = false

func _update_enemy_info_panel(enemy):
	"""更新敌人信息面板"""
	if not is_instance_valid(enemy):
		return
	enemy_state_label.text = "状态: " + Enemy.get_state_display(enemy.state)
	enemy_hp_label.text = "生命:"
	enemy_hp_bar.max_value = enemy.max_hp
	enemy_hp_bar.value = enemy.hp

func _build_boar_info_ui(boar):
	"""构建野猪信息面板"""
	if not is_instance_valid(boar):
		return
	
	boar_state_label.text = "状态: " + Boar.get_state_display(boar.state)
	boar_hp_label.text = "生命:"
	boar_hp_bar.max_value = boar.max_hp
	boar_hp_bar.value = boar.hp
	
	# 重建需求条
	for child in boar_needs_container.get_children():
		child.queue_free()
	
	var need_configs = {
		"hunger": "饥饿度",
		"energy": "精力",
	}
	
	for need_id in need_configs:
		var val = boar.hunger if need_id == "hunger" else boar.energy
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = need_configs[need_id] + ":"
		label.custom_minimum_size = Vector2(50, 0)
		label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		label.add_theme_constant_override("minimum_font_size", 12)
		
		var bar = ProgressBar.new()
		bar.max_value = 100.0
		bar.value = val
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = true
		
		# 饥饿度用橙色，精力用蓝色
		if need_id == "hunger":
			bar.add_theme_stylebox_override("fill", _make_stylebox(Color(1.0, 0.6, 0.2, 0.8)))
		else:
			bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.3, 0.6, 1.0, 0.8)))
		
		hbox.add_child(label)
		hbox.add_child(bar)
		boar_needs_container.add_child(hbox)

func _make_stylebox(color: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	sb.corner_radius_bottom_left = 2
	return sb

# -------- 存储建筑面板 / 通用建筑信息面板 --------
func _on_building_selected(bld):
	"""选中建筑时显示信息面板（存储建筑显示库存，其他显示基本信息）"""
	_hide_all_info_panels()
	_showing_ground_items = false
	
	var data = bld.get_data()
	if data and data.storage_capacity > 0 and bld.inventory != null:
		# 存储建筑 → 显示库存面板
		storage_panel.visible = true
		_update_storage_panel(bld)
	else:
		# 非存储建筑 → 显示通用建筑信息面板
		building_info_panel.visible = true
		_update_building_info_panel(bld, data)

func _on_building_deselected():
	"""取消选中建筑"""
	_showing_ground_items = false
	storage_panel.visible = false
	building_info_panel.visible = false

# -------- 在建建筑进度面板 --------
func _on_construction_selected(bld):
	"""选中在建建筑时显示进度面板"""
	_hide_all_info_panels()
	construction_panel.visible = true
	_update_construction_panel(bld)

func _on_construction_deselected():
	"""取消选中在建建筑"""
	construction_panel.visible = false

# -------- 资源节点信息面板 --------
func _on_resource_selected(_pos: Vector2i, deposit):
	"""选中资源节点时显示信息面板"""
	_hide_all_info_panels()
	resource_panel.visible = true
	_update_resource_panel(deposit)

func _on_resource_deselected():
	"""取消选中资源节点"""
	resource_panel.visible = false

func _update_resource_panel(deposit):
	"""更新资源信息面板内容"""
	if deposit == null:
		return
	
	var res_names = {
		World.ResourceNodeType.TREE: "树木",
		World.ResourceNodeType.STONE_DEPOSIT: "石矿",
		World.ResourceNodeType.IRON_DEPOSIT: "铁矿",
		World.ResourceNodeType.COPPER_DEPOSIT: "铜矿",
		World.ResourceNodeType.COAL_DEPOSIT: "煤矿",
		World.ResourceNodeType.BERRY_BUSH: "浆果丛",
	}
	
	var res_name = res_names.get(deposit.type, "资源")
	resource_name_label.text = res_name
	resource_amount_label.text = "剩余: %.0f" % deposit.amount
	resource_max_label.text = "总量: %.0f" % deposit.max_amount
	
	# 根据剩余比例改变颜色
	var ratio = deposit.amount / max(deposit.max_amount, 1.0)
	if ratio < 0.2:
		resource_amount_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif ratio < 0.5:
		resource_amount_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		resource_amount_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

# -------- 地块信息面板（空格子）--------
func _on_tile_selected(pos: Vector2i, tile_type: int):
	"""选中空格子时显示地块信息和坐标"""
	_hide_all_info_panels()
	tile_info_panel.visible = true
	_update_tile_info_panel(pos, tile_type)

func _on_tile_deselected():
	"""取消选中空格子"""
	tile_info_panel.visible = false

func _update_tile_info_panel(pos: Vector2i, tile_type: int):
	"""更新地块信息面板内容"""
	var type_names = {
		World.TileType.GRASS: "草地",
		World.TileType.DIRT: "泥土",
		World.TileType.SAND: "沙地",
		World.TileType.WATER: "水域",
		World.TileType.DEEP_WATER: "深水",
		World.TileType.STONE: "岩石地面",
		World.TileType.FOREST: "森林",
		World.TileType.MOUNTAIN: "山脉",
		World.TileType.SNOW: "雪地",
		World.TileType.ROAD: "道路",
		World.TileType.FLOOR: "地板",
		World.TileType.WALL: "墙壁",
	}
	
	var type_name = type_names.get(tile_type, "未知地形")
	tile_type_label.text = "地形: " + type_name
	tile_coord_label.text = "坐标: (%d, %d)" % [pos.x, pos.y]

# -------- 农田地块信息面板（动态创建）--------
var _farm_plot_info_panel: Panel = null
var _farm_plot_name_label: Label = null
var _farm_plot_state_label: Label = null
var _farm_plot_progress_bar: ProgressBar = null
var _farm_plot_progress_label: Label = null
var _farm_plot_count_label: Label = null
var _tracked_farm_plot = null
var _tracked_farm_plot_group_size: int = 0

func _init_farm_plot_panel():
	if _farm_plot_info_panel != null:
		return

	_farm_plot_info_panel = Panel.new()
	_farm_plot_info_panel.name = "FarmPlotInfoPanel"
	_farm_plot_info_panel.visible = false
	_farm_plot_info_panel.position = Vector2(8, 420)
	_farm_plot_info_panel.size = Vector2(170, 110)
	_farm_plot_info_panel.add_theme_stylebox_override("panel", _make_info_panel_stylebox())
	add_child(_farm_plot_info_panel)

	var vbox = VBoxContainer.new()
	vbox.position = Vector2(8, 8)
	vbox.size = Vector2(154, 94)
	vbox.add_theme_constant_override("separation", 4)
	_farm_plot_info_panel.add_child(vbox)

	_farm_plot_name_label = Label.new()
	_farm_plot_name_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_farm_plot_name_label.add_theme_constant_override("minimum_font_size", 13)
	vbox.add_child(_farm_plot_name_label)

	_farm_plot_state_label = Label.new()
	_farm_plot_state_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_farm_plot_state_label.add_theme_constant_override("minimum_font_size", 12)
	vbox.add_child(_farm_plot_state_label)

	var progress_hbox = HBoxContainer.new()
	vbox.add_child(progress_hbox)

	_farm_plot_progress_bar = ProgressBar.new()
	_farm_plot_progress_bar.max_value = 1.0
	_farm_plot_progress_bar.value = 0.0
	_farm_plot_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_farm_plot_progress_bar.show_percentage = false
	_farm_plot_progress_bar.add_theme_constant_override("minimum_font_size", 11)
	_farm_plot_progress_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.3, 1.0, 0.3, 0.8)))
	progress_hbox.add_child(_farm_plot_progress_bar)

	_farm_plot_progress_label = Label.new()
	_farm_plot_progress_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_farm_plot_progress_label.add_theme_constant_override("minimum_font_size", 11)
	_farm_plot_progress_label.custom_minimum_size = Vector2(40, 0)
	progress_hbox.add_child(_farm_plot_progress_label)

	_farm_plot_count_label = Label.new()
	_farm_plot_count_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_farm_plot_count_label.add_theme_constant_override("minimum_font_size", 11)
	vbox.add_child(_farm_plot_count_label)

func _make_info_panel_stylebox() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.3, 0.3, 0.35, 0.8)
	return sb

func _on_farm_plot_selected(_pos: Vector2i, plot):
	_hide_all_info_panels()
	_tracked_farm_plot = plot

	# 获取选中组大小
	var game = get_node_or_null("/root/Game")
	if game and game.selection_system:
		_tracked_farm_plot_group_size = game.selection_system.selected_farm_plots_group.size()
	else:
		_tracked_farm_plot_group_size = 1

	if _farm_plot_info_panel == null:
		_init_farm_plot_panel()
	_farm_plot_info_panel.visible = true
	_update_farm_plot_panel(plot)

func _on_farm_plot_deselected():
	_farm_plot_info_panel.visible = false
	_tracked_farm_plot = null
	_tracked_farm_plot_group_size = 0

func _update_farm_plot_panel(plot):
	if plot == null:
		return

	var game = get_node_or_null("/root/Game")
	var farming_system = get_node_or_null("/root/Game/Systems/FarmingSystem") if game else null
	var crop_def = farming_system.get_crop_def(plot.crop_id) if farming_system else null
	var crop_name = crop_def.name if crop_def else plot.crop_id
	var emoji = crop_def.emoji if crop_def else "🌾"

	_farm_plot_name_label.text = "%s %s" % [emoji, crop_name]

	match plot.state:
		_FS.PlotState.EMPTY:
			_farm_plot_state_label.text = "状态: 刚种下"
			_farm_plot_state_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
			_farm_plot_progress_bar.value = 0.0
			_farm_plot_progress_label.text = "0%"
			_farm_plot_progress_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.6, 0.9, 0.6, 0.6)))
		_FS.PlotState.PLANTED:
			_farm_plot_state_label.text = "状态: 生长中"
			_farm_plot_state_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
			_farm_plot_progress_bar.value = plot.growth_progress
			_farm_plot_progress_label.text = "%d%%" % (plot.growth_progress * 100.0)
			if plot.growth_progress < 0.5:
				_farm_plot_progress_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.3, 1.0, 0.3, 0.8)))
			else:
				_farm_plot_progress_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(1.0, 0.8, 0.2, 0.8)))
		_FS.PlotState.READY:
			_farm_plot_state_label.text = "状态: 可收获 ✓"
			_farm_plot_state_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			_farm_plot_progress_bar.value = 1.0
			_farm_plot_progress_label.text = "100%"
			_farm_plot_progress_bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.3, 1.0, 0.3, 0.8)))

	if _tracked_farm_plot_group_size > 1:
		_farm_plot_count_label.text = "已选中 %d 块相邻田" % _tracked_farm_plot_group_size
		_farm_plot_count_label.visible = true
	else:
		_farm_plot_count_label.visible = false

# -------- 地面物品信息面板（复用存储面板）--------
func _on_ground_item_selected(_pos: Vector2i, stacks):
	"""选中地面物品时显示信息面板（复用存储面板）"""
	_hide_all_info_panels()
	_showing_ground_items = true
	storage_panel.visible = true
	_update_ground_item_storage_panel(stacks)

func _on_ground_item_deselected_storage():
	"""取消选中地面物品"""
	_showing_ground_items = false
	storage_panel.visible = false

func _update_ground_item_storage_panel(stacks):
	"""更新地面物品信息（复用存储面板UI）"""
	if stacks.is_empty():
		return
	
	# 统计信息
	var total_stacks = stacks.size()
	var total_items = 0
	for s in stacks:
		total_items += s.amount
	
	storage_name_label.text = "地面物品 (%d 种)" % total_stacks
	storage_capacity_label.text = "总数量: %d" % total_items
	
	# 重建物品列表
	for child in storage_items_container.get_children():
		child.queue_free()
	
	for stack in stacks:
		var item_data = ItemDefinitions.get_item(stack.item_id)
		var name_str = item_data.name if item_data else stack.item_id
		var hbox = HBoxContainer.new()
		var icon_label = Label.new()
		icon_label.text = "•"
		icon_label.custom_minimum_size = Vector2(16, 0)
		var name_label = Label.new()
		name_label.text = "%s × %d" % [name_str, stack.amount]
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.add_theme_constant_override("minimum_font_size", 12)
		hbox.add_child(icon_label)
		hbox.add_child(name_label)
		storage_items_container.add_child(hbox)

func _update_construction_panel(bld):
	"""更新建筑进度面板内容"""
	if not is_instance_valid(bld):
		return
	
	var data = bld.get_data()
	if not data:
		return
	
	# 建筑名称
	var display_name = bld.display_name if bld.display_name != "" else data.name
	construction_name_label.text = display_name
	
	# 建造进度条
	var ratio = bld.construction_progress / data.work_cost if data.work_cost > 0 else 0.0
	ratio = clamp(ratio, 0.0, 1.0)
	construction_progress_bar.max_value = 1.0
	construction_progress_bar.value = ratio
	construction_progress_bar.show_percentage = true
	construction_progress_label.text = "建造进度: %.0f / %.0f" % [bld.construction_progress, data.work_cost]
	
	# 刷新材料列表
	for child in construction_materials_container.get_children():
		child.queue_free()
	
	if data.materials.is_empty():
		# 无需材料
		var no_mat_label = Label.new()
		no_mat_label.text = "  无需建造材料"
		no_mat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_mat_label.add_theme_constant_override("minimum_font_size", 12)
		construction_materials_container.add_child(no_mat_label)
		
		construction_status_label.text = "⏳ 等待工人施工..."
		construction_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		var all_ready = true
		for mat_id in data.materials:
			var needed = data.materials[mat_id]
			var deposited = bld.deposited_materials.get(mat_id, 0)
			var item_data = ItemDefinitions.get_item(mat_id)
			var name_str = item_data.name if item_data else mat_id
			var is_ready = deposited >= needed
			if not is_ready:
				all_ready = false
			
			var hbox = HBoxContainer.new()
			var label = Label.new()
			label.text = "  %s: %d / %d" % [name_str, deposited, needed]
			label.add_theme_constant_override("minimum_font_size", 12)
			if is_ready:
				label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			else:
				label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			hbox.add_child(label)
			construction_materials_container.add_child(hbox)
		
		# 状态提示
		if all_ready:
			construction_status_label.text = "✅ 材料已备齐，等待工人施工..."
			construction_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		else:
			construction_status_label.text = "⏳ 等待材料搬运到工地..."
			construction_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))

func _update_storage_panel(bld):
	"""更新存储建筑面板内容"""
	if not is_instance_valid(bld):
		return
	
	var data = bld.get_data()
	var display_name = bld.display_name if bld.display_name != "" else (data.name if data else "存储")
	storage_name_label.text = display_name
	
	# 容量信息
	var used = bld.inventory.get_total_items() if bld.inventory else 0
	var cap = bld.inventory.capacity if bld.inventory else 0
	storage_capacity_label.text = "容量: %d/%d" % [used, cap]
	
	# 物品列表
	for child in storage_items_container.get_children():
		child.queue_free()
	
	if bld.inventory == null or bld.inventory.is_empty():
		var empty_label = Label.new()
		empty_label.text = "  (空)"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		storage_items_container.add_child(empty_label)
		return
	
	# 显示物品种类及总数（ inventories 现已按种类汇总）
	for item_id in bld.inventory.items:
		var total = bld.inventory.items[item_id]
		var item_data = ItemDefinitions.get_item(item_id)
		var name_str = item_data.name if item_data else item_id
		var hbox = HBoxContainer.new()
		var icon_label = Label.new()
		icon_label.text = "•"
		icon_label.custom_minimum_size = Vector2(16, 0)
		var name_label = Label.new()
		name_label.text = "%s × %d" % [name_str, total]
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.add_theme_constant_override("minimum_font_size", 12)
		hbox.add_child(icon_label)
		hbox.add_child(name_label)
		storage_items_container.add_child(hbox)

func _update_building_info_panel(bld, data):
	"""更新通用建筑信息面板内容（非存储建筑）"""
	if not is_instance_valid(bld):
		return
	
	if data == null:
		building_info_name_label.text = "未知建筑"
		building_info_desc_label.text = ""
		building_info_category_label.text = ""
		building_info_size_label.text = ""
		return
	
	var display_name = bld.display_name if bld.display_name != "" else data.name
	building_info_name_label.text = display_name
	building_info_desc_label.text = data.description
	
	# 分类
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
	var cat_name = category_names.get(data.category, "其他")
	building_info_category_label.text = "分类: %s" % cat_name
	building_info_size_label.text = "大小: %d×%d" % [data.size.x, data.size.y]
	
	# 额外信息（按建筑类型）
	for child in building_info_extra_container.get_children():
		child.queue_free()
	
	# 床铺显示分配对象（信息面板中）
	if bld.building_id == "wooden_bed" and bld.assigned_settler_name != "":
		var assign_label = Label.new()
		assign_label.text = "分配: %s" % bld.assigned_settler_name
		assign_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		building_info_extra_container.add_child(assign_label)
		
		var gm = get_node("/root/GameManager")
		if gm and bld.assigned_settler_id != "":
			var game = get_node_or_null("/root/Game")
			var settler = game.task_system.get_settler_by_id(bld.assigned_settler_id) if game else null
			if settler and is_instance_valid(settler):
				var state_text = Settler.get_state_display(settler.state)
				var state_label = Label.new()
				state_label.text = "状态: %s" % state_text
				state_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
				building_info_extra_container.add_child(state_label)
	
	# 生产建筑显示产出信息
	if data.production_time > 0 and not data.produces.is_empty():
		var prod_text = "产出: "
		var first = true
		for item_id in data.produces:
			if not first:
				prod_text += ", "
			first = false
			var item_data = ItemDefinitions.get_item(item_id)
			var item_name = item_data.name if item_data else item_id
			prod_text += "%s×%d" % [item_name, data.produces[item_id]]
		var prod_label = Label.new()
		prod_label.text = prod_text
		prod_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.6))
		building_info_extra_container.add_child(prod_label)
		
		var cycle_label = Label.new()
		cycle_label.text = "周期: %.1f秒" % data.production_time
		cycle_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		building_info_extra_container.add_child(cycle_label)
	
	# 居住建筑显示容量
	if data.category == ItemDefinitions.BuildingCategory.RESIDENTIAL:
		var cap_label = Label.new()
		cap_label.text = "可容纳定居者"
		cap_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		building_info_extra_container.add_child(cap_label)
	
	# 显示建筑材料（建造时需要的）
	if not data.materials.is_empty():
		var mat_sep = HSeparator.new()
		building_info_extra_container.add_child(mat_sep)
		var mat_title = Label.new()
		mat_title.text = "建造材料:"
		mat_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		building_info_extra_container.add_child(mat_title)
		for mat_id in data.materials:
			var amount = data.materials[mat_id]
			var item_data = ItemDefinitions.get_item(mat_id)
			var item_name = item_data.name if item_data else mat_id
			var mat_label = Label.new()
			mat_label.text = "  %s × %d" % [item_name, amount]
			mat_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			building_info_extra_container.add_child(mat_label)

	# 显示建筑耐久度（使用实例的当前 HP，而非模板的 max HP）
	var hp_label = Label.new()
	var hp_ratio = float(bld.hp) / float(bld.max_hp) if bld.max_hp > 0 else 1.0
	var hp_color = Color(0.3, 1.0, 0.3)
	if hp_ratio < 0.3:
		hp_color = Color(1.0, 0.3, 0.3)
	elif hp_ratio < 0.6:
		hp_color = Color(1.0, 0.8, 0.2)
	hp_label.text = "耐久: %d/%d" % [bld.hp, bld.max_hp]
	hp_label.add_theme_color_override("font_color", hp_color)
	hp_label.add_theme_constant_override("minimum_font_size", 12)
	building_info_extra_container.add_child(hp_label)
	
	# ===== 可制作配方（生产建筑专用） =====
	_show_building_recipes(bld)

func _show_building_recipes(bld):
	"""在建筑信息面板中显示可制作的配方和添加制作按钮"""
	var game = get_node_or_null("/root/Game")
	if not game or not game.crafting_system or not game.tech_system:
		return
	
	var recipes = game.crafting_system.get_available_recipes(bld.building_id, game.tech_system.researched_techs)
	if recipes.is_empty():
		return
	
	var recipe_sep = HSeparator.new()
	building_info_extra_container.add_child(recipe_sep)
	
	var recipe_title = Label.new()
	recipe_title.text = "可制作配方:"
	recipe_title.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	building_info_extra_container.add_child(recipe_title)
	
	for recipe in recipes:
		var recipe_hbox = HBoxContainer.new()
		recipe_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 配方信息：输入 → 输出
		var input_text = ""
		var first = true
		for item_id in recipe.inputs:
			if not first:
				input_text += " "
			first = false
			var item_data = ItemDefinitions.get_item(item_id)
			var item_name = item_data.name if item_data else item_id
			input_text += "%s×%d" % [item_name, recipe.inputs[item_id]]
		
		var output_text = ""
		first = true
		for item_id in recipe.outputs:
			if not first:
				output_text += " "
			first = false
			var item_data = ItemDefinitions.get_item(item_id)
			var item_name = item_data.name if item_data else item_id
			output_text += "%s×%d" % [item_name, recipe.outputs[item_id]]
		
		var info_label = Label.new()
		info_label.text = "  %s: %s → %s" % [recipe.name, input_text, output_text]
		info_label.custom_minimum_size = Vector2(160, 0)
		info_label.autowrap_mode = 1
		info_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		info_label.add_theme_constant_override("minimum_font_size", 10)
		recipe_hbox.add_child(info_label)
		
		# 添加制作按钮
		var add_btn = Button.new()
		add_btn.text = "制作"
		add_btn.custom_minimum_size = Vector2(50, 24)
		add_btn.add_theme_constant_override("minimum_font_size", 10)
		var recipe_id = recipe.id
		var bld_pos = bld.grid_pos
		add_btn.pressed.connect(func():
			if game and game.crafting_system:
				game.crafting_system.add_with_prerequisites(recipe_id, bld_pos)
				var gm = get_node("/root/GameManager")
				if gm:
					gm.show_notification("已添加制作: %s" % recipe.name, gm.NotificationType.INFO)
		)
		recipe_hbox.add_child(add_btn)
		
		building_info_extra_container.add_child(recipe_hbox)

func _update_population():
	"""更新人口显示"""
	var game = get_node("/root/Game")
	if game and population_label:
		var count = 0
		for s in game.settlers:
			if is_instance_valid(s):
				count += 1
		population_label.text = "人口: %d" % count

func _build_settler_info_ui(settler):
	"""构建定居者信息面板（选中不同人时调用）"""
	if not is_instance_valid(settler):
		return
	
	settler_name_label.text = settler.settler_name
	settler_state_label.text = "状态: " + Settler.get_state_display(settler.state, settler.current_task if settler.current_task else {})
	settler_hp_label.text = "生命:"
	settler_hp_bar.max_value = settler.max_hp
	settler_hp_bar.value = settler.hp
	
	# 重建需求条
	for child in settler_needs_container.get_children():
		child.queue_free()
	_need_bars.clear()
	
	var need_names = {
		"hunger": "饱食度",
		"rest": "睡眠",
	}
	
	for need_id in settler.needs:
		if not need_names.has(need_id):
			continue
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = need_names.get(need_id, need_id) + ":"
		label.custom_minimum_size = Vector2(50, 0)
		label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		label.add_theme_constant_override("minimum_font_size", 12)
		
		var bar = ProgressBar.new()
		bar.max_value = 100.0
		bar.value = settler.needs[need_id]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = true
		
		hbox.add_child(label)
		hbox.add_child(bar)
		settler_needs_container.add_child(hbox)
		_need_bars[need_id] = bar
	
	# -------- 背包/负重区域 --------
	var inv_sep = HSeparator.new()
	settler_needs_container.add_child(inv_sep)
	
	_inventory_weight_label = Label.new()
	_inventory_weight_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_inventory_weight_label.add_theme_constant_override("minimum_font_size", 12)
	settler_needs_container.add_child(_inventory_weight_label)
	
	_inventory_container = VBoxContainer.new()
	settler_needs_container.add_child(_inventory_container)
	
	_update_inventory_display(settler)

func _process(delta):
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	
	# 选中定居者时实时更新信息面板
	if settler_info_panel.visible and is_instance_valid(_tracked_settler):
		var s = _tracked_settler
		settler_state_label.text = "状态: " + Settler.get_state_display(s.state, s.current_task if s.current_task else {})
		settler_hp_bar.max_value = s.max_hp
		settler_hp_bar.value = s.hp
		# 更新需求条数值
		for need_id in _need_bars:
			var bar = _need_bars[need_id]
			if is_instance_valid(bar):
				bar.value = s.needs.get(need_id, 0.0)
		# 更新背包显示
		_update_inventory_display(s)
	elif settler_info_panel.visible and not is_instance_valid(_tracked_settler):
		# 如果选中的定居者已死亡/消失，自动隐藏面板
		_on_settler_deselected()
		var game = get_node("/root/Game")
		if game:
			game.selection_system.selected_settler = null
	
	# 选中野猪时实时更新信息面板
	if boar_info_panel.visible and is_instance_valid(_tracked_boar):
		var b = _tracked_boar
		boar_state_label.text = "状态: " + Boar.get_state_display(b.state)
		boar_hp_bar.max_value = b.max_hp
		boar_hp_bar.value = b.hp
		# 更新需求条数值
		for child in boar_needs_container.get_children():
			if child is HBoxContainer and child.get_child_count() >= 2:
				var bar = child.get_child(1)
				if bar is ProgressBar:
					var label = child.get_child(0)
					if label and label is Label:
						if "饥饿度" in label.text:
							bar.value = b.hunger
						elif "精力" in label.text:
							bar.value = b.energy
	elif boar_info_panel.visible and not is_instance_valid(_tracked_boar):
		_on_boar_deselected()
		var game = get_node("/root/Game")
		if game:
			game.selection_system.selected_boar = null
	
	# 选中敌人时实时更新信息面板
	if enemy_info_panel.visible:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_enemy != null and is_instance_valid(game.selection_system.selected_enemy):
			var e = game.selection_system.selected_enemy
			enemy_state_label.text = "状态: " + Enemy.get_state_display(e.state)
			enemy_hp_bar.max_value = e.max_hp
			enemy_hp_bar.value = e.hp
		elif game and (game.selection_system.selected_enemy == null or not is_instance_valid(game.selection_system.selected_enemy)):
			_on_enemy_deselected()
	
	# 选中地面物品时实时更新物品列表（复用存储面板）
	if storage_panel.visible and _showing_ground_items:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_ground_item_pos.x >= 0:
			var stacks = game.world.get_ground_items_at(game.selection_system.selected_ground_item_pos)
			if not stacks.is_empty():
				_update_ground_item_storage_panel(stacks)
			else:
				# 地面物品已被拾取完，隐藏面板
				_on_ground_item_deselected_storage()
				game.selection_system.deselect_ground_item()
	
	# 选中资源节点时实时更新资源量
	if resource_panel.visible:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_resource_pos.x >= 0:
			var deposit = game.world.get_resource_at(game.selection_system.selected_resource_pos)
			if deposit != null and deposit.amount > 0:
				_update_resource_panel(deposit)
			else:
				# 资源已耗尽，隐藏面板
				_on_resource_deselected()
	
	# 定时更新存储面板信息（仅当显示的是存储建筑时，地面物品走上面的实时更新）
	if Engine.get_physics_frames() % 30 == 0 and storage_panel.visible and not _showing_ground_items:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_building_instance:
			_update_storage_panel(game.selection_system.selected_building_instance)
	
	# 定时更新建造进度面板
	if Engine.get_physics_frames() % 15 == 0 and construction_panel.visible:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_construction_building:
			_update_construction_panel(game.selection_system.selected_construction_building)
	
	# 定时更新建筑信息面板（HP 实时变化）
	if Engine.get_physics_frames() % 30 == 0 and building_info_panel.visible:
		var game = get_node("/root/Game")
		if game and game.selection_system.selected_building_instance:
			var bld = game.selection_system.selected_building_instance
			if is_instance_valid(bld) and bld.get_data():
				# 只更新耐久度标签（最后一个子节点）
				for child in building_info_extra_container.get_children():
					if child is Label and child.text.begins_with("耐久:"):
						var hp_ratio = float(bld.hp) / float(bld.max_hp) if bld.max_hp > 0 else 1.0
						var hp_color = Color(0.3, 1.0, 0.3)
						if hp_ratio < 0.3:
							hp_color = Color(1.0, 0.3, 0.3)
						elif hp_ratio < 0.6:
							hp_color = Color(1.0, 0.8, 0.2)
						child.text = "耐久: %d/%d" % [bld.hp, bld.max_hp]
						child.add_theme_color_override("font_color", hp_color)
						break
	
	# 定时更新人口（不每帧刷新）
	if Engine.get_physics_frames() % 60 == 0:
		_update_population()
	
	# 选中农田时实时更新信息面板
	if _farm_plot_info_panel and _farm_plot_info_panel.visible and _tracked_farm_plot != null:
		var plot = _tracked_farm_plot
		var game = get_node_or_null("/root/Game")
		if game and game.selection_system:
			_tracked_farm_plot_group_size = game.selection_system.selected_farm_plots_group.size()
		if plot.state == _FS.PlotState.PLANTED or plot.state == _FS.PlotState.EMPTY:
			_update_farm_plot_panel(plot)

	# 定时刷新资源显示（来自置物架+地面）
	_resource_refresh_timer += delta
	if _resource_refresh_timer >= 2.0:
		_resource_refresh_timer = 0.0
		_refresh_resource_display()

func _on_time_changed(_hour: float):
	if time_label:
		time_label.text = game_manager.get_time_string()

func _on_day_changed(day: int):
	if day_label:
		day_label.text = "第 %d 天" % day

func _on_pause_pressed():
	game_manager.toggle_pause()
	if pause_btn:
		pause_btn.text = "▶" if game_manager.state == 2 else "⏸"

func _update_speed_label():
	"""更新速度显示标签"""
	if not speed_label:
		return
	var speed = game_manager.time_speed
	LogUtil.i("更新速度标签: 当前速度 = %s" % game_manager.time_speed)
	if speed == int(speed):
		speed_label.text = "×%d" % speed
	else:
		speed_label.text = "×%.1f" % speed

func _on_speed_up_pressed():
	var speeds = game_manager.speed_levels
	var current = game_manager.time_speed
	var idx = speeds.find(current)
	if idx >= 0 and idx < len(speeds) - 1:
		idx += 1
		game_manager.set_time_speed(speeds[idx])
		_update_speed_label()

func _on_speed_down_pressed():
	var speeds = game_manager.speed_levels
	var current = game_manager.time_speed
	var idx = speeds.find(current)
	if idx > 0:
		idx -= 1
		game_manager.set_time_speed(speeds[idx])
		_update_speed_label()

func _on_build_menu_pressed():
	# 发送打开建筑菜单的信号
	var build_menu = get_node_or_null("/root/Game/UI/BuildMenu")
	if build_menu:
		build_menu.visible = not build_menu.visible
		if build_menu.visible:
			# 重置菜单到初始状态
			build_menu.shortcut_category_active = false
			build_menu.current_category = -1
			build_menu._populate_buildings()
			build_menu.info_panel.visible = false
			build_menu.selected_building = ""
			# 取消所有分类按钮的选中状态
			for i in build_menu.category_tabs.get_child_count():
				build_menu.category_tabs.get_child(i).button_pressed = false

func _on_tech_pressed():
	var tech_panel = get_node_or_null("/root/Game/UI/TechPanel")
	if tech_panel:
		tech_panel.visible = not tech_panel.visible

func _on_work_pressed():
	var work_panel = get_node_or_null("/root/Game/UI/WorkPanel")
	if work_panel:
		work_panel.visible = not work_panel.visible
		if work_panel.visible:
			work_panel._rebuild_grid()

func _on_menu_pressed():
	"""菜单按钮：打开游戏中暂停菜单"""
	var main_menu = get_node_or_null("/root/Game/UI/MainMenu")
	if main_menu:
		main_menu.visible = not main_menu.visible
		if main_menu.visible:
			game_manager.pause_game()

func _on_plant_pressed():
	var plant_panel = get_node_or_null("/root/Game/UI/PlantPanel")
	if plant_panel:
		plant_panel.visible = not plant_panel.visible
		if plant_panel.visible:
			plant_panel._populate_crops()

func _on_notification(msg: String, type: int):
	var notif = notification_scene.instantiate()
	notification_container.add_child(notif)
	notif.show_notification(msg, type)
	# 自动移除
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(notif):
		notif.queue_free()

func _refresh_resource_display():
	"""扫描所有置物架和地面，更新资源数量显示"""
	if not game_manager or resource_container == null:
		return
	
	var game = get_node_or_null("/root/Game")
	
	for res_id in tracked_resources:
		var total = 0
		
		# 1. 统计所有已完成的存储建筑中的物品（使用预索引快查）
		if game and game.building_system:
			total += game.building_system.count_item_in_storage(res_id)
		
		# 2. 统计地面物品
		if game and game.world:
			total += game.world.count_ground_item(res_id)
		
		# 3. 统计所有定居者背包中的物品（可选）
		if game:
			for s in game.settlers:
				if is_instance_valid(s) and s.inventory:
					total += s.inventory.get_item_count(res_id)
		
		var emoji = RESOURCE_EMOJI.get(res_id, "")
		var item_def = ItemDefinitions.get_item(res_id)
		var name_str = item_def.name if item_def else res_id
		
		# 查找或创建标签
		var existing = null
		for child in resource_container.get_children():
			if child.name == res_id:
				existing = child
				break
		
		if existing:
			existing.text = "%s %s: %d" % [emoji, name_str, total]
		else:
			var label = Label.new()
			label.name = res_id
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_constant_override("minimum_font_size", 14)
			label.text = "%s %s: %d" % [emoji, name_str, total]
			resource_container.add_child(label)

func _on_ground_items_changed(_grid_pos: Vector2i):
	"""地面物品变化时实时刷新资源显示"""
	_refresh_resource_display()

# ==================== 事件菜单系统 ====================

# 事件配置列表
var _event_list: Array[Dictionary] = [
	{
		"id": "enemy_raid",
		"name": "⚔️ 敌袭",
		"desc": "从地图边缘生成3名敌对战士，他们会主动攻击你的建筑！",
		"enemy_count": 3,
	},
	{
		"id": "enemy_raid_large",
		"name": "⚔️ 大规模敌袭",
		"desc": "从地图边缘生成6名敌对战士，危险程度更高！",
		"enemy_count": 6,
	},
]

func _populate_event_buttons():
	"""填充事件按钮列表"""
	if not event_button_container:
		return
	
	for child in event_button_container.get_children():
		child.queue_free()
	
	for evt in _event_list:
		var event_frame = VBoxContainer.new()
		
		# 事件标题行
		var title_hbox = HBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = evt.name
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.add_theme_constant_override("minimum_font_size", 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_hbox.add_child(name_label)
		
		event_frame.add_child(title_hbox)
		
		# 描述文字
		var desc_label = Label.new()
		desc_label.text = evt.desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_label.add_theme_constant_override("minimum_font_size", 11)
		event_frame.add_child(desc_label)
		
		# 触发按钮
		var trigger_btn = Button.new()
		trigger_btn.text = "触发事件"
		trigger_btn.custom_minimum_size = Vector2(0, 30)
		trigger_btn.add_theme_constant_override("minimum_font_size", 12)
		trigger_btn.pressed.connect(_on_trigger_event.bind(evt.id, trigger_btn))
		event_frame.add_child(trigger_btn)
		
		# 分隔线
		var separator = HSeparator.new()
		separator.add_theme_color_override("default_color", Color(0.3, 0.3, 0.3, 0.5))
		event_frame.add_child(separator)
		
		event_button_container.add_child(event_frame)

func _on_event_pressed():
	"""事件按钮：切换事件面板显示"""
	if event_panel:
		event_panel.visible = not event_panel.visible

func _on_trigger_event(event_id: String, btn: Button):
	"""触发指定事件"""
	var evt = null
	for e in _event_list:
		if e.id == event_id:
			evt = e
			break
	
	if evt == null:
		return
	
	match event_id:
		"enemy_raid", "enemy_raid_large":
			var game = get_node_or_null("/root/Game")
			if game and game.has_method("trigger_enemy_raid"):
				game.trigger_enemy_raid(evt.enemy_count)
