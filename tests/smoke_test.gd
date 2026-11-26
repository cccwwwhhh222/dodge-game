extends Node
## ===========================================================================
## 无头冒烟测试（不需要窗口，不需要显卡）：
##   godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
##
## 覆盖：首界面 → 开始 → 触摸摇杆 → 暂停 → 继续 → 计分 → 撞死 → 结算 → 重开 → 返回首页
## 任何一步不符合预期都会打印 FAIL 并以退出码 1 结束（方便 CI 用）。
## ===========================================================================

var _main: Node
var _fail: int = 0
var _frame: int = 0
var _checks: int = 0


func _ready() -> void:
	# 测试节点必须永不暂停，否则「暂停」那几步之后测试自己就停了
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("=== smoke test start ===")

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("FAIL: 无法加载 res://scenes/main.tscn")
		_quit(1)
		return
	_main = packed.instantiate()
	add_child(_main)

	_assert(get_node_or_null("/root/Game") != null, "Autoload Game 已加载")
	_assert(_main.get_node_or_null("Playfield/Player") != null, "Player 节点存在")
	_assert(_main.get_node_or_null("Playfield/Enemies") != null, "Enemies 容器存在")
	_assert(_main.get_node_or_null("HUD") != null, "HUD 节点存在")
	_assert(_main.get_node_or_null("Home") != null, "首界面节点存在")
	_assert(_main.get_node_or_null("Bgm") != null, "背景音乐节点存在")
	_assert(_main.state == 0, "初始状态 = HOME(0)")


func _process(_delta: float) -> void:
	_frame += 1

	if _frame == 3:
		var home: Node = _main.get_node("Home")
		var hud0: Node = _main.get_node("HUD")
		_assert(home.visible, "首界面可见")
		_assert(not hud0._game_ui.visible, "首界面时游戏内 HUD 隐藏")
		_assert(_main.get_node("Playfield/Player")._home_mode, "首界面时玩家处于看板姿态")
		_assert(home._title.text == "暴龙躲避", "标题文字是中文「暴龙躲避」")
		_assert(home._start_button.text == "开 始 游 戏", "开始按钮文字正确")
		_assert(home._music_button.text == "音乐  开", "音乐开关初始为「开」")

	if _frame == 4:
		var bgm: AudioStreamPlayer = _main.get_node("Bgm")
		_assert(bgm.stream != null, "背景音乐文件已加载（bgm.ogg）")
		if bgm.stream != null:
			print("  .. bgm 时长 = ", bgm.stream.get_length(), " 秒")
			_assert(bgm.stream.get_length() > 30.0, "bgm 时长 > 30 秒（不是空文件）")
			_assert(bgm.stream.get("loop") == true, "bgm 已开启循环")
		_assert(bgm.playing, "首界面时 bgm 正在播放")

	if _frame == 5:
		# 音乐开关：关掉后音量应压到近似静音，再打开恢复
		_main.get_node("Home").music_pressed.emit()

	if _frame == 6:
		_assert(not Game.music_on, "点音乐开关后 Game.music_on = false")
		_assert(_main.get_node("Bgm").volume_db <= -60.0, "关音乐后音量降到近似静音")
		_main.get_node("Home").music_pressed.emit()

	if _frame == 7:
		_assert(Game.music_on, "再点一次恢复音乐开关")
		_assert(_main.get_node("Bgm").volume_db > -20.0, "恢复后音量回到正常")
		_main.get_node("Home").start_pressed.emit()

	if _frame == 9:
		var hud: Node = _main.get_node("HUD")
		_assert(_main.state == 1, "开始后状态 = PLAYING(1)")
		_assert(not _main.get_node("Home").visible, "开始后首界面隐藏")
		_assert(hud._game_ui.visible, "游戏内 HUD 显示")
		_assert(_main.get_node("TouchLayer/Joystick").enabled, "PLAYING 时摇杆启用")
		_assert(not _main.get_node("Playfield/Player")._home_mode, "进入游戏后不再是看板姿态")

	if _frame == 10:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = true
		touch.position = Vector2(300.0, 700.0)
		Input.parse_input_event(touch)
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(420.0, 700.0)
		Input.parse_input_event(drag)

	if _frame == 13:
		var mv: Vector2 = _main.get_node("Playfield/Player").move_input
		print("  .. 摇杆输出 = ", mv)
		_assert(mv.x > 0.5, "触摸拖动 → 输出向右的 move_input")
		var release: InputEventScreenTouch = InputEventScreenTouch.new()
		release.index = 0
		release.pressed = false
		release.position = Vector2(420.0, 700.0)
		Input.parse_input_event(release)

	if _frame == 16:
		_assert(_main.get_node("Playfield/Player").move_input.length() < 0.01, "松手后 move_input 归零")

	if _frame == 20:
		_main.get_node("HUD").pause_pressed.emit()

	if _frame == 22:
		var hud: Node = _main.get_node("HUD")
		_assert(_main.state == 2, "暂停后状态 = PAUSED(2)")
		_assert(get_tree().paused, "整棵树已暂停（敌人/计分停住）")
		_assert(hud._pause_center.visible, "暂停面板显示")
		_assert(not _main.get_node("TouchLayer/Joystick").enabled, "暂停时摇杆禁用")
		hud.resume_pressed.emit()

	if _frame == 25:
		_assert(_main.state == 1, "继续后状态 = PLAYING(1)")
		_assert(not get_tree().paused, "继续后取消暂停")
		_assert(not _main.get_node("HUD")._pause_center.visible, "暂停面板隐藏")

	if _frame == 150:
		var count: int = _main.get_node("Playfield/Enemies").get_child_count()
		print("  .. 2.5s：敌人 = ", count, "，分数 = ", Game.score, "，elapsed = ", _main.elapsed)
		_assert(count >= 1, "至少刷出 1 个敌人")
		_assert(Game.score > 0, "分数在增长")

	if _frame == 152:
		_main._on_player_hit()

	if _frame == 155:
		var hud: Node = _main.get_node("HUD")
		_assert(_main.state == 3, "死亡后状态 = GAME_OVER(3)")
		_assert(hud._over_center.visible, "结算面板显示")
		_assert(hud._over_score.text == str(Game.score), "结算分数与 Game.score 一致")
		_assert(not hud._pause_button.visible, "结算时暂停键隐藏")
		_assert(not _main.get_node("TouchLayer/Joystick").enabled, "死亡后摇杆禁用")

	if _frame == 157:
		_main.get_node("HUD").restart_pressed.emit()

	if _frame == 160:
		_assert(_main.state == 1, "「再来一局」后状态 = PLAYING(1)")
		_assert(_main.get_node("Playfield/Enemies").get_child_count() == 0, "重开时清空了敌人")
		_assert(Game.score == 0, "重开时分数归零")
		_main.get_node("Playfield/Player").position = Vector2(-900.0, -900.0)

	if _frame == 163:
		var p: Node2D = _main.get_node("Playfield/Player")
		print("  .. 玩家被夹回的位置 = ", p.position)
		_assert(p.position.x >= 0.0 and p.position.y >= 0.0, "玩家不会跑出屏幕")

	if _frame == 166:
		_main.get_node("HUD").home_pressed.emit()

	if _frame == 169:
		_assert(_main.state == 0, "「返回首界面」后状态 = HOME(0)")
		_assert(_main.get_node("Home").visible, "返回后首界面重新显示")
		_assert(not _main.get_node("HUD")._game_ui.visible, "返回后游戏内 HUD 隐藏")

	if _frame == 172:
		print("=== smoke test end: ", _checks, " checks, ", _fail, " failed ===")
		_quit(1 if _fail > 0 else 0)


func _assert(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("OK  : ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _quit(code: int) -> void:
	set_process(false)
	get_tree().quit(code)
