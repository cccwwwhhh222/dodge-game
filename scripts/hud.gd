class_name DodgeHUD
extends CanvasLayer
## ===========================================================================
## 游戏内界面：
##   · 左上角分数胶囊 / 右上角最高分 + 暂停键
##   · 暂停面板（继续 / 重新开始 / 返回首界面）
##   · 结算面板（本局分数 / 存活时间 / 最高分 / 新纪录 / 再来一局 / 返回首界面）
## 全部代码搭 UI，样式统一从 UIKit 取。
## ===========================================================================

signal pause_pressed
signal resume_pressed
signal restart_pressed
signal home_pressed
signal music_pressed

var _root: Control
var _game_ui: Control
var _score_pill: PanelContainer
var _score_label: Label
var _best_pill: PanelContainer
var _best_label: Label
var _pause_button: Button

var _overlay: ColorRect

var _pause_center: CenterContainer
var _pause_panel: PanelContainer
var _music_button: Button

var _over_center: CenterContainer
var _over_panel: PanelContainer
var _over_score: Label
var _over_time: Label
var _over_best: Label
var _over_record: Label


func _ready() -> void:
	# 暂停时整棵树会被 get_tree().paused 停下，HUD 必须继续处理输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide_all()


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------
func set_score(value: int) -> void:
	_score_label.text = str(value)


func set_best(value: int) -> void:
	_best_label.text = "最高  %d" % value
	# 文字变长后胶囊要重新量一次尺寸，否则会溢出到暂停键上
	_layout()


func set_music_state(on: bool) -> void:
	if _music_button == null:
		return
	_music_button.text = "音乐：开" if on else "音乐：关"


func show_game_hud() -> void:
	_game_ui.visible = true
	_pause_button.visible = true
	_hide_center(_pause_center)
	_hide_center(_over_center)
	_overlay.visible = false


func hide_all() -> void:
	_game_ui.visible = false
	_overlay.visible = false
	_hide_center(_pause_center)
	_hide_center(_over_center)


func show_pause_menu() -> void:
	_game_ui.visible = true
	_pause_button.visible = false
	_hide_center(_over_center)
	_overlay.visible = true
	_show_center(_pause_center)


func show_game_over(score: int, best: int, is_record: bool, survived: float) -> void:
	_game_ui.visible = true
	_pause_button.visible = false
	_hide_center(_pause_center)
	_overlay.visible = true

	_over_score.text = str(score)
	_over_time.text = "存活时间    %0.1f 秒" % survived
	_over_best.text = "最高分      %d" % best
	_over_record.visible = is_record
	_show_center(_over_center)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 暗罩最先加：只压暗游戏世界和背景，不压暗分数/面板
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color(0.02, 0.03, 0.06, 0.62)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)

	_build_game_ui()
	_build_pause_menu()
	_build_game_over()


func _build_game_ui() -> void:
	_game_ui = Control.new()
	_game_ui.name = "GameUI"
	_game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_game_ui)

	# 分数胶囊
	_score_pill = PanelContainer.new()
	_score_pill.name = "ScorePill"
	_score_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_pill.add_theme_stylebox_override("panel", UIKit.pill_style())
	_score_pill.custom_minimum_size = Vector2(206.0, 0.0)
	_game_ui.add_child(_score_pill)

	var score_box: VBoxContainer = VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	_score_pill.add_child(score_box)

	var score_caption: Label = UIKit.make_label("分数", 22, UIKit.C_MUTED)
	score_box.add_child(score_caption)

	_score_label = UIKit.make_label("0", 54, UIKit.C_CREAM)
	UIKit.add_shadow(_score_label, Color(0.0, 0.0, 0.0, 0.55), 3)
	score_box.add_child(_score_label)

	# 最高分（也做成胶囊，否则压在草地/树上根本看不清）
	_best_pill = PanelContainer.new()
	_best_pill.name = "BestPill"
	_best_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_pill.add_theme_stylebox_override("panel", UIKit.pill_style())
	_game_ui.add_child(_best_pill)

	_best_label = UIKit.make_label("最高  0", 26, UIKit.C_MUTED)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_best_pill.add_child(_best_label)

	# 暂停键
	_pause_button = UIKit.make_compact_button("暂停", 28)
	_pause_button.name = "PauseButton"
	_pause_button.pressed.connect(_on_pause_pressed)
	_game_ui.add_child(_pause_button)


func _build_pause_menu() -> void:
	_pause_center = CenterContainer.new()
	_pause_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_pause_center)

	_pause_panel = PanelContainer.new()
	_pause_panel.add_theme_stylebox_override("panel", UIKit.panel_style())
	_pause_panel.custom_minimum_size = Vector2(560.0, 0.0)
	_pause_center.add_child(_pause_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	_pause_panel.add_child(box)

	var title: Label = UIKit.make_label("暂停中", 64, UIKit.C_CREAM)
	UIKit.add_outline(title, Color(0.0, 0.0, 0.0, 0.6), 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(UIKit.divider(320.0))

	var resume: Button = UIKit.make_button("继续游戏", true, 40)
	resume.pressed.connect(_on_resume_pressed)
	box.add_child(resume)

	var restart: Button = UIKit.make_button("重新开始", false, 36)
	restart.custom_minimum_size = Vector2(0.0, 96.0)
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

	_music_button = UIKit.make_button("音乐：开", false, 34)
	_music_button.custom_minimum_size = Vector2(0.0, 88.0)
	_music_button.pressed.connect(_on_music_pressed)
	box.add_child(_music_button)

	var quit: Button = UIKit.make_button("返回首界面", false, 36)
	quit.custom_minimum_size = Vector2(0.0, 96.0)
	quit.pressed.connect(_on_home_pressed)
	box.add_child(quit)


func _build_game_over() -> void:
	_over_center = CenterContainer.new()
	_over_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_over_center)

	_over_panel = PanelContainer.new()
	_over_panel.add_theme_stylebox_override("panel", UIKit.panel_style())
	_over_panel.custom_minimum_size = Vector2(560.0, 0.0)
	_over_center.add_child(_over_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_over_panel.add_child(box)

	var title: Label = UIKit.make_label("游戏结束", 64, UIKit.C_CREAM)
	UIKit.add_outline(title, Color(0.0, 0.0, 0.0, 0.6), 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_over_record = UIKit.make_label("新 纪 录 ！", 30, UIKit.C_GOLD)
	_over_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_record.visible = false
	box.add_child(_over_record)

	box.add_child(UIKit.divider(320.0))

	var caption: Label = UIKit.make_label("本局分数", 24, UIKit.C_MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)

	_over_score = UIKit.make_label("0", 112, UIKit.C_GOLD)
	UIKit.add_outline(_over_score, Color(0.05, 0.03, 0.01, 0.9), 12)
	_over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_score)

	_over_time = UIKit.make_label("", 28, UIKit.C_MUTED)
	_over_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_time)

	_over_best = UIKit.make_label("", 28, UIKit.C_MUTED)
	_over_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_best)

	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	box.add_child(gap)

	var again: Button = UIKit.make_button("再 来 一 局", true, 42)
	again.pressed.connect(_on_restart_pressed)
	box.add_child(again)

	var home: Button = UIKit.make_button("返回首界面", false, 36)
	home.custom_minimum_size = Vector2(0.0, 96.0)
	home.pressed.connect(_on_home_pressed)
	box.add_child(home)


# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = vp.x

	var pause_w: float = 132.0
	var pause_h: float = 86.0

	if _score_pill != null:
		_score_pill.size = _score_pill.get_combined_minimum_size()
		_score_pill.position = Vector2(24.0, 18.0)

	if _pause_button != null:
		_pause_button.size = Vector2(pause_w, pause_h)
		_pause_button.position = Vector2(w - 24.0 - pause_w, 18.0)

	if _best_pill != null:
		_best_pill.size = _best_pill.get_combined_minimum_size()
		var best_size: Vector2 = _best_pill.size
		_best_pill.position = Vector2(
			w - 24.0 - pause_w - 12.0 - best_size.x,
			18.0 + (pause_h - best_size.y) * 0.5
		)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _show_center(center: CenterContainer) -> void:
	center.visible = true
	var panel: CanvasItem = center.get_child(0) as CanvasItem
	if panel != null:
		UIKit.fade_in(panel, 0.18)


func _hide_center(center: CenterContainer) -> void:
	center.visible = false


func _on_pause_pressed() -> void:
	pause_pressed.emit()


func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_restart_pressed() -> void:
	restart_pressed.emit()


func _on_home_pressed() -> void:
	home_pressed.emit()


func _on_music_pressed() -> void:
	music_pressed.emit()
