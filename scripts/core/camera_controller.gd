# 相机控制器 - Camera Controller
# WASD移动，滚轮缩放
extends Camera2D

var drag_start: Vector2
var is_dragging: bool = false
var zoom_level: float = 2.0
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 5.0
const EDGE_SCROLL_MARGIN: int = 20
const SCROLL_SPEED: float = 300.0

func _ready():
	# 鼠标中键拖动
	set_process_input(true)

func _input(event):
	# 鼠标中键拖动
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			drag_start = event.position
			is_dragging = true
		else:
			is_dragging = false
	
	if event is InputEventMouseMotion and is_dragging:
		var delta = event.position - drag_start
		position -= delta * (1.0 / zoom.x)
		drag_start = event.position
	
	# 滚轮缩放
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = max(MIN_ZOOM, zoom_level - 0.2)
			zoom = Vector2(zoom_level, zoom_level)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = min(MAX_ZOOM, zoom_level + 0.2)
			zoom = Vector2(zoom_level, zoom_level)

func _process(delta):
	# WASD移动
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	
	if move != Vector2.ZERO:
		position += move.normalized() * SCROLL_SPEED * delta * (1.0 / zoom_level)
	
	# 屏幕边缘滚动
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	
	if mouse_pos.x < EDGE_SCROLL_MARGIN:
		position.x -= SCROLL_SPEED * delta * (1.0 / zoom_level)
	elif mouse_pos.x > viewport_size.x - EDGE_SCROLL_MARGIN:
		position.x += SCROLL_SPEED * delta * (1.0 / zoom_level)
	
	if mouse_pos.y < EDGE_SCROLL_MARGIN:
		position.y -= SCROLL_SPEED * delta * (1.0 / zoom_level)
	elif mouse_pos.y > viewport_size.y - EDGE_SCROLL_MARGIN:
		position.y += SCROLL_SPEED * delta * (1.0 / zoom_level)
