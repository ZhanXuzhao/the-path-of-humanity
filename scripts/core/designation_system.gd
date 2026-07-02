# 指令标记系统 - Designation System
# 管理标记/清除/拆除模式、资源/野猪/敌人标记、框选操作
extends Node
class_name DesignationSystem

const ItemDefinitions = preload("res://resources/item_definitions.gd")
const WorkManager = preload("res://scripts/autoload/work_manager.gd")
const World = preload("res://scripts/core/world.gd")

var _game: Game

# 标记模式——玩家可标记哪些资源允许采集
var designation_mode: bool = false
var designation_work_type: int = -1  # WorkManager.WorkType

# 清除模式——玩家可框选/点选清除已标记的资源
var clear_mode: bool = false

# 拆除模式——玩家可点击建筑标记为拆除
var demolition_mode: bool = false

# 已标记的资源 {"x,y": work_type}
# 只有被标记的资源才会被定居者采集
var designated_resources: Dictionary = {}

# 已标记的野猪 {boar_instance_id: true} — 狩猎目标
var designated_boars: Dictionary = {}

# 已标记的敌对敌人 {enemy_instance_id: true} — 攻击目标
var designated_enemies: Dictionary = {}

# 已标记的待拆除建筑 {"x,y": true}
var designated_demolitions: Dictionary = {}

signal designation_mode_changed(active: bool, work_type: int)
signal clear_mode_changed(active: bool)
signal demolition_mode_changed(active: bool)
signal designated_resources_changed()

# 框选拖拽状态
var _is_designation_dragging: bool = false
var _drag_start_grid: Vector2i = Vector2i(-999999, -999999)
var _drag_end_grid: Vector2i = Vector2i(-999999, -999999)
var _drag_overlay: Node2D = null

func _ready():
	_game = get_parent() as Game

func process_drag_update():
	"""由 Game._process 调用，更新框选拖拽视觉"""
	if (designation_mode or clear_mode) and _is_designation_dragging:
		var mouse_pos = _game.get_global_mouse_position()
		_drag_end_grid = Vector2i(
			floori(mouse_pos.x / _game.world.tile_size),
			floori(mouse_pos.y / _game.world.tile_size)
		)
		_update_designation_drag_visual()

func _init_drag_overlay():
	if _drag_overlay != null:
		return
	_drag_overlay = Node2D.new()
	_drag_overlay.name = "DragOverlay"
	_drag_overlay.z_index = 200
	_drag_overlay.set_script(preload("res://scripts/core/drag_overlay.gd"))
	_game.add_child(_drag_overlay)
	_game.move_child(_drag_overlay, _game.get_child_count() - 1)

# ==================== 指令标记模式 ====================

func enter_designation_mode(work_type: int):
	if _game.build_mode:
		_game.exit_build_mode()
	if clear_mode:
		exit_clear_mode()

	designation_mode = true
	designation_work_type = work_type
	_is_designation_dragging = false
	_init_drag_overlay()

	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

	designation_mode_changed.emit(true, work_type)

func exit_designation_mode():
	designation_mode = false
	designation_work_type = -1
	_is_designation_dragging = false
	if _drag_overlay:
		_drag_overlay.queue_redraw()
	if _game.world_renderer and _game.world_renderer.has_method("_clear_designation_preview"):
		_game.world_renderer._clear_designation_preview()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	designation_mode_changed.emit(false, -1)

func enter_clear_mode():
	if _game.build_mode:
		_game.exit_build_mode()
	if designation_mode:
		exit_designation_mode()

	clear_mode = true
	_is_designation_dragging = false
	_init_drag_overlay()

	Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)

	clear_mode_changed.emit(true)

func exit_clear_mode():
	clear_mode = false
	_is_designation_dragging = false
	if _drag_overlay:
		_drag_overlay.queue_redraw()
	if _game.world_renderer and _game.world_renderer.has_method("_clear_designation_preview"):
		_game.world_renderer._clear_designation_preview()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	clear_mode_changed.emit(false)

# ==================== 拆除标记模式 ====================

func enter_demolition_mode():
	if _game.build_mode:
		_game.exit_build_mode()
	if designation_mode:
		exit_designation_mode()
	if clear_mode:
		exit_clear_mode()

	demolition_mode = true
	_is_designation_dragging = false
	_init_drag_overlay()

	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

	demolition_mode_changed.emit(true)

func exit_demolition_mode():
	demolition_mode = false
	_is_designation_dragging = false
	if _drag_overlay:
		_drag_overlay.queue_redraw()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	demolition_mode_changed.emit(false)

func toggle_building_demolition(grid_pos: Vector2i) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]

	var bld = _game.building_system.get_building_at(grid_pos) if _game.building_system else null
	if bld == null or not bld.is_completed:
		return false

	var data = bld.get_data()
	if data == null:
		return false

	if designated_demolitions.has(key):
		designated_demolitions.erase(key)
		designated_resources_changed.emit()
		return false
	else:
		designated_demolitions[key] = true
		designated_resources_changed.emit()
		return true

func _toggle_demolition_at_pos(global_pos: Vector2) -> bool:
	var grid_pos = Vector2i(
		floori(global_pos.x / _game.world.tile_size),
		floori(global_pos.y / _game.world.tile_size)
	)
	return toggle_building_demolition(grid_pos)

func toggle_resource_designation(grid_pos: Vector2i) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	var is_auto = (designation_work_type == -2)

	if designation_work_type == WorkManager.WorkType.COMBAT:
		return _toggle_enemy_designation_at(grid_pos)

	if designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
		if _toggle_boar_designation_at(grid_pos):
			return true
		if not is_auto:
			return false

	if designated_resources.has(key):
		if is_auto:
			designated_resources.erase(key)
			designated_resources_changed.emit()
			return false
		else:
			if designated_resources[key] == designation_work_type:
				designated_resources.erase(key)
				designated_resources_changed.emit()
				return false
			else:
				designated_resources[key] = designation_work_type
				designated_resources_changed.emit()
				return true
	else:
		var dep = _game.world.get_resource_at(grid_pos) if _game.world else null
		if dep != null and dep.amount > 0:
			if _is_resource_match_work_type(dep.type, designation_work_type):
				var actual_type = _auto_detect_work_type(dep.type) if is_auto else designation_work_type
				if actual_type >= 0:
					designated_resources[key] = actual_type
					designated_resources_changed.emit()
					return true
		if (designation_work_type == WorkManager.WorkType.HAULING or is_auto) and _game.world:
			var stacks = _game.world.get_ground_items_at(grid_pos)
			if not stacks.is_empty():
				designated_resources[key] = WorkManager.WorkType.HAULING
				designated_resources_changed.emit()
				return true

	return false

func is_resource_designated(grid_pos: Vector2i) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return designated_resources.has(key)

func get_designated_work_type(grid_pos: Vector2i) -> int:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return designated_resources.get(key, -1)

# -------- 野猪标记（狩猎） --------
func _toggle_boar_designation_at(grid_pos: Vector2i) -> bool:
	var tile_center = Vector2(
		grid_pos.x * _game.world.tile_size + _game.world.tile_size / 2.0,
		grid_pos.y * _game.world.tile_size + _game.world.tile_size / 2.0
	)
	var click_dist = _game.world.tile_size * 0.6

	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(tile_center)
		if dist < click_dist:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				designated_resources_changed.emit()
				return false
			else:
				designated_boars[inst_id] = true
				b.is_designated = true
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
	return false

func _toggle_boar_designation_at_pos(global_pos: Vector2) -> bool:
	var click_dist = _game.world.tile_size * 0.6

	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		var dist = b.position.distance_to(global_pos)
		if dist < click_dist:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
			else:
				designated_boars[inst_id] = true
				b.is_designated = true
				b.queue_redraw()
				designated_resources_changed.emit()
				return true
	return false

func is_boar_designated(boar_instance_id: int) -> bool:
	return designated_boars.has(boar_instance_id)

# -------- 敌人标记（攻击） --------
func _toggle_enemy_designation_at(grid_pos: Vector2i) -> bool:
	var tile_center = Vector2(
		grid_pos.x * _game.world.tile_size + _game.world.tile_size / 2.0,
		grid_pos.y * _game.world.tile_size + _game.world.tile_size / 2.0
	)
	return _toggle_enemy_designation_at_pos(tile_center)

func _toggle_enemy_designation_at_pos(global_pos: Vector2) -> bool:
	var click_dist = _game.world.tile_size * 0.6

	for e in _game.enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
			continue
		var dist = e.position.distance_to(global_pos)
		if dist < click_dist:
			var inst_id = e.get_instance_id()
			if designated_enemies.has(inst_id):
				designated_enemies.erase(inst_id)
				e.is_designated = false
				e.queue_redraw()
				designated_resources_changed.emit()
				return true
			else:
				designated_enemies[inst_id] = true
				e.is_designated = true
				e.queue_redraw()
				designated_resources_changed.emit()
				return true
	return false

func is_enemy_designated(enemy_instance_id: int) -> bool:
	return designated_enemies.has(enemy_instance_id)

func clear_all_designations():
	designated_resources.clear()
	designated_demolitions.clear()
	for b in _game.boars:
		if is_instance_valid(b):
			b.is_designated = false
			b.queue_redraw()
	designated_boars.clear()
	for e in _game.enemies:
		if is_instance_valid(e):
			e.is_designated = false
			e.queue_redraw()
	designated_enemies.clear()
	designated_resources_changed.emit()

func clear_designations_by_type(work_type: int):
	var to_remove: Array[String] = []
	for key in designated_resources:
		if designated_resources[key] == work_type:
			to_remove.append(key)
	for key in to_remove:
		designated_resources.erase(key)
	if not to_remove.is_empty():
		designated_resources_changed.emit()

func remove_designation_at(grid_pos: Vector2i):
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	if designated_resources.has(key):
		designated_resources.erase(key)
		designated_resources_changed.emit()

func _auto_detect_work_type(resource_type: int) -> int:
	match resource_type:
		World.ResourceNodeType.STONE_DEPOSIT, World.ResourceNodeType.IRON_DEPOSIT, World.ResourceNodeType.COPPER_DEPOSIT, World.ResourceNodeType.COAL_DEPOSIT:
			return WorkManager.WorkType.MINING
		World.ResourceNodeType.TREE:
			return WorkManager.WorkType.WOODCUTTING
		World.ResourceNodeType.BERRY_BUSH:
			return WorkManager.WorkType.FARMING
		_:
			return -1

func _is_resource_match_work_type(resource_type: int, work_type: int) -> bool:
	match work_type:
		WorkManager.WorkType.MINING:
			return resource_type in [
				World.ResourceNodeType.STONE_DEPOSIT,
				World.ResourceNodeType.IRON_DEPOSIT,
				World.ResourceNodeType.COPPER_DEPOSIT,
				World.ResourceNodeType.COAL_DEPOSIT,
			]
		WorkManager.WorkType.WOODCUTTING:
			return resource_type == World.ResourceNodeType.TREE
		WorkManager.WorkType.FARMING:
			return resource_type == World.ResourceNodeType.BERRY_BUSH
		-2:
			return resource_type in [
				World.ResourceNodeType.STONE_DEPOSIT,
				World.ResourceNodeType.IRON_DEPOSIT,
				World.ResourceNodeType.COPPER_DEPOSIT,
				World.ResourceNodeType.COAL_DEPOSIT,
				World.ResourceNodeType.TREE,
				World.ResourceNodeType.BERRY_BUSH,
			]
		_:
			return false

func _designate_resources_in_rect(from_grid: Vector2i, to_grid: Vector2i):
	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)
	var is_auto = (designation_work_type == -2)

	var tile_size = _game.world.tile_size if _game.world else 32.0
	var rect_pixel_min = Vector2(min_x * tile_size, min_y * tile_size)
	var rect_pixel_max = Vector2((max_x + 1) * tile_size, (max_y + 1) * tile_size)

	if designation_work_type == WorkManager.WorkType.COMBAT:
		var enemy_changed = false
		for e in _game.enemies:
			if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
				continue
			if e.position.x >= rect_pixel_min.x and e.position.x < rect_pixel_max.x \
					and e.position.y >= rect_pixel_min.y and e.position.y < rect_pixel_max.y:
				var inst_id = e.get_instance_id()
				if not designated_enemies.has(inst_id):
					designated_enemies[inst_id] = true
					e.is_designated = true
					e.queue_redraw()
					enemy_changed = true
		if enemy_changed:
			designated_resources_changed.emit()
		return

	var boar_changed = false
	if designation_work_type == WorkManager.WorkType.HUNTING or is_auto:
		for b in _game.boars:
			if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
				continue
			if b.position.x >= rect_pixel_min.x and b.position.x < rect_pixel_max.x \
					and b.position.y >= rect_pixel_min.y and b.position.y < rect_pixel_max.y:
				var inst_id = b.get_instance_id()
				if not designated_boars.has(inst_id):
					designated_boars[inst_id] = true
					b.is_designated = true
					b.queue_redraw()
					boar_changed = true

	if designation_work_type == WorkManager.WorkType.HUNTING:
		if boar_changed:
			designated_resources_changed.emit()
		return

	var changed = false
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var pos = Vector2i(x, y)
			var dep = _game.world.get_resource_at(pos) if _game.world else null
			if dep != null and dep.amount > 0:
				if _is_resource_match_work_type(dep.type, designation_work_type):
					var key = "%d,%d" % [x, y]
					var actual_type = _auto_detect_work_type(dep.type) if is_auto else designation_work_type
					if actual_type >= 0:
						designated_resources[key] = actual_type
						changed = true
			if (designation_work_type == WorkManager.WorkType.HAULING or is_auto) and _game.world:
				var stacks = _game.world.get_ground_items_at(pos)
				if not stacks.is_empty():
					var key = "%d,%d" % [x, y]
					designated_resources[key] = WorkManager.WorkType.HAULING
					changed = true

	if changed or boar_changed:
		designated_resources_changed.emit()

func _remove_designations_in_rect(from_grid: Vector2i, to_grid: Vector2i):
	var min_x = mini(from_grid.x, to_grid.x)
	var max_x = maxi(from_grid.x, to_grid.x)
	var min_y = mini(from_grid.y, to_grid.y)
	var max_y = maxi(from_grid.y, to_grid.y)

	var tile_size = _game.world.tile_size if _game.world else 32.0
	var rect_pixel_min = Vector2(min_x * tile_size, min_y * tile_size)
	var rect_pixel_max = Vector2((max_x + 1) * tile_size, (max_y + 1) * tile_size)

	var enemy_changed = false
	for e in _game.enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
			continue
		if e.position.x >= rect_pixel_min.x and e.position.x < rect_pixel_max.x \
				and e.position.y >= rect_pixel_min.y and e.position.y < rect_pixel_max.y:
			var inst_id = e.get_instance_id()
			if designated_enemies.has(inst_id):
				designated_enemies.erase(inst_id)
				e.is_designated = false
				e.queue_redraw()
				enemy_changed = true

	var boar_changed = false
	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			continue
		if b.position.x >= rect_pixel_min.x and b.position.x < rect_pixel_max.x \
				and b.position.y >= rect_pixel_min.y and b.position.y < rect_pixel_max.y:
			var inst_id = b.get_instance_id()
			if designated_boars.has(inst_id):
				designated_boars.erase(inst_id)
				b.is_designated = false
				b.queue_redraw()
				boar_changed = true

	var changed = false
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var key = "%d,%d" % [x, y]
			if designated_resources.has(key):
				designated_resources.erase(key)
				changed = true
			if designated_demolitions.has(key):
				designated_demolitions.erase(key)
				changed = true

	if changed or boar_changed or enemy_changed:
		designated_resources_changed.emit()

func _update_designation_drag_visual():
	if not _drag_overlay:
		return

	if not _is_designation_dragging or _drag_start_grid.x < -99999 or _drag_end_grid.x < -99999:
		_drag_overlay.visible = false
		return

	_drag_overlay.visible = true

	var min_x = mini(_drag_start_grid.x, _drag_end_grid.x)
	var max_x = maxi(_drag_start_grid.x, _drag_end_grid.x)
	var min_y = mini(_drag_start_grid.y, _drag_end_grid.y)
	var max_y = maxi(_drag_start_grid.y, _drag_end_grid.y)

	var pixel_pos = Vector2(min_x * _game.world.tile_size, min_y * _game.world.tile_size)
	var pixel_size = Vector2(
		(max_x - min_x + 1) * _game.world.tile_size,
		(max_y - min_y + 1) * _game.world.tile_size
	)

	_drag_overlay.set("drag_rect_pos", pixel_pos)
	_drag_overlay.set("drag_rect_size", pixel_size)
	_drag_overlay.set("is_clear_mode", clear_mode)
	_drag_overlay.queue_redraw()

	if designation_mode and _game.world_renderer and _game.world_renderer.has_method("update_designation_preview"):
		_game.world_renderer.update_designation_preview(
			Vector2i(min_x, min_y),
			Vector2i(max_x, max_y),
			designation_work_type,
			false
		)
	if clear_mode and _game.world_renderer and _game.world_renderer.has_method("update_designation_preview"):
		_game.world_renderer.update_designation_preview(
			Vector2i(min_x, min_y),
			Vector2i(max_x, max_y),
			-1,
			true
		)
