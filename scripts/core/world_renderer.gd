# 世界渲染器 - World Renderer
# 负责使用 SVG 纹理绘制地图、资源和建筑
extends Node2D
class_name WorldRenderer

const _ID = preload("res://resources/item_definitions.gd")
const _TG = preload("res://scripts/core/texture_generator.gd")

@onready var world: World = get_parent()
@onready var building_system = get_node("/root/Game/Systems/BuildingSystem")

# 瓦片纹理映射
var tile_textures: Dictionary = {}

# 资源纹理映射
var resource_textures: Dictionary = {}

# 建筑纹理映射
var building_textures: Dictionary = {}

# 角色纹理
var settler_texture: Texture2D

# 当前可见的精灵节点
var tile_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var resource_sprites: Dictionary = {}  # Vector2i -> Sprite2D
var building_sprites: Dictionary = {}  # Vector2i -> Sprite2D

func _ready():
	# 使用 TextureGenerator 生成所有纹理
	var all_textures = _TG.generate_all()
	tile_textures = all_textures["tiles"]
	resource_textures = all_textures["resources"]
	building_textures = all_textures["buildings"]
	settler_texture = all_textures["character"]["settler"]
	
	# 连接信号
	world.tile_changed.connect(_on_tile_changed)
	world.resource_depleted.connect(_on_resource_depleted)
	
	# 连接建筑系统信号
	if building_system:
		building_system.building_placed.connect(_on_building_placed)
		building_system.building_removed.connect(_on_building_removed)
	
	# 延迟一帧渲染，确保 Game._ready() 已完成区块生成
	call_deferred("_render_existing_chunks")
	
	# 强制触发 _draw()
	queue_redraw()



func _render_existing_chunks():
	"""渲染所有已生成的区块"""
	for chunk_pos in world.chunks:
		var chunk = world.chunks[chunk_pos]
		if not chunk.is_generated:
			continue
		var chunk_origin = chunk_pos * World.CHUNK_SIZE
		for tile_pos in chunk.tiles:
			var global_pos = chunk_origin + tile_pos
			_render_tile(global_pos, chunk.tiles[tile_pos])
		for res_pos in chunk.resources:
			var global_pos = chunk_origin + res_pos
			_render_resource(global_pos, chunk.resources[res_pos])
		for bld_pos in chunk.buildings:
			var global_pos = chunk_origin + bld_pos
			var bld_id = chunk.buildings[bld_pos]
			var bld_instance = building_system.get_building_at(global_pos) if building_system else null
			if bld_instance and bld_instance.grid_pos == global_pos:
				_render_building(global_pos, bld_id)

func _render_tile(pos: Vector2i, tile_type: int):
	"""渲染单个瓦片"""
	var key = pos
	if tile_sprites.has(key):
		return
	
	var tex = tile_textures.get(tile_type)
	if tex == null:
		return
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	var pixel_pos = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(world.tile_size / 2.0, world.tile_size / 2.0)
	sprite.position = pixel_pos
	sprite.scale = Vector2(world.tile_size / 32.0, world.tile_size / 32.0)
	sprite.z_index = 0
	add_child(sprite)
	tile_sprites[key] = sprite

func _render_resource(pos: Vector2i, deposit: World.ResourceDeposit):
	"""渲染资源节点"""
	var key = pos
	if resource_sprites.has(key):
		return
	
	var tex = resource_textures.get(deposit.type)
	if tex == null:
		return
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	var pixel_pos = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(world.tile_size / 2.0, world.tile_size / 2.0)
	sprite.position = pixel_pos
	# 资源比瓦片稍大
	sprite.scale = Vector2(0.7, 0.7)
	sprite.z_index = 1
	add_child(sprite)
	resource_sprites[key] = sprite

func render_building_at(pos: Vector2i, building_id: String):
	"""渲染建筑（从外部调用）"""
	_render_building(pos, building_id)

func _render_building(pos: Vector2i, building_id: String):
	"""渲染建筑"""
	var key = pos
	if building_sprites.has(key):
		return
	
	var tex = building_textures.get(building_id)
	if tex == null:
		return
	
	var data = _ID.get_building(building_id)
	var size = data.size if data else Vector2i.ONE
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	# 建筑以格子为单位居中
	var center = Vector2(pos.x * world.tile_size, pos.y * world.tile_size) + Vector2(size.x * world.tile_size / 2.0, size.y * world.tile_size / 2.0)
	sprite.position = center
	# 根据建筑大小调整缩放
	sprite.scale = Vector2(world.tile_size / 32.0, world.tile_size / 32.0)
	sprite.z_index = 2
	add_child(sprite)
	building_sprites[key] = sprite

func _on_tile_changed(pos: Vector2i, tile_type: int):
	"""瓦片变化时更新渲染"""
	# 移除旧的精灵
	var key = pos
	if tile_sprites.has(key):
		tile_sprites[key].queue_free()
		tile_sprites.erase(key)
	_render_tile(pos, tile_type)

func _on_resource_depleted(pos: Vector2i):
	"""资源耗尽时移除精灵"""
	var key = pos
	if resource_sprites.has(key):
		resource_sprites[key].queue_free()
		resource_sprites.erase(key)

func _on_building_placed(building_id: String, pos: Vector2i):
	"""建筑放置时渲染"""
	_render_building(pos, building_id)

func _on_building_removed(building_id: String, pos: Vector2i):
	"""建筑移除时清除精灵"""
	var data = _ID.get_building(building_id)
	var size = data.size if data else Vector2i.ONE
	for x in size.x:
		for y in size.y:
			clear_building(pos + Vector2i(x, y))

func clear_building(pos: Vector2i):
	"""清除建筑精灵"""
	var key = pos
	if building_sprites.has(key):
		building_sprites[key].queue_free()
		building_sprites.erase(key)

func clear_all():
	"""清除所有精灵"""
	for s in tile_sprites.values():
		s.queue_free()
	tile_sprites.clear()
	for s in resource_sprites.values():
		s.queue_free()
	resource_sprites.clear()
	for s in building_sprites.values():
		s.queue_free()
	building_sprites.clear()
