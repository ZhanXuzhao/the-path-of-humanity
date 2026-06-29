# 相机控制器 - Camera Controller
# WASD移动，滚轮缩放
extends Camera2D

var drag_start: Vector2
var is_dragging: bool = false
var zoom_level: float = 2.0
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 5.0

# 从 GameManager.settings 读取滚动参数
var _scroll_speed: float = 300.0
var _edge_scroll_margin: int = 20

# 镜头聚焦动画
var _focus_tween: Tween = null

func _ready():
	# 从 GameManager 读取配置的滚动参数
	if GameManager.settings.has("scroll_speed"):
		_scroll_speed = GameManager.settings.scroll_speed
	if GameManager.settings.has("edge_scroll_margin"):
		_edge_scroll_margin = GameManager.settings.edge_scroll_margin
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
		position += move.normalized() * _scroll_speed * delta * (1.0 / zoom_level)
	
	# 屏幕边缘滚动
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	
	if mouse_pos.x < _edge_scroll_margin:
		position.x -= _scroll_speed * delta * (1.0 / zoom_level)
	elif mouse_pos.x > viewport_size.x - _edge_scroll_margin:
		position.x += _scroll_speed * delta * (1.0 / zoom_level)
	
	if mouse_pos.y < _edge_scroll_margin:
		position.y -= _scroll_speed * delta * (1.0 / zoom_level)
	elif mouse_pos.y > viewport_size.y - _edge_scroll_margin:
		position.y += _scroll_speed * delta * (1.0 / zoom_level)

# -------- 镜头聚焦 --------
func focus_on(target_pos: Vector2, duration: float = 0.3):
	"""平滑移动镜头到目标位置，居中聚焦"""
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.set_trans(Tween.TRANS_CUBIC)
	_focus_tween.tween_property(self, "position", target_pos, duration)
