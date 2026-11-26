extends Node
## 自动截图：首界面 → 游戏中 → 暂停 → 结算，四张 PNG，然后退出。
## 用法（会短暂弹出一个窗口）：
##   godot --path . --fixed-fps 60 --resolution 360x640 res://tests/capture.tscn

var _main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	add_child(_main)

	await get_tree().create_timer(0.4).timeout
	await _save("home")

	_main.get_node("Home").start_pressed.emit()
	await get_tree().create_timer(2.8).timeout
	await _save("gameplay")

	_main.get_node("HUD").pause_pressed.emit()
	await get_tree().create_timer(0.35).timeout
	await _save("pause")

	_main.get_node("HUD").resume_pressed.emit()
	await get_tree().create_timer(0.2).timeout
	_main._on_player_hit()
	await get_tree().create_timer(0.45).timeout
	await _save("gameover")

	get_tree().quit()


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "res://tests/preview_%dx%d_%s.png" % [img.get_width(), img.get_height(), tag]
	img.save_png(path)
	print("saved: ", path)
