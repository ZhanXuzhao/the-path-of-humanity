# 选择系统 - Selection System
# 管理定居者、野猪、敌人、建筑、资源、地面物品、格子等对象的选中/取消
extends Node
class_name SelectionSystem

var _game: Game

# 选中敌人
var selected_enemy = null
signal enemy_selected(enemy)
signal enemy_deselected()

# 选中定居者
var selected_settler = null
signal settler_selected(settler)
signal settler_deselected()

# 选中建筑（置物架等）
var selected_building_instance = null
signal building_selected(building_instance)
signal building_deselected()

# 选中在建建筑（施工进度）
var selected_construction_building = null
signal construction_selected(building_instance)
signal construction_deselected()

# 选中资源节点
var selected_resource_pos: Vector2i = Vector2i(-1, -1)
var selected_resource_deposit = null
signal resource_selected(pos: Vector2i, deposit)
signal resource_deselected()

# 选中地面物品
var selected_ground_item_pos: Vector2i = Vector2i(-1, -1)
signal ground_item_selected(pos: Vector2i, stacks)
signal ground_item_deselected()

# 选中空格子（显示地块信息和坐标）
var selected_tile_pos: Vector2i = Vector2i(-1, -1)
signal tile_selected(pos: Vector2i, tile_type: int)
signal tile_deselected()

# 选中野猪
var selected_boar = null
signal boar_selected(boar)
signal boar_deselected()

func _ready():
	_game = get_parent() as Game
	if _game.building_system:
		_game.building_system.building_completed.connect(_on_building_completed)

# -------- 定居者选择 --------
func find_settler_at_pos(global_pos: Vector2):
	var closest = null
	var closest_dist = _game.world.tile_size * 0.6

	for s in _game.settlers:
		if not is_instance_valid(s):
			continue
		var dist = s.position.distance_to(global_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = s

	return closest

func is_settler_at_grid(settler, grid_pos: Vector2i) -> bool:
	if settler == null or not is_instance_valid(settler):
		return false
	var s_grid = Vector2i(
		floori(settler.position.x / _game.world.tile_size),
		floori(settler.position.y / _game.world.tile_size)
	)
	return s_grid == grid_pos

func try_select_settler() -> bool:
	var s = find_settler_at_pos(_game.get_global_mouse_position())
	if s != null:
		select_settler(s)
		return true

	deselect_settler()
	return false

func select_settler(settler, focus_camera: bool = false):
	if selected_settler == settler:
		return
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	deselect_boar()
	deselect_enemy()
	deselect_building()
	deselect_construction()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()
	selected_settler = settler
	settler.set_selected(true)
	settler_selected.emit(settler)
	if focus_camera and _game.camera and is_instance_valid(_game.camera):
		_game.camera.focus_on(settler.position)

func deselect_settler():
	if selected_settler != null and is_instance_valid(selected_settler):
		selected_settler.set_selected(false)
	selected_settler = null
	settler_deselected.emit()

# -------- 野猪选择 --------
func find_boar_at_pos(global_pos: Vector2):
	var closest = null
	var closest_dist = _game.world.tile_size * 0.6

	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(global_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = b

	return closest

func select_boar(boar):
	if selected_boar == boar:
		return
	deselect_boar()
	selected_boar = boar
	boar.set_selected(true)
	boar_selected.emit(boar)
	deselect_settler()
	deselect_enemy()
	deselect_construction()
	deselect_building()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()

func deselect_boar():
	if selected_boar != null and is_instance_valid(selected_boar):
		selected_boar.set_selected(false)
	selected_boar = null
	boar_deselected.emit()

func switch_to_next_settler():
	if _game.settlers.is_empty():
		return

	var valid_settlers = []
	for s in _game.settlers:
		if is_instance_valid(s):
			valid_settlers.append(s)

	if valid_settlers.is_empty():
		return

	var current_idx = -1
	if selected_settler != null and is_instance_valid(selected_settler):
		current_idx = valid_settlers.find(selected_settler)

	var next_idx = (current_idx + 1) % valid_settlers.size()
	select_settler(valid_settlers[next_idx], true)

# -------- 建筑点击选择 --------
func try_select_building():
	var global_pos = _game.get_global_mouse_position()
	var grid_pos = Vector2i(
		floori(global_pos.x / _game.world.tile_size),
		floori(global_pos.y / _game.world.tile_size)
	)
	try_select_building_at(grid_pos)

func try_select_building_at(grid_pos: Vector2i):
	deselect_resource()
	deselect_ground_item()

	var bld = _game.building_system.get_building_at(grid_pos) if _game.building_system else null
	if bld == null:
		deselect_construction()
		deselect_building()
		return

	if bld.is_completed:
		deselect_construction()
		select_building(bld)
		return

	deselect_building()
	select_construction(bld)

func select_building(bld):
	if selected_building_instance == bld:
		return
	deselect_settler()
	deselect_boar()
	deselect_enemy()
	deselect_construction()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()
	selected_building_instance = bld
	building_selected.emit(bld)

func deselect_building():
	selected_building_instance = null
	building_deselected.emit()

func select_construction(bld):
	if selected_construction_building == bld:
		return
	deselect_settler()
	deselect_boar()
	deselect_enemy()
	deselect_building()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()
	selected_construction_building = bld
	construction_selected.emit(bld)

func deselect_construction():
	if selected_construction_building != null:
		selected_construction_building = null
		construction_deselected.emit()

# -------- 资源节点选择 --------
func select_resource(pos: Vector2i, deposit):
	if selected_resource_pos == pos:
		return
	deselect_settler()
	deselect_boar()
	deselect_enemy()
	deselect_building()
	deselect_construction()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()
	selected_resource_pos = pos
	selected_resource_deposit = deposit
	resource_selected.emit(pos, deposit)

func deselect_resource():
	if selected_resource_pos.x >= 0:
		selected_resource_pos = Vector2i(-1, -1)
		selected_resource_deposit = null
		resource_deselected.emit()

# -------- 地面物品选择 --------
func select_ground_item(pos: Vector2i, stacks):
	if selected_ground_item_pos == pos:
		return
	deselect_settler()
	deselect_boar()
	deselect_enemy()
	deselect_building()
	deselect_construction()
	deselect_resource()
	deselect_tile()
	deselect_farm_plot()
	selected_ground_item_pos = pos
	ground_item_selected.emit(pos, stacks)

func deselect_ground_item():
	if selected_ground_item_pos.x >= 0:
		selected_ground_item_pos = Vector2i(-1, -1)
		ground_item_deselected.emit()

# -------- 空格子（地块信息）选择 --------
func select_tile(pos: Vector2i, tile_type: int):
	if selected_tile_pos == pos:
		return
	deselect_settler()
	deselect_boar()
	deselect_enemy()
	deselect_building()
	deselect_construction()
	deselect_resource()
	deselect_ground_item()
	deselect_farm_plot()
	selected_tile_pos = pos
	tile_selected.emit(pos, tile_type)

func deselect_tile():
	if selected_tile_pos.x >= 0:
		selected_tile_pos = Vector2i(-1, -1)
		tile_deselected.emit()

# -------- 农田地块选择 --------
var selected_farm_plot_pos: Vector2i = Vector2i(-1, -1)
var selected_farm_plot = null  # FarmPlot
var selected_farm_plots_group: Array = []  # 多选（双击全选相邻同作物地块）

signal farm_plot_selected(grid_pos: Vector2i, plot)
signal farm_plot_deselected()
signal farm_plots_group_selected(plots: Array)

func select_farm_plot(grid_pos: Vector2i, plot):
	if selected_farm_plot_pos == grid_pos:
		return
	deselect_enemy()
	deselect_boar()
	deselect_settler()
	deselect_construction()
	deselect_building()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()

	selected_farm_plot_pos = grid_pos
	selected_farm_plot = plot
	selected_farm_plots_group = [plot]
	farm_plot_selected.emit(grid_pos, plot)

func select_farm_plots_group(plots: Array):
	if plots.is_empty():
		return
	deselect_enemy()
	deselect_boar()
	deselect_settler()
	deselect_construction()
	deselect_building()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()

	selected_farm_plot_pos = plots[0].grid_pos
	selected_farm_plot = plots[0]
	selected_farm_plots_group = plots
	farm_plots_group_selected.emit(plots)
	farm_plot_selected.emit(plots[0].grid_pos, plots[0])

func deselect_farm_plot():
	if selected_farm_plot_pos.x >= 0:
		selected_farm_plot_pos = Vector2i(-1, -1)
		selected_farm_plot = null
		selected_farm_plots_group = []
		farm_plot_deselected.emit()

# -------- 敌人选择 --------
func find_enemy_at_pos(global_pos: Vector2):
	var closest = null
	var closest_dist = _game.world.tile_size * 0.6

	for e in _game.enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
			continue
		var dist = e.position.distance_to(global_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = e
	return closest

func select_enemy(enemy):
	if selected_enemy == enemy:
		return
	deselect_enemy()
	selected_enemy = enemy
	enemy.set_selected(true)
	enemy_selected.emit(enemy)
	deselect_settler()
	deselect_boar()
	deselect_construction()
	deselect_building()
	deselect_resource()
	deselect_ground_item()
	deselect_tile()
	deselect_farm_plot()

func deselect_enemy():
	if selected_enemy != null and is_instance_valid(selected_enemy):
		selected_enemy.set_selected(false)
	selected_enemy = null
	enemy_deselected.emit()

func get_occupied_grid_positions(exclude_unit = null) -> Dictionary:
	var occupied: Dictionary = {}
	var ts = _game.world.tile_size if _game.world else 32.0

	for s in _game.settlers:
		if not is_instance_valid(s) or s == exclude_unit:
			continue
		var g = Vector2i(floori(s.position.x / ts), floori(s.position.y / ts))
		occupied["%d,%d" % [g.x, g.y]] = true

	for e in _game.enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD or e == exclude_unit:
			continue
		var g = Vector2i(floori(e.position.x / ts), floori(e.position.y / ts))
		occupied["%d,%d" % [g.x, g.y]] = true

	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD or b == exclude_unit:
			continue
		var g = Vector2i(floori(b.position.x / ts), floori(b.position.y / ts))
		occupied["%d,%d" % [g.x, g.y]] = true

	return occupied

func _on_building_completed(pos: Vector2i):
	if selected_construction_building and selected_construction_building.grid_pos == pos:
		deselect_construction()
		var bld = _game.building_system.get_building_at(pos) if _game.building_system else null
		if bld:
			var data = bld.get_data()
			if data and data.storage_capacity > 0 and bld.inventory:
				select_building(bld)
