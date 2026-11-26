class_name DodgePlayer
extends CharacterBody2D
## ===========================================================================
## 玩家：八方向移动 + 屏幕边界限制
## 输入双通道：
##   1) 键盘：Input.get_vector("left","right","up","down")
##   2) 触屏：由 main.gd 把 TouchJoystick 的方向写进 move_input
## 想换成自己的美术：把 Visual/Core 两个 Node2D 换成 Sprite2D 即可，
## 碰撞体保持圆形最省事（圆形判定最宽容，适合躲避游戏）。
## ===========================================================================

## 最高移动速度（像素/秒，基于 720×1280 的设计分辨率）
@export var speed: float = 430.0
## 加速度：数值越大越「跟手」。躲避游戏建议 4000~8000，几乎无惯性。
@export var acceleration: float = 6000.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite

## 触屏摇杆写入的方向（长度 0~1）
var move_input: Vector2 = Vector2.ZERO

var _bounds: Rect2 = Rect2()
var _radius: float = 20.0
var _alive: bool = true
var _death_tween: Tween = null
## 首界面模式：站在中间当看板，放大一点、上下浮动、不接受输入
var _home_mode: bool = false
var _bob_time: float = 0.0
var _sprite_base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	add_to_group("player")
	if collision_shape.shape is CircleShape2D:
		_radius = (collision_shape.shape as CircleShape2D).radius
	_sprite_base_scale = sprite.scale


func _process(delta: float) -> void:
	if not _home_mode:
		return
	_bob_time += delta
	sprite.position.y = sin(_bob_time * 2.2) * 7.0


## 首界面 / 游戏内两种姿态
func set_home_mode(on: bool) -> void:
	_home_mode = on
	velocity = Vector2.ZERO
	move_input = Vector2.ZERO
	_bob_time = 0.0
	if on:
		sprite.scale = _sprite_base_scale * 1.18
	else:
		sprite.scale = _sprite_base_scale
		sprite.position.y = 0.0


## 由 main.gd 在视口尺寸变化时调用
func set_bounds(rect: Rect2) -> void:
	_bounds = rect


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	# 首界面里龙只负责站着（会上下浮动），不参与移动
	if _home_mode:
		return

	var dir: Vector2 = Input.get_vector("left", "right", "up", "down")
	if move_input.length_squared() > 0.01:
		dir = move_input
	dir = dir.limit_length(1.0)

	velocity = velocity.move_toward(dir * speed, acceleration * delta)
	move_and_slide()
	_clamp_position()

	# 龙默认朝右，往左走时翻转贴图（素材是侧面图，翻转即可，不需要另做一套）
	if absf(dir.x) > 0.1:
		sprite.flip_h = dir.x < 0.0


## 把角色锁在屏幕内，避免「躲到屏幕外」这种作弊
func _clamp_position() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	position.x = clampf(position.x, _bounds.position.x + _radius, _bounds.end.x - _radius)
	position.y = clampf(position.y, _bounds.position.y + _radius, _bounds.end.y - _radius)


func reset_state() -> void:
	_alive = true
	velocity = Vector2.ZERO
	move_input = Vector2.ZERO
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	# 上一局的死亡动画可能还没播完，先掐掉，否则会被它重新淡出
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null


## 死亡表现：放大 + 淡出（结束后由 main 弹出结算面板）
func die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	move_input = Vector2.ZERO
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	var scale_tween: PropertyTweener = _death_tween.tween_property(self, "scale", Vector2(1.9, 1.9), 0.22)
	scale_tween.set_trans(Tween.TRANS_QUAD)
	scale_tween.set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.22)
