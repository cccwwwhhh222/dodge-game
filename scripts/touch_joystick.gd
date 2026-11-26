class_name TouchJoystick
extends Control
## ===========================================================================
## 手机端「浮动摇杆」：手指按在屏幕任意位置即为摇杆原点，拖动即为方向。
## 相比固定摇杆，单手操作更舒服，也不会挡住画面。
##
## 关键点：
##  * 在 _input() 里收事件（不用 _gui_input，避免 UI 层级干扰）
##  * 用 make_input_local() 把事件坐标换算到本控件坐标系，
##    stretch / 高 DPI / 刘海屏下都不会偏
##  * 忽略「触摸模拟出来的鼠标事件」，否则一次触摸会被处理两遍
## ===========================================================================

signal input_changed(dir: Vector2)

## 摇杆底盘半径（到边缘即为满速）
@export var base_radius: float = 110.0
## 摇杆头半径
@export var knob_radius: float = 46.0
## 死区：手指几乎没动时输出 0，防止人物自己飘
@export var dead_zone: float = 10.0

var enabled: bool = false

var _touch_index: int = -1
var _active: bool = false
var _mouse_down: bool = false
var _origin: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 本控件只负责收输入和画摇杆，不能挡住 HUD 上的按钮点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		reset()


func reset() -> void:
	_touch_index = -1
	_active = false
	_mouse_down = false
	if _dir != Vector2.ZERO:
		_dir = Vector2.ZERO
		input_changed.emit(_dir)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	# 把屏幕坐标换算成本控件坐标：stretch / 高 DPI / 刘海屏都不会偏
	_handle(make_input_local(event))


func _handle(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			if not enabled or _active:
				return
			_touch_index = touch.index
			_begin(touch.position)
		elif touch.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_index and _active:
			_move_to(drag.position)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if _touch_index != -1:
			return  # 这是触摸模拟出来的鼠标事件，丢掉
		if button.pressed:
			if not enabled or _active:
				return
			_mouse_down = true
			_begin(button.position)
		elif _mouse_down:
			_end()
	elif event is InputEventMouseMotion and _mouse_down and _active:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_move_to(motion.position)


func _begin(pos: Vector2) -> void:
	_active = true
	_origin = pos
	_knob_pos = pos
	_dir = Vector2.ZERO
	input_changed.emit(_dir)
	queue_redraw()


func _move_to(pos: Vector2) -> void:
	var offset: Vector2 = pos - _origin
	if offset.length() > base_radius:
		# 手指拖出底盘：整个摇杆跟着走，保证始终有方向输出
		_origin = pos - offset.normalized() * base_radius
		offset = pos - _origin

	_knob_pos = _origin + offset

	if offset.length() < dead_zone:
		_dir = Vector2.ZERO
	else:
		var strength: float = clampf(offset.length() / base_radius, 0.0, 1.0)
		_dir = offset.normalized() * strength

	input_changed.emit(_dir)
	queue_redraw()


func _end() -> void:
	_active = false
	_touch_index = -1
	_mouse_down = false
	_dir = Vector2.ZERO
	input_changed.emit(_dir)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_origin, base_radius, Color(1, 1, 1, 0.06))
	draw_arc(_origin, base_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 3.0, true)
	draw_circle(_knob_pos, knob_radius, Color(0.45, 0.85, 1.0, 0.22))
	draw_arc(_knob_pos, knob_radius, 0.0, TAU, 48, Color(0.55, 0.9, 1.0, 0.55), 3.0, true)
