"""生成 TapTap 商店素材：1:1 图标（1024）和 16:9 封面图（1280x720）。

素材来源就是游戏里的农场背景 + 小龙，不用另外找图。
用法：python tools/make_store_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
LITE = ROOT / "web-lite" / "assets"
OUT = ROOT / "dist" / "store"
OUT.mkdir(parents=True, exist_ok=True)


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    """等比铺满并居中裁切"""
    s = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    left = (img.width - w) // 2
    top = (img.height - h) // 2
    return img.crop((left, top, left + w, top + h))


def vignette(size, strength=110):
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.25, -h * 0.35, w * 1.25, h * 1.35), fill=strength)
    return mask.filter(ImageFilter.GaussianBlur(min(w, h) // 8))


bg = Image.open(ROOT / "assets" / "bg_farm.png").convert("RGB")
dragon = Image.open(LITE / "dragon.png").convert("RGBA")

# ---------------- 1:1 图标 1024 ----------------
S = 1024
canvas = cover(bg, S, S).convert("RGBA")
canvas = Image.alpha_composite(canvas, Image.new("RGBA", (S, S), (6, 10, 18, 120)))
dh = int(S * 0.66)
dw = round(dh * dragon.width / dragon.height)
sprite = dragon.resize((dw, dh), Image.LANCZOS)
canvas.alpha_composite(sprite, ((S - dw) // 2, int(S * 0.24)))
# 底部压暗，放名字
grad = Image.new("L", (1, S))
for y in range(S):
    grad.putpixel((0, y), int(120 * max(0, (y / S - 0.55)) / 0.45))
band = Image.new("RGBA", (S, S), (5, 8, 14, 255))
band.putalpha(grad.resize((S, S)))
canvas = Image.alpha_composite(canvas, band)
icon = canvas.convert("RGB")
icon.save(OUT / "icon-1024.png", optimize=True)

# ---------------- 16:9 封面 1280x720 ----------------
W, H = 1280, 720
canvas2 = cover(bg, W, H).convert("RGBA")
canvas2 = Image.alpha_composite(canvas2, Image.new("RGBA", (W, H), (6, 10, 18, 100)))

# 左侧压暗，给标题留位置
grad = Image.new("L", (W, 1))
for x in range(W):
    t = x / W
    grad.putpixel((x, 0), int(235 * max(0.0, 1.0 - t / 0.62)))
grad = grad.resize((W, H))
shade = Image.new("RGBA", (W, H), (5, 9, 16, 255))
shade.putalpha(grad)
canvas2 = Image.alpha_composite(canvas2, shade)

# 小龙放右边
dh2 = int(H * 0.86)
dw2 = round(dh2 * dragon.width / dragon.height)
sprite2 = dragon.resize((dw2, dh2), Image.LANCZOS)
canvas2.alpha_composite(sprite2, (int(W * 0.40), int(H * 0.10)))

# 文案
from PIL import ImageFont  # noqa: E402  （放在这里，前面不需要）

font_path = ROOT / "assets" / "fonts" / "NotoSansSC-Subset.ttf"
title_font = ImageFont.truetype(str(font_path), 128)
sub_font = ImageFont.truetype(str(font_path), 40)
tag_font = ImageFont.truetype(str(font_path), 30)

d = ImageDraw.Draw(canvas2)
d.text((78, 168), "暴龙躲避", font=title_font, fill=(253, 246, 227, 255),
       stroke_width=6, stroke_fill=(60, 38, 8, 255))
d.text((84, 330), "躲开满屏的便便，活得越久分越高", font=sub_font,
       fill=(255, 209, 102, 255), stroke_width=3, stroke_fill=(20, 14, 4, 220))
d.text((84, 400), "单指拖动 · 手机 / 网页 · 首屏 0.4 MB", font=tag_font,
       fill=(154, 167, 189, 255), stroke_width=2, stroke_fill=(10, 10, 14, 200))

canvas2.convert("RGB").save(OUT / "cover-1280x720.png", quality=92, optimize=True)

# ---------------- 便便小图标（列表用）----------------
for i, name in enumerate(["poop1", "poop2", "poop3"], start=1):
    im = Image.open(LITE / f"{name}.png").convert("RGBA").resize((256, 256), Image.LANCZOS)
    im.save(OUT / f"enemy-{i}.png", optimize=True)

for f in sorted(OUT.iterdir()):
    print(f"{f.name:<24} {f.stat().st_size / 1024:7.1f} KB")
