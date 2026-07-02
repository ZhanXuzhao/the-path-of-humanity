# 任务系统 - Task System
# 管理定居者AI、任务分配、资源扫描、搬运任务等
extends Node
class_name TaskSystem

const WorkManager = preload("res://scripts/autoload/work_manager.gd")

var _game: Game

# 建筑建造重试冷却（防止反复给同一缺物资建筑分配任务）
var _construction_retry_cooldown: Dictionary = {}

# 资源采集占用标记——防止多个定居者被分配到同一资源
var _claimed_harvest_resources: Dictionary = {}

func _ready():
	_game = get_parent() as Game

func process_tick(elapsed: float):
	_update_settlers(elapsed)
	_assign_ai_tasks()
	_handle_idle_sleep()
	_cleanup_depleted_designations()

func get_idle_settlers() -> Array:
	var idle: Array[Settler] = []
	for s in _game.settlers:
		if s.state == Settler.SettlerState.IDLE:
			idle.append(s)
	return idle

func get_settler_by_id(id: String):
	for s in _game.settlers:
		if s.settler_id == id:
			return s
	return null

func _update_settlers(delta):
	var delta_hours = delta * (24.0 / _game._gm.day_length)

	for s in _game.settlers:
		if not is_instance_valid(s):
			continue

		s.update_needs(delta_hours)
		s.apply_passive_heal(delta_hours)

		if s.state != Settler.SettlerState.IDLE:
			continue

		if s.needs.get("hunger", 100) < 25:
			s.try_eat()
			continue

		if s.is_overweight():
			s._auto_store_overweight()
			continue

	_cleanup_harvest_claims()

func _handle_idle_sleep():
	var is_night = not _game._gm.is_daytime()
	for s in _game.settlers:
		if not is_instance_valid(s):
			continue
		if s.state != Settler.SettlerState.IDLE:
			continue
		var rest = s.needs.get("rest", 100)
		if rest < 30.0 or is_night:
			LogUtil.info(s, "IDLE -> sleep (rest=%.1f, night=%s)" % [rest, is_night])
			var home = s.find_nearest_residential()
			if not home.is_empty():
				s.try_sleep(home.pos, home.world_pos)
				continue
			s.try_sleep(Vector2i.ZERO, s.position)

func _assign_ai_tasks():
	var idle_settlers = get_idle_settlers()
	if idle_settlers.is_empty():
		return

	var work_manager = get_node_or_null("/root/WorkManager")

	var current_frame = Engine.get_physics_frames()
	var expired_keys = []
	for key in _construction_retry_cooldown:
		if current_frame - _construction_retry_cooldown[key] > 300:
			expired_keys.append(key)
	for key in expired_keys:
		_construction_retry_cooldown.erase(key)

	var tasks = []

	var uncompleted = _game.building_system.get_uncompleted_buildings() if _game.building_system else []
	for bld in uncompleted:
		var data = bld.get_data()
		if data == null:
			continue

		var bld_key = "%d,%d" % [bld.grid_pos.x, bld.grid_pos.y]

		if _construction_retry_cooldown.has(bld_key):
			continue

		if not bld.is_materials_ready():
			var has_any_material = false
			var missing = bld.get_missing_materials()
			var any_auto_queued = false
			for mat_id in missing.keys():
				if _has_material_in_storage(mat_id):
					has_any_material = true
					break
				if _game.world and _game.world.has_ground_item(mat_id, 1):
					has_any_material = true
					break
				# 尝试自动生产缺失的中间材料（木板、铁锭等）
				if _game.crafting_system and _game.crafting_system.auto_queue_production_for_item(mat_id, missing[mat_id]):
					any_auto_queued = true
			if not has_any_material:
				if any_auto_queued:
					_construction_retry_cooldown[bld_key] = current_frame - 240
				else:
					_construction_retry_cooldown[bld_key] = current_frame
				continue

		var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		tasks.append({
			"id": "construct_%d_%d" % [bld.grid_pos.x, bld.grid_pos.y],
			"type": "CONSTRUCT",
			"target_pos": bld.grid_pos,
			"target_world_pos": center_pixel,
			"skill": "construction",
			"work_required": data.work_cost - bld.construction_progress if data else 10.0,
			"work_type": WorkManager.WorkType.CONSTRUCTION,
		})

	if _game.crafting_system:
		var pending_jobs = _game.crafting_system.get_pending_crafting_jobs()
		for job in pending_jobs:
			var bld = _game.building_system.get_building_at(job.building_pos) if _game.building_system else null
			if bld == null:
				continue
			var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
			var recipe = job.get_recipe()
			tasks.append({
				"id": "craft_%d_%d_%s" % [job.building_pos.x, job.building_pos.y, job.recipe_id],
				"type": "CRAFT",
				"target_pos": job.building_pos,
				"target_world_pos": center_pixel,
				"building_pos": job.building_pos,
				"recipe_id": job.recipe_id,
				"skill": "crafting",
				"work_required": recipe.work_time if recipe else 5.0,
				"crafting_job": job,
				"work_type": WorkManager.WorkType.CRAFTING,
			})

	var haul_tasks = _scan_material_hauling_tasks(idle_settlers)
	tasks.append_array(haul_tasks)

	var ground_cleanup_tasks = _scan_ground_item_storage_tasks(idle_settlers, haul_tasks)
	tasks.append_array(ground_cleanup_tasks)

	var hunting_tasks = _scan_hunting_targets(idle_settlers)
	tasks.append_array(hunting_tasks)

	var combat_tasks = _scan_enemy_combat_targets(idle_settlers)
	tasks.append_array(combat_tasks)

	var repair_tasks = _scan_repair_tasks(idle_settlers)
	tasks.append_array(repair_tasks)

	var demolition_tasks = _scan_demolition_tasks()
	tasks.append_array(demolition_tasks)

	var harvest_tasks = _scan_nearby_resources(idle_settlers)
	tasks.append_array(harvest_tasks)

	var farm_plant_tasks = _scan_farm_plant_tasks(idle_settlers)
	tasks.append_array(farm_plant_tasks)

	var farm_harvest_tasks = _scan_farm_harvest_tasks(idle_settlers)
	tasks.append_array(farm_harvest_tasks)

	if tasks.is_empty():
		return

	for settler in idle_settlers:
		if tasks.is_empty():
			break

		if settler.is_overweight():
			continue

		var sid = settler.settler_id

		var best_task = null
		var best_score = INF
		var best_idx = -1
		var best_priority = 0

		for i in range(tasks.size()):
			var t = tasks[i]

			var pri = 0
			if work_manager:
				var wt = t.get("work_type", -1)
				if wt >= 0:
					pri = work_manager.get_priority(sid, wt)

			if pri <= 0:
				continue

			if t.get("type") == "CRAFT":
				var job = t.get("crafting_job")
				if job and job.assigned_settler_id != "":
					continue
				var building_pos = t.get("building_pos", Vector2i.ZERO)
				if building_pos != Vector2i.ZERO and _game.crafting_system.is_building_occupied(building_pos):
					continue

			if t.get("type") == "CONSTRUCT" and settler._construction_retry_count >= settler.MAX_CONSTRUCTION_RETRIES:
				continue

			var task_pos = t.get("target_world_pos", Vector2.ZERO)
			var dist = settler.position.distance_squared_to(task_pos) if task_pos != Vector2.ZERO else 0

			var score = dist / (pri * pri * 2.0)

			if pri > best_priority or (pri == best_priority and score < best_score):
				best_priority = pri
				best_score = score
				best_task = t
				best_idx = i

		if best_task == null:
			continue

		if best_task.get("type") == "CRAFT":
			var job = best_task.get("crafting_job")
			if job:
				job.assigned_settler_id = settler.settler_id

		if best_task.get("type") == "HARVEST":
			var target_pos: Vector2i = best_task.get("target_pos", Vector2i.ZERO)
			var res_key = "%d,%d" % [target_pos.x, target_pos.y]
			_claimed_harvest_resources[res_key] = settler.settler_id

		tasks.remove_at(best_idx)
		settler.assign_task(best_task)
		LogUtil.d("settler.assign_task(best_task): %s -> %s" % [settler.settler_name, best_task.get("id", "")])

func _scan_hunting_targets(_idle_settlers: Array) -> Array:
	var result: Array = []
	if _game.designation_system.designated_boars.is_empty():
		return result

	for b in _game.boars:
		if not is_instance_valid(b) or b.state == b.BoarState.DEAD:
			var dead_id = b.get_instance_id() if is_instance_valid(b) else 0
			if _game.designation_system.designated_boars.has(dead_id):
				_game.designation_system.designated_boars.erase(dead_id)
			continue

		var inst_id = b.get_instance_id()
		if not _game.designation_system.designated_boars.has(inst_id):
			continue

		result.append({
			"id": "hunt_%d" % inst_id,
			"type": "HUNTING",
			"target_pos": Vector2i.ZERO,
			"target_world_pos": b.position,
			"skill": "combat",
			"work_required": 10.0,
			"work_type": WorkManager.WorkType.HUNTING,
			"boar_instance_id": inst_id,
		})

	return result

func _scan_enemy_combat_targets(_idle_settlers: Array) -> Array:
	var result: Array = []
	if _game.designation_system.designated_enemies.is_empty():
		return result

	for e in _game.enemies:
		if not is_instance_valid(e) or e.state == e.EnemyState.DEAD:
			var dead_id = e.get_instance_id() if is_instance_valid(e) else 0
			if _game.designation_system.designated_enemies.has(dead_id):
				_game.designation_system.designated_enemies.erase(dead_id)
			continue

		var inst_id = e.get_instance_id()
		if not _game.designation_system.designated_enemies.has(inst_id):
			continue

		result.append({
			"id": "combat_%d" % inst_id,
			"type": "COMBAT",
			"target_pos": Vector2i.ZERO,
			"target_world_pos": e.position,
			"skill": "combat",
			"work_required": 10.0,
			"work_type": WorkManager.WorkType.COMBAT,
			"enemy_instance_id": inst_id,
		})

	return result

func _scan_repair_tasks(_idle_settlers: Array) -> Array:
	var result: Array = []
	if not _game.building_system:
		return result

	var damaged = _game.building_system.get_damaged_buildings()
	if damaged.is_empty():
		return result

	for bld in damaged:
		var damage_pct = float(bld.max_hp - bld.hp) / float(bld.max_hp)
		var work_needed = 10.0 + damage_pct * 20.0
		var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)

		if not bld.is_completed:
			continue

		result.append({
			"id": "repair_%d_%d" % [bld.grid_pos.x, bld.grid_pos.y],
			"type": "REPAIR",
			"target_pos": bld.grid_pos,
			"target_world_pos": center_pixel,
			"skill": "construction",
			"work_required": work_needed,
			"work_type": WorkManager.WorkType.REPAIR,
		})

	return result

func _scan_demolition_tasks() -> Array:
	var result: Array = []
	if not _game.building_system or _game.designation_system.designated_demolitions.is_empty():
		return result

	for key in _game.designation_system.designated_demolitions:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		var bld = _game.building_system.get_building_at(grid_pos)
		if bld == null:
			continue

		if not bld.is_completed:
			continue

		var center_pixel = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		result.append({
			"id": "demolish_%d_%d" % [grid_pos.x, grid_pos.y],
			"type": "DEMOLISH",
			"target_pos": bld.grid_pos,
			"target_world_pos": center_pixel,
			"skill": "construction",
			"work_required": bld.max_hp,
			"work_type": WorkManager.WorkType.CONSTRUCTION,
		})

	return result

func _scan_nearby_resources(idle_settlers: Array) -> Array:
	var result: Array = []
	var scanned_chunks: Dictionary = {}

	var search_radius = 5
	if idle_settlers.is_empty():
		return result

	var center_chunk = _game.world.global_to_chunk(Vector2i(
		floori(idle_settlers[0].position.x / _game.world.tile_size),
		floori(idle_settlers[0].position.y / _game.world.tile_size)
	))

	for cx in range(center_chunk.x - search_radius, center_chunk.x + search_radius + 1):
		for cy in range(center_chunk.y - search_radius, center_chunk.y + search_radius + 1):
			var chunk_pos = Vector2i(cx, cy)
			if scanned_chunks.has(chunk_pos):
				continue
			scanned_chunks[chunk_pos] = true

			var chunk = _game.world.chunks.get(chunk_pos)
			if chunk == null or not chunk.is_generated:
				continue

			for local_pos in chunk.resources:
				var dep = chunk.resources[local_pos]
				if dep.amount <= 0:
					continue

				var global_pos = chunk_pos * _game.world.CHUNK_SIZE + local_pos
				var res_key = "%d,%d" % [global_pos.x, global_pos.y]

				if _claimed_harvest_resources.has(res_key):
					continue

				if not _game.designation_system.designated_resources.has(res_key):
					continue

				var world_pos = _grid_to_world(global_pos)
				var item_id = dep.get_item_drop()

				var work_type = WorkManager.WorkType.WOODCUTTING
				match dep.type:
					_game.world.ResourceNodeType.STONE_DEPOSIT, _game.world.ResourceNodeType.IRON_DEPOSIT, _game.world.ResourceNodeType.COPPER_DEPOSIT, _game.world.ResourceNodeType.COAL_DEPOSIT:
						work_type = WorkManager.WorkType.MINING
					_game.world.ResourceNodeType.BERRY_BUSH:
						work_type = WorkManager.WorkType.FARMING

				result.append({
					"id": "harvest_%d_%d" % [global_pos.x, global_pos.y],
					"type": "HARVEST",
					"target_pos": global_pos,
					"target_world_pos": world_pos,
					"resource_type": dep.type,
					"harvest_item": item_id,
					"work_required": dep.harvest_time,
					"work_type": work_type,
				})

	return result

func _scan_farm_plant_tasks(_idle_settlers: Array) -> Array:
	var result: Array = []
	if _game.farming_system == null:
		return result

	var plots = _game.farming_system.get_plots_needing_planting()
	for plot in plots:
		var world_pos = _grid_to_world(plot.grid_pos)
		result.append({
			"id": "plant_%d_%d" % [plot.grid_pos.x, plot.grid_pos.y],
			"type": "PLANT",
			"target_pos": plot.grid_pos,
			"target_world_pos": world_pos,
			"crop_id": plot.crop_id,
			"skill": "farming",
			"work_required": 5.0,
			"work_type": WorkManager.WorkType.FARMING,
		})

	return result

func _scan_farm_harvest_tasks(_idle_settlers: Array) -> Array:
	var result: Array = []
	if _game.farming_system == null:
		return result

	var plots = _game.farming_system.get_plots_ready_for_harvest()
	for plot in plots:
		var world_pos = _grid_to_world(plot.grid_pos)
		result.append({
			"id": "harvest_farm_%d_%d" % [plot.grid_pos.x, plot.grid_pos.y],
			"type": "HARVEST_FARM",
			"target_pos": plot.grid_pos,
			"target_world_pos": world_pos,
			"crop_id": plot.crop_id,
			"skill": "farming",
			"work_required": 5.0,
			"work_type": WorkManager.WorkType.FARMING,
		})

	return result

func _scan_material_hauling_tasks(_settlers: Array) -> Array:
	var result: Array = []
	if _game.building_system == null:
		return result

	var haul_tasks_added: Dictionary = {}

	for bld in _game.building_system.get_uncompleted_buildings():
		if bld.is_materials_ready():
			continue
		var missing = bld.get_missing_materials()

		for mat_id in missing.keys():
			var needed = missing[mat_id]
			var task_key = "haul_construct_%d_%d_%s" % [bld.grid_pos.x, bld.grid_pos.y, mat_id]
			if haul_tasks_added.has(task_key):
				continue

			var source_pos = _find_material_source(mat_id)
			if source_pos == null:
				continue

			haul_tasks_added[task_key] = true
			var source_world_pos = source_pos.world_pos if source_pos.has("world_pos") else Vector2.ZERO
			result.append({
				"id": task_key,
				"type": "HAUL_CONSTRUCT",
				"target_pos": bld.grid_pos,
				"target_world_pos": source_world_pos,
				"target_bld_pos": bld.grid_pos,
				"source_type": source_pos.type,
				"source_bld_pos": source_pos.get("bld_pos", Vector2i.ZERO),
				"item_id": mat_id,
				"amount": needed,
				"haul_phase": "fetch",
				"skill": "",
				"work_type": WorkManager.WorkType.HAULING,
			})

	for bld in _game.building_system.get_completed_production_buildings():
		var data = bld.get_data()
		if data == null or data.consumes.is_empty():
			continue

		for mat_id in data.consumes:
			var needed = data.consumes[mat_id]
			if bld.inventory != null and bld.inventory.has_item(mat_id, needed):
				continue

			var task_key = "haul_prod_%d_%d_%s" % [bld.grid_pos.x, bld.grid_pos.y, mat_id]
			if haul_tasks_added.has(task_key):
				continue

			var source_pos = _find_material_source(mat_id)
			if source_pos == null:
				continue

			haul_tasks_added[task_key] = true
			var source_world_pos = source_pos.world_pos if source_pos.has("world_pos") else Vector2.ZERO
			result.append({
				"id": task_key,
				"type": "HAUL_CONSTRUCT",
				"target_pos": bld.grid_pos,
				"target_world_pos": source_world_pos,
				"target_bld_pos": bld.grid_pos,
				"source_type": source_pos.type,
				"source_bld_pos": source_pos.get("bld_pos", Vector2i.ZERO),
				"item_id": mat_id,
				"amount": needed,
				"haul_phase": "fetch",
				"skill": "",
				"work_type": WorkManager.WorkType.HAULING,
			})

	return result

func _scan_ground_item_storage_tasks(_idle_settlers: Array, existing_haul_tasks: Array) -> Array:
	if _game.building_system == null or _game.world == null:
		return []

	var already_claimed: Dictionary = {}
	for t in existing_haul_tasks:
		if t.get("source_type") == "ground":
			var src_pos = t.get("source_bld_pos", Vector2i.ZERO)
			var item = t.get("item_id", "")
			if item != "":
				already_claimed["%s@%d,%d" % [item, src_pos.x, src_pos.y]] = true

	var storage_rack_list = _game.building_system.get_storage_buildings_with_space()
	if storage_rack_list.is_empty():
		return []

	var result: Array = []

	for pos in _game.world.ground_items:
		var stacks = _game.world.ground_items[pos]
		if stacks.is_empty():
			continue

		var haul_key = "%d,%d" % [pos.x, pos.y]
		if not _game.designation_system.designated_resources.is_empty() and not _game.designation_system.designated_resources.has(haul_key):
			continue

		for stack in stacks:
			if stack.amount <= 0:
				continue

			var item_id = stack.item_id
			var claim_key = "%s@%d,%d" % [item_id, pos.x, pos.y]
			if already_claimed.has(claim_key):
				continue

			var best_storage = null
			var best_dist = INF
			var ground_world = _grid_to_world(pos)

			for bld in storage_rack_list:
				if bld.inventory == null or bld.inventory.is_full():
					continue
				var bld_center = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
				var dist = ground_world.distance_squared_to(bld_center)
				if dist < best_dist:
					best_dist = dist
					best_storage = bld

			if best_storage == null:
				continue

			already_claimed[claim_key] = true

			var to_haul = mini(stack.amount, 50)
			result.append({
				"id": "ground_store_%s_%d_%d" % [item_id, pos.x, pos.y],
				"type": "HAUL_CONSTRUCT",
				"target_pos": best_storage.grid_pos,
				"target_world_pos": _grid_to_world(pos),
				"target_bld_pos": best_storage.grid_pos,
				"source_type": "ground",
				"source_bld_pos": pos,
				"item_id": item_id,
				"amount": to_haul,
				"haul_phase": "fetch",
				"skill": "",
				"work_type": WorkManager.WorkType.HAULING,
			})

	return result

func _find_material_source(item_id: String):
	if _game.building_system == null:
		return null

	var best_bld = null
	var best_dist = INF
	var storage_blds = _game.building_system.get_storage_buildings_with_item(item_id, 1)
	for bld in storage_blds:
		var center = _grid_to_world(bld.grid_pos + bld.get_size() / 2)
		var dist = center.length_squared()
		if dist < best_dist:
			best_dist = dist
			best_bld = bld

	if best_bld != null:
		return {
			"type": "storage",
			"bld_pos": best_bld.grid_pos,
			"world_pos": _grid_to_world(best_bld.grid_pos + best_bld.get_size() / 2)
		}

	if _game.world:
		var ground_positions = _game.world.get_all_ground_positions_of(item_id)
		if not ground_positions.is_empty():
			var best_grid = ground_positions[0]
			best_dist = INF
			for gp in ground_positions:
				var center = _grid_to_world(gp)
				var dist = center.length_squared()
				if dist < best_dist:
					best_dist = dist
					best_grid = gp
			return {
				"type": "ground",
				"bld_pos": best_grid,
				"grid_pos": best_grid,
				"world_pos": _grid_to_world(best_grid)
			}

	return null

func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _game.world.tile_size + _game.world.tile_size / 2.0,
		grid_pos.y * _game.world.tile_size + _game.world.tile_size / 2.0
	)

func _has_material_in_storage(item_id: String) -> bool:
	if _game.building_system == null:
		return false
	return not _game.building_system.get_storage_buildings_with_item(item_id, 1).is_empty()

func claim_harvest_resource(grid_pos: Vector2i, settler_id: String):
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	_claimed_harvest_resources[key] = settler_id

func release_harvest_resource(grid_pos: Vector2i):
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	_claimed_harvest_resources.erase(key)

func _cleanup_depleted_designations():
	var to_remove: Array[String] = []
	for res_key in _game.designation_system.designated_resources:
		var parts = res_key.split(",")
		if parts.size() != 2:
			to_remove.append(res_key)
			continue
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		var wt = _game.designation_system.designated_resources[res_key]

		if wt == WorkManager.WorkType.HAULING:
			if _game.world:
				var stacks = _game.world.get_ground_items_at(grid_pos)
				if stacks.is_empty():
					to_remove.append(res_key)
			continue

		if _game.world:
			var dep = _game.world.get_resource_at(grid_pos)
			if dep == null or dep.amount <= 0:
				to_remove.append(res_key)
				continue

	for key in to_remove:
		_game.designation_system.designated_resources.erase(key)
	if not to_remove.is_empty():
		_game.designation_system.designated_resources_changed.emit()

	var demo_to_remove: Array[String] = []
	for key in _game.designation_system.designated_demolitions:
		var parts = key.split(",")
		if parts.size() != 2:
			demo_to_remove.append(key)
			continue
		var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
		if _game.building_system:
			var bld = _game.building_system.get_building_at(grid_pos)
			if bld == null:
				demo_to_remove.append(key)
	for key in demo_to_remove:
		_game.designation_system.designated_demolitions.erase(key)
	if not demo_to_remove.is_empty():
		_game.designation_system.designated_resources_changed.emit()

func _cleanup_harvest_claims():
	var expired_keys: Array = []
	for res_key in _claimed_harvest_resources:
		var claim_settler_id = _claimed_harvest_resources[res_key]
		var settler = get_settler_by_id(claim_settler_id)
		if settler == null or not is_instance_valid(settler):
			expired_keys.append(res_key)
			continue
		if settler.current_task == null or settler.current_task.get("type", "") != "HARVEST":
			expired_keys.append(res_key)
			continue
		var task_target = settler.current_task.get("target_pos", Vector2i.ZERO)
		var task_key = "%d,%d" % [task_target.x, task_target.y]
		if task_key != res_key:
			expired_keys.append(res_key)
			continue
		if _game.world:
			var parts = res_key.split(",")
			var grid_pos = Vector2i(int(parts[0]), int(parts[1]))
			var dep = _game.world.get_resource_at(grid_pos)
			if dep == null or dep.amount <= 0:
				expired_keys.append(res_key)
				continue

	for key in expired_keys:
		_claimed_harvest_resources.erase(key)
