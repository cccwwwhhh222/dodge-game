class_name DodgeEnemy
extends Area2D
## ===========================================================================
## 敌人：表情便便贴图 + 直线/蛇形飞行 + 出屏回收
## 用 Area2D 而不是 CharacterBody2D：只需要「碰到就算死」，不需要物理推挤。
##
## 美术：$Sprite 的贴图由 main.gd 在 setup() 时随机挑一张（3 种表情）。
## 贴图始终「正着」显示（不跟着速度旋转，否则脸会歪），只做左右翻转 + 轻微倾斜。
## $Halo 是脚下红色光晕，用来在花哨的背景（草地/土路）上把敌人「拎」出来。
## ===========================================================================

signal hit_player

@onready var sprite: Sprite2D = $Sprite
@onready var halo: CircleVisual = $Halo
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 200.0
## 0 = 直线；0.2~0.5 = 明显的蛇形走位
var wobble: float = 0.0

var _radius: float = 18.0
var _life: float = 0.0
var _phase: float = 0.0
var _hit_done: bool = false


func _ready() -> void:
	add_to_group("enemies")
	body_entered.connect(_on_body_entered)


## 注意：必须在 add_child() 之后调用，否则 @onready 变量还是 null
func setup(start: Vector2, dir: Vector2, move_speed: float, texture: Texture2D, radius: float, wobble_amount: float) -> void:
	position = start
	if dir.length_squared() > 0.0001:
		direction = dir.normalized()
	speed = move_speed
	wobble = wobble_amount
	_radius = radius
	_phase = randf() * TAU
	_apply_look(texture)


func _apply_look(texture: Texture2D) -> void:
	if texture != null:
		sprite.texture = texture
	# 视觉高度 = 3 倍判定半径：看起来比实际判定大一点，玩家会觉得「差一点就撞到」= 爽
	var target_size: float = _radius * 3.0
	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.x > 0.0:
		var s: float = target_size / tex_size.x
		sprite.scale = Vector2(s, s)

	# 红色提示环：背景是草地/土路，便便本身也是褐色，不加一层提示很容易看漏
	halo.radius = _radius * 1.55
	halo.color = Color(1.0, 0.35, 0.35, 0.10)
	halo.outline_width = 3.0
	halo.outline_color = Color(1.0, 0.35, 0.35, 0.6)

	# 判定圆略小于视觉：躲避游戏对玩家要宽容
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = _radius * 0.9
	collision_shape.shape = shape


func _physics_process(delta: float) -> void:
	_life += delta

	var move_dir: Vector2 = direction
	if wobble > 0.0:
		var perp: Vector2 = direction.orthogonal()
		move_dir = (direction + perp * sin(_life * 2.4 + _phase) * wobble).normalized()

	position += move_dir * speed * delta

	# 贴图不跟着角度转（脸会歪），只做左右翻转 + 轻微倾斜
	sprite.flip_h = move_dir.x < -0.05
	sprite.rotation = clampf(move_dir.x, -1.0, 1.0) * 0.22
	# 上下飞的时候给一点「扑腾」的错觉
	sprite.scale.y = absf(sprite.scale.x) * (1.0 - clampf(move_dir.y, 0.0, 1.0) * 0.08)

	# 光晕呼吸，让敌人看起来是「活」的
	halo.scale = Vector2.ONE * (1.0 + sin(_life * 3.4 + _phase) * 0.08)

	_cull()


## 出屏回收：视口外 260px 就删掉，防止节点越积越多导致卡顿
func _cull() -> void:
	var view: Rect2 = get_viewport_rect().grow(260.0)
	if not view.has_point(global_position):
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _hit_done:
		return
	if body.is_in_group("player"):
		_hit_done = true
		hit_player.emit()
