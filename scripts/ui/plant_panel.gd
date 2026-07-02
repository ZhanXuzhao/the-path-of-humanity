extends Panel
class_name PlantPanel

const ItemDefinitions = preload("res://resources/item_definitions.gd")

@onready var crop_list: VBoxContainer = $ScrollContainer/CropList
@onready var close_btn: Button = $CloseBtn

var farming_system
var selected_crop: String = ""

func _ready():
	farming_system = get_node("/root/Game/Systems/FarmingSystem")
	visible = false
	if close_btn:
		close_btn.pressed.connect(func(): visible = false)

func _populate_crops():
	for child in crop_list.get_children():
		child.queue_free()

	var crops = farming_system.get_available_crops()
	for crop in crops:
		var frame = VBoxContainer.new()

		var hbox = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = "%s %s" % [crop.emoji, crop.name]
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.add_theme_constant_override("minimum_font_size", 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)

		frame.add_child(hbox)

		var info_label = Label.new()
		var harvest_item_data = ItemDefinitions.get_item(crop.harvest_item)
		var item_name = harvest_item_data.name if harvest_item_data else crop.harvest_item
		info_label.text = "  成熟时间: 1天  收获: %s" % item_name
		info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		info_label.add_theme_constant_override("minimum_font_size", 11)
		frame.add_child(info_label)

		var select_btn = Button.new()
		select_btn.text = "选择种植"
		select_btn.custom_minimum_size = Vector2(0, 30)
		var crop_id = crop.id
		select_btn.pressed.connect(func():
			_on_crop_selected(crop_id)
		)
		frame.add_child(select_btn)

		var sep = HSeparator.new()
		sep.add_theme_color_override("default_color", Color(0.3, 0.3, 0.3, 0.5))
		frame.add_child(sep)

		crop_list.add_child(frame)

func _on_crop_selected(crop_id: String):
	selected_crop = crop_id
	visible = false

	var game = get_node("/root/Game")
	if game.has_method("enter_plant_mode"):
		var crop_def = farming_system.get_crop_def(crop_id)
		if crop_def:
			game.enter_plant_mode(crop_id)
			var gm = get_node("/root/GameManager")
			if gm:
				gm.show_notification("选择作物: %s，点击地图空地开始种植" % crop_def.name, gm.NotificationType.INFO)
