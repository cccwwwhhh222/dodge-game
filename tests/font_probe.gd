extends Node
## 临时探针：比较 variation_embolden（合成加粗）几档强度的观感。

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var base: FontFile = load("res://assets/fonts/NotoSansSC-Subset.ttf")

	var rows: Array = [["0.0", 0.0], ["0.4", 0.4], ["0.8", 0.8], ["1.2", 1.2], ["1.8", 1.8]]
	var y: float = 20.0
	for item in rows:
		var fv: FontVariation = FontVariation.new()
		fv.base_font = base
		fv.variation_embolden = item[1]
		var label: Label = Label.new()
		label.text = "embolden %s  暴龙躲避 分数 429" % item[0]
		label.add_theme_font_override("font", fv)
		label.add_theme_font_size_override("font_size", 44)
		label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.89))
		label.position = Vector2(24, y)
		add_child(label)
		y += 70.0

	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_font_probe.png")
	print("probe saved")
	get_tree().quit()
