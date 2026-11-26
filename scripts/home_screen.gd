class_name HomeScreen
extends CanvasLayer
## ===========================================================================
## 首界面：标题 + 主角亮相 + 最高分 + 开始游戏
## 布局全部按视口比例算，竖屏 / 长屏 / 平板都不会错位。
## ===========================================================================

signal start_pressed
signal music_pressed

const TITLE_TEXT: String = "暴龙躲避"

var _root: Control
var _scrim: ColorRect
var _title: Label
var _divider: ColorRect
var _subtitle: Label
var _best: Label
var _hint: Label
var _start_button: Button
var _music_button: Button
var _footer: Label
var _pulse_tween: Tween = null


func _ready() -> void:
	layer = 20
	# 即使游戏被暂停（get_tree().paused），首屏也要能响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------
func show_screen(best_score: int) -> void:
	_best.text = "最高分   %d" % best_score
	visible = true
	_root.modulate.a = 0.0
	var tween: Tween = _root.create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.25)
	_start_pulse()


## 同步音乐开关的文字
func set_music_state(on: bool) -> void:
	if _music_button == null:
		return
	_music_button.text = "音乐  开" if on else "音乐  关"


func hide_screen() -> void:
	visible = false
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_start_button.scale = Vector2.ONE


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.02, 0.03, 0.06, 0.55)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_scrim)

	_title = UIKit.make_label(TITLE_TEXT, 128, UIKit.C_CREAM)
	UIKit.add_outline(_title, Color(0.06, 0.04, 0.02, 0.95), 20)
	UIKit.add_shadow(_title, Color(0.85, 0.58, 0.0, 0.45), 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_title)

	_divider = UIKit.divider(240.0)
	_root.add_child(_divider)

	_subtitle = UIKit.make_label("躲开满屏的便便，活得越久分越高", 34, UIKit.C_MUTED)
	UIKit.add_outline(_subtitle, Color(0.0, 0.0, 0.0, 0.55), 8)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_subtitle)

	_best = UIKit.make_label("最高分   0", 34, UIKit.C_GOLD)
	UIKit.add_outline(_best, Color(0.0, 0.0, 0.0, 0.6), 8)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_best)

	_hint = UIKit.make_label("手指在屏幕任意位置按住并拖动即可移动", 26, UIKit.C_MUTED)
	UIKit.add_outline(_hint, Color(0.0, 0.0, 0.0, 0.6), 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_hint)

	_start_button = UIKit.make_button("开 始 游 戏", true, 46)
	_start_button.pressed.connect(_on_start_pressed)
	_root.add_child(_start_button)

	# 右上角音乐开关
	_music_button = UIKit.make_compact_button("音乐  开", 24)
	_music_button.name = "MusicButton"
	_music_button.pressed.connect(_on_music_pressed)
	_root.add_child(_music_button)

	_footer = UIKit.make_label("v1.0   ·   Godot 4.7   ·   手机 / 网页通用", 22, UIKit.C_MUTED)
	_footer.modulate.a = 0.75
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_footer)


# ---------------------------------------------------------------------------
# 布局（按视口比例，任何宽高比都不会错位）
# ---------------------------------------------------------------------------
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = vp.x
	var h: float = vp.y

	# 按控件实际最小高度依次往下排，避免写死像素导致叠在一起
	var y: float = h * 0.075

	var title_h: float = _title.get_combined_minimum_size().y
	_title.position = Vector2(0.0, y)
	_title.size = Vector2(w, title_h)
	y += title_h + 6.0

	_divider.position = Vector2(w * 0.5 - 120.0, y)
	_divider.size = Vector2(240.0, 3.0)
	y += 26.0

	var subtitle_h: float = _subtitle.get_combined_minimum_size().y
	_subtitle.position = Vector2(0.0, y)
	_subtitle.size = Vector2(w, subtitle_h)
	y += subtitle_h + 10.0

	var best_h: float = _best.get_combined_minimum_size().y
	_best.position = Vector2(0.0, y)
	_best.size = Vector2(w, best_h)

	var button_w: float = minf(w - 120.0, 520.0)
	var button_h: float = 124.0
	_hint.position = Vector2(0.0, h * 0.70)
	_hint.size = Vector2(w, 44.0)

	_start_button.size = Vector2(button_w, button_h)
	_start_button.position = Vector2((w - button_w) * 0.5, h * 0.745)
	_start_button.pivot_offset = _start_button.size * 0.5

	_footer.position = Vector2(0.0, h - 64.0)
	_footer.size = Vector2(w, 36.0)

	_music_button.size = _music_button.get_combined_minimum_size()
	_music_button.position = Vector2(w - 24.0 - _music_button.size.x, 20.0)


func _start_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_start_button.scale = Vector2.ONE
	_pulse_tween = UIKit.pulse(_start_button, 1.035, 1.1)


func _on_start_pressed() -> void:
	start_pressed.emit()


func _on_music_pressed() -> void:
	music_pressed.emit()
