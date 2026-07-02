# 箭矢投射物 - Arrow Projectile
# 从射手飞向目标的飞行物，击中目标后造成伤害并消失
extends Node2D
class_name ArrowProjectile

const ARROW_TEXTURE_PATH := "res://assets/art/creatures/arrow.svg"
const MAX_LIFETIME := 5.0
const MAX_DISTANCE_SQUARED := 500.0 * 500.0

var speed: float = 200.0
var damage: float = 5.0
var target: Node2D = null
var target_pos: Vector2 = Vector2.ZERO
var shooter: Node2D = null
var shooter_grid_pos: Vector2i = Vector2i(-1, -1)
var _start_pos: Vector2 = Vector2.ZERO
var _lifetime: float = 0.0
var _has_hit: bool = false

var _sprite: Sprite2D

func _ready():
	_sprite = Sprite2D.new()
	var tex = ResourceLoader.load(ARROW_TEXTURE_PATH, "Texture2D")
	if tex:
		_sprite.texture = tex
	_sprite.z_index = 5
	add_child(_sprite)

func init(from_pos: Vector2, to_target: Node2D, dmg: float):
	position = from_pos
	_start_pos = from_pos
	target = to_target
	damage = dmg
	if target and is_instance_valid(target):
		target_pos = target.position

func _process(delta):
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		_hit_target()
		return
	
	if not target or not is_instance_valid(target):
		if position.distance_squared_to(_start_pos) > MAX_DISTANCE_SQUARED:
			_hit_target()
			return
	
	if target and is_instance_valid(target):
		target_pos = target.position
	
	var offset = target_pos - position
	var dist = offset.length()
	
	if dist < 10.0:
		_hit_target()
		return
	
	var dir = offset.normalized()
	rotation = dir.angle()
	position += dir * speed * delta

func _hit_target():
	if _has_hit:
		return
	_has_hit = true
	
	if target and is_instance_valid(target):
		if target.has_method("take_damage"):
			target.take_damage(damage, shooter)
		if shooter_grid_pos.x >= 0 and target.has_method("notify_tower_attack"):
			target.notify_tower_attack(shooter_grid_pos)
	
	_hit_effect()
	queue_free()

func _hit_effect():
	var spark = Sprite2D.new()
	spark.texture = _sprite.texture
	spark.position = position
	spark.scale = Vector2(0.5, 0.5)
	spark.modulate = Color(1, 0.8, 0.2, 0.8)
	spark.z_index = 5
	get_parent().add_child(spark)
	
	var tween = spark.create_tween()
	tween.tween_property(spark, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(spark.queue_free)
