extends Node
class_name FarmingSystem

signal plot_changed(grid_pos: Vector2i)

class CropDef:
	var id: String
	var name: String
	var grow_time_hours: float
	var harvest_item: String
	var emoji: String

enum PlotState {
	EMPTY,
	PLANTED,
	READY,
}

class FarmPlot:
	var grid_pos: Vector2i
	var crop_id: String
	var state: int = PlotState.EMPTY
	var plant_time: float = 0.0
	var growth_progress: float = 0.0

	func _init(pos: Vector2i, crop: String):
		grid_pos = pos
		crop_id = crop

var plots: Dictionary = {}
var available_crops: Dictionary = {}

var _game: Game
var _gm

func _ready():
	_game = get_node("/root/Game")
	_gm = get_node("/root/GameManager")
	_register_crops()

func _register_crops():
	var rice = CropDef.new()
	rice.id = "rice"
	rice.name = "水稻"
	rice.grow_time_hours = 24.0
	rice.harvest_item = "rice"
	rice.emoji = "🌾"
	available_crops[rice.id] = rice

func get_crop_def(crop_id: String) -> CropDef:
	return available_crops.get(crop_id, null)

func get_available_crops() -> Array:
	return available_crops.values()

func add_plot(grid_pos: Vector2i, crop_id: String) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	if plots.has(key):
		return false
	if _game.world == null:
		return false
	if not _game.world.is_walkable(grid_pos):
		return false
	if _game.building_system and _game.building_system.get_building_at(grid_pos) != null:
		return false
	var plot = FarmPlot.new(grid_pos, crop_id)
	plot.state = PlotState.EMPTY
	plots[key] = plot
	plot_changed.emit(grid_pos)
	return true

func remove_plot(grid_pos: Vector2i):
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	if plots.has(key):
		plots.erase(key)
		plot_changed.emit(grid_pos)

func get_plot(grid_pos: Vector2i) -> FarmPlot:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return plots.get(key, null)

func has_plot(grid_pos: Vector2i) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	return plots.has(key)

func process_farming(delta: float):
	if _gm.state != 1:
		return

	var delta_hours = delta * (24.0 / _gm.day_length)

	for key in plots:
		var plot = plots[key]
		if plot.state != PlotState.PLANTED:
			continue

		var crop = available_crops.get(plot.crop_id)
		if crop == null:
			continue

		plot.growth_progress += delta_hours / crop.grow_time_hours

		if plot.growth_progress >= 1.0:
			plot.state = PlotState.READY
			plot.growth_progress = 1.0
			plot_changed.emit(plot.grid_pos)

func plant_crop(grid_pos: Vector2i) -> bool:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	var plot = plots.get(key, null)
	if plot == null or plot.state != PlotState.EMPTY:
		return false

	plot.state = PlotState.PLANTED
	plot.plant_time = _gm.game_time + _gm.current_day * 24.0
	plot.growth_progress = 0.0
	plot_changed.emit(grid_pos)
	return true

func harvest_crop(grid_pos: Vector2i) -> String:
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	var plot = plots.get(key, null)
	if plot == null or plot.state != PlotState.READY:
		return ""

	var crop = available_crops.get(plot.crop_id)
	if crop == null:
		return ""

	plot.state = PlotState.EMPTY
	plot.growth_progress = 0.0
	plot_changed.emit(grid_pos)
	return crop.harvest_item

func get_plots_needing_planting() -> Array:
	var result: Array = []
	for key in plots:
		var plot = plots[key]
		if plot.state == PlotState.EMPTY:
			result.append(plot)
	return result

func get_plots_ready_for_harvest() -> Array:
	var result: Array = []
	for key in plots:
		var plot = plots[key]
		if plot.state == PlotState.READY:
			result.append(plot)
	return result

func get_all_plots() -> Array:
	var result: Array = []
	for key in plots:
		result.append(plots[key])
	return result

func to_dict() -> Dictionary:
	var data = {}
	for key in plots:
		var plot = plots[key]
		data[key] = {
			"crop_id": plot.crop_id,
			"state": plot.state,
			"plant_time": plot.plant_time,
			"growth_progress": plot.growth_progress,
		}
	return data

func from_dict(data: Dictionary):
	plots.clear()
	for key in data:
		var p = data[key]
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		var plot = FarmPlot.new(pos, p.get("crop_id", "rice"))
		plot.state = p.get("state", PlotState.EMPTY)
		plot.plant_time = p.get("plant_time", 0.0)
		plot.growth_progress = p.get("growth_progress", 0.0)
		plots[key] = plot
