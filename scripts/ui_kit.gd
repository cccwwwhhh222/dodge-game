class_name UIKit
extends RefCounted
## ===========================================================================
## UI 工具箱：配色、字体、按钮/面板工厂、入场动画
## 所有界面（首屏 / 游戏内 HUD / 暂停 / 结算）都从这里取样式，保证风格统一。
## 字体用 Noto Sans SC（SIL OFL 1.1，可随游戏分发），已在 project.godot 里设为全局默认字体。
## ===========================================================================

const FONT_PATH: String = "res://assets/fonts/ui_font.tres"

## 深夜蓝黑（面板底）
const C_INK: Color = Color(0.063, 0.082, 0.129)
const C_PANEL: Color = Color(0.105, 0.133, 0.196, 0.96)
const C_PANEL_SOFT: Color = Color(0.137, 0.172, 0.247, 0.94)
## 主色：龙鳞金
const C_GOLD: Color = Color(1.0, 0.718, 0.012)
const C_GOLD_LIGHT: Color = Color(1.0, 0.788, 0.235)
const C_GOLD_DARK: Color = Color(0.851, 0.58, 0.0)
## 文字
const C_CREAM: Color = Color(0.992, 0.965, 0.89)
const C_MUTED: Color = Color(0.604, 0.655, 0.741)
const C_DANGER: Color = Color(1.0, 0.42, 0.42)
const C_MINT: Color = Color(0.302, 0.831, 0.675)


# ---------------------------------------------------------------------------
# 基础控件
# ---------------------------------------------------------------------------
static func make_label(text: String, size: int, color: Color = C_CREAM) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func add_outline(label: Label, color: Color = Color(0.05, 0.03, 0.02, 0.9), size: int = 14) -> void:
	label.add_theme_color_override("font_outline_color", color)
	label.add_theme_constant_override("outline_size", size)


static func add_shadow(label: Label, color: Color = Color(0.0, 0.0, 0.0, 0.5), offset: int = 4) -> void:
	label.add_theme_color_override("font_shadow_color", color)
	label.add_theme_constant_override("shadow_offset_x", offset)
	label.add_theme_constant_override("shadow_offset_y", offset)


# ---------------------------------------------------------------------------
# 面板 / 按钮
# ---------------------------------------------------------------------------
static func panel_style(bg: Color = C_PANEL, radius: int = 36, border: Color = C_GOLD, border_alpha: float = 0.55, border_width: int = 3) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width)
	var bc: Color = border
	bc.a = border_alpha
	sb.border_color = bc
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 26
	sb.content_margin_left = 48.0
	sb.content_margin_right = 48.0
	sb.content_margin_top = 44.0
	sb.content_margin_bottom = 44.0
	return sb


static func pill_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.055, 0.09, 0.62)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.718, 0.012, 0.35)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 18.0
	return sb


## primary = 金色主按钮（开始游戏 / 继续 / 再来一局）
static func make_button(text: String, primary: bool = true, font_size: int = 40) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size = Vector2(0.0, 112.0)
	button.add_theme_stylebox_override("normal", _button_style(primary, 0))
	button.add_theme_stylebox_override("hover", _button_style(primary, 1))
	button.add_theme_stylebox_override("pressed", _button_style(primary, 2))
	button.add_theme_stylebox_override("focus", _button_style(primary, 0))
	if primary:
		button.add_theme_color_override("font_color", Color(0.09, 0.07, 0.03))
		button.add_theme_color_override("font_hover_color", Color(0.09, 0.07, 0.03))
		button.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.02))
	else:
		button.add_theme_color_override("font_color", C_CREAM)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", C_MUTED)
	return button


## 小尺寸按钮（暂停键这种，不需要大内边距）
static func make_compact_button(text: String, font_size: int = 26) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _compact_style(0))
	button.add_theme_stylebox_override("hover", _compact_style(1))
	button.add_theme_stylebox_override("pressed", _compact_style(2))
	button.add_theme_stylebox_override("focus", _compact_style(0))
	button.add_theme_color_override("font_color", C_CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", C_MUTED)
	return button


static func _compact_style(state: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_corner_radius_all(22)
	match state:
		1:
			sb.bg_color = Color(0.20, 0.25, 0.34, 0.95)
		2:
			sb.bg_color = Color(0.09, 0.12, 0.17, 0.95)
		_:
			sb.bg_color = Color(0.07, 0.09, 0.14, 0.72)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.56, 0.63, 0.73, 0.40)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func _button_style(primary: bool, state: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_corner_radius_all(26)
	if primary:
		match state:
			1:
				sb.bg_color = C_GOLD_LIGHT
			2:
				sb.bg_color = C_GOLD_DARK
			_:
				sb.bg_color = C_GOLD
		sb.shadow_color = Color(0.85, 0.58, 0.0, 0.35)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0.0, 6.0)
	else:
		match state:
			1:
				sb.bg_color = Color(0.19, 0.235, 0.325, 0.96)
			2:
				sb.bg_color = Color(0.10, 0.13, 0.19, 0.96)
			_:
				sb.bg_color = C_PANEL_SOFT
		sb.set_border_width_all(2)
		sb.border_color = Color(0.56, 0.63, 0.73, 0.35)
	sb.content_margin_left = 32.0
	sb.content_margin_right = 32.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	return sb


# ---------------------------------------------------------------------------
# 动效
# ---------------------------------------------------------------------------
## 淡入（用于容器里的面板：不能改 position，否则会打架）
static func fade_in(item: CanvasItem, duration: float = 0.2) -> void:
	item.modulate.a = 0.0
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE)


## 呼吸缩放（用于「开始游戏」这类主按钮）
static func pulse(button: Control, amount: float = 1.035, half_period: float = 1.1) -> Tween:
	button.pivot_offset = button.size * 0.5
	var tween: Tween = button.create_tween()
	tween.set_loops()
	tween.tween_property(button, "scale", Vector2.ONE * amount, half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


## 上下浮动（用于首屏标题 / 主角）
static func bob(item: Node2D, amplitude: float = 8.0, half_period: float = 1.4) -> Tween:
	var base: Vector2 = item.position
	var tween: Tween = item.create_tween()
	tween.set_loops()
	tween.tween_property(item, "position", base + Vector2(0.0, -amplitude), half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(item, "position", base, half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


## 细分割线
static func divider(width: float, color: Color = C_GOLD) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.color.a = 0.8
	rect.custom_minimum_size = Vector2(width, 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
