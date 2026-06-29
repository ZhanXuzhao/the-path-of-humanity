# 科技面板 - Tech Panel
# 显示科技树和研究界面
extends Panel
class_name TechPanel

@onready var tech_list: VBoxContainer = $ScrollContainer/TechList
@onready var current_label: Label = $CurrentResearch/CurrentLabel
@onready var progress_bar: ProgressBar = $CurrentResearch/ProgressBar
@onready var close_btn: Button = $CloseBtn

var tech_system: TechSystem

func _ready():
	tech_system = get_node("/root/Game/Systems/TechSystem")
	visible = false
	close_btn.pressed.connect(func(): visible = false)
	
	# 连接科技信号
	tech_system.research_started.connect(_on_research_started)
	tech_system.research_completed.connect(_on_research_completed)
	
	_populate_techs()

func _process(_delta):
	# 更新当前研究进度
	if tech_system and tech_system.current_research:
		var project = tech_system.current_research
		var total = project.get_total_time()
		if total > 0:
			progress_bar.value = project.progress / total * 100.0
			current_label.text = "正在研究: %s (%.1f%%)" % [project.get_data().name, progress_bar.value]
	else:
		progress_bar.value = 0
		current_label.text = "当前无研究"

func _populate_techs():
	for child in tech_list.get_children():
		child.queue_free()
	
	var categories = ["基础", "工业", "科学"]
	for cat in categories:
		var cat_label = Label.new()
		cat_label.text = "--- %s ---" % cat
		cat_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
		tech_list.add_child(cat_label)
		
		for tech_id in ItemDefinitions.techs:
			var data = ItemDefinitions.techs[tech_id]
			if data.category != cat:
				continue
			
			var can = tech_system.can_research(tech_id)
			var researched = tech_system.is_tech_researched(tech_id)
			
			var hbox = HBoxContainer.new()
			var btn = Button.new()
			btn.text = data.name
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			if researched:
				btn.disabled = true
				btn.text += " ✓"
			elif not can.can:
				btn.disabled = true
				btn.modulate = Color(0.5, 0.5, 0.5)
			else:
				btn.pressed.connect(_on_research_btn.bind(tech_id))
			
			var cost_label = Label.new()
			var cost_text = ""
			for mat_id in data.cost:
				var mat_data = ItemDefinitions.get_item(mat_id)
				cost_text += "%s×%d " % [mat_data.name, data.cost[mat_id]]
			cost_label.text = cost_text
			cost_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			
			hbox.add_child(btn)
			hbox.add_child(cost_label)
			tech_list.add_child(hbox)

func _on_research_btn(tech_id: String):
	if tech_system.start_research(tech_id):
		_populate_techs()

func _on_research_started(tech_id: String):
	GameManager.show_notification("开始研究: " + ItemDefinitions.get_tech(tech_id).name,
		GameManager.NotificationType.RESEARCH)
	_populate_techs()

func _on_research_completed(tech_id: String):
	var data = ItemDefinitions.get_tech(tech_id)
	var unlocks_text = ""
	for unlock in data.unlocks:
		if ItemDefinitions.buildings.has(unlock):
			unlocks_text += ItemDefinitions.buildings[unlock].name + " "
		elif ItemDefinitions.recipes.has(unlock):
			unlocks_text += ItemDefinitions.recipes[unlock].name + " "
	
	GameManager.show_notification("科技完成: %s! 解锁: %s" % [data.name, unlocks_text],
		GameManager.NotificationType.RESEARCH)
	_populate_techs()
