# 字体说明

`NotoSansSC-Regular.otf` —— **Noto Sans SC（思源黑体简体中文）** Regular 字重。

- 来源：Google / Adobe 的 Noto 字体项目，取自本机 `C:\Windows\Fonts\Noto Sans SC (TrueType).otf`
- 授权：**SIL Open Font License 1.1（OFL-1.1）**，可随游戏一起分发、可商用，保留本说明即可
- 体积：8.09 MB

## 为什么游戏里必须自带字体

Godot 内置的默认字体只覆盖拉丁 / 西里尔等字符集，**不含汉字**。不打包字体的话，
界面上所有中文都会显示成方框或空白。

## 网页端的体积问题（重要）

8 MB 字体会显著拖慢网页版首屏。正式发布前建议做**子集化**（只保留 UI 实际用到的字）：

```bash
pip install fonttools brotli
pyftsubset NotoSansSC-Regular.otf \
  --text-file=ui_chars.txt \
  --output-file=NotoSansSC-subset.otf \
  --layout-features=* --glyph-names --symbol-cmap --legacy-cmap \
  --notdef-glyph --notdef-outline --recommended-glyphs
```

`ui_chars.txt` 里放你要用到的全部汉字（可以从 `scripts/*.gd` 里把所有中文字符抽出来），
通常 100~300 个字就能压到 **100~300 KB**。然后把 `project.godot` 的
`gui/theme/custom_font` 和 `scripts/ui_kit.gd` 的 `FONT_PATH` 改成新文件名即可。

## 换字体

任何支持中文的 `.ttf/.otf/.woff2` 都行（比如「思源黑体」「阿里巴巴普惠体」「霞鹜文楷」），
要求是**简体中文字形齐全**。换完后把这两个地方指向新文件：

1. `project.godot` → `[gui] theme/custom_font`
2. `scripts/ui_kit.gd` → `FONT_PATH`
