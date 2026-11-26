@tool
class_name CircleVisual
extends Node2D
## 用 _draw() 画一个圆（可选描边），避免示例工程依赖美术资源。
## 现在主要用于：玩家脚下的光圈、敌人身后的红色提示环、玩家的椭圆投影。
## 换成自己的贴图时，直接把这个节点换成 Sprite2D 即可。

@export var radius: float = 18.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color(1, 1, 1):
	set(value):
		color = value
		queue_redraw()

@export var outline_width: float = 0.0:
	set(value):
		outline_width = value
		queue_redraw()

@export var outline_color: Color = Color(1, 1, 1, 0.5):
	set(value):
		outline_color = value
		queue_redraw()


func _draw() -> void:
	if color.a > 0.0:
		draw_circle(Vector2.ZERO, radius, color)
	if outline_width > 0.0:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, outline_color, outline_width, true)
